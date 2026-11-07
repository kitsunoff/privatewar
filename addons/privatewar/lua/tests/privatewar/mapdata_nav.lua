-- T-2.8 navmesh fallback (TASKS.md, "Mandatory test cases" T-2.8; 03-mapdata.md d.3, d.7; docs/api/map.md).
-- Pure cases run over synthetic area data (plain tables, no CNavArea): the size, water, slope and crouch filters,
-- the slope of an area from its corners, the spread selection capped at the sample count, the hull predicate and
-- the spawn layers with the navmesh samples. The glue cases swap PW._Map for a fresh store and inject the navmesh
-- reads, so "no navmesh" is tested on any map. The in-game smoke reads the real navmesh of the loaded map
-- (gm_construct in the test run) and measures the cost of one sampling pass.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.MapLib
local function lib()
    return must(PW.Map)
end

---@return PW.NavRules
local function rules()
    return lib()._NavRules
end

---A synthetic area: a rectangle of sizeX by sizeY with its north-west corner at (x, y), tilted along x by slope
---degrees (z rises with x). Corners in CNavArea order: north-west, north-east, south-east, south-west.
---@param id integer
---@param x number
---@param y number
---@param opts? { sizeX?: number, sizeY?: number, slope?: number, underwater?: boolean, crouch?: boolean }
---@return PW.NavAreaData
local function area(id, x, y, opts)
    opts = opts or {}
    local sx, sy = opts.sizeX or 100, opts.sizeY or 100
    local rise = sx * math.tan(math.rad(opts.slope or 0))
    local corners = {
        Vector(x, y, 0), Vector(x + sx, y, rise), Vector(x + sx, y + sy, rise), Vector(x, y + sy, 0)
    }
    return {
        id = id,
        center = Vector(x + sx / 2, y + sy / 2, rise / 2),
        sizeX = sx,
        sizeY = sy,
        underwater = opts.underwater == true,
        crouch = opts.crouch == true,
        corners = corners
    }
end

---Whether pos lies on the area: inside its x/y rectangle and at the height of its plane there.
---@param pos Vector
---@param a PW.NavAreaData
---@return boolean
local function onArea(pos, a)
    local nw, se = must(a.corners[1]), must(a.corners[3])
    local inside = pos.x >= nw.x and pos.x <= se.x and pos.y >= nw.y and pos.y <= se.y
    local t = (pos.x - nw.x) / (se.x - nw.x)
    local z = nw.z + t * (se.z - nw.z)
    return inside and math.abs(pos.z - z) < 0.01
end

