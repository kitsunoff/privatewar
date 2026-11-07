-- Built-in behaviour: throw_equipment (T-5.10; 07-bots.md d.13, bucket combat). A grenade at an enemy that was seen
-- moments ago and is now behind cover, at a throwable range: look at its remembered position (the aim never fires at
-- a remembered contact), then use the lethal slot through the equipment module (05-loadout.md d.11:
-- PW.Equipment.Use is the bot path; since T-11.4 it switches the bot to the grenade SWEP, throws it and switches
-- back). Without the equipment module the bot has no lethal and this never runs.
-- Grenades into an objective zone belong to the objective half of T-5.10.
BEHAVIOR.Interval = 0.5
BEHAVIOR.MinRun = 0.5
BEHAVIOR.Cooldown = 12

local turnTime, maxAimError, giveUp = 0.6, 8, 2

---@return PW.BotTacticsLib?
local function tactics()
    return rawget(PW, "BotTactics")
end

---@param c PW.BotContact
---@return boolean
local function sighting(c)
    local lib = tactics()
    return lib ~= nil and not lib.FightSounds[c.source]
end

---@param ctx PW.BotBrainCtx
---@return PW.BotContact?
local function target(ctx)
    local lib = tactics()
    if lib == nil then return nil end
    local f = lib.FactsOf(ctx)
    if f.lethal <= 0 or lib.Visible(ctx) ~= nil then return nil end
    local c = lib.Lost(ctx, lib.Config.throwAge, sighting)
    if c == nil then return nil end
    local d = f.pos:Distance(c.pos)
    if d < lib.Config.throwMin or d > lib.Config.throwMax then return nil end
    return c
end

---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    return target(ctx) ~= nil and "combat" or false
end

---@return number
function BEHAVIOR:Weight()
    return 1
end

---The aim error of the last aim step, degrees; nil when the aim has not written one.
---@param ctx PW.BotBrainCtx
---@return number?
local function aimError(ctx)
    local debugInfo = ctx.board.debug --[[@as table<string, any>?]]
    local aim = debugInfo ~= nil and debugInfo.aim or nil
    local err = aim ~= nil and aim.err or nil
    return isnumber(err) and err or nil
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local lib = tactics()
    if lib == nil then return PW.BotBrain.Done("no tactics") end
    local st = ctx.state --[[@as table<string, any>]]
    if st.since == nil then
        local c = target(ctx)
        if c == nil then return PW.BotBrain.Done("no grenade target") end
        st.since = ctx.now
        ctx:SetTarget(c.ent)
        return PW.BotBrain.Continue()
    end
    local waited = ctx.now - (tonumber(st.since) or ctx.now)
    if waited < turnTime then return PW.BotBrain.Continue() end
    local err = aimError(ctx)
    if err ~= nil and err > maxAimError and waited < giveUp then
        return PW.BotBrain.Continue()
    end
    if lib.UseEquipment(ctx, "lethal") then return PW.BotBrain.Done("grenade thrown") end
    return PW.BotBrain.Done("no grenade")
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    ctx:SetTarget(nil)
end
