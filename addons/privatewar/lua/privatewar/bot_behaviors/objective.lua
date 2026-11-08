-- Built-in behaviour: objective (T-5.10; 07-bots.md d.13, d.14). Objective bucket. Follows the commander's order
-- (board.order) or, until the commander exists (T-5.11), the local pick of PW.BotObjectives.Resolve over the mode's
-- objectives (MODE:BotObjectives, else the Domination flags or the Kill Confirmed tags). Actions:
--   capture, hold: walk into the zone, then drift between points inside it so the bot does not stand like a post;
--   defend: a guard point around the zone, watching outward, moving to another one every 6-12 s;
--   collect, deny: walk onto the tag; the behaviour ends when the tag is gone.
-- Weight: an order 0.55 + 0.45 * weight, scaled by teamwork (bots may ignore orders, 07 d.9); the local pick
-- 0.3 + 0.6 * its score.
BEHAVIOR.Interval = 0.5
BEHAVIOR.MinRun = 2

local inZone = { capture = true, hold = true }
local guard = { defend = true }
local interact = { plant = true, defuse = true }

---@param ctx PW.BotBrainCtx
local function releaseUse(ctx)
    local intent = ctx:Intent()
    intent.buttons = bit.band(intent.buttons or 0, bit.bnot(IN_USE))
end

---@param ctx PW.BotBrainCtx
---@param target PW.BotObjective
---@return boolean
local function validateGoal(ctx, target)
    local goal, commander = ctx.board.goal, PW.BotCommander
    if target.zone == nil or goal == nil then return true end
    if commander ~= nil and goal.projected ~= nil and commander.ArrivalFits(target, goal.projected, goal.radius) then
        return true
    end
    ctx:ClearGoal()
    return false
end

---@return PW.BotObjectivesLib
local function lib()
    return PW.BotObjectives --[[@as PW.BotObjectivesLib]]
end

---@param ctx PW.BotBrainCtx
---@return PW.BotObjective?, number, boolean
local function resolve(ctx)
    local facts = lib().Facts(ctx)
    local st = ctx.state
    return lib().Resolve(ctx, facts, st ~= nil and st.id or ctx.lastObjective)
end

---@param target PW.BotObjective
---@param ctx PW.BotBrainCtx
---@return boolean
local function urgent(target, ctx)
    local value = target.urgency
    if not isnumber(value) or value ~= value or value <= 0 or value == math.huge then return false end
    local tactics = PW.BotTactics
    local contact = tactics ~= nil and tactics.Visible(ctx) or nil
    -- Only legally recognized visible contacts interrupt the advance. No hidden entity positions are read.
    return contact == nil or lib().Facts(ctx).pos:DistToSqr(contact.pos) > 400 * 400
end

---@param ctx PW.BotBrainCtx
---@param target PW.BotObjective
local function aimWhileAdvancing(ctx, target)
    if not urgent(target, ctx) then return end
    local tactics = PW.BotTactics
    local contact = tactics ~= nil and tactics.Visible(ctx) or nil
    if contact == nil then
        if ctx.target ~= nil and not isvector(ctx.target) then ctx:SetTarget(nil) end
        return
    end
    if tactics ~= nil then tactics.Run(ctx, false) end
    -- SetTarget is the public intent/aim boundary; the normal aim controller still enforces reaction/flash/fire.
    ctx:SetTarget(contact.ent)
end

---@param _ Player
---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    if PW.BotObjectives == nil then return false end
    local target = resolve(ctx)
    if target == nil then return false end
    return urgent(target, ctx) and 31 or "objective"
end

---@param _ Player
---@param ctx PW.BotBrainCtx
---@return number
function BEHAVIOR:Weight(_, ctx)
    local target, score, ordered = resolve(ctx)
    if target == nil then return 0 end
    if ordered then
        local teamwork = math.Clamp(lib().Facts(ctx).teamwork, 0, 1)
        return (0.55 + 0.45 * math.Clamp(target.weight, 0, 1)) * (0.5 + 0.5 * teamwork)
    end
    return 0.3 + 0.6 * math.min(score, 1)
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnStart(_, ctx)
    releaseUse(ctx)
    ctx:ClearGoal()
    local target = resolve(ctx)
    if target ~= nil and urgent(target, ctx) then
        -- Do not inherit a suspended fight's direct strafe drive instead of following the new objective goal.
        local intent = ctx:Intent()
        intent.drive, intent.stance = nil, "stand"
    end
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnResume(_, ctx)
    local st = ctx.state
    if st ~= nil then st.next = 0 end
    local target = resolve(ctx)
    if target ~= nil and urgent(target, ctx) then ctx:Intent().drive = nil end
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    releaseUse(ctx)
    lib().LookAt(ctx, nil)
    ctx:Intent().stance = "stand"
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnSuspend(_, ctx)
    releaseUse(ctx)
    lib().LookAt(ctx, nil)
