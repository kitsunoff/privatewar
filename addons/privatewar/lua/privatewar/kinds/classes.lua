-- The classes kind (05-loadout.md d.13; 01-extensibility.md d.12, d.16). One data file per preset class in
-- lua/privatewar/classes/ with a CLASS table: Name (display name) and Loadout (a PW.Loadout: slot id -> entity id,
-- "builds" for attachment builds), optional Description. Data only, never auto-subscribed (d.18). The loadout module
-- repairs a preset against the match settings like a player's class (T-4.7). Per-entry ConVar:
-- pw_class_<id>_enabled (d.11).
KIND.Folder = "classes"
KIND.Global = "CLASS"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", Loadout = "table" }
