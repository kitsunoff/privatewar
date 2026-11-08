---@meta
-- Frozen authored S&D map schema. No implicit gameplay dimensions or map fallback.

---@class PW.SNDSite
---@field id string unique stable site id
---@field pos Vector finite marker/plant-cylinder center
---@field radius number finite positive horizontal plant radius
---@field above number finite nonnegative upper plant bound relative to pos.z
---@field below number finite nonnegative lower plant bound relative to pos.z
---@field approach Vector finite reachable plant approach inside the cylinder

---@class PW.SNDMapData
---@field sites PW.SNDSite[] authored sites; approved first layout has two
---@field bomb Vector finite authored initial/recovery ground point
---@field spawns table<integer, PW.SpawnPoint[]> side-indexed authored round spawns, not player cohort ids

---@class PW.SNDActor
---@field id string stable session identity (SteamID64 for humans, session UserID for bots)
---@field userId integer current connection identity
---@field team integer side
---@field alive boolean
---@field pos Vector
---@field use boolean
---@field clear boolean authoritative interaction line of sight
---@field generation integer

---@class PW.SNDParticipant
---@field userId integer
---@field team integer
---@field alive boolean
---@field connected boolean
---@field spawned boolean

---@class PW.SNDInteraction
---@field id string
---@field userId integer
---@field generation integer
---@field action string
---@field site string
---@field at number

---@class PW.SNDState
---@field generation integer
---@field deadline number
---@field map PW.SNDMapData
---@field roster table<string, PW.SNDParticipant>
---@field phase "carried"|"dropped"|"planted"|"resolved"
---@field carrier? string
---@field pos Vector
---@field site? string
---@field fuse number
---@field interaction? PW.SNDInteraction
---@field winner? integer|false

---@class PW.SNDSnapshot
---@field generation integer
---@field phase string
---@field deadline number
---@field fuse number
---@field site? string
---@field carrier? integer attacker-only UserID
---@field pos? Vector attacker drop or globally public planted bomb
---@field action? string local interaction only
---@field progress number bounded local progress

---@class PW.SNDLib
---@field Validate fun(data: any): boolean, string?
---@field Inside fun(site: PW.SNDSite|PW.BotObjectiveZone, pos: Vector): boolean
---@field NewRound fun(map: PW.SNDMapData, actors: PW.SNDActor[], now: number, generation: integer,
---    carrierId: string?): PW.SNDState
---@field Step fun(state: PW.SNDState, now: number, actors: PW.SNDActor[]): integer|false|nil, boolean
---@field Death fun(state: PW.SNDState, id: string, userId: integer, pos: Vector, now: number): boolean
---@field Disconnect fun(state: PW.SNDState, id: string, userId: integer, pos: Vector, now: number): boolean
---@field Admit fun(state: PW.SNDState, id: string, userId: integer): boolean
---@field Snapshot fun(state: PW.SNDState, viewerTeam: integer, viewerId: string, now: number): PW.SNDSnapshot
---@field Objectives fun(state: PW.SNDState, team: integer): PW.BotObjective[]
---@field Identity fun(ply: Player): string server: stable human/session bot identity
---@field NextGeneration fun(): integer server: fresh monotonic round identity
---@field Roster fun(): PW.SNDActor[] server: next-round admitted participants and planned sides
---@field AdmitRoster fun(state: PW.SNDState) server: release held participants and request owner placement
---@field Actors fun(state: PW.SNDState): PW.SNDActor[] server: authoritative current input/geometry samples
---@field Activate fun(map: PW.SNDMapData) server: validate current-world floor, hull and mutual nav routes
---@field Invalidate fun(state: PW.SNDState) server: synchronously release old objective inputs/orders
---@field DropPoint fun(state: PW.SNDState, ply: Player): Vector server: usable ground or authored recovery
---@field Physical fun(state: PW.SNDState) server: one ordinary-sight bomb prop
---@field Clear fun() server: remove owned prop and clear presentation
---@field Publish fun(state: PW.SNDState?, force?: boolean) server: recipient-specific bounded snapshots
---@field View fun(): PW.SNDSnapshot? client: current active snapshot only
---@field Display fun(): PW.SNDDisplay? client: cached draw-ready model, no HUDPaint allocations
---@field HudText fun(view: PW.SNDSnapshot, now: number): string, string shared: draw-independent labels

---@class PW.SNDMarker
---@field x number
---@field y number
---@field text string
---@field visible boolean

---@class PW.SNDDisplay
---@field title string
---@field line string
---@field progress number
---@field markers PW.SNDMarker[]

---@class PW.SNDStore
---@field generation integer
---@field serial integer
---@field nextSnapshot number
---@field bomb? Entity

---@class PW
---@field SND? PW.SNDLib
---@field _SND PW.SNDStore internal server-only S&D engine resources

---@class PW.SNDMode: PW.Mode
---@field _SND? PW.SNDState
---@field _Rounds? PW.RoundState
---@field PW_CanJoinInProgress fun(self: PW.SNDMode): boolean
---@field PW_CanRespawn fun(self: PW.SNDMode): boolean
---@field PW_CanTakeDamage fun(self: PW.SNDMode, victim?: Player, attacker?: Entity): boolean?
---@field PW_CanRunBotBehavior fun(self: PW.SNDMode): boolean
---@field PW_CanUseLoadoutKind fun(self: PW.SNDMode): boolean
