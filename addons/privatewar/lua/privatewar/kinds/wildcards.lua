-- The wildcards kind (05-loadout.md d.5; 01-extensibility.md d.12, d.16). One file per wildcard in
-- lua/privatewar/wildcards/ with a WILDCARD table: Name and ModifySlots(slots) are required; Description, Cost (Pick X,
-- default 1) and Stats (multipliers by stat id, read through PW.Stat) are optional. A wildcard is picked in the
-- loadout slot "wildcard"; ModifySlots changes a copy of the slot set that the validation, the budget and the class
-- repair use. Never auto-subscribed (d.18). Per-wildcard ConVar: pw_wildcard_<id>_enabled (d.11). The registry is
-- PW.Registries.wildcards.
KIND.Folder = "wildcards"
KIND.Global = "WILDCARD"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", ModifySlots = "function" }
