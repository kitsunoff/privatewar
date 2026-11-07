-- Map data module (T-2.7, T-2.8; 03-mapdata.md d.1-d.3, d.6, d.7; docs/api/map.md). Owns PW.Map: the current
-- map's entry of the maps kind, mode data along a mode's Base chain, and the spawn layers (map file over
-- auto-detected spawn entities, then the navmesh fallback). Shared: the API and the pure rules (plain data in, plain
-- data out). Server glue that reads the spawn entities and the navmesh once per map: init.lua. The module stores
-- mode data only; it never interprets it (d.6).

MODULE.Name = "Map data"

local lib = (rawget(PW, "Map") or {}) --[[@as PW.MapLib]]
PW.Map = lib

lib.AnyTeam = 0

-- Engine teams 2 and 3 of CS:S (T, CT), HL2DM (Combine, Rebels) and TF2 (RED, BLU) become teams 1 and 2.
lib._SpawnClasses = {
    info_player_terrorist = { team = 1 },
    info_player_counterterrorist = { team = 2 },
    info_player_combine = { team = 1 },
    info_player_rebel = { team = 2 },
    info_player_deathmatch = { team = 0 },
    info_player_teamspawn = { byTeamNum = true },
    info_player_start = { team = 0, generic = true },
    gmod_player_start = { team = 0, generic = true }
}

---@return PW.MapStore
function lib._NewStore()
    return {}
end

PW._Map = PW._Map or lib._NewStore()

---@param mapName string
---@return string
function lib.Id(mapName)
    return (string.gsub(string.lower(mapName), "[^a-z0-9_]", "_"))
end

---@param class string
---@param teamNum? integer
---@return integer?
---@return boolean
function lib._SpawnTeam(class, teamNum)
    local rule = lib._SpawnClasses[class]
    if rule == nil then return nil, false end
    if rule.byTeamNum then
        if teamNum == 2 or teamNum == 3 then return teamNum - 1, false end
        return lib.AnyTeam, false
    end
    return rule.team or lib.AnyTeam, rule.generic == true
end

