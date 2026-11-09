-- Exercise the optional seam through the unchanged fight Action, not a second movement controller.
local id = "bots_combat_movement"

---@return PW.BotBehavior
local function fight() return assert(assert(PW.BotBehaviors).Get("fight")) --[[@as PW.BotBehavior]] end

---@param state table<string, any>
---@return PW.BotBrainCtx
local function context(state)
    local frame = {}
    local target = {} --[[@as Entity]]
    local contact = { ent = target, pos = Vector(400, 0, 0), vel = Vector(), visible = true,
        time = 10, source = "sight" }
    local ctx = assert(PW.BotBrain).NewState().ctx
    local lib = assert(PW.BotTactics)
    local bot = {} --[[@as Player]]
    ctx.bot, ctx.now, ctx.running, ctx.state = bot, 10, "fight", frame
    ctx.board = { bot = bot, _behaviorOwner = frame, intent = { buttons = IN_ATTACK },
        contacts = { contact }, tactics = { at = 10, pos = Vector(), health = 100, maxHealth = 100,
            clip = 30, capacity = 30, reserve = 90, reloading = false, lethal = 0, speed = 400, runSpeed = 400,
            profile = lib.ProfileFor(nil, nil, "veteran") } }
    ctx.contacts, ctx.memory = { contact }, { [target] = contact }
    ctx._api = { clearGoal = function() ctx.board.goal, ctx:Intent().move = nil, nil end,
        walkable = function() return true end }
    state.ctx, state.target = ctx, target
    fight():OnStart(ctx.bot, ctx)
    return ctx
end

