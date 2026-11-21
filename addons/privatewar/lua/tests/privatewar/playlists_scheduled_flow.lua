-- Engine-backed integration cases; clocks/map changes are isolated, no real changelevel is run.
local path = "privatewar/pw_test_scheduled_pending.json"
local function playlists() return assert(PW.Playlist) end
local function match() return assert(PW.Match) end
local function changer() return assert(PW.MapChange) end

return {
    groupName = "PW scheduled playlist flow",
    beforeEach = function(state)
        state.previous = { playlist = PW._Playlist, match = PW._Match, change = PW._MapChange,
            settings = PW._Settings, enable = PW._Enable, mode = PW.ActiveMode, lobby = PW._Lobby }
        state.now, state.utc, state.count, state.map, state.calls = 1000, 1000, 5, "gm_a", 0
        state.mode, state.active = { ClassName = "scheduled_test" }, ""
        PW._Settings = PW.Settings._NewStore()
        PW._Enable = assert(PW.Enable)._NewStore({ registries = function() return {} end })
        PW._Match = match()._NewStore({ clock = function() return state.now end, log = function() end,
            players = function() return {} end,
            settings = function()
                return { prematch = 60, countdown = 0, postmatch = 1, vote = 15, afterMatch = "rotation" }
            end })
        PW._MapChange = changer()._NewStore({ path = path, clock = function() return state.now end,
            time = function() return state.utc end, map = function() return state.map end,
            mapChangeCount = function() return state.count end, delay = function() return 1 end,
            log = function() end, announce = function() end, changelevel = function() end,
            bots = function() return 0 end, resolveMode = function() return state.mode end })
        PW._Playlist = assert(playlists()._NewStore)({
            luaEntries = function() return { { ClassName = "event", Name = "Event",
                Modes = { scheduled_test = 1 }, Maps = { "gm_b" }, IsActive = function()
                    assert(match().GetPhase() == "LOBBY" or match().GetPhase() == "VOTE",
                        "availability predicate ran inside the running-match interval")
                    state.calls = state.calls + 1 return state.utc < 1100
                end } } end,
            facts = function() return {} end, time = function() return state.utc end,
            phase = match().GetPhase, fits = function() return true end, broadcast = function() end,
            log = function() end, getActive = function() return state.active end,
            setActive = function(id) state.active = id end,
            start = function(_, map) return match().Start(state.mode, map) end })
        stub(PW, "Notify").with(function() end)
        stub(net, "Start").with(function() end)
        stub(net, "WriteString").with(function() end)
        stub(net, "Broadcast").with(function() end)
    end,
    afterEach = function(state)
        file.Delete(path) -- only this suite's owned pending fixture
        PW._Playlist, PW._Match, PW._MapChange = state.previous.playlist, state.previous.match, state.previous.change
        PW._Settings, PW._Enable, PW.ActiveMode = state.previous.settings, state.previous.enable, state.previous.mode
        PW._Lobby = state.previous.lobby
    end,
    cases = {
        {
            name = "Expired accepted start continues once with zero restored PREMATCH predicate calls",
            func = function(state)
                expect(assert(playlists().SetActive)("event")).to.beTrue()
                state.utc = 1100
                expect(assert(playlists().Start)("event")).to.beTrue()
                state.now = 1001 changer()._Tick()
                local text = assert(file.Read(path, "DATA"))
                expect(assert(changer()._Decode(text)).playlist).to.equal("event")
                local calls = state.calls --[[@as number]]
                state.map, state.count = "gm_b", 6
                PW._MapChange.changing = nil
                expect(changer()._Apply()).to.beTrue()
                expect(match().GetPhase()).to.equal("PREMATCH")
                playlists()._Poll()
                expect(state.calls).to.equal(calls)
                expect(changer()._Apply()).to.beFalse()
                expect(file.Exists(path, "DATA")).to.beFalse()
            end
        },
        {
            name = "Core preflight refusal preserves the grant but accepted pending-write failure consumes it",
            func = function(state)
                assert(playlists().SetActive)("event")
                state.utc = 1100
                local schedule = changer().Schedule
                local refuse = true
                stub(changer(), "Schedule").with(function(mode, map)
                    if refuse then return false end
                    return schedule(mode, map)
                end)
                local rejected = assert(playlists().Start)("event")
                refuse = false
                expect(rejected).to.beFalse()
                expect(assert(playlists().GetSelection)().canStart).to.beTrue()
                expect(assert(playlists().Start)("event")).to.beTrue()
                stub(changer(), "_Begin").with(function() return false end)
                state.now = 1001 changer()._Tick()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(match().GetAbortReason()).to.exist()
                expect(assert(playlists().GetSelection)().canStart).to.beFalse()
                expect(playlists()._PendingStart("scheduled_test", "gm_b")).to.beNil()
            end
        },
        {
            name = "Pending playlist continuation retains version age map and count guards",
            func = function(state)
                for _, field in ipairs({ "v", "map", "mapChangeCount", "createdAt" }) do
                    local pending = { v = 1, map = "gm_a", mode = "scheduled_test", settings = {}, teams = {},
                        bots = 0, mapChangeCount = 4, createdAt = 999, playlist = "event" }
                        --[[@as table<string, any>]]
                    pending[field] = field == "map" and "wrong" or -1000
                    file.CreateDir("privatewar") file.Write(path, util.TableToJSON(pending))
                    expect(changer()._Apply()).to.beFalse()
                    expect(match().GetPhase()).to.equal("LOBBY")
                end
                expect(state.calls).to.equal(0)
            end
        },
        {
            name = "Expired running match finishes normally then freshly checks before choosing lobby instead of vote",
            func = function(state)
                assert(playlists().SetActive)("event")
                state.mode = { ClassName = "scheduled_test", Start = function() end, Cleanup = function() end }
                expect(match().Start(state.mode)).to.beTrue()
                state.utc = 1200
                local calls = state.calls --[[@as number]]
                match()._SetPhase("LIVE")
                playlists()._Poll()
                expect(match().Finish({ winner = 1 })).to.beTrue()
                playlists()._Poll()
                expect(state.calls).to.equal(calls)
                state.now = 1001 match()._Tick()
                expect(state.calls).to.equal(calls + 1)
                expect(match().GetPhase()).to.equal("LOBBY")
            end
        },
        {
            name = "Custom server start clears playlist entitlement through SetActive",
            func = function()
                local lobby = assert(PW.Lobby)
                local previous = PW._Lobby
                local selected = "not called"
                stub(playlists(), "SetActive").with(function(id) selected = id return true end)
                stub(lobby, "_StartableModes").with(function() return { { ClassName = "test" } } end)
                stub(lobby, "_CheckStart").with(function() return true end)
                PW._Lobby = assert(lobby._NewStore)({ readStart = function() return "test", "gm_a" end,
                    registries = function() return {} end, log = function() end, start = function() return true end })
                local ok = assert(lobby._OnStart)(NULL)
                PW._Lobby = previous
                expect(ok).to.beTrue()
                expect(selected).to.equal("")
            end
        },
        {
            name = "Final vote launch revalidates after result resolution instead of falling back to the same mode",
            func = function(state)
                assert(playlists().SetActive)("event")
                PW._Match.phase, PW._Match.mode, PW._Match.endsAt = "VOTE", state.mode, 1005
                stub(PW, "Ask").with(function(name)
                    if name == "PW_NextMatch" then
                        state.utc = 1200
                        return { mode = state.mode --[[@as table]], map = "gm_a" }
                    end
                end)
                expect(match().EndVote()).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(PW._MapChange.scheduled).to.beNil()
            end
        },
        {
            name = "Expiry during VOTE rejects the core launch and returns to lobby without same-mode fallback",
            func = function(state)
                assert(playlists().SetActive)("event")
                PW._Match.phase, PW._Match.mode, PW._Match.endsAt = "VOTE", state.mode, 1005
                state.utc = 1200
                expect(match().EndVote()).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(PW._MapChange.scheduled).to.beNil()
            end
        }
    }
}
