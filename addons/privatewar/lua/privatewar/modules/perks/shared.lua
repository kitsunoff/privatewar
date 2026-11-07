-- Perks module (T-4.4; 05-loadout.md d.4, d.8). Shared and pure: the perk slots perk1..perk3 (declared in the loadout
-- module, kind perks, one group each), the group rule (asked through PW_ValidateLoadout), the multiplier chain behind
-- PW.Stat, the weapon subset for PW.SetStatMods and the owner filter of the event methods. Server state, recompute,
-- instances and the hooks are init.lua; the perks are lua/privatewar/perks/.
--
-- Decisions of the lane agent:
--   1. The event methods are the design's convenience events (OnKill, OnDeath, OnDamaged, OnDealDamage, plus
--      OnEquip/OnUnequip from PW.Instance), called only for the owner; other hooks go through self:Hook.
--   2. Recompute trigger: the notification PW_LoadoutGiven(ply, loadout), fired by PW.Loadout.Give. It covers the
--      spawn in LIVE and a mode giving a new loadout mid-life; class edits apply at the next spawn (d.12).
--   3. Chain order: perks, then registered stat sources (the wildcards hook point, sorted by id), then the active
--      mode's MODE.Stats table. The product is commutative; the order only fixes iteration.
--   4. The group rule runs in PW_ValidateLoadout, so a class with a perk in the wrong group is marked unavailable
--      (not repaired). A slot without a group accepts any perk (a wildcard may drop the group on purpose).

MODULE.Name = "Perks"

local lib = (rawget(PW, "Perks") or {}) --[[@as PW.PerksLib]]
PW.Perks = lib

lib.Slots = { "perk1", "perk2", "perk3" }

---@type table<string, PW.PerkStatSource>
PW._PerkSources = PW._PerkSources or {}

---@param value any
---@return boolean
local function goodNumber(value)
    return isnumber(value) and value > 0 and value < math.huge
end

function lib._GroupError(slot, def)
    local group = slot.group
    if group == nil or def.Group == group then return nil end
    return string.format("%s is a group %s perk, slot %s takes group %s", tostring(def.ClassName or def.Name),
        tostring(def.Group), tostring(slot.id), tostring(group))
end

---The ids a perks-kind slot holds (an id or a list of ids); empty for any other slot or value.
---@param slot table?
---@param value any
---@return string[]
local function perkItems(slot, value)
    if slot == nil or slot.kind ~= "perks" or value == nil then return {} end
    ---@type string[]
    local items = {}
    local list = (istable(value) and value or { value }) --[[@as any[] ]]
    for _, id in ipairs(list) do
        if isstring(id) then items[#items + 1] = id --[[@as string]] end
    end
    return items
end

---@param slot table
---@param items string[]
---@param lookup fun(id: string): table?
---@return string?
local function slotGroupError(slot, items, lookup)
    for _, id in ipairs(items) do
        local def = lookup(id)
        local reason = def ~= nil and lib._GroupError(slot, def) or nil
        if reason ~= nil then return reason end
    end
    return nil
end

function lib._CheckGroups(slots, loadout, lookup)
    local ids = table.GetKeys(slots) --[[@as string[] ]]
    table.sort(ids)
    for _, slotId in ipairs(ids) do
        local slot = slots[slotId]
        local reason = slotGroupError(slot, perkItems(slot, loadout[slotId]), lookup)
        if reason ~= nil then return false, reason end
    end
    return true
end

function lib._PerkIds(order, slots, loadout)
    ---@type string[]
    local ids = {}
    for _, slotId in ipairs(order) do
        for _, id in ipairs(perkItems(slots[slotId], loadout[slotId])) do ids[#ids + 1] = id end
    end
    return ids
end

---@param combined table<string, number>
---@param stats any
local function multiplyInto(combined, stats)
    if not istable(stats) then return end
    for stat, value in pairs(stats --[[@as table<any, any>]]) do
        if isstring(stat) and goodNumber(value) then combined[stat] = (combined[stat] or 1) * value end
    end
end

function lib._Multiply(lists)
    ---@type table<string, number>
    local combined = {}
    for _, list in ipairs(lists) do
        for _, stats in ipairs(list) do multiplyInto(combined, stats) end
    end
    return combined
end

function lib._WeaponMods(stats, keys)
    ---@type table<string, number>
    local mods = {}
    for _, key in ipairs(keys) do
        if stats[key] ~= nil then mods[key] = stats[key] end
    end
    return mods
end

function lib._Targets(event, victim, attacker, isPlayer)
    local mine, theirs = "OnDealDamage", "OnDamaged"
    if event == "kill" then mine, theirs = "OnKill", "OnDeath" end
    ---@type PW.PerkTarget[]
    local targets = {}
    if attacker ~= victim and isPlayer(attacker) then
        targets[#targets + 1] = { owner = attacker, method = mine, other = victim }
    end
    if isPlayer(victim) then targets[#targets + 1] = { owner = victim, method = theirs, other = attacker } end
    return targets
end

function lib.StatSource(id, fn)
    PW._PerkSources[id] = fn
end

---@param id string
---@return table?
local function registryPerk(id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries.perks or nil
    if registry == nil then return nil end
    return registry.Get(id)
end

function lib._Validate(loadout)
    local store = rawget(PW, "_Loadout") --[[@as PW.LoadoutStore?]]
    if store == nil or not istable(loadout) then return nil end
    -- T-4.3: a wildcard may change the group of a perk slot, so judge by the effective slots.
    local loadoutLib = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
    local slots = store.slots
    if loadoutLib ~= nil and loadoutLib._EffectiveSlots ~= nil and loadoutLib._RegistryLookup ~= nil then
        slots = loadoutLib._EffectiveSlots(slots, loadout, loadoutLib._RegistryLookup)
    end
    local ok, reason = lib._CheckGroups(slots, loadout, registryPerk)
    if ok then return nil end
    return reason
end

function lib._DeclareSlots()
    local loadout = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
    if loadout == nil then return end
    for group, slot in ipairs(lib.Slots) do
        loadout.DeclareSlot(slot, { kind = "perks", group = group, label = "#pw.slot." .. slot })
    end
end

lib._DeclareSlots()

function MODULE:PW_RegistriesLoaded()
    lib._DeclareSlots()
end

function MODULE:PW_ValidateLoadout(_, loadout)
    return lib._Validate(loadout)
end

---@param ply Player
---@param stat string
---@param base number
---@return number
function PW.Stat(ply, stat, base)
    local store = rawget(PW, "_Perks") --[[@as PW.PerksStore?]]
    local stats = store ~= nil and store.stats[ply] or nil
    local multiplier = stats ~= nil and stats[stat] or nil
    if multiplier == nil then return base end
    return base * multiplier
end
