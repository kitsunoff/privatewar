-- Progression, pure part 3 (T-4.10; 06-progression.md d.5): storage and transfer. Everything lives on the client in
-- data/privatewar/progression.json; the server sanity-checks the upload, sends 10 s deltas, the levels a client needs
-- for its own unlock checks and the postmatch summary. Plain data in, plain data out: the sanity checks, the delta
-- apply (additive, idempotent per batch id), the file shape and the explicit wire encoding (never net.WriteTable,
-- DESIGN.md global rule 4) over an injected writer and reader. Loaded by shared.lua.
--
-- File (JSON): { "v": 2, "xp": <total>, "weapons": { "<class>": <total> }, "currency": <total>, "owned": [ "<key>" ],
-- "batch": { "session": n, "seq": n } }. batch is the last delta applied: a delta with the same session and a seq not
-- above it is a duplicate. T-4.12 added v 2 (currency, owned: sh_wallet.lua); a v1 file loads with 0 currency.
--
-- Wire (bits): upload xp u32, count u16, count x (class string, xp u32), currency u32, owned (sh_wallet.lua); delta
-- session u32, seq u32, xp u32, count u16, count x (class, xp u32), earned u32, spent u32, owned; levels level u16,
-- unlockAll bool, maxAttachments u8, count u16, count x (class, level u16); summary xp u32, levelBefore u16,
-- levelAfter u16, count u16, count x (class, before u16, after u16), medals u8,
-- medals x (id string, count u16). Counts are capped at MaxWeapons (MaxMedals for medals) on both sides.

local lib = PW.Progression --[[@as PW.ProgressionLib]]

lib.FileVersion = 2
lib.FilePath = "privatewar/progression.json"
lib.FlushInterval = 10
lib.MaxXP = 1000000000
lib.MaxDeltaXP = 10000000
lib.MaxWeapons = 256
lib.MaxClassLength = 64
lib.MaxMedals = 64
lib.UploadMaxBytes = 4 + 2 + lib.MaxWeapons * (lib.MaxClassLength + 1 + 4)
    + 4 + 2 + lib.MaxOwned * (lib.MaxKeyLength + 1)

local maxU32 = 2 ^ 32 - 1

function lib._CheckXP(value, limit)
    if not isnumber(value) then return nil end
    local number = value --[[@as number]]
    if number ~= number or number < 0 or number > limit then return nil end
    return math.floor(number)
end

---@param class any
---@return boolean
local function validClass(class)
    return isstring(class) and #class > 0 and #class <= lib.MaxClassLength
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

