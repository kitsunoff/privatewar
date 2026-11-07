-- Bots navigation, the path service (T-5.5; included by shared.lua, see the decisions there). The service owns the
-- unreachable cache and the baked cost table, runs searches in slices as jobs of the bot scheduler, and hands the
-- caller a handle. Pure: it works on any PW.NavGraph and any scheduler with Enqueue.

local lib = PW.BotNav

---@class PW.NavBaker
---@field layers { id: string, fn: PW.NavCostLayer }[]
---@field baked table<any, number>
---@field building { nodes: any[], index: integer, out: table<any, number> }?
---@field nextAt number
---@field dirty boolean

---@return PW.NavCounters
local function newCounters()
    return { requests = 0, found = 0, partial = 0, unreachable = 0, cacheHits = 0, cancelled = 0, slices = 0,
        iterations = 0, bakes = 0, layerErrors = 0 }
end

---The extra cost of entering node: the sum of the layers (a failing layer counts 0 and is counted).
---@param baker PW.NavBaker
---@param graph PW.NavGraph
---@param counters PW.NavCounters
---@param node any
---@return number
local function layersCost(baker, graph, counters, node)
    local sum = 0
    for _, layer in ipairs(baker.layers) do
        local ok, extra = pcall(layer.fn, node, graph)
        if not ok then
            counters.layerErrors = counters.layerErrors + 1
        elseif isnumber(extra) and extra > 0 then
            sum = sum + extra
        end
    end
    return sum
end

