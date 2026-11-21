-- Progression unlock decisions (06-progression.md d.2, d.8). Each view injects catalogue, levels and sources.

local lib = PW.Progression --[[@as PW.ProgressionLib]]
local unlocks = PW.Unlocks --[[@as PW.UnlocksLib]]

---The curated entry of an option, if any.
---@param weapon table<string, any>
---@param field "Attachments"|"Camos"
---@param option string
---@return table<string, any>?
local function entryOf(weapon, field, option)
    local entries = weapon[field]
    if not istable(entries) then return nil end
    local entry = (entries --[[@as table<string, any>]])[option]
    if istable(entry) then return entry --[[@as table<string, any>]] end
    return nil
end

---@param weapon table<string, any>
---@param option string
---@return "attachments"|"camos"
local function optionKind(weapon, option)
    return entryOf(weapon, "Camos", option) ~= nil and "camos" or "attachments"
end

function lib._AttachmentLimit(weaponLevel, cap)
    return math.max(0, math.min(weaponLevel, cap))
end

---@param view PW.ProgressionView
---@param kind string
---@param id string
---@return table<string, any>? entry
---@return string? canonicalKind
---@return string? canonicalId
---@return string? weaponId
local function resolve(view, kind, id)
    if type(kind) ~= "string" or type(id) ~= "string" then return nil end
    local name, item, weaponId, option = unlocks.ParseKey(lib._OwnedKey(kind, id))
    if name == nil or item == nil or name == "bundles" or name == "classes" then return nil end
    if weaponId ~= nil and option ~= nil then
        local weapon = view.lookup("weapons", weaponId)
        if weapon == nil then return nil end
        local field = name == "camos" and "Camos" or "Attachments"
        return entryOf(weapon, field, option) or {}, name, item, weaponId
    end
    return view.lookup(name, item), name, item
end

---@param view PW.ProgressionView
---@param kind string
---@param id string
---@param entry table<string, any>
---@param weaponId? string
---@return boolean, PW.UnlockReason
local function decide(view, kind, id, entry, weaponId)
    if weaponId ~= nil and entry.Hidden == true then return false, "hidden" end
    if view.override ~= nil then
        local answer = view.override(kind, id)
        if type(answer) == "boolean" then return answer, "override" end
    end
    if view.unlockAll then return true, "unlockall" end
    local key = lib._OwnedKey(kind, id)
    if view.granted ~= nil and view.granted(key) then return true, "grant" end
    if view.owned ~= nil and view.owned(key) then return true, "purchase" end
    local spec = unlocks._Spec(entry.Unlock)
    if spec.level == false then return false, "grant_only" end
    if weaponId == nil and not spec.declared and view.owned ~= nil and unlocks._Price(entry) ~= nil then
        return false, "price"
    end
    if spec.level == 0 then return true, "default" end
    if weaponId ~= nil then return view.weaponLevel(weaponId) >= spec.level, "weapon_level" end
    return view.level >= spec.level, "level"
end

function unlocks._Decide(view, kind, id)
    local entry, name, item, weaponId = resolve(view, kind, id)
    if entry == nil or name == nil or item == nil then return false, "unknown" end
    return decide(view, name, item, entry, weaponId)
end

function unlocks._Requirement(view, kind, id)
    local entry, name, item, weaponId = resolve(view, kind, id)
    if entry == nil or name == nil or item == nil then return unlocks._StaticRequirement(nil, false) end
    local unlocked, reason = decide(view, name, item, entry, weaponId)
    ---@type PW.UnlockRequirement
    local out = { unlocked = unlocked, reason = reason }
    if unlocked or reason == "hidden" then return out end
    local spec = unlocks._Spec(entry.Unlock)
    if spec.level ~= false then
        if reason == "level" then out.level = spec.level end
        if reason == "weapon_level" then out.weaponLevel = spec.level end
    end
    if weaponId == nil and view.owned ~= nil then
        local key = lib._OwnedKey(name, item)
        if not view.owned(key) and not (view.granted ~= nil and view.granted(key)) then
            out.price = unlocks._Price(entry)
        end
    end
    local hint = view.hint ~= nil and unlocks._CheckHint(view.hint(name, item)) or nil
    out.hint = hint or spec.hint
    out.lockText, out.text = unlocks.LockText(out)
    return out
end

