-- The bot_behaviors kind (07-bots.md d.4, d.5, d.13; 01-extensibility.md d.17; docs/api/bots-blackboard.md "Kinds"):
-- one file or folder per behaviour in lua/privatewar/bot_behaviors/ with a BEHAVIOR table. The brain
-- (modules/bots_brain) calls its methods through PW.Call, so an erroring behaviour is disabled and the others go on;
-- never auto-subscribed (behaviour methods are not PW_* hooks). Per-entry ConVar: pw_behavior_<id>_enabled (d.11).
-- Rank, Weight and Update are required; Modes, Interval, MinRun, Cooldown, OnStart, OnEnd, OnSuspend and OnResume
-- are optional.
KIND.Folder = "bot_behaviors"
KIND.Global = "BEHAVIOR"
KIND.Subscribe = "never"
KIND.Required = { Rank = "function", Weight = "function", Update = "function" }
