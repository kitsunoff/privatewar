-- The maps kind (03-mapdata.md d.2; 01-extensibility.md d.16; docs/api/map.md). One data file per map in
-- lua/privatewar/maps/ with a MAP table (Spawns, Modes). The id is the map name normalised by PW.Map.Id
-- (lowercase, characters outside [a-z0-9_] replaced by "_"). Never auto-subscribed (d.18): map data is data. No
-- required fields: map data is optional (03-mapdata.md d.1). Per-entry ConVar: pw_map_<id>_enabled (d.11).
KIND.Folder = "maps"
KIND.Global = "MAP"
KIND.Subscribe = "never"
