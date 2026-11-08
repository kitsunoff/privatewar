-- Weapon ammo module (T-3.4; 04-weapons.md d.1; docs/api/adapter.md "Ammo" and "Open in design" item 6). Ammo is
-- owned by the core: the weapon base's default ammo is suppressed, then the core gives a configured number of
-- magazines. Shared: the setting and the pure arithmetic. The Give wrapper (engine calls) is in init.lua.
--
-- Decisions of the lane agent:
--   1. Who gives ammo: this module, through PW.WeaponAmmo.Give(ply, class, opts?) (the loadout lane calls it).
--      PW.Weapons is the weapons registry, so the API lives in PW.WeaponAmmo.
--   2. How many: the match setting weapons_ammo.magazines, default 3 spare magazines (gameplay value, to be
--      confirmed), 0 to 20. Reserve = magazines times the clip size; a weapon without a clip gets one round per
--      magazine.

MODULE.Name = "Weapon ammo"

MODULE.Settings = {
    magazines = { type = "int", default = 3, min = 0, max = 20, label = "Spare magazines per weapon" }
}

local lib = (rawget(PW, "WeaponAmmo") or {}) --[[@as PW.WeaponAmmoLib]]
PW.WeaponAmmo = lib

if SERVER then AddCSLuaFile("privatewar/modules/weapons_ammo/sh_resupply.lua") end
include("privatewar/modules/weapons_ammo/sh_resupply.lua")

---@param capacity number
---@param magazines number
---@return integer
function lib._ReserveFor(capacity, magazines)
    local count = math.max(0, math.floor(magazines))
    if capacity <= 0 then return count end
    return count * math.floor(capacity)
end

---@return integer
function lib._Magazines()
    local value = PW.Setting("weapons_ammo.magazines")
    if not isnumber(value) then return 3 end
    return math.max(0, math.floor(value --[[@as number]]))
end
