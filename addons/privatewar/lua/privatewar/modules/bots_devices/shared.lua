-- Device knowledge is separate from player contacts. The bounded server scanner owns all acquisition.
MODULE.Name = "Bots device perception"
local lib = (rawget(PW, "BotDevices") or {}) --[[@as PW.BotDevicesLib]]
PW.BotDevices = lib

function lib.Perceivable(eye, facing, point, range, fov, visible)
    local rules = PW.SupportStreaks
    if rules == nil or not visible then return false end
    -- Reuse the finite geometry guard; scale range to its fixed scan sphere after normalizing offset.
    local offset = point - eye
    local distance = offset:Length()
    if distance <= 0 or distance > range or distance ~= distance or distance == math.huge then return false end
    if not rules.ScanEligible(eye, facing, eye + facing:GetNormalized(), true) then return false end
    return facing:GetNormalized():Dot(offset / distance) >= math.cos(math.rad(fov * 0.5)) - 1e-7
end

function lib.Recognized(firstSeen, now, delay, visible)
    return visible and firstSeen ~= nil and firstSeen == firstSeen and now == now and now < math.huge
        and now >= firstSeen + math.max(0, delay)
end

function lib.AttackWanted(playerThreat, deviceVisible)
    return not playerThreat and deviceVisible
end
