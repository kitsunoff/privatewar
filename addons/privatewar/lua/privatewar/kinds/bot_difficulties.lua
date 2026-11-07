-- The bot_difficulties kind (07-bots.md d.10, d.15; docs/api/bots-blackboard.md "Kinds"): one data file per tier in
-- lua/privatewar/bot_difficulties/ with a DIFFICULTY table (recruit, regular, hardened, veteran). Every other field is
-- a number (or the headshot_allowed string) that a bots_* module reads; a field nobody reads fails the T-5.12 test, so
-- a module that wants a new parameter declares it with PW.BotProfiles.Reads and adds it to every file. Data only,
-- never auto-subscribed (01-extensibility.md d.18). Per-entry ConVar: pw_difficulty_<id>_enabled (d.11). Only Name is
-- required; the registry is PW.BotDifficulties.
KIND.Folder = "bot_difficulties"
KIND.Global = "DIFFICULTY"
KIND.Subscribe = "never"
KIND.Required = { Name = "string" }
