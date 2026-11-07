-- The score_events kind (06-progression.md d.3; 01-extensibility.md d.12, d.16). One file per event in
-- lua/privatewar/score_events/ with an EVENT table: the single source of match score, XP and streak progress.
-- Medals are events with Medal = true (there is no medals kind). Data only, never auto-subscribed (d.18). Per-event
-- ConVar: pw_event_<id>_enabled (d.11). Name and Points are required; XP (nil = same as Points), Medal and Currency
-- are optional.
KIND.Folder = "score_events"
KIND.Global = "EVENT"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", Points = "number" }
