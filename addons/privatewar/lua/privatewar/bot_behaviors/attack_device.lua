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
    local devices, aim = PW.BotDevices, PW.BotAim
    local contact = devices ~= nil and devices.Contact(bot) or nil
    if contact == nil or aim == nil or playerThreat(ctx) then
        return PW.BotBrain.Done("device lost or player threat")
    end
    local params = aim.ParamsFor(ctx.board.difficulty)
    local state = ctx.state --[[@as table<string, any>]]
    if state.aim == nil then
        local eye = bot:EyeAngles()
        state.aim = aim.NewState(eye.p, eye.y, params, ctx.now)
        aim.Acquire(state.aim, params, ctx.now, nil)
    end
    local wep = bot:GetActiveWeapon()
    local clip = IsValid(wep) and PW.Adapters.CallFor(wep, "GetClip", wep) or 0
    local tr = util.TraceLine({ start = bot:EyePos(), endpos = contact.position, filter = bot, mask = MASK_SHOT })
    local clear = tr.Entity == contact.device.entity or tr.Fraction >= 0.99
    aim.Step(state.aim, { now = ctx.now, dt = 0.1, eye = bot:EyePos(), point = contact.position, radius = 8,
        canFire = clear and clip > 0 }, params)
    local intent = ctx:Intent()
    ctx:SetTarget(nil)
    intent.view, intent.viewTarget, intent.viewSpeed = Angle(state.aim.p, state.aim.y, 0), nil, nil
    intent.buttons = bit.band(intent.buttons or 0, bit.bnot(bit.bor(IN_ATTACK, IN_RELOAD)))
    if clip <= 0 then intent.buttons = bit.bor(intent.buttons, IN_RELOAD)
    elseif state.aim.fire then intent.buttons = bit.bor(intent.buttons, IN_ATTACK) end
    return PW.BotBrain.Continue()
end

---@param ctx PW.BotBrainCtx
local function release(_, ctx)
    local intent = ctx:Intent()
    intent.buttons = bit.band(intent.buttons or 0, bit.bnot(bit.bor(IN_ATTACK, IN_RELOAD)))
    ctx:SetTarget(nil)
end

BEHAVIOR.OnEnd = release
BEHAVIOR.OnSuspend = release
