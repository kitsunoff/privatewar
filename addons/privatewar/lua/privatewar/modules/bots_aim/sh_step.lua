-- Bots aim, one aim step and the dev command parser (T-5.8; included by shared.lua, see the decisions there). Pure:
-- plain numbers and vectors in, the updated per-bot state out. The glue in init.lua feeds the facts of a tick and
-- copies the state's view and fire decision into the intent.

local lib = PW.BotAim --[[@as PW.BotAimLib]]

---@param dp number
---@param dy number
---@return number
local function length(dp, dy)
    return math.sqrt(dp * dp + dy * dy)
end

---Settle and fire decision of a step: the view held within the tolerance for settleTime, the attack delay passed,
---an entity target seen now, then (only then) one line-of-fire trace. A settled view stays settled while the error
---is within holdTolerance tolerances (hysteresis), so the spring chasing the focus error does not chatter the gate.
---@param s PW.BotAimState
---@param input PW.BotAimInput
---@param params PW.BotAimParams
---@return boolean
local function decideFire(s, input, params)
    local now = input.now
    local limit = s.tolerance
    if s.settledSince ~= nil then limit = math.min(limit * lib.Config.holdTolerance, lib.Config.maxTolerance) end
    if s.err > limit then
        s.settledSince, s.blockedSince = nil, nil
        return false
    end
    s.settledSince = s.settledSince or now
    if not input.canFire or now - s.settledSince < lib.Config.settleTime then return false end
    if now - s.acquiredAt < params.attack_delay then return false end
    if input.lineOfFire == nil or input.lineOfFire() then
        s.blockedSince = nil
        return true
    end
    s.blockedSince = s.blockedSince or now
    return false
end

function lib.Step(s, input, params, roll)
    local dt = input.dt
    local baseP, baseY = lib.AnglesTo(input.eye, input.point)
    local gvp, gvy, moved = 0, 0, 0
    -- Sight lost or regained moves the aim point between the remembered and the seen position: the bot learns
    -- where the target is, the target did not move. The spring still turns the view; the focus does not reset.
    local switched = s.sighted ~= nil and s.sighted ~= input.canFire
    s.sighted = input.canFire
    if s.baseP ~= nil and dt > 0 and not switched then
        local dp, dy = math.AngleDifference(baseP, s.baseP), math.AngleDifference(baseY, s.baseY)
        local cap = params.turn_max_speed
        moved = length(dp, dy)
        gvp, gvy = math.Clamp(dp / dt, -cap, cap), math.Clamp(dy / dt, -cap, cap)
    end
    s.baseP, s.baseY = baseP, baseY
    lib.Wander(s, params, input.now, dt, roll)
    lib.Focus(s, moved, params, dt)
    local rp, ry = lib.RecoilOffset(input.kickP or 0, input.kickY or 0, params)
    local limit = lib.Config.pitchLimit
    s.goalP = math.Clamp(baseP + s.offP * s.focus + rp, -limit, limit)
    s.goalY = math.NormalizeAngle(baseY + s.offY * s.focus + ry)
    lib.Spring(s, s.goalP, s.goalY, params, dt, gvp, gvy)
    s.err = length(math.AngleDifference(s.goalP, s.p), math.AngleDifference(s.goalY, s.y))
    s.tolerance = lib.Tolerance(input.radius, (input.point - input.eye):Length(), s.focus)
    s.fire = decideFire(s, input, params)
    if s.fire then s.firingSince = s.firingSince or input.now else s.firingSince = nil end
    return s
end

local usage = "usage: pw_bot_aim <bot name|*> <player name|me> [recruit|regular|hardened|veteran] | clear | status"

function lib.ParseArgs(args)
    local bots, what, tier = args[1], args[2], args[3]
    if bots == nil or bots == "" or what == nil or what == "" or args[4] ~= nil then return nil, usage end
    local lower = string.lower(what)
    if lower == "clear" or lower == "status" then
        if tier ~= nil then return nil, usage end
        return { bots = bots, action = lower --[[@as "clear"|"status"]] }
    end
    if tier ~= nil then
        tier = string.lower(tier)
        if not PW.BotProfiles.TierExists(tier) then return nil, usage end
    end
    return { bots = bots, action = "target", target = what, tier = tier }
end
