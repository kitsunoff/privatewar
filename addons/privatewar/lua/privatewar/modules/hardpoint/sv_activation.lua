-- Cold activation checks only: structural filtering stays independent of the currently loaded world.
local hp = assert(PW.Hardpoint)
local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
local up, down, lift = Vector(0, 0, 32), Vector(0, 0, 64), Vector(0, 0, 8)

---@param zone PW.HardpointZone
---@param players Player[]
---@return CNavArea?
local function usable(zone, players)
    local floor = util.TraceLine({ start = zone.pos + up, endpos = zone.pos - down,
        mask = MASK_PLAYERSOLID_BRUSHONLY })
    if not floor.Hit or floor.StartSolid or floor.HitNormal.z < 0.7 or not hp.Inside(zone, floor.HitPos) then return end
    local pos = floor.HitPos + lift
    local hull = util.TraceHull({ start = pos, endpos = pos, mins = mins, maxs = maxs,
        mask = MASK_PLAYERSOLID, filter = players })
    if hull.StartSolid or hull.AllSolid then return end
    local area = navmesh.GetNearestNavArea(floor.HitPos, false, 128, false, true)
    if not IsValid(area) then return end
    local projected = area:GetClosestPointOnArea(floor.HitPos)
    if not hp.ArrivalFits(zone, projected, math.min(48, zone.radius / 4)) then return end
    return area
end

---@param start CNavArea
---@param targets CNavArea[]
---@return boolean
local function reaches(start, targets)
    ---@type table<integer, boolean>
    local seen = { [start:GetID()] = true }
    ---@type CNavArea[], integer
    local queue, head = { start }, 1
    while queue[head] ~= nil do
        local adjacentAreas = queue[head]:GetAdjacentAreas() --[[@as CNavArea[] ]]
        for _, adjacent in ipairs(adjacentAreas) do
            if not seen[adjacent:GetID()] then
                seen[adjacent:GetID()] = true
                queue[#queue + 1] = adjacent
            end
        end
        head = head + 1
    end
    for _, target in ipairs(targets) do if not seen[target:GetID()] then return false end end
    return true
end

function hp.CheckActivation(layout)
    ---@type CNavArea[]
    local areas = {}
    local players = player.GetAll()
    local valid, reason = hp.ValidateActivation(layout, function(zone)
        local area = usable(zone, players)
        if area == nil then return false end
        areas[#areas + 1] = area
        return true
    end)
    if not valid then return false, reason end
    for _, area in ipairs(areas) do
        if not reaches(area, areas) then return false, "Hardpoint zones lack mutual directed nav routes" end
    end
    -- The ordinary map spawn source is unchanged; require a route from every detected initial spawn.
    local map = PW.Map
    for _, points in pairs(map ~= nil and map.GetDetectedSpawns() or {}) do
        for _, point in ipairs(points) do
            local start = navmesh.GetNearestNavArea(point.pos, false, 256, false, true)
            if not IsValid(start) or not reaches(start, areas) then
                return false, "Hardpoint has no route from an initial spawn"
            end
        end
    end
    return true
end
