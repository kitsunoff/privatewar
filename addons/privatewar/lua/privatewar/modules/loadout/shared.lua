-- Loadout module (T-4.1; 05-loadout.md d.1; 01-extensibility.md d.9). Slots are declared by modules (this one knows
-- nothing about perks or streaks); a loadout is { [slotId] = entityId } (a list of ids for a slot with count > 1).
-- Shared: slot declarations, the pure validation rules, the question hooks and the choice of the loadout. Giving the
-- weapons on spawn (engine calls) is in init.lua.
--
-- Questions (hook.Call dispatch, the active mode answers last as the default):
--   PW_PlayerLoadout(ply)           a table replaces the player's class (Gun Game, Gunfight); the mode is trusted, the
--                                   table is not validated; any other answer is ignored.
--   PW_ValidateLoadout(ply, loadout) false, or a string reason, rejects a loadout that passed the slot rules.
--
-- Decisions of the lane agent:
--   1. A filter entry matches the Category of the item or, when the item has none, its Kind: the design's secondary
--      filter names "launcher" (a Kind of the adapter) next to categories, and the crowbar has a Kind only.
--   2. The built-in slots are primary, secondary and melee (weapons). The design lists no melee slot; the HL2
--      fallback weapons need one for the crowbar. Lethal, tactical, perks and streaks belong to their
--      modules (T-4.4 to T-4.6); the wildcard slot is declared here (sh_wildcards.lua).
--   3. Without a picked class (T-4.7) a player has the default loadout (smg1, pistol, crowbar: a gameplay value).

MODULE.Name = "Loadout"

-- Pick X (T-4.2; 05-loadout.md d.2, d.3, d.7). Names follow the task: bannedweapons, bannedattachments (the design
-- draft says "bannedatts").
MODULE.Settings = {
    budget = { type = "int", default = 10, min = 0, max = 100, label = "Pick X budget (0 = unlimited)" },
    maxattachments = { type = "int", default = 5, min = 0, max = 20, label = "Attachments per weapon" },
    bannedweapons = { type = "set", default = {}, label = "Banned weapons" },
    bannedattachments = { type = "set", default = {}, label = "Banned attachments" },
    -- T-4.7, 05-loadout.md d.12: custom classes a player may bring (classes.json).
    classes = { type = "int", scope = "server", default = 10, min = 1, max = 20, label = "Custom classes per player" }
}

local lib = (rawget(PW, "Loadout") or {}) --[[@as PW.LoadoutLib]]
PW.Loadout = lib

if SERVER then
    AddCSLuaFile("privatewar/modules/loadout/sh_budget.lua")
    AddCSLuaFile("privatewar/modules/loadout/sh_classes.lua")
    AddCSLuaFile("privatewar/modules/loadout/sh_classes_repair.lua")
    AddCSLuaFile("privatewar/modules/loadout/sh_class_visibility.lua")
    AddCSLuaFile("privatewar/modules/loadout/sh_wildcards.lua")
    AddCSLuaFile("privatewar/modules/loadout/sh_gunsmith.lua")
end
include("privatewar/modules/loadout/sh_budget.lua")
include("privatewar/modules/loadout/sh_classes.lua")
include("privatewar/modules/loadout/sh_classes_repair.lua")
include("privatewar/modules/loadout/sh_class_visibility.lua")
include("privatewar/modules/loadout/sh_wildcards.lua")
include("privatewar/modules/loadout/sh_gunsmith.lua")

---@type PW.LoadoutStore
PW._Loadout = PW._Loadout or { slots = {}, order = {}, classes = setmetatable({}, { __mode = "k" }) }

---@param filter any
---@return boolean
local function filterOk(filter)
    if filter == nil then return true end
    if not istable(filter) then return false end
    for _, entry in ipairs(filter --[[@as any[] ]]) do
        if not isstring(entry) then return false end
    end
    return true
end

---@param decl any
---@return string?
local function declError(decl)
    if not istable(decl) then return "the declaration is not a table" end
    local fields = decl --[[@as table<string, any>]]
    if not isstring(fields.kind) or fields.kind == "" then return "kind must be a non-empty string" end
    if not filterOk(fields.filter) then return "filter must be a list of strings" end
    local count = fields.count
    if count ~= nil and (not isnumber(count) or count < 1 or count ~= math.floor(count)) then
        return "count must be a positive integer"
    end
    return nil
end

