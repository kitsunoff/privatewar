-- Progression, pure part 2 (T-4.9; 06-progression.md d.1, d.2): unlock rules over a view of one player. Plain data
-- in, plain data out; the view (levels, catalogue lookup, switches) is injected, so the tests need no engine.
--
-- Rules:
--   1. An entity (weapons, perks, equipment, streaks, wildcards: any kind with a registry) is unlocked when the player
--      level reaches its Unlock (an integer, or { level = N }). No Unlock means unlocked from the start: a pack
--      works without markup (a lane agent decision).
--   2. A curated attachment (Attachments[option].Unlock) or camo (Camos[id].Unlock) is unlocked by the WEAPON level.
--      Hidden is never offered, not even with unlockall.
--   3. An attachment without a curated Unlock is unlocked by count: the weapon level is the number of such
--      attachments a build may hold (level 1 allows 1), capped by loadout.maxattachments. Cosmetic options (a
--      Cosmetic flag or listed in Camos) are not counted.
--   4. unlockall opens rules 1 to 3 (the count limit becomes the cap); Hidden stays hidden.
--   5. (T-4.12, 06 d.6) A purchased item is unlocked ("<kind>:<id>" owned, view.owned); Hidden options stay hidden. An
--      entity with a Price and no Unlock is for sale only: locked until bought. Both apply only while view.owned is
--      set (the economy module is active); without it prices are ignored and rule 1 stands.
-- Loaded by shared.lua.

local lib = PW.Progression --[[@as PW.ProgressionLib]]

---The level an Unlock field asks for: an integer, { level = N } or nothing (0).
---@param unlock any
---@return number
local function required(unlock)
    if isnumber(unlock) then return unlock --[[@as number]] end
    if istable(unlock) then
        local level = (unlock --[[@as table<string, any>]]).level
        if isnumber(level) then return level --[[@as number]] end
    end
    return 0
end

---The curated entry of an option, or an empty table.
---@param weapon table<string, any>
---@param field "Attachments"|"Camos"
---@param option string
---@return table<string, any>
local function entryOf(weapon, field, option)
    local entries = weapon[field]
    if not istable(entries) then return {} end
    local entry = (entries --[[@as table<string, any>]])[option]
    if istable(entry) then return entry --[[@as table<string, any>]] end
    return {}
end

---@param weapon table<string, any>
---@param option string
---@return boolean
local function cosmetic(weapon, option)
    return entryOf(weapon, "Attachments", option).Cosmetic == true or entryOf(weapon, "Camos", option).Unlock ~= nil
end

function lib._AttachmentLimit(weaponLevel, cap)
    return math.max(0, math.min(weaponLevel, cap))
end

---@param view PW.ProgressionView
---@param entry table<string, any>
---@param weaponId string
---@return boolean
local function curatedOpen(view, entry, weaponId)
    return view.unlockAll or view.weaponLevel(weaponId) >= required(entry.Unlock)
end

---@param view PW.ProgressionView
---@param weaponId string
---@param option string
---@param field "Attachments"|"Camos"
---@return boolean
local function optionUnlocked(view, weaponId, option, field)
    local weapon = view.lookup("weapons", weaponId)
    if weapon == nil then return false end
    local entry = entryOf(weapon, field, option)
    if entry.Hidden == true then return false end
    if view.owned ~= nil and view.owned(lib._OwnedKey(field == "Camos" and "camos" or "attachments",
        weaponId .. ":" .. option)) then return true end
    return curatedOpen(view, entry, weaponId)
end

function lib._IsUnlocked(view, kind, id)
    if kind == "attachments" or kind == "camos" then
        local weaponId, option = string.match(id, "^([^:]+):(.+)$")
        if weaponId == nil or option == nil then return false end
        return optionUnlocked(view, weaponId, option, kind == "camos" and "Camos" or "Attachments")
    end
    local entity = view.lookup(kind, id)
    if entity == nil then return false end
    if view.unlockAll then return true end
    if view.owned ~= nil then
        if view.owned(lib._OwnedKey(kind, id)) then return true end
        local price = entity.Price
        if entity.Unlock == nil and isnumber(price) and price > 0 then return false end
    end
    return view.level >= required(entity.Unlock)
end

---@param view PW.ProgressionView
---@param weaponId string
---@return integer
local function countLimit(view, weaponId)
    if view.unlockAll then return view.maxAttachments end
    return lib._AttachmentLimit(view.weaponLevel(weaponId), view.maxAttachments)
end

---The option ids of a build in slot order (cleared slots skipped).
---@param build table<string, string|false>
---@return string[]
local function optionsOf(build)
    ---@type string[]
    local slots = {}
    for slot in pairs(build) do slots[#slots + 1] = slot end
    table.sort(slots)
    ---@type string[]
    local options = {}
    for _, slot in ipairs(slots) do
        local option = build[slot]
        if isstring(option) then options[#options + 1] = option --[[@as string]] end
    end
    return options
end

function lib._LockedOptions(view, weaponId, build)
    ---@type table<string, boolean>
    local locked = {}
    local weapon = view.lookup("weapons", weaponId)
    if weapon == nil then return locked end
    local limit = countLimit(view, weaponId)
    local counted = 0
    for _, option in ipairs(optionsOf(build)) do
        local entry = entryOf(weapon, "Attachments", option)
        if entry.Unlock ~= nil then
            if not curatedOpen(view, entry, weaponId) then locked[option] = true end
        elseif not cosmetic(weapon, option) then
            counted = counted + 1
            if counted > limit then locked[option] = true end
        end
    end
    return locked
end

---The live catalogue: a valid entity of a registry kind, nil otherwise. Shared: the client resolves the same files.
---@type PW.LoadoutLookup
function lib._RegistryLookup(kind, id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries[kind] or nil
    if registry == nil then return nil end
    local entity = registry.Get(id)
    if entity == nil or not entity:IsValid() then return nil end
    return entity
end
