-- Bots navigation (T-5.5; 07-bots.md d.6; DESIGN.md performance rules). A pure core over an abstract graph
-- (Neighbours, Cost, Heuristic): a resumable A* with a binary heap, an unreachable-pair cache, cost layers baked
-- into a per-node table, and a path service that runs the search in slices through the bot scheduler FIFO. The
-- CNavArea adapter and the engine hooks are in init.lua. The A* inner loop never calls hooks or engine functions.
--
-- Decisions of the lane agent:
--   1. A node is any table key. The engine adapter uses the integer area id (CNavArea userdata are not stable keys).
--   2. A search expands at most iterationCap nodes (default 4000). If it has not reached the goal by then it ends as
--      "partial" with the path to the expanded node that is closest to the goal by the heuristic. Only a search
--      that drained its open set ends as "unreachable" and only that fills the unreachable cache.
--   3. A slice is at most sliceIterations expansions (default 150) and at most sliceMs (default 1 ms, checked every
--      4 expansions); it is one scheduler job. A search that is not done enqueues the next slice, so the FIFO
--      interleaves searches of different bots. Slicing does not change the result.
--   4. The unreachable cache keys the ordered pair (from, to); entries expire after unreachableTtl seconds (30).
--      A cached request completes at once (handle.cached) and calls its callback synchronously.
--   5. Cost layers: RegisterCostLayer(id, fn(node, graph) -> extra cost in distance units); negative counts as 0
--      so the heuristic stays admissible. Layers are baked into one table node -> extra cost about once per
--      bakeInterval (1 s), bakeChunk nodes per Tick; the table is replaced when a bake finishes. The step cost is
--      graph.Cost(from, to) + baked[to].
--   6. A path is a list of nodes (area ids); handle.positions is filled when the graph has Position.
--   7. A request is async: a handle to poll (status, done) plus an optional callback(handle) called once when the
--      handle is done. Cancel marks the handle cancelled; its job exits at the next slice without a callback.

MODULE.Name = "Bots navigation"

local lib = (rawget(PW, "BotNav") or {}) --[[@as PW.BotNavLib]]
PW.BotNav = lib

local heapFile = "privatewar/modules/bots_nav/third_party/binaryheap.lua"
if SERVER then AddCSLuaFile(heapFile) end
---@type { minUnique: fun(lt?: fun(a: any, b: any): boolean): PW.BinaryHeap }
local heapLib = include(heapFile)

lib.SliceIterations = 150
lib.SliceMs = 1
lib.IterationCap = 4000

---@class PW.NavSearchState
---@field graph PW.NavGraph
---@field goal any
---@field open PW.BinaryHeap
---@field cost table<any, number> best known cost from the start
---@field parent table<any, any>
---@field closed table<any, boolean>
---@field cap integer

