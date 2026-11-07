-- T-5.1 bots manager (TASKS.md, "Mandatory test cases" T-5.1; 07-bots.md d.3; 00-core.md d.9; 02-modes.md d.5a;
-- 08-lobby.md d.4). The rules are pure functions over plain data; the steps run on fake stores whose create and
-- kick only record, so these cases never create a bot. One real bot (beforeAll, kicked in afterAll) checks the
-- engine glue: player.CreateNextBot and Player:Kick. The real manager (PW._BotsManager) is paused for the whole
-- GLuaTest run, so other groups that start matches are never filled with bots.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotsManagerLib
local function lib()
    return must(PW.BotsManager)
end

local unassigned = 1001

---A fake engine for a manager store: players are plain entries, create and kick only record.
---@class PW.Test.BotsWorld
---@field entries PW.BotsEntry[]
---@field created string[]
---@field kicked any[]
---@field logs string[]
---@field phase string
---@field fill integer
---@field max integer
---@field n integer
---@field sp boolean
---@field paused boolean
---@field generating boolean
---@field createResult? fun(name: string): any
---@field nextId integer

---@param ent any
---@return any
local function fakeEnt(ent)
    return setmetatable({ label = ent }, { __index = { IsValid = function() return true end } })
end

---@param over? table<string, any>
---@return PW.Test.BotsWorld
local function newWorld(over)
    ---@type PW.Test.BotsWorld
    local world = {
        entries = {}, created = {}, kicked = {}, logs = {}, phase = "LIVE", fill = 12, max = 12, n = 2, sp = false,
        paused = false, generating = false, nextId = 1
    }
    ---@type table<string, any>
    local overrides = over or {}
    for key, value in pairs(overrides) do (world --[[@as table<string, any>]])[key] = value end
    return world
end

