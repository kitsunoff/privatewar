-- Tests the actual generic objective-to-goal seam, not merely HP's necessary cylinder helper.
return {
    groupName = "PW Hardpoint shared follower containment",
    cases = {
        {
            name = "Hardpoint: generic follower never accepts an out-of-cylinder projected arrival disc",
            func = function()
                local hp, api, goals = assert(PW.Hardpoint), assert(PW.Bot), assert(PW.BotGoal)
                local actor = assert(player.GetHumans()[1])
                local origin = actor:GetPos()
                ---@type PW.HardpointZone
                local zone = { id = "synthetic", pos = origin + Vector(300, 0, 0),
                    radius = 100, above = 80, below = 8 }
                ---@type PW.BotObjective
                local objective = { id = "hp_synthetic_visit", action = "hold", pos = zone.pos, radius = 24,
                    weight = 1, want = 1, revision = 1, eligible = { [actor:UserID()] = true }, zone = zone }
                ---@type PW.BotBoard
                local board = { bot = actor, intent = { buttons = 0 }, team = 1 }
                stub(goals, "BoardOf").with(function(ply) return ply == actor and board or nil end)
                local projected = zone.pos + Vector(1000, 0, 0)
                stub(goals, "Project").with(function() return projected end)
                stub(assert(PW.BotNav), "RequestPath").with(function()
                    return { status = "queued", partial = false, cached = false, iterations = 0,
                        slices = 0, done = false, from = 1, to = 2 }
                end)
                stub(assert(PW.BotNav), "Cancel").with(function() end)
                ---@type PW.BotBrainCtx
                local ctx = {
                    bot = actor, board = board, now = 10, state = {}, contacts = {}, memory = {}, _api = {},
                    order = { id = objective.id, type = "hold", since = 0, priority = 1, objective = objective },
                    factsAt = 10, facts = { pos = origin, objectives = { objective }, mates = {}, deaths = {},
                        candidates = {}, stationary = false, teamwork = 1 },
                    Intent = function() return assert(board.intent) end,
                    SetGoal = function(_, point, radius, priority)
                        return api.SetGoal(actor, point, radius, priority)
                    end,
                    ClearGoal = function() api.ClearGoal(actor) end,
                    GoalStatus = function() return board.goal ~= nil and board.goal.status or nil end,
                    SetTarget = function() end, Contact = function() end, SearchPlan = function() end
                }
                local behavior = assert(assert(PW.BotBehaviors).Get("objective")) --[[@as PW.BotBehavior]]
                local ok, err = pcall(function()
                    for _, offset in ipairs({ Vector(1000, 0, 0), Vector(0, 0, 500) }) do
                        projected = zone.pos + offset
                        api.ClearGoal(actor)
                        ctx.state = {}
                        behavior:Update(actor, ctx)
                        local goal = board.goal
                        expect(goal == nil or (goal.projected ~= nil
                            and hp.ArrivalFits(zone, goal.projected, goal.radius))).to.beTrue()
                    end
                end)
                api.ClearGoal(actor)
                assert(ok, tostring(err))
            end
        }
    }
}
