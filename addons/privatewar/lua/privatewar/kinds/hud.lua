-- The hud kind (09-hud.md d.3; 01-extensibility.md d.12, d.16). One file per element in lua/privatewar/hud/ with a
-- HUDELEMENT table: Draw (required), Order, Phases, ShouldDraw. Never auto-subscribed (d.18): the single HUDPaint of
-- the hud module iterates the registry and calls Draw through PW.Call. Per-element ConVar:
-- pw_hudelement_<id>_enabled (d.11).
KIND.Folder = "hud"
KIND.Global = "HUDELEMENT"
KIND.Subscribe = "never"
KIND.Required = { Draw = "function" }
