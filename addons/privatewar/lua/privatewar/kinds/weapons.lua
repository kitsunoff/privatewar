-- The weapons kind (04-weapons.md d.3; 01-extensibility.md d.16): id = SWEP class. One file per weapon in
-- lua/privatewar/weapons/ with a WEAPON table (declarative), plus programmatic entries registered by
-- PW_RegisterWeapons listeners after InitPostEntity (core/sh_weapon_phase.lua). Never auto-subscribed (d.18): a
-- weapon entry is data. Per-entry ConVar: pw_weapon_<class>_enabled (d.11). No required fields: a soft
-- registration may carry only some fields (Category, Name, Unlock, ...), filled from other sources.
KIND.Folder = "weapons"
KIND.Global = "WEAPON"
KIND.Subscribe = "never"
