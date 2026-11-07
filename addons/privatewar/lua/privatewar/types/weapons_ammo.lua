---@meta
-- Types of the weapon ammo module (T-3.4; docs/api/adapter.md "Ammo"). Code: lua/privatewar/modules/weapons_ammo/.

---@class PW.WeaponGiveOptions
---@field magazines? integer spare magazines to give; defaults to the setting weapons_ammo.magazines

---Ammo is owned by the core: a weapon given through Give has its default ammo suppressed and gets the configured
---number of magazines.
---@class PW.WeaponAmmoLib
---Gives the weapon class to the player (server). Default ammo is suppressed (adapter SuppressDefaultAmmo), the clip
---is filled and the reserve of GetAmmoType is set to magazines times the clip size. Returns the weapon, or nil when
---nothing was given (invalid player, unknown class, the player already holds it).
---@field Give fun(ply: Player, class: string, opts?: PW.WeaponGiveOptions): Weapon?
---Internal, pure: the reserve for a clip size and a number of magazines (rounded down, never negative). A weapon
---without a clip (capacity of 0 or less) gets one round per magazine.
---@field _ReserveFor fun(capacity: number, magazines: number): integer
---Internal: the configured magazines (the setting, a non-negative integer).
---@field _Magazines fun(): integer

---@class PW
---@field WeaponAmmo PW.WeaponAmmoLib
