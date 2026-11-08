-- Authoritative local floor, supporting corners, actual model hull and player-sized exit footprint.
local lib = PW.Devices --[[@as PW.DevicesLib]]

---@type table<string, { mins: Vector, maxs: Vector }>
local bounds = {}

---@param value Vector
---@return boolean
local function finite(value)
    return isvector(value) and value.x == value.x and value.y == value.y and value.z == value.z
        and math.abs(value.x) < math.huge and math.abs(value.y) < math.huge and math.abs(value.z) < math.huge
end

function lib.ModelBounds(kind)
    local cfg = lib.Config[kind]
    if cfg == nil or not util.IsValidModel(cfg.model) then return nil, nil end
    local cached = bounds[kind]
    if cached == nil then
        -- GetModelBounds is an entity method on the supported engine. This unspawned probe never has collision.
        local probe = ents.Create("base_anim")
        if not IsValid(probe) then return nil, nil end
        probe:SetModel(cfg.model)
        local mins, maxs = probe:GetModelBounds()
        probe:Remove()
        cached = { mins = mins, maxs = maxs }
        bounds[kind] = cached
    end
    return cached.mins, cached.maxs
end

---@param owner Player
---@param kind PW.SupportDeviceKind
---@param position Vector
---@return boolean, string?
function lib.Validate(owner, kind, position)
    if not IsValid(owner) then return false, "owner" end
    local eye, aim = owner:EyePos(), owner:GetAimVector()
    if not finite(position) or not finite(eye) or not finite(aim) or aim:LengthSqr() <= 0 then
        return false, "invalid"
    end
    local cfg = lib.Config[kind]
    if cfg == nil or not util.IsValidModel(cfg.model) then return false, "model" end
    local floor = util.TraceLine({ start = position + Vector(0, 0, 12), endpos = position - Vector(0, 0, 20),
        filter = owner, mask = MASK_PLAYERSOLID })
    local mins, maxs = lib.ModelBounds(kind)
    if mins == nil or maxs == nil then return false, "model" end
    local hull = util.TraceHull({ start = position + Vector(0, 0, 2 - mins.z),
        endpos = position + Vector(0, 0, 2 - mins.z), mins = mins, maxs = maxs,
        filter = owner, mask = MASK_PLAYERSOLID })
    local exit = util.TraceHull({ start = position + Vector(0, 0, 3), endpos = position + Vector(0, 0, 3),
        mins = Vector(-math.max(32, -mins.x), -math.max(32, -mins.y), 0),
        maxs = Vector(math.max(32, maxs.x), math.max(32, maxs.y), math.max(72, maxs.z - mins.z)),
        filter = owner, mask = MASK_PLAYERSOLID })
    local sight = util.TraceLine({ start = eye, endpos = position + Vector(0, 0, 4), filter = owner,
        mask = MASK_PLAYERSOLID })
    local supported = true
    for _, corner in ipairs({ Vector(mins.x, mins.y), Vector(mins.x, maxs.y),
        Vector(maxs.x, mins.y), Vector(maxs.x, maxs.y) }) do
        local tr = util.TraceLine({ start = position + corner + Vector(0, 0, 12),
            endpos = position + corner - Vector(0, 0, 12), filter = owner, mask = MASK_PLAYERSOLID })
        if not tr.HitWorld or tr.HitNormal.z < math.cos(math.rad(20)) then supported = false end
    end
    return assert(PW.SupportStreaks).Placement({ origin = eye, aim = aim, position = position,
        normal = floor.HitNormal, hit = floor.Hit, world = floor.HitWorld, sky = floor.HitSky,
        water = bit.band(util.PointContents(position + Vector(0, 0, 2)), CONTENTS_WATER) ~= 0,
        hullClear = not hull.Hit and not hull.StartSolid, exitClear = not exit.Hit and not exit.StartSolid,
        supported = supported, visible = sight.Fraction >= 0.99 })
end

function lib.Prepare(owner, kind)
    if not IsValid(owner) or not owner:Alive() or not lib.Enabled(kind)
        or not assert(PW.SupportStreaks).Capacity(lib.List(), owner, kind) then return nil, "capacity" end
    local aim = owner:GetAimVector()
    if not finite(aim) or not finite(owner:GetPos()) then return nil, "invalid" end
    local direction = Vector(aim.x, aim.y, 0)
    if direction:LengthSqr() < 0.001 then return nil, "aim" end
    direction:Normalize()
    local point = owner:GetPos() + direction * 80
    local floor = util.TraceLine({ start = point + Vector(0, 0, 48), endpos = point - Vector(0, 0, 96),
        filter = owner, mask = MASK_PLAYERSOLID })
    local valid, reason = lib.Validate(owner, kind, floor.HitPos)
    if not valid then return nil, reason end
    return { position = floor.HitPos, angles = Angle() }
end
