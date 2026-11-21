-- Lua playlist validation, startup resolution, protected availability evaluation, weighted sampling and bounded
-- authoritative UI snapshots. No playlist persistence or calendar policy lives here.
--
-- Messages (server module playlists owns them):
--   pw_playlist_request  any player, LOBBY/PREMATCH/VOTE: cached authoritative list
--   pw_playlist_pick     pw.match.start, LOBBY: playlist id ("" = Custom) -> the active playlist, answers the list
--   pw_playlist_start    pw.match.start, LOBBY: playlist id -> settings applied, next mode + map sampled, match started
--   pw_playlist_list     server -> client: PW.PlaylistListState

MODULE.Name = "Playlists"

local lib = (rawget(PW, "Playlist") or {}) --[[@as PW.PlaylistLib]]
PW.Playlist = lib

if SERVER then AddCSLuaFile("privatewar/modules/playlists/sh_content.lua") end
include("privatewar/modules/playlists/sh_content.lua")

lib.Privilege = "pw.match.start"
lib._MaxEntries = 128

local maxName = 64

---@param value any
---@return boolean
local function validDescription(value)
    return isstring(value) and #value <= 256 and not string.find(value, "%c") and not not utf8.len(value)
end

---@param text string
---@return boolean
local function validId(text)
    return string.match(text, "^[a-z0-9_]+$") ~= nil
end

---@param raw any
---@return string?
local function checkName(raw)
    if not isstring(raw) or raw == "" then return "Name must be a non-empty string" end
    local name = raw --[[@as string]]
    if #name > maxName then return "Name is longer than " .. maxName .. " characters" end
    return nil
end

---@param raw any
---@param facts PW.PlaylistFacts
---@return table<string, number>?
---@return string?
local function checkModes(raw, facts)
    if not istable(raw) or next(raw --[[@as table]]) == nil then return nil, "Modes must list at least one mode" end
    ---@type table<string, number>
    local modes = {}
    for id, weight in pairs(raw --[[@as table<any, any>]]) do
        if not isstring(id) or not validId(id --[[@as string]]) then
            return nil, "Modes: " .. tostring(id) .. " is not a mode id"
        end
        if facts.modes ~= nil and not facts.modes[id] then return nil, "Modes: unknown mode " .. id end
        if not isnumber(weight) or weight ~= weight or weight <= 0 or weight == math.huge then
            return nil, "Modes: the weight of " .. id .. " must be a number above 0"
        end
        modes[id] = weight
    end
    return modes
end

---@param name any
---@return boolean
local function validMapName(name)
    if not isstring(name) then return false end
    local text = name --[[@as string]]
    return #text > 0 and #text <= 64 and string.match(text, "^[%w_%-]+$") ~= nil
end

---@param raw any
---@return string[]?
---@return string?
local function checkMaps(raw)
    if raw == nil then return nil end
    if not istable(raw) then return nil, "Maps must be a list of map names" end
    local list = raw --[[@as table<any, any>]]
    if next(list) == nil then return nil, "Maps is empty (leave it out to use every map that fits the modes)" end
    ---@type string[]
    local maps = {}
    for index = 1, #list do
        if not validMapName(list[index]) then return nil, "Maps: entry " .. index .. " is not a map name" end
        maps[index] = list[index]
    end
    if table.Count(list) ~= #maps then return nil, "Maps must be a list of map names" end
    return maps
end

---@param fullId any
---@param value any
---@param facts PW.PlaylistFacts
---@return any
---@return string?
local function checkSetting(fullId, value, facts)
    if not isstring(fullId) or string.match(fullId --[[@as string]], "^[a-z0-9_]+%.[a-z0-9_]+$") == nil then
        return nil, "Settings: " .. tostring(fullId) .. " is not a full setting id (owner.key)"
    end
    if value == nil then return nil, "Settings: " .. fullId .. " has no value" end
    if facts.settings == nil then return value end
    local def = facts.settings[fullId]
    if def == nil then return nil, "Settings: unknown setting " .. fullId end
    if def.scope ~= "match" then return nil, "Settings: " .. fullId .. " is not a match setting" end
    if facts.validate == nil then return value end
    local ok, stored, note = facts.validate(def, value)
    if not ok then return nil, "Settings: bad value for " .. fullId .. " (" .. tostring(stored or note) .. ")" end
    return stored
