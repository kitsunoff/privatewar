---@meta
-- Frozen optional spectator restriction. Server-only policy; no client target-request channel.

---@class PW.SpectatorPolicy
---@field restricted true any malformed non-nil policy fails closed to a fixed view
---@field eligible table<integer, boolean> current connection UserID allow-set; empty means fixed neutral view

---@class PW.SpectatorCandidate
---@field id integer
---@field alive boolean

---@alias PW.SpectatorPolicyHook fun(ply: Player): PW.SpectatorPolicy?

---@class PW.JipLib
---@field SpectatorChoice? fun(policy: any, candidates: PW.SpectatorCandidate[], currentId?: integer):
---    "roaming"|"fixed"|"follow", integer?
---@field RefreshSpectator? fun(ply: Player): boolean server owner: apply optional restricted camera synchronously

---@class PW.SNDMode
---@field PW_SpectatorPolicy fun(self: PW.SNDMode, ply: Player): PW.SpectatorPolicy?
