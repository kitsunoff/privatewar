-- The equipment kind (05-loadout.md d.11; 01-extensibility.md d.12, d.16). One file per item in
-- lua/privatewar/equipment/ with an EQUIPMENT table: Name, Count (uses per life) and OnUse(owner) are required;
-- Category (the slot filter value: "lethal", "tactical") and Cost (Pick X) are optional. Never auto-subscribed
-- (d.18): on spawn the equipment module makes every equipped item a per-player instance (00-core.md d.11) and
-- calls OnUse on it through PW.Call when a bot uses the slot (players switch to the grenade SWEP with the slot key
-- and throw by releasing attack, see docs/api/equipment.md). Per-item ConVar:
-- pw_equipment_<id>_enabled (d.11). The accessor PW.Equipment is the module's library, so the registry is
-- PW.Registries.equipment.
KIND.Folder = "equipment"
KIND.Global = "EQUIPMENT"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", Count = "number", OnUse = "function" }
