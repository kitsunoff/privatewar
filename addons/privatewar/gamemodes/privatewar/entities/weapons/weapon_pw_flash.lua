-- Flash grenade SWEP (T-11.4): given by the equipment item "flash" (tactical slot); the count is its ammo
-- "pw_flash". Everything else is the base weapon_pw_grenade.
SWEP.Base = "weapon_pw_grenade"
SWEP.PrintName = "Flash"
SWEP.PWSlot = "tactical"
SWEP.SlotPos = 1
SWEP.Primary = { ClipSize = -1, DefaultClip = 0, Automatic = true, Ammo = "pw_flash" }
