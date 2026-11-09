-- Ordinary legs: at most eight traces per update. A prospective dodge adds at most seventeen more.
local lib = assert(PW.BotCombatMovement)

function lib.Safe(bot, side, distance, direction)
    if distance ~= distance or distance > 512 or distance <= 0 then return false end
    local pos = bot:GetPos()
    local axis = direction or Angle(0, bot:EyeAngles().y, 0):Right() * side
    local delta = axis * distance
    local mins, maxs = bot:GetHull()
    local lift = Vector(0, 0, 2)
    local hull = util.TraceHull({ start = pos + lift, endpos = pos + delta + lift,
        mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = bot })
    if hull.StartSolid or hull.AllSolid or hull.Fraction < 1 then return false end
    local samples = math.ceil(distance / 32)
    for i = 1, samples do
        local point = pos + delta * (i / samples)
        local ground = util.TraceLine({ start = point + Vector(0, 0, 18), endpos = point - Vector(0, 0, 18),
            mask = MASK_PLAYERSOLID, filter = bot })
        if not ground.Hit or ground.StartSolid or ground.HitNormal.z < 0.7 then return false end
    end
    return true
end

---@param bot Player
---@param ctx PW.BotBrainCtx
---@param previous PW.CombatMovePlan?
---@param contact PW.BotContact
---@return PW.CombatMovePlan?
function MODULE:Plan(bot, ctx, previous, contact)
    if not IsValid(bot) or not isentity(bot) or not bot:IsPlayer() then return nil end
    if ctx.board._behaviorOwner ~= ctx.state then return nil end
    local goal, intent = ctx.board.goal, ctx:Intent()
    local roam = goal ~= nil and goal.status == "moving" and goal.priority == "hunt"
    local nav = not roam and ((goal ~= nil and goal.status == "moving") or intent.move ~= nil)
    if previous ~= nil and previous.drive ~= nil and not rawequal(intent.drive, previous.drive) then nav = true end
    local grounded = bot:Alive() and bot:OnGround() and bot:GetMoveType() == MOVETYPE_WALK and bot:WaterLevel() <= 1
    local visible = contact.visible and IsValid(contact.ent)
        and (not contact.ent:IsPlayer() or (contact.ent --[[@as Player]]):Alive())
    ---@type PW.CombatMoveInput
    local f = { now = ctx.now, target = contact.ent, visible = visible, grounded = grounded,
        nav = nav, speed = bot:GetRunSpeed(), left = false, right = false, sliding = false }
    local getSliding = (bot --[[@as table<string, any>]]).GetSliding
    if isfunction(getSliding) then f.sliding = getSliding(bot) == true end
    if f.visible and grounded and not nav and (not f.sliding or (previous ~= nil and previous.slideAt ~= nil)) then
        local distance = math.Clamp(bot:GetVelocity():Length2D() * 0.2, 48, 96)
        if previous ~= nil and previous.slideAt ~= nil then
            local velocity = bot:GetVelocity()
            velocity.z = 0
            velocity:Normalize()
            local safe = assert(lib.Safe)(bot, previous.side, distance, velocity)
            f.left, f.right = previous.side == -1 and safe, previous.side == 1 and safe
        else
            f.left, f.right = assert(lib.Safe)(bot, -1, distance), assert(lib.Safe)(bot, 1, distance)
        end
    end
    local tactics = assert(PW.BotTactics)
    local plan = lib.Plan(f, previous, tactics.Random(), tactics.Random())
    if roam and f.visible and grounded and not f.sliding then plan.releaseGoal = goal end
    if plan.side == 0 or plan.slideAt ~= nil or f.sliding or bot:Crouching() then return plan end
    if bot:GetVelocity():Length2D() <= bot:GetRunSpeed() * 0.5 then return plan end
    local velocity = bot:GetVelocity()
    velocity.z = 0
    velocity:Normalize()
    if velocity:Dot(Angle(0, bot:EyeAngles().y, 0):Right() * plan.side) < 0.95 then return plan end
    if not tactics.SlideReady(ctx, "dodge") then return plan end
    local quickSlide = rawget(PW, "BotQuickSlide") --[[@as PW.BotQuickSlideLib?]]
    if quickSlide == nil then return plan end
    local duration = quickSlide.Duration()
    -- No mid-slide steering: require the entire conservative launch corridor before requesting the keys.
    local distance = bot:GetRunSpeed() * duration * 1.5 + 32
    if not assert(lib.Safe)(bot, plan.side, distance, velocity) then return plan end
    plan.slideAt, plan.untilAt = ctx.now, ctx.now + duration
    return plan
end
