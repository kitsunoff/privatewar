-- Objective action contract: real registry definitions, pure brain contexts and isolated match stores.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil, "objective action dependency absent") return value end

---@return table<string, any>
local function actions() return must(PW.BotObjectives) --[[@as table<string, any>]] end

---@param action? string
---@return PW.BotObjective
local function objective(action)
    return { id = "test_zone", action = action or "capture", revision = 1, pos = Vector(500, 0, 0),
        radius = 100, weight = 1, want = 1, eligible = { [7] = true } }
end

---@return PW.BotBrainCtx
local function context()
    local ctx = must(PW.BotBrain).NewState().ctx
    ctx.bot = { IsValid = function() return true end, Alive = function() return true end,
        UserID = function() return 7 end, GetPos = function() return Vector() end } --[[@as Player]]
    ctx.board, ctx.state, ctx.now = { bot = ctx.bot, intent = { buttons = 0 } }, {}, 10
    ctx._api = { random = function() return 0.5 end,
        facts = function() return { pos = Vector(), objectives = {}, mates = {}, deaths = {}, candidates = {},
            stationary = false, teamwork = 1 } end,
        clearGoal = function() ctx.board.goal = nil end,
        setGoal = function(_, point, radius, priority)
            ctx.board.goal = { point = point, projected = point, radius = radius, priority = priority,
                status = "moving", since = ctx.now }
            return true, "moving"
        end }
    return ctx
end

