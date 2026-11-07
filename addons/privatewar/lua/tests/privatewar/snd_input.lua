-- A real player bot holds E via the ordinary behaviour -> intent -> StartCommand path. No teleport/damage smoke.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil, "expected input contract") return value end

---@param bot Player
---@param action string
---@return PW.BotBrainCtx, PW.BotBehavior
local function context(bot, action)
    local pos, id = bot:GetPos(), bot:UserID()
    local objective = { id = "input_site", pos = pos, radius = 64, action = action, weight = 1, want = 1,
        revision = 1, eligible = { [id] = true }, zone = { pos = pos, radius = 64, above = 72, below = 16 } }
    ---@type table<string, any>
    local board = { bot = bot, intent = { buttons = 0 }, order = { id = objective.id, objective = objective,
        type = action, priority = 1, since = 0 } }
    ---@type table<string, any>
    local ctx = { bot = bot, board = board, now = CurTime(), state = {}, order = board.order,
        _api = { facts = function()
            return { pos = bot:GetPos(), team = bot:Team(), objectives = {}, mates = {}, deaths = {},
                candidates = {}, stationary = false, teamwork = 1 }
        end } }
    ctx.Intent = function() return board.intent end
    ctx.ClearGoal = function() board.goal = nil end
    ctx.SetGoal = function(_, point, radius, priority)
        board.goal = { point = point, radius = radius, priority = priority, status = "moving", since = CurTime() }
        return true, "moving"
    end
    ctx.GoalStatus = function() return board.goal ~= nil and board.goal.status or nil end
    ctx.SetTarget = function(_, target) board.target = target board.intent.target = target end
    return ctx --[[@as PW.BotBrainCtx]], must(PW.BotBehaviors.Get("objective")) --[[@as PW.BotBehavior]]
end

return {
    groupName = "PW SND ordinary input",
    beforeAll = function(state)
        state.bot = player.CreateNextBot("PW SND input")
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then
            bot:SetTeam(must(PW.MatchRules).FreeTeam)
            must(PW.MatchRules).Spawn(bot)
        end
    end,
    afterAll = function(state)
        timer.Remove("PW.SNDInputSmoke")
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then must(PW.BotInput).SetScripted(bot, nil) bot:Kick("SND input finished") end
    end,
    cases = {
        { name = "SND input: plant defuse hold use and suspend end revision range release it", func = function(state)
            local bot = must(state.bot --[[@as Player?]])
            expect(IsValid(bot)).to.beTrue()
            for _, action in ipairs({ "plant", "defuse" }) do
                local ctx, behavior = context(bot, action)
                PW.Call(behavior, "OnStart", bot, ctx)
                PW.Call(behavior, "Update", bot, ctx)
                expect(bit.band(ctx:Intent().buttons, IN_USE) ~= 0).to.beTrue()
                PW.Call(behavior, "OnSuspend", bot, ctx)
                expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
                PW.Call(behavior, "OnResume", bot, ctx)
                PW.Call(behavior, "Update", bot, ctx)
                expect(bit.band(ctx:Intent().buttons, IN_USE) ~= 0).to.beTrue()
                must(must(ctx.order).objective.zone).pos = bot:GetPos() + Vector(0, 0, 200)
                ctx.now = ctx.now + 1
                PW.Call(behavior, "Update", bot, ctx)
                expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
                PW.Call(behavior, "OnEnd", bot, ctx)
                expect(bit.band(ctx:Intent().buttons, IN_USE)).to.equal(0)
            end
        end },
        { name = "SND input: real StartCommand holds E through an ordinary five-second plant", async = true,
            timeout = 15, func = function(state)
                local bot = must(state.bot --[[@as Player?]])
                expect(IsValid(bot) and bot:Alive()).to.beTrue()
                local ctx, behavior = context(bot, "plant")
                local lib = must(PW.SND)
                local pos, now = bot:GetPos(), CurTime()
                local map = { sites = {
                    { id = "A", pos = pos, approach = pos, radius = 160, above = 96, below = 16 },
                    { id = "B", pos = pos + Vector(500, 0, 0), approach = pos + Vector(500, 0, 0),
                        radius = 160, above = 96, below = 16 }
                }, bomb = pos, spawns = { [1] = { { pos = pos, yaw = 0 } }, [2] = { { pos = pos, yaw = 0 } } } }
                local actors = { { id = "bot", userId = bot:UserID(), team = 1, pos = pos, alive = true,
                    use = false, clear = true, generation = 1 },
                { id = "opponent", userId = 999, team = 2, pos = pos + Vector(500, 0, 0), alive = true,
                    use = false, clear = true, generation = 1 } }
                local round = lib.NewRound(map, actors, now, 1, "bot")
                PW.Call(behavior, "OnStart", bot, ctx)
                must(PW.BotInput).SetScripted(bot, ctx:Intent())
                timer.Create("PW.SNDInputSmoke", 0.1, 80, function()
                    ctx.now = CurTime()
                    PW.Call(behavior, "Update", bot, ctx)
                    actors[1].pos, actors[1].use = bot:GetPos(), bot:KeyDown(IN_USE)
                    lib.Step(round, CurTime(), actors)
                    if round.phase ~= "planted" and CurTime() - now < 7.8 then return end
                    timer.Remove("PW.SNDInputSmoke")
                    must(PW.BotInput).SetScripted(bot, nil)
                    PW.Call(behavior, "OnEnd", bot, ctx)
                    expect(round.phase).to.equal("planted")
                    expect(round.fuse >= now + 50).to.beTrue()
                    done()
                end)
            end }
    }
}
