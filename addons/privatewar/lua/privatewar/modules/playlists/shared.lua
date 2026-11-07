-- Playlists module (T-2.6; 02-modes.md d.1-d.5b; 08-lobby.md d.2; docs/api/modes.md "Playlists"). Shared and pure:
-- the one validation of a playlist (Lua file or host-saved JSON), the JSON form, the weighted sampling of the next
-- mode and map over an injected RNG, and the wire form of the list the lobby shows. Server glue (registry, files,
-- messages, starting the match): init.lua. Client state: cl_init.lua.
--
-- Messages (server module playlists owns them):
--   pw_playlist_request  any player, LOBBY: the server answers with pw_playlist_list
--   pw_playlist_pick     pw.match.start, LOBBY: playlist id ("" = Custom) -> the active playlist, answers the list
--   pw_playlist_start    pw.match.start, LOBBY: playlist id -> settings applied, next mode + map sampled, match started
--   pw_playlist_list     server -> client: PW.PlaylistListState

MODULE.Name = "Playlists"

local lib = (rawget(PW, "Playlist") or {}) --[[@as PW.PlaylistLib]]
PW.Playlist = lib

lib.Version = 1
lib.DataDir = "privatewar/playlists"
lib.Privilege = "pw.match.start"

local maxName = 64
local allowedFields = { Name = true, Modes = true, Maps = true, Settings = true }

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
    local modes, modesErr = checkModes(fields.Modes, facts)
    if modes == nil then return nil, modesErr end
    local maps, mapsErr = checkMaps(fields.Maps)
    if mapsErr ~= nil then return nil, mapsErr end
    local settings, settingsErr = checkSettings(fields.Settings, facts)
    if settings == nil then return nil, settingsErr end
    return { Name = fields.Name --[[@as string]], Modes = modes, Maps = maps, Settings = settings }
end

function lib.FromJson(text, facts)
    if not isstring(text) or string.Trim(text --[[@as string]]) == "" then
        return nil, "invalid JSON: the text is empty"
    end
    local parsed = util.JSONToTable(text --[[@as string]])
    if parsed == nil then return nil, "invalid JSON: the text could not be parsed" end
    local raw = parsed --[[@as table<any, any>]]
    if not istable(raw) or (raw[1] ~= nil and raw.Name == nil) then
        return nil, "invalid JSON: a playlist is an object with Name, Modes, Maps and Settings"
    end
    if raw.Version ~= nil and raw.Version ~= lib.Version then
        return nil, "unsupported playlist Version " .. tostring(raw.Version) .. " (expected " .. lib.Version .. ")"
    end
    for key in pairs(raw) do
        if key ~= "Version" and not allowedFields[key] then return nil, "unknown field " .. tostring(key) end
    end
    return lib.Normalize(raw, facts)
end

function lib.ToJson(data)
    return util.TableToJSON({ Version = lib.Version, Name = data.Name, Modes = data.Modes, Maps = data.Maps,
        Settings = data.Settings }, true)
end

function lib.FileId(fileName)
    if not isstring(fileName) then return nil end
    local id = string.match(fileName --[[@as string]], "^(.+)%.json$")
    if id == nil or #id > 64 or not validId(id) then return nil end
    return id
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
    return { id = entry.id, name = entry.Name, summary = modeNames(entry) .. " on " .. where, fill = fill }
end

-- Wire format of pw_playlist_list (DESIGN.md global rule 4: explicit writes, no net.WriteTable).
local countBits, fillBits = 8, 8

function lib._Encode(state, writer)
    local count = math.min(#state.list, 2 ^ countBits - 1)
    writer.uint(count, countBits)
    for index = 1, count do
        local item = state.list[index]
        writer.string(item.id)
        writer.string(item.name)
        writer.string(item.summary)
        writer.uint(math.Clamp(item.fill, 0, 2 ^ fillBits - 1), fillBits)
    end
    writer.string(state.active)
    writer.bool(state.canPick)
end

function lib._Decode(reader)
    ---@type PW.PlaylistSummary[]
    local list = {}
    for index = 1, reader.uint(countBits) do
        local id, name, summary = reader.string(), reader.string(), reader.string()
        list[index] = { id = id, name = name, summary = summary, fill = reader.uint(fillBits) }
    end
    local active = reader.string()
    return { list = list, active = active, canPick = reader.bool() }
end

lib.CustomRow = "@custom"

function lib._Items(state, maxPlayers)
    ---@type { id: string, label: string }[]
    local items = { { id = lib.CustomRow, label = "Custom (pick mode and map)" } }
    ---@type PW.PlaylistSummary?
    local active = nil
    for _, item in ipairs(state.list) do
        items[#items + 1] = { id = item.id, label = item.name .. " - " .. item.summary }
        if item.id == state.active then active = item end
    end
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
