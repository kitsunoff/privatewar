---@meta
-- Frozen Hardpoint contract declarations only; no runtime implementation or observed runtime RED yet.
-- Contract and approved preset: docs/api/hardpoint.md.

---@class PW.HardpointZone
---@field id string unique nonempty authored id, at most 32 bytes; array order is the rotation order
---@field pos Vector finite centre; synthetic positions in tests are not map content
---@field radius number finite, positive horizontal radius, at most 4096
---@field below number finite, nonnegative distance below pos.z; above + below at most 2048
---@field above number finite, positive distance above pos.z; above + below at most 2048

---@class PW.HardpointLayout
---@field zones PW.HardpointZone[] dense ordered array, 2..16 zones

---@class PW.HardpointActor
---@field team integer
---@field pos Vector
---@field alive boolean
---@field observer boolean
---@field eligible boolean roster participant only; never excludes god mode or spawn-protected participants

---@class PW.HardpointPresence
---@field control integer 0 empty or contested; otherwise the exclusively present team
---@field contested boolean any eligible opposing occupancy, including unequal counts

---@class PW.HardpointRules
---@field pointTime number finite 5..600 seconds, configurable default 60
---@field scoreLimit integer finite 1..1000 points, configurable default 250
---@field matchTime number finite 60..3600 seconds, configurable default 600

---@class PW.HardpointState
---@field layout PW.HardpointLayout
---@field rules PW.HardpointRules
---@field startedAt number
---@field matchEndsAt number
---@field lastAt? number
---@field fraction number
---@field control integer
---@field contested boolean
---@field effects? PW.HardpointEffects
---@field generation integer match generation
---@field visit integer monotonic visit, not merely the repeating zone id
---@field index integer active authored zone index
---@field zoneEndsAt number absolute deadline
---@field scores table<integer, integer> separate from personal XP and scorestreak progress
---@field finished boolean terminal latch

---@class PW.HardpointSample
---@field at number authoritative sample time
---@field actors PW.HardpointActor[] server-only input, never a snapshot field

---@class PW.HardpointEffects
---@field rotated boolean
---@field finish? PW.MatchResult emitted at most once

---@class PW.HardpointSnapshot
---@field generation integer
---@field revision integer monotonic within a match, including cleanup tombstones
---@field visit integer
---@field active boolean false invalidates old public state
---@field zone PW.HardpointZone public static geometry only
---@field zoneEndsAt number
---@field matchEndsAt number distinct match clock
---@field control integer
---@field contested boolean
---@field scores table<integer, integer>

---@class PW.HardpointView
---@field zoneId string
---@field zoneRemaining number
---@field matchRemaining number

---@class PW.HardpointLib
---@field Inside fun(zone: PW.HardpointZone, pos: Vector): boolean
---@field Presence fun(zone: PW.HardpointZone, actors: PW.HardpointActor[]): PW.HardpointPresence
---@field ScoreDelta fun(presence: PW.HardpointPresence, points: integer): table<integer, integer>
---@field ValidateLayout fun(data: any): boolean, string?
---@field VisitAt fun(startedAt: number, now: number, pointTime: number, count: integer): integer, integer, number
---@field NewState fun(layout: PW.HardpointLayout, rules: PW.HardpointRules,
---    startedAt: number, generation: integer): PW.HardpointState
---@field Step fun(state: PW.HardpointState, sample: PW.HardpointSample): PW.HardpointEffects
---@field ArrivalFits fun(zone: PW.HardpointZone, projected: Vector, arrivalRadius: number): boolean
---@field PublicSnapshot fun(state: PW.HardpointState, revision: integer): PW.HardpointSnapshot
---@field AcceptSnapshot fun(current: PW.HardpointSnapshot?, incoming: PW.HardpointSnapshot): PW.HardpointSnapshot
---@field View fun(snapshot: PW.HardpointSnapshot, now: number, out: PW.HardpointView): PW.HardpointView
---@field ValidateActivation fun(layout: PW.HardpointLayout,
---    probe: fun(zone: PW.HardpointZone): boolean): boolean, string?
---@field CheckActivation fun(layout: PW.HardpointLayout): boolean, string?
---@field WriteSnapshot fun(snapshot: PW.HardpointSnapshot)
---@field ReadSnapshot fun(): PW.HardpointSnapshot

---@class PW
---@field Hardpoint? PW.HardpointLib optional module; deliberately absent until observed RED
