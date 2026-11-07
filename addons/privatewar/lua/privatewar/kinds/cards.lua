-- The cards kind (06-progression.md d.6; 01-extensibility.md d.12, d.16). One data file per calling card in
-- lua/privatewar/cards/ with a CARD table: Name and Material (the material path) are required; Price, Unlock (player
-- level), Rarity and Description are optional. A card with a Price and no Unlock is for sale only. Data only, never
-- auto-subscribed (d.18). Per-card ConVar: pw_card_<id>_enabled (d.11).
KIND.Folder = "cards"
KIND.Global = "CARD"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", Material = "string" }
