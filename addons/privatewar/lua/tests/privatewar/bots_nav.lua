-- T-5.5 bots navigation (07-bots.md d.6): resumable A* over an abstract graph, partial paths, the unreachable cache,
-- cost layers baked into a per-node table, the path service on the bot scheduler FIFO. Pure cases run on synthetic
-- graphs with a fake clock; the in-game smoke finds a path between two real navmesh areas on gm_construct.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotNavLib
local function lib()
    return must(PW.BotNav)
end

---A synthetic graph from nodes with positions and undirected edges. weights[a .. b] overrides the distance.
---@class TestGraph: PW.NavGraph
---@field calls { n: integer } Neighbours calls, for "no search ran" checks

---@param nodes table<string, { [1]: number, [2]: number }>
---@param edges (string|number)[][] pairs { a, b } or { a, b, cost }
---@param zero? boolean heuristic 0 (Dijkstra); default straight-line distance
---@return TestGraph
local function graph(nodes, edges, zero)
    ---@type table<string, string[]>
    local adjacent = {}
    ---@type table<string, number>
    local weight = {}
    for name in pairs(nodes) do adjacent[name] = {} end
    for _, e in ipairs(edges) do
        local a, b = tostring(e[1]), tostring(e[2])
        table.insert(adjacent[a], b)
        table.insert(adjacent[b], a)
        local custom = tonumber(e[3])
        if custom ~= nil then
            weight[a .. ">" .. b], weight[b .. ">" .. a] = custom, custom
        end
    end
    ---@param name string
    ---@return Vector
    local function pos(name) return Vector(nodes[name][1], nodes[name][2], 0) end
    local calls = { n = 0 }
    ---@type string[]
    local names = {}
    for name in pairs(nodes) do names[#names + 1] = name end
    table.sort(names)
    ---@type TestGraph
    return {
        calls = calls,
        Neighbours = function(node)
            calls.n = calls.n + 1
            return adjacent[node]
        end,
        Cost = function(a, b) return weight[a .. ">" .. b] or pos(a):Distance(pos(b)) end,
        Heuristic = function(a, goal) return zero and 0 or pos(a):Distance(pos(goal)) end,
        Nodes = function() return names end,
        Position = function(node) return pos(node) end
    }
end

---Diamond: A to D through B (20 long, hops 2) or through C (22 long, hops 2); B and C at x = 10.
---@return TestGraph
local function diamond()
    return graph({ A = { 0, 0 }, B = { 10, 5 }, C = { 10, -6 }, D = { 20, 0 } },
        { { "A", "B", 10 }, { "B", "D", 10 }, { "A", "C", 11 }, { "C", "D", 11 } }, true)
end

---A chain n1 - n2 - ... - n(len) along x.
---@param len integer
---@return TestGraph
local function chain(len)
    ---@type table<string, { [1]: number, [2]: number }>
    local nodes = {}
    ---@type string[][]
    local edges = {}
    for i = 1, len do
        nodes["n" .. i] = { i * 10, 0 }
        if i > 1 then edges[#edges + 1] = { "n" .. (i - 1), "n" .. i } end
    end
    return graph(nodes, edges)
end

---An open grid size x size, 4-neighbour, with a wall column at x = 5 that has one gap at y = size.
---@param size integer
---@param zero? boolean heuristic 0
---@return TestGraph
local function maze(size, zero)
    ---@type table<string, { [1]: number, [2]: number }>
    local nodes = {}
    ---@type string[][]
    local edges = {}
    for x = 1, size do
        for y = 1, size do
            if x ~= 5 or y == size then nodes[x .. "," .. y] = { x * 10, y * 10 } end
        end
    end
    for name in pairs(nodes) do
        local sx, sy = name:match("(%d+),(%d+)")
        local x, y = tonumber(sx) or 0, tonumber(sy) or 0
        local right, up = (x + 1) .. "," .. y, x .. "," .. (y + 1)
        if nodes[right] ~= nil then edges[#edges + 1] = { name, right } end
        if nodes[up] ~= nil then edges[#edges + 1] = { name, up } end
    end
    return graph(nodes, edges, zero)
end

---@param t { v: number }
---@return fun(): number
local function clockOf(t)
    return function() return t.v end
end

---A scheduler on a fake clock; every Tick runs one queued job.
---@param t { v: number }
---@return PW.BotScheduler
local function newScheduler(t)
    return must(PW.BotScheduler).New({ clock = clockOf(t), budget = 2 })
end

---Ticks the scheduler until the handle is done; returns the number of ticks used.
---@param sched PW.BotScheduler
---@param handle PW.NavHandle
---@param maxTicks? integer
---@return integer
local function drain(sched, handle, maxTicks)
    local ticks = 0
    while not handle.done and ticks < (maxTicks or 500) do
        sched.Tick()
        ticks = ticks + 1
    end
    return ticks
end

---@param t { v: number }
---@param g PW.NavGraph
---@param extra? { sliceIterations?: integer, iterationCap?: integer, unreachableTtl?: number,
---  bakeInterval?: number, bakeChunk?: integer }
---@return PW.NavService, PW.BotScheduler
local function newService(t, g, extra)
    local sched = newScheduler(t)
    local opts = extra or {}
    ---@type PW.NavServiceOpts
    local full = { graph = g, scheduler = sched, clock = clockOf(t), sliceIterations = opts.sliceIterations,
        iterationCap = opts.iterationCap, unreachableTtl = opts.unreachableTtl, bakeInterval = opts.bakeInterval,
        bakeChunk = opts.bakeChunk }
    return lib().NewService(full), sched
end

return {
    groupName = "Bots navigation (T-5.5)",
    cases = {
        {
            name = "Search: the shortest path on a synthetic graph (not the one with fewer hops)",
            func = function()
                local g = graph({ S = { 0, 0 }, A = { 10, 0 }, B = { 20, 0 }, C = { 10, 10 }, G = { 30, 0 } },
                    { { "S", "G", 100 }, { "S", "A", 10 }, { "A", "B", 10 }, { "B", "G", 10 }, { "S", "C", 5 },
                        { "C", "G", 80 } }, true)
                local search = lib().NewSearch(g, "S", "G")
                expect(search.Step(100)).to.equal("found")
                expect(search.path).to.deepEqual({ "S", "A", "B", "G" })
                local trivial = lib().NewSearch(g, "A", "A")
                expect(trivial.Step(10)).to.equal("found")
                expect(trivial.path).to.deepEqual({ "A" })
            end
        },
        {
            name = "Search: the straight-line heuristic finds the same shortest path around a wall",
            func = function()
                local g = maze(8)
                local informed = lib().NewSearch(g, "1,1", "8,1")
                local blind = lib().NewSearch(maze(8, true), "1,1", "8,1")
                expect(informed.Step(10000)).to.equal("found")
                expect(blind.Step(10000)).to.equal("found")
                expect(#must(informed.path)).to.equal(#must(blind.path))
                expect(must(informed.path)[1]).to.equal("1,1")
                expect(must(informed.path)[#must(informed.path)]).to.equal("8,1")
                -- the wall at x = 5 leaves one gap at y = 8: 4 steps right, 7 up, 7 down, 3 right = 21 steps
                expect(#must(informed.path)).to.equal(22)
            end
        },
        {
            name = "Time slicing: a search that yields every expansion resumes to the same result",
            func = function()
                local whole = lib().NewSearch(maze(8), "1,1", "8,1")
                expect(whole.Step(100000)).to.equal("found")
                local sliced = lib().NewSearch(maze(8), "1,1", "8,1")
                local yields = 0
                while sliced.Step(1) == "running" do yields = yields + 1 end
                expect(yields > 10).to.beTrue()
                expect(sliced.status).to.equal("found")
                expect(sliced.path).to.deepEqual(whole.path)
                expect(sliced.iterations).to.equal(whole.iterations)
                local coarse = lib().NewSearch(maze(8), "1,1", "8,1")
                local slices = 1
                while coarse.Step(7) == "running" do slices = slices + 1 end
                expect(slices > 1).to.beTrue()
                expect(coarse.path).to.deepEqual(whole.path)
            end
        },
        {
            name = "Time slicing: the service runs one slice per scheduler tick and the result equals one slice",
            func = function()
                local t = { v = 0 }
                local oneSlice, schedA = newService(t, maze(8), { sliceIterations = 100000 })
                local manySlices, schedB = newService(t, maze(8), { sliceIterations = 5 })
                local a = oneSlice.RequestPath("1,1", "8,1")
                local b = manySlices.RequestPath("1,1", "8,1")
                expect(a.status).to.equal("queued")
                local ticksA, ticksB = drain(schedA, a), drain(schedB, b)
                expect(ticksA).to.equal(1)
                expect(ticksB > 5).to.beTrue()
                expect(b.slices).to.equal(ticksB)
                expect(b.status).to.equal("found")
                expect(b.path).to.deepEqual(a.path)
                expect(b.iterations).to.equal(a.iterations)
                expect(schedB.GetCounters().jobsRun).to.equal(ticksB)
            end
        },
        {
            name = "Partial path: at the iteration cap the path leads to the expanded node closest to the goal",
            func = function()
                local search = lib().NewSearch(chain(50), "n1", "n50", { iterationCap = 10 })
                expect(search.Step(1000)).to.equal("partial")
                expect(search.iterations).to.equal(10)
                expect(search.best).to.equal("n10")
                local path = must(search.path)
                expect(path[1]).to.equal("n1")
                expect(path[#path]).to.equal("n10")
                expect(#path).to.equal(10)
                local t = { v = 0 }
                local service, sched = newService(t, chain(50), { iterationCap = 10, sliceIterations = 4 })
                local handle = service.RequestPath("n1", "n50")
                drain(sched, handle)
                expect(handle.status).to.equal("partial")
                expect(handle.partial).to.beTrue()
                expect(must(handle.path)[#must(handle.path)]).to.equal("n10")
                expect(must(handle.positions)[#must(handle.positions)]).to.equal(Vector(100, 0, 0))
            end
        },
        {
            name = "Unreachable cache: a pair proven unreachable is answered without a search until it expires",
            func = function()
                local g = graph({ A = { 0, 0 }, B = { 10, 0 }, X = { 100, 0 }, Y = { 110, 0 } },
                    { { "A", "B" }, { "X", "Y" } })
                local t = { v = 0 }
                local service, sched = newService(t, g, { unreachableTtl = 30 })
                local first = service.RequestPath("A", "X")
                drain(sched, first)
                expect(first.status).to.equal("unreachable")
                expect(first.cached).to.beFalse()
                local callsAfterFirst = g.calls.n
                expect(callsAfterFirst > 0).to.beTrue()
                local seen = nil
                local second = service.RequestPath("A", "X", function(handle) seen = handle end)
                expect(second.done).to.beTrue()
                expect(second.status).to.equal("unreachable")
                expect(second.cached).to.beTrue()
                expect(seen).to.equal(second)
                expect(g.calls.n).to.equal(callsAfterFirst)
                expect(service.GetCounters().cacheHits).to.equal(1)
                expect(service.RequestPath("B", "A").cached).to.beFalse() -- another pair is searched
                t.v = 31
                local third = service.RequestPath("A", "X")
                expect(third.cached).to.beFalse()
                drain(sched, third)
                expect(third.status).to.equal("unreachable")
                expect(g.calls.n > callsAfterFirst).to.beTrue()
            end
        },
        {
            name = "Unreachable cache: pure cache with expiry and a partial path is not cached",
            func = function()
                local t = { v = 0 }
                local cache = lib().NewUnreachableCache(10, clockOf(t))
                cache.Mark("a", "b")
                expect(cache.Has("a", "b")).to.beTrue()
                expect(cache.Has("b", "a")).to.beFalse()
                expect(cache.Count()).to.equal(1)
                t.v = 10
                expect(cache.Has("a", "b")).to.beFalse()
                expect(cache.Count()).to.equal(0)
                local service, sched = newService(t, chain(50), { iterationCap = 5 })
                local handle = service.RequestPath("n1", "n50")
                drain(sched, handle)
                expect(handle.status).to.equal("partial")
                expect(service.RequestPath("n1", "n50").cached).to.beFalse()
            end
        },
        {
            name = "Cost layers: a registered layer changes the chosen path once baked, and removing it restores it",
            func = function()
                local t = { v = 0 }
                local service, sched = newService(t, diamond())
                local before = service.RequestPath("A", "D")
                drain(sched, before)
                expect(before.path).to.deepEqual({ "A", "B", "D" })
                service.RegisterCostLayer("blockB", function(node) return node == "B" and 50 or 0 end)
                service.Bake()
                expect(service.GetCostTable().B).to.equal(50)
                expect(service.GetCostTable().C).to.beNil()
                local after = service.RequestPath("A", "D")
                drain(sched, after)
                expect(after.path).to.deepEqual({ "A", "C", "D" })
                expect(after.status).to.equal("found")
                expect(service.UnregisterCostLayer("blockB")).to.beTrue()
                expect(service.UnregisterCostLayer("blockB")).to.beFalse()
                service.Bake()
                local restored = service.RequestPath("A", "D")
                drain(sched, restored)
                expect(restored.path).to.deepEqual({ "A", "B", "D" })
            end
        },
        {
            name = "Cost layers: baked in chunks once per interval, a negative or failing layer adds nothing",
            func = function()
                local t = { v = 0 }
                local calls = 0
                local service = newService(t, diamond(), { bakeInterval = 1, bakeChunk = 2 })
                service.RegisterCostLayer("count", function(node)
                    calls = calls + 1
                    return node == "B" and 7 or -3
                end)
                service.RegisterCostLayer("boom", function() error("layer failure") end)
                service.Tick()
                expect(calls).to.equal(2) -- chunk of 2 nodes: the table is not swapped in yet
                expect(service.GetCostTable().B).to.beNil()
                service.Tick()
                expect(service.GetCostTable().B).to.equal(7)
                expect(service.GetCostTable().A).to.beNil()
                expect(service.GetCounters().bakes).to.equal(1)
                expect(service.GetCounters().layerErrors).to.equal(4)
                local callsAfter = calls
                service.Tick()
                service.Tick()
                expect(calls).to.equal(callsAfter) -- not due before the interval passed
                t.v = 1.5
                service.Tick()
                service.Tick()
                expect(service.GetCounters().bakes).to.equal(2)
            end
        },
        {
            name = "Cost layers: the sample death danger layer decays and steers the path away from a recent death",
            func = function()
                local t = { v = 0 }
                local g = diamond()
                local danger = lib().NewDanger({ clock = clockOf(t), radius = 10, weight = 60, decay = 120 })
                danger.Record(Vector(10, 5, 0))
                expect(danger.Layer("B", g)).to.equal(60)
                expect(danger.Layer("D", g)).to.equal(0)
                t.v = 60
                expect(danger.Layer("B", g)).to.equal(30)
                local service, sched = newService(t, g)
                t.v = 0
                service.RegisterCostLayer("danger", danger.Layer)
                service.Bake()
                local handle = service.RequestPath("A", "D")
                drain(sched, handle)
                expect(handle.path).to.deepEqual({ "A", "C", "D" })
                t.v = 121
                expect(danger.Count()).to.equal(0)
                expect(danger.Layer("B", g)).to.equal(0)
            end
        },
        {
            name = "Service: a cancelled request ends without a callback and the queue stays healthy",
            func = function()
                local t = { v = 0 }
                local service, sched = newService(t, maze(8), { sliceIterations = 3 })
                local calledBack = 0
                local handle = service.RequestPath("1,1", "8,1", function() calledBack = calledBack + 1 end)
                sched.Tick()
                expect(handle.status).to.equal("running")
                service.Cancel(handle)
                expect(handle.status).to.equal("cancelled")
                expect(handle.done).to.beTrue()
                sched.Tick()
                expect(sched.GetCounters().queued).to.equal(0)
                expect(calledBack).to.equal(0)
                local other = service.RequestPath("1,1", "2,2", function() calledBack = calledBack + 1 end)
                drain(sched, other)
                expect(other.status).to.equal("found")
                expect(calledBack).to.equal(1)
                expect(service.GetCounters().cancelled).to.equal(1)
            end
        },
        {
            name = "Service: two searches share the FIFO, each slice is one job",
            func = function()
                local t = { v = 0 }
                local service, sched = newService(t, maze(8), { sliceIterations = 4 })
                local a = service.RequestPath("1,1", "8,1")
                local b = service.RequestPath("1,2", "8,2")
                local ticks = 0
                while not (a.done and b.done) and ticks < 500 do
                    sched.Tick()
                    ticks = ticks + 1
                end
                expect(a.status).to.equal("found")
                expect(b.status).to.equal("found")
                expect(ticks).to.equal(a.slices + b.slices)
            end
        },
        {
            name = "Vendored heap: pops in order, update moves a payload, remove takes one out",
            func = function()
                ---@type { minUnique: fun(): PW.BinaryHeap }
                local heapLib = include("privatewar/modules/bots_nav/third_party/binaryheap.lua")
                local heap = heapLib.minUnique()
                for i, v in ipairs({ 5, 3, 8, 1, 9, 2 }) do heap:insert(v, "p" .. i) end
                expect(heap:size()).to.equal(6)
                expect(heap:peek()).to.equal("p4")
                heap:update("p5", 0)
                heap:remove("p2")
                ---@type any[]
                local order = {}
                while heap:size() > 0 do
                    local payload = heap:pop()
                    order[#order + 1] = payload
                end
                expect(order).to.deepEqual({ "p5", "p4", "p6", "p1", "p3" })
            end
        },
        {
            name = "Engine glue: the CNavArea adapter finds a path between two navmesh areas within the budget",
            func = function()
                local areas = navmesh.GetAllNavAreas() --[[@as CNavArea[] ]]
                if game.GetMap() == "gm_construct" then expect(#areas > 0).to.beTrue() end
                if #areas == 0 then return end
                local g = must(lib().AreaGraph)(areas)
                local start = areas[1]
                ---@type CNavArea[]
                local far = table.Copy(areas)
                table.sort(far, function(a, b)
                    return a:GetCenter():DistToSqr(start:GetCenter()) > b:GetCenter():DistToSqr(start:GetCenter())
                end)
                local sched = must(PW.BotScheduler).New({ budget = 2 })
                local service = lib().NewService({ graph = g, scheduler = sched })
                ---@type PW.NavHandle?
                local handle
                for i = 1, math.min(#far, 10) do
                    handle = service.RequestPath(start:GetID(), far[i]:GetID())
                    drain(sched, handle, 2000)
                    if handle.status == "found" then break end
                end
                local found = must(handle)
                local counters = sched.GetCounters()
                print(string.format("[PW] nav smoke on %s: %d areas, %d steps, %d iterations, %d slices, %.2f ms",
                    game.GetMap(), #areas, #(found.path or {}), found.iterations, found.slices, counters.maxTickMs))
                expect(found.status).to.equal("found")
                local path = must(found.path)
                expect(path[1]).to.equal(start:GetID())
                for i = 2, #path do
                    expect(table.HasValue(g.Neighbours(path[i - 1]), path[i])).to.beTrue()
                end
                expect(counters.maxTickMs).to.beLessThan(25)
                expect(counters.ticks).to.beLessThan(2000)
            end
        }
    }
}
