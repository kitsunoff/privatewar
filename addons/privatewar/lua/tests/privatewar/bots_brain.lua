-- T-5.9 bot brain (07-bots.md d.4, d.5): dual-utility selection (rank bucket, then weighted-random among the
-- near-best), commitment bonus, per-behaviour intervals, the Action stack with suspend and resume, the ctx helpers.
-- Pure cases over plain data: fixture behaviours, a fake random generator and a fake clock; no real bots.

local epsilon = 1e-9

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotBrainLib
local function lib()
    return must(PW.BotBrain)
end

---A deterministic random generator: a repeating sequence in [0, 1).
---@param values number[]
---@return fun(): number
local function sequence(values)
    local index = 0
    return function()
        index = index % #values + 1
        return values[index]
    end
end

---@alias PW.TestBrainSpec { rank: any, weight: any, interval: number?, minRun: number?, cooldown: number?,
---    modes: string[]?, updates: table<integer, PW.BotTransition|false>?, failWeight: boolean?, failUpdate: boolean? }

---A fixture behaviour. rank and weight are values or functions of the evaluation number; updates[n] is what the
---n-th Update returns (false: nothing; missing: Continue). Frame methods are written to log as "<id>:<Method>";
---Rank, Weight and Update calls are counted in def.calls.
---@param id string
---@param spec PW.TestBrainSpec
---@param log string[]
---@return table
local function fixture(id, spec, log)
    local calls = { Rank = 0, Weight = 0, Update = 0 }
    ---@type table<string, any>
    local def = { ClassName = id, Interval = spec.interval, MinRun = spec.minRun, Cooldown = spec.cooldown,
        Modes = spec.modes, calls = calls }
    ---@param value any
    ---@param n integer
    local function valueOf(value, n)
        if isfunction(value) then return value(n) end
        return value
    end
    function def:Rank()
        calls.Rank = calls.Rank + 1
        return valueOf(spec.rank, calls.Rank)
    end
    function def:Weight()
        calls.Weight = calls.Weight + 1
        if spec.failWeight then error("broken weight") end
        return valueOf(spec.weight, calls.Weight)
    end
    function def:Update()
        calls.Update = calls.Update + 1
        log[#log + 1] = id .. ":Update"
        if spec.failUpdate then error("broken update") end
        local answer = (spec.updates or {})[calls.Update]
        if answer == false then return nil end
        return answer or lib().Continue()
    end
    for _, method in ipairs({ "OnStart", "OnEnd", "OnSuspend", "OnResume" }) do
        def[method] = function() log[#log + 1] = id .. ":" .. method end
    end
    return def
end

---A brain environment over fixture behaviours.
---@param behaviors table[]
---@param opts { random: (fun(): number)?, screen: number?, bonus: number?, mode: string?, api: table? }?
---@return PW.BotBrainEnv
local function newEnv(behaviors, opts)
    local o = opts or {}
    return {
        bot = "bot", board = { bot = "bot" --[[@as Player]] }, behaviors = behaviors --[[@as PW.BotBehavior[] ]],
        random = o.random or sequence({ 0.5 }), screen = o.screen, bonus = o.bonus, mode = o.mode, api = o.api
    }
end

---Runs ticks brain ticks every dt seconds starting at start; returns the running behaviour id after each tick.
---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param ticks integer
---@param dt number
---@param start number?
---@return string[]
local function run(state, env, ticks, dt, start)
    ---@type string[]
    local running = {}
    for i = 0, ticks - 1 do
        lib().Think(state, env, (start or 0) + i * dt)
        local stack = state.stack
        running[#running + 1] = #stack > 0 and stack[#stack].id or "-"
    end
    return running
end

---@param list string[]
---@return integer
local function switches(list)
    local count = 0
    for i = 2, #list do
        if list[i] ~= list[i - 1] then count = count + 1 end
    end
    return count
end

return {
    groupName = "PW bots brain",
    beforeEach = function(state)
        state.log = PW._Call.log
        PW._Call.log = function() end
    end,
    afterEach = function(state)
        PW._Call.log = state.log
    end,
    cases = {
        {
            name = "Dual-utility: the highest rank bucket wins over any weight",
            func = function()
                local brain = lib()
                local cands = {
                    { id = "roam", rank = brain.Buckets.roam, weight = 100 },
                    { id = "fight", rank = brain.Buckets.combat, weight = 0.2 },
                    { id = "cover", rank = brain.Buckets.survival, weight = 0.1 },
                    { id = "flag", rank = brain.Buckets.objective, weight = 50 }
                }
                for _, r in ipairs({ 0, 0.5, 0.99 }) do
                    local opts = { screen = 0.5, bonus = 1.15, random = function() return r end }
                    expect(brain.Choose(cands, nil, opts)).to.equal("cover")
                end
                expect(brain.Buckets.survival > brain.Buckets.combat).to.beTrue()
                expect(brain.Buckets.combat > brain.Buckets.objective).to.beTrue()
                expect(brain.Buckets.objective > brain.Buckets.roam).to.beTrue()
            end
        },
        {
            name = "Dual-utility: Think runs the behaviour of the highest bucket; names and numbers rank alike",
            func = function()
                local brain = lib()
                local log = {}
                local env = newEnv({
                    fixture("idle", { rank = "roam", weight = 9 }, log),
                    fixture("fight", { rank = "combat", weight = 0.5 }, log),
                    fixture("flag", { rank = 20, weight = 5 }, log),
                    fixture("off", { rank = nil, weight = 99 }, log)
                })
                local state = brain.NewState()
                brain.Think(state, env, 0)
                expect(brain.StackIds(state)[1]).to.equal("fight")
                expect(must(env.board.behavior).id).to.equal("fight")
                expect(brain.RankValue("objective")).to.equal(20)
                expect(brain.RankValue(nil)).to.beNil()
                expect(brain.RankValue(false)).to.beNil()
                expect(brain.RankValue(0)).to.beNil()
                expect(brain.RankValue("nonsense")).to.beNil()
            end
        },
        {
            name = "Screen: weighted-random picks only among the near-best of the best bucket",
            func = function()
                local brain = lib()
                local cands = {
                    { id = "a", rank = 30, weight = 1.0 },
                    { id = "b", rank = 30, weight = 0.8 },
                    { id = "c", rank = 30, weight = 0.3 },
                    { id = "low", rank = 10, weight = 5 }
                }
                local screened = brain.Screen(cands, 0.7)
                expect(#screened).to.equal(2)
                local counts = { a = 0, b = 0, c = 0, low = 0 }
                for i = 0, 99 do
                    local id = must(brain.Choose(cands, nil, { screen = 0.7, bonus = 1, random = function()
                        return i / 100
                    end }))
                    counts[id] = counts[id] + 1
                end
                expect(counts.c).to.equal(0)
                expect(counts.low).to.equal(0)
                expect(counts.a + counts.b).to.equal(100)
                expect(math.abs(counts.a - 100 / 1.8) <= 1).to.beTrue()
                expect(counts.b > 0).to.beTrue()
            end
        },
        {
            name = "Screen: a wider screen (lower difficulty) lets weaker options in",
            func = function()
                local cands = { { id = "a", rank = 30, weight = 1.0 }, { id = "c", rank = 30, weight = 0.3 } }
                expect(#lib().Screen(cands, 0.7)).to.equal(1)
                expect(#lib().Screen(cands, 0.25)).to.equal(2)
                expect(lib().Pick({}, function() return 0.5 end)).to.beNil()
            end
        },
        {
            name = "Commitment: the bonus keeps the running behaviour against a slightly better option",
            func = function()
                local brain = lib()
                local cands = { { id = "a", rank = 30, weight = 1.0 }, { id = "b", rank = 30, weight = 1.05 } }
                local current = { id = "a", rank = 30, weight = 1.0 }
                for _, r in ipairs({ 0, 0.3, 0.6, 0.99 }) do
                    local opts = { screen = 0.99, bonus = 1.15, random = function() return r end }
                    expect(brain.Choose(cands, current, opts)).to.equal("a")
                end
                local noBonus = { screen = 0.99, bonus = 1, random = function() return 0 end }
                expect(brain.Choose(cands, current, noBonus)).to.equal("b")
            end
        },
        {
            name = "Commitment: alternating near-equal weights do not flip-flop with the bonus, and do without it",
            func = function()
                local brain = lib()
                local function alternate(first, second)
                    return function(n) return n % 2 == 1 and first or second end
                end
                local function build(bonus)
                    local log = {}
                    return newEnv({
                        fixture("a", { rank = "combat", weight = alternate(1.0, 1.05), interval = 0.1 }, log),
                        fixture("b", { rank = "combat", weight = alternate(1.05, 1.0), interval = 0.1 }, log)
                    }, { screen = 0.99, bonus = bonus })
                end
                local with = run(brain.NewState(), build(1.15), 30, 0.1)
                expect(switches(with)).to.equal(0)
                local without = run(brain.NewState(), build(1), 30, 0.1)
                expect(switches(without) >= 20).to.beTrue()
            end
        },
        {
            name = "Commitment: the minimum run time holds against the same bucket, not against a higher one",
            func = function()
                local brain = lib()
                local log = {}
                local env = newEnv({
                    fixture("idle", { rank = "roam", weight = 1, minRun = 5, interval = 0.1 }, log),
                    fixture("walk", { rank = "roam", weight = function(n) return n == 1 and 0.1 or 3 end,
                        interval = 0.1 }, log),
                    fixture("hide", { rank = function(n) return n >= 4 and "survival" or nil end, weight = 1,
                        interval = 0.1 }, log)
                })
                local running = run(brain.NewState(), env, 4, 0.1)
                expect(running[1]).to.equal("idle")
                expect(running[3]).to.equal("idle")
                expect(running[4]).to.equal("hide")
            end
        },
        {
            name = "Interval: Rank and Weight run only when the behaviour's interval has passed",
            func = function()
                local brain = lib()
                local log = {}
                local half = fixture("half", { rank = "roam", weight = 1, interval = 0.5 }, log)
                local default = fixture("default", { rank = "roam", weight = 1 }, log)
                local tiny = fixture("tiny", { rank = "roam", weight = 1, interval = 0.01 }, log)
                local state = brain.NewState()
                run(state, newEnv({ half, default, tiny }), 11, 0.1)
                expect(half.calls.Rank).to.equal(3)
                expect(default.calls.Rank).to.equal(2)
                expect(tiny.calls.Rank).to.equal(11)
                expect(brain.IntervalOf(tiny --[[@as PW.BotBehavior]])).to.equal(brain.Defaults.minInterval)
                expect(brain.IntervalOf(default --[[@as PW.BotBehavior]])).to.equal(brain.Defaults.interval)
                expect(math.abs(half.calls.Weight - 3) < epsilon).to.beTrue()
            end
        },
        {
            name = "Stack: SuspendFor suspends, Done resumes, in this order",
            func = function()
                local brain = lib()
                local log = {}
                local env = newEnv({
                    fixture("a", { rank = "combat", weight = 1, updates = { nil, brain.SuspendFor("b", "reload") } },
                        log),
                    fixture("b", { rank = nil, weight = 0, updates = { brain.Done("reloaded") } }, log)
                })
                local state = brain.NewState()
                brain.Think(state, env, 0)
                brain.Think(state, env, 0.1)
                expect(table.concat(brain.StackIds(state), ",")).to.equal("a,b")
                expect(must(env.board.behavior).reason).to.equal("reload")
                brain.Think(state, env, 0.2)
                expect(table.concat(brain.StackIds(state), ",")).to.equal("a")
                brain.Think(state, env, 0.3)
                expect(table.concat(log, " ")).to.equal(
                    "a:OnStart a:Update a:Update a:OnSuspend b:OnStart b:Update b:OnEnd a:OnResume a:Update")
            end
        },
        {
            name = "Stack: a higher bucket suspends the running behaviour and resumes it when done",
            func = function()
                local brain = lib()
                local log = {}
                local env = newEnv({
                    fixture("idle", { rank = "roam", weight = 1, interval = 0.1 }, log),
                    fixture("dodge", { rank = function(n) return n >= 2 and "survival" or nil end, weight = 1,
                        interval = 0.1, updates = { nil, brain.Done("safe") } }, log)
                })
                local state = brain.NewState()
                brain.Think(state, env, 0)
                brain.Think(state, env, 0.1)
                expect(table.concat(brain.StackIds(state), ",")).to.equal("idle,dodge")
                brain.Think(state, env, 0.2)
                expect(table.concat(log, " ")).to.equal(
                    "idle:OnStart idle:Update idle:OnSuspend dodge:OnStart dodge:Update dodge:Update dodge:OnEnd "
                    .. "idle:OnResume")
                expect(table.concat(brain.StackIds(state), ",")).to.equal("idle")
            end
        },
        {
            name = "Stack: ChangeTo replaces the top, Stop ends every frame top first",
            func = function()
                local brain = lib()
                local log = {}
                local env = newEnv({
                    fixture("a", { rank = "combat", weight = 1, updates = { brain.ChangeTo("c", "flank") } }, log),
                    fixture("b", { rank = nil, weight = 1 }, log),
                    fixture("c", { rank = nil, weight = 1, updates = { brain.SuspendFor("b") } }, log)
                })
                local state = brain.NewState()
                brain.Think(state, env, 0)
                brain.Think(state, env, 0.1)
                expect(table.concat(brain.StackIds(state), ",")).to.equal("c,b")
                brain.Stop(state, env, 0.2, "died")
                expect(#state.stack).to.equal(0)
                expect(env.board.behavior).to.beNil()
                expect(table.concat(log, " ")).to.equal(
                    "a:OnStart a:Update a:OnEnd c:OnStart c:Update c:OnSuspend b:OnStart b:OnEnd c:OnEnd")
            end
        },
        {
            name = "Errors: an erroring behaviour is dropped and the others continue",
            func = function()
                local brain = lib()
                local log = {}
                local broken = fixture("broken", { rank = "survival", weight = 1, failWeight = true }, log)
                local crash = fixture("crash", { rank = "combat", weight = 1, failUpdate = true }, log)
                local idle = fixture("idle", { rank = "roam", weight = 1 }, log)
                local env = newEnv({ broken, crash, idle })
                local state = brain.NewState()
                brain.Think(state, env, 0)
                expect(#state.stack).to.equal(0)
                brain.Think(state, env, 0.1)
                expect(brain.StackIds(state)[1]).to.equal("idle")
                expect(crash.calls.Update).to.equal(1)
            end
        },
        {
            name = "Selection: Modes filter, cooldown after the end, debug data",
            func = function()
                local brain = lib()
                local log = {}
                local env = newEnv({
                    fixture("dom_only", { rank = "objective", weight = 1, modes = { "dom" } }, log),
                    fixture("short", { rank = "combat", weight = 1, cooldown = 1, interval = 0.1,
                        updates = { nil, brain.Done("finished") } }, log),
                    fixture("idle", { rank = "roam", weight = 1, interval = 0.1 }, log)
                }, { mode = "tdm" })
                local running = run(brain.NewState(), env, 4, 0.1)
                expect(table.concat(running, ",")).to.equal("short,-,idle,idle")
                local debug = must(must(env.board.debug).brain) --[[@as PW.BotBrainDebug]]
                expect(debug.stack[1]).to.equal("idle")
                expect(must(debug.scores.idle).rank).to.equal(brain.Buckets.roam)
                expect(debug.scores.dom_only).to.beNil()
                expect(isstring(debug.reason)).to.beTrue()
            end
        },
        {
            name = "ctx: target, intent and goal helpers write the blackboard and call the goal API",
            func = function()
                local brain = lib()
                ---@type any[]
                local seen = {}
                local enemy = {}
                ---@param priority string
                ---@return boolean, string
                local function setGoal(_, _, _, priority)
                    seen[#seen + 1] = { priority = priority }
                    return true, "moving"
                end
                ---@type PW.BotBrainApi
                local api = { setGoal = setGoal, clearGoal = function() seen[#seen + 1] = "clear" end }
                local def = fixture("go", { rank = "roam", weight = 1 }, {})
                ---@param ctx PW.BotBrainCtx
                function def:Update(_, ctx)
                    ctx:SetTarget(enemy --[[@as Entity]])
                    ctx:Intent().stance = "crouch"
                    local own = must(ctx.state)
                    own.ticks = (own.ticks or 0) + 1
                    ctx:SetGoal(Vector(1, 2, 3), 64, "tactical")
                    if own.ticks == 2 then ctx:ClearGoal() end
                    return brain.Continue()
                end
                local env = newEnv({ def }, { api = api })
                local state = brain.NewState()
                brain.Think(state, env, 0)
                brain.Think(state, env, 0.1)
                expect(env.board.target).to.equal(enemy)
                expect(must(env.board.intent).target).to.equal(enemy)
                expect(must(env.board.intent).stance).to.equal("crouch")
                expect(#seen).to.equal(3)
                expect(seen[1].priority).to.equal("tactical")
                expect(seen[3]).to.equal("clear")
                expect(state.stack[1].state.ticks).to.equal(2)
            end
        },
        {
            name = "Kind: the built-in idle behaviour is registered in the roam bucket",
            func = function()
                local registry = must(PW.BotBehaviors)
                local idle = must(registry.Get("idle")) --[[@as PW.BotBehavior]]
                expect(lib().RankValue(PW.Call(idle, "Rank", nil, nil))).to.equal(lib().Buckets.roam)
                expect(PW.Call(idle, "Weight", nil, nil) > 0).to.beTrue()
            end
        }
    }
}
