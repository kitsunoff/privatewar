-- T-5.4 bots debug overlay (TASKS.md, "Mandatory test cases" T-5.4; 07-bots.md d.11). The snapshot, its wire format,
-- the recipient filter and the send step are pure (PW.BotDebug over plain data and injected dependencies), so the
-- cases run them with fakes. One real bot checks the privilege against a real Player. Drawing is a checkpoint.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotDebugLib
local function lib()
    return must(PW.BotDebug)
end

---A target that is valid and has no class: BuildEntry only asks IsValid and the namer.
---@return Entity
local function fakeTarget()
    return setmetatable({}, { __index = { IsValid = function() return true end } }) --[[@as Entity]]
end

---@param count integer
---@return Vector[]
local function waypoints(count)
    ---@type Vector[]
    local points = {}
    for i = 1, count do points[i] = Vector(i * 10, -i * 5, 3) end
    return points
end

---@return PW.BotBoard
local function board()
    ---@type table<string, any>
    local out = {
        behavior = { id = "fight", reason = "enemy visible" },
        target = fakeTarget(),
        goal = { point = Vector(100.4, -200.6, 8), radius = 32, priority = "tactical", status = "moving", since = 0 },
        path = { points = waypoints(5), index = 2, partial = false }
    }
    return out --[[@as PW.BotBoard]]
end