---@param samples PW.MapSpawn[]
---@param areas PW.NavAreaData[]
---@return PW.NavAreaData[] hit the area each sample lies on, in sample order
local function areasOf(samples, areas)
    ---@type PW.NavAreaData[]
    local hit = {}
    for _, s in ipairs(samples) do
        for _, a in ipairs(areas) do
            if onArea(s.pos, a) then
                hit[#hit + 1] = a
                break
            end
        end
    end
    return hit
end

---@param n integer
---@return PW.NavAreaData[]
local function grid(n)
    ---@type PW.NavAreaData[]
    local list = {}
    for i = 1, n do list[i] = area(i, (i - 1) * 200, 0) end
    return list
end

---@param spawns PW.MapSpawns
---@param team integer
---@return integer
local function count(spawns, team)
    local list = spawns[team]
    if list == nil then return 0 end
    return #list
end

---@param n integer
---@return PW.MapSpawn[]
local function points(n)
    ---@type PW.MapSpawn[]
    local list = {}
    for i = 1, n do list[i] = { pos = Vector(i, 0, 0), yaw = 0 } end
    return list
end

return {
    groupName = "PW map data: navmesh fallback",
    beforeEach = function(state)
        state.store = PW._Map
    end,
    afterEach = function(state)
        PW._Map = state.store --[[@as PW.MapStore]]
    end,
    cases = {
        {
            name = "Mandatory (T-2.8): sampled points are on walkable areas and respect the size/water/slope filters",
            func = function()
                local r = rules()
                local good = { area(1, 0, 0), area(2, 1000, 0, { slope = r.maxSlope - 5 }), area(3, 2000, 0) }
                local bad = {
                    area(10, 0, 1000, { sizeX = r.minSide - 1 }),
                    area(11, 1000, 1000, { sizeY = r.minSide - 1 }),
                    area(12, 2000, 1000, { underwater = true }),
                    area(13, 3000, 1000, { slope = r.maxSlope + 5 }),
                    area(14, 4000, 1000, { crouch = true })
                }
                local all = { bad[1], good[1], bad[2], bad[3], good[2], bad[4], good[3], bad[5] }
                local samples = lib()._NavSample(all, r)
                expect(#samples).to.equal(#good)
                local hit = areasOf(samples, all)
                expect(#hit).to.equal(#samples)
                for i, a in ipairs(hit) do
                    expect(a.id).to.equal(must(good[i]).id)
                    expect(lib()._NavAreaOk(a, r)).to.beTrue()
                    expect(a.underwater).to.beFalse()
                    expect(math.min(a.sizeX, a.sizeY) >= r.minSide).to.beTrue()
                    expect(lib()._NavSlope(a.corners) <= r.maxSlope).to.beTrue()
                end
            end
        },
        {
            name = "Filters: each rule rejects with its reason; the limits themselves pass",
            func = function()
                local r = rules()
                expect(lib()._NavAreaOk(area(1, 0, 0, { sizeX = r.minSide, sizeY = r.minSide }), r)).to.beTrue()
                local ok, why = lib()._NavAreaOk(area(1, 0, 0, { sizeX = r.minSide - 0.5 }), r)
                expect(ok).to.beFalse()
                expect(why).to.equal("small")
                ok, why = lib()._NavAreaOk(area(1, 0, 0, { underwater = true }), r)
                expect(ok).to.beFalse()
                expect(why).to.equal("water")
                expect(lib()._NavAreaOk(area(1, 0, 0, { slope = r.maxSlope - 0.01 }), r)).to.beTrue()
                ok, why = lib()._NavAreaOk(area(1, 0, 0, { slope = r.maxSlope + 0.5 }), r)
                expect(ok).to.beFalse()
                expect(why).to.equal("steep")
                ok, why = lib()._NavAreaOk(area(1, 0, 0, { crouch = true }), r)
                expect(ok).to.beFalse()
                expect(why).to.equal("crouch")
            end
        },
        {
            name = "Slope from corners: flat 0, tilted planes their angle, degenerate corners 0",
            func = function()
                expect(lib()._NavSlope(area(1, 0, 0).corners)).to.equal(0)
                expect(math.abs(lib()._NavSlope(area(1, 0, 0, { slope = 20 }).corners) - 20) < 0.01).to.beTrue()
                expect(math.abs(lib()._NavSlope(area(1, 0, 0, { slope = 45 }).corners) - 45) < 0.01).to.beTrue()
                local v = Vector(5, 5, 5)
                expect(lib()._NavSlope({ v, v, v, v })).to.equal(0)
            end
        },
        {
            name = "Selection: at most rules.count points, spread over the whole area list",
            func = function()
                local r = rules()
                local list = grid(r.count * 5)
                local hit = areasOf(lib()._NavSample(list, r), list)
                expect(#hit).to.equal(r.count)
                expect(must(hit[1]).id).to.equal(1)
                expect(must(hit[#hit]).id > r.count * 4).to.beTrue()
                local few = grid(10)
                expect(#lib()._NavSample(few, r)).to.equal(10)
                expect(#lib()._NavSample({}, r)).to.equal(0)
            end
        },
        {
            name = "Hull predicate: a blocked area is replaced by the next one of its slot, never sampled",
            func = function()
                local r = { minSide = rules().minSide, maxSlope = rules().maxSlope, count = 2 }
                local list = grid(6)
                local blocked = { [1] = true, [4] = true, [5] = true, [6] = true }
                local samples = lib()._NavSample(list, r, function(pos)
                    for _, a in ipairs(areasOf({ { pos = pos, yaw = 0 } }, list)) do
                        if blocked[a.id] then return false end
                    end
                    return true
                end)
                local hit = areasOf(samples, list)
                expect(#hit).to.equal(1)
                expect(must(hit[1]).id).to.equal(2)
            end
        },
        {
            name = "Yaw: every sample faces the middle of the samples",
            func = function()
                local list = { area(1, -1050, -50), area(2, 950, -50) }
                local samples = lib()._NavSample(list, rules())
                expect(math.Round(must(samples[1]).yaw)).to.equal(0)
                expect(math.abs(math.Round(must(samples[2]).yaw))).to.equal(180)
            end
        },
        {
            name = "Layers: navmesh samples join the any-team points only without file spawns and too few detected",
            func = function()
                local min = rules().minSpawns
                local nav = points(5)
                local none = lib()._Layer(nil, {}, nav, min)
                expect(count(none, 0)).to.equal(5)
                local few = { [1] = points(1), [0] = points(min - 2) }
                local layered = lib()._Layer(nil, few, nav, min)
                expect(count(layered, 1)).to.equal(1)
                expect(count(layered, 0)).to.equal(min - 2 + 5)
                expect(count(few, 0)).to.equal(min - 2)
                local enough = { [1] = points(min / 2), [2] = points(min / 2) }
                expect(lib()._Layer(nil, enough, nav, min)).to.equal(enough)
                local file = { [1] = { { pos = Vector(1, 1, 1), yaw = 0 } } }
                local fromFile = lib()._Layer(file, {}, nav, min)
                expect(count(fromFile, 1)).to.equal(1)
                expect(count(fromFile, 0)).to.equal(0)
                expect(lib()._Layer(nil, few, {}, min)).to.equal(few)
                expect(lib()._Layer(nil, few)).to.equal(few)
            end
        },
        {
            name = "No navmesh: nothing is sampled, one log line, empty getters",
            func = function()
                PW._Map = lib()._NewStore()
                ---@type string[]
                local lines = {}
                must(lib()._LoadNav)({
                    count = function() return 0 end,
                    areas = function() error("must not read areas without a navmesh") end,
                    log = function(message) lines[#lines + 1] = message end
                })
                expect(#lines).to.equal(1)
                expect(string.find(must(lines[1]), "no navmesh", 1, true)).to.exist()
                expect(#must(lib().GetNavSamples)()).to.equal(0)
                expect(#must(lib().GetNavAreas)()).to.equal(0)
                expect(must(PW._Map.nav).loaded).to.beFalse()
            end
        },
        {
            name = "In-game: on gm_construct the navmesh is sampled once after load, within the time budget",
            func = function()
                if game.GetMap() == "gm_construct" then expect(navmesh.GetNavAreaCount() > 0).to.beTrue() end
                if navmesh.GetNavAreaCount() == 0 then return end
                local cached = must(PW._Map.nav)
                expect(cached.loaded).to.beTrue()
                expect(#must(lib().GetNavAreas)()).to.equal(navmesh.GetNavAreaCount())
                PW._Map = lib()._NewStore()
                must(lib()._LoadNav)({ log = function() end })
                local nav = must(PW._Map.nav)
                local samples = must(lib().GetNavSamples)()
                print(string.format("[PW] navmesh smoke on %s: %d areas, %d eligible, %d samples, %.1f ms",
                    game.GetMap(), #nav.areas, nav.eligible, #samples, nav.costMs))
                expect(#samples > 0).to.beTrue()
                expect(#samples <= rules().count).to.beTrue()
                expect(nav.costMs).to.beLessThan(rules().budgetMs)
                for _, s in ipairs(samples) do
                    local a = navmesh.GetNearestNavArea(s.pos, false, 64, false, true)
                    expect(a).to.exist()
                    expect(must(a):IsUnderwater()).to.beFalse()
                end
            end
        }
    }
}
