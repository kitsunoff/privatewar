-- Equipment module (T-4.5; 05-loadout.md d.11: equipment is an item in a slot, its behaviour belongs to the item).
-- Shared and pure: the slots lethal and tactical (declared in the loadout module, kind equipment, an action key
-- each), the counts, the use rule and the slot keys; the grenade rules are sh_grenades.lua (T-11.4: grenades are
-- inventory SWEPs). Server state, spawn and death hooks and the grenade SWEPs' glue are init.lua; the key handling
-- (select the grenade SWEP) is cl_init.lua; the items are lua/privatewar/equipment/.
--
-- No net message of its own: the slot keys select the grenade SWEP on the client (input.SelectWeapon) and the SWEP
-- throws on release. Counts and item ids reach the client as NW2 values of the player ("pw_eq_<slot>",
-- "pw_eqn_<slot>"), written only when they change; the count is also the ammo of the grenade SWEP.
--
-- Decisions of the lane agent:
--   1. Keys: lethal G (the design), tactical 4 (the design; F stays the flashlight). Each slot also has a console
--      command (the slot's key field: pw_lethal, pw_tactical) for players who bind keys themselves; the default
--      physical keys are client ConVars pw_key_lethal and pw_key_tactical.
--   2. A use (a thrown grenade) costs one count; OnUse returning false refuses the use (count kept). One use per
--      slot per Cooldown.
--   3. Equipment is spent on death and refilled on spawn (CoD rule); items are instances living one life.

MODULE.Name = "Equipment"

local lib = (rawget(PW, "Equipment") or {}) --[[@as PW.EquipmentLib]]
PW.Equipment = lib

lib.Slots = { "lethal", "tactical" }
lib.Keys = {
    lethal = { command = "pw_lethal", convar = "pw_key_lethal", default = "g" },
    tactical = { command = "pw_tactical", convar = "pw_key_tactical", default = "4" }
}
lib.Cooldown = 0.75

---@type table<string, string>
local itemKeys = {}
---@type table<string, string>
local countKeys = {}
for _, slot in ipairs(lib.Slots) do
    itemKeys[slot], countKeys[slot] = "pw_eq_" .. slot, "pw_eqn_" .. slot
end

function lib._ItemKey(slot)
    return itemKeys[slot] or ("pw_eq_" .. slot)
end

function lib._CountKey(slot)
    return countKeys[slot] or ("pw_eqn_" .. slot)
end

function lib._Refill(def)
    local count = def.Count
    if not isnumber(count) then return 0 end
    return math.max(0, math.floor(count --[[@as number]]))
end

function lib._CanUse(entry, now, cooldown)
    if entry.count < 1 then return false, "empty" end
    local instance = entry.instance
    if instance == nil or not instance:IsValid() then return false, "invalid" end
    if now - entry.last < cooldown then return false, "cooldown" end
    return true
end

function lib._KeySlot(button, codes)
    if button == nil or button == KEY_NONE then return nil end
    for _, slot in ipairs(lib.Slots) do
        if codes[slot] == button then return slot end
    end
    return nil
end

function lib._DeclareSlots()
    local loadout = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
    if loadout == nil then return end
    for _, slot in ipairs(lib.Slots) do
        loadout.DeclareSlot(slot, { kind = "equipment", filter = { slot }, key = lib.Keys[slot].command,
            label = "#pw.slot." .. slot })
    end
end

-- The loadout module loads after this one (modules load by id): declare again once every registry is loaded.
lib._DeclareSlots()

function MODULE:PW_RegistriesLoaded()
    lib._DeclareSlots()
end

if SERVER then AddCSLuaFile("privatewar/modules/equipment/sh_grenades.lua") end
include("privatewar/modules/equipment/sh_grenades.lua")

if CLIENT then
    function lib.Item(ply, slot)
        local id = ply:GetNW2String(lib._ItemKey(slot), "")
        if id == "" then return nil end
        return id
    end

    function lib.Count(ply, slot)
        local class = lib._ItemWeapon(lib.Item(ply, slot))
        local ammo = class ~= nil and ply:HasWeapon(class) and lib._AmmoOf(class) or nil
        if ammo ~= nil then return ply:GetAmmoCount(ammo) end
        return ply:GetNW2Int(lib._CountKey(slot), 0)
    end
end
