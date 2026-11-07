---@meta
-- Frozen authored S&D map schema. No implicit gameplay dimensions or map fallback.

---@class PW.SNDSite
---@field id string unique stable site id
---@field pos Vector finite marker/plant-cylinder center
---@field radius number finite positive horizontal plant radius
---@field above number finite nonnegative upper plant bound relative to pos.z
---@field below number finite nonnegative lower plant bound relative to pos.z
---@field approach Vector finite reachable plant approach inside the cylinder

---@class PW.SNDMapData
---@field sites PW.SNDSite[] authored sites; approved first layout has two
---@field bomb Vector finite authored initial/recovery ground point
---@field spawns table<integer, PW.SpawnPoint[]> side-indexed authored round spawns, not player cohort ids