---The checked entries of a weapons table: valid class names, XP above 0 and within limit.
---@param raw any
---@param limit number
---@return { class: string, xp: integer }[]
local function checkedWeapons(raw, limit)
    ---@type { class: string, xp: integer }[]
    local kept = {}
    if not istable(raw) then return kept end
    for class, value in pairs(raw --[[@as table<any, any>]]) do
        local xp = lib._CheckXP(value, limit)
        if validClass(class) and xp ~= nil and xp > 0 then kept[#kept + 1] = { class = class, xp = xp } end
    end
    return kept
end

function lib._CheckState(raw, maxWeapons)
    local source = istable(raw) and raw --[[@as table<string, any>]] or {}
    local kept = checkedWeapons(source.weapons, lib.MaxXP)
    if maxWeapons ~= nil and #kept > maxWeapons then
        table.sort(kept, function(a, b)
            if a.xp ~= b.xp then return a.xp > b.xp end
            return a.class < b.class
        end)
        for index = #kept, maxWeapons + 1, -1 do kept[index] = nil end
    end
    ---@type table<string, number>
    local weapons = {}
    for _, entry in ipairs(kept) do weapons[entry.class] = entry.xp end
    return {
        xp = lib._CheckXP(source.xp, lib.MaxXP) or 0, weapons = weapons,
        currency = lib._CheckXP(source.currency, lib.MaxCurrency) or 0,
        owned = lib._CheckOwned(source.owned, lib.MaxOwned)
    }
end

function lib._ApplyDelta(current, delta)
    local batch = current.batch
    if delta.session == batch.session and delta.seq <= batch.seq then return current, false end
    ---@type table<string, number>
    local weapons = {}
    for class, xp in pairs(current.weapons) do weapons[class] = xp end
    for _, entry in ipairs(checkedWeapons(delta.weapons, lib.MaxDeltaXP)) do
        weapons[entry.class] = (weapons[entry.class] or 0) + entry.xp
    end
    local xp = current.xp + (lib._CheckXP(delta.xp, lib.MaxDeltaXP) or 0)
    return {
        v = lib.FileVersion, xp = xp, weapons = weapons, batch = { session = delta.session, seq = delta.seq },
        currency = lib._CurrencyAfter(current.currency, delta.earned, delta.spent),
        owned = lib._MergeOwned(current.owned or {}, lib._CheckOwned(delta.owned, lib.MaxOwned))
    }, true
end

function lib._FileFromJson(decoded)
    local source = istable(decoded) and decoded --[[@as table<string, any>]] or {}
    local state = lib._CheckState(source)
    local batch = istable(source.batch) and source.batch --[[@as table<string, any>]] or {}
    return {
        v = lib.FileVersion, xp = state.xp, weapons = state.weapons, currency = state.currency, owned = state.owned,
        batch = { session = lib._CheckXP(batch.session, maxU32) or 0, seq = lib._CheckXP(batch.seq, maxU32) or 0 }
    }
end

function lib._FileToJson(stored)
    ---@type table<string, number>
    local weapons = {}
    for class, xp in pairs(stored.weapons) do weapons[class] = xp end
    return {
        v = lib.FileVersion, xp = stored.xp, weapons = weapons, currency = stored.currency or 0,
        owned = lib._SortedOwned(stored.owned or {}),
        batch = { session = stored.batch.session, seq = stored.batch.seq }
    }
end

function lib._ViewFromLevels(levels, lookup, owned)
    return {
        level = levels.level,
        weaponLevel = function(weaponId) return levels.weapons[weaponId] or 1 end,
        lookup = lookup, unlockAll = levels.unlockAll, maxAttachments = levels.maxAttachments, owned = owned
    }
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

---@param writer PW.ProgressionWriter
---@param value number
---@param width integer
local function writeUInt(writer, value, width)
    writer.uint(math.Clamp(math.floor(value), 0, 2 ^ width - 1), width)
end

---Writes a class -> number table: count u16, then (class, value) in class order, capped at MaxWeapons.
---@param writer PW.ProgressionWriter
---@param values table<string, number>
---@param width integer
local function writeMap(writer, values, width)
    local keys = sortedKeys(values)
    local count = math.min(#keys, lib.MaxWeapons)
    writer.uint(count, 16)
    for index = 1, count do
        writer.string(keys[index])
        writeUInt(writer, values[keys[index]], width)
    end
end

---@param reader PW.ProgressionReader
---@param width integer
---@return table<string, number>
local function readMap(reader, width)
    ---@type table<string, number>
    local values = {}
    local count = reader.uint(16)
    if count > lib.MaxWeapons then return values end
    for _ = 1, count do
        local class = reader.string()
        values[class] = reader.uint(width)
    end
    return values
end

function lib._EncodeState(state, writer)
    writeUInt(writer, state.xp, 32)
    writeMap(writer, state.weapons, 32)
    writeUInt(writer, state.currency or 0, 32)
    lib._WriteOwned(writer, state.owned or {})
end

function lib._DecodeState(reader)
    local xp = reader.uint(32)
    local weapons = readMap(reader, 32)
    local currency = lib._CheckXP(reader.uint(32), lib.MaxCurrency) or 0
    return { xp = xp, weapons = weapons, currency = currency, owned = lib._ReadOwned(reader) }
end

function lib._EncodeDelta(delta, writer)
    writeUInt(writer, delta.session, 32)
    writeUInt(writer, delta.seq, 32)
    writeUInt(writer, delta.xp, 32)
    writeMap(writer, delta.weapons, 32)
    writeUInt(writer, delta.earned or 0, 32)
    writeUInt(writer, delta.spent or 0, 32)
    lib._WriteOwned(writer, delta.owned or {})
end

function lib._DecodeDelta(reader)
    local session = reader.uint(32)
    local seq = reader.uint(32)
    local xp = reader.uint(32)
    local weapons = readMap(reader, 32)
    local earned, spent = reader.uint(32), reader.uint(32)
    return { session = session, seq = seq, xp = xp, weapons = weapons, earned = earned, spent = spent,
        owned = lib._ReadOwned(reader) }
end

function lib._EncodeLevels(levels, writer)
    writeUInt(writer, levels.level, 16)
    writer.bool(levels.unlockAll)
    writeUInt(writer, levels.maxAttachments, 8)
    writeMap(writer, levels.weapons, 16)
end

function lib._DecodeLevels(reader)
    local level = reader.uint(16)
    local unlockAll = reader.bool()
    local maxAttachments = reader.uint(8)
    return { level = level, unlockAll = unlockAll, maxAttachments = maxAttachments, weapons = readMap(reader, 16) }
end

function lib._EncodeSummary(summary, writer)
    writeUInt(writer, summary.xp, 32)
    writeUInt(writer, summary.levelBefore, 16)
    writeUInt(writer, summary.levelAfter, 16)
    local weapons = math.min(#summary.weapons, lib.MaxWeapons)
    writer.uint(weapons, 16)
    for index = 1, weapons do
        local entry = summary.weapons[index]
        writer.string(entry.class)
        writeUInt(writer, entry.before, 16)
        writeUInt(writer, entry.after, 16)
    end
    local medals = math.min(#summary.medals, lib.MaxMedals)
    writer.uint(medals, 8)
    for index = 1, medals do
        writer.string(summary.medals[index].id)
        writeUInt(writer, summary.medals[index].count, 16)
    end
end

function lib._DecodeSummary(reader)
    ---@type PW.ProgressionSummary
    local summary = { xp = reader.uint(32), levelBefore = reader.uint(16), levelAfter = reader.uint(16),
        weapons = {}, medals = {} }
    local weapons = reader.uint(16)
    for index = 1, math.min(weapons, lib.MaxWeapons) do
        summary.weapons[index] = { class = reader.string(), before = reader.uint(16), after = reader.uint(16) }
    end
    local medals = reader.uint(8)
    for index = 1, math.min(medals, lib.MaxMedals) do
        summary.medals[index] = { id = reader.string(), count = reader.uint(16) }
    end
    return summary
end
