-- The playlists kind (02-modes.md d.2; 01-extensibility.md d.12, d.16; docs/api/modes.md "Playlists"). One data file
-- per playlist in lua/privatewar/playlists/ with a PLAYLIST table. Never auto-subscribed (d.18).
-- Name is required here; the playlists owner validates the static/callable Modes, Maps and Settings union.
-- Maps (nil = every map that fits the modes) and Settings
-- are optional. Per-entry ConVar: pw_playlist_<id>_enabled (d.11). The playlists module (modules/playlists)
-- validates the rest of the fields, because it needs the settings schema and the modes registry.
KIND.Folder = "playlists"
KIND.Global = "PLAYLIST"
KIND.Subscribe = "never"
KIND.Required = { Name = "string" }
