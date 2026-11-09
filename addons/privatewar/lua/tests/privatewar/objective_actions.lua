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
        UserID = function() return 7 end } --[[@as Player]]
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
        state.call = PW._Call
        PW._Call = { log = function() end, failed = {}, profile = {} }
        PW._Match = must(PW.Match)._NewStore({ log = function() end })
    end,
    afterEach = function(state)
        rawset(PW, "ObjectiveActions", state.registry)
        PW._Match, PW._Call = state.match, state.call
    end,
    cases = {
        {
            name = "Actions: kind registers all seven built-ins with required Update and no subscriptions",
            func = function(state)
                local kind = must(PW.Kinds.Get("objective_actions"))
                expect(kind.Global).to.equal("OBJECTIVEACTION")
                expect(kind.Subscribe).to.equal("never")
                for _, id in ipairs({ "capture", "hold", "defend", "collect", "deny", "plant", "defuse" }) do
                    local def = must(state.registry.Get(id)) --[[@as PW.Entity]]
                    expect(isfunction(def.Update)).to.beTrue()
                end
                local reg = PW.Registry.New("test_actions", { required = kind.Required, log = function() end })
                reg.Register({}, "invalid")
                reg.ResolveAll()
                expect(reg.Get("invalid")).to.beNil()
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
