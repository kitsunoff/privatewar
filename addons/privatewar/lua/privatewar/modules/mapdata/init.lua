-- Map data module, server glue (T-2.7; 03-mapdata.md d.3). Thin wrappers around the pure rules in shared.lua:
--   InitPostEntity: reads every spawn entity of the map once (ents.FindByClass over PW.Map._SpawnClasses) and
--     caches the grouped points in PW._Map, which survives pw_reload. Not a hot path: once per map.
--   GetSpawns / GetDetectedSpawns: the layered and the detected spawns, read from the cache.
--   Navmesh (T-2.8): the engine loads the .nav after InitPostEntity, so the first Think after it reads the navmesh
--     once (retried navTriesMax times, 1 s apart, while the area count is 0), caches the areas and samples the
--     fallback spawn points (PW.Map._NavSample over plain area data). No navmesh: one log line, nothing else.
--   PauseNav (T-2.12): the navgen module pauses the sampler while a navmesh generation runs and drops the cached
--     areas (generation destroys the navmesh); the map reloads when generation ends, which starts over.
-- The engine hook goes through PW.HookFor, so it runs only while the module is enabled (01-extensibility.md d.16).

local lib = PW.Map --[[@as PW.MapLib]]
include("privatewar/modules/mapdata/sv_spawn_quality.lua")

---The TeamNum keyvalue of a spawn entity (kept by the engine in the entity's datadesc), nil if not a number.
---@param ent Entity
---@return integer?
local function teamNumOf(ent)
    local value = ent:GetInternalVariable("TeamNum")
    if isnumber(value) then return value --[[@as integer]] end
    return nil
end

---@return PW.SpawnRecord[]
function lib._Collect()
    ---@type PW.SpawnRecord[]
    local records = {}
    local classes = table.GetKeys(lib._SpawnClasses) --[[@as string[] ]]
    table.sort(classes)
    for _, class in ipairs(classes) do
        local rule = lib._SpawnClasses[class]
        for _, ent in ipairs(ents.FindByClass(class)) do
            local teamNum = rule.byTeamNum and teamNumOf(ent) or nil
            records[#records + 1] = { class = class, pos = ent:GetPos(), yaw = ent:GetAngles().y, teamNum = teamNum }
        end
    end
    return records
end

---@return PW.MapSpawns
function lib._Detect()
    return lib._GroupSpawns(lib._Collect())
end

---@param reason string
---@return PW.MapSpawns
function lib._Refresh(reason)
    local detected = lib._Detect()
    PW._Map.detected = detected
    if PW._Map.nav ~= nil then PW._Map.nav.supplements = nil end
    PW._Map.reason = reason
    return detected
end

---@return PW.MapSpawns
function lib.GetDetectedSpawns()
    return PW._Map.detected or lib._Refresh("on demand")
end

---@param firstTeam? integer preserve a real team's detected first-spawn zone on the new quality-fallback path
---@return PW.MapSpawns
function lib.GetSpawns(firstTeam)
    local entry = lib.Get()
    local nav = PW._Map.nav
    return lib._Layer(entry ~= nil and entry.Spawns or nil, lib.GetDetectedSpawns(), lib.GetNavSamples(),
        lib._NavRules.minSpawns, nav ~= nil and nav.supplements or nil, firstTeam)
end

local navTriesMax = 5
local hullMins, hullMaxs = Vector(-16, -16, 0), Vector(16, 16, 72)
local hullLift = Vector(0, 0, 18)

---Thin trace wrapper: whether a standing player hull fits at pos (lifted by the step height for slopes).
---@param pos Vector
---@return boolean
function lib._HullClear(pos)
    local start = pos + hullLift
    local tr = util.TraceHull({ start = start, endpos = start, mins = hullMins, maxs = hullMaxs,
        mask = MASK_PLAYERSOLID })
    return not tr.StartSolid
end

---@param area CNavArea
---@return PW.NavAreaData
function lib._ReadNavArea(area)
    ---@type Vector[]
    local corners = {}
    for i = 0, 3 do corners[i + 1] = area:GetCorner(i) end
    return {
        id = area:GetID(),
        center = area:GetCenter(),
        sizeX = area:GetSizeX(),
        sizeY = area:GetSizeY(),
        underwater = area:IsUnderwater(),
        crouch = area:HasAttributes(NAV_MESH_CROUCH),
        corners = corners
    }
end

---@param opts? PW.NavLoadOpts
---@return PW.MapNav
function lib._LoadNav(opts)
    opts = opts or {}
    local log = opts.log or function(message) print("[PW] " .. message) end
    local count = (opts.count or navmesh.GetNavAreaCount)()
    if count == 0 then
        local nav = { loaded = false, areas = {}, samples = {}, eligible = 0, costMs = 0 }
        PW._Map.nav = nav
        log("map " .. game.GetMap() .. ": no navmesh; navmesh spawn fallback unavailable")
        return nav
    end
    local started = SysTime()
    local areas = (opts.areas or navmesh.GetAllNavAreas)()
    ---@type PW.NavAreaData[]
    local data = {}
    for i, area in ipairs(areas) do data[i] = lib._ReadNavArea(area) end
    local samples, eligible = lib._NavSample(data, lib._NavRules, lib._HullClear)
    local supplements = lib._LoadSupplements(areas, samples)
    local nav = { loaded = true, areas = areas, samples = samples, eligible = eligible,
        costMs = (SysTime() - started) * 1000, supplements = supplements }
    PW._Map.nav = nav
    log(string.format("map %s: navmesh %d areas, %d eligible, %d spawn samples, %d quality supplements, %.1f ms",
        game.GetMap(), #areas, eligible, #samples, #supplements, nav.costMs))
    return nav
end

---@return PW.MapSpawn[]
function lib.GetNavSamples()
    local nav = PW._Map.nav
    return nav ~= nil and nav.samples or {}
end

---@return CNavArea[]
function lib.GetNavAreas()
    local nav = PW._Map.nav
    return nav ~= nil and nav.areas or {}
end

PW.HookFor(MODULE, "InitPostEntity", function()
    lib._Refresh("InitPostEntity")
    PW._Map.navCheckAt = 0
    PW._Map.navTries = 0
end)

function lib._NavThink()
    local store = PW._Map
    local at = store.navCheckAt
    if store.navPaused or at == nil or store.nav ~= nil or CurTime() < at then return end
    local tries = (store.navTries or 0) + 1
    store.navTries = tries
    if navmesh.GetNavAreaCount() > 0 or tries >= navTriesMax then
        store.navCheckAt = nil
        lib._LoadNav()
    else
        store.navCheckAt = CurTime() + 1
    end
end

---@param paused boolean
function lib.PauseNav(paused)
    local store = PW._Map
    if not paused then
        store.navPaused = nil
        return
    end
    store.navPaused = true
    local nav = store.nav
    if nav ~= nil then
        store.nav = { loaded = false, areas = {}, samples = nav.samples, eligible = nav.eligible, costMs = nav.costMs }
    end
end

PW.HookFor(MODULE, "Think", function() lib._NavThink() end)
