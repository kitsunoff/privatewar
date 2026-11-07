-- Lobby screen v0 (T-1.19; 08-lobby.md d.3; 00-core.md d.5, d.7; 01-extensibility.md d.11, d.17). Shared and pure:
-- the checks of the Start and enable-toggle requests, the map list from a .bsp listing, the state the server sends
-- to one client and the model the screen draws. Server glue (net messages, privileges, ConVars): init.lua. The
-- screen: cl_init.lua. The client never decides anything: the server checks privilege, phase and values again.
--
-- Messages (client -> server through PW.Net.Receive; server -> client pw_lobby_state):
--   pw_lobby_request  any player, LOBBY or PREMATCH: the server answers with pw_lobby_state (PW.LobbyState); the
--                     client resends it every RetryEvery seconds while the screen is open and no state arrived
--                     (_ShouldRequest)
--   pw_lobby_start    pw.match.start, LOBBY: mode id, map -> PW.Match.Start(mode, map)
--   pw_lobby_enable   pw.entities.toggle, any phase: kind id, entity id, enabled -> the entity's enable ConVar
--                     (takes effect at the next match, 01-extensibility.md d.11)
-- The state ends with the navmesh line of the navgen module (T-2.12) when that module is valid; its Generate
-- button sends the navgen module's own message pw_navgen_start.

MODULE.Name = "Lobby"

local lib = (rawget(PW, "Lobby") or {}) --[[@as PW.LobbyLib]]
PW.Lobby = lib

lib.StartPrivilege = "pw.match.start"
lib.TogglePrivilege = "pw.entities.toggle"

-- The kinds registry describes kinds; switching a kind off is not a lobby action.
local untoggled = { kinds = true }

-- Seconds between two pw_lobby_request retries; the server accepts 4 per second (init.lua).
lib.RetryEvery = 2

function lib._ShouldRequest(open, waiting)
    return open and waiting
end

function lib._ValidMapName(name)
    return isstring(name) and #name > 0 and #name <= 64 and string.match(name, "^[%w_%-]+$") ~= nil
end

