-- Behavior-first integration cases. No real map change, detector geometry or native spawn is exercised.
local path = "privatewar/pw_test_snd_start.json"
local function match() return assert(PW.Match) end
local function playlist() return assert(PW.Playlist) end
local function changer() return assert(PW.MapChange) end

---@param state table<string, any>
local function selectExpired(state)
    expect(playlist().SetActive("event")).to.beTrue()
    state.utc = 1200
    playlist().RefreshAvailability()
    expect(playlist().GetSelection().retained).to.beTrue()
end

return {
    groupName = "PW SND start integration",
    beforeEach = function(state)
        state.previous = { match = PW._Match, change = PW._MapChange, playlist = PW._Playlist,
            settings = PW._Settings, enable = PW._Enable, mode = PW.ActiveMode, lobby = PW._Lobby }
        state.now, state.utc, state.nav, state.readiness = 1000, 1000, true, "ready"
        state.prepares, state.accepts, state.events, state.messages = 0, 0, {}, {}
        state.active, state.map, state.predicates = "", game.GetMap(), 0
        state.mode = { ClassName = "snd", MapData = true, MapReadiness = true }
        PW.ActiveMode = nil
        PW._Settings = PW.Settings._NewStore()
        PW._Enable = assert(PW.Enable)._NewStore({ registries = function() return {} end })
        PW._Match = match()._NewStore({ clock = function() return state.now end, log = function() end,
            players = function() return {} end, settings = function()
                return { prematch = 60, countdown = 0, postmatch = 1, vote = 15, afterMatch = "rotation" }
            end })
        PW._MapChange = changer()._NewStore({ path = path, clock = function() return state.now end,
            time = function() return state.utc end, map = function() return state.map end,
            mapChangeCount = function() return 6 end, log = function() end, announce = function() end,
            changelevel = function() error("unexpected native changelevel") end,
            resolveMode = function() return state.mode end })
        PW._Playlist = playlist()._NewStore({ luaEntries = function() return {
            { ClassName = "event", Name = "Event", Modes = { snd = 1 }, Maps = { state.map },
                IsActive = function()
                    state.predicates = state.predicates + 1
                    return state.utc < 1100
                end }
        } end, facts = function() return {} end, time = function() return state.utc end,
            phase = match().GetPhase, fits = function() return true end, broadcast = function() end,
            log = function() end, getActive = function() return state.active end,
            setActive = function(id) state.active = id end,
            start = function(_, map) return match().Start(state.mode, map) end })
        stub(assert(PW.Map), "IsNavReady").with(function() return state.nav end)
        stub(assert(PW.Map), "ModeFits").with(function() return true end)
        stub(assert(PW.Map), "GetModeReadiness").with(function()
            return state.readiness, "S&D plant volume is blocked"
        end)
        stub(assert(PW.SND), "PrepareMap").with(function()
            state.prepares = state.prepares + 1
            if state.explode then error("private detector failure") end
            return state.readiness == "ready" and {} or nil
        end)
        stub(PW, "Notify").with(function(name, ...)
            local events = state.events --[[@as table[] ]]
            events[#events + 1] = { name, ... }
            if state.refuseOnVote and name == "PW_PhaseChange" and select(1, ...) == "VOTE" then
                match()._RefuseStart("S&D vote has no compatible maps")
            end
            if state.deliverRefusal and name == "PW_MatchStartRefused" then
                local owner = assert(PW.Modules.Get("lobby_ui"))
                local handler = owner.PW_MatchStartRefused --[[@as fun(self: PW.Entity, reason: string)]]
                handler(owner, select(1, ...))
            end
        end)
        stub(net, "Start").with(function() end)
        stub(net, "WriteString").with(function(text)
            local messages = state.messages --[[@as string[] ]]
            messages[#messages + 1] = text
        end)
        stub(net, "Broadcast").with(function() end)
        stub(net, "Send").with(function() end)
    end,
    afterEach = function(state)
        file.Delete(path)
        PW._Match, PW._MapChange, PW._Playlist = state.previous.match, state.previous.change, state.previous.playlist
        PW._Settings, PW._Enable, PW.ActiveMode = state.previous.settings, state.previous.enable, state.previous.mode
        PW._Lobby = state.previous.lobby
    end,
    cases = {
        {
            name = "Pending playlist restoration rejects a different mode or map without evaluating availability",
            func = function(state)
                expect(playlist()._RestoreStart("event", "tdm", state.map)).to.beFalse()
                expect(playlist()._RestoreStart("event", "snd", "de_other_fixture")).to.beFalse()
                expect(state.predicates).to.equal(0)
                expect(match().GetPhase()).to.equal("LOBBY")
            end
        },
        {
            name = "SND refusal while opening VOTE is deferred safely until the phase transition finishes",
            func = function(state)
                PW._Match.phase, PW._Match.mode = "POSTMATCH", state.mode
                state.refuseOnVote = true
                expect(match()._SetPhase("VOTE", 15)).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(match().GetAbortReason()).to.equal("S&D vote has no compatible maps")
            end
        },
        {
            name = "SND provisional remote selection never prepares geometry from the currently loaded map",
            func = function(state)
                local target = "de_pw_start_fixture"
                local scheduled = ""
                stub(changer(), "Schedule").with(function(_, map) scheduled = map return true end)
                stub(assert(PW.Map), "ModeFits").with(function(mode, map)
                    expect(mode).to.equal(state.mode)
                    expect(map).to.equal(target)
                    return true, nil, "provisional"
                end)
                expect(match().Start(state.mode, target)).to.beTrue()
                expect(scheduled).to.equal(target)
                expect(state.prepares).to.equal(0)
                expect(match().GetPhase()).to.equal("LOBBY")
            end
        },
        {
            name = "SND waiting vote cannot be resolved twice and an abort prevents any later launch",
            func = function(state)
                PW._Match.phase, PW._Match.mode, PW._Match.endsAt = "VOTE", state.mode, 1005
                local asked = 0
                stub(PW, "Ask").with(function()
                    asked = asked + 1
                    return { mode = state.mode --[[@as table]] }
                end)
                state.nav = false
                expect(match().EndVote()).to.beTrue()
                expect(match().EndVote()).to.beFalse()
                expect(asked).to.equal(1)
                match().Abort("Host cancelled the start")
                state.nav = true
                match()._Tick()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(state.prepares).to.equal(0)
            end
        },
        {
            name = "SND async accepted pending rejection is terminal and never restores expired permission",
            func = function(state)
                file.CreateDir("privatewar")
                file.Write(path, util.TableToJSON({ v = 1, map = state.map --[[@as string]],
                    mode = "snd", settings = {}, teams = {}, bots = 0, mapChangeCount = 5,
                    createdAt = 999, playlist = "event" }))
                state.nav, state.utc = false, 1200
                expect(changer()._Apply()).to.beTrue()
                state.nav, state.readiness = true, "rejected"
                match()._Tick()
                playlist().RefreshAvailability()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(playlist().GetSelection().canStart).to.beFalse()
                local prepares = state.prepares --[[@as number]]
                match()._Tick()
                expect(state.prepares).to.equal(prepares)
                for _, event in ipairs(state.events --[[@as table[] ]]) do
                    expect(event[1] == "PW_PendingMatchApplied").to.beFalse()
                end
            end
        },
        {
            name = "Ordinary direct matches retain their phase flow without calling SND preparation",
            func = function(state)
                expect(match().Start({ ClassName = "tdm" })).to.beTrue()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(state.prepares).to.equal(0)
            end
        },
        {
            name = "SND direct rejection precedes PREMATCH and exposes a bounded player-safe reason",
            func = function(state)
                state.readiness, state.deliverRefusal = "rejected", true
                expect(match().Start(state.mode)).to.beFalse()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(PW.ActiveMode).to.beNil()
                expect(state.prepares).to.equal(1)
                expect(match().GetAbortReason()).to.equal("S&D plant volume is blocked")
                expect(PW._Match.dependencies).to.beNil()
                expect(state.messages[1]).to.equal("S&D plant volume is blocked")
                local lobby = assert(PW.Lobby)
                lobby._StartFailure(string.rep("x", 300) .. "\n")
                expect(#state.messages[2]).to.equal(256)
            end
        },
        {
            name = "SND direct start waits for nav readiness before preparing and entering PREMATCH once",
            func = function(state)
                state.nav = false
                expect(match().Start(state.mode)).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
                match()._Tick()
                expect(state.prepares).to.equal(0)
                expect(match().Start(state.mode)).to.beFalse()
                state.nav = true
                match()._Tick()
                expect(state.prepares).to.equal(1)
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(PW.ActiveMode).to.equal(state.mode)
            end
        },
        {
            name = "SND pending readiness and detector errors fail closed without catch-up retries",
            func = function(state)
                state.readiness = "pending"
                expect(match().Start(state.mode)).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
                state.now = 1130
                match()._Tick()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(match().GetAbortReason()).to.exist()
                state.explode, state.readiness = true, "ready"
                expect(match().Start(state.mode)).to.beFalse()
                expect(match().GetAbortReason()).to.equal("S&D map preparation failed; choose another map")
                local prepares = state.prepares --[[@as number]]
                match()._Tick()
                expect(state.prepares).to.equal(prepares)
            end
        },
        {
            name = "SND rejected expired playlist preflight preserves the selected one-shot grant",
            func = function(state)
                selectExpired(state)
                state.readiness = "rejected"
                expect(playlist().Start("event")).to.beFalse()
                expect(playlist().GetSelection().canStart).to.beTrue()
                expect(playlist().GetSelection().retained).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
            end
        },
        {
            name = "SND waiting expired playlist reserves nothing until ready then consumes its original target once",
            func = function(state)
                selectExpired(state)
                local draws = 0
                PW._Playlist.rng = function() draws = draws + 1 return 0 end
                state.nav = false
                expect(playlist().Start("event")).to.beTrue()
                expect(playlist().GetSelection().retained).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
                state.nav = true
                match()._Tick()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(playlist().GetSelection().retained).to.beFalse()
                expect(state.prepares).to.equal(1)
                expect(draws).to.equal(2)
            end
        },
        {
            name = "SND async rejection preserves expiry grant and replacing selection cancels the waiting launch",
            func = function(state)
                selectExpired(state)
                state.nav = false
                expect(playlist().Start("event")).to.beTrue()
                state.nav, state.readiness = true, "rejected"
                match()._Tick()
                expect(playlist().GetSelection().retained).to.beTrue()
                state.nav, state.readiness = false, "ready"
                expect(playlist().Start("event")).to.beTrue()
                expect(playlist().SetActive("")).to.beTrue()
                state.nav = true
                match()._Tick()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(playlist().GetActive()).to.equal("")
            end
        },
        {
            name = "SND vote rejection returns to usable lobby without repeating the old or unrelated mode",
            func = function(state)
                PW._Match.phase, PW._Match.mode, PW._Match.endsAt = "VOTE", { ClassName = "tdm" }, 1005
                stub(PW, "Ask").with(function() return { mode = state.mode --[[@as table]] } end)
                state.readiness = "rejected"
                match().EndVote()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(PW.ActiveMode).to.beNil()
                expect(match().GetAbortReason()).to.equal("S&D plant volume is blocked")
                expect(PW._MapChange.scheduled).to.beNil()
            end
        },
        {
            name = "SND waiting vote checks playlist expiry at readiness and never spends the lobby grant",
            func = function(state)
                expect(playlist().SetActive("event")).to.beTrue()
                PW._Match.phase, PW._Match.mode, PW._Match.endsAt = "VOTE", state.mode, 1005
                stub(PW, "Ask").with(function() return { mode = state.mode --[[@as table]] } end)
                state.nav = false
                match().EndVote()
                expect(match().GetPhase()).to.equal("VOTE")
                state.utc, state.nav = 1200, true
                match()._Tick()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(PW.ActiveMode).to.beNil()
            end
        },
        {
            name = "SND pending-file wait delays applied notification without evaluating expired availability",
            func = function(state)
                file.CreateDir("privatewar")
                file.Write(path, util.TableToJSON({ v = 1, map = state.map --[[@as string]],
                    mode = "snd", settings = {},
                    teams = {}, bots = 0, mapChangeCount = 5, createdAt = 999, playlist = "event" }))
                state.nav, state.utc = false, 1200
                expect(changer()._Apply()).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(file.Exists(path, "DATA")).to.beFalse()
                expect(#state.events).to.equal(0)
                local calls = state.predicates --[[@as number]]
                playlist()._Poll()
                expect(state.predicates).to.equal(calls)
                state.nav = true
                match()._Tick()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(state.predicates).to.equal(calls)
                local applied = 0
                for _, event in ipairs(state.events --[[@as table[] ]]) do
                    if event[1] == "PW_PendingMatchApplied" then applied = applied + 1 end
                end
                expect(applied).to.equal(1)
                expect(changer()._Apply()).to.beFalse()
            end
        },
        {
            name = "SND accepted pending continuation rejection does not refund an expired entitlement",
            func = function(state)
                file.CreateDir("privatewar")
                file.Write(path, util.TableToJSON({ v = 1, map = state.map --[[@as string]],
                    mode = "snd", settings = {},
                    teams = {}, bots = 0, mapChangeCount = 5, createdAt = 999, playlist = "event" }))
                state.readiness, state.utc = "rejected", 1200
                expect(changer()._Apply()).to.beFalse()
                expect(match().GetPhase()).to.equal("LOBBY")
                playlist().RefreshAvailability()
                expect(playlist().GetSelection().canStart).to.beFalse()
                expect(PW.ActiveMode).to.beNil()
            end
        }
    }
}
