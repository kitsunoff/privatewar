-- The models kind (06-progression.md d.6; 01-extensibility.md d.12, d.16). One data file per playermodel ("operator")
-- in lua/privatewar/models/ with a MODEL table: Name and Model (the model path) are required; Price, Unlock (player
-- level), Rarity and Description are optional. A model with a Price and no Unlock is for sale only. Data only, never
-- auto-subscribed (d.18). Per-model ConVar: pw_model_<id>_enabled (d.11).
KIND.Folder = "models"
KIND.Global = "MODEL"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", Model = "string" }