function lib._MapsFromFiles(files)
    ---@type table<string, true>
    local seen = {}
    ---@type string[]
    local maps = {}
    for _, file in ipairs(files) do
        local name = string.match(file, "^(.+)%.bsp$")
        if name ~= nil and lib._ValidMapName(name) and not seen[name] then
            seen[name] = true
            maps[#maps + 1] = name
        end
    end
    table.sort(maps)
    return maps
end

function lib._CheckStart(request, facts)
    if not isstring(request.mode) or not facts.modes[request.mode] then return false, "unknown mode" end
    if not lib._ValidMapName(request.map) then return false, "invalid map" end
    if not facts.mapExists(request.map --[[@as string]]) then return false, "no such map" end
    if facts.fits ~= nil and not facts.fits(request.mode --[[@as string]], request.map --[[@as string]]) then
        return false, "mode not offered on this map"
    end
    return true
end

function lib._NavLine(nav)
    if nav == nil then return "" end
    if nav.generating then
        return "Generating the navmesh: the game stutters and the map reloads when it is done."
    end
    if nav.result ~= "" then return nav.result end
    if nav.areas == 0 then return "No navmesh: bots and dynamic spawns unavailable." end
    return string.format("Navmesh: %d areas.", nav.areas)
end

function lib._Fits(registries)
    return function(modeId, map)
        local modes = registries.modes
        local mode = modes ~= nil and modes.Get(modeId) or nil
        local mapData = rawget(PW, "Map") --[[@as PW.MapLib?]]
        if mode == nil or mapData == nil then return mode ~= nil and mode.MapData ~= true end
        return (mapData.ModeFits(mode, map))
    end
end

function lib._CheckToggle(request, listed)
    if not isstring(request.kind) or untoggled[request.kind] then return false, "unknown kind" end
    local ids = listed[request.kind]
    if ids == nil or not isstring(request.id) or not ids[request.id] then return false, "unknown entity" end
    if not isbool(request.enabled) then return false, "enabled must be a boolean" end
    return true
end

---@param entity PW.Entity
---@return string
local function displayName(entity)
    local name = entity.Name
    if isstring(name) and name ~= "" then return name --[[@as string]] end
    return entity.ClassName
end

function lib._Toggles(registries, flagOf)
    ---@type string[]
    local kinds = {}
    for kind in pairs(registries) do
        if not untoggled[kind] then kinds[#kinds + 1] = kind end
    end
    table.sort(kinds)
    ---@type PW.LobbyToggle[]
    local toggles = {}
    for _, kind in ipairs(kinds) do
        for _, entity in ipairs(registries[kind].GetList()) do
            toggles[#toggles + 1] = { kind = kind, id = entity.ClassName, name = displayName(entity),
                enabled = flagOf(kind, entity.ClassName) }
        end
    end
    return toggles
end

function lib._BuildState(input)
    ---@type PW.LobbyMode[]
    local modes = {}
    for _, mode in ipairs(input.modes) do
        local entity = mode --[[@as PW.Entity]]
        modes[#modes + 1] = { id = entity.ClassName, name = displayName(entity), groups = input.groupsOf(mode) }
    end
    return {
        map = input.map, maps = input.maps, modes = modes,
        toggles = input.canToggle and input.toggles or {},
        canStart = input.canStart, canEdit = input.canEdit, canToggle = input.canToggle, nav = input.nav
    }
end

---@param list string[]
---@param wanted string?
---@return boolean
local function contains(list, wanted)
    for _, item in ipairs(list) do
        if item == wanted then return true end
    end
    return false
end

---@param state PW.LobbyState
---@param wanted string?
---@return PW.LobbyMode?
local function pickMode(state, wanted)
    for _, mode in ipairs(state.modes) do
        if mode.id == wanted then return mode end
    end
    return state.modes[1]
end

---@param state PW.LobbyState
---@param maps string[]
---@param wanted string?
---@return string?
local function pickMap(state, maps, wanted)
    if contains(maps, wanted) then return wanted end
    if contains(maps, state.map) then return state.map end
    return maps[1]
end

---The maps a mode is offered on (all of them without a fits test or without a mode).
---@param state PW.LobbyState
---@param modeId string?
---@param fits PW.LobbyFits?
---@return string[]
local function mapsFor(state, modeId, fits)
    if fits == nil or modeId == nil then return state.maps end
    ---@type string[]
    local list = {}
    for _, name in ipairs(state.maps) do
        if fits(modeId, name) then list[#list + 1] = name end
    end
    return list
end

lib._PickerMaps = mapsFor

function lib._Model(state, selection, fits)
    local mode = pickMode(state, selection.mode)
    local offered = mapsFor(state, mode ~= nil and mode.id or nil, fits)
    local map = pickMap(state, offered, selection.map)
    ---@type PW.UIFormSection[]
    local sections = {}
    local kit = rawget(PW, "UI") --[[@as PW.UILib?]]
    if mode ~= nil and kit ~= nil then sections = kit.BuildForm(mode.groups, { [mode.id] = mode.name }) end
    ---@type { id: string, label: string }[]
    local modes = {}
    ---@type { id: string, label: string }[]
    local maps = {}
    for index, entry in ipairs(state.modes) do modes[index] = { id = entry.id, label = entry.name } end
    for index, name in ipairs(offered) do maps[index] = { id = name, label = name } end
    return {
        modes = modes, maps = maps, mode = mode ~= nil and mode.id or nil, map = map, sections = sections,
        toggles = state.toggles, canEdit = state.canEdit, canToggle = state.canToggle, nav = state.nav,
        canStart = state.canStart and mode ~= nil and map ~= nil
    }
end

-- Wire format of pw_lobby_state (DESIGN.md global rule 4: explicit writes, no net.WriteTable). Bits of the counts:
local mapBits, modeBits, fieldBits, toggleBits, areaBits = 12, 8, 10, 12, 24

---@param count integer
---@param bits integer
---@return integer
local function capped(count, bits)
    return math.min(count, 2 ^ bits - 1)
end

---@param mode PW.LobbyMode
---@return PW.SettingField[]
local function fieldsOf(mode)
    ---@type PW.SettingField[]
    local fields = {}
    for _, group in ipairs(mode.groups) do
        for _, field in ipairs(group.fields) do fields[#fields + 1] = field end
    end
    return fields
end

---@param mode PW.LobbyMode
---@param writer PW.LobbyWriter
local function encodeMode(mode, writer)
    local fields = fieldsOf(mode)
    local count = capped(#fields, fieldBits)
    writer.string(mode.id)
    writer.uint(count, fieldBits)
    for index = 1, count do
        local def = fields[index].def
        writer.string(def.id)
        writer.string(PW.Settings.Format(def, fields[index].value) or "")
    end
end

function lib._Encode(state, writer)
    writer.string(state.map)
    local mapCount = capped(#state.maps, mapBits)
    writer.uint(mapCount, mapBits)
    for index = 1, mapCount do writer.string(state.maps[index]) end
    local modeCount = capped(#state.modes, modeBits)
    writer.uint(modeCount, modeBits)
    for index = 1, modeCount do encodeMode(state.modes[index], writer) end
    writer.bool(state.canStart)
    writer.bool(state.canEdit)
    writer.bool(state.canToggle)
    local toggleCount = capped(#state.toggles, toggleBits)
    writer.uint(toggleCount, toggleBits)
    for index = 1, toggleCount do
        local toggle = state.toggles[index]
        writer.string(toggle.kind)
        writer.string(toggle.id)
        writer.bool(toggle.enabled)
    end
    local nav = state.nav
    writer.bool(nav ~= nil)
    if nav == nil then return end
    writer.uint(capped(nav.areas, areaBits), areaBits)
    writer.bool(nav.generating)
    writer.bool(nav.canGenerate)
    writer.bool(nav.fastDefault)
    writer.string(nav.result)
end

function lib._ParseText(def, text)
    local kind = def.type
    if kind == "int" or kind == "float" then return tonumber(text) end
    if kind == "bool" then return text == "1" end
    if kind == "enum" then return text end
    ---@type table<string, true>
    local set = {}
    for _, part in ipairs(string.Explode(",", text)) do
        if part ~= "" then set[part] = true end
    end
    return set
end

---Sets the sent values on the groups; a module group without any sent value is dropped (disabled on the server).
---@param groups PW.SettingGroup[]
---@param values table<string, string>
---@return PW.SettingGroup[]
local function applyValues(groups, values)
    ---@type PW.SettingGroup[]
    local kept = {}
    for _, group in ipairs(groups) do
        local sent = false
        for _, field in ipairs(group.fields) do
            local text = values[field.def.id]
            if text ~= nil then
                sent = true
                field.value = lib._ParseText(field.def, text)
            end
        end
        if sent or group.ownerKind == "modes" then kept[#kept + 1] = group end
    end
    return kept
end

---Reads one mode; every field is read even when the mode is unknown here, so the stream stays aligned.
---@param reader PW.LobbyReader
---@param resolver PW.LobbyResolver
---@return PW.LobbyMode?
local function decodeMode(reader, resolver)
    local id = reader.string()
    ---@type table<string, string>
    local values = {}
    for _ = 1, reader.uint(fieldBits) do
        local fullId = reader.string()
        values[fullId] = reader.string()
    end
    local groups = resolver.groupsOf(id)
    if groups == nil then return nil end
    return { id = id, name = resolver.nameOf("modes", id), groups = applyValues(groups, values) }
end

function lib._Resolver(registries)
    return {
        groupsOf = function(modeId)
            local modes = registries.modes
            local mode = modes ~= nil and modes.Get(modeId) or nil
            if mode == nil then return nil end
            return PW.Settings.GetGroups("match", mode)
        end,
        nameOf = function(kind, id)
            local registry = registries[kind]
            local entity = registry ~= nil and registry.Get(id) or nil
            if entity == nil then return id end
            return displayName(entity)
        end
    }
end

function lib._Decode(reader, resolver)
    local map = reader.string()
    ---@type string[]
    local maps = {}
    for index = 1, reader.uint(mapBits) do maps[index] = reader.string() end
    ---@type PW.LobbyMode[]
    local modes = {}
    for _ = 1, reader.uint(modeBits) do
        local mode = decodeMode(reader, resolver)
        if mode ~= nil then modes[#modes + 1] = mode end
    end
    local canStart, canEdit, canToggle = reader.bool(), reader.bool(), reader.bool()
    ---@type PW.LobbyToggle[]
    local toggles = {}
    for index = 1, reader.uint(toggleBits) do
        local kind, id = reader.string(), reader.string()
        toggles[index] = { kind = kind, id = id, name = resolver.nameOf(kind, id), enabled = reader.bool() }
    end
    ---@type PW.LobbyNav?
    local nav = nil
    if reader.bool() then
        nav = { areas = reader.uint(areaBits), generating = reader.bool(), canGenerate = reader.bool(),
            fastDefault = reader.bool(), result = reader.string() }
    end
    return {
        map = map, maps = maps, modes = modes, toggles = toggles,
        canStart = canStart, canEdit = canEdit, canToggle = canToggle, nav = nav
    }
end

-- Hub and custom game models (U-5), the map picker model (U-6) and the match flow rules (sh_flow.lua): separate
-- shared files (the loader runs shared.lua only).
if SERVER then
    AddCSLuaFile("privatewar/modules/lobby_ui/sh_entry.lua")
    AddCSLuaFile("privatewar/modules/lobby_ui/sh_hub.lua")
    AddCSLuaFile("privatewar/modules/lobby_ui/sh_picker.lua")
    AddCSLuaFile("privatewar/modules/lobby_ui/sh_flow.lua")
end
include("privatewar/modules/lobby_ui/sh_entry.lua")
include("privatewar/modules/lobby_ui/sh_hub.lua")
include("privatewar/modules/lobby_ui/sh_picker.lua")
include("privatewar/modules/lobby_ui/sh_flow.lua")