return {
    groupName = "PW combat movement ownership",
    beforeEach = function(state)
        state.oldModules, state.oldCall = PW.Registries.modules, PW._Call
        state.registry = PW.Registry.New("modules", { log = function() end, preRegister = function() end })
        PW.Registries.modules = state.registry
        PW._Call = { log = function() end, failed = setmetatable({}, { __mode = "k" }), profile = {} }
        state.registry.Register({ Name = "Test movement", Plan = function(_, _, ctx, old, contact)
            ---@type PW.BotGoal?
            local goal = ctx.board.goal
            local roam = goal ~= nil and goal.priority == "hunt" and goal.status == "moving"
            local plan = assert(PW.BotCombatMovement).Plan({ now = ctx.now, target = contact.ent,
                visible = contact.visible, grounded = true, nav = goal ~= nil and not roam,
                speed = 400, left = true, right = true,
                sliding = false }, old, 0, 0)
            plan.releaseGoal = roam and goal or nil
            return plan
        end }, id)
        state.registry.ResolveAll()
        stub(assert(PW.BotTactics), "Random").returns(0)
    end,
    afterEach = function(state)
        state.registry._Release()
        PW.Registries.modules, PW._Call = state.oldModules, state.oldCall
    end,
    cases = {
        {
            name = "Default ON next-match snapshot: editing flags does not change the current valid module",
            func = function(state)
                local enable = assert(PW.Enable)
                local convar = assert(GetConVar("pw_module_bots_combat_movement_enabled"))
                expect(convar:GetDefault()).to.equal("1")
                local registry = state.registry --[[@as PW.Registry]]
                local def = assert(registry.Get(id))
                local on = true
                local snapshot = enable._TakeSnapshot({ modules = registry }, function() return on end)
                enable._Apply({ modules = registry }, snapshot)
                on = false
                expect(assert(def.IsValid)(def)).to.beTrue()
                snapshot = enable._TakeSnapshot({ modules = registry }, function() return on end)
                enable._Apply({ modules = registry }, snapshot)
                expect(assert(def.IsValid)(def)).to.beFalse()
                on = true
                expect(assert(def.IsValid)(def)).to.beFalse()
                snapshot = enable._TakeSnapshot({ modules = registry }, function() return on end)
                enable._Apply({ modules = registry }, snapshot)
                expect(assert(def.IsValid)(def)).to.beTrue()
            end
        },
        {
            name = "Action ownership: only the fight frame drives; nav/direct precedence preserves a foreign goal",
            func = function(state)
                local ctx = context(state)
                fight():Update(ctx.bot, ctx)
                expect(assert(ctx:Intent().drive).y).to.equal(-400)
                local goal = { point = Vector(100, 0, 0), radius = 16, priority = "critical",
                    status = "moving", since = 10 } --[[@as PW.BotGoal]]
                ctx.board.goal, ctx:Intent().move = goal, Vector(100, 0, 0)
                ctx.now = 10.1
                fight():Update(ctx.bot, ctx)
                expect(ctx:Intent().drive).to.beNil()
                expect(ctx.board.goal).to.equal(goal)
                expect(assert(ctx:Intent().move).x).to.equal(100)
            end
        },
        {
            name = "Acquisition: active fight releases only an exact inherited hunt goal before direct drive",
            func = function(state)
                local ctx = context(state)
                ctx.board.goal = { point = Vector(100, 0, 0), radius = 16, priority = "hunt",
                    status = "moving", since = 9 }
                ctx:Intent().move = Vector(100, 0, 0)
                fight():Update(ctx.bot, ctx)
                expect(ctx.board.goal).to.beNil()
                expect(ctx:Intent().move).to.beNil()
                expect(assert(ctx:Intent().drive).y).to.equal(-400)
            end
        },
        {
            name = "Off missing module and runtime failure all fall back to legacy fight without changing utility",
            func = function(state)
                local registry = state.registry --[[@as PW.Registry]]
                local get, missing = registry.Get, false
                stub(registry, "Get").with(function(key)
                    if missing and key == id then return nil end
                    return get(key)
                end)
                for _, kind in ipairs({ "off", "missing", "failure" }) do
                    missing = false
                    registry._Enable(id)
                    local ctx = context(state)
                    fight():Update(ctx.bot, ctx)
                    local old = ctx:Intent().drive
                    if kind == "off" then registry._Disable(id, "test")
                    elseif kind == "missing" then missing = true
                    else
                        registry.Register({ Name = "Failing movement",
                            Plan = function() error("test failure") end }, id)
                    end
                    ctx.now = 10.1
                    fight():Update(ctx.bot, ctx)
                    expect(ctx:Intent().drive ~= nil).to.beTrue()
                    expect(rawequal(ctx:Intent().drive, old)).to.beFalse()
                    expect(fight():Rank(ctx.bot, ctx)).to.equal("combat")
                    expect(fight():Weight(ctx.bot, ctx)).to.equal(1)
                end
            end
        },
        {
            name = "Reentrant proposal: a newer movement owner survives the older planner's return",
            func = function(state)
                local ctx = context(state)
                local foreign, target = Vector(0, 123, 0), {} --[[@as Entity]]
                ---@type Entity
                local originalTarget = state.target
                state.registry.Register({ Name = "Handoff movement", Plan = function()
                    ctx.board._behaviorOwner = {}
                    ctx:Intent().drive, ctx:Intent().slideAt = foreign, 10
                    ctx:SetTarget(target)
                    return { side = -1, untilAt = 10.5, target = originalTarget,
                        drive = Vector(0, -400, 0), slideAt = 10 }
                end }, id)
                fight():Update(ctx.bot, ctx)
                expect(rawequal(ctx:Intent().drive, foreign)).to.beTrue()
                expect(ctx:Intent().slideAt).to.equal(10)
                expect(ctx.board.target).to.equal(target)
            end
        },
        {
            name = "Reentrant ClearGoal: a newer frame keeps its goal drive slide target and fire inputs",
            func = function(state)
                local ctx = context(state)
                local foreign, target = Vector(0, 123, 0), {} --[[@as Entity]]
                local newer = {}
                local goal = { point = Vector(200, 0, 0), radius = 16, priority = "critical",
                    status = "moving", since = 10 } --[[@as PW.BotGoal]]
                ctx.board.goal = { point = Vector(100, 0, 0), radius = 16, priority = "hunt",
                    status = "moving", since = 9 }
                ---@type Entity
                local originalTarget = state.target
                state.registry.Register({ Name = "Goal handoff movement", Plan = function()
                    return { side = -1, untilAt = 10.5, target = originalTarget, releaseGoal = ctx.board.goal,
                        drive = Vector(0, -400, 0), slideAt = 10 }
                end }, id)
                ctx._api.clearGoal = function()
                    ctx.board._behaviorOwner, ctx.board.goal = newer, goal
                    ctx:Intent().drive, ctx:Intent().slideAt = foreign, 11
                    ctx:Intent().buttons, ctx:Intent().sprint = IN_RELOAD, true
                    ctx:SetTarget(target)
                end
                fight():Update(ctx.bot, ctx)
                expect(rawequal(ctx:Intent().drive, foreign)).to.beTrue()
                expect(ctx:Intent().slideAt).to.equal(11)
                expect(ctx.board._behaviorOwner).to.equal(newer)
                expect(ctx.board.goal).to.equal(goal)
                expect(ctx.board.target).to.equal(target)
                expect(ctx:Intent().buttons).to.equal(IN_RELOAD)
                expect(ctx:Intent().sprint).to.beTrue()
                expect((ctx.state --[[@as table<string, any>]]).combatMove).to.beNil()
                expect(assert(PW.BotTactics).Marked(ctx.board, "tactics.slide", 10)).to.beFalse()
            end
        },
        {
            name = "Brain teardown: death and round relationship reset release the active fight frame",
            func = function(state)
                local brain = assert(PW.BotBrain)
                for _, reason in ipairs({ "dead", "relationships changed" }) do
                    local ctx = context(state)
                    local runner = brain.NewState()
                    local env = { bot = ctx.bot, board = ctx.board, behaviors = { fight() }, api = ctx._api,
                        random = function() return 0 end }
                    brain.Think(runner, env, 10)
                    expect(ctx:Intent().drive ~= nil).to.beTrue()
                    brain.Stop(runner, env, 10.1, reason)
                    expect(#runner.stack).to.equal(0)
                    expect(ctx:Intent().drive).to.beNil()
                    expect(ctx:Intent().slideAt).to.beNil()
                end
            end
        },
        {
            name = "Target loss death round reset suspend and end release only the current visit's resources",
            func = function(state)
                for _, event in ipairs({ "lost", "suspend", "end", "death", "round" }) do
                    local ctx = context(state)
                    fight():Update(ctx.bot, ctx)
                    if event == "lost" then
                        ctx.contacts, ctx.target = {}, nil
                        fight():Update(ctx.bot, ctx)
                    elseif event == "suspend" then fight():OnSuspend(ctx.bot, ctx)
                    else fight():OnEnd(ctx.bot, ctx) end
                    expect(ctx:Intent().drive).to.beNil()
                    expect(ctx:Intent().buttons).to.equal(IN_ATTACK)
                end
                local ctx = context(state)
                fight():Update(ctx.bot, ctx)
                local plan = assert((ctx.state --[[@as table<string, any>]]).combatMove)
                plan.slideAt = 10
                local foreign = Vector(0, assert(ctx:Intent().drive).y, 0)
                ctx:Intent().drive, ctx:Intent().slideAt = foreign, 10
                ctx.board._behaviorOwner = {}
                fight():OnEnd(ctx.bot, ctx)
                expect(rawequal(ctx:Intent().drive, foreign)).to.beTrue()
                expect(ctx:Intent().slideAt).to.equal(10)
            end
        }
    }
}
