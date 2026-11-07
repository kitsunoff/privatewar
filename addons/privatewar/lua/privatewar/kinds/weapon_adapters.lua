-- The weapon adapters kind (04-weapons.md d.1, d.4; 01-extensibility.md d.16; docs/api/adapter.md): one file or
-- folder per adapter in lua/privatewar/weapon_adapters/ with an ADAPTER table. The id is the file name. Never
-- auto-subscribed: adapter methods are not PW_* hooks, the core calls them through PW.Call (adapter lookup:
-- modules/weapons_core). Per-entry ConVar: pw_adapter_<id>_enabled (d.11, from Global = "ADAPTER").
-- Required is checked after Base resolution (core.md "Required fields"): an adapter may inherit these methods.
KIND.Folder = "weapon_adapters"
KIND.Global = "ADAPTER"
KIND.Subscribe = "never"
KIND.Required = { IsAvailable = "function", Claims = "function", ListWeapons = "function" }