end

---@param raw any
---@param facts PW.PlaylistFacts
---@return table<string, any>?
---@return string?
local function checkSettings(raw, facts)
    if raw == nil then return {} end
    if not istable(raw) then return nil, "Settings must be a table of full setting ids" end
    ---@type table<string, any>
    local settings = {}
    for fullId, value in pairs(raw --[[@as table<any, any>]]) do
        local stored, err = checkSetting(fullId, value, facts)
        if err ~= nil then return nil, err end
        settings[fullId] = stored
    end
    return settings
end

function lib.Normalize(raw, facts)
    facts = facts or {}
    if not istable(raw) then return nil, "a playlist must be a table" end
    local fields = raw --[[@as table<string, any>]]
    local nameErr = checkName(fields.Name)
    if nameErr ~= nil then return nil, nameErr end
    local description = fields.Description
    if description ~= nil then
        if not validDescription(description) then
            return nil, "Description must be plain UTF-8 text, at most 256 bytes"
        end
        description = string.Trim(description)
        if description == "" then description = nil end
    end
    local modes, modesErr = checkModes(fields.Modes, facts)
    if modes == nil then return nil, modesErr end
    local maps, mapsErr = checkMaps(fields.Maps)
    if mapsErr ~= nil then return nil, mapsErr end
    local settings, settingsErr = checkSettings(fields.Settings, facts)
    if settings == nil then return nil, settingsErr end
    return { Name = fields.Name --[[@as string]], Description = description,
        Modes = modes, Maps = maps, Settings = settings }
end

function lib.Resolve(definition, facts)
    if not istable(definition) then return nil, "a playlist must be a table" end
    local resolved = { Name = definition.Name, Description = definition.Description } --[[@as table<string, any>]]
    for _, field in ipairs({ "Modes", "Maps", "Settings" }) do
        local value = definition[field]
        if isfunction(value) then
            local ok, result = pcall(value, definition)
            if not ok then return nil, field .. " resolver failed: " .. tostring(result) end
            value = result
        end
        resolved[field] = istable(value) and table.Copy(value) or value
    end
    return lib.Normalize(resolved, facts)
end

function lib._Evaluate(definition, now)
    local predicate = definition.IsActive
    if predicate == nil then return { active = true, valid = true } end
    local ok, active, boundary = pcall(predicate, definition, now)
    if not ok or not isbool(active) then
        return { active = false, valid = false }, "IsActive failed: " .. tostring(active)
    end
    local nextChange = isnumber(boundary) and boundary == boundary and boundary < math.huge
        and boundary > now and boundary or nil
    return { active = active, valid = true, nextChange = nextChange }
end

---@param weights table<string, number>
---@return string[]
local function sortedIds(weights)
    ---@type string[]
    local ids = {}
    for id, weight in pairs(weights) do
        if isnumber(weight) and weight > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

