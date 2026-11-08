-- A lower-than-player-combat action. Native weapon fire only, through the existing input writer.
BEHAVIOR.Interval = 0.1
BEHAVIOR.MinRun = 0.1

---@param ctx PW.BotBrainCtx
---@return boolean
local function playerThreat(ctx)
    for _, contact in ipairs(ctx.contacts or {}) do
        if contact.visible or ctx.now - contact.time < 1 then return true end
    end
    return false
end

---@param bot Player
---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(bot, ctx)
    local devices = PW.BotDevices
    return devices ~= nil and devices.AttackWanted(playerThreat(ctx), devices.Contact(bot) ~= nil) and 25 or false
end

function BEHAVIOR:Weight() return 1 end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnStart(_, ctx)
    ctx:ClearGoal()
    ctx:SetTarget(nil)
    ctx:Intent().sprint = false
end

---@param bot Player
---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(bot, ctx)
    local devices = PW.BotDevices
    local contact = devices ~= nil and devices.Contact(bot) or nil
    if contact == nil or PW.BotAim == nil or playerThreat(ctx) then
        return PW.BotBrain.Done("device lost or player threat")
    end
    -- The owned controller evaluates current contact and shot LOS every engine tick, like player-target aim.
    if devices ~= nil then devices.OwnInput(bot, ctx:Intent()) end
    ctx:SetTarget(nil)
    return PW.BotBrain.Continue()
end

---@param bot Player
---@param ctx PW.BotBrainCtx
local function release(_, bot, ctx)
    if PW.BotDevices ~= nil then PW.BotDevices.ReleaseInput(bot) end
    local intent = ctx:Intent()
    intent.buttons = bit.band(intent.buttons or 0, bit.bnot(bit.bor(IN_ATTACK, IN_RELOAD)))
    ctx:SetTarget(nil)
end

BEHAVIOR.OnEnd = release
BEHAVIOR.OnSuspend = release
