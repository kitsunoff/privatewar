-- The bot_personalities kind (07-bots.md d.10; docs/api/bots-blackboard.md "Kinds"): one data file per personality in
-- lua/privatewar/bot_personalities/ with a PERSONALITY table. The type is "active" or "stationary" (only a stationary
-- personality runs camp); the manager gives every team 4 active : 1 stationary. Every other field is read by a bots_*
-- module (a field nobody reads fails the T-5.12 test). Data only, never auto-subscribed (01-extensibility.md d.18).
-- Per-entry ConVar: pw_personality_<id>_enabled (d.11). Name and type are required; the registry is
-- PW.BotPersonalities.
KIND.Folder = "bot_personalities"
KIND.Global = "PERSONALITY"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", type = "string" }