function lib.DeclareSlot(id, decl)
    if not isstring(id) or id == "" then return false, "the slot id must be a non-empty string" end
    local err = declError(decl)
    if err ~= nil then return false, err end
    local store = PW._Loadout
    local slot = table.Copy(decl) --[[@as PW.LoadoutSlot]]
    slot.id = id
    if store.slots[id] == nil then store.order[#store.order + 1] = id end
    store.slots[id] = slot
    return true
end

function lib.GetSlot(id)
    local slot = PW._Loadout.slots[id]
    if slot == nil then return nil end
    return table.Copy(slot) --[[@as PW.LoadoutSlot]]
end

function lib.GetSlotIds()
    ---@type string[]
    local ids = {}
    for index, id in ipairs(PW._Loadout.order) do ids[index] = id end
    return ids
end

function lib.RemoveSlot(id)
    local store = PW._Loadout
    if store.slots[id] == nil then return false end
    store.slots[id] = nil
    table.RemoveByValue(store.order, id)
    return true
end

function lib._Matches(slot, entity)
    local filter = slot.filter
    if filter == nil then return true end
    local category, kind = entity.Category, entity.Kind
    for _, entry in ipairs(filter) do
        if entry == category or (category == nil and entry == kind) then return true end
    end
    return false
end

function lib._Items(value)
    if isstring(value) then return { value --[[@as string]] } end
    if not istable(value) then return nil end
    local list = value --[[@as any[] ]]
    if #list == 0 then return nil end
    ---@type string[]
    local items = {}
    for index, item in ipairs(list) do
        if not isstring(item) then return nil end
        items[index] = item
    end
    return items
end

---@param slot PW.LoadoutSlot
---@param value any
---@param lookup PW.LoadoutLookup
---@return string?
local function slotError(slot, value, lookup)
    local items = lib._Items(value)
    if items == nil then return "slot " .. slot.id .. " holds neither an id nor a list of ids" end
    if #items > (slot.count or 1) then return "slot " .. slot.id .. " holds at most " .. (slot.count or 1) end
    for _, item in ipairs(items) do
        local entity = lookup(slot.kind, item)
        if entity == nil then return item .. " is not in the kind " .. slot.kind end
        if not lib._Matches(slot, entity) then return item .. " does not fit the filter of slot " .. slot.id end
    end
    return nil
end

function lib._Validate(declared, loadout, lookup, ctx)
    -- T-4.3: the wildcards in the loadout change the slot set it is judged by.
    local slots = lib._EffectiveSlots(declared, loadout, lookup, ctx ~= nil and ctx.maxattachments or nil)
    ---@type string[]
    local ids = table.GetKeys(loadout) --[[@as string[] ]]
    table.sort(ids)
    for _, id in ipairs(ids) do
        local slot = slots[id]
        -- The reserved key "builds" is not a slot; lib._Extras checks it.
        if id ~= "builds" and slot == nil then return false, "unknown slot " .. tostring(id) end
        local err = id ~= "builds" and slotError(slot, loadout[id], lookup) or nil
        if err ~= nil then return false, err end
    end
    local err = lib._WildcardError(slots, loadout)
    if err ~= nil then return false, err end
    if ctx ~= nil then return lib._Extras(slots, loadout, ctx) end
    return true
end

---@type PW.LoadoutLookup
function lib._RegistryLookup(kind, id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries[kind] or nil
    if registry == nil then return nil end
    local entity = registry.Get(id)
    if entity == nil or not entity:IsValid() then return nil end
    return entity
end

function lib.Validate(ply, loadout, lookup)
    local find = lookup or lib._RegistryLookup
    local ok, err = lib._Validate(PW._Loadout.slots, loadout, find, lib._LiveContext(find))
    if not ok then return false, err end
    return lib._AskValidate(ply, loadout)
end

function lib._AskValidate(ply, loadout)
    local answer = PW.Ask("PW_ValidateLoadout", ply, loadout)
    if answer == false then return false, "rejected by PW_ValidateLoadout" end
    if isstring(answer) then return false, answer --[[@as string]] end
    return true
end

function lib.SetClass(ply, loadout)
    PW._Loadout.classes[ply] = loadout
end

function lib.GetClass(ply)
    return PW._Loadout.classes[ply]
end

-- Default items of slots declared by other modules (a gameplay value).
local moduleDefaults = { lethal = "frag", tactical = "flash", perk1 = "ready_up", perk2 = "sleight_of_hand",
    perk3 = "adrenaline", streak1 = "uav", streak2 = "counter_uav", streak3 = "airstrike" }

function lib.Default()
    local default = { primary = "weapon_smg1", secondary = "weapon_pistol", melee = "weapon_crowbar" }
    -- Slots of other modules (equipment T-4.5, perks T-4.4, streaks T-4.6), only while declared.
    local slots = PW._Loadout.slots
    for slot, id in pairs(moduleDefaults) do
        if slots[slot] ~= nil then default[slot] = id end
    end
    return default
end

function lib.Resolve(ply)
    local fromMode = PW.Ask("PW_PlayerLoadout", ply)
    if istable(fromMode) then return fromMode --[[@as PW.Loadout]], "mode" end
    local class = lib.GetClass(ply)
    if class ~= nil then return class, "class" end
    return lib.Default(), "default"
end

lib.DeclareSlot("primary", { kind = "weapons", filter = { "ar", "smg", "lmg", "sniper", "shotgun" } })
lib.DeclareSlot("secondary", { kind = "weapons", filter = { "pistol", "launcher" } })
lib.DeclareSlot("melee", { kind = "weapons", filter = { "melee" } })
-- T-4.3: up to two wildcards (05-loadout.md d.5); their ModifySlots changes the other slots.
lib.DeclareSlot(lib.WildcardSlot, { kind = "wildcards", count = 2, label = "#pw.slot.wildcard" })