function lib._IsUnlocked(view, kind, id)
    return (unlocks._Decide(view, kind, id))
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

---@param view PW.ProgressionView
---@param key string
---@return boolean
local function entitled(view, key)
    return (view.granted ~= nil and view.granted(key)) or (view.owned ~= nil and view.owned(key))
end

function lib._EntitledOption(view, weaponId, option)
    local weapon = view.lookup("weapons", weaponId)
    if weapon == nil then return false end
    return entitled(view, lib._OwnedKey(optionKind(weapon, option), weaponId .. ":" .. option))
end

function lib._LockedOptions(view, weaponId, build)
    ---@type table<string, boolean>
    local locked = {}
    local weapon = view.lookup("weapons", weaponId)
    if weapon == nil then return locked end
    local limit = countLimit(view, weaponId)
    local counted = 0
    for _, option in ipairs(optionsOf(build)) do
        local attachment = entryOf(weapon, "Attachments", option) or {}
        local kind, id = optionKind(weapon, option), weaponId .. ":" .. option
        if attachment.Hidden == true or not unlocks._Decide(view, kind, id) then
            locked[option] = true
        elseif kind == "attachments" and attachment.Unlock == nil and attachment.Cosmetic ~= true
            and not entitled(view, lib._OwnedKey(kind, id)) then
            counted = counted + 1
            if counted > limit then locked[option] = true end
        end
    end
    return locked
end

local debugVar = GetConVar("pw_debug")
---@type table<table, boolean>
local warned = setmetatable({}, { __mode = "k" })

---@param entity table<string, any>
---@param kind string
---@param id string
local function warnBadUnlock(entity, kind, id)
    if debugVar == nil or not debugVar:GetBool() or warned[entity] then return end
    local value = entity.Unlock
    if istable(value) then value = (value --[[@as table<string, any>]]).level end
    if value == nil or value == false or (isnumber(value) and value == value and math.abs(value) < math.huge) then
        return
    end
    warned[entity] = true
    print(string.format("[PW] invalid Unlock field on %s:%s; ignoring its level", kind, id))
end

---The live catalogue: a valid entity of a registry kind, nil otherwise. Shared: the client resolves the same files.
---@type PW.LoadoutLookup
function lib._RegistryLookup(kind, id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries[kind] or nil
    if registry == nil then return nil end
    local entity = registry.Get(id)
    if entity == nil or not entity:IsValid() then return nil end
    warnBadUnlock(entity, kind, id)
    return entity
end

---@param weaponId string
---@param option string
---@return boolean
local function offeredOption(weaponId, option)
    local adapters = PW.Adapters
    if adapters == nil then return false end
    local slots = adapters.CallFor(weaponId, "GetSlots", weaponId, {}) --[[@as PW.Slot[]?]]
    for _, slot in ipairs(slots or {}) do
        local options = adapters.CallFor(weaponId, "GetOptions", weaponId, slot.id) --[[@as PW.Option[]?]]
        for _, entry in ipairs(options or {}) do
            if entry.id == option then return true end
        end
    end
    return false
end

function unlocks._Known(key)
    local kind, id, weaponId, option = unlocks.ParseKey(key)
    if kind == nil or id == nil then return false end
    if weaponId == nil or option == nil then return lib._RegistryLookup(kind, id) ~= nil end
    local weapon = lib._RegistryLookup("weapons", weaponId)
    if weapon == nil then return false end
    return entryOf(weapon, kind == "camos" and "Camos" or "Attachments", option) ~= nil
        or offeredOption(weaponId, option)
end

function unlocks.Describe(item)
    local key = unlocks._EntitlementKey(unlocks.KeyOf(item))
    local kind, id, weaponId, option = unlocks.ParseKey(key or "")
    if key == nil or kind == nil or id == nil then
        return { key = "", kind = "", id = "", name = "Unknown item", valid = false }
    end
    local entity = nil
    if weaponId == nil then
        entity = lib._RegistryLookup(kind, id)
    elseif kind == "camos" and option ~= nil then
        local weapon = lib._RegistryLookup("weapons", weaponId)
        entity = weapon ~= nil and entryOf(weapon, "Camos", option) or nil
    end
    local name = entity ~= nil and type(entity.Name) == "string" and entity.Name or option or id
    return { key = key, kind = kind, id = id, weapon = weaponId, name = name, valid = unlocks._Known(key) }
end
