-- Approved support rules. Engine traces, inventory and disclosure are separate owners.
local lib = (rawget(PW, "SupportStreaks") or {}) --[[@as PW.SupportStreaksLib]]
PW.SupportStreaks = lib

---@param value number
---@return boolean
local function finite(value)
    return isnumber(value) and value == value and math.abs(value) < math.huge
end

---@param value Vector
---@return boolean
local function vector(value)
    return isvector(value) and finite(value.x) and finite(value.y) and finite(value.z)
end

---@param origin Vector
---@param direction Vector
---@param target Vector
---@param range number
---@param half number
---@return boolean
local function cone(origin, direction, target, range, half)
    if not vector(origin) or not vector(direction) or not vector(target) then return false end
    local offset = target - origin
    local distance, length = offset:Length(), direction:Length()
    if distance <= 0 or distance > range or length <= 0 then return false end
    return direction:Dot(offset) / (length * distance) >= math.cos(math.rad(half)) - 1e-7
end

function lib.Placement(f)
    if not vector(f.origin) or not vector(f.aim) or not vector(f.position) or not vector(f.normal)
        or f.aim:LengthSqr() <= 0 then return false, "invalid" end
    if not f.hit or not f.world or f.sky or f.water or not f.supported then return false, "floor" end
    if f.normal.z < math.cos(math.rad(20)) - 1e-7 then return false, "slope" end
    if f.origin:DistToSqr(f.position) > 192 * 192 then return false, "range" end
    if not f.visible then return false, "occluded" end
    if not f.hullClear or not f.exitClear then return false, "blocked" end
    return true
end

function lib.Capacity(records, owner, kind)
    if #records >= 8 then return false end
    for _, record in ipairs(records) do
        if record.owner == owner and record.kind == kind then return false end
    end
    return true
end

function lib.ScanEligible(origin, direction, target, visible)
    return visible and cone(origin, direction, target, 1800, 45)
end

function lib.SensorEligible(origin, target, visible)
    return visible and vector(origin) and vector(target) and math.abs(origin.z - target.z) <= 128
        and origin:DistToSqr(target) <= 600 * 600
end

function lib.SupportEligible(f)
    return f.alive and f.allowed and f.visible and finite(f.distance) and f.distance >= 0
        and f.distance <= f.radius and ((f.teams and f.allied) or f.owner == f.recipient)
end

function lib.ReceiptReady(charges, last, now)
    return charges > 0 and finite(now) and (last == nil or (finite(last) and now >= last + 5))
end

function lib.HealAmount(hp, maximum, damaged, now, dt, rates)
    if not finite(hp) or not finite(maximum) or not finite(damaged) or not finite(now) or not finite(dt)
        or hp <= 0 or hp >= maximum or dt <= 0 or now < damaged + 5 then return 0 end
    local rate = 0
    for _, candidate in ipairs(rates) do
        if finite(candidate) then rate = math.max(rate, candidate) end
    end
    return math.min(maximum - hp, rate * math.min(1, dt))
end

function lib.ScanDirection(origin, facing, contacts, publicPoint)
    for _, contact in ipairs(contacts) do
        if vector(contact.pos) and origin:DistToSqr(contact.pos) > 0 then
            return (contact.pos - origin):GetNormalized()
        end
    end
    if publicPoint ~= nil and vector(publicPoint) and origin:DistToSqr(publicPoint) > 0 then
        return (publicPoint - origin):GetNormalized()
    end
    return facing:GetNormalized()
end

function lib.EndReason(f)
    if not finite(f.now) or not finite(f.ends) then return "invalid" end
    if f.now >= f.ends then return "expired" end
    if not f.ownerValid then return "owner" end
    if f.team ~= f.currentTeam then return "relationship" end
    if not f.enabled then return "disabled" end
    if not f.allowed then return "forbidden" end
    return nil
end

function lib.DamageAllowed(hostilePlayer, world)
    return hostilePlayer or world
end

---@param row PW.DeviceMarker
---@param other PW.DeviceMarker
---@return boolean
local function overlaps(row, other)
    return other.visible and math.abs(row.x - other.x) < ((row.width or 160) + (other.width or 160)) * 0.5 + 4
        and row.y > other.y - (other.height or 20) - 4 and row.y - (row.height or 20) < other.y + 4
end

---@param row PW.DeviceMarker
---@param rows PW.DeviceMarker[]
---@param index integer
---@param down boolean
---@param tall number
local function separate(row, rows, index, down, tall)
    for _ = 1, index do
        for j = 1, index - 1 do
            local other = rows[j]
            if overlaps(row, other) then
                row.y = down and other.y + tall + 4 or other.y - (other.height or 20) - 4
            end
        end
    end
end

function lib.LayoutMarkers(rows, width, height)
    for i, row in ipairs(rows) do
        if row.visible then
            local half, tall = math.min(row.width or 160, width - 16) * 0.5, row.height or 20
            row.x = math.Clamp(row.x, half + 8, width - half - 8)
            row.y = math.Clamp(row.y, tall + 8, height - 8)
            local down = row.y < height * 0.5
            separate(row, rows, i, down, tall)
            row.y = math.Clamp(row.y, tall + 8, height - 8)
        end
    end
end
