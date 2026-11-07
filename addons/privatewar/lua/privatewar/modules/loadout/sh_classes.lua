-- Classes, pure part (T-4.7; 05-loadout.md d.12, d.13). Plain data in, plain data out: the wire format of a class
-- upload and of the state the server answers, the classes.json shape check, the repair against the catalogue and
-- the match settings, availability, and the card model of the class list. Loaded by shared.lua through include.
--
-- Wire (explicit, never net.WriteTable; DESIGN.md global rule 4). A loadout:
--   uint(4) slot count, per slot: string slot id, uint(3) item count, the item ids (strings);
--   uint(3) build count, per build: string slot id, uint(5) option count, per option: string build slot,
--   bool "has option", string option id when it has one (false = cleared).
-- An upload: uint(5) class count, per class: string name, loadout. Every count is bounded by its bit width, so a
-- forged message cannot make the reader loop; the payload is also bounded by maxLen (ClassesMaxBytes).
--
-- Decisions of the lane agent (05 d.12 leaves the split open):
--   1. Repair removes what is wrong whatever the budget: unknown slot, unknown or disabled item, wrong filter, too
--      many items, banned weapon, banned or hidden attachment (the build of a removed weapon goes with it).
--   2. Budget and attachment cap only mark the class unavailable (05 d.12: "marked unavailable, not silently
--      trimmed"); the uploaded class is kept as sent and repaired again under each match's settings.
--   3. A class with nothing left is unavailable ("the class is empty").
--   4. Attachments (T-4.8, 05 d.15): an option the adapter does not offer, a locked one, one ADAPTER:Validate
--      rejects and one over the progression count limit are removed with their reason (sh_gunsmith.lua).

local lib = PW.Loadout --[[@as PW.LoadoutLib]]

local buildsKey = "builds"
local bits = { classes = 5, slots = 4, items = 3, builds = 3, options = 5, removed = 5, entries = 6 }

lib.ClassesMaxBytes = 16384
lib.ClassNameMax = 32

---@param count integer
---@param width integer
---@return integer
local function capped(count, width)
    return math.min(count, 2 ^ width - 1)
end

---@param tbl table<string, any>
---@return string[]
local function sortedKeys(tbl)
    ---@type string[]
    local keys = {}
    for key in pairs(tbl) do
        if isstring(key) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

-- Wire ---------------------------------------------------------------------------------------------------------------

function lib._NetWriter()
    return {
        uint = function(value, width) net.WriteUInt(value, width) end,
        string = function(value) net.WriteString(value) end,
        bool = function(value) net.WriteBool(value) end
    }
end

function lib._NetReader()
    return {
        uint = function(width) return net.ReadUInt(width) end,
        string = function() return net.ReadString() end,
        bool = function() return net.ReadBool() end
    }
end

---@param build table<string, string|false>
---@param writer PW.LoadoutWriter
local function encodeBuild(build, writer)
    local keys = sortedKeys(build)
    local count = capped(#keys, bits.options)
    writer.uint(count, bits.options)
    for index = 1, count do
        local option = build[keys[index]]
        writer.string(keys[index])
        writer.bool(isstring(option))
        if isstring(option) then writer.string(option --[[@as string]]) end
    end
end

---@param loadout PW.Loadout
---@param writer PW.LoadoutWriter
local function encodeLoadout(loadout, writer)
    ---@type string[]
    local slotIds = {}
    for _, key in ipairs(sortedKeys(loadout)) do
        if key ~= buildsKey and lib._Items(loadout[key]) ~= nil then slotIds[#slotIds + 1] = key end
    end
    local count = capped(#slotIds, bits.slots)
    writer.uint(count, bits.slots)
    for index = 1, count do
        local items = lib._Items(loadout[slotIds[index]]) --[[@as string[] ]]
        writer.string(slotIds[index])
        local itemCount = capped(#items, bits.items)
        writer.uint(itemCount, bits.items)
        for item = 1, itemCount do writer.string(items[item]) end
    end
    local builds = loadout[buildsKey]
    local buildIds = istable(builds) and sortedKeys(builds --[[@as table<string, any>]]) or {}
    local buildCount = capped(#buildIds, bits.builds)
    writer.uint(buildCount, bits.builds)
    for index = 1, buildCount do
        writer.string(buildIds[index])
        local build = (builds --[[@as table<string, any>]])[buildIds[index]]
        encodeBuild(istable(build) and build or {}, writer)
    end
end

---@param reader PW.LoadoutReader
---@return PW.Loadout
local function decodeLoadout(reader)
    ---@type PW.Loadout
    local loadout = {}
    for _ = 1, reader.uint(bits.slots) do
        local slotId = reader.string()
        ---@type string[]
        local items = {}
        for index = 1, reader.uint(bits.items) do items[index] = reader.string() end
        if slotId ~= "" and slotId ~= buildsKey and #items > 0 then
            loadout[slotId] = #items == 1 and items[1] or items
        end
    end
    ---@type table<string, table<string, string|false>>
    local builds = {}
    for _ = 1, reader.uint(bits.builds) do
        local slotId = reader.string()
        ---@type table<string, string|false>
        local build = {}
        for _ = 1, reader.uint(bits.options) do
            local buildSlot = reader.string()
            local option = reader.bool() and reader.string() or false
            if buildSlot ~= "" then build[buildSlot] = option end
        end
        if slotId ~= "" and next(build) ~= nil then builds[slotId] = build end
    end
    if next(builds) ~= nil then loadout[buildsKey] = builds end
    return loadout
end

function lib._EncodeClasses(classes, writer)
    local count = capped(#classes, bits.classes)
    writer.uint(count, bits.classes)
    for index = 1, count do
        writer.string(string.sub(classes[index].name, 1, lib.ClassNameMax))
        encodeLoadout(classes[index].loadout, writer)
    end
end

function lib._DecodeClasses(reader, max)
    ---@type PW.LoadoutClass[]
    local classes = {}
    for _ = 1, reader.uint(bits.classes) do
        local name = string.sub(reader.string(), 1, lib.ClassNameMax)
        local loadout = decodeLoadout(reader)
        if #classes < max then classes[#classes + 1] = { name = name, loadout = loadout } end
    end
    return classes
end

---@param entry PW.LoadoutClassEntry
---@param writer PW.LoadoutWriter
local function encodeEntry(entry, writer)
    writer.string(entry.ref)
    writer.string(entry.name)
    writer.bool(entry.available)
    writer.string(entry.reason or "")
    local removed = capped(#entry.removed, bits.removed)
    writer.uint(removed, bits.removed)
    for index = 1, removed do writer.string(entry.removed[index]) end
    encodeLoadout(entry.loadout, writer)
end

function lib._EncodeClassState(state, writer)
    writer.string(state.selected)
    local count = capped(#state.entries, bits.entries)
    writer.uint(count, bits.entries)
    for index = 1, count do encodeEntry(state.entries[index], writer) end
end

function lib._DecodeClassState(reader)
    local selected = reader.string()
    ---@type PW.LoadoutClassEntry[]
    local entries = {}
    for index = 1, reader.uint(bits.entries) do
        local ref, name, available, reason = reader.string(), reader.string(), reader.bool(), reader.string()
        ---@type string[]
        local removed = {}
        for item = 1, reader.uint(bits.removed) do removed[item] = reader.string() end
        entries[index] = {
            ref = ref, name = name, available = available, reason = reason ~= "" and reason or nil,
            removed = removed, loadout = decodeLoadout(reader)
        }
    end
    return { selected = selected, entries = entries }
end

-- classes.json -------------------------------------------------------------------------------------------------------

---util.JSONToTable turns digit-only object keys ("2", "3": ARC9 and MW Base attachment slots) into numbers; the
---loadout structure is keyed by strings, so give every key back as a string.
---@param tbl any
---@return table<string, any>
local function stringKeyed(tbl)
    ---@type table<string, any>
    local copy = {}
    if not istable(tbl) then return copy end
    for key, value in pairs(tbl --[[@as table<any, any>]]) do copy[tostring(key)] = value end
    return copy
end

---Only the structure the wire can carry: slot -> id or list of ids, builds -> slot -> build slot -> id or false.
---@param raw any
---@return PW.Loadout
local function sanitize(raw)
    ---@type PW.Loadout
    local loadout = {}
    if not istable(raw) then return loadout end
    local source = stringKeyed(raw)
    for _, key in ipairs(sortedKeys(source)) do
        local items = key ~= buildsKey and lib._Items(source[key]) or nil
        if items ~= nil then loadout[key] = #items == 1 and items[1] or items end
    end
    if not istable(source[buildsKey]) then return loadout end
    local builds = stringKeyed(source[buildsKey])
    ---@type table<string, table<string, string|false>>
    local clean = {}
    for _, slotId in ipairs(sortedKeys(builds)) do
        local build = stringKeyed(builds[slotId])
        ---@type table<string, string|false>
        local kept = {}
        for _, buildSlot in ipairs(sortedKeys(build)) do
            local option = build[buildSlot]
            if isstring(option) or option == false then kept[buildSlot] = option --[[@as string|false]] end
        end
        if next(kept) ~= nil then clean[slotId] = kept end
    end
    if next(clean) ~= nil then loadout[buildsKey] = clean end
    return loadout
end

function lib._ClassesFromJson(data, max)
    ---@type PW.LoadoutClass[]
    local classes = {}
    local list = istable(data) and (data --[[@as table<string, any>]]).classes or nil
    if not istable(list) then return classes end
    for _, raw in ipairs(list --[[@as any[] ]]) do
        if #classes >= max then break end
        local loadout = istable(raw) and sanitize((raw --[[@as table<string, any>]]).loadout) or {}
        if next(loadout) ~= nil then
            local name = (raw --[[@as table<string, any>]]).name
            local text = isstring(name) and name ~= "" and name --[[@as string]] or ("Class " .. (#classes + 1))
            classes[#classes + 1] = { name = string.sub(text, 1, lib.ClassNameMax), loadout = loadout }
        end
    end
    return classes
end
