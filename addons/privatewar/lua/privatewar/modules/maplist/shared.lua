-- Map list module (T-2.11; 03-mapdata.md d.9; docs/api/map.md "Map list"). Owns PW.MapList: the curated list of
-- maps for the vote, the rotation and playlists with Maps = nil: the union of maps that have a data file, maps with
-- a PvP prefix and the host's whitelist, minus junk. Only installed maps are ever listed. Shared: the settings and
-- the pure filter over plain data. Server glue (file.Find, the registry, the settings): init.lua.
--
-- Settings (scope server, ConVars pw_maplist_prefixes and pw_maplist_whitelist, archived):
--   maplist.prefixes   set, the PvP prefixes ("de_" lists de_dust2)
--   maplist.whitelist  set, map names the host added by hand (gm_construct, an RP map)

MODULE.Name = "Map list"

local defaultPrefixes = { "de_", "cs_", "ar_", "fy_", "dm_", "tdm_", "ctf_", "koth_", "cp_", "pl_", "plr_", "arena_",
    "sd_" }

MODULE.Settings = {
    prefixes = { scope = "server", type = "set", label = "Map prefixes", default = defaultPrefixes },
    whitelist = { scope = "server", type = "set", label = "Whitelisted maps", default = {} }
}

local lib = (rawget(PW, "MapList") or {}) --[[@as PW.MapListLib]]
PW.MapList = lib

lib.DefaultPrefixes = defaultPrefixes

-- 03-mapdata.md d.9 names background*, d1_*, d2_*, d3_*, ep1_*, ep2_*; credits, test maps and the HL2 intro are
-- added as "the like" (the lane agent's choice, reported).
lib.JunkPatterns = { "^background", "^d1_", "^d2_", "^d3_", "^ep1_", "^ep2_", "^credits$", "^test_", "^test$",
    "^intro$" }

---@param mapName string
---@return boolean
function lib.IsJunk(mapName)
    local name = string.lower(mapName)
    for _, pattern in ipairs(lib.JunkPatterns) do
        if string.find(name, pattern) then return true end
    end
    return false
end

---The members of a set value (a lookup { [id] = true } or a list) as lowercase strings.
---@param set PW.MapListSet
---@return string[]
local function members(set)
    ---@type string[]
    local out = {}
    for key, value in pairs(set --[[@as table<any, any>]]) do
        local id = isstring(key) and key or value
        if isstring(id) and id ~= "" then out[#out + 1] = string.lower(id --[[@as string]]) end
    end
    return out
end

---@param set PW.MapListSet
---@return table<string, true>
local function lookupOf(set)
    ---@type table<string, true>
    local lookup = {}
    for _, id in ipairs(members(set)) do lookup[id] = true end
    return lookup
end

---@param lower string
---@param prefixes string[]
---@return boolean
local function hasPrefix(lower, prefixes)
    for _, prefix in ipairs(prefixes) do
        if string.sub(lower, 1, #prefix) == prefix then return true end
    end
    return false
end

---Same rule as PW.Map.Id (lowercase, every character outside [a-z0-9_] becomes "_"); kept local so the list does
---not depend on the mapdata module being loaded.
---@param mapName string
---@return string
local function dataId(mapName)
    return (string.gsub(string.lower(mapName), "[^a-z0-9_]", "_"))
end

---@param sources PW.MapListSources
---@return string[]
function lib.Filter(sources)
    local data = lookupOf(sources.data)
    local whitelist = lookupOf(sources.whitelist)
    local prefixes = members(sources.prefixes)
    ---@type table<string, true>
    local seen = {}
    ---@type string[]
    local list = {}
    for _, name in ipairs(sources.installed) do
        local lower = string.lower(name)
        local wanted = data[dataId(name)] or whitelist[lower] or hasPrefix(lower, prefixes)
        if wanted and not seen[name] and not lib.IsJunk(name) then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end

---@param files string[]
---@return string[]
function lib._NamesFromFiles(files)
    ---@type table<string, true>
    local seen = {}
    ---@type string[]
    local names = {}
    for _, file in ipairs(files) do
        local name = string.match(file, "^(.+)%.bsp$")
        if name ~= nil and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end