---@param records PW.SpawnRecord[]
---@return PW.MapSpawns
function lib._GroupSpawns(records)
    ---@type PW.MapSpawns
    local specific, generic = {}, {}
    local hasSpecific = false
    for _, rec in ipairs(records) do
        local team, isGeneric = lib._SpawnTeam(rec.class, rec.teamNum)
        if team ~= nil then
            local target = isGeneric and generic or specific
            if not isGeneric then hasSpecific = true end
            local list = target[team] or {}
            target[team] = list
            list[#list + 1] = { pos = rec.pos, yaw = rec.yaw }
        end
    end
    if hasSpecific then return specific end
    return generic
end

---The valid points of one team's list in a map file.
---@param list any[]
---@return PW.MapSpawn[]
local function cleanList(list)
    ---@type PW.MapSpawn[]
    local points = {}
    for _, point in ipairs(list) do
        if istable(point) and isvector(point.pos) then
            points[#points + 1] = { pos = point.pos, yaw = isnumber(point.yaw) and point.yaw or 0 }
        end
    end
    return points
end

---@param raw any
---@return PW.MapSpawns
---@return integer
function lib._CleanSpawns(raw)
    ---@type PW.MapSpawns
    local spawns = {}
    local total = 0
    if not istable(raw) then return spawns, 0 end
    for team, list in pairs(raw --[[@as table<any, any>]]) do
        local valid = isnumber(team) and team >= 0 and team == math.floor(team) and istable(list)
        local points = valid and cleanList(list --[[@as any[] ]]) or {}
        if #points > 0 then
            spawns[team --[[@as integer]]] = points
            total = total + #points
        end
    end
    return spawns, total
end

---@param spawns PW.MapSpawns
---@return integer
local function total(spawns)
    local n = 0
    for _, list in pairs(spawns) do n = n + #list end
    return n
end

---@param fileSpawns any
---@param detected PW.MapSpawns
---@param navSamples? PW.MapSpawn[]
---@param minSpawns? integer
---@return PW.MapSpawns
function lib._Layer(fileSpawns, detected, navSamples, minSpawns)
    local spawns, fileTotal = lib._CleanSpawns(fileSpawns)
    if fileTotal > 0 then return spawns end
    if navSamples == nil or #navSamples == 0 or minSpawns == nil or total(detected) >= minSpawns then
        return detected
    end
    ---@type PW.MapSpawns
    local layered = {}
    for team, list in pairs(detected) do layered[team] = list end
    ---@type PW.MapSpawn[]
    local any = {}
    for _, point in ipairs(detected[lib.AnyTeam] or {}) do any[#any + 1] = point end
    for _, point in ipairs(navSamples) do any[#any + 1] = point end
    layered[lib.AnyTeam] = any
    return layered
end

-- Navmesh fallback (T-2.8; 03-mapdata.md d.3, d.7). Gameplay values, reported for confirmation.
lib._NavRules = {
    minSide = 32,
    maxSlope = 30,
    count = 200,
    minSpawns = 8,
    budgetMs = 100
}

---@param corners Vector[]
---@return number
function lib._NavSlope(corners)
    local nw, ne, se, sw = corners[1], corners[2], corners[3], corners[4]
    if nw == nil or ne == nil or se == nil or sw == nil then return 0 end
    local normal = (se - nw):Cross(sw - ne)
    local len = normal:Length()
    if len < 1e-6 then return 0 end
    return math.deg(math.acos(math.min(1, math.abs(normal.z) / len)))
end

---@param area PW.NavAreaData
---@param rules PW.NavRules
---@return boolean
---@return string?
function lib._NavAreaOk(area, rules)
    if math.min(area.sizeX, area.sizeY) < rules.minSide then return false, "small" end
    if area.underwater then return false, "water" end
    if area.crouch then return false, "crouch" end
    if lib._NavSlope(area.corners) > rules.maxSlope then return false, "steep" end
    return true
end

---Every sample faces the middle of all samples.
---@param samples PW.MapSpawn[]
local function faceMiddle(samples)
    if #samples == 0 then return end
    local sum = Vector(0, 0, 0)
    for _, s in ipairs(samples) do sum = sum + s.pos end
    local middle = sum / #samples
    for _, s in ipairs(samples) do
        local dx, dy = middle.x - s.pos.x, middle.y - s.pos.y
        s.yaw = (dx ~= 0 or dy ~= 0) and math.deg(math.atan2(dy, dx)) or 0
    end
end

---@param areas PW.NavAreaData[]
---@param rules PW.NavRules
---@param clear? fun(pos: Vector): boolean
---@return PW.MapSpawn[]
---@return integer eligible
function lib._NavSample(areas, rules, clear)
    ---@type PW.NavAreaData[]
    local eligible = {}
    for _, area in ipairs(areas) do
        if lib._NavAreaOk(area, rules) then eligible[#eligible + 1] = area end
    end
    local n = #eligible
    local slots = math.min(rules.count, n)
    ---@type PW.MapSpawn[]
    local samples = {}
    for slot = 1, slots do
        for i = math.floor((slot - 1) * n / slots) + 1, math.floor(slot * n / slots) do
            local pos = eligible[i].center
            if clear == nil or clear(pos) then
                samples[#samples + 1] = { pos = pos, yaw = 0 }
                break
            end
        end
    end
    faceMiddle(samples)
    return samples, n
end

---@param mode table?
---@param modeId string
---@return string[]
function lib._ModeChain(mode, modeId)
    local chain = { modeId }
    ---@type table<table, true>
    local seen = {}
    ---@type any
    local current = mode ~= nil and mode.BaseClass or nil
    if mode ~= nil then seen[mode] = true end
    while istable(current) and not seen[current] do
        local base = current --[[@as table<string, any>]]
        seen[base] = true
        local id = base.ClassName --[[@as any]]
        if isstring(id) then chain[#chain + 1] = id --[[@as string]] end
        current = base.BaseClass
    end
    return chain
end

---@param modes any
---@param chain string[]
---@return table?
function lib._FindModeData(modes, chain)
    if not istable(modes) then return nil end
    for _, id in ipairs(chain) do
        local data = (modes --[[@as table<string, any>]])[id]
        if istable(data) then return data end
    end
    return nil
end

---@param mapName? string
---@return PW.MapEntry?
function lib.Get(mapName)
    local registry = rawget(PW, "Maps") --[[@as PW.Registry?]]
    if registry == nil then return nil end
    local entry = registry.Get(lib.Id(mapName or game.GetMap())) --[[@as PW.MapEntry?]]
    if entry == nil or (entry.IsValid ~= nil and not entry:IsValid()) then return nil end
    return entry
end

---@param modeId string
---@return table?
function lib.GetModeData(modeId)
    local entry = lib.Get()
    if entry == nil then return nil end
    local modes = rawget(PW, "Modes") --[[@as PW.Registry?]]
    local mode = modes ~= nil and modes.Get(modeId) or nil
    return lib._FindModeData(entry.Modes, lib._ModeChain(mode, modeId))
end

---One log line per map and mode for map data a mode rejects (03-mapdata.md d.6).
---@param mapName string
---@param modeId string
---@param reason string
local function reportInvalid(mapName, modeId, reason)
    local store = PW._Map
    local seen = store.reported or {}
    store.reported = seen
    local key = mapName .. "/" .. modeId
    if seen[key] then return end
    seen[key] = true
    print(string.format("[PW] map %s: invalid data for mode %s, the mode is hidden there: %s", mapName, modeId,
        reason))
end

---@param mode table
---@param mapName string
---@return boolean
---@return string?
function lib.ModeFits(mode, mapName)
    if mode.MapData ~= true then return true end
    local modeId = tostring(mode.ClassName)
    local entry = lib.Get(mapName)
    if entry == nil then return false, "no map data" end
    local data = lib._FindModeData(entry.Modes, lib._ModeChain(mode, modeId))
    if data == nil then return false, "no data for " .. modeId end
    if not isfunction(mode.ValidateMapData) then return true end
    local ok, reason = PW.Call(mode, "ValidateMapData", data)
    if ok == true then return true end
    reason = isstring(reason) and reason or "ValidateMapData failed"
    reportInvalid(mapName, modeId, reason)
    return false, reason
end
