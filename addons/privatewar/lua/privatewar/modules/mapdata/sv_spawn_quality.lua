-- New quality supplements only. The legacy <8 sampler deliberately retains its previous checks and semantics.
local lib = assert(PW.Map)
local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
local lift, down = Vector(0, 0, 8), Vector(0, 0, 32)

---@param pos Vector
---@return boolean
function lib._SupplementClear(pos)
    local start = pos + lift
    local hull = util.TraceHull({ start = start, endpos = start, mins = mins, maxs = maxs,
        mask = MASK_PLAYERSOLID })
    if hull.StartSolid ~= false or hull.AllSolid ~= false then return false end
    local floor = util.TraceLine({ start = start, endpos = pos - down, mask = MASK_PLAYERSOLID_BRUSHONLY })
    return floor.Hit == true and floor.StartSolid == false and floor.AllSolid == false
        and floor.HitNormal.z >= math.cos(math.rad(lib._NavRules.maxSlope))
        and floor.HitPos:DistToSqr(pos) <= 8 ^ 2
end

---@param areas CNavArea[]
---@param started number
---@return table<integer, integer[]>?
local function readGraph(areas, started)
    local rules = lib._FallbackRules
    if #areas == 0 or #areas > rules.maxAreas then return nil end
    ---@type table<integer, integer[]>
    local graph = {}
    local edges = 0
    for _, area in ipairs(areas) do
        if not IsValid(area) or (SysTime() - started) * 1000 > rules.budgetMs then return nil end
        local id = area:GetID()
        if graph[id] ~= nil then return nil end
        ---@type integer[]
        local neighbours = {}
        local adjacentAreas = area:GetAdjacentAreas() --[[@as CNavArea[] ]]
        for _, adjacent in ipairs(adjacentAreas) do
            edges = edges + 1
            if edges > rules.maxEdges or not IsValid(adjacent) then return nil end
            neighbours[#neighbours + 1] = adjacent:GetID()
        end
        graph[id] = neighbours
    end
    return graph
end

---Same nearest-area query as bots_nav and Hardpoint activation. A stricter 64-HU surface proximity rejects
---unknown/off-mesh projections. Keeping every supplement in every detected anchor's mutual component preserves
---directed routes from those anchors to HP objectives already accepted by HP activation. No mode data is decoded.
---@param pos Vector
---@param graph table<integer, integer[]>
---@return integer?
local function project(pos, graph)
    local area = navmesh.GetNearestNavArea(pos, false, 256, false, true)
    if not IsValid(area) or graph[area:GetID()] == nil then return nil end
    if area:GetClosestPointOnArea(pos):DistToSqr(pos) > 64 ^ 2 then return nil end
    return area:GetID()
end

---@param areas CNavArea[]
---@param samples PW.MapSpawn[]
---@return PW.MapSpawn[]
function lib._LoadSupplements(areas, samples)
    local entry = lib.Get()
    local _, authored = lib._CleanSpawns(entry ~= nil and entry.Spawns or nil)
    if authored > 0 then return {} end
    local detected, rules = assert(lib.GetDetectedSpawns)(), lib._FallbackRules
    if not lib._SpawnClustered(detected, rules) or #samples > rules.maxCandidates then return {} end
    local started = SysTime()
    local graph = readGraph(areas, started)
    if graph == nil then return {} end
    ---@type integer[]
    local anchors = {}
    for _, list in pairs(detected) do
        for _, point in ipairs(list) do
            local id = project(point.pos, graph)
            if id == nil then return {} end
            anchors[#anchors + 1] = id
        end
    end
    local component = lib._MutualNav(graph, anchors, rules)
    if component == nil then return {} end
    ---@type PW.NavSpawnCandidate[]
    local candidates = {}
    for _, point in ipairs(samples) do
        if (SysTime() - started) * 1000 > rules.budgetMs then return {} end
        local id = project(point.pos, graph)
        if id ~= nil then candidates[#candidates + 1] = { point = point, area = id } end
    end
    local out = lib._SpawnSupplements(detected, candidates,
        { component = component, clear = lib._SupplementClear, rules = rules })
    if (SysTime() - started) * 1000 > rules.budgetMs then return {} end
    return out
end
