-- Legacy approach, zone drift, guard watching and touch movement; no mode verdicts or scoring here.
OBJECTIVEACTION.Abstract = true

---@return PW.BotObjectivesLib
local function lib() return assert(PW.BotObjectives) end

---@param ctx PW.BotBrainCtx
---@param st table
---@param target PW.BotObjective
---@param arrived boolean
---@param motion string?
local function nextLeg(ctx, st, target, arrived, motion)
    local random = function() return lib().Random(ctx) end
    local point, radius, priority, wait = target.pos, 20, "objective", 0.5
    if motion == "guard" then
        point, radius, priority, wait = lib().PointIn(target.pos, target.radius * 1.5, random), 48, "guard",
            6 + 6 * random()
    elseif motion == "zone" and arrived then
        local center = target.zone ~= nil and target.zone.pos or target.pos
        point, radius, wait = lib().PointIn(center, target.radius * 0.6, random), 40, 3 + 3 * random()
    elseif motion == "zone" then
        radius, wait = target.radius * 0.5, 0
    end
    if target.zone ~= nil then radius = math.min(radius, target.zone.radius * 0.25) end
    st.anchor, st.point, st.next = target.pos, point, ctx.now + wait
    lib().LookAt(ctx, nil)
    local current = ctx.board.goal
    if current ~= nil and current.priority ~= priority then ctx:ClearGoal() end
    ctx:SetGoal(point, radius, priority)
    if not lib().ValidateGoal(ctx, target) then return end
    local tactics = PW.BotTactics
    if tactics == nil then return end
    if arrived or motion == "guard" then tactics.Run(ctx, false) else tactics.Travel(ctx, point) end
end

---@param ctx PW.BotBrainCtx
---@param target PW.BotObjective
---@param point Vector
local function watch(ctx, target, point)
    local out = point - target.pos
    out.z = 0
    if out:IsZero() then out = Vector(1, 0, 0) end
    out:Normalize()
    lib().LookAt(ctx, point + out * 600 + Vector(0, 0, 60))
end

local retry = { failed = true, unreachable = true }

---@param _ Player
---@param ctx PW.BotBrainCtx
---@param target PW.BotObjective
---@param st table
---@return PW.BotTransition
function OBJECTIVEACTION:Update(_, ctx, target, st)
    ctx.lastObjective = target.id
    local status = ctx:GoalStatus()
    local commander, goal = PW.BotCommander, ctx.board.goal
    if goal ~= nil and not lib().ValidateGoal(ctx, target) then
        return assert(PW.BotBrain).Done("projected outside objective zone")
    end
    if target.zone ~= nil and commander ~= nil and not commander.Inside(target, lib().Facts(ctx).pos) then
        status = nil
    end
    if st.anchor == nil or (st.anchor --[[@as Vector]]):Distance(target.pos) > 32
        or status == nil or retry[status] then
        nextLeg(ctx, st, target, false, self.Motion)
    elseif status == "arrived" and ctx.now >= st.next then
        nextLeg(ctx, st, target, true, self.Motion)
    elseif status == "arrived" and self.Motion == "guard" then
        watch(ctx, target, st.point)
    end
    return assert(PW.BotBrain).Continue()
end
