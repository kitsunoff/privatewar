---@meta

---@alias PW.MapReadinessState "pending"|"ready"|"rejected"

---@class PW.MapModeReadiness
---@field state PW.MapReadinessState
---@field reason? string bounded player-safe reason
---@field source? string authored or generated when ready

---@class PW.Mode
---@field MapReadiness? boolean activation requires current-map readiness, inherited by children

---@class PW.MapModeAvailability
---@field fits boolean eligibility only; never a playable-start guarantee
---@field classification? string authored, provisional or generated, matching ModeFits
---@field readiness? PW.MapReadinessState current-map activation state only
---@field reason? string preserve this on rejected cards instead of discarding the picker entry
---@field canRetry boolean loaded S&D source may be explicitly retried; no automatic attempt is made
