-- The perks kind (05-loadout.md d.4, d.8; 01-extensibility.md d.12, d.16). One file per perk in lua/privatewar/perks/
-- with a PERK table: Name and Group (the perk slot it fits, one perk per group) are required; Description, Cost
-- (Pick X), Stats (multipliers by stat id, read through PW.Stat) and the event methods OnEquip, OnUnequip, OnKill,
-- OnDeath, OnDamaged, OnDealDamage are optional. Never auto-subscribed (d.18): the perks module makes every equipped
-- perk a per-player instance (00-core.md d.11) from spawn to death and calls its event methods only for the owner.
-- Per-perk ConVar: pw_perk_<id>_enabled (d.11). The accessor PW.Perks is the module's library, so the registry is
-- PW.Registries.perks.
KIND.Folder = "perks"
KIND.Global = "PERK"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", Group = "number" }
