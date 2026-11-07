---@meta
-- DRAFT contract declarations only; no runtime implementation. Approved preset is in docs/api/hardpoint.md.
-- Review docs/api/hardpoint.md before implementing or consuming this proposed surface.

---@class PW.HardpointZone
---@field id string unique authored id; array order is the proposed rotation order
---@field pos Vector finite centre; synthetic positions in tests are not map content
---@field radius number finite, positive horizontal radius
---@field below number finite, nonnegative distance below pos.z
---@field above number finite, positive distance above pos.z

---@class PW.HardpointLayout
---@field zones PW.HardpointZone[] dense ordered array

---@class PW.HardpointLayoutLimits
---@field minZones integer required approved minimum, not a default
---@field maxZones integer codec/authoring bound requiring contract review
---@field maxIdBytes integer codec bound requiring contract review
---@field maxRadius number authoring bound requiring contract review
---@field maxHeight number authoring bound requiring contract review

---@class PW.HardpointActor
---@field team integer
---@field pos Vector
---@field alive boolean
---@field observer boolean
---@field eligible boolean upstream membership/protection decision, not an inferred default

---@class PW.HardpointPresence
---@field control integer 0 empty or contested; otherwise the exclusively present team
---@field contested boolean any eligible opposing occupancy, including unequal counts

---@class PW.HardpointRules
---@field pointTime number required, positive; approved configurable default 60 seconds
---@field tickInterval number required, positive; approved scoring cadence 1 second
---@field tickPoints integer required, positive; approved 1 point per scoring second
---@field scoreLimit integer required; approved configurable default 250, zero semantics still need approval
---@field matchTime number required; approved configurable default 600 seconds, zero semantics still need approval
---@field maxSampleGap number required scoring freshness bound, no catch-up from current presence
---@field rotationBoundary "exclude"|"include_old" test policy alternatives, not shipped settings
---@field deadlineBoundary "exclude"|"include" test policy alternatives, not shipped settings
---@field limitPrecedence "score"|"time" required exact-time arbitration
---@field tieWinner fun(scores: table<integer, integer>): integer? equal final scores must return nil (draw)

---@class PW.HardpointState
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
---@field ValidateLayout fun(data: any, limits: PW.HardpointLayoutLimits): boolean, string?
---@field VisitAt fun(startedAt: number, now: number, pointTime: number, count: integer): integer, integer, number
---@field NewState fun(layout: PW.HardpointLayout, rules: PW.HardpointRules,
---    startedAt: number, generation: integer): PW.HardpointState
---@field Step fun(state: PW.HardpointState, sample: PW.HardpointSample): PW.HardpointEffects
---@field ArrivalFits fun(zone: PW.HardpointZone, projected: Vector, arrivalRadius: number): boolean
---@field PublicSnapshot fun(state: PW.HardpointState, revision: integer): PW.HardpointSnapshot
---@field AcceptSnapshot fun(current: PW.HardpointSnapshot?, incoming: PW.HardpointSnapshot): PW.HardpointSnapshot
---@field View fun(snapshot: PW.HardpointSnapshot, now: number, out: PW.HardpointView): PW.HardpointView

---@class PW
---@field Hardpoint? PW.HardpointLib proposed optional module; deliberately absent in phase 1
