-- Optional fight-leg planner. No scheduler, movement hook, target or goal writer lives here.
MODULE.Name = "Bots combat movement"

local lib = (rawget(PW, "BotCombatMovement") or {}) --[[@as PW.BotCombatMovementLib]]
PW.BotCombatMovement = lib

function lib.Plan(f, previous, sideRoll, lengthRoll)
    ---@type PW.CombatMovePlan
    local plan = { side = 0, untilAt = f.now + 0.1, target = f.target }
    if not f.visible or not f.grounded or f.nav then return plan end
    if previous ~= nil and previous.slideAt ~= nil and previous.target == f.target and f.now < previous.untilAt then
        local safe = previous.side == -1 and f.left or previous.side == 1 and f.right
        if not safe then return plan end
        plan.side, plan.untilAt, plan.slideAt = previous.side, previous.untilAt, previous.slideAt
        plan.drive = Vector(0, plan.side * f.speed, 0)
        return plan
    end
    if f.sliding then return plan end
    local held = previous ~= nil and previous.target == f.target and f.now < previous.untilAt
    local side = held and previous.side or (sideRoll < 0.5 and -1 or 1)
    if side == 0 then side = sideRoll < 0.5 and -1 or 1 end
    local safe = side == -1 and f.left or side == 1 and f.right
    if not safe then side = -side end
    safe = side == -1 and f.left or side == 1 and f.right
    if not safe then return plan end
    plan.side = side
    plan.untilAt = held and previous.untilAt or f.now + 0.3 + 0.3 * math.Clamp(lengthRoll, 0, 1)
    plan.drive = Vector(0, side * f.speed, 0)
    return plan
end

function lib.Release(intent, plan)
    if plan == nil then return end
    if plan.drive ~= nil and rawequal(intent.drive, plan.drive) then intent.drive = nil end
    if plan.slideAt ~= nil and intent.slideAt == plan.slideAt then intent.slideAt = nil end
end
