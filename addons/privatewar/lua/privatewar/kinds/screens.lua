-- The screens kind (10-frontend.md d.1; 01-extensibility.md d.12, d.16). One file per screen in
-- lua/privatewar/screens/ with a SCREEN table: Tab (the hub tab it belongs to), Build (required), Root (the screen
-- is the root of its tab), Order, Title. Never auto-subscribed (d.18): the ui_kit router calls Build through PW.Call.
-- Per-entry ConVar: pw_screen_<id>_enabled (d.11).
KIND.Folder = "screens"
KIND.Global = "SCREEN"
KIND.Subscribe = "never"
KIND.Required = { Build = "function", Tab = "string" }