---The path from the start to node, following the parents.
---@param parent table<any, any>
---@param node any
---@return any[]
local function trace(parent, node)
    ---@type any[]
    local reversed = {}
    local current = node
    while current ~= nil do
        reversed[#reversed + 1] = current
        current = parent[current]
    end
    ---@type any[]
    local path = {}
    for i = #reversed, 1, -1 do path[#path + 1] = reversed[i] end
    return path
end

---Relaxes the edge node -> next.
---@param state PW.NavSearchState
---@param node any
---@param next any
local function relax(state, node, next)
    local graph = state.graph
    local stepCost = state.cost[node] + graph.Cost(node, next)
    local known = state.cost[next]
    if known ~= nil and stepCost >= known then return end
    state.cost[next] = stepCost
    state.parent[next] = node
    local priority = stepCost + graph.Heuristic(next, state.goal)
    if state.open.reverse[next] ~= nil then
        state.open:update(next, priority)
    else
        state.open:insert(priority, next)
    end
end

---Relaxes the edges of node.
---@param search PW.NavSearch
---@param state PW.NavSearchState
---@param node any
local function expand(search, state, node)
    for _, next in ipairs(state.graph.Neighbours(node)) do
        if not state.closed[next] then relax(state, node, next) end
    end
    search.iterations = search.iterations + 1
end

---One expansion. Returns the status the search has after it.
---@param search PW.NavSearch
---@param state PW.NavSearchState
---@param bestH number the smallest heuristic value of an expanded node so far
---@return number bestH
local function expandOne(search, state, bestH)
    local node = state.open:pop()
    if node == nil then
        search.status = "unreachable"
        return bestH
    end
    if node == state.goal then
        search.status = "found"
        search.path = trace(state.parent, node)
        return bestH
    end
    state.closed[node] = true
    local h = state.graph.Heuristic(node, state.goal)
    if h < bestH then
        bestH = h
        search.best = node
    end
    expand(search, state, node)
    if search.iterations >= state.cap then
        search.status = "partial"
        search.path = trace(state.parent, search.best)
    end
    return bestH
end

---A resumable A*. Step(n) expands up to n nodes and returns the status; call it again until it is not "running".
---@param graph PW.NavGraph
---@param start any
---@param goal any
---@param opts? PW.NavSearchOpts
---@return PW.NavSearch
function lib.NewSearch(graph, start, goal, opts)
    assert(start ~= nil and goal ~= nil, "bots_nav: a search needs a start and a goal")
    local cap = opts ~= nil and opts.iterationCap or lib.IterationCap
    ---@type PW.NavSearchState
    local state = { graph = graph, goal = goal, open = heapLib.minUnique(), cost = { [start] = 0 }, parent = {},
        closed = {}, cap = cap }
    state.open:insert(graph.Heuristic(start, goal), start)
    local bestH = graph.Heuristic(start, goal)
    ---@type PW.NavSearch
    local search
    search = { status = "running", iterations = 0, best = start,
        Step = function(maxIterations)
            local budget = maxIterations
            while search.status == "running" and budget > 0 do
                bestH = expandOne(search, state, bestH)
                budget = budget - 1
            end
            return search.status
        end }
    return search
end

---@param row table<any, number> to -> expiry time
---@param t number
---@return integer
local function countLive(row, t)
    local count = 0
    for _, expiry in pairs(row) do
        if expiry > t then count = count + 1 end
    end
    return count
end

---The unreachable-pair cache with expiry.
---@param ttl number seconds
---@param clock? fun(): number
---@return PW.NavUnreachableCache
function lib.NewUnreachableCache(ttl, clock)
    local now = clock or SysTime
    ---@type table<any, table<any, number>> from -> to -> expiry time
    local entries = {}
    local cache = {}
    function cache.Mark(from, to)
        local row = entries[from]
        if row == nil then
            row = {}
            entries[from] = row
        end
        row[to] = now() + ttl
    end
    function cache.Has(from, to)
        local row = entries[from]
        if row == nil or row[to] == nil then return false end
        if now() >= row[to] then
            row[to] = nil
            return false
        end
        return true
    end
    function cache.Clear() entries = {} end
    function cache.Count()
        local count, t = 0, now()
        for _, row in pairs(entries) do count = count + countLive(row, t) end
        return count
    end
    return cache
end

---Sample layer, pure: recent deaths make the nodes near them costly; the cost falls off linearly with the distance
---and with the age of the death (07-bots.md d.6: danger near recent deaths, decays in 120 s).
---@param opts? PW.NavDangerOpts
---@return PW.NavDanger
function lib.NewDanger(opts)
    local options = opts or {}
    local now = options.clock or SysTime
    local radius, weight = options.radius or 600, options.weight or 800
    local decay, maxDeaths = options.decay or 120, options.maxDeaths or 64
    ---@type { pos: Vector, at: number }[]
    local deaths = {}
    local function prune()
        local t = now()
        for i = #deaths, 1, -1 do
            if t - deaths[i].at >= decay then table.remove(deaths, i) end
        end
    end
    ---@type PW.NavDanger
    return {
        Record = function(pos)
            prune()
            if #deaths >= maxDeaths then table.remove(deaths, 1) end
            deaths[#deaths + 1] = { pos = pos, at = now() }
        end,
        Count = function()
            prune()
            return #deaths
        end,
        Layer = function(node, graph)
            if graph.Position == nil or #deaths == 0 then return 0 end
            local at, t, sum = graph.Position(node), now(), 0
            for _, death in ipairs(deaths) do
                local age = 1 - (t - death.at) / decay
                local near = 1 - at:Distance(death.pos) / radius
                if age > 0 and near > 0 then sum = sum + weight * age * near end
            end
            return sum
        end
    }
end

local serviceFile = "privatewar/modules/bots_nav/sh_service.lua"
if SERVER then AddCSLuaFile(serviceFile) end
include(serviceFile)
