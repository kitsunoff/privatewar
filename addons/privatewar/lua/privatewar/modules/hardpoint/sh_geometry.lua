local hp = assert(PW.Hardpoint)

---@param n any
---@return boolean
local function finite(n)
    return isnumber(n) and n == n and n > -math.huge and n < math.huge
end

---@param p any
---@return boolean
local function vector(p)
    return isvector(p) and finite(p.x) and finite(p.y) and finite(p.z)
end

function hp.Inside(zone, pos)
    local dx, dy, dz = pos.x - zone.pos.x, pos.y - zone.pos.y, pos.z - zone.pos.z
    return dx * dx + dy * dy <= zone.radius * zone.radius and dz >= -zone.below and dz <= zone.above
end

function hp.Presence(zone, actors, out)
    local first, second = false, false
    for _, actor in ipairs(actors) do
        if actor.alive and actor.eligible and not actor.observer and hp.Inside(zone, actor.pos) then
            if actor.team == 1 then first = true elseif actor.team == 2 then second = true end
        end
    end
    out = out or { control = 0, contested = false }
    out.control = first and not second and 1 or second and not first and 2 or 0
    out.contested = first and second
    return out
end

function hp.ScoreDelta(presence, points)
    return { presence.control == 1 and points or 0, presence.control == 2 and points or 0 }
end

---@param zone any
---@return boolean
local function validZone(zone)
    return istable(zone) and isstring(zone.id) and #zone.id > 0 and #zone.id <= 32 and vector(zone.pos)
        and finite(zone.radius) and zone.radius > 0 and zone.radius <= 4096
        and finite(zone.above) and zone.above > 0 and finite(zone.below) and zone.below >= 0
        and zone.above + zone.below <= 2048
end

function hp.ValidateLayout(data)
    if not istable(data) or not istable(data.zones) then return false, "Hardpoint needs authored zones" end
    local zones = data.zones --[[@as table<any, any>]]
    local count = 0
    ---@type table<string, boolean>
    local seen = {}
    for key, zone in pairs(zones) do
        if not isnumber(key) or key % 1 ~= 0 or key < 1 or key > 16 or not validZone(zone) then
            return false, "Hardpoint zone is malformed or out of bounds"
        end
        if seen[zone.id] then return false, "Hardpoint zone ids must be unique" end
        seen[zone.id], count = true, count + 1
    end
    if count < 2 then return false, "Hardpoint needs 2..16 zones" end
    for index = 1, count do
        if zones[index] == nil then return false, "Hardpoint zones must be dense and ordered" end
    end
    return true
end

function hp.ArrivalFits(zone, projected, arrivalRadius)
    if not finite(arrivalRadius) or arrivalRadius < 0 or arrivalRadius > zone.radius then return false end
    local dx, dy = projected.x - zone.pos.x, projected.y - zone.pos.y
    return hp.Inside(zone, projected) and dx * dx + dy * dy <= (zone.radius - arrivalRadius) ^ 2
end

function hp.ValidateActivation(layout, probe)
    local valid, reason = hp.ValidateLayout(layout)
    if not valid then return false, reason end
    for _, zone in ipairs(layout.zones) do
        if not probe(zone) then return false, "Hardpoint zone " .. zone.id .. " has no usable floor, hull or route" end
    end
    return true
end
