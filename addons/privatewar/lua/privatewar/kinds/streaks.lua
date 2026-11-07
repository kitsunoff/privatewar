-- The streaks kind (05-loadout.md d.9, d.10; 01-extensibility.md d.12, d.16). One file per killstreak in
-- lua/privatewar/streaks/ with a STREAK table: Name, Kills (the cost when earned by kills) and OnEquip(owner) (the
-- activation, 00-core.md d.11) are required; Score (the cost when earned by score, default Kills x 100), Duration
-- (seconds until the streaks module ends the activation, default PW.Streaks.DefaultDuration), OnUnequip and
-- BotShouldUse(bot) are optional. Never auto-subscribed (d.18): activating a streak makes a PW.Instance of it.
-- Per-streak ConVar: pw_streak_<id>_enabled (d.11). The accessor PW.Streaks is the module's library, so the
-- registry is PW.Registries.streaks.
KIND.Folder = "streaks"
KIND.Global = "STREAK"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", Kills = "number", OnEquip = "function" }
