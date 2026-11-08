-- Regression: counts alone do not make a usable dynamic spawn pool. No existing fallback assertions are replaced.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@return PW.MapLib
local function map()
    return must(PW.Map)
end

---@param n integer
---@param step? number
---@param offset? number
---@return PW.MapSpawn[]
local function points(n, step, offset)
    ---@type PW.MapSpawn[]
    local out = {}
    for i = 1, n do out[i] = { pos = Vector((offset or 0) + (i - 1) * (step or 0), 0, 0), yaw = i } end
    return out
end

---@param n? integer
---@return PW.NavSpawnCandidate[]
local function candidates(n)
    ---@type PW.NavSpawnCandidate[]
    local out = {}
    for i, point in ipairs(points(n or 8, 64, 1100)) do out[i] = { point = point, area = i + 1 } end
    return out
end

---@return table<integer, integer[]>
local function graph()
    ---@type table<integer, integer[]>
    local out = { [1] = {} }
    for i = 2, 9 do out[1][#out[1] + 1] = i; out[i] = { 1 } end
    return out
end

---@param detected? PW.MapSpawns
---@param samples? PW.NavSpawnCandidate[]
---@param clear? PW.NavClear
---@return PW.MapSpawn[]
local function supplements(detected, samples, clear)
    local lib = map()
    local component = must(lib._MutualNav(graph(), { 1 }, lib._FallbackRules))
    return lib._SpawnSupplements(detected or { [0] = points(17, 12) }, samples or candidates(),
        { component = component, clear = clear or function() return true end, rules = lib._FallbackRules })
end

---@return CNavArea[]
local function engineAreas()
    ---@type CNavArea[]
    local areas = {}
    for i = 1, 9 do
        local id = i
        ---@type table<string, any>
        local area = {
            IsValid = function() return true end,
            GetID = function() return id end,
            GetClosestPointOnArea = function(_, pos) return pos end,
            GetAdjacentAreas = function()
                if id > 1 then return { areas[1] } end
                ---@type CNavArea[]
                local adjacent = {}
                for j = 2, 9 do adjacent[#adjacent + 1] = areas[j] end
                return adjacent
            end
        }
        areas[i] = area --[[@as CNavArea]]
    end
    return areas
end

return {
    groupName = "PW map data: bounded spawn quality fallback",
    beforeEach = function(state)
        state.map = PW._Map
        state.spawns = PW._Spawns
        state.mode = PW.ActiveMode
        state.get = map().Get
        state.hull = must(PW.Spawns)._HullClear
        state.sample = must(PW.Spawns)._Sample
        state.nearest = navmesh.GetNearestNavArea
        state.clear = map()._SupplementClear
        state.mutual = map()._MutualNav
        state.load = map()._LoadSupplements
        state.rules = map()._FallbackRules
    end,
    afterEach = function(state)
        PW._Map = state.map
        PW._Spawns = state.spawns
        PW.ActiveMode = state.mode
        map().Get = state.get
        must(PW.Spawns)._HullClear = state.hull
        must(PW.Spawns)._Sample = state.sample
        rawset(navmesh, "GetNearestNavArea", state.nearest)
        rawset(map(), "_SupplementClear", state.clear)
        rawset(map(), "_MutualNav", state.mutual)
        rawset(map(), "_LoadSupplements", state.load)
        rawset(map(), "_FallbackRules", state.rules)
    end,
    cases = {
        {
            name = "Quality: zero and fewer than eight retain the old fallback; eight or more coincident qualify",
            func = function()
                local lib = map()
                expect(lib._SpawnClustered({}, lib._FallbackRules)).to.beFalse()
                expect(lib._SpawnClustered({ [0] = points(7) }, lib._FallbackRules)).to.beFalse()
                expect(lib._SpawnClustered({ [0] = points(8) }, lib._FallbackRules)).to.beTrue()
                expect(lib._SpawnClustered({ [0] = points(17) }, lib._FallbackRules)).to.beTrue()
                local nav = points(3, 1000)
                expect(#must(lib._Layer(nil, {}, nav, 8)[0])).to.equal(3)
                local few = { [1] = points(1), [0] = points(6) }
                local result = lib._Layer(nil, few, nav, 8, points(8, 64, 1100), 1)
                expect(result[1]).to.equal(few[1])
                expect(#must(result[0])).to.equal(9)
                expect(#must(few[0])).to.equal(6)
            end
        },
        {
            name = "Quality: compact diameter boundary, distributed points, small maps and two legitimate team zones",
            func = function()
                local lib, rules = map(), map()._FallbackRules
                expect(lib._SpawnClustered({ [0] = points(17, 12) }, rules)).to.beTrue()
                expect(lib._SpawnClustered({ [0] = points(9, 32) }, rules)).to.beTrue()
                expect(lib._SpawnClustered({ [0] = points(9, 32.01) }, rules)).to.beFalse()
                expect(lib._SpawnClustered({ [0] = points(8, 300) }, rules)).to.beFalse()
                local teams = { [1] = points(4, 16), [2] = points(4, 16, 1200) }
                expect(lib._SpawnClustered(teams, rules)).to.beFalse()
                local smallMap = candidates()
                for i, candidate in ipairs(smallMap) do candidate.point.pos = Vector(300 + i * 32, 0, 0) end
                expect(#supplements(nil, smallMap)).to.equal(0)
                expect(#supplements({ [0] = points(rules.maxDetected + 1) })).to.equal(0)
            end
        },
        {
            name = "Quality: at least eight distinct far candidates; exact distance boundary and nearest of all starts",
            func = function()
                local lib = map()
                expect(#supplements()).to.equal(8)
                expect(#supplements(nil, candidates(7))).to.equal(0)
                ---@type PW.NavSpawnCandidate[]
                local repeated = {}
                for i = 1, 8 do repeated[i] = { point = points(1, 0, 1200)[1], area = i + 1 } end
                expect(#supplements(nil, repeated)).to.equal(0)
                local far = candidates()
                far[1].point.pos = Vector(800, 0, 0)
                expect(#supplements({ [0] = points(8) }, far)).to.equal(8)
                far[1].point.pos = Vector(799.99, 0, 0)
                expect(#supplements({ [0] = points(8) }, far)).to.equal(0)
                far[1].point.pos = Vector(900, 0, 0)
                expect(#supplements({ [0] = points(8, 32) }, far)).to.equal(0)
                local reversed = candidates()
                reversed = table.Reverse(reversed)
                local a, b = supplements(), supplements(nil, reversed)
                for i, point in ipairs(a) do expect(point.pos).to.equal(must(b[i]).pos) end
                expect(#lib._SpawnSupplements({ [0] = points(8) }, far,
                    { component = {}, clear = function() return true end, rules = lib._FallbackRules })).to.equal(0)
                expect(#supplements(nil, candidates(lib._FallbackRules.maxCandidates + 1))).to.equal(0)
            end
        },
        {
            name = "Directed graph: only the mutual component of every anchor, not one-way islands or nearby roofs",
            func = function()
                local lib, rules = map(), map()._FallbackRules
                local nodes = { [1] = { 2, 3 }, [2] = { 1 }, [3] = {}, [4] = { 1 }, [5] = {} }
                local component = must(lib._MutualNav(nodes, { 1, 2 }, rules))
                expect(component[1]).to.beTrue()
                expect(component[2]).to.beTrue()
                expect(component[3]).to.beNil()
                expect(component[4]).to.beNil()
                expect(component[5]).to.beNil()
                expect(lib._MutualNav(nodes, { 1, 3 }, rules)).to.beNil()
                expect(lib._MutualNav(nodes, { 1, 5 }, rules)).to.beNil()
                expect(lib._MutualNav(nodes, { 99 }, rules)).to.beNil()
                expect(lib._MutualNav(nodes, {}, rules)).to.beNil()
                -- Every added point can reach an initial anchor and thus every objective reachable from that
                -- anchor. This is the same directed adjacency used by bots and Hardpoint activation, not travel proof.
                nodes[2] = { 1, 3 }
                component = must(lib._MutualNav(nodes, { 1, 2 }, rules))
                expect(component[2]).to.beTrue()
                expect(component[3]).to.beNil()
            end
        },
        {
            name = "Directed graph: unknown adjacency and bounded node or edge overflow fail closed",
            func = function()
                local lib = map()
                local rules = table.Copy(lib._FallbackRules)
                expect(lib._MutualNav({ [1] = { 99 } }, { 1 }, rules)).to.beNil()
                rules.maxAreas = 2
                expect(lib._MutualNav(graph(), { 1 }, rules)).to.beNil()
                rules.maxAreas, rules.maxEdges = 9, 2
                expect(lib._MutualNav(graph(), { 1 }, rules)).to.beNil()
            end
        },
        {
            name = "Validation: blocked or disconnected candidates cannot activate a seven-point supplement",
            func = function()
                expect(#supplements(nil, nil, function(pos) return pos.x ~= 1100 end)).to.equal(0)
                local samples = candidates()
                samples[1].area = 99
                expect(#supplements(nil, samples)).to.equal(0)
                samples[1].area = 2
                samples[1].point.pos = Vector(math.huge, 0, 0)
                expect(#supplements(nil, samples)).to.equal(0)
            end
        },
        {
            name = "Layers: quality supplements preserve authored data, detected lists, no-nav and legacy calls",
            func = function()
                local lib = map()
                local detected, extra = { [0] = points(17, 12) }, supplements()
                local layered = lib._Layer(nil, detected, {}, 8, extra)
                expect(#must(layered[0])).to.equal(25)
                expect(#must(detected[0])).to.equal(17)
                expect(#extra).to.equal(8)
                expect(lib._Layer(nil, detected, {}, 8)).to.equal(detected)
                expect(lib._Layer(nil, detected, {}, 8, {})).to.equal(detected)
                local authored = { [1] = points(1) }
                local result = lib._Layer(authored, detected, points(200), 8, extra)
                expect(#must(result[1])).to.equal(1)
                expect(result[0]).to.beNil()
            end
        },
        {
            name = "Picker: own first-team zone stays; respawns, FFA and unzoned starts expand",
            func = function()
                local lib, spawns = map(), must(PW.Spawns)
                local detected = { [1] = points(8, 12), [0] = points(1, 0, 10) }
                PW._Map = { detected = detected, nav = { loaded = true, areas = {}, samples = {}, eligible = 0,
                    costMs = 0, supplements = supplements(detected) } }
                lib.Get = function() return nil end
                local count = 0
                rawset(spawns, "_Sample", function(pool) count = #pool; return {} end)
                local ply = { Team = function() return 1 end } --[[@as Player]]
                PW.ActiveMode = { ClassName = "tdm", Teams = 2 } --[[@as PW.Entity]]
                PW._Spawns = spawns._NewStore()
                spawns.Pick(ply, { first = true, enemies = {}, mates = {} })
                expect(count).to.equal(9)
                spawns.Pick(ply, { first = false, enemies = {}, mates = {} })
                expect(count).to.equal(17)
                PW._Spawns.spawned[ply] = true
                spawns.Pick(ply, { enemies = {}, mates = {} })
                expect(count).to.equal(17)
                PW.ActiveMode = { ClassName = "ffa", Teams = 0 } --[[@as PW.Entity]]
                spawns.Pick(ply, { first = true, enemies = {}, mates = {} })
                expect(count).to.equal(17)
                PW.ActiveMode = { ClassName = "tdm", Teams = 2 } --[[@as PW.Entity]]
                PW._Map.detected = { [0] = points(17, 12) }
                spawns.Pick(ply, { first = true, enemies = {}, mates = {} })
                expect(count).to.equal(25)
            end
        },
        {
            name = "Picker: explicit mode-owned S&D side pool bypasses map quality supplements",
            func = function()
                local lib, spawns = map(), must(PW.Spawns)
                PW._Map = { detected = { [0] = points(17) }, nav = { loaded = true, areas = {}, samples = {},
                    eligible = 0, costMs = 0, supplements = supplements() } }
                lib.Get = function() error("mode-owned spawn pool must not consult ordinary map data") end
                local side = points(2, 64, 2000)
                local count = 0
                rawset(spawns, "_Sample", function(pool)
                    count = #pool
                    for i, point in ipairs(pool --[[@as PW.SpawnCandidate[] ]]) do
                        expect(point.pos).to.equal(must(side[i]).pos)
                    end
                    return {}
                end)
                PW._Spawns = spawns._NewStore()
                spawns.Pick({ Team = function() return 1 end } --[[@as Player]],
                    { first = true, all = false, spawns = { [1] = side }, enemies = {}, mates = {} })
                expect(count).to.equal(2)
            end
        },
        {
            name = "Cold glue: every anchor is required; one-way, unknown projection and expired budget fail closed",
            func = function()
                local lib, areas = map(), engineAreas()
                PW._Map = { detected = { [0] = points(8) } }
                lib.Get = function() return nil end
                rawset(lib, "_SupplementClear", function() return true end)
                rawset(navmesh, "GetNearestNavArea", function(pos, _, distance, _, ground)
                    expect(distance).to.equal(256)
                    expect(ground).to.beTrue()
                    if pos.x < 500 then return areas[1] end
                    return areas[math.Round((pos.x - 1100) / 64) + 2]
                end)
                local samples = points(8, 64, 1100)
                expect(#must(lib._LoadSupplements)(areas, samples)).to.equal(8)
                rawset(must(areas[2]), "GetAdjacentAreas", function() return {} end)
                expect(#must(lib._LoadSupplements)(areas, samples)).to.equal(0)
                PW._Map.detected = { [0] = points(8, 1) }
                rawset(navmesh, "GetNearestNavArea", function(pos)
                    if pos.x == 7 then return nil end
                    return areas[1]
                end)
                expect(#must(lib._LoadSupplements)(areas, samples)).to.equal(0)
                local rules = table.Copy(lib._FallbackRules)
                rules.budgetMs = -1
                rawset(lib, "_FallbackRules", rules)
                expect(#must(lib._LoadSupplements)(areas, samples)).to.equal(0)
            end
        },
        {
            name = "Cold glue: authored spawns bypass graph validation; cached getters never traverse the graph",
            func = function()
                local lib, extra = map(), supplements()
                PW._Map = { detected = { [0] = points(17, 12) }, nav = { loaded = true, areas = {}, samples = {},
                    eligible = 0, costMs = 0, supplements = extra } }
                rawset(lib, "Get", function()
                    return { ClassName = "authored", Spawns = { [1] = points(1) } } --[[@as PW.MapEntry]]
                end)
                rawset(navmesh, "GetNearestNavArea", function() error("authored data must bypass graph checks") end)
                expect(#must(lib._LoadSupplements)(engineAreas(), points(8))).to.equal(0)
                expect(#must(must(lib.GetSpawns)()[1])).to.equal(1)
                rawset(lib, "Get", function() return nil end)
                rawset(lib, "_MutualNav", function() error("getter must not traverse graph") end)
                rawset(lib, "_LoadSupplements", function() error("getter must use cache") end)
                rawset(lib, "_SupplementClear", function() error("getter must not trace") end)
                for _ = 1, 20 do expect(#must(must(lib.GetSpawns)()[0])).to.equal(25) end
                must(lib.PauseNav)(true)
                expect(#must(must(lib.GetSpawns)()[0])).to.equal(17)
            end
        },
        {
            name = "Native validation: supplement uses picker +8 hull, rejects AllSolid and missing ground",
            func = function()
                local lib = map()
                local traceHull, traceLine = util.TraceHull, util.TraceLine
                local ok, message = pcall(function()
                    rawset(util, "TraceHull", function(data)
                        expect(data.start).to.equal(Vector(1000, 0, 8))
                        expect(data.endpos).to.equal(data.start)
                        expect(data.mins).to.equal(Vector(-16, -16, 0))
                        expect(data.maxs).to.equal(Vector(16, 16, 72))
                        expect(data.mask).to.equal(MASK_PLAYERSOLID)
                        return { StartSolid = false, AllSolid = true } --[[@as TraceResult]]
                    end)
                    expect(must(lib._SupplementClear)(Vector(1000, 0, 0))).to.beFalse()
                    rawset(util, "TraceHull", function()
                        return { StartSolid = false, AllSolid = false } --[[@as TraceResult]]
                    end)
                    rawset(util, "TraceLine", function() return { Hit = false } --[[@as TraceResult]] end)
                    expect(must(lib._SupplementClear)(Vector(1000, 0, 0))).to.beFalse()
                    rawset(util, "TraceLine", function()
                        return { Hit = true, StartSolid = false, AllSolid = false, HitPos = Vector(1000, 0, 0),
                            HitNormal = Vector(0, 0, 1) } --[[@as TraceResult]]
                    end)
                    expect(must(lib._SupplementClear)(Vector(1000, 0, 0))).to.beTrue()
                    rawset(util, "TraceHull", function()
                        return { StartSolid = true, AllSolid = false } --[[@as TraceResult]]
                    end)
                    expect(must(lib._SupplementClear)(Vector(1000, 0, 0))).to.beFalse()
                end)
                util.TraceHull, util.TraceLine = traceHull, traceLine
                assert(ok, message)
            end
        }
    }
}
