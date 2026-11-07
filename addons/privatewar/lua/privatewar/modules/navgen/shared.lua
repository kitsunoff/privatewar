-- Navmesh generation (T-2.12; 03-mapdata.md d.8; notes/11-navmesh-generation.md "Recommendations"). Owns
-- PW.NavGen. Shared: the privilege name and the pure rules over plain data (the seeds from spawn records, the
-- "may generate now" check, the marker format and its validation, the fast mode default, the result text). Server
-- glue (navmesh.*, file.*, RunConsoleCommand, the net message, the post-reload check): init.lua. The lobby screen
-- (lobby_ui) draws the navmesh line and sends pw_navgen_start.
--
-- Flow: the host presses Generate in LOBBY on a map without navmesh -> the marker data/privatewar/navgen.json is
-- written -> bots are kicked, the map data sampler is paused -> (fast mode: sv_cheats 1, nav_max_view_distance 1,
-- one tick) -> one walkable seed per spawn entity -> navmesh.BeginGeneration(). The engine saves maps/<map>.nav and
-- reloads the map by itself; on the new load the marker tells success, failure or stale, the host sees the result.

MODULE.Name = "Navmesh generation"

local lib = (rawget(PW, "NavGen") or {}) --[[@as PW.NavGenLib]]
PW.NavGen = lib

lib.Privilege = "pw.map.navgen"
lib.Version = 1
lib.MaxAge = 6 * 3600

function lib._Seeds(records, classes)
    ---@type PW.NavGenSeed[]
    local seeds = {}
    for _, rec in ipairs(records) do
        if classes[rec.class] ~= nil then seeds[#seeds + 1] = { class = rec.class, pos = rec.pos } end
    end
    return seeds
end

function lib._MayGenerate(facts)
    if not facts.allowed then return false, "privilege" end
    if facts.phase ~= "LOBBY" then return false, "phase" end
    if facts.generating or facts.changing then return false, "busy" end
    if facts.areas > 0 and not facts.force then return false, "navmesh exists" end
    return true
end

local fieldTypes = { map = "string", startedAt = "number", fast = "boolean", cheatsWasOn = "boolean" }

function lib._ValidateMarker(marker, facts)
    if not istable(marker) or not isnumber(marker.v) then return "stale", "corrupt" end
    for field, expected in pairs(fieldTypes) do
        if type(marker[field]) ~= expected then return "stale", "corrupt" end
    end
    if marker.v ~= lib.Version then return "stale", "version" end
    if marker.map ~= facts.map then return "stale", "map" end
    local startedAt = marker.startedAt --[[@as number]]
    local age = facts.now - startedAt
    if age < 0 or age > lib.MaxAge then return "stale", "age" end
    if facts.areas > 0 then return "success" end
    return "failure"
end

function lib._Encode(marker)
    return util.TableToJSON(marker)
end

function lib._Decode(text)
    local decoded = util.JSONToTable(text, false, true)
    if not istable(decoded) then return nil end
    return decoded
end

function lib._FastDefault(humans)
    return humans <= 1
end

function lib._ResultText(kind, map, areas)
    if kind == "success" then return string.format("Navmesh generated for %s: %d areas.", map, areas) end
    return string.format("The last navmesh generation on %s did not finish. Try again, try fast mode, search the " ..
        "Workshop for \"%s navmesh\", or pick another map.", map, map)
end
