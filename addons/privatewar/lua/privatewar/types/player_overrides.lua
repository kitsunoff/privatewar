---@meta
-- Frozen contract declarations only. Implementation must follow observed game RED.

---@class PW.PlayerOverrideProfile
---@field maxHealth? number finite positive maximum
---@field spawnHealth? number finite positive, at most maxHealth; only once on a new life
---@field walkSpeedMult? number finite positive, relative to ordinary postspawn baseline
---@field runSpeedMult? number finite positive, relative to ordinary postspawn baseline

---@alias PW.PlayerOverridesQuestion fun(ply: Player): PW.PlayerOverrideProfile?
---@alias PW.PlayerModelOverrideQuestion fun(ply: Player): string?

---@class PW.PlayerOverridesLib
---Validate the complete profile before mutation. Repeated refresh never heals or compounds speed.
---@field Refresh fun(ply: Player): boolean, string?
---Restore baseline maximum and speeds; living current HP clamps down only, dead players never revive.
---@field Release fun(ply: Player): boolean

---@class PW
---@field PlayerOverrides? PW.PlayerOverridesLib nil when the generic module is absent
