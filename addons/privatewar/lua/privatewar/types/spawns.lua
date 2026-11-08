---@meta
-- Types of the spawns module (T-2.9; 03-mapdata.md d.7; docs/api/map.md). Source: lua/privatewar/modules/spawns/
-- (shared.lua: API, pure scoring and protection rules; init.lua: server glue, traces and engine hooks).

---A living player as plain data for scoring: feet position, eye position and view direction.
---@class PW.SpawnActor
---@field pos Vector feet position
---@field eye? Vector eye position (line of sight traces start here); pos + 64 units up when nil
---@field dir? Vector view direction (unit vector); nil: never counts as facing a point

---One spawn candidate. visible and jitter are filled by the glue before scoring.
---@class PW.SpawnCandidate
---@field pos Vector
---@field yaw number
---@field key string identity of the point for the recently used memory (PW.Spawns._Key)
---@field jitter? number small random bonus, 0 when nil
---@field visible? boolean an enemy has line of sight to the point; nil or false: none

---Plain input of the scoring.
---@class PW.SpawnContext
---@field enemies PW.SpawnActor[]
---@field mates PW.SpawnActor[]
---@field teamBonus boolean whether nearby teammates add to the score (team modes only)
---@field now number CurTime() of the pick
---@field used table<string, number> CurTime() at which each point (by key) was last picked
---@field weights? PW.SpawnWeights PW.Spawns.Weights when nil

---Gameplay values of the scoring (03-mapdata.md d.7). Distances in Hammer units, times in seconds.
---@class PW.SpawnWeights
---@field distCap number distance to the nearest enemy counts up to this value (also the value without enemies)
---@field los number penalty when an enemy has line of sight to the point
---@field losFacing number extra penalty when the point is visible and an enemy looks toward it
---@field facingCos number cosine of the half angle of "looks toward"
---@field mateRadius number a teammate within this distance counts as nearby
---@field mate number bonus per nearby teammate (team modes only)
---@field mateMax integer at most this many teammates count
---@field recent number penalty of a point picked just now; falls linearly to 0 over recentWindow
---@field recentWindow number
---@field jitter number upper bound of the random bonus
---@field eyeHeight number height above a point at which line of sight is checked

---Cost limits of one pick (per respawn, 03-mapdata.md d.7).
---@class PW.SpawnBudget
---@field sample integer candidates drawn at random from the pool
---@field maxEnemies integer nearest enemies considered (scoring and line of sight)
---@field maxTraces integer line of sight traces per pick; past it a candidate counts as seen
---@field maxMs number time limit of one pick in the in-game measurement

---Engine checks of a candidate, injected into PW.Spawns._Choose (the glue does traces, tests use fakes).
---@class PW.SpawnProbe
---@field clear fun(c: PW.SpawnCandidate): boolean a standing player hull fits at the point
---@field sees fun(c: PW.SpawnCandidate): boolean an enemy has line of sight to the point

---Options of PW.Spawns.Pick. Every field is optional; defaults come from the active mode and the match state.
---@class PW.SpawnPickOpts
---@field all? boolean use every point of the map; default: true for respawns and in modes without teams
---@field first? boolean first spawn of the match (team zone); default: the player has not spawned during LIVE
---@field teamBonus? boolean reward nearby teammates; default: the active mode has teams (FFA: false)
---@field sample? integer candidates to evaluate; default Budget.sample
---@field enemies? PW.SpawnActor[] instead of the living enemies of the player (measurement, tests)
---@field mates? PW.SpawnActor[] instead of the living teammates of the player
---@field spawns? PW.MapSpawns authored side-indexed pool instead of the ordinary whole-map spawn source

---Random integer in m..n (the signature of math.random(m, n)).
---@alias PW.SpawnRand fun(m: integer, n: integer): integer

---Cost of the last pick, for measurement.
---@class PW.SpawnStats
---@field candidates integer sampled candidates
---@field probed integer candidates checked with traces
---@field traces integer hull and line of sight traces
---@field ms number wall time of the pick

---Internal (server): state of the spawns module.
---@class PW.SpawnsStore
---@field used table<string, number> CurTime() of the last pick by point key
---@field spawned table<any, true> players that spawned during this LIVE
---@field protect table<any, number> CurTime() at which spawn protection ends, by player
---@field stats? PW.SpawnStats

---Spawn selection and spawn protection (T-2.9; 03-mapdata.md d.7).
---@class PW.SpawnsLib
---Server: the best free spawn point for ply, or nil when the map has no point or every sampled point is blocked
---(the base gamemode then chooses). Remembers the point as recently used.
---@field Pick? fun(ply: Player, opts?: PW.SpawnPickOpts): PW.SpawnPoint?
---CurTime() at which the spawn protection of ply ends, 0 without protection. Shared (NW2).
---@field ProtectedUntil fun(ply: Player): number
---@field Weights PW.SpawnWeights
---@field Budget PW.SpawnBudget
---Internal, pure: the score of one candidate.
---@field _Score fun(c: PW.SpawnCandidate, ctx: PW.SpawnContext): number
---Internal, pure over the probe: the best candidate that is not hull-blocked; probes candidates best first and
---stops once no remaining candidate can beat the best one. Sets c.visible on probed candidates.
---@field _Choose fun(cands: PW.SpawnCandidate[], ctx: PW.SpawnContext, probe: PW.SpawnProbe): PW.SpawnCandidate?
---Internal, pure: candidates of a team: its own points plus any-team points, or every point when all is true or
---the team has no points.
---@field _Pool fun(spawns: PW.MapSpawns, team: integer, all: boolean): PW.SpawnCandidate[]
---Internal, pure: at most n distinct entries of list drawn with rand (math.random signature); list is not changed.
---@field _Sample fun(list: PW.SpawnCandidate[], n: integer, rand: PW.SpawnRand): PW.SpawnCandidate[]
---Internal, pure: the key of a point position.
---@field _Key fun(pos: Vector): string
---Internal, pure: end time of protection for a spawn at now, nil when seconds is 0 or less.
---@field _ProtectUntil fun(now: number, seconds: number): number?
---Internal, pure: whether protection ending at untilTime is active at now.
---@field _Protected fun(untilTime: number?, now: number): boolean
---Internal: the spawns.protection setting of the current match, in seconds (tests swap it).
---@field _ProtectionTime fun(): number
---Internal (server): whether a standing player hull fits at pos; filter is ignored by the trace.
---@field _HullClear? fun(pos: Vector, filter: Entity?): boolean
---Internal: NW2 key of the protection end time.
---@field _ProtectKey string
---Internal: a fresh store (tests swap PW._Spawns).
---@field _NewStore fun(): PW.SpawnsStore

---@class PW
---@field Spawns? PW.SpawnsLib the spawns module (nil when the module is missing)
---@field _Spawns PW.SpawnsStore internal
