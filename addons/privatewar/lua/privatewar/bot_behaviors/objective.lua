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

---@param ctx PW.BotBrainCtx
local function releaseUse(ctx)
    local intent = ctx:Intent()
    intent.buttons = bit.band(intent.buttons or 0, bit.bnot(IN_USE))
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
    local target = resolve(ctx)
    if target ~= nil and urgent(target, ctx) then ctx:Intent().drive = nil end
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    lib().EndAction(ctx)
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnSuspend(_, ctx)
    lib().EndAction(ctx)
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    releaseUse(ctx)
    local target = resolve(ctx)
    if target == nil then
        lib().EndAction(ctx)
        return PW.BotBrain.Done("objective gone")
    end
    -- Rank is cached for 0.5s. A recognized enemy can approach inside that interval without a new-sight nudge.
    if (target.urgency or 0) > 0 and not urgent(target, ctx) then
        return PW.BotBrain.Done("recognized near threat")
    end
    local result = lib().RunAction(ctx, target)
    if result.kind == "continue" then aimWhileAdvancing(ctx, target) end
    return result
end
