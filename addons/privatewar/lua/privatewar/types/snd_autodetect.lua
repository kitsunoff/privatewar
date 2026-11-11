---@meta

---@class PW.SNDBombTarget: Entity
---@field pwSNDDisabled? boolean

---@class PW.SNDTarget
---@field mins Vector world-space bounds
---@field maxs Vector world-space bounds
---@field name string targetname, empty when unnamed
---@field disabled? boolean

---@class PW.SNDDeriveInput
---@field targets PW.SNDTarget[] at most 128
---@field spawns table<integer, PW.SpawnPoint[]> CS side pools only, at most 64 per side
---@field points Vector[] deterministic nav candidates, at most 4096
---@field safe fun(pos: Vector): boolean world/floor/hull/nav probe
---@field mutual fun(from: Vector, to: Vector): boolean directed routes in both directions

---@class PW.SNDLib
---@field CopyMap fun(data: PW.SNDMapData): PW.SNDMapData isolated layout and vectors; no engine/readiness queries
---@field PinMap fun(mode: table, data: PW.SNDMapData) copy and attach a validated preflight map before PREMATCH
---@field ReleaseMap fun(mode: table) clear only the accepted pin; safe before MODE:Start or after Cleanup
---@field PublicSites fun(raw: any): PW.SNDPublicSite[]? shared: bounded public presentation facts only
---@field GroupTargets fun(targets: PW.SNDTarget[]): PW.SNDTarget[][]?, string?
---@field SitesOverlap fun(a: PW.SNDSite, b: PW.SNDSite): boolean touching counts as ambiguous overlap
---@field Derive fun(input: PW.SNDDeriveInput): PW.SNDMapData?, string?
---@field Detect fun(): PW.SNDMapData?, string? server: inspect the loaded map, no persistent cache
---@field PrepareMap fun(modeId: string): PW.SNDMapData?, string? server: rederive/validate before start
---@field RetryMap fun(modeId: string): PW.SNDMapData?, string? server: explicit rejected-map retry, LOBBY/VOTE only
---@field _AutoSafe fun(pos: Vector): boolean
---@field _AutoMutual fun(from: Vector, to: Vector): boolean
---@field _ReadinessThink fun() server: one readiness resolution after entities/nav are available

---@class PW.SNDStore
---@field mapChecked? boolean current-map automatic preflight already attempted

---@class PW.SNDPublicSite
---@field id string
---@field pos Vector

---@class PW.SNDSnapshot
---@field sites? PW.SNDPublicSite[] exactly two public site markers

---@class PW.Mode
---@field MapCandidate? fun(self: PW.Mode, mapName: string): boolean shared provisional eligibility, never validation
