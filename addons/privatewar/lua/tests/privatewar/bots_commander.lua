-- T-5.11 bot commander (TASKS.md "Mandatory test cases" T-5.11; 07-bots.md d.9, d.14). Pure cases over plain data:
-- the assignment (want, weight, the Domination defender cap, anti-dither, rebalance, determinism), the hunt slots
-- (at most 2 per human, budget re-roll, a stalled hunter replaced) and the hunt filter the hunt behaviour applies.
-- The mode cases call MODE:BotObjectives of dom and kc over fixture flags and tags. No bots are created.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotCommanderLib
local function lib()
    return must(PW.BotCommander)
end

---@param id string
---@param action string
---@param pos Vector
---@param weight number
---@param want integer
---@param radius? number
---@return PW.BotObjective
local function objective(id, action, pos, weight, want, radius)
    return { id = id, action = action, pos = pos, weight = weight, want = want, radius = radius or 160 }
end

---count bots with ids 1..count at pos (default the origin).
---@param count integer
---@param pos? Vector
---@return PW.CommanderBot[]
local function bots(count, pos)
    ---@type PW.CommanderBot[]
    local list = {}
    for i = 1, count do list[i] = { id = i, pos = pos or Vector(0, 0, 0), team = 1 } end
    return list
end

---How many orders go to each objective id (and to each action under "action:<name>").
---@param orders table<integer, PW.BotOrder>
---@return table<string, integer>
local function tally(orders)
    ---@type table<string, integer>
    local out = {}
    for _, order in pairs(orders) do
        out[order.id] = (out[order.id] or 0) + 1
        out["action:" .. order.type] = (out["action:" .. order.type] or 0) + 1
    end
    return out
end

---@param objectiveRef PW.BotObjective
---@param since number
---@return PW.BotOrder
local function orderOf(objectiveRef, since)
    return { objective = objectiveRef, type = objectiveRef.action, id = objectiveRef.id, priority = objectiveRef.weight,
        since = since }
end

---A fixed random source.
---@param value number
---@return fun(): number
local function fixed(value)
    return function() return value end
end

---@param map table<integer, integer>
---@return integer
local function size(map)
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
end

local human = { id = 100, pos = Vector(3000, 0, 0), team = 2 }

