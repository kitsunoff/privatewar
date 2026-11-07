-- T-5.10 MVP behaviours, objective and roam buckets (TASKS.md "Mandatory test cases" T-5.10; 07-bots.md d.13, d.14):
-- objective, use_streak (objective bucket), hunt, camp (roam bucket). Every behaviour has a case "chosen when it
-- should be" and one "not chosen when it should not be"; they run the real behaviour files through the brain's Think
-- with fixture facts (ctx._api.facts), a fake goal API and a fixed random source. The pure helpers of the module
-- bots_objectives are checked directly. One real bot (beforeAll, kicked in afterAll) runs the smoke case: on
-- gm_construct, with the Domination flags of the map data spawned, the brain sends it toward a flag.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotObjectivesLib
local function obj()
    return must(PW.BotObjectives)
end

---@return PW.BotBrainLib
local function brain()
    return must(PW.BotBrain)
end

local mine = { "objective", "use_streak", "hunt", "camp", "idle" }

---The real behaviours of this group plus idle.
---@param ids string[]?
---@return PW.BotBehavior[]
local function behaviors(ids)
    ---@type PW.BotBehavior[]
    local list = {}
    for _, id in ipairs(ids or mine) do
        list[#list + 1] = must(must(PW.BotBehaviors).Get(id)) --[[@as PW.BotBehavior]]
    end
    return list
end

---Facts with defaults: a bot at the origin of team 1 in TDM, nothing around.
---@param over table<string, any>?
---@return PW.BotFacts
local function facts(over)
    ---@type table<string, any>
    local f = { pos = Vector(0, 0, 0), team = 1, mode = "tdm", objectives = {}, mates = {}, deaths = {},
        candidates = {}, stationary = false, teamwork = 1 }
    for k, v in pairs(over or {}) do f[k] = v end
    return f --[[@as PW.BotFacts]]
end

---@class PW.TestObjEnv: PW.BotBrainEnv
---@field goals { point: Vector, radius: number, priority: string }[]
---@field used string[]
---@field rolls number[]

---A brain environment over the real behaviours with fixture facts, a recording goal API and a fixed random source
---(roll is the value every random() returns; the brain's own pick uses 0.5).
---@param f PW.BotFacts
---@param board table<string, any>?
---@param roll number?
---@return PW.TestObjEnv
local function newEnv(f, board, roll)
    ---@type table<string, any>
    local b = { bot = "bot", team = f.team }
    for k, v in pairs(board or {}) do b[k] = v end
    ---@type { point: Vector, radius: number, priority: string }[]
    local goals = {}
    ---@type string[]
    local used = {}
    local env = { bot = "bot", board = b, behaviors = behaviors(), mode = f.mode, goals = goals, used = used }
    env.random = function() return 0.5 end
    env.api = {
        facts = function() return f end,
        random = function() return roll or 0.5 end,
        setGoal = function(_, point, radius, priority)
            local held, rank = b.goal, must(PW.BotGoal).PriorityValue
            if held ~= nil and held.status == "moving" and (rank(priority) or 0) < (rank(held.priority) or 0) then
                return false, "moving"
            end
            goals[#goals + 1] = { point = point, radius = radius, priority = priority }
            b.goal = { point = point, radius = radius, priority = priority, status = "moving", since = 0 }
            return true, "moving"
        end,
        clearGoal = function() b.goal = nil end,
        useStreak = function(_, id)
            used[#used + 1] = id
            return true
        end
    }
    return env --[[@as PW.TestObjEnv]]
end

---Runs one brain tick and returns the running behaviour id ("-" for none).
---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param now number
---@return string
local function think(state, env, now)
    brain().Think(state, env, now)
    local top = state.stack[#state.stack]
    return top ~= nil and top.id or "-"
end

---@return PW.BotGoal
local function goalOf(env)
    return must(env.board.goal)
end

---@param id string
---@param pos Vector
---@param action string
---@param weight number?
---@return PW.BotObjective
local function objective(id, pos, action, weight)
    return { id = id, pos = pos, radius = 160, action = action, weight = weight or 0.6, want = 2 }
end

---A contact the bot lost (heard or seen earlier, not visible now).
---@param pos Vector
---@param time number
---@return PW.BotContact
local function lostContact(pos, time)
    return { ent = "enemy" --[[@as any]], pos = pos, vel = Vector(0, 0, 0), time = time, visible = false,
        source = "gunfire" }
end

local ring = { Vector(1200, 0, 0), Vector(0, 1200, 0), Vector(-1200, 0, 0), Vector(0, -1200, 0) }

return {
    groupName = "PW bots behaviours objective",
    beforeEach = function(state)
        state.callLog = PW._Call.log
        rawset(PW._Call, "log", function() end)
    end,
    afterEach = function(state)
        rawset(PW._Call, "log", state.callLog)
    end,
    beforeAll = function(state)
        if game.GetMap() ~= "gm_construct" then return end
        local bot = player.CreateNextBot("PW objective test") --[[@as Player?]]
        state.bot = bot
        if bot ~= nil and IsValid(bot) then
            bot:SetTeam(must(PW.MatchRules).FreeTeam)
            bot:Spawn()
        end
    end,
    afterAll = function(state)
        timer.Remove("PW.BotObjectiveSmoke")
        must(must(PW.DomFlags).RemoveAll)()
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then
            must(PW.BotGoal)._Drop(bot)
            must(PW.BotInput).SetScripted(bot, nil)
            bot:Kick("PW bots objective test finished")
        end
    end,
    cases = {
        {
            name = "Mandatory (T-5.10) objective chosen: Domination without an order captures the best flag",
            func = function()
                local flag = objective("flag_A", Vector(900, 0, 0), "capture")
                local env = newEnv(facts({ mode = "dom", objectives = { flag }, candidates = ring }))
                local state = brain().NewState()
                expect(think(state, env, 0)).to.equal("objective")
                expect(goalOf(env).priority).to.equal("objective")
                expect(goalOf(env).point:Distance(flag.pos) < 1).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.10) objective chosen: the commander's order wins over the local pick",
            func = function()
                local near = objective("flag_A", Vector(300, 0, 0), "capture", 1)
                local ordered = objective("flag_C", Vector(-2000, 0, 0), "capture", 0.2)
                local order = { objective = ordered, type = "defend", since = 0 }
                local env = newEnv(facts({ mode = "dom", objectives = { near } }), { order = order })
                local state = brain().NewState()
                expect(think(state, env, 0)).to.equal("objective")
                local goal = goalOf(env)
                expect(goal.priority).to.equal("guard")
                expect(goal.point:Distance(ordered.pos) <= ordered.radius * 1.5 + 1).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.10) objective not chosen: TDM without objectives or an order hunts instead",
            func = function()
                local env = newEnv(facts({ candidates = ring }))
                local state = brain().NewState()
                expect(think(state, env, 0)).to.equal("hunt")
                expect(goalOf(env).priority).to.equal("hunt")
            end
        },
        {
            name = "Objective: a flag taken while the bot walks to it turns the capture goal into a guard goal",
            func = function()
                local f = facts({ mode = "dom", objectives = { objective("flag_A", Vector(900, 0, 0), "capture") } })
                local env = newEnv(f)
                local state = brain().NewState()
                think(state, env, 0)
                expect(goalOf(env).priority).to.equal("objective")
                f.objectives = { objective("flag_A", Vector(900, 0, 0), "defend", 0.3) }
                think(state, env, 0.6)
                expect(goalOf(env).priority).to.equal("guard")
            end
        },
        {
            name = "Objective: a collected Kill Confirmed tag ends the behaviour",
            func = function()
                local tag = objective("tag_7", Vector(500, 0, 0), "collect")
                local f = facts({ mode = "kc", objectives = { tag } })
                local env = newEnv(f)
                local state = brain().NewState()
                expect(think(state, env, 0)).to.equal("objective")
                expect(goalOf(env).priority).to.equal("objective")
                f.objectives = {}
                think(state, env, 0.1)
                expect(env.board.behavior == nil or env.board.behavior.id ~= "objective").to.beTrue()
            end
        },
        {
            name = "Objective, pure: Domination fallback follows 07 d.14 (capture, defend, ours under capture)",
            func = function()
                local flags = {
                    { letter = "A", pos = Vector(0, 0, 0), owner = 0, value = 0 },
                    { letter = "B", pos = Vector(500, 0, 0), owner = 1, value = 100 },
                    { letter = "C", pos = Vector(1000, 0, 0), owner = 1, value = 40 }
                }
                local list = obj().DomObjectives(flags, 1)
                expect(#list).to.equal(3)
                expect(list[1].action).to.equal("capture")
                expect(list[2].action).to.equal("defend")
                expect(list[2].want).to.equal(1)
                expect(list[3].action).to.equal("capture")
                expect(list[3].weight > list[1].weight).to.beTrue()
                local enemy = obj().DomObjectives(flags, 2)
                expect(enemy[2].action).to.equal("capture")
                expect(enemy[2].weight > enemy[1].weight).to.beTrue()
            end
        },
        {
            name = "Objective, pure: Kill Confirmed fallback collects enemy tags and denies own ones",
            func = function()
                local tags = { { id = "t1", pos = Vector(0, 0, 0), team = 2 },
                    { id = "t2", pos = Vector(9, 0, 0), team = 1 } }
                local list = obj().KCObjectives(tags, 1)
                expect(list[1].action).to.equal("collect")
                expect(list[2].action).to.equal("deny")
                expect(list[1].want).to.equal(1)
            end
        },
        {
            name = "Objective, pure: flags only in dom, tags only in kc, and the mode's own answer wins",
            func = function()
                local flags = { { letter = "A", pos = Vector(0, 0, 0), owner = 0, value = 0 } }
                local tags = { { id = "t1", pos = Vector(0, 0, 0), team = 2 } }
                expect(#obj().Derive("dom", nil, flags, tags, 1)).to.equal(1)
                expect(obj().Derive("dom", nil, flags, tags, 1)[1].action).to.equal("capture")
                expect(obj().Derive("kc", nil, flags, tags, 1)[1].action).to.equal("collect")
                expect(#obj().Derive("tdm", nil, flags, tags, 1)).to.equal(0)
                local own = { objective("x", Vector(0, 0, 0), "hold") }
                expect(obj().Derive("dom", own, flags, tags, 1)[1].id).to.equal("x")
            end
        },
        {
            name = "Objective, pure: the local pick avoids a crowded flag and sticks to the current one",
            func = function()
                local a = objective("A", Vector(1000, 0, 0), "capture")
                local b = objective("B", Vector(-1000, 0, 0), "capture")
                local here = Vector(0, 0, 0)
                local crowd = { Vector(1000, 50, 0), Vector(1000, -50, 0) }
                expect(must(obj().PickObjective({ a, b }, here, crowd, nil)).id).to.equal("B")
                local closer = objective("C", Vector(900, 0, 0), "capture")
                expect(must(obj().PickObjective({ closer, b }, here, {}, "B")).id).to.equal("B")
                expect(obj().PickObjective({}, here, {}, nil)).to.beNil()
            end
        },
        {
            name = "Mandatory (T-5.10) use_streak chosen: a ready streak is used, then the behaviour ends",
            func = function()
                local flag = objective("flag_A", Vector(900, 0, 0), "capture")
                local f = facts({ mode = "dom", objectives = { flag }, streak = { id = "uav" } })
                local env = newEnv(f)
                local state = brain().NewState()
                expect(think(state, env, 0)).to.equal("use_streak")
                think(state, env, 0.1)
                expect(env.used[1]).to.equal("uav")
                f.streak = nil
                expect(think(state, env, 0.2)).to.equal("objective")
            end
        },
        {
            name = "Mandatory (T-5.10) use_streak not chosen: no ready streak",
            func = function()
                local flag = objective("flag_A", Vector(900, 0, 0), "capture")
                local env = newEnv(facts({ mode = "dom", objectives = { flag } }))
                local state = brain().NewState()
                expect(think(state, env, 0)).to.equal("objective")
                expect(#env.used).to.equal(0)
            end
        },
        {
            name = "use_streak wiring: a bot without held streaks has none ready; a ctx without a bot uses none",
            func = function()
                -- ReadyStreak and UseStreak go through PW.Streaks.Ready and PW.Streaks.Use (T-4.6); the held-streak
                -- path is covered by the PW streaks group (lua/tests/privatewar/streaks.lua).
                expect(obj().ReadyStreak("bot")).to.beNil()
                local ctx = brain().NewState().ctx
                expect(obj().UseStreak(ctx, "uav")).to.beFalse()
            end
        },
        {
            name = "Mandatory (T-5.10) hunt chosen: a heard enemy is hunted at the heard position",
            func = function()
                local heard = Vector(1500, 300, 0)
                local env = newEnv(facts({ candidates = ring }), { memory = { enemy = lostContact(heard, 0) } })
                local state = brain().NewState()
                expect(think(state, env, 1)).to.equal("hunt")
                expect(goalOf(env).priority).to.equal("hunt")
                expect(goalOf(env).point:Distance(heard) < 1).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.10) hunt chosen: with nothing heard it roams to a navmesh point",
            func = function()
                local env = newEnv(facts({ candidates = ring }))
                local state = brain().NewState()
                expect(think(state, env, 0)).to.equal("hunt")
                local point = goalOf(env).point
                local onRing = false
                for _, p in ipairs(ring) do onRing = onRing or p:Distance(point) < 1 end
                expect(onRing).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.10) hunt not chosen: an objective outranks it, and with nowhere to go idle runs",
            func = function()
                local flag = objective("flag_A", Vector(900, 0, 0), "capture")
                local heard = { enemy = lostContact(Vector(1500, 0, 0), 0) }
                local f = facts({ mode = "dom", objectives = { flag }, candidates = ring })
                local env = newEnv(f, { memory = heard })
                expect(think(brain().NewState(), env, 1)).to.equal("objective")
                local empty = newEnv(facts())
                expect(think(brain().NewState(), empty, 0)).to.equal("idle")
            end
        },
        {
            name = "Hunt: after arriving it sometimes pauses and looks around, then moves on",
            func = function()
                local env = newEnv(facts({ candidates = ring }), nil, 0.1)
                local state = brain().NewState()
                think(state, env, 0)
                expect(#env.goals).to.equal(1)
                goalOf(env).status = "arrived"
                think(state, env, 0.1)
                expect(#env.goals).to.equal(1)
                expect(isvector(env.board.target)).to.beTrue()
                think(state, env, 6)
                expect(#env.goals).to.equal(2)
                expect(env.board.target).to.beNil()
            end
        },
        {
            name = "Hunt, pure: roam points avoid the recent places, crowded places and points too near",
            func = function()
                local here = Vector(0, 0, 0)
                local half = function() return 0.5 end
                local near = { Vector(100, 0, 0) }
                expect(obj().PickRoamPoint(here, near, {}, {}, half)).to.beNil()
                local a, b = Vector(1200, 0, 0), Vector(-1200, 0, 0)
                expect(must(obj().PickRoamPoint(here, { a, b }, { Vector(1100, 0, 0) }, {}, half))).to.equal(b)
                local mates = { Vector(-1200, 50, 0), Vector(-1200, -50, 0) }
                expect(must(obj().PickRoamPoint(here, { a, b }, {}, mates, half))).to.equal(a)
            end
        },
        {
            name = "Hunt, pure: hot spots come from lost contacts and teammates' deaths, not visible ones",
            func = function()
                local seen = lostContact(Vector(1, 0, 0), 9)
                seen.visible = true
                local memory = { a = lostContact(Vector(500, 0, 0), 9), b = seen }
                local deaths = { { pos = Vector(0, 900, 0), team = 1, time = 5 },
                    { pos = Vector(0, 0, 0), time = -90 } }
                local spots = obj().HotSpots(memory, deaths, 10)
                expect(#spots).to.equal(2)
                local best = must(obj().PickHotSpot(spots, Vector(0, 0, 0), nil, 10))
                expect(best.kind).to.equal("gunfire")
                local checked = { { pos = Vector(500, 0, 0), time = 9 } }
                expect(must(obj().PickHotSpot(spots, Vector(0, 0, 0), checked, 10)).kind).to.equal("death")
            end
        },
        {
            name = "Mandatory (T-5.10) camp chosen: a stationary personality holds a spot, crouched and watching",
            func = function()
                local f = facts({ candidates = ring, stationary = true })
                local env = newEnv(f, { personality = { type = "stationary" } })
                local state = brain().NewState()
                expect(think(state, env, 0)).to.equal("camp")
                expect(goalOf(env).priority).to.equal("guard")
                goalOf(env).status = "arrived"
                think(state, env, 0.1)
                expect(must(env.board.intent).stance).to.equal("crouch")
                expect(isvector(env.board.target)).to.beTrue()
                think(state, env, 60)
                local top = state.stack[#state.stack]
                expect(top == nil or top.id ~= "camp").to.beTrue()
                expect(must(env.board.intent).stance).to.equal("stand")
            end
        },
        {
            name = "Mandatory (T-5.10) camp not chosen: an active personality roams instead",
            func = function()
                local env = newEnv(facts({ candidates = ring }), { personality = { type = "active" } })
                expect(think(brain().NewState(), env, 0)).to.equal("hunt")
            end
        },
        {
            name = "Camp, pure: the spot is near a flag the team defends, else a quiet medium-distance point",
            func = function()
                local here = Vector(0, 0, 0)
                local defend = objective("B", Vector(3000, 0, 0), "defend")
                local candidates = { Vector(3500, 0, 0), Vector(800, 0, 0) }
                expect(must(obj().PickCampSpot(here, candidates, { defend }, {}))).to.equal(candidates[1])
                expect(must(obj().PickCampSpot(here, candidates, {}, {}))).to.equal(candidates[2])
            end
        },
        {
            name = "Mandatory (T-5.10), smoke on gm_construct: in Domination a real bot starts moving toward a flag",
            async = true,
            timeout = 40,
            func = function(state)
                if game.GetMap() ~= "gm_construct" then
                    print("[PW] bots objective smoke skipped: map is " .. game.GetMap())
                    done()
                    return
                end
                local bot = must(state.bot) --[[@as Player]]
                expect(bot).to.beValid()
                ---@type PW.BotBoard
                local board = { bot = bot, team = 1, intent = { buttons = 0 } }
                must(PW.BotInput).SetScripted(bot, board.intent)
                stub(must(PW.BotGoal), "BoardOf").with(function(ply) return ply == bot and board or nil end)
                local data = must(must(PW.Map).GetModeData("dom"))
                local spots = data.flags --[[@as table<string, Vector>]]
                timer.Simple(0.5, function()
                    local start = bot:GetPos()
                    for letter, pos in pairs(spots) do
                        if pos:Distance(start) > 500 then must(must(PW.DomFlags).Spawn)(letter, pos) end
                    end
                    local brainState = brain().NewState()
                    local env = { bot = bot, board = board, behaviors = behaviors(), mode = "dom",
                        random = math.random, api = { mode = "dom" } }
                    local started, best = CurTime(), math.huge
                    timer.Create("PW.BotObjectiveSmoke", 0.1, 0, function()
                        brain().Think(brainState, env, CurTime())
                        local goal = board.goal
                        local d = goal ~= nil and bot:GetPos():Distance(goal.point) or math.huge
                        local first = best == math.huge and goal ~= nil
                        if first then best = d end
                        local moved = goal ~= nil and best - d >= 150
                        local late = CurTime() - started > 30
                        if not moved and not late then return end
                        timer.Remove("PW.BotObjectiveSmoke")
                        print(string.format("[PW] bots objective smoke: %s, behaviour %s, goal %s, %.0f units closer"
                            .. " in %.1f s", moved and "moving" or "stalled", tostring((board.behavior or {}).id),
                            goal ~= nil and goal.priority or "none", best - d, CurTime() - started))
                        brain().Stop(brainState, env, CurTime(), "test end")
                        must(PW.BotGoal)._Drop(bot)
                        must(must(PW.DomFlags).RemoveAll)()
                        expect((board.behavior or { id = "objective" }).id).to.equal("objective")
                        expect(moved).to.beTrue()
                        done()
                    end)
                end)
            end
        }
    }
}