---@param world PW.Test.BotsWorld
---@param team integer
---@param bot boolean
---@return any ent
local function addPlayer(world, team, bot)
    local ent = fakeEnt((bot and "bot" or "human") .. world.nextId)
    world.entries[#world.entries + 1] = { ent = ent, team = team, bot = bot, id = world.nextId }
    world.nextId = world.nextId + 1
    return ent
end

---@param world PW.Test.BotsWorld
---@param ent any
local function removePlayer(world, ent)
    for i, entry in ipairs(world.entries) do
        if entry.ent == ent then
            table.remove(world.entries, i)
            return
        end
    end
end

---@param world PW.Test.BotsWorld
---@return integer?
local function smallest(world)
    ---@type table<integer, integer>
    local counts = {}
    for _, entry in ipairs(world.entries) do counts[entry.team] = (counts[entry.team] or 0) + 1 end
    ---@type integer?
    local best = nil
    for team = 1, world.n do
        if best == nil or (counts[team] or 0) < (counts[best] or 0) then best = team end
    end
    return best
end

---@param world PW.Test.BotsWorld
---@return PW.BotsStore
local function storeFor(world)
    return must(lib()._NewStore)({
        log = function(message) world.logs[#world.logs + 1] = message end,
        singlePlayer = function() return world.sp end,
        maxPlayers = function() return world.max end,
        players = function() return { unpack(world.entries) } end,
        create = function(name)
            world.created[#world.created + 1] = name
            if world.createResult ~= nil then return world.createResult(name) end
            return addPlayer(world, unassigned, true)
        end,
        kick = function(ent, _) world.kicked[#world.kicked + 1] = ent end,
        phase = function() return world.phase end,
        fill = function() return world.fill end,
        generating = function() return world.generating end,
        teams = function() return world.n end,
        smallest = function() return smallest(world) end,
        clock = function() return 0 end
    })
end

---A pending file as the new map hands it to PW_PendingMatchApplied, with the given bot target.
---@param bots integer
---@return PW.PendingMatch
local function pendingWith(bots)
    return { v = 1, map = "gm_test", mode = "tdm", settings = {}, bots = bots, teams = {}, createdAt = 0,
        mapChangeCount = 0 }
end

---@param world PW.Test.BotsWorld
---@param ent any
---@return PW.BotsEntry?
local function entryOf(world, ent)
    for _, entry in ipairs(world.entries) do
        if entry.ent == ent then return entry end
    end
    return nil
end

---@param world PW.Test.BotsWorld
---@param count integer
---@param team integer
---@return any[]
local function addBots(world, count, team)
    ---@type any[]
    local list = {}
    for i = 1, count do list[i] = addPlayer(world, team, true) end
    return list
end

return {
    groupName = "PW bots manager",
    beforeAll = function(state)
        -- One real bot through the engine defaults of a store: only bots this store created are its players.
        ---@type PW.BotsStore
        local store
        store = must(lib()._NewStore)({
            players = function()
                ---@type PW.BotsEntry[]
                local list = {}
                for bot in pairs(store.boards) do
                    if IsValid(bot) then list[#list + 1] = { ent = bot, team = 0, bot = true, id = bot:UserID() } end
                end
                return list
            end,
            phase = function() return "LIVE" end,
            fill = function() return state.config.fill --[[@as integer]] end,
            maxPlayers = function() return 64 end,
            singlePlayer = function() return false end,
            generating = function() return false end,
            teams = function() return 0 end
        })
        -- a shared table: the cases get their own state (reads fall back to this one), so they change config
        state.config = { fill = 1 }
        state.store = store
        state.created = { must(lib()._Step)(store) }
        state.bot = next(store.boards)
    end,
    afterAll = function(state)
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then bot:Kick("PW bots manager test finished") end
    end,
    cases = {
        {
            name = "Mandatory (T-5.1): quota arithmetic: fill minus humans, humans join and leave",
            func = function()
                local quota = lib()._Quota
                expect(quota({ fill = 8, maxPlayers = 16, humans = 1 })).to.equal(7)
                expect(quota({ fill = 8, maxPlayers = 16, humans = 3 })).to.equal(5)
                expect(quota({ fill = 8, maxPlayers = 16, humans = 2 })).to.equal(6)
                expect(quota({ fill = 8, maxPlayers = 16, humans = 8 })).to.equal(0)
                expect(quota({ fill = 8, maxPlayers = 16, humans = 10 })).to.equal(0)
                expect(quota({ fill = 0, maxPlayers = 16, humans = 1 })).to.equal(0)
            end
        },
        {
            name = "Mandatory (T-5.1): quota arithmetic: capped by maxplayers with one slot free for a joining human",
            func = function()
                local quota = lib()._Quota
                expect(lib()._FreeSlots).to.equal(1)
                expect(quota({ fill = 12, maxPlayers = 12, humans = 1 })).to.equal(10)
                expect(quota({ fill = 24, maxPlayers = 12, humans = 2 })).to.equal(9)
                expect(quota({ fill = 24, maxPlayers = 12, humans = 11 })).to.equal(0)
                expect(quota({ fill = 24, maxPlayers = 12, humans = 12 })).to.equal(0)
                expect(quota({ fill = 12, maxPlayers = 1, humans = 1 })).to.equal(0)
                expect(quota({ fill = 12, maxPlayers = 12, humans = 1, freeSlots = 0 })).to.equal(11)
            end
        },
        {
            name = "Mandatory (T-5.1): quota recomputed by the steps when humans join and leave",
            func = function()
                local world = newWorld({ fill = 6, max = 12, n = 0 })
                addPlayer(world, unassigned, false)
                local store = storeFor(world)
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 5, 0 })
                expect(#world.created).to.equal(5)
                local friend = addPlayer(world, unassigned, false)
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 1 })
                expect(#world.kicked).to.equal(1)
                removePlayer(world, world.kicked[1])
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 0 })
                removePlayer(world, friend)
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 1, 0 })
                expect(#world.created).to.equal(6)
            end
        },
        {
            name = "Mandatory (T-5.1): a human joining replaces a bot of the smaller team",
            func = function()
                -- fill 9: host + 3 bots in team 1 (4), 5 bots in team 2. The joining human has no team yet, so the
                -- smaller team is 1: the teams module will place the human there, and a bot of team 1 goes.
                local world = newWorld({ fill = 9, max = 12, n = 2 })
                addPlayer(world, 1, false)
                addBots(world, 3, 1)
                addBots(world, 5, 2)
                local store = storeFor(world)
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 0 })
                addPlayer(world, unassigned, false)
                expect({ must(lib()._OnHumanJoined)(store) }).to.deepEqual({ 0, 1 })
                expect(#world.kicked).to.equal(1)
                expect(must(entryOf(world, world.kicked[1])).team).to.equal(1)
                expect(must(entryOf(world, world.kicked[1])).bot).to.beTrue()
                expect(#world.created).to.equal(0)
            end
        },
        {
            name = "A join-in-progress spectator is not a human of the quota: no bot is kicked until they play",
            func = function()
                local world = newWorld({ fill = 9, max = 12, n = 2 })
                addPlayer(world, 1, false)
                addBots(world, 3, 1)
                addBots(world, 5, 2)
                local spectator = addPlayer(world, 1002, false)
                must(entryOf(world, spectator)).spectating = true
                local store = storeFor(world)
                expect({ must(lib()._OnHumanJoined)(store) }).to.deepEqual({ 0, 0 })
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 0 })
                expect(#world.kicked).to.equal(0)
                expect(must(lib().Target)(store)).to.equal(8)
                must(entryOf(world, spectator)).spectating = false
                expect(must(lib().Target)(store)).to.equal(7)
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 1 })
            end
        },
        {
            name = "_PickKick: prefer a bot of the given team, else the largest team, the newest bot first",
            func = function()
                ---@type PW.BotsEntry[]
                local entries = {
                    { ent = "h", team = 1, bot = false, id = 1 }, { ent = "a", team = 1, bot = true, id = 2 },
                    { ent = "b", team = 2, bot = true, id = 3 }, { ent = "c", team = 2, bot = true, id = 4 },
                    { ent = "d", team = 1, bot = true, id = 5 }
                }
                expect(lib()._PickKick(entries, 2, 1)).to.equal(5)
                expect(lib()._PickKick(entries, 2, 2)).to.equal(4)
                -- team 1 has 3 players (human included), team 2 has 2: the largest is team 1
                expect(lib()._PickKick(entries, 2, nil)).to.equal(5)
                expect(lib()._PickKick(entries, 0, nil)).to.equal(5)
                expect(lib()._PickKick({ entries[1] }, 2, 1)).to.beNil()
            end
        },
        {
            name = "_Plan: creates the missing bots, kicks the extras one at a time keeping the teams balanced",
            func = function()
                ---@type PW.BotsEntry[]
                local entries = {
                    { ent = "a", team = 1, bot = true, id = 1 }, { ent = "b", team = 1, bot = true, id = 2 },
                    { ent = "c", team = 1, bot = true, id = 3 }, { ent = "d", team = 2, bot = true, id = 4 }
                }
                expect(lib()._Plan(6, entries, 2, nil)).to.deepEqual({ create = 2, kick = {} })
                expect(lib()._Plan(2, entries, 2, nil)).to.deepEqual({ create = 0, kick = { "c", "b" } })
                expect(lib()._Plan(3, entries, 2, 2)).to.deepEqual({ create = 0, kick = { "d" } })
            end
        },
        {
            name = "Mandatory (T-5.1): reconciliation after a map change: extras kicked, survivors get a blackboard",
            func = function()
                local world = newWorld({ phase = "PREMATCH", fill = 12, max = 12, n = 0 })
                addPlayer(world, unassigned, false)
                local survivors = addBots(world, 5, unassigned)
                local store = storeFor(world)
                local pending = pendingWith(3)
                expect({ must(lib()._OnPendingApplied)(store, pending) }).to.deepEqual({ 0, 2 })
                expect(world.kicked).to.deepEqual({ survivors[5], survivors[4] })
                for i = 1, 3 do expect(must(store.boards[survivors[i]]).bot).to.equal(survivors[i]) end
                expect(store.boards[survivors[5]]).to.beNil()
                -- the file's target holds through PREMATCH (fill 12 would ask for 10)
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 0 })
                must(lib()._OnPhase)(store, "LIVE")
                expect(store.pinned).to.beNil()
            end
        },
        {
            name = "Mandatory (T-5.1): reconciliation after a map change: missing bots created, a NULL handled",
            func = function()
                local world = newWorld({ phase = "PREMATCH", fill = 12, max = 12, n = 0 })
                addPlayer(world, unassigned, false)
                addBots(world, 1, unassigned)
                local calls = 0
                world.createResult = function()
                    calls = calls + 1
                    if calls == 2 or calls == 3 then return NULL end
                    return addPlayer(world, unassigned, true)
                end
                local store = storeFor(world)
                expect({ must(lib()._OnPendingApplied)(store, pendingWith(4)) })
                    .to.deepEqual({ 1, 0 })
                expect(#world.logs).to.equal(1)
                expect(string.find(world.logs[1], "could not create a bot", 1, true) ~= nil).to.beTrue()
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 0 })
                expect(#world.logs).to.equal(1)
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 2, 0 })
                local boards = 0
                for _ in pairs(store.boards) do boards = boards + 1 end
                expect(boards).to.equal(4)
            end
        },
        {
            name = "Mandatory (T-5.1): refusal in Singleplayer: one log line, never creates or kicks",
            func = function()
                local world = newWorld({ sp = true, max = 1 })
                addPlayer(world, unassigned, false)
                addBots(world, 2, unassigned)
                local store = storeFor(world)
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 0 })
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 0 })
                expect({ must(lib()._OnPendingApplied)(store, pendingWith(0)) })
                    .to.deepEqual({ 0, 0 })
                must(lib()._OnPhase)(store, "LOBBY")
                expect(#world.created).to.equal(0)
                expect(#world.kicked).to.equal(0)
                expect(#world.logs).to.equal(1)
                expect(string.find(world.logs[1], "Singleplayer", 1, true) ~= nil).to.beTrue()
                expect(lib()._Gate({ singlePlayer = true, paused = false, generating = false, phase = "LIVE" }))
                    .to.equal("singleplayer")
            end
        },
        {
            name = "_Gate: idle during tests, navmesh generation and outside PREMATCH..VOTE",
            func = function()
                local gate = lib()._Gate
                local facts = { singlePlayer = false, paused = false, generating = false, phase = "LIVE" }
                expect(gate(facts)).to.beNil()
                for _, phase in ipairs({ "PREMATCH", "POSTMATCH", "VOTE" }) do
                    facts.phase = phase
                    expect(gate(facts)).to.beNil()
                end
                facts.phase = "LOBBY"
                expect(gate(facts)).to.equal("phase")
                facts.phase, facts.generating = "LIVE", true
                expect(gate(facts)).to.equal("navgen")
                facts.paused = true
                expect(gate(facts)).to.equal("tests")
            end
        },
        {
            name = "Entering LOBBY kicks every bot; navmesh generation and a test run pause the manager",
            func = function()
                local world = newWorld({ phase = "LIVE", fill = 4, n = 0 })
                addPlayer(world, unassigned, false)
                local store = storeFor(world)
                world.generating = true
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 0 })
                world.generating = false
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 3, 0 })
                must(lib()._SetTestRun)(store, true)
                world.phase = "LOBBY"
                must(lib()._OnPhase)(store, "LOBBY")
                expect(#world.kicked).to.equal(0)
                must(lib()._SetTestRun)(store, false)
                expect(store.paused).to.beFalse()
                must(lib()._OnPhase)(store, "LOBBY")
                expect(#world.kicked).to.equal(3)
                expect(next(store.boards)).to.beNil()
            end
        },
        {
            name = "A test run that ends outside LOBBY keeps the manager paused until the next LOBBY",
            func = function()
                local world = newWorld({ phase = "LIVE", fill = 4, n = 0 })
                local store = storeFor(world)
                must(lib()._SetTestRun)(store, true)
                must(lib()._SetTestRun)(store, false)
                expect(store.paused).to.beTrue()
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 0 })
                world.phase = "LOBBY"
                must(lib()._OnPhase)(store, "LOBBY")
                expect(store.paused).to.beFalse()
            end
        },
        {
            name = "The real manager is paused while GLuaTest runs",
            func = function()
                expect(PW._BotsManager.paused).to.beTrue()
            end
        },
        {
            name = "PendingTarget: the quota with the file's bots.fill and the humans connected now",
            func = function()
                local humans = #player.GetHumans()
                local expected = lib()._Quota({ fill = 5, maxPlayers = game.MaxPlayers(), humans = humans })
                expect(must(lib().PendingTarget)({ ["bots.fill"] = 5 })).to.equal(expected)
                expect(must(PW.MapChange)._NewStore().bots({ ["bots.fill"] = 5 })).to.equal(expected)
            end
        },
        {
            name = "Engine glue: a real bot from player.CreateNextBot with a blackboard",
            func = function(state)
                expect(state.created).to.deepEqual({ 1, 0 })
                local bot = must(state.bot) --[[@as Player]]
                expect(bot).to.beValid()
                expect(bot:IsBot()).to.beTrue()
                local store = state.store --[[@as PW.BotsStore]]
                expect(must(store.boards[bot]).bot).to.equal(bot)
                expect(must(PW.Bot).Get(bot)).to.beNil()
                expect(must(PW.Bot).Get(must(player.GetHumans()[1]))).to.beNil()
            end
        },
        {
            name = "Engine glue: a real bot kicked with Player:Kick leaves the server",
            async = true,
            timeout = 3,
            func = function(state)
                local bot = must(state.bot) --[[@as Player]]
                local store = state.store --[[@as PW.BotsStore]]
                state.config.fill = 0
                expect({ must(lib()._Step)(store) }).to.deepEqual({ 0, 1 })
                expect(store.boards[bot]).to.beNil()
                timer.Simple(1, function()
                    expect(IsValid(bot)).to.beFalse()
                    done()
                end)
            end
        }
    }
}