---Bakes up to chunk nodes of the running bake; replaces the table when the last node is done.
---@param baker PW.NavBaker
---@param graph PW.NavGraph
---@param counters PW.NavCounters
---@param chunk integer
local function bakeChunk(baker, graph, counters, chunk)
    local building = baker.building
    if building == nil then return end
    local last = math.min(building.index + chunk - 1, #building.nodes)
    for i = building.index, last do
        local node = building.nodes[i]
        local cost = layersCost(baker, graph, counters, node)
        if cost > 0 then building.out[node] = cost end
    end
    building.index = last + 1
    if building.index > #building.nodes then
        baker.baked = building.out
        baker.building = nil
        counters.bakes = counters.bakes + 1
    end
end

---Starts a bake when one is due (a layer changed, or the interval passed) and there is something to bake or clear.
---@param baker PW.NavBaker
---@param graph PW.NavGraph
---@param now number
---@param interval number
---@param force? boolean
local function startBake(baker, graph, now, interval, force)
    if baker.building ~= nil and not force then return end
    if graph.Nodes == nil then return end
    if not force and not baker.dirty and now < baker.nextAt then return end
    if #baker.layers == 0 and next(baker.baked) == nil then
        baker.dirty = false
        return
    end
    baker.building = { nodes = graph.Nodes(), index = 1, out = {} }
    baker.nextAt = now + interval
    baker.dirty = false
end

---@param baker PW.NavBaker
---@param id string
---@return integer? index
local function layerIndex(baker, id)
    for i, layer in ipairs(baker.layers) do
        if layer.id == id then return i end
    end
    return nil
end

---@param baker PW.NavBaker
---@param id string
---@param fn PW.NavCostLayer
local function addLayer(baker, id, fn)
    assert(isstring(id) and isfunction(fn), "bots_nav: RegisterCostLayer needs an id and a function")
    local index = layerIndex(baker, id)
    if index ~= nil then
        baker.layers[index].fn = fn
    else
        baker.layers[#baker.layers + 1] = { id = id, fn = fn }
    end
    baker.dirty = true
end

---@param baker PW.NavBaker
---@param id string
---@return boolean
local function removeLayer(baker, id)
    local index = layerIndex(baker, id)
    if index == nil then return false end
    table.remove(baker.layers, index)
    baker.dirty = true
    return true
end

---Fills the public fields of a finished search into the handle.
---@param handle PW.NavHandle
---@param search PW.NavSearch
---@param graph PW.NavGraph
local function applyResult(handle, search, graph)
    handle.status = search.status == "running" and "running" or search.status
    handle.iterations = search.iterations
    handle.partial = search.status == "partial"
    handle.path = search.path
    if search.path ~= nil and graph.Position ~= nil then
        ---@type Vector[]
        local positions = {}
        for i, node in ipairs(search.path) do positions[i] = graph.Position(node) end
        handle.positions = positions
    end
end

---Everything the request functions share.
---@class PW.NavServiceCtx
---@field graph PW.NavGraph the graph with the baked cost in its step cost
---@field scheduler { Enqueue: fun(job: fun()) }
---@field cache PW.NavUnreachableCache
---@field counters PW.NavCounters
---@field slice integer
---@field sliceSeconds number
---@field clock fun(): number
---@field cap integer

---@param ctx PW.NavServiceCtx
---@param handle PW.NavHandle
---@param search PW.NavSearch
---@param callback? fun(handle: PW.NavHandle)
local function finish(ctx, handle, search, callback)
    local counters = ctx.counters
    applyResult(handle, search, ctx.graph)
    handle.done = true
    if search.status == "found" then counters.found = counters.found + 1 end
    if search.status == "partial" then counters.partial = counters.partial + 1 end
    if search.status == "unreachable" then
        counters.unreachable = counters.unreachable + 1
        ctx.cache.Mark(handle.from, handle.to)
    end
    if callback ~= nil then callback(handle) end
end

---Runs up to ctx.slice expansions, in small steps; stops early when the slice has used its time budget.
---@param ctx PW.NavServiceCtx
---@param search PW.NavSearch
---@return "running"|"found"|"partial"|"unreachable"
local function runSlice(ctx, search)
    ---@type number
    local started = ctx.clock()
    ---@type integer
    local ran = 0
    ---@type "running"|"found"|"partial"|"unreachable"
    local status = search.status
    while status == "running" and ran < ctx.slice and (ran == 0 or ctx.clock() - started < ctx.sliceSeconds) do
        ---@type integer
        local step = math.min(4, ctx.slice - ran)
        status = search.Step(step)
        ran = ran + step
    end
    return status
end

---One scheduler job: a slice of the search; the next slice is enqueued while the search runs.
---@param ctx PW.NavServiceCtx
---@param handle PW.NavHandle
---@param search PW.NavSearch
---@param callback? fun(handle: PW.NavHandle)
local function enqueueSlice(ctx, handle, search, callback)
    ctx.scheduler.Enqueue(function()
        if handle.done then return end
        handle.status = "running"
        local before = search.iterations
        local status = runSlice(ctx, search)
        handle.slices = handle.slices + 1
        ctx.counters.slices = ctx.counters.slices + 1
        ctx.counters.iterations = ctx.counters.iterations + search.iterations - before
        if status == "running" then
            enqueueSlice(ctx, handle, search, callback)
        else
            finish(ctx, handle, search, callback)
        end
    end)
end

---@param ctx PW.NavServiceCtx
---@param from any
---@param to any
---@param callback? fun(handle: PW.NavHandle)
---@return PW.NavHandle
local function requestPath(ctx, from, to, callback)
    local counters = ctx.counters
    counters.requests = counters.requests + 1
    ---@type PW.NavHandle
    local handle = { status = "queued", partial = false, cached = false, iterations = 0, slices = 0,
        done = false, from = from, to = to }
    if ctx.cache.Has(from, to) then
        counters.cacheHits = counters.cacheHits + 1
        counters.unreachable = counters.unreachable + 1
        handle.status, handle.cached, handle.done = "unreachable", true, true
        if callback ~= nil then callback(handle) end
        return handle
    end
    enqueueSlice(ctx, handle, lib.NewSearch(ctx.graph, from, to, { iterationCap = ctx.cap }), callback)
    return handle
end

---@param counters PW.NavCounters
---@param handle PW.NavHandle
local function cancel(counters, handle)
    if handle.done then return end
    handle.status, handle.done = "cancelled", true
    counters.cancelled = counters.cancelled + 1
end

---@param opts PW.NavServiceOpts
---@return PW.NavService
function lib.NewService(opts)
    local graph = opts.graph
    local clock = opts.clock or SysTime
    local interval = opts.bakeInterval or 1
    local chunk = opts.bakeChunk or 256
    local counters = newCounters()
    ---@type PW.NavBaker
    local baker = { layers = {}, baked = {}, nextAt = 0, dirty = false }
    ---@type PW.NavServiceCtx
    local ctx = { scheduler = opts.scheduler or PW.BotScheduler, counters = counters,
        slice = opts.sliceIterations or lib.SliceIterations, clock = clock,
        sliceSeconds = (opts.sliceMs or lib.SliceMs) / 1000, cap = opts.iterationCap or lib.IterationCap,
        cache = lib.NewUnreachableCache(opts.unreachableTtl or 30, clock),
        -- the graph the search sees: the step cost includes the baked extra cost of the target node
        graph = { Neighbours = graph.Neighbours, Heuristic = graph.Heuristic, Position = graph.Position,
            Nodes = graph.Nodes, Cost = function(from, to) return graph.Cost(from, to) + (baker.baked[to] or 0) end } }
    ---@type PW.NavService
    return {
        RequestPath = function(from, to, callback) return requestPath(ctx, from, to, callback) end,
        Cancel = function(handle) cancel(counters, handle) end,
        RegisterCostLayer = function(id, layer) addLayer(baker, id, layer) end,
        UnregisterCostLayer = function(id) return removeLayer(baker, id) end,
        Bake = function()
            startBake(baker, graph, clock(), interval, true)
            bakeChunk(baker, graph, counters, math.huge)
        end,
        Tick = function()
            startBake(baker, graph, clock(), interval)
            bakeChunk(baker, graph, counters, chunk)
        end,
        GetCostTable = function() return baker.baked end,
        ClearUnreachable = function() ctx.cache.Clear() end,
        GetCounters = function() return table.Copy(counters) end
    }
end