return {
    groupName = "PW objective action handlers",
    beforeEach = function(state)
        state.registry = rawget(PW, "ObjectiveActions")
        state.match = PW._Match
        state.mode = PW.ActiveMode
        state.call = PW._Call
        PW._Call = { log = function() end, failed = {}, profile = {} }
        PW._Match = must(PW.Match)._NewStore({ log = function() end })
    end,
    afterEach = function(state)
        rawset(PW, "ObjectiveActions", state.registry)
        PW._Match, PW._Call = state.match, state.call
        PW.ActiveMode = state.mode
    end,
    cases = {
        {
            name = "Actions: kind registers all seven built-ins with required Update and no subscriptions",
            func = function(state)
                local kind = must(PW.Kinds.Get("objective_actions"))
                expect(kind.Global).to.equal("OBJECTIVEACTION")
                expect(kind.Subscribe).to.equal("never")
                expect(GetConVar("pw_objectiveaction_capture_enabled")).to.exist()
                for _, id in ipairs({ "capture", "hold", "defend", "collect", "deny", "plant", "defuse" }) do
                    local def = must(state.registry.Get(id)) --[[@as PW.Entity]]
                    expect(isfunction(def.Update)).to.beTrue()
                end
                local reg = PW.Registry.New("test_actions", { required = kind.Required, log = function() end })
                reg.Register({}, "invalid")
                reg.Register({ Update = "wrong type" }, "mistyped")
                reg.ResolveAll()
                expect(reg.Get("invalid")).to.beNil()
                expect(reg.Get("mistyped")).to.beNil()
            end
        },
        {
            name = "Actions: all movement built-ins retain approach priorities and capture arrival drift",
            func = function()
                for _, id in ipairs({ "capture", "hold", "defend", "collect", "deny" }) do
                    local ctx, target = context(), objective(id)
                    expect(actions().RunAction(ctx, target).kind).to.equal("continue")
                    local goal = must(ctx.board.goal)
                    expect(goal.priority).to.equal(id == "defend" and "guard" or "objective")
                    if id == "capture" or id == "hold" then
                        expect(goal.radius).to.equal(50)
                        goal.status = "arrived"
                        actions().RunAction(ctx, target)
                        expect(must(ctx.board.goal).radius).to.equal(40)
                        expect(must(ctx.board.goal).point:Distance(target.pos) <= 60).to.beTrue()
                    elseif id == "defend" then
                        expect(goal.point:Distance(target.pos) <= 150).to.beTrue()
                    else
                        expect(goal.point).to.equal(target.pos)
                        expect(goal.radius).to.equal(20)
                    end
                    actions().EndAction(ctx)
                end
            end
        },
        {
            name = "Actions: plant and defuse only hold use inside the authoritative zone, never award a verdict",
            func = function()
                for _, id in ipairs({ "plant", "defuse" }) do
                    local ctx, target = context(), objective(id)
                    actions().RunAction(ctx, target)
                    expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
                    must(ctx.facts).pos = target.pos
                    actions().RunAction(ctx, target)
                    expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(IN_USE)
                    expect(ctx.board.goal).to.beNil()
                    actions().EndAction(ctx)
                    expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
                    expect(ctx.board.target).to.beNil()
                end
            end
        },
        {
            name = "Actions: state belongs to each bot and visit; revision and action changes end the old visit",
            func = function()
                local a, b, target = context(), context(), objective()
                actions().RunAction(a, target)
                actions().RunAction(b, target)
                local first = must(a.state).visit --[[@as any]]
                expect(first == must(b.state).visit).to.beFalse()
                target.revision = 2
                actions().RunAction(a, target)
                expect(first == must(a.state).visit).to.beFalse()
                expect(must(a.state).revision).to.equal(2)
                target.action = "defend"
                actions().RunAction(a, target)
                expect(must(a.board.goal).priority).to.equal("guard")
                actions().EndAction(a)
                expect(must(a.state).visit).to.beNil()
                expect(must(b.state).visit).to.exist()
                actions().EndAction(b)
            end
        },
        {
            name = "Actions: handler failure disables only that handler and runner cleanup survives failed OnEnd",
            func = function()
                local reg = PW.Registry.New("objective_actions", { preRegister = function() end, log = function() end })
                reg.Register({ Update = function(_, _, ctx)
                    ---@cast ctx PW.BotBrainCtx
                    ctx:Intent().buttons = IN_USE
                    ctx:SetTarget(Vector(1, 2, 3) --[[@as any]])
                    ctx:SetGoal(Vector(), 10, "objective")
                    error("handler failed")
                end, OnEnd = function() error("cleanup failed") end }, "broken")
                reg.Register({ Update = function() return must(PW.BotBrain).Continue() end }, "healthy")
                reg.ResolveAll()
                rawset(PW, "ObjectiveActions", reg)
                local ctx = context()
                expect(actions().RunAction(ctx, objective("broken")).kind).to.equal("done")
                expect(must(reg.Get("broken")):IsValid()).to.beFalse()
                expect(must(reg.Get("healthy")):IsValid()).to.beTrue()
                expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
                expect(ctx.board.target).to.beNil()
                expect(ctx.board.goal).to.beNil()
                expect(must(must(PW.BotBehaviors).Get("objective")):IsValid()).to.beTrue()
            end
        },
        {
            name = "Actions: eligibility loss and dead actor clear use, look and goal before dispatch",
            func = function()
                local ctx, target = context(), objective("plant")
                local facts = actions().Facts(ctx) --[[@as PW.BotFacts]]
                facts.pos = target.pos
                actions().RunAction(ctx, target)
                target.eligible = {}
                expect(actions().RunAction(ctx, target).kind).to.equal("done")
                expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
                target.eligible = { [7] = true }
                actions().RunAction(ctx, target)
                ctx.bot = { IsValid = function() return true end, Alive = function() return false end,
                    UserID = function() return 7 end } --[[@as Player]]
                expect(actions().RunAction(ctx, target).kind).to.equal("done")
                expect(ctx.board.target).to.beNil()
                expect(ctx.board.goal).to.beNil()
            end
        },
        {
            name = "Actions: failed OnEnd cannot retain runner-owned input, look or movement",
            func = function()
                local reg = PW.Registry.New("objective_actions", { preRegister = function() end, log = function() end })
                local ends = 0
                reg.Register({ Update = function() return must(PW.BotBrain).Continue() end,
                    OnEnd = function() ends = ends + 1 error("cleanup failed") end }, "bad_end")
                reg.ResolveAll()
                rawset(PW, "ObjectiveActions", reg)
                local ctx = context()
                actions().RunAction(ctx, objective("bad_end"))
                ctx:Intent().buttons = IN_USE
                ctx:SetTarget(Vector(1, 2, 3) --[[@as any]])
                ctx:SetGoal(Vector(), 10, "objective")
                actions().EndAction(ctx)
                actions().EndAction(ctx)
                expect(ends).to.equal(1)
                expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
                expect(ctx.board.goal).to.beNil()
                expect(ctx.board.target).to.beNil()
            end
        },
        {
            name = "Actions: authoritative facts reject stale orders by identity, action, revision and eligibility",
            func = function()
                local ctx, target = context(), objective("plant")
                local facts = actions().Facts(ctx) --[[@as PW.BotFacts]]
                facts.authoritative, facts.objectives = true, { target }
                ctx.order = { id = target.id, type = target.action, objective = table.Copy(target), since = 0,
                    priority = 1 }
                local lib = must(PW.BotObjectives)
                local _, _, ordered = lib.Resolve(ctx, facts)
                expect(ordered).to.beTrue()
                target.eligible = {}
                expect(lib.Resolve(ctx, facts)).to.beNil()
                target.eligible = { [7] = true }
                target.revision = 2
                local _, _, stale = lib.Resolve(ctx, facts)
                expect(stale).to.beFalse()
                target.revision, target.action = 1, "defuse"
                local _, _, changed = lib.Resolve(ctx, facts)
                expect(changed).to.beFalse()
                facts.objectives = {}
                expect(lib.Resolve(ctx, facts)).to.beNil()
            end
        },
        {
            name = "Actions: suspended invalidation and death cleanup work even if the objective facade is disabled",
            func = function()
                local brain, ctx, target = must(PW.BotBrain), context(), objective("plant")
                must(actions().Facts(ctx) --[[@as PW.BotFacts]]).pos = target.pos
                actions().RunAction(ctx, target)
                local facade = must(must(PW.BotBehaviors).Get("objective")) --[[@as PW.BotBehavior]]
                local state = brain.NewState()
                state.stack = { { id = "objective", def = facade, state = must(ctx.state), since = 0,
                    rank = 20, weight = 1, via = "select", reason = "test" } }
                state.ctx = ctx
                local env = { bot = ctx.bot, board = ctx.board, behaviors = {}, mode = "test",
                    random = function() return 0 end, api = ctx._api }
                PW._Call.failed[facade] = true
                brain._InvalidateObjective(state, env, 10, target.id, 1)
                expect(#state.stack).to.equal(0)
                expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
                expect(ctx.board.goal).to.beNil()
                PW._Call.failed[facade] = nil
                ctx.state = {}
                actions().RunAction(ctx, target)
                PW.Call(facade, "OnSuspend", ctx.bot, ctx)
                local suspended = must(ctx.state)
                local guard = { ClassName = "cover_fixture", Rank = function() return "survival" end,
                    Weight = function() return 1 end, Update = function() return brain.Continue() end }
                state.stack = { { id = "objective", def = facade, state = suspended, since = 0,
                    rank = 20, weight = 1, via = "select", reason = "test" },
                    { id = "cover_fixture", def = guard, state = {}, since = 0,
                        rank = 40, weight = 1, via = "select", reason = "test" } }
                state.legsOf = "cover_fixture"
                ctx:SetGoal(Vector(100, 200, 0), 20, "critical")
                local coverGoal = ctx.board.goal
                brain._InvalidateObjective(state, env, 10, target.id, 1)
                expect(#state.stack).to.equal(1)
                expect(ctx.board.goal).to.equal(coverGoal)
                ctx.state = {}
                actions().RunAction(ctx, target)
                state.stack = { { id = "objective", def = facade, state = must(ctx.state), since = 0,
                    rank = 20, weight = 1, via = "select", reason = "test" } }
                brain.Stop(state, env, 11, "dead")
                expect(#state.stack).to.equal(0)
                expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
            end
        },
        {
            name = "Actions: late cleanup preserves a newer behavior's identical intent values and new goal",
            func = function()
                local brain, ctx = must(PW.BotBrain), context()
                local reg = PW.Registry.New("objective_actions", { preRegister = function() end, log = function() end })
                local drive, look = Vector(200, 0, 0), Vector(600, 0, 50)
                reg.Register({ Update = function(_, _, current)
                    ---@cast current PW.BotBrainCtx
                    current:Intent().buttons = IN_USE
                    current:Intent().drive, current:Intent().sprint, current:Intent().stance = drive, true, "crouch"
                    current:SetTarget(look --[[@as any]])
                    current:SetGoal(Vector(500, 0, 0), 10, "objective")
                    return brain.Continue()
                end }, "owned")
                reg.ResolveAll()
                rawset(PW, "ObjectiveActions", reg)
                actions().RunAction(ctx, objective("owned"))
                local oldState = must(ctx.state)
                local newer = brain.NewState()
                local def = { ClassName = "newer_fixture", Rank = function() return "survival" end,
                    Weight = function() return 1 end, Update = function(_, _, current)
                        ---@cast current PW.BotBrainCtx
                        current:Intent().buttons = IN_USE
                        current:Intent().drive, current:Intent().sprint = drive, true
                        current:Intent().stance = "crouch"
                        current:SetTarget(look --[[@as any]])
                        current:SetGoal(Vector(900, 0, 0), 20, "critical")
                        return brain.Continue()
                    end }
                local env = { bot = ctx.bot, board = ctx.board, behaviors = { def }, mode = "test",
                    random = function() return 0 end, api = ctx._api }
                brain.Think(newer, env, 11)
                local goal = ctx.board.goal
                ctx.state = oldState
                actions().EndAction(ctx)
                expect(ctx.board.goal).to.equal(goal)
                expect(ctx:Intent().drive).to.equal(drive)
                expect(ctx:Intent().sprint).to.beTrue()
                expect(ctx:Intent().stance).to.equal("crouch")
                expect(ctx.board.target).to.equal(look)
                expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(IN_USE)
            end
        },
        {
            name = "Actions: reentrant OnEnd handoff survives cleanup success and cleanup failure",
            func = function()
                local brain = must(PW.BotBrain)
                for _, fails in ipairs({ false, true }) do
                    local ctx, newer = context(), brain.NewState()
                    local drive, look = Vector(200, 0, 0), Vector(700, 0, 50)
                    local def = { ClassName = "handoff_fixture", Rank = function() return "survival" end,
                        Weight = function() return 1 end, Update = function(_, _, current)
                            ---@cast current PW.BotBrainCtx
                            current:Intent().drive, current:Intent().sprint = drive, true
                            current:Intent().stance = "crouch"
                            current:SetTarget(look --[[@as any]])
                            current:SetGoal(Vector(900, 0, 0), 20, "critical")
                            return brain.Continue()
                        end }
                    local env = { bot = ctx.bot, board = ctx.board, behaviors = { def }, mode = "test",
                        random = function() return 0 end, api = ctx._api }
                    local reg = PW.Registry.New("objective_actions", {
                        preRegister = function() end, log = function() end })
                    reg.Register({ Update = function(_, _, current)
                        ---@cast current PW.BotBrainCtx
                        current:Intent().buttons = IN_USE
                        current:SetGoal(Vector(500, 0, 0), 10, "objective")
                        return brain.Continue()
                    end, OnEnd = function()
                        brain.Think(newer, env, 11)
                        if fails then error("cleanup failed after newer behavior started") end
                    end }, "handoff")
                    reg.ResolveAll()
                    rawset(PW, "ObjectiveActions", reg)
                    actions().RunAction(ctx, objective("handoff"))
                    actions().EndAction(ctx)
                    expect(must(ctx.board.goal).priority).to.equal("critical")
                    expect(ctx:Intent().drive).to.equal(drive)
                    expect(ctx:Intent().sprint).to.beTrue()
                    expect(ctx:Intent().stance).to.equal("crouch")
                    expect(ctx.board.target).to.equal(look)
                    expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
                end
            end
        },
        {
            name = "Actions: a reentrant suspension handoff cannot be reclaimed by the older brain tick",
            func = function()
                local brain, ctx = must(PW.BotBrain), context()
                local running, newer = brain.NewState(), brain.NewState()
                local combat, updates = false, 0
                local drive, look = Vector(200, 0, 0), Vector(700, 0, 50)
                local nextDef = { ClassName = "newer_fixture", Rank = function() return "survival" end,
                    Weight = function() return 1 end, Update = function(_, _, current)
                        ---@cast current PW.BotBrainCtx
                        current:Intent().drive, current:Intent().sprint = drive, true
                        current:Intent().stance = "crouch"
                        current:SetTarget(look --[[@as any]])
                        current:SetGoal(Vector(900, 0, 0), 20, "critical")
                        return brain.Continue()
                    end }
                local nextEnv = { bot = ctx.bot, board = ctx.board, behaviors = { nextDef }, mode = "test",
                    random = function() return 0 end, api = ctx._api }
                local reg = PW.Registry.New("objective_actions", { preRegister = function() end, log = function() end })
                reg.Register({ Update = function()
                    updates = updates + 1
                    return brain.Continue()
                end, OnEnd = function() brain.Think(newer, nextEnv, 11) end }, "handoff")
                reg.ResolveAll()
                rawset(PW, "ObjectiveActions", reg)
                local facts = actions().Facts(ctx) --[[@as PW.BotFacts]]
                facts.objectives = { objective("handoff") }
                ctx._api.facts = function() return facts end
                local competitor = { ClassName = "competitor_fixture",
                    Rank = function() return combat and "combat" or false end, Weight = function() return 1 end,
                    Update = function() error("older selector reclaimed control after handoff") end }
                local facade = must(must(PW.BotBehaviors).Get("objective")) --[[@as PW.BotBehavior]]
                local env = { bot = ctx.bot, board = ctx.board, behaviors = { facade, competitor }, mode = "test",
                    random = function() return 0 end, api = ctx._api }
                brain.Think(running, env, 10)
                expect(must(running.stack[1]).id).to.equal("objective")
                combat = true
                brain.Think(running, env, 11)
                expect(updates).to.equal(1)
                expect(PW._Call.failed[competitor]).to.beNil()
                expect(must(ctx.board.goal).priority).to.equal("critical")
                expect(ctx:Intent().drive).to.equal(drive)
                expect(ctx:Intent().sprint).to.beTrue()
                expect(ctx:Intent().stance).to.equal("crouch")
                expect(ctx.board.target).to.equal(look)
            end
        },
        {
            name = "Actions: ending invalidating or stopping an old objective preserves a reentrant handoff",
            func = function()
                ---@param ending string
                local function verify(ending)
                    local brain, ctx = must(PW.BotBrain), context()
                    local running, newer = brain.NewState(), brain.NewState()
                    local nextDef = { ClassName = "newer_fixture", Rank = function() return "survival" end,
                        Weight = function() return 1 end, Update = function(_, _, current)
                            ---@cast current PW.BotBrainCtx
                            current:SetGoal(Vector(900, 0, 0), 20, "critical")
                            current:Intent().sprint = true
                            return brain.Continue()
                        end }
                    local nextEnv = { bot = ctx.bot, board = ctx.board, behaviors = { nextDef }, mode = "test",
                        random = function() return 0 end, api = ctx._api }
                    local reg = PW.Registry.New("objective_actions", {
                        preRegister = function() end, log = function() end })
                    reg.Register({ Update = function() return brain.Continue() end,
                        OnEnd = function() brain.Think(newer, nextEnv, 11) end }, "handoff")
                    reg.ResolveAll()
                    rawset(PW, "ObjectiveActions", reg)
                    actions().RunAction(ctx, objective("handoff"))
                    local def = { ClassName = "objective", Rank = function() return false end,
                        Weight = function() return 1 end, Update = function() return brain.Done("finished") end }
                    local below = { ClassName = "below_fixture", Rank = function() return false end,
                        Weight = function() return 1 end, Update = function() return brain.Continue() end,
                        OnResume = function() error("resumed an older frame after handoff") end }
                    running.ctx = ctx
                    running.stack = { { id = "below_fixture", def = below, state = {}, since = 0,
                        rank = 10, weight = 1, via = "select", reason = "test" },
                        { id = "objective", def = def, state = must(ctx.state), since = 0,
                            rank = 20, weight = 1, via = "select", reason = "test" } }
                    local env = { bot = ctx.bot, board = ctx.board, behaviors = { def, below }, mode = "test",
                        random = function() return 0 end, api = ctx._api }
                    if ending == "think" then brain.Think(running, env, 11)
                    elseif ending == "invalidate" then brain._InvalidateObjective(running, env, 11, "test_zone", 1)
                    else brain.Stop(running, env, 11, "reset") end
                    expect(PW._Call.failed[below]).to.beNil()
                    expect(must(ctx.board.goal).priority).to.equal("critical")
                    expect(ctx:Intent().sprint).to.beTrue()
                    expect(must(ctx.board.behavior).id).to.equal("newer_fixture")
                end
                for _, ending in ipairs({ "think", "invalidate", "stop" }) do verify(ending) end
            end
        },
        {
            name = "Actions: an authoritative custom required action omitted from dependencies never executes",
            func = function()
                local reg = PW.Registry.New("objective_actions", { preRegister = function() end, log = function() end })
                local calls, aborts = 0, 0
                reg.Register({ Update = function()
                    calls = calls + 1
                    return must(PW.BotBrain).Continue()
                end }, "custom")
                reg.ResolveAll()
                rawset(PW, "ObjectiveActions", reg)
                stub(must(PW.Match), "Abort").with(function() aborts = aborts + 1 return true end)
                for _, snapshot in ipairs({ {}, { objective_actions = {} } }) do
                    PW._Match.dependencies = snapshot
                    local ctx = context()
                    local facts = actions().Facts(ctx) --[[@as PW.BotFacts]]
                    facts.authoritative = true
                    expect(actions().RunAction(ctx, objective("custom")).kind).to.equal("done")
                end
                expect(calls).to.equal(0)
                expect(aborts).to.equal(2)
            end
        },
        {
            name = "Actions: gathered facts only invalidate orders when a mode catalog was actually queried",
            func = function()
                local lib, ctx, target = must(PW.BotObjectives), context(), objective("hold")
                local now, calls = 6000, 0
                ---@type table<string, any>
                local mode = { ClassName = "authority_fixture", BotObjectives = function()
                    calls = calls + 1
                    return { target }
                end }
                PW.ActiveMode = mode
                stub(_G, "CurTime").with(function() return now end)
                stub(player, "GetAll").returns({})
                stub(lib, "ReadyStreak").with(function() end)
                ctx.order = { id = target.id, type = target.action, objective = target, since = 0, priority = 1 }
                ctx._api.mode = mode.ClassName
                local gather = must(lib.Gather)
                -- The existing gatherer deliberately does not call BotObjectives(nil) in FFA.
                local ffa = gather(ctx)
                expect(calls).to.equal(0)
                expect(ffa.authoritative == true).to.beFalse()
                local _, _, ordered = lib.Resolve(ctx, ffa)
                expect(ordered).to.beTrue()
                now, ctx.board.team = 6001, 1
                local team = gather(ctx)
                expect(calls).to.equal(1)
                expect(team.authoritative).to.beTrue()
                mode.BotObjectives, now = nil, 6002
                local absent = gather(ctx)
                expect(calls).to.equal(1)
                expect(absent.authoritative == true).to.beFalse()
                local _, _, legacy = lib.Resolve(ctx, absent)
                expect(legacy).to.beTrue()
            end
        },
        {
            name = "Actions: an unsafe projected arrival never holds use",
            func = function()
                local ctx, target = context(), objective("plant")
                target.zone = { pos = target.pos, radius = 100, above = 50, below = 10 }
                ctx.board.goal = { point = target.pos, projected = target.pos + Vector(0, 0, 80), radius = 16,
                    priority = "objective", status = "moving", since = 0 }
                expect(actions().RunAction(ctx, target).kind).to.equal("done")
                expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
                expect(ctx.board.goal).to.beNil()
            end
        }
    }
}
