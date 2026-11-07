-- Map list module, server glue (T-2.11; 03-mapdata.md d.9). Thin wrappers around the pure filter in shared.lua:
-- file.Find over maps/*.bsp, the enabled entries of the maps registry and the two server settings.
-- The "Show all maps" list of Custom is GetInstalled (everything installed except junk); the curated list is
-- GetList. Both read the disk on every call: they run in the lobby and in vote building, not in a hot path.

local lib = PW.MapList --[[@as PW.MapListLib]]

---@return string[]
function lib._Installed()
    return lib._NamesFromFiles(file.Find("maps/*.bsp", "GAME") or {})
end

---@return string[]
function lib.GetInstalled()
    ---@type string[]
    local list = {}
    for _, name in ipairs(lib._Installed()) do
        if not lib.IsJunk(name) then list[#list + 1] = name end
    end
    return list
end

---The ids of the enabled entries of the maps registry.
---@return table<string, true>
local function dataIds()
    ---@type table<string, true>
    local ids = {}
    local registry = rawget(PW, "Maps") --[[@as PW.Registry?]]
    if registry == nil then return ids end
    for _, entry in ipairs(registry.GetEnabledList()) do ids[entry.ClassName] = true end
    return ids
end

---@return string[]
function lib.GetList()
    return lib.Filter({
        installed = lib._Installed(),
        data = dataIds(),
        prefixes = PW.Setting("maplist.prefixes") or {},
        whitelist = PW.Setting("maplist.whitelist") or {}
    })
end

---@param mapName string
---@return boolean
function lib.IsListed(mapName)
    return table.HasValue(lib.GetList(), mapName)
end