return {
    groupName = "PW bots commander",
    cases = {
        {
            name = "Mandatory (T-5.11) assignment respects want and weight",
            func = function()
                local heavy = objective("flag_A", "capture", Vector(1000, 0, 0), 0.9, 2)
                local light = objective("flag_B", "capture", Vector(-1000, 0, 0), 0.4, 1)
                local unwanted = objective("flag_C", "capture", Vector(0, 1000, 0), 0, 3)
                local count = tally(lib().Assign(bots(4), { light, unwanted, heavy }, {}, 0))
                expect(count.flag_A).to.equal(2)
                expect(count.flag_B).to.equal(1)
                expect(count.flag_C).to.beNil()
                local few = tally(lib().Assign(bots(2), { light, heavy }, {}, 0))
                expect(few.flag_A).to.equal(2)
                expect(few.flag_B).to.beNil()
            end
        },
        {
            name = "Assignment: weight is traded against distance, the nearer bot takes the slot",
            func = function()
                local list = bots(2)
                list[2].pos = Vector(900, 0, 0)
                local orders = lib().Assign(list, { objective("tag_1", "collect", Vector(1000, 0, 0), 0.6, 1) }, {}, 5)
                expect(must(orders[2]).id).to.equal("tag_1")
                expect(must(orders[2]).since).to.equal(5)
                expect(orders[1]).to.beNil()
            end
        },
        {
            name = "Mandatory (T-5.11) Domination defenders are at most a third of the team",
            func = function()
                local list = bots(6)
                local objs = {
                    objective("flag_A", "defend", Vector(500, 0, 0), 0.9, 2),
                    objective("flag_B", "defend", Vector(0, 500, 0), 0.9, 2),
                    objective("flag_C", "defend", Vector(-500, 0, 0), 0.9, 2)
                }
                expect(tally(lib().Assign(list, objs, {}, 0))["action:defend"]).to.equal(2)
                local nine = tally(lib().Assign(bots(9), objs, {}, 0))
                expect(nine["action:defend"]).to.equal(3)
                ---@type table<integer, PW.BotOrder>
                local held = {}
                for i = 1, 4 do held[i] = orderOf(objs[(i % 3) + 1], 99) end
                local kept = tally(lib().Assign(list, objs, held, 100))
                expect(kept["action:defend"]).to.equal(2)
                expect(tally(lib().Assign(bots(2), objs, {}, 0))["action:defend"]).to.beNil()
            end
        },
        {
            name = "Mandatory (T-5.11) anti-dither: a bot capturing a flag is never reassigned",
            func = function()
                local flagB = objective("flag_B", "capture", Vector(0, 0, 0), 0.1, 1)
                local flagA = objective("flag_A", "capture", Vector(200, 0, 0), 1, 3)
                local list = bots(2, Vector(50, 0, 0))
                local current = { [1] = orderOf(flagB, 0), [2] = orderOf(flagB, 0) }
                local orders = lib().Assign(list, { flagA, flagB }, current, 500)
                expect(must(orders[1]).id).to.equal("flag_B")
                expect(must(orders[2]).id).to.equal("flag_B")
                expect(must(orders[1]).since).to.equal(0)
                local unwanted = objective("flag_B", "capture", Vector(0, 0, 0), 0.1, 0)
                local still = lib().Assign(bots(1, Vector(50, 0, 0)), { flagA, unwanted }, { [1] = orderOf(flagB, 0) },
                    500)
                expect(must(still[1]).id).to.equal("flag_B")
            end
        },
        {
            name = "Anti-dither: an order is held for Config.hold, then the better objective wins",
            func = function()
                local hold = lib().Config.hold
                local flagB = objective("flag_B", "capture", Vector(-2000, 0, 0), 0.5, 1)
                local flagA = objective("flag_A", "capture", Vector(300, 0, 0), 1, 1)
                local current = { [1] = orderOf(flagB, 100) }
                local early = lib().Assign(bots(1), { flagA, flagB }, current, 100 + hold - 1)
                expect(must(early[1]).id).to.equal("flag_B")
                expect(must(early[1]).since).to.equal(100)
                local late = lib().Assign(bots(1), { flagA, flagB }, current, 100 + hold + 1)
                expect(must(late[1]).id).to.equal("flag_A")
                expect(must(late[1]).since).to.equal(100 + hold + 1)
            end
        },
        {
            name = "Anti-dither: a changed action (our flag now) or a gone objective frees the bot at once",
            func = function()
                local capture = objective("flag_A", "capture", Vector(0, 0, 0), 0.6, 2)
                local defend = objective("flag_A", "defend", Vector(0, 0, 0), 0.3, 1)
                local other = objective("flag_B", "capture", Vector(800, 0, 0), 0.6, 2)
                local list = bots(3, Vector(0, 0, 0))
                local current = { [1] = orderOf(capture, 10), [2] = orderOf(capture, 10), [3] = orderOf(capture, 10) }
                local count = tally(lib().Assign(list, { defend, other }, current, 12))
                expect(count["action:defend"]).to.equal(1)
                expect(count.flag_B).to.equal(2)
                local gone = lib().Assign(bots(1), { other }, { [1] = orderOf(objective("tag_9", "collect",
                    Vector(0, 0, 0), 0.6, 1), 11) }, 12)
                expect(must(gone[1]).id).to.equal("flag_B")
            end
        },
        {
            name = "Rebalance: a dead bot's slot goes to a free bot, a joining bot gets an order",
            func = function()
                local flagA = objective("flag_A", "capture", Vector(1000, 0, 0), 0.9, 2)
                local flagB = objective("flag_B", "capture", Vector(-1000, 0, 0), 0.5, 1)
                local list = bots(4)
                local first = lib().Assign(list, { flagA, flagB }, {}, 0)
                expect(must(first[1]).id).to.equal("flag_A")
                expect(must(first[3]).id).to.equal("flag_B")
                expect(first[4]).to.beNil()
                ---@type PW.CommanderBot[]
                local alive = { list[2], list[3], list[4] }
                local after = lib().Assign(alive, { flagA, flagB }, first, 1)
                expect(must(after[4]).id).to.equal("flag_A")
                expect(tally(after).flag_A).to.equal(2)
                ---@type PW.CommanderBot[]
                local joined = { list[2], list[4], { id = 5, pos = Vector(0, 0, 0), team = 1 } }
                local rejoined = lib().Assign(joined, { flagA, flagB }, after, 2)
                expect(must(rejoined[5]).id).to.equal("flag_B")
                expect(tally(rejoined).flag_A).to.equal(2)
            end
        },
        {
            name = "Assignment is deterministic: ties go to the smaller objective id, then the smaller bot id",
            func = function()
                local objs = { objective("flag_B", "capture", Vector(1000, 0, 0), 0.5, 1),
                    objective("flag_A", "capture", Vector(-1000, 0, 0), 0.5, 1) }
                local orders = lib().Assign(bots(3), objs, {}, 0)
                expect(must(orders[1]).id).to.equal("flag_A")
                expect(must(orders[2]).id).to.equal("flag_B")
                expect(orders[3]).to.beNil()
                local again = lib().Assign(bots(3), objs, {}, 0)
                expect(must(again[1]).id).to.equal("flag_A")
                expect(must(again[2]).id).to.equal("flag_B")
            end
        },
        {
            name = "Assignment: a stationary personality prefers defend",
            func = function()
                local list = bots(3)
                list[3].stationary = true
                local objs = { objective("flag_A", "defend", Vector(1000, 0, 0), 0.5, 1),
                    objective("flag_B", "capture", Vector(-1000, 0, 0), 0.6, 2) }
                local orders = lib().Assign(list, objs, {}, 0)
                expect(must(orders[3]).id).to.equal("flag_A")
                expect(must(orders[1]).id).to.equal("flag_B")
            end
        },
        {
            name = "Mandatory (T-5.11) hunt slots: at most 2 bots hunt a human",
            func = function()
                local state = lib().NewHuntState()
                local hunters = lib().Hunt(state, { human }, bots(6), 0, { random = fixed(0.99) })
                expect(size(hunters)).to.equal(2)
                for _, target in pairs(hunters) do expect(target).to.equal(100) end
                local second = { id = 101, pos = Vector(-3000, 0, 0), team = 2 }
                local two = lib().Hunt(lib().NewHuntState(), { human, second }, bots(6), 0, { random = fixed(0.99) })
                ---@type table<integer, integer>
                local per = {}
                for _, target in pairs(two) do per[target] = (per[target] or 0) + 1 end
                expect(per[100]).to.equal(2)
                expect(per[101]).to.equal(2)
                local one = lib().Hunt(lib().NewHuntState(), { human }, bots(6), 0, { random = fixed(0) })
                expect(size(one)).to.equal(1)
                local wide = lib().Hunt(lib().NewHuntState(), { human }, bots(6), 0, { random = fixed(0.99), max = 3 })
                expect(size(wide)).to.equal(3)
            end
        },
        {
            name = "Hunt slots: the closest free enemy bot hunts; busy bots and teammates of the human do not",
            func = function()
                local list = bots(4)
                list[1].pos, list[1].busy = Vector(2900, 0, 0), true
                list[2].pos, list[2].team = Vector(2950, 0, 0), 2
                list[3].pos = Vector(2000, 0, 0)
                local hunters = lib().Hunt(lib().NewHuntState(), { human }, list, 0, { random = fixed(0) })
                expect(size(hunters)).to.equal(1)
                expect(hunters[3]).to.equal(100)
            end
        },
        {
            name = "Mandatory (T-5.11) hunt slots: a stalled hunter is replaced by another bot",
            func = function()
                local stall = lib().Config.huntStall
                local state = lib().NewHuntState()
                local list = bots(3)
                list[1].pos, list[2].pos, list[3].pos = Vector(1000, 0, 0), Vector(500, 0, 0), Vector(0, 0, 0)
                local opts = { random = fixed(0), rerollMin = 1000, rerollMax = 1000 }
                expect(lib().Hunt(state, { human }, list, 0, opts)[1]).to.equal(100)
                list[1].pos = Vector(1100, 0, 0)
                local mid = lib().Hunt(state, { human }, list, stall - 1, opts)
                expect(mid[1]).to.equal(100)
                local after = lib().Hunt(state, { human }, list, stall + 1, opts)
                expect(after[1]).to.beNil()
                expect(after[2]).to.equal(100)
                expect(size(after)).to.equal(1)
            end
        },
        {
            name = "Hunt slots: moving closer or a contact is progress, the hunter keeps its slot",
            func = function()
                local stall = lib().Config.huntStall
                local opts = { random = fixed(0), rerollMin = 1000, rerollMax = 1000 }
                local state = lib().NewHuntState()
                local list = bots(2)
                list[1].pos = Vector(1000, 0, 0)
                lib().Hunt(state, { human }, list, 0, opts)
                list[1].pos = Vector(2000, 0, 0)
                lib().Hunt(state, { human }, list, stall - 1, opts)
                expect(lib().Hunt(state, { human }, list, stall + 1, opts)[1]).to.equal(100)
                list[1].seen = { [100] = 2 * stall - 1 }
                expect(lib().Hunt(state, { human }, list, 2 * stall + 1, opts)[1]).to.equal(100)
            end
        },
        {
            name = "Hunt slots: the budget is re-rolled after its period, a hunter with an order leaves",
            func = function()
                local state = lib().NewHuntState()
                local value = 0
                local opts = { random = function() return value end, rerollMin = 30, rerollMax = 60 }
                local list = bots(4)
                expect(size(lib().Hunt(state, { human }, list, 0, opts))).to.equal(1)
                value = 0.99
                expect(size(lib().Hunt(state, { human }, list, 29, opts))).to.equal(1)
                expect(size(lib().Hunt(state, { human }, list, 31, opts))).to.equal(2)
                for _, bot in ipairs(list) do bot.busy = true end
                expect(size(lib().Hunt(state, { human }, list, 32, opts))).to.equal(0)
            end
        },
        {
            name = "HuntView: no slot hides the humans and the deaths, a slot shows its target, no commander = all",
            func = function()
                local humanEnt, otherHuman, botEnt = { name = "h1" }, { name = "h2" }, { name = "b" }
                ---@param ent any
                ---@return boolean
                local function isHuman(ent) return ent == humanEnt or ent == otherHuman end
                ---@type table<any, any>
                local raw = {}
                raw[humanEnt] = { pos = Vector(1, 0, 0), time = 1 }
                raw[otherHuman] = { pos = Vector(2, 0, 0), time = 1 }
                raw[botEnt] = { pos = Vector(3, 0, 0), time = 1 }
                local memory = raw --[[@as table<any, PW.BotContact>]]
                local deaths = { { pos = Vector(0, 0, 0), team = 1, time = 1 } }
                local board = { bot = botEnt } --[[@as PW.BotBoard]]
                local m, d = lib().HuntView(board, memory, deaths, isHuman)
                expect(m).to.equal(memory)
                expect(#d).to.equal(1)
                board.hunt = { since = 0 }
                m, d = lib().HuntView(board, memory, deaths, isHuman)
                expect(m[humanEnt]).to.beNil()
                expect(m[botEnt]).to.exist()
                expect(#d).to.equal(0)
                board.hunt = { since = 0, target = humanEnt --[[@as any]] }
                m, d = lib().HuntView(board, memory, deaths, isHuman)
                expect(m[humanEnt]).to.exist()
                expect(m[otherHuman]).to.beNil()
                expect(#d).to.equal(1)
            end
        },
        {
            name = "Modes: dom and kc answer BotObjectives from their flags and tags; tdm and ffa define none",
            func = function()
                local dom = must(PW.Modes.Get("dom")) --[[@as PW.DomMode]]
                local saved = dom._Flags
                dom._Flags = {
                    { letter = "A", pos = Vector(0, 0, 0), value = 100, owner = 1 },
                    { letter = "B", pos = Vector(500, 0, 0), value = 0, owner = 0 }
                }
                local ok, list = pcall(dom.BotObjectives, dom, 1)
                dom._Flags = saved
                expect(ok).to.beTrue()
                expect(#list).to.equal(2)
                expect(list[1].id).to.equal("flag_A")
                expect(list[1].action).to.equal("defend")
                expect(list[2].action).to.equal("capture")
                local kc = must(PW.Modes.Get("kc")) --[[@as PW.KCMode]]
                expect(#kc:BotObjectives(1)).to.equal(#must(PW.KCTags).GetAll())
                local tdm = must(PW.Modes.Get("tdm")) --[[@as table<string, any>]]
                local ffa = must(PW.Modes.Get("ffa")) --[[@as table<string, any>]]
                expect(tdm.BotObjectives).to.beNil()
                expect(ffa.BotObjectives).to.beNil()
            end
        },
        {
            name = "Module: the Think hook runs the commander pass",
            func = function()
                local module = must(must(PW.Modules).Get("bots_commander")) --[[@as PW.Module]]
                local think = (hook.GetTable() --[[@as table<string, table<any, function>>]])["Think"][module]
                expect(think).to.exist()
                expect(lib().Step).to.exist()
                lib().Step(CurTime())
            end
        }
    }
}