function lib.PickWeighted(weights, rng)
    local ids = sortedIds(weights)
    if #ids == 0 then return nil end
    local total = 0
    for _, id in ipairs(ids) do total = total + weights[id] end
    local point = rng() * total
    local passed = 0
    for _, id in ipairs(ids) do
        passed = passed + weights[id]
        if point < passed then return id end
    end
    return ids[#ids]
end

---@param data PW.PlaylistData
---@param opts PW.PlaylistSampleOptions
---@param modeId string
---@return string[]
local function candidates(data, opts, modeId)
    local pool = data.Maps or opts.maps or {}
    local fits = opts.fits
    if fits == nil then return pool end
    ---@type string[]
    local list = {}
    for _, map in ipairs(pool) do
        if fits(modeId, map) then list[#list + 1] = map end
    end
    return list
end

function lib.Sample(data, opts)
    ---@type table<string, number>
    local weights = {}
    ---@type table<string, string[]>
    local maps = {}
    for modeId, weight in pairs(data.Modes) do
        local list = candidates(data, opts, modeId)
        if #list > 0 then
            weights[modeId] = weight
            maps[modeId] = list
        end
    end
    local mode = lib.PickWeighted(weights, opts.rng)
    if mode == nil then return nil, "no mode of the playlist is offered on any map" end
    local list = maps[mode]
    local index = math.min(#list, math.floor(opts.rng() * #list) + 1)
    return { mode = mode, map = list[index] }
end

---@param data PW.PlaylistData
---@return string
local function modeNames(data)
    ---@type string[]
    local ids = sortedIds(data.Modes)
    return table.concat(ids, ", ")
end

function lib._Summary(entry, fill)
    local where = entry.Maps ~= nil and (#entry.Maps .. (#entry.Maps == 1 and " map" or " maps")) or "all maps"
    return { id = entry.id, name = entry.Name,
        summary = entry.Description or string.sub(modeNames(entry) .. " on " .. where, 1, 256),
        fill = fill, active = false, valid = false }
end

-- Wire format of pw_playlist_list (DESIGN.md global rule 4: explicit writes, no net.WriteTable).
local countBits, fillBits = 8, 8

function lib._Encode(state, writer)
    writer.uint(1, 8)
    writer.uint(state.serial, 32)
    writer.number(state.sampledAt)
    local count = math.min(#state.list, lib._MaxEntries)
    writer.uint(count, countBits)
    for index = 1, count do
        local item = state.list[index]
        writer.string(item.id)
        writer.string(item.name)
        writer.string(item.summary)
        writer.uint(math.Clamp(item.fill, 0, 2 ^ fillBits - 1), fillBits)
        writer.bool(item.active)
        writer.bool(item.valid)
        writer.bool(item.nextChange ~= nil)
        if item.nextChange ~= nil then writer.number(item.nextChange) end
    end
    writer.string(state.active)
    writer.bool(state.canPick)
    writer.bool(state.retained)
    writer.bool(state.canStart)
end

function lib._Decode(reader)
    if reader.uint(8) ~= 1 then return nil end
    local serial, sampledAt = reader.uint(32), reader.number()
    if sampledAt ~= sampledAt or sampledAt == math.huge or sampledAt == -math.huge then return nil end
    local count = reader.uint(countBits)
    if count > lib._MaxEntries then return nil end
    ---@type PW.PlaylistSummary[]
    local list = {}
    ---@type table<string, boolean>
    local seen = {}
    for index = 1, count do
        local id, name, summary = reader.string(), reader.string(), reader.string()
        if #id > 64 or not validId(id) or seen[id] or #name == 0 or #name > 64
            or not validDescription(summary) then return nil end
        seen[id] = true
        local fill, active, valid = reader.uint(fillBits), reader.bool(), reader.bool()
        if active and not valid then return nil end
        local boundary = reader.bool() and reader.number() or nil
        if boundary ~= nil and (boundary ~= boundary or boundary == math.huge or boundary <= sampledAt) then
            return nil
        end
        list[index] = { id = id, name = name, summary = summary, fill = fill,
            active = active, valid = valid, nextChange = boundary }
    end
    local active = reader.string()
    if active ~= "" and not seen[active] then return nil end
    return { list = list, active = active, canPick = reader.bool(), serial = serial, sampledAt = sampledAt,
        retained = reader.bool(), canStart = reader.bool() }
end

lib.CustomRow = "@custom"

function lib._Newer(current, incoming)
    return current == nil or incoming.serial > current.serial
end

function lib._Items(state, maxPlayers)
    ---@type { id: string, label: string }[]
    local items = {}
    ---@type PW.PlaylistSummary?
    local active = nil
    for _, item in ipairs(state.list) do
        local upcoming = item.valid and not item.active and item.nextChange ~= nil
            and item.nextChange > state.sampledAt and item.nextChange - state.sampledAt <= 48 * 3600
        if item.active or item.id == state.active or upcoming then
            local timing = ""
            if item.valid and item.nextChange ~= nil then
                timing = string.format(" (%s in %dm)", item.active and "ends" or "starts",
                    math.ceil((item.nextChange - state.sampledAt) / 60))
            elseif not item.active then
                timing = " (unavailable)"
            end
            items[#items + 1] = { id = item.id, label = item.name .. " - " .. item.summary .. timing }
        end
        if item.id == state.active then active = item end
    end
    items[#items + 1] = { id = lib.CustomRow, label = "Custom (pick mode and map)" }
    ---@type PW.PlaylistItems
    local out = { items = items, selected = active ~= nil and active.id or lib.CustomRow }
    if active ~= nil then
        out.activeName = active.name
        if active.fill > maxPlayers then
            out.warning = string.format("%s expects %d players, the server has %d", active.name, active.fill,
                maxPlayers)
        end
    end
    return out
end
