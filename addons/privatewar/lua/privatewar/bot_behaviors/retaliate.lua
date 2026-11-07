-- Built-in behaviour: retaliate (T-5.10; 07-bots.md d.7, d.13, bucket survival). Took damage from an attacker it
-- does not see: make the attacker the target, so the aim turns toward the direction the damage revealed with its
-- human-like spring (no snap). Ends when the attacker is in sight (fight takes over) or the damage is old.
BEHAVIOR.Interval = 0.1
BEHAVIOR.MinRun = 0.3
BEHAVIOR.Cooldown = 0.5

local giveUp = 2.5

---@return PW.BotTacticsLib?
local function tactics()
    return rawget(PW, "BotTactics")
end

---@param ctx PW.BotBrainCtx
---@return boolean
local function wanted(ctx)
    local lib = tactics()
    if lib == nil then return false end
    local attacker = lib.FactsOf(ctx).attacker
    if attacker == nil or not lib.Hurt(ctx, lib.Config.hurtWindow) then return false end
    local c = ctx:Contact(attacker)
    return c == nil or not c.visible
end

---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    return wanted(ctx) and "survival" or false
end

---@return number
function BEHAVIOR:Weight()
    return 1.2
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnStart(_, ctx)
    local lib = tactics()
    if lib == nil then return end
    local f = lib.FactsOf(ctx)
    ctx:Intent().stance = lib.Random() < f.profile.crouch and "crouch" or "stand"
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local lib = tactics()
    if lib == nil then return PW.BotBrain.Done("no tactics") end
    local attacker = lib.FactsOf(ctx).attacker
    if attacker == nil then return PW.BotBrain.Done("no attacker") end
    if ctx.target ~= attacker then ctx:SetTarget(attacker) end
    local c = ctx:Contact(attacker)
    if c ~= nil and c.visible then return PW.BotBrain.Done("attacker in sight") end
    if not lib.Hurt(ctx, giveUp) then return PW.BotBrain.Done("attacker not found") end
    return PW.BotBrain.Continue()
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    ctx:Intent().stance = "stand"
end
