-- Progression, pure part 4 (T-4.12; 06-progression.md d.6): the wallet. The meta currency and the purchases are part of
-- the progression state and of the same client file and deltas as XP: { currency = <total>, owned = { ["<kind>:<id>"]
-- = true } }. Plain data in, plain data out. Loaded by shared.lua before sh_storage.lua.
--
-- An owned key is "<kind>:<id>" (a camo is "camos:<weapon>:<option>"). The checks keep the shape sane against a hand-
-- edited file or a forged upload (forgery itself is accepted, 06 d.0): keys are well formed and short, at most MaxOwned
-- of them (the first ones in key order), the currency is a whole number in 0..MaxCurrency (anything else is 0).
-- Wire (bits): owned count u16, count x key string; capped at MaxOwned on both sides.

local lib = PW.Progression --[[@as PW.ProgressionLib]]

lib.MaxCurrency = 1000000000
lib.MaxDeltaCurrency = 10000000
lib.MaxOwned = 256
lib.MaxKeyLength = 96

function lib._OwnedKey(kind, id)
    return kind .. ":" .. id
end

---@param key any
---@return boolean
local function validKey(key)
    return isstring(key) and #key <= lib.MaxKeyLength and string.match(key, "^%l[%l_]*:[%w_%-%.:]+$") ~= nil
end

function lib._SortedOwned(owned)
    ---@type string[]
    local keys = {}
    for key in pairs(owned) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

---The candidate keys of a raw value: a list of strings (the file and wire shape) or a key -> true map.
---@param raw any
---@return string[]
local function candidates(raw)
    ---@type string[]
    local found = {}
    if not istable(raw) then return found end
    for key, value in pairs(raw --[[@as table<any, any>]]) do
        if isstring(key) and value == true then
            found[#found + 1] = key
        elseif isnumber(key) and isstring(value) then
            found[#found + 1] = value
        end
    end
    return found
end

function lib._CheckOwned(raw, limit)
    ---@type string[]
    local keys = {}
    for _, key in ipairs(candidates(raw)) do
        if validKey(key) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    ---@type table<string, boolean>
    local owned = {}
    for index = 1, math.min(#keys, limit) do owned[keys[index]] = true end
    return owned
end

function lib._MergeOwned(current, added)
    ---@type table<string, boolean>
    local merged = {}
    for key in pairs(current) do merged[key] = true end
    for key in pairs(added) do merged[key] = true end
    return lib._CheckOwned(merged, lib.MaxOwned)
end

function lib._CurrencyAfter(current, earned, spent)
    local gained = lib._CheckXP(earned, lib.MaxDeltaCurrency) or 0
    local used = lib._CheckXP(spent, lib.MaxDeltaCurrency) or 0
    return math.Clamp((current or 0) + gained - used, 0, lib.MaxCurrency)
end

function lib._WriteOwned(writer, owned)
    local keys = lib._SortedOwned(owned)
    local count = math.min(#keys, lib.MaxOwned)
    writer.uint(count, 16)
    for index = 1, count do writer.string(keys[index]) end
end

function lib._ReadOwned(reader)
    local count = reader.uint(16)
    if count > lib.MaxOwned then return {} end
    ---@type string[]
    local keys = {}
    for _ = 1, count do keys[#keys + 1] = reader.string() end
    return lib._CheckOwned(keys, lib.MaxOwned)
end
