-- The bundles kind (06-progression.md d.6; 01-extensibility.md d.12, d.16). One data file per shop bundle in
-- lua/privatewar/bundles/ with a BUNDLE table: Name, Price (whole currency above 0) and Items (a list of { kind, id },
-- or { kind = "camos", weapon, id }) are required; Rarity and Description are optional. A bundle with an item that does
-- not resolve is not offered. Bundles are sold only while the date-seeded rotation features them (the economy module).
-- Data only, never auto-subscribed (d.18). Per-bundle ConVar: pw_bundle_<id>_enabled (d.11).
KIND.Folder = "bundles"
KIND.Global = "BUNDLE"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", Price = "number", Items = "table" }
