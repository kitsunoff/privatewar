-- T-2.12 navmesh generation flow (TASKS.md, "Mandatory test cases" T-2.12: marker validation (success, failure,
-- stale marker); seeds generated for every spawn entity class; no generation without the privilege or outside
-- LOBBY; 03-mapdata.md d.8; notes/11-navmesh-generation.md "Recommendations"). Pure cases run over plain data. Glue
-- cases swap PW._NavGen for a store whose engine calls are fakes: navmesh generation never starts, no file is
-- written and the map never reloads. Net cases call the receive path (PW.Net._Dispatch) with one pool bot as sender
-- in a fresh net store (fake clock and phase); the real phase machine is never touched.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.NavGenLib
local function lib()
    return must(PW.NavGen)
end

---@param state table<string, any>
---@return table<string, any[]>
local function calls(state)
    return state.calls --[[@as table<string, any[]>]]
end

---@param state table<string, any>
---@param kind string
---@param value any
local function record(state, kind, value)
    local list = calls(state)[kind]
    list[#list + 1] = value
end

---One record per spawn entity class of the map module, plus one of a class that is not a spawn class.
---@return PW.SpawnRecord[]
local function everyClass()
    local classes = table.GetKeys(must(PW.Map)._SpawnClasses) --[[@as string[] ]]
    table.sort(classes)
    ---@type PW.SpawnRecord[]
    local records = {}
    for index, class in ipairs(classes) do
        records[#records + 1] = { class = class, pos = Vector(index * 100, 0, 0), yaw = 0 }
    end
    records[#records + 1] = { class = "prop_physics", pos = Vector(0, 0, 0), yaw = 0 }
    return records
end

---A fresh navgen store over fakes: the marker file is state.file, the navmesh area count is state.areas, the
---engine starts generating when state.engineStarts is true.
---@param state table<string, any>
local function installStore(state)
    state.calls = { log = {}, seeds = {}, commands = {}, paused = {}, begin = {}, kicked = {}, broadcast = {} }
    PW._NavGen = must(lib()._NewStore)({
        log = function(message) record(state, "log", message) end,
        time = function() return state.now end,
        map = function() return "gm_pw_nav" end,
        read = function() return state.file end,
        write = function(_, text)
            state.file = text
            return true
        end,
        delete = function() state.file = nil end,
        navCount = function() return state.areas end,
        isGenerating = function() return #calls(state).begin > 0 and state.engineStarts == true end,
        clearSeeds = function() calls(state).seeds = {} end,
        addSeed = function(pos) record(state, "seeds", pos) end,
        begin = function() record(state, "begin", true) end,
        command = function(name, value) record(state, "commands", name .. " " .. value) end,
        cheats = function() return state.cheats == true end,
        records = function() return state.records end,
        ground = function(pos) return pos, Vector(0, 0, 1) end,
        hostSeed = function() return nil end,
        kickBots = function() record(state, "kicked", true) end,
        pauseNav = function(paused) record(state, "paused", paused) end,
        defer = function(fn) fn() end,
        humans = function() return state.humans end,
        phase = function() return state.phase end,
        changing = function() return false end,
        broadcast = function() record(state, "broadcast", true) end,
        readStart = function()
            local request = state.request --[[@as any[] ]]
            return request[1], request[2]
        end
    })
end

---Returns the one pool bot with the given usergroup (one bot for the whole group, as in the lobby tests).
---@param state table<string, any>
---@param group string
---@return Player
local function makeBot(state, group)
    local pool = state.pool --[[@as table<string, Player>]]
    local bot = pool.bot
    if bot == nil or not IsValid(bot) then
        bot = player.CreateNextBot("PW navgen test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        pool.bot = bot
    end
    bot:SetUserGroup(group)
    return bot
end

---Sends pw_navgen_start from ply through the real wrapper (2 s after the previous one).
---@param state table<string, any>
---@param ply Player
---@param fast boolean
---@param force boolean
---@return boolean
---@return string?
local function send(state, ply, fast, force)
    state.request = { fast, force }
    state.now = state.now + 2
    return must(PW.Net)._Dispatch("pw_navgen_start", 8, ply)
end

---@param map string
---@param startedAt number
---@return PW.NavGenMarker
local function marker(map, startedAt)
    return { v = lib().Version, map = map, startedAt = startedAt, fast = false, cheatsWasOn = false }
end

return {
    groupName = "PW navgen",
    beforeAll = function(state)
        state.pool = {}
    end,
    afterAll = function(state)
        local bot = (state.pool --[[@as table<string, Player>]]).bot
        if bot ~= nil and IsValid(bot) then bot:Kick("PW navgen test finished") end
    end,
    beforeEach = function(state)
        state.previousNet = PW._Net
        state.previousStore = PW._NavGen
        state.previousMap = PW._Map
        state.previousLobby = PW._Lobby
        state.now = 100000
        state.phase = "LOBBY"
        state.areas = 0
        state.humans = 1
        state.cheats = false
        state.engineStarts = true
        state.records = everyClass()
        installStore(state)
        PW._Net = must(PW.Net)._NewStore({ log = function() end, clock = function() return state.now end,
            phase = function() return state.phase end })
        must(lib()._RegisterNet)({ IsValid = function() return true end })
    end,
    afterEach = function(state)
        PW._Net = state.previousNet
        PW._NavGen = state.previousStore
        PW._Map = state.previousMap
        PW._Lobby = state.previousLobby
    end,
    cases = {
        {
            -- Async and first, as in the lobby tests: lets bot slots freed by earlier groups come back.
            name = "The navgen privilege is declared with the superadmin default",
            async = true,
            timeout = 3,
            func = function()
                expect(lib().Privilege).to.equal("pw.map.navgen")
                expect(must(PW._Privileges.defs["pw.map.navgen"]).MinAccess).to.equal("superadmin")
                timer.Simple(0.2, function() done() end)
            end
        },
        {
            name = "Mandatory (T-2.12): marker validation success: this map, fresh, the navmesh now has areas",
            func = function()
                local facts = { map = "gm_pw_nav", now = 1000, areas = 42 }
                expect({ lib()._ValidateMarker(marker("gm_pw_nav", 900), facts) }).to.deepEqual({ "success" })
            end
        },
        {
            name = "Mandatory (T-2.12): marker validation failure: this map, fresh, still no navmesh",
            func = function()
                local facts = { map = "gm_pw_nav", now = 1000, areas = 0 }
                expect({ lib()._ValidateMarker(marker("gm_pw_nav", 900), facts) }).to.deepEqual({ "failure" })
            end
        },
        {
            name = "Mandatory (T-2.12): marker validation stale: other map, too old, from the future, corrupt, version",
            func = function()
                local facts = { map = "gm_pw_nav", now = 100000, areas = 42 }
                local function check(value, reason)
                    expect({ lib()._ValidateMarker(value, facts) }).to.deepEqual({ "stale", reason })
                end
                check(marker("gm_other", 99000), "map")
                check(marker("gm_pw_nav", 100000 - lib().MaxAge - 1), "age")
                check(marker("gm_pw_nav", 100001), "age")
                check(nil, "corrupt")
                check("text", "corrupt")
                check({ v = lib().Version, map = "gm_pw_nav" }, "corrupt")
                local old = marker("gm_pw_nav", 99000)
                old.v = lib().Version + 1
                check(old, "version")
                expect(lib()._ValidateMarker(marker("gm_pw_nav", 100000 - lib().MaxAge), facts)).to.equal("success")
            end
        },
        {
            name = "Mandatory (T-2.12): seeds are generated for every spawn entity class, other classes ignored",
            func = function()
                local seeds = lib()._Seeds(everyClass(), must(PW.Map)._SpawnClasses)
                ---@type table<string, integer>
                local byClass = {}
                for _, seed in ipairs(seeds) do byClass[seed.class] = (byClass[seed.class] or 0) + 1 end
                for class in pairs(must(PW.Map)._SpawnClasses) do expect(byClass[class]).to.equal(1) end
                expect(byClass.prop_physics).to.equal(nil)
                expect(#seeds).to.equal(table.Count(must(PW.Map)._SpawnClasses))
            end
        },
        {
            name = "Mandatory (T-2.12): the start adds one walkable seed per spawn entity of every class",
            func = function(state)
                local ok = lib()._Start(nil, false, false)
                expect(ok).to.beTrue()
                local seeds = calls(state).seeds
                expect(#seeds).to.equal(table.Count(must(PW.Map)._SpawnClasses))
                for index, rec in ipairs(state.records --[[@as PW.SpawnRecord[] ]]) do
                    if rec.class ~= "prop_physics" then expect(seeds[index]).to.equal(rec.pos) end
                end
                expect(#calls(state).begin).to.equal(1)
            end
        },
        {
            name = "Mandatory (T-2.12): the pure check refuses without the privilege and outside LOBBY",
            func = function()
                local base = { phase = "LOBBY", allowed = true, generating = false, changing = false, areas = 0 }
                ---@param changes table<string, any>
                ---@return any[]
                local function with(changes)
                    local facts = table.Copy(base) --[[@as table<string, any>]]
                    for key, value in pairs(changes) do facts[key] = value end
                    return { lib()._MayGenerate(facts --[[@as PW.NavGenStartFacts]]) }
                end
                expect(with({})).to.deepEqual({ true })
                expect(with({ allowed = false })).to.deepEqual({ false, "privilege" })
                for _, phase in ipairs({ "PREMATCH", "LIVE", "POSTMATCH" }) do
                    expect(with({ phase = phase })).to.deepEqual({ false, "phase" })
                end
                expect(with({ generating = true })).to.deepEqual({ false, "busy" })
                expect(with({ changing = true })).to.deepEqual({ false, "busy" })
                expect(with({ areas = 10 })).to.deepEqual({ false, "navmesh exists" })
                expect(with({ areas = 10, force = true })).to.deepEqual({ true })
            end
        },
        {
            name = "Mandatory (T-2.12): no generation without the privilege or outside LOBBY (net and start paths)",
            func = function(state)
                local bot = makeBot(state, "user")
                expect({ send(state, bot, false, false) }).to.deepEqual({ false, "privilege" })
                expect({ lib()._Start(bot, false, false) }).to.deepEqual({ false, "privilege" })
                makeBot(state, "superadmin")
                state.phase = "LIVE"
                expect({ send(state, bot, false, false) }).to.deepEqual({ false, "phase" })
                expect({ lib()._Start(bot, false, false) }).to.deepEqual({ false, "phase" })
                expect(#calls(state).begin).to.equal(0)
                expect(#calls(state).seeds).to.equal(0)
                expect(state.file).to.equal(nil)
                state.phase = "LOBBY"
                expect(send(state, bot, false, false)).to.beTrue()
                expect(#calls(state).begin).to.equal(1)
            end
        },
        {
            name = "Start: marker written first, bots kicked, sampler paused, clients told; marker fields",
            func = function(state)
                state.cheats = true
                expect(lib()._Start(nil, false, false)).to.beTrue()
                local written = must(lib()._Decode(must(state.file)))
                expect(written).to.deepEqual({ v = lib().Version, map = "gm_pw_nav", startedAt = 100000, fast = false,
                    cheatsWasOn = true })
                expect(calls(state).kicked).to.deepEqual({ true })
                expect(calls(state).paused).to.deepEqual({ true })
                expect(#calls(state).broadcast).to.equal(1)
                expect(#calls(state).commands).to.equal(0)
                expect(lib().IsGenerating()).to.beTrue()
                expect({ lib()._Start(nil, false, false) }).to.deepEqual({ false, "busy" })
            end
        },
        {
            name = "Fast mode: sv_cheats, view distance and fence tops are set before generation starts",
            func = function(state)
                expect(lib()._Start(nil, true, false)).to.beTrue()
                expect(calls(state).commands).to.deepEqual({ "sv_cheats 1", "nav_max_view_distance 1",
                    "nav_generate_fencetops 0" })
                expect(must(lib()._Decode(must(state.file))).fast).to.beTrue()
                expect(lib()._FastDefault(1)).to.beTrue()
                expect(lib()._FastDefault(2)).to.beFalse()
            end
        },
        {
            name = "Start that the engine refuses (no walkable seed): marker deleted, cheats restored, failure shown",
            func = function(state)
                state.engineStarts = false
                expect({ lib()._Start(nil, true, false) }).to.deepEqual({ false, "engine" })
                expect(state.file).to.equal(nil)
                expect(calls(state).paused).to.deepEqual({ true, false })
                expect(calls(state).commands[4]).to.equal("sv_cheats 0")
                expect(lib().IsGenerating()).to.beFalse()
                expect(must(PW._NavGen.result).kind).to.equal("failure")
            end
        },
        {
            name = "Start without any seed is refused before the marker and the engine",
            func = function(state)
                state.records = {}
                expect({ lib()._Start(nil, false, false) }).to.deepEqual({ false, "no seeds" })
                expect(state.file).to.equal(nil)
                expect(#calls(state).begin).to.equal(0)
            end
        },
        {
            name = "After the reload: success reported to the host, cheats restored after fast mode, marker deleted",
            func = function(state)
                local fast = marker("gm_pw_nav", 99000)
                fast.fast = true
                state.file = lib()._Encode(fast)
                state.areas = 0
                expect(lib()._Check(false)).to.equal(nil)
                expect(state.file).toNot.equal(nil)
                state.areas = 321
                expect(lib()._Check(false)).to.equal("success")
                expect(state.file).to.equal(nil)
                expect(calls(state).commands).to.deepEqual({ "sv_cheats 0" })
                local result = must(PW._NavGen.result)
                expect(result.kind).to.equal("success")
                expect(string.find(result.text, "321", 1, true) ~= nil).to.beTrue()
                expect(#calls(state).broadcast).to.equal(1)
                expect(#calls(state).log).to.equal(1)
                expect(lib()._Check(true)).to.equal(nil)
            end
        },
        {
            name = "After the reload: no navmesh at the last check is a failure; a stale marker is only logged",
            func = function(state)
                state.file = lib()._Encode(marker("gm_pw_nav", 99000))
                expect(lib()._Check(true)).to.equal("failure")
                expect(must(PW._NavGen.result).kind).to.equal("failure")
                expect(state.file).to.equal(nil)
                PW._NavGen.result = nil
                state.file = lib()._Encode(marker("gm_other", 99000))
                expect(lib()._Check(true)).to.equal("stale")
                expect(PW._NavGen.result).to.equal(nil)
                expect(state.file).to.equal(nil)
                state.file = "{broken"
                expect(lib()._Check(true)).to.equal("stale")
                expect(state.file).to.equal(nil)
            end
        },
        {
            name = "Lobby info: generate offered only to the privileged host in LOBBY on a map without navmesh",
            func = function(state)
                local admin = makeBot(state, "superadmin")
                local info = lib().LobbyInfo(admin)
                expect(info).to.deepEqual({ areas = 0, generating = false, canGenerate = true, fastDefault = true,
                    result = "" })
                makeBot(state, "user")
                expect(lib().LobbyInfo(admin).canGenerate).to.beFalse()
                makeBot(state, "superadmin")
                state.areas = 50
                expect(lib().LobbyInfo(admin).canGenerate).to.beFalse()
                state.areas = 0
                state.humans = 3
                expect(lib().LobbyInfo(admin).fastDefault).to.beFalse()
            end
        },
        {
            name = "The lobby state carries the navmesh block through the explicit wire encoding",
            func = function()
                local lobby = must(PW.Lobby)
                local nav = { areas = 1234, generating = true, canGenerate = false, fastDefault = true,
                    result = "Navmesh generated: 1234 areas." }
                local sentState = lobby._BuildState({ map = "gm_pw_nav", maps = { "gm_pw_nav" }, modes = {},
                    groupsOf = function() return {} end, toggles = {}, canStart = true, canEdit = false,
                    canToggle = false, nav = nav })
                ---@type any[]
                local queue = {}
                local function push(value) queue[#queue + 1] = value end
                lobby._Encode(sentState, { uint = push, string = push, bool = push })
                local position = 0
                local function nextValue()
                    position = position + 1
                    return queue[position]
                end
                local received = lobby._Decode({ uint = nextValue, string = nextValue, bool = nextValue },
                    lobby._Resolver({}))
                expect(position).to.equal(#queue)
                expect(received.nav).to.deepEqual(nav)
            end
        },
        {
            name = "A lobby or playlist start is refused on the server while a navmesh generation runs",
            func = function(state)
                local admin = makeBot(state, "superadmin")
                ---@type string[]
                local logs = {}
                local starts = 0
                PW._Lobby = must(must(PW.Lobby)._NewStore)({
                    log = function(message) logs[#logs + 1] = message end,
                    readStart = function() return "tdm", "gm_construct" end,
                    start = function()
                        starts = starts + 1
                        return true
                    end
                })
                must(PW._NavGen).generating = true
                expect(must(must(PW.Lobby)._OnStart)(admin)).to.beFalse()
                expect(starts).to.equal(0)
                expect(string.find(must(logs[1]), "navmesh generation running", 1, true) ~= nil).to.beTrue()
                expect({ must(must(PW.Playlist).Start)("pwt_any") })
                    .to.deepEqual({ false, "navmesh generation running" })
            end
        },
        {
            name = "The lobby navmesh line: none, no navmesh, area count, last result, generating",
            func = function()
                local line = must(PW.Lobby)._NavLine
                local nav = { areas = 0, generating = false, canGenerate = true, fastDefault = true, result = "" }
                expect(line(nil)).to.equal("")
                expect(line(nav)).to.equal("No navmesh: bots and dynamic spawns unavailable.")
                nav.areas = 12
                expect(line(nav)).to.equal("Navmesh: 12 areas.")
                nav.result = "done"
                expect(line(nav)).to.equal("done")
                nav.generating = true
                expect(string.find(line(nav), "map reloads", 1, true) ~= nil).to.beTrue()
            end
        },
        {
            name = "Map data: the navmesh sampler does not run while paused and drops the destroyed areas",
            func = function()
                local map = must(PW.Map)
                PW._Map = map._NewStore()
                PW._Map.navCheckAt = 0
                PW._Map.nav = { loaded = true, areas = { "area" }, samples = { { pos = Vector(1, 2, 3), yaw = 0 } },
                    eligible = 1, costMs = 0 }
                map.PauseNav(true)
                expect(#map.GetNavAreas()).to.equal(0)
                expect(#map.GetNavSamples()).to.equal(1)
                PW._Map.nav = nil
                map._NavThink()
                expect(PW._Map.nav).to.equal(nil)
                expect(PW._Map.navTries).to.equal(nil)
                map.PauseNav(false)
                expect(PW._Map.navPaused).to.equal(nil)
            end
        },
        {
            name = "The real registration gives pw_navgen_start the navgen class table as owner",
            func = function(state)
                local real = state.previousNet --[[@as PW.NetStore]]
                local owner = must(PW.Modules.GetStored("navgen"))
                expect(must(real.defs.pw_navgen_start).owner).to.equal(owner)
                expect(must(real.defs.pw_navgen_start).who).to.equal("pw.map.navgen")
            end
        }
    }
}
