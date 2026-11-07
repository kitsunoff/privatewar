-- Authoritative map activation and the one ordinary-sight bomb prop. No hidden global entity coordinates.
local lib = PW.SND --[[@as PW.SNDLib]]
local lift, down = Vector(0, 0, 32), Vector(0, 0, 96)
local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)

---@param pos Vector
---@return CNavArea?
local function areaAt(pos)
    local area = navmesh.GetNearestNavArea(pos, false, 128, false, true)
    if not IsValid(area) or area:GetClosestPointOnArea(pos):DistToSqr(pos) > 128 * 128 then return nil end
    return area
end

---@param pos Vector
---@return boolean
local function grounded(pos)
    if not util.IsInWorld(pos) then return false end
    local floor = util.TraceLine({ start = pos + lift, endpos = pos - down, mask = MASK_SOLID_BRUSHONLY })
    return floor.Hit == true and not floor.StartSolid and floor.HitNormal.z >= 0.7
        and math.abs(floor.HitPos.z - pos.z) <= 16
end

---@param from CNavArea
---@param to CNavArea
---@return boolean
local function reachable(from, to)
    ---@type CNavArea[]
    local queue = { from }
    ---@type table<integer, boolean>
    local visited = { [from:GetID()] = true }
    local index = 1
    while index <= #queue and index <= 10000 do
        local area = queue[index]
        if area:GetID() == to:GetID() then return true end
        index = index + 1
        for _, adjacent in ipairs(area:GetAdjacentAreas() --[[@as CNavArea[] ]]) do
            local id = adjacent:GetID()
            if not visited[id] then visited[id] = true queue[#queue + 1] = adjacent end
        end
    end
    return false
end

function lib.Activate(map)
    local origin = assert(areaAt(map.bomb), "S&D bomb point is off the navmesh")
    local points = { map.bomb }
    for _, site in ipairs(map.sites) do
        points[#points + 1], points[#points + 2] = site.pos, site.approach
        local sight = util.TraceLine({ start = site.approach + Vector(0, 0, 64),
            endpos = site.pos + Vector(0, 0, 8), mask = MASK_OPAQUE, filter = player.GetAll() })
        assert(not sight.Hit or sight.Fraction >= 0.98, "S&D plant approach has no line of sight to its site")
    end
    for side = 1, 2 do for _, spawn in ipairs(map.spawns[side]) do points[#points + 1] = spawn.pos end end
    local filter = player.GetAll()
    for _, pos in ipairs(points) do
        assert(grounded(pos), "S&D authored point has no valid ground")
        local hull = util.TraceHull({ start = pos + Vector(0, 0, 2), endpos = pos + Vector(0, 0, 2),
            mins = mins, maxs = maxs, filter = filter, mask = MASK_PLAYERSOLID })
        assert(not hull.StartSolid, "S&D authored point is hull blocked")
        local area = assert(areaAt(pos), "S&D authored point is off the navmesh")
        assert(reachable(origin, area) and reachable(area, origin), "S&D authored point has no mutual route")
    end
end

function lib.DropPoint(state, ply)
    local pos = ply:GetPos()
    local floor = util.TraceLine({ start = pos + lift, endpos = pos - Vector(0, 0, 256), filter = ply,
        mask = MASK_SOLID_BRUSHONLY })
    if not floor.Hit or floor.StartSolid or not util.IsInWorld(floor.HitPos) then return state.map.bomb end
    local ground = floor.HitPos + Vector(0, 0, 2)
    local area, origin = areaAt(ground), areaAt(state.map.bomb)
    if floor.HitNormal.z < 0.7 or area == nil or origin == nil or not reachable(origin, area)
        or not reachable(area, origin) then return state.map.bomb end
    local hull = util.TraceHull({ start = ground, endpos = ground, mins = Vector(-8, -8, 0),
        maxs = Vector(8, 8, 16), filter = { ply, PW._SND.bomb }, mask = MASK_SOLID })
    if hull.StartSolid then return state.map.bomb end
    return ground
end

function lib.Physical(state)
    local store = PW._SND
    local visible = state.phase == "dropped" or state.phase == "planted"
    if not visible then
        if IsValid(store.bomb) then store.bomb:Remove() end
        store.bomb = nil
        return
    end
    if not IsValid(store.bomb) then
        local bomb = ents.Create("prop_dynamic")
        assert(IsValid(bomb), "S&D bomb prop could not be created")
        bomb:SetModel("models/props_lab/reciever01b.mdl")
        bomb:SetPos(state.pos)
        bomb:Spawn()
        bomb:SetSolid(SOLID_NONE)
        bomb:SetMoveType(MOVETYPE_NONE)
        store.bomb = bomb
    end
    assert(store.bomb):SetPos(state.pos)
end

function lib.Clear()
    local store = PW._SND
    if IsValid(store.bomb) then store.bomb:Remove() end
    store.bomb = nil
    lib.Publish(nil)
end
