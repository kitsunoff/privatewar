-- PREMATCH is already an accepted match. Exercise real registry retirement without reloading the live server.
local path = "privatewar/pw_test_snd_pin_pending.json"
local function match() return assert(PW.Match) end
local function snd() return assert(PW.SND) end

---@return PW.SNDMapData
local function layout()
    return { bomb = Vector(-200, 0, 0), spawns = {
        [1] = { { pos = Vector(-200, 0, 0), yaw = 0 } },
        [2] = { { pos = Vector(1500, 0, 0), yaw = 180 } }
    }, sites = {
        { id = "A", pos = Vector(0, 0, 0), approach = Vector(0, 0, 0), radius = 64, above = 72, below = 16 },
        { id = "B", pos = Vector(1000, 0, 0), approach = Vector(1000, 0, 0), radius = 64, above = 72, below = 16 }
    } }
end

---@param state table<string, any>
---@param replacement? boolean
---@param remove? boolean
---@return PW.Registry
local function definitions(state, replacement, remove)
    local registry = PW.Registry.New("modes", { subscribe = "never", log = function() end,
        preRegister = function() end })
    local tracked = state.tracked --[[@as PW.Registry[] ]]
    tracked[#tracked + 1] = registry
    registry.Register({ Abstract = true, Start = function(self)
        state.started = state.started + 1
        state.usedNewBase = replacement == true
        state.liveMap = self._SNDMap
    end, Cleanup = function() end }, "round_base")
    registry.Register({ Base = "round_base", MapData = true, MapReadiness = true,
        Start = state.start, Cleanup = state.cleanup, PrepareRound = state.prepareRound }, "snd")
    if not remove then
        registry.Register({ Base = replacement and state.invalidChild and "missing_pin_base" or "snd",
            Name = "Pinned child", Teams = 2 }, "pin_child")
    end
    registry.ResolveAll()
    return registry
end

---@param state table<string, any>
---@param remove? boolean
local function reloadDefinitions(state, remove)
    local previous = PW.Registries
    local nextModes = definitions(state, true, remove)
    local active = PW.ActiveMode
    local keep = PW.Loader._KeepFor(previous, active ~= nil and { active } or {})
    assert(previous.modes)._Release(keep.modes)
    PW.Modes, PW.Registries = nextModes, { modes = nextModes, modules = previous.modules }
end

return {
    groupName = "PW SND accepted PREMATCH geometry",
    beforeEach = function(state)
        state.previous = { match = PW._Match, change = PW._MapChange, playlist = PW._Playlist,
            settings = PW._Settings, enable = PW._Enable, call = PW._Call, active = PW.ActiveMode,
            registries = PW.Registries, modes = PW.Modes }
        local source = assert(PW.Modes.Get("snd"))
        state.start, state.cleanup = source.Start, source.Cleanup
        state.prepareRound = source.PrepareRound
        state.tracked, state.current, state.started, state.prepares = {}, layout(), 0, 0
        state.now, state.utc, state.active, state.nav = 1000, 1000, "", true
        state.classification = "authored"
        PW.ActiveMode = nil
        PW._Call = { log = function() end, failed = setmetatable({}, { __mode = "k" }), profile = {} }
        PW._Settings = PW.Settings._NewStore()
        PW._Enable = assert(PW.Enable)._NewStore({ registries = function() return {} end })
        PW.Modes = definitions(state)
        PW.Registries = { modes = PW.Modes, modules = state.previous.registries.modules }
        state.mode = assert(PW.Modes.Get("pin_child"))
        PW._Match = match()._NewStore({ log = function() end, clock = function() return state.now end,
            players = function() return {} end, settings = function()
                return { prematch = 60, countdown = 10, postmatch = 1, vote = 15, afterMatch = "lobby" }
            end })
        PW._MapChange = assert(PW.MapChange)._NewStore({ path = path, log = function() end,
            time = function() return state.utc end, map = game.GetMap, mapChangeCount = function() return 6 end,
            announce = function() end, resolveMode = function(id) return PW.Modes.Get(id) end })
        PW._Playlist = assert(PW.Playlist)._NewStore({
            luaEntries = function() return { { ClassName = "pin_event", Name = "Pin event",
                Modes = { pin_child = 1 }, Maps = { game.GetMap() }, IsActive = function() return state.utc < 1100 end
            } } end, facts = function() return {} end, phase = match().GetPhase, time = function() return state.utc end,
            fits = function() return true end, log = function() end, broadcast = function() end,
            getActive = function() return state.active end, setActive = function(id) state.active = id end,
            start = function(id, map) return match().Start(assert(PW.Modes.Get(id)), map) end })
        stub(assert(PW.Map), "IsNavReady").with(function() return state.nav end)
        stub(assert(PW.Map), "GetModeAvailability").with(function()
            return { fits = not state.rejected, readiness = "pending", canRetry = false,
                classification = state.classification }
        end)
        stub(assert(PW.Map), "GetModeReadiness").with(function()
            return state.rejected and "rejected" or "ready", "New layout is invalid"
        end)
        stub(assert(PW.Map), "GetModeData").with(function() return state.current end)
        stub(snd(), "PrepareMap").with(function()
            state.prepares = state.prepares + 1
            assert(not state.forbidPrepare, "accepted match must not prepare from the new registry")
            return not state.rejected and state.current or nil
        end)
        stub(snd(), "Activate").with(function(data)
            assert(not state.blocked, "pinned world geometry is now blocked")
            state.activated = data
        end)
        stub(snd(), "Clear").with(function() end)
        stub(player, "GetAll").with(function() return {} end)
        stub(PW, "Notify").with(function(name, phase)
            if name == "PW_PhaseChange" and phase == "PREMATCH" then
                local mode = assert(PW._Match.mode) --[[@as PW.SNDMode]]
                state.phasePin = mode._SNDMap
            end
        end)
        stub(net, "Start").with(function() end)
        stub(net, "WriteString").with(function() end)
        stub(net, "Broadcast").with(function() end)
    end,
    afterEach = function(state)
        if PW._Match ~= state.previous.match then match()._ReleaseStartMap() end
        file.Delete(path)
        for _, registry in ipairs(state.tracked --[[@as PW.Registry[] ]]) do registry._Release() end
        PW._Match, PW._MapChange, PW._Playlist = state.previous.match, state.previous.change, state.previous.playlist
        PW._Settings, PW._Enable, PW._Call = state.previous.settings, state.previous.enable, state.previous.call
        PW.ActiveMode, PW.Modes, PW.Registries = state.previous.active, state.previous.modes, state.previous.registries
    end,
    cases = {
        {
            name = "SND preflight pins an isolated map before PREMATCH including vectors and both spawn pools",
            func = function(state)
                expect(match().Start(state.mode)).to.beTrue()
                expect(match().GetPhase()).to.equal("PREMATCH")
                local pinned = assert(state.mode._SNDMap) --[[@as PW.SNDMapData]]
                expect(state.phasePin).to.equal(pinned)
                expect(pinned == state.current).to.beFalse()
                local current = state.current --[[@as PW.SNDMapData]]
                current.bomb.x = 900
                current.sites[1].pos.x = 800
                current.spawns[1][1].pos.x = 700
                current.spawns[2][1].yaw = 0
                expect(pinned.bomb.x).to.equal(-200)
                expect(pinned.sites[1].pos.x).to.equal(0)
                expect(pinned.spawns[1][1].pos.x).to.equal(-200)
                expect(pinned.spawns[2][1].yaw).to.equal(180)
            end
        },
        {
            name = "SND PREMATCH reload with removed child starts the old definition and pinned map at LIVE",
            func = function(state)
                expect(match().Start(state.mode)).to.beTrue()
                local pinned = assert(state.mode._SNDMap)
                reloadDefinitions(state, true)
                state.forbidPrepare, state.rejected = true, true
                rawset(state, "current", nil)
                expect(PW.Modes.Get("pin_child")).to.beNil()
                expect(state.mode:IsValid()).to.beTrue()
                expect(match()._SetPhase("LIVE")).to.beTrue()
                expect(match().GetPhase()).to.equal("LIVE")
                expect(state.started).to.equal(1)
                expect(state.usedNewBase).to.beFalse()
                expect(state.liveMap).to.equal(pinned)
                expect(state.activated).to.equal(pinned)
                expect(state.prepares).to.equal(1)
                match().Finish({})
                match()._SetPhase("LOBBY")
                expect(state.mode._SNDMap).to.beNil()
                expect(match().Start(state.mode)).to.beFalse()
                expect(match().GetPhase()).to.equal("LOBBY")
            end
        },
        {
            name = "SND changed invalid authored child during PREMATCH cannot replace accepted geometry",
            func = function(state)
                expect(match().Start(state.mode)).to.beTrue()
                local pinned = assert(state.mode._SNDMap)
                reloadDefinitions(state)
                state.current, state.forbidPrepare, state.rejected = { sites = {} }, true, true
                match()._SetPhase("LIVE")
                expect(match().GetPhase()).to.equal("LIVE")
                expect(state.liveMap).to.equal(pinned)
                expect(state.usedNewBase).to.beFalse()
            end
        },
        {
            name = "SND invalid replacement child during PREMATCH cannot invalidate the accepted old definition",
            func = function(state)
                expect(match().Start(state.mode)).to.beTrue()
                local pinned = assert(state.mode._SNDMap)
                state.invalidChild = true
                reloadDefinitions(state)
                expect(PW.Modes.Get("pin_child")).to.beNil()
                state.forbidPrepare = true
                match()._SetPhase("LIVE")
                expect(match().GetPhase()).to.equal("LIVE")
                expect(state.liveMap).to.equal(pinned)
                expect(state.usedNewBase).to.beFalse()
                match().Finish({})
                match()._SetPhase("LOBBY")
                expect(match().Start(state.mode)).to.beFalse()
            end
        },
        {
            name = "SND vote and accepted pending starts pin their own geometry before PREMATCH",
            func = function(state)
                PW._Match.phase, PW._Match.mode, PW._Match.endsAt = "VOTE", state.mode, 1005
                stub(PW, "Ask").with(function() return { mode = state.mode --[[@as table]] } end)
                expect(match().EndVote()).to.beTrue()
                local first = assert(state.mode._SNDMap)
                match().Abort("pin fixture ends vote visit")
                expect(state.mode._SNDMap).to.beNil()
                file.CreateDir("privatewar")
                file.Write(path, util.TableToJSON({ v = 1, mode = "pin_child", map = game.GetMap(), settings = {},
                    teams = {}, bots = 0, mapChangeCount = 5, createdAt = 999 }))
                expect(assert(PW.MapChange)._Apply()).to.beTrue()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(state.mode._SNDMap == first).to.beFalse()
                reloadDefinitions(state, true)
                state.forbidPrepare = true
                rawset(state, "current", nil)
                match()._SetPhase("LIVE")
                expect(state.started).to.equal(1)
            end
        },
        {
            name = "SND async readiness pins the completed generated layout once and abort clears the pin",
            func = function(state)
                state.nav = false
                state.classification = "generated"
                expect(match().Start(state.mode)).to.beTrue()
                expect(state.mode._SNDMap).to.beNil()
                state.nav = true
                match()._Tick()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(state.mode._SNDMap ~= nil).to.beTrue()
                expect(state.prepares).to.equal(1)
                match().Abort("pin fixture cancels PREMATCH")
                expect(state.mode._SNDMap).to.beNil()
                expect(match().GetPhase()).to.equal("LOBBY")
            end
        },
        {
            name = "SND reload while readiness waits cancels without a pin and the next attempt uses the new child",
            func = function(state)
                state.nav = false
                expect(match().Start(state.mode)).to.beTrue()
                reloadDefinitions(state)
                match()._Tick()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(state.mode._SNDMap).to.beNil()
                expect(state.prepares).to.equal(0)
                state.nav = true
                expect(match().Start(state.mode)).to.beTrue()
                expect(PW.ActiveMode).to.equal(PW.Modes.Get("pin_child"))
                expect(PW.ActiveMode._SNDMap ~= nil).to.beTrue()
                expect(state.mode._SNDMap).to.beNil()
            end
        },
        {
            name = "SND preflight rejection preserves expiry grant but accepted final failure cannot refund",
            func = function(state)
                local playlists = assert(PW.Playlist)
                expect(playlists.SetActive("pin_event")).to.beTrue()
                state.utc, state.rejected = 1200, true
                expect(playlists.Start("pin_event")).to.beFalse()
                expect(state.mode._SNDMap).to.beNil()
                expect(playlists.GetSelection().retained).to.beTrue()
                state.rejected = false
                expect(playlists.Start("pin_event")).to.beTrue()
                state.blocked = true
                match()._SetPhase("LIVE")
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(state.started).to.equal(0)
                expect(state.mode._SNDMap).to.beNil()
                expect(playlists.GetSelection().canStart).to.beFalse()
            end
        },
        {
            name = "SND next match uses the new definition and layout after the previous pin is retired",
            func = function(state)
                expect(match().Start(state.mode)).to.beTrue()
                local old = assert(state.mode._SNDMap)
                reloadDefinitions(state)
                match()._SetPhase("LIVE")
                expect(state.usedNewBase).to.beFalse()
                expect(match().Finish({})).to.beTrue()
                expect(state.mode._SNDMap).to.beNil()
                match()._SetPhase("LOBBY")
                state.current = layout()
                state.current.sites[1].radius = 96
                expect(match().Start(state.mode)).to.beTrue()
                expect(PW.ActiveMode).to.equal(PW.Modes.Get("pin_child"))
                match()._SetPhase("LIVE")
                expect(state.usedNewBase).to.beTrue()
                expect(state.liveMap == old).to.beFalse()
                expect(state.liveMap.sites[1].radius).to.equal(96)
            end
        }
    }
}
