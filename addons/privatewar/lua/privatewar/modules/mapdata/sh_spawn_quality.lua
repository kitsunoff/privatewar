-- Cold, bounded quality fallback for detected (never authored) spawn pools. These engineering thresholds address
-- the measured nz_shipment cluster, not a general map-suitability test; representative-map feel remains a checkpoint.
local lib = assert(PW.Map)

lib._FallbackRules = {
    minSpawns = 8,
    diameter = 256,
    farDistance = 800,
    minCandidates = 8,
    separation = 32,
    maxDetected = 256,
    maxAreas = 4096,
    maxEdges = 32768,
    maxCandidates = 200,
    budgetMs = 100
}

---@param pos Vector
---@return boolean
local function finite(pos)
    return pos.x == pos.x and pos.y == pos.y and pos.z == pos.z
        and math.max(math.abs(pos.x), math.abs(pos.y), math.abs(pos.z)) < math.huge
end

---@param a PW.NavSpawnCandidate
---@param b PW.NavSpawnCandidate
---@return boolean
local function candidateBefore(a, b)
    if a.area ~= b.area then return a.area < b.area end
    ---@type Vector
    local x, y = a.point.pos, b.point.pos
    if x.x ~= y.x then return x.x < y.x end
    if x.y ~= y.y then return x.y < y.y end
    if x.z ~= y.z then return x.z < y.z end
    return a.point.yaw < b.point.yaw
end

---@param detected PW.MapSpawns
---@param limit integer
---@return PW.MapSpawn[]?
local function flatten(detected, limit)
    ---@type PW.MapSpawn[]
    local out = {}
    for _, list in pairs(detected) do
        for _, point in ipairs(list) do
            if #out >= limit then return nil end
            if not finite(point.pos) then return nil end
            out[#out + 1] = point
        end
    end
    return out
end

---@param detected PW.MapSpawns
---@param rules PW.SpawnFallbackRules
---@return boolean
function lib._SpawnClustered(detected, rules)
    local points = flatten(detected, rules.maxDetected)
    if points == nil or #points < rules.minSpawns then return false end
    for i, point in ipairs(points) do
        for j = i + 1, #points do
            if point.pos:DistToSqr(points[j].pos) > rules.diameter ^ 2 then return false end
        end
    end
    return true
end

---@param graph table<integer, integer[]>
---@param first integer
---@return table<integer, true>
local function flood(graph, first)
    ---@type table<integer, true>
    local seen = { [first] = true }
    local queue, head = { first }, 1
    while queue[head] ~= nil do
        for _, id in ipairs(graph[queue[head]]) do
            if not seen[id] then
                seen[id] = true
                queue[#queue + 1] = id
            end
        end
        head = head + 1
    end
    return seen
end

---Intersection of forward and reverse reachability is the anchor's strongly connected component. Every anchor
---must be in it. Uses exactly directed GetAdjacentAreas edges, as bots_nav and Hardpoint activation do; no ladders
---or inferred reverse links. Graph reachability does not establish that a bot physically traverses a route.
---@param graph table<integer, integer[]>
---@param anchors integer[]
---@param rules PW.SpawnFallbackRules
---@return table<integer, true>?
function lib._MutualNav(graph, anchors, rules)
    local first = anchors[1]
    if first == nil or graph[first] == nil then return nil end
    ---@type table<integer, integer[]>
    local reverse = {}
    local nodes, edges = 0, 0
    for id in pairs(graph) do
        nodes = nodes + 1
        if nodes > rules.maxAreas then return nil end
        reverse[id] = {}
    end
    for from, neighbours in pairs(graph) do
        for _, to in ipairs(neighbours) do
            edges = edges + 1
            if edges > rules.maxEdges or reverse[to] == nil then return nil end
            reverse[to][#reverse[to] + 1] = from
        end
    end
    local forward, backward = flood(graph, first), flood(reverse, first)
    for _, id in ipairs(anchors) do
        if not forward[id] or not backward[id] then return nil end
    end
    for id in pairs(forward) do if not backward[id] then forward[id] = nil end end
    return forward
end

---@param point PW.MapSpawn
---@param points PW.MapSpawn[]
---@param distance number
---@return boolean
local function apart(point, points, distance)
    for _, other in ipairs(points) do
        if point.pos:DistToSqr(other.pos) < distance ^ 2 then return false end
    end
    return true
end

---@param detected PW.MapSpawns
---@param candidates PW.NavSpawnCandidate[]
---@param checks PW.SpawnChecks
---@return PW.MapSpawn[]
function lib._SpawnSupplements(detected, candidates, checks)
    local component, clear, rules = checks.component, checks.clear, checks.rules
    if not lib._SpawnClustered(detected, rules) or #candidates > rules.maxCandidates then return {} end
    local starts = flatten(detected, rules.maxDetected)
    if starts == nil then return {} end
    ---@type PW.NavSpawnCandidate[]
    local sorted = {}
    for _, candidate in ipairs(candidates) do
        if finite(candidate.point.pos) then sorted[#sorted + 1] = candidate end
    end
    table.sort(sorted, candidateBefore)
    ---@type PW.MapSpawn[]
    local out = {}
    for _, candidate in ipairs(sorted) do
        local point = candidate.point
        if finite(point.pos) and component[candidate.area] and apart(point, starts, rules.farDistance)
            and apart(point, out, rules.separation) and clear(point.pos) then
            out[#out + 1] = point
        end
    end
    if #out < rules.minCandidates then return {} end
    return out
end
