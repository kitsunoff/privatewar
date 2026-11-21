-- Progression unlock decisions (06-progression.md d.2, d.8). Each view injects catalogue, levels and sources.

local lib = PW.Progression --[[@as PW.ProgressionLib]]
local unlocks = PW.Unlocks --[[@as PW.UnlocksLib]]

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
    local level = unlocks._Spec(entry.Unlock).level
    return view.unlockAll or (level ~= false and view.weaponLevel(weaponId) >= level)
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
        return entryOf(weapon, field, option), name, item, weaponId
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