end

---Starts the next leg of an action: approach the objective, or (arrived) move to the next point inside or around it.
---@param ctx PW.BotBrainCtx
---@param st table
---@param target PW.BotObjective
---@param arrived boolean
local function nextLeg(ctx, st, target, arrived)
    local random = function() return lib().Random(ctx) end
    local point, radius, priority, wait = target.pos, 20, "objective", 0.5
    if guard[target.action] then
        point, radius, priority, wait = lib().PointIn(target.pos, target.radius * 1.5, random), 48, "guard",
            6 + 6 * random()
    elseif inZone[target.action] and arrived then
        local center = target.zone ~= nil and target.zone.pos or target.pos
        point, radius, wait = lib().PointIn(center, target.radius * 0.6, random), 40, 3 + 3 * random()
    elseif inZone[target.action] then
        radius, wait = target.radius * 0.5, 0
    end
    if target.zone ~= nil then radius = math.min(radius, target.zone.radius * 0.25) end
    st.id, st.action, st.anchor, st.point, st.next = target.id, target.action, target.pos, point, ctx.now + wait
    st.revision = target.revision
    lib().LookAt(ctx, nil)
    local current = ctx.board.goal
    if current ~= nil and current.priority ~= priority then ctx:ClearGoal() end
    ctx:SetGoal(point, radius, priority --[[@as string]])
    if not validateGoal(ctx, target) then return end
    local tactics = rawget(PW, "BotTactics") --[[@as PW.BotTacticsLib?]]
    if tactics == nil then return end
    if arrived or guard[target.action] then
        tactics.Run(ctx, false)
    else
        tactics.Travel(ctx, point)
    end
end

---A defender that reached its spot watches outward from the zone.
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

---@param st table
---@param target PW.BotObjective
---@return boolean
local function changed(st, target)
    return st.id ~= target.id or st.action ~= target.action or st.revision ~= target.revision or not isvector(st.anchor)
        or (st.anchor --[[@as Vector]]):Distance(target.pos) > 32
end

local retry = { failed = true, unreachable = true }

---@param ctx PW.BotBrainCtx
---@param target PW.BotObjective
---@return PW.BotTransition
local function use(ctx, target)
    local commander = PW.BotCommander
    releaseUse(ctx)
    if commander == nil or not IsValid(ctx.bot) or not ctx.bot:Alive() then
        return PW.BotBrain.Done("interaction unavailable")
    end
    local goal = ctx.board.goal
    if goal ~= nil and not validateGoal(ctx, target) then
        return PW.BotBrain.Done("projected outside interaction zone")
    end
    if not commander.Inside(target, lib().Facts(ctx).pos) then
        ctx:SetGoal(target.pos, math.min(target.radius * 0.25, 16), "objective")
        validateGoal(ctx, target)
        return PW.BotBrain.Continue()
    end
    ctx:ClearGoal()
    lib().LookAt(ctx, target.pos + Vector(0, 0, 16))
    local intent = ctx:Intent()
    intent.sprint, intent.drive = false, nil
    intent.buttons = bit.bor(intent.buttons or 0, IN_USE)
    return PW.BotBrain.Continue()
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    releaseUse(ctx)
    local target = resolve(ctx)
    if target == nil then return PW.BotBrain.Done("objective gone") end
    if interact[target.action] then
        if ctx.state ~= nil then ctx.state.id, ctx.state.revision = target.id, target.revision end
        return use(ctx, target)
    end
    local st = ctx.state or {}
    ctx.lastObjective = target.id
    local status = ctx:GoalStatus()
    local commander, goal = PW.BotCommander, ctx.board.goal
    if goal ~= nil and not validateGoal(ctx, target) then
        return PW.BotBrain.Done("projected outside objective zone")
    end
    if target.zone ~= nil and commander ~= nil and not commander.Inside(target, lib().Facts(ctx).pos) then
        status = nil
    end
    if changed(st, target) or status == nil or retry[status] then
        nextLeg(ctx, st, target, false)
    elseif status == "arrived" and ctx.now >= st.next then
        nextLeg(ctx, st, target, true)
    elseif status == "arrived" and guard[target.action] then
        watch(ctx, target, st.point)
    end
    aimWhileAdvancing(ctx, target)
    return PW.BotBrain.Continue()
end
