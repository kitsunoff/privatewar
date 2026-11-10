---@meta

---@alias PW.MapReadinessState "pending"|"ready"|"rejected"

---@class PW.MapModeReadiness
---@field state PW.MapReadinessState
---@field reason? string bounded player-safe reason
---@field source? string authored or generated when ready

---@class PW.Mode
---@field MapReadiness? boolean activation requires current-map readiness, inherited by children