---Records writes, replays them as reads.
---@return PW.BotDebugWriter, PW.BotDebugReader, any[]
local function tape()
    ---@type any[]
    local items = {}
    local at = 0
    local function put(value) items[#items + 1] = value end
    local function take()
        at = at + 1
        return items[at]
    end
    local writer = {
        uint = function(value) put(value) end,
        int = function(value) put(value) end,
        string = put,
        bool = put
    }
    local reader = { uint = take, int = take, string = take, bool = take }
    return writer, reader, items
end

---@param over? table<string, any>
---@return PW.BotDebugDeps, table
local function deps(over)
    local calls = { boardOf = 0, send = 0, counters = 0 }
    ---@type PW.BotDebugDeps
    local out = {
        enabled = function() return true end,
        players = function() return {} end,
        can = function() return true end,
        bots = function() return {} end,
        boardOf = function()
            calls.boardOf = calls.boardOf + 1
            return board()
        end,
        nameOf = function() return "Victim" end,
        counters = function()
            calls.counters = calls.counters + 1
            return nil
        end,
        send = function() calls.send = calls.send + 1 end
    }
    for key, value in pairs(over or {}) do (out --[[@as table<string, any>]])[key] = value end
    return out, calls
end

return {
    groupName = "PW bots debug overlay",
    beforeAll = function(state)
        local bot = player.CreateNextBot("PW debug test") --[[@as Player?]]
        state.bot = bot
    end,
    afterAll = function(state)
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then bot:Kick("PW bots debug test finished") end
    end,
    cases = {
        {
            name = "Mandatory (T-5.4): debug data (behaviour, reason, goal) is produced only when pw_bot_debug is on",
            func = function()
                local fake, calls = deps({ bots = function() return {} end })
                expect(lib().Collect(false, fake)).to.beNil()
                expect(calls.boardOf).to.equal(0)
                expect(calls.counters).to.equal(0)
                local entry = lib().BuildEntry(5, "Alpha", board(), function() return "Victim" end)
                expect(entry.behavior).to.equal("fight")
                expect(entry.reason).to.equal("enemy visible")
                expect(entry.target).to.equal("Victim")
                expect(must(entry.goal).status).to.equal("moving")
            end
        },
        {
            name = "Mandatory (T-5.4): the sender builds and sends nothing while pw_bot_debug is off",
            func = function()
                local sent = 0
                local fake, calls = deps({
                    enabled = function() return false end,
                    players = function() return { must(player.GetBots()[1]) } end,
                    bots = function() return player.GetBots() end,
                    send = function() sent = sent + 1 end
                })
                expect(lib().Step({ nextAt = 0 }, 10, fake)).to.beFalse()
                expect(sent).to.equal(0)
                expect(calls.boardOf).to.equal(0)
                expect(calls.counters).to.equal(0)
            end
        },
        {
            name = "The ConVar pw_bot_debug exists and is off by default",
            func = function()
                local convar = must(GetConVar("pw_bot_debug"))
                expect(convar:GetDefault()).to.equal("0")
                expect(must(lib().Enabled)()).to.equal(convar:GetBool())
            end
        },
        {
            name = "Mandatory (T-5.4): the snapshot encode/decode round-trips",
            func = function()
                local entry = lib().BuildEntry(7, "Alpha", board(), function() return "Victim" end)
                local bare = lib().BuildEntry(9, "Bravo", nil, function() return "" end)
                ---@type PW.BotDebugSnapshot
                local snapshot = { perf = "bots 2  tick 0.40 ms", bots = { entry, bare } }
                local writer, reader = tape()
                lib().Encode(snapshot, writer)
                expect(lib().Decode(reader)).to.deepEqual(snapshot)
            end
        },
        {
            name = "The path on the wire is the remaining waypoints, rounded, capped at MaxPath",
            func = function()
                local entry = lib().BuildEntry(7, "Alpha", board(), function() return "Victim" end)
                expect(entry.path).to.deepEqual({ 20, -10, 3, 30, -15, 3, 40, -20, 3, 50, -25, 3 })
                expect(must(entry.goal).x).to.equal(100)
                expect(must(entry.goal).y).to.equal(-201)
                local long = board()
                long.path = { points = waypoints(100), index = 1, partial = true }
                local capped = lib().BuildEntry(7, "Alpha", long, function() return "" end)
                expect(#capped.path).to.equal(lib().MaxPath * 3)
            end
        },
        {
            name = "A bot without a blackboard or without a goal gives an empty entry, not an error",
            func = function()
                local bare = lib().BuildEntry(3, "Bravo", nil, function() return "" end)
                expect(bare.behavior).to.equal("")
                expect(bare.goal).to.beNil()
                expect(#bare.path).to.equal(0)
                local noGoal = board()
                noGoal.goal, noGoal.path, noGoal.target = nil, nil, nil
                local entry = lib().BuildEntry(3, "Bravo", noGoal, function() return "x" end)
                expect(entry.goal).to.beNil()
                expect(entry.target).to.equal("")
            end
        },
        {
            name = "The wire format uses explicit writes only: no table is written",
            func = function()
                local writer, _, items = tape()
                local entry = lib().BuildEntry(7, "Alpha", board(), function() return "Victim" end)
                lib().Encode({ perf = "p", bots = { entry } }, writer)
                for _, item in ipairs(items) do expect(istable(item)).to.beFalse() end
            end
        },
        {
            name = "Mandatory (T-5.4): the snapshot is sent only to privileged clients",
            func = function(state)
                local bot = must(state.bot --[[@as Player?]])
                local admin = setmetatable({}, { __index = { IsValid = function() return true end } }) --[[@as Player]]
                local plain = { bot, admin }
                local chosen = lib().Recipients(plain, function(ply) return ply == admin end)
                expect(#chosen).to.equal(1)
                expect(chosen[1]).to.equal(admin)
                -- The real privilege: a bot is not a superadmin.
                expect(PW.Can(bot, lib().Privilege)).to.beFalse()
                expect(#lib().Recipients({ bot }, function(ply) return PW.Can(ply, lib().Privilege) end)).to.equal(0)
            end
        },
        {
            name = "The sender sends once per interval to the privileged only, and not at all without any",
            func = function()
                local admin = setmetatable({}, { __index = { IsValid = function() return true end } }) --[[@as Player]]
                local guest = setmetatable({}, { __index = { IsValid = function() return true end } }) --[[@as Player]]
                ---@type Player[][]
                local sentTo = {}
                local fake = deps({
                    players = function() return { admin, guest } end,
                    can = function(ply) return ply == admin end,
                    bots = function() return { must(player.GetBots()[1]) } end,
                    send = function(recipients) sentTo[#sentTo + 1] = recipients end
                })
                local sender = { nextAt = 0 }
                expect(lib().Step(sender, 10, fake)).to.beTrue()
                expect(lib().Step(sender, 10.1, fake)).to.beFalse()
                expect(lib().Step(sender, 10 + lib().Interval, fake)).to.beTrue()
                expect(#sentTo).to.equal(2)
                expect(#sentTo[1]).to.equal(1)
                expect(sentTo[1][1]).to.equal(admin)
                local none = deps({ players = function() return { guest } end, can = function() return false end })
                expect(lib().Step({ nextAt = 0 }, 10, none)).to.beFalse()
            end
        },
        {
            name = "The perf line shows the scheduler counters and survives a missing scheduler",
            func = function()
                expect(lib().PerfLine(nil)).to.equal("bots: no scheduler")
                local line = lib().PerfLine(must(PW.BotScheduler).Default.GetCounters())
                expect(string.find(line, "tick", 1, true)).to.exist()
            end
        }
    }
}
