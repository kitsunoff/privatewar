---@meta

---@alias PW.StartContinuation fun(): boolean, string?
---@alias PW.Preflight fun(mode: table, map: string?, run: PW.StartContinuation): PW.MapReadinessState, PW.SNDMapData?

---@class PW.StartWait
---@field mode table
---@field map? string original requested target, never resampled
---@field current string loaded map when the request was made
---@field phase PW.PhaseName LOBBY or VOTE; no playable phase while waiting
---@field deadline number monotonic timeout, 120 seconds after the request
---@field prepared? boolean PrepareMap completed for the current nav readiness interval
---@field resume PW.StartContinuation exact request continuation, not a retry or a new vote
---@field accepted? boolean restored pending file already consumed its start entitlement
---@field applied? fun() pending-team notification only after PREMATCH was reached
---@field layout? PW.SNDMapData isolated validated snapshot carried only through the synchronous continuation

---@class PW.MatchLib
---@field _StartReason fun(reason: any): string bounded safe UTF-8, no control characters
---@field _RefuseStart fun(reason: string): boolean preflight refusal, does not spend lobby entitlement
---@field _RefusePhase fun(): boolean defer VOTE cancellation until the current transition finishes
---@field _StartPreflight PW.Preflight
---@field _PinStartMap fun(mode: table, data: PW.SNDMapData?): boolean commit the isolated layout before PREMATCH
---@field _ReleaseStartMap fun() discard an accepted pin on cancellation/completion, including PREMATCH abort
---@field _TickStart fun(): boolean true when this tick belongs to an outstanding preflight

---@class PW.LobbyLib
---@field _StartFailure fun(reason: string, ply?: Player) bounded server-to-client failure; nil broadcasts
