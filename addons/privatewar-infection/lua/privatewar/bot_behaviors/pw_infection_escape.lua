-- Survivor-only legs and target requests. Aim, navigation and input remain the sole engine writers.
BEHAVIOR.Modes = { "pw_infection" }
BEHAVIOR.Interval = 0.1
BEHAVIOR.MinRun = 0

local roles = PW.Infection --[[@as PW.InfectionLib]]
local tactics = PW.BotTactics --[[@as PW.BotTacticsLib]]
local angles = { 0, 45, -45, 80, -80, 0, 45, -45 }

---@param bot Player
---@param ctx PW.BotBrainCtx
function BEHAVIOR:Rank(bot, ctx)
    return roles.Role(bot) == "survivor" and tactics.Visible(ctx) ~= nil and "survival" or false
end

function BEHAVIOR:Weight() return 2 end

---@param bot Player
---@param ctx PW.BotBrainCtx
---@param point Vector
---@return boolean
local function clearRoute(bot, ctx, point)
    if not tactics.Walkable(ctx, point) then return false end
    if ctx._api.walkable ~= nil then return true end -- injected local geometry boundary in deterministic tests
    local up = Vector(0, 0, 2)
    return not util.TraceHull({ start = bot:GetPos() + up, endpos = point + up,
        mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 64), mask = MASK_SOLID_BRUSHONLY }).Hit
end

---@param bot Player
---@param ctx PW.BotBrainCtx
---@param threat PW.BotContact
---@return Vector?
local function escapePoint(bot, ctx, threat)
    local pos = bot:GetPos()
    local away = pos - threat.pos
    away.z = 0
    if away:IsZero() then away = Vector(1, 0, 0) end
    local yaw = away:Angle().y
    for i, angle in ipairs(angles) do
        local distance = i > 5 and 128 or 384
        local point = pos + Angle(0, yaw + angle, 0):Forward() * distance
        if point:DistToSqr(threat.pos) > pos:DistToSqr(threat.pos) and clearRoute(bot, ctx, point)
            and ctx:SetGoal(point, 32, "tactical") then return point end
    end
    return nil
end

---@param bot Player
---@param ctx PW.BotBrainCtx
function BEHAVIOR:Update(bot, ctx)
    local contact = tactics.Visible(ctx)
    if contact == nil or roles.Role(bot) ~= "survivor" then return assert(PW.BotBrain).Done("threat lost") end
    local intent, state = ctx:Intent(), assert(ctx.state)
    intent.drive, intent.weapon, intent.sprint, intent.stance = nil, nil, nil, "stand"
    ctx:SetTarget(contact.ent) -- a walking retreat can fire through the ordinary reaction/LOS/settled-aim gate
    local distance = bot:GetPos():Distance(contact.pos)
    if distance >= 600 then
        ctx:ClearGoal()
        state.point = nil
    elseif ctx.now >= (state.nextPlan or 0) then
        state.nextPlan = ctx.now + 0.5
        state.point = escapePoint(bot, ctx, contact)
        if state.point == nil then ctx:ClearGoal() end
    end
    if state.point ~= nil and distance < 110 then intent.sprint = true ctx:SetTarget(nil) end
    local f = tactics.FactsOf(ctx)
    tactics.SetButton(intent, IN_RELOAD, f.clip == 0 and f.reserve > 0 and not f.reloading)
    return assert(PW.BotBrain).Continue()
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    ctx:SetTarget(nil)
    ctx:ClearGoal()
    local intent = ctx:Intent()
    intent.drive, intent.sprint, intent.weapon = nil, nil, nil
    tactics.SetButton(intent, IN_RELOAD, false)
    local state = ctx.state --[[@as table<string, any>?]]
    if state ~= nil then state.point, state.nextPlan = nil, nil end
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnSuspend(bot, ctx) self:OnEnd(bot, ctx) end
