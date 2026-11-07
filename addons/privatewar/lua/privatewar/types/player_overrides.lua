---@meta

---@class PW.PlayerOverrideProfile
---@field maxHealth? number finite positive maximum
---@field spawnHealth? number finite positive, at most maxHealth; only once on a new life
---@field walkSpeedMult? number finite positive, relative to ordinary postspawn baseline
---@field runSpeedMult? number finite positive, relative to ordinary postspawn baseline

---@alias PW.PlayerOverridesQuestion fun(ply: Player): PW.PlayerOverrideProfile?
---@alias PW.PlayerStatsChangedNotification fun(ply: Player)
---@alias PW.FallDamageBaselineQuestion fun(ply: Player, speed: number): number?
---@alias PW.PlayerModelOverrideQuestion fun(ply: Player): string?

---@class PW.PlayerOverrideBaseline
---@field max number ordinary maximum for this life
---@field walk number ordinary walk speed for this life
---@field run number ordinary run speed for this life

---@class PW.PlayerOverridesLib
---Validate the complete profile before mutation. Repeated refresh never heals or compounds speed.
---@field Refresh fun(ply: Player): boolean, string?
---Restore baseline maximum and speeds; living current HP clamps down only, dead players never revive.
---@field Release fun(ply: Player): boolean

---@class PW
---@field PlayerOverrides? PW.PlayerOverridesLib nil when the generic module is absent
---@field _PlayerOverrideBaselines table<Player, PW.PlayerOverrideBaseline>? internal, retained across reload
