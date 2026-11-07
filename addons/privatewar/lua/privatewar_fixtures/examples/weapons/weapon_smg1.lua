-- Example (T-1.18): a declarative weapon entry (04-weapons.md d.3). The file name is the SWEP class, here the
-- HL2 SMG. No field is required: a weapon base integration can fill missing ones later with a soft registration
-- in PW_RegisterWeapons. Every entry gets the ConVar pw_weapon_<class>_enabled (01-extensibility.md d.11).

WEAPON.Category = "smg"
WEAPON.Name = "SMG"
-- Unlock level, read by progression; leave it out to use its default.
WEAPON.Unlock = 1
