---@meta
-- Optional addon API. Source files, not successful API registration, establish installation in tests.

---Either a human player or a managed player bot can hold either role.
---@alias PW.InfectionRole "survivor"|"infected"

---Pure addon rules, keyed by stable round identity (not entity indices). No round loop lives here.
---@class PW.InfectionParticipant
---@field id string
---@field bot boolean
---@field life integer

---@class PW.InfectionLife : PW.InfectionParticipant
---@field role PW.InfectionRole
---@field initial boolean
---@field present boolean
---@field converted boolean
---@field alive boolean
---@field deadLife? integer death callback deduplication, independent of actor type
---@field won? boolean sealed at the round outcome, never retroactive for converted players

---@class PW.InfectionRound
---@field players table<string, PW.InfectionLife>
---@field deadline number
---@field winner? PW.InfectionRole immutable once decided

---@class PW.InfectionStanding
---@field id string
---@field score integer

---@class PW.InfectionSummary
---@field reason string
---@field teams boolean
---@field draw boolean
---@field winner? string
---@field standings PW.InfectionStanding[]

---@class PW.InfectionRulesLib
---@field PickSeed fun(players: PW.InfectionParticipant[], previous: string?, rng: fun(): number): string?
---@field NewRound fun(players: PW.InfectionParticipant[], seed: string, deadline: number): PW.InfectionRound?, string?
---@field Death fun(round: PW.InfectionRound, id: string, life: integer, now: number): boolean
---@field Disconnect fun(round: PW.InfectionRound, id: string, now: number)
---@field Admit fun(round: PW.InfectionRound, player: PW.InfectionParticipant): boolean
---@field Winner fun(round: PW.InfectionRound, now: number): PW.InfectionRole?
---@field Summary fun(rounds: PW.InfectionRound[]): PW.InfectionSummary

---@class PW
---@field InfectionRules? PW.InfectionRulesLib optional addon; declaration is not an implementation

---@class PW.InfectionSnapshot
---@field revision integer
---@field round integer
---@field survivors integer
---@field infected integer
---@field deadline number
---@field role PW.InfectionRole|"waiting"
---@field personalWins integer
---@field active? boolean false is a revisioned cleanup tombstone
---@field intermission? boolean
---@field infections? integer informational only

---@class PW.InfectionPresentationLib
---@field Accept fun(current: PW.InfectionSnapshot?, incoming: table<string, any>): PW.InfectionSnapshot?
---@field Model fun(snapshot: PW.InfectionSnapshot, now: number): table<string, any>
---@field Encode fun(writer: PW.InfectionWriter, incoming: table<string, any>): boolean validate before any write
---@field Decode fun(reader: PW.InfectionReader): table<string, any>
---@field Results fun(rows: PW.InfectionResultRow[], ownId: integer): PW.InfectionResultModel?
---@field ResultChunk fun(current: PW.InfectionResultAssembly?, incoming: PW.InfectionResultChunk):
---    PW.InfectionResultAssembly?, PW.InfectionTerminal?
---@field EncodeResults fun(writer: PW.InfectionResultWriter, chunk: PW.InfectionResultChunk): boolean
---@field DecodeResults fun(reader: PW.InfectionResultReader): PW.InfectionResultChunk
---@field ApplyPostmatch fun(data: PW.UIPostmatchData, terminal: PW.InfectionTerminal, ownId: integer)

---@class PW.InfectionResultRow
---@field id integer public session UserID, not an engine entity
---@field name string
---@field wins integer
---@field infections? integer informational, never a rank tiebreaker
---@field place? integer output only
---@field bot? boolean
---@field kills? integer
---@field deaths? integer

---@class PW.InfectionTerminal
---@field revision integer
---@field active boolean
---@field ownId integer authoritative association to a participant row; 0 for an unadmitted late viewer
---@field rows PW.InfectionResultRow[] includes departed participants, never entities or SteamIDs

---@class PW.InfectionResultChunk : PW.InfectionTerminal
---@field total? integer total rows in this revision, maximum 4096
---@field offset? integer zero-based position of this bounded chunk, maximum 64 rows per packet

---@class PW.InfectionResultAssembly : PW.InfectionTerminal
---@field total integer
---@field seen table<integer, boolean>

---@class PW.InfectionResultWriter : PW.InfectionWriter
---@field string fun(value: string)

---@class PW.InfectionResultReader : PW.InfectionReader
---@field string fun(): string

---@class PW.InfectionResultCache
---@field revision integer
---@field rows PW.InfectionResultRow[]
---@field identities table<string, integer> server-only recipient association, never serialized

---@class PW.InfectionResultModel
---@field rows PW.InfectionResultRow[] sorted by wins with shared places
---@field personalWins integer
---@field place? integer
---@field draw boolean
---@field winner? integer

---@class PW.InfectionWriter
---@field uint fun(value: integer, bits: integer)
---@field bool fun(value: boolean)
---@field float fun(value: number)

---@class PW.InfectionReader
---@field uint fun(bits: integer): integer
---@field bool fun(): boolean
---@field float fun(): number

---@class PW
---@field InfectionPresentation? PW.InfectionPresentationLib optional addon presentation reducer

---@class PW.InfectionPursuitPlan
---@field sprint boolean
---@field forward number
---@field point? Vector only a legal contact's last observed point
---@field target? Entity

---@class PW.InfectionAILib
---@field Contact fun(contacts: PW.BotContact[]): PW.BotContact?
---@field Plan fun(pos: Vector, contact: PW.BotContact, walkSpeed: number): PW.InfectionPursuitPlan

---@class PW.InfectionState
---@field mode PW.RoundBase
---@field current? PW.InfectionRound
---@field completed PW.InfectionRound[]
---@field actors table<string, Player> current admitted identity -> entity
---@field identities table<Player, string> entity -> admitted identity, weak keys
---@field lives table<Player, integer> per-entity new-life generation, weak keys
---@field history table<string, Player> last entity of each participant for final standings
---@field userIds table<string, integer> safe result identity for departed participants
---@field metadata? table<string, PW.InfectionResultRow> copied public identity/stat metadata for departed rows
---@field deathBaselines? table<string, integer>
---@field infections table<string, integer> informational counters, never score events
---@field previous? string previous seed identity
---@field round integer
---@field playing boolean
---@field credited boolean round was added to completed once
---@field zombie boolean false after an installed animation compatibility failure

---@class PW.InfectionMode : PW.RoundBase
---@field Start fun(self: PW.InfectionMode)
---@field Think fun(self: PW.InfectionMode)
---@field Cleanup fun(self: PW.InfectionMode)
---@field _Rounds? PW.RoundState
---@field PW_CanRespawn fun(self: PW.InfectionMode, ply: Player): boolean
---@field PW_CanRunBotInput fun(self: PW.InfectionMode, ply: Player): boolean
---@field PW_PlayerLoadout fun(self: PW.InfectionMode, ply: Player): PW.Loadout?
---@field PW_PlayerOverrides fun(self: PW.InfectionMode, ply: Player): PW.PlayerOverrideProfile?
---@field PW_PlayerModelOverride fun(self: PW.InfectionMode, ply: Player): string?
---@field PW_PhaseChange fun(self: PW.InfectionMode, phase: PW.PhaseName)

---@class PW.InfectionLib
---@field State? PW.InfectionState server-owned, read-only to consumers
---@field View? PW.InfectionSnapshot client-owned accepted snapshot
---@field Revision integer persistent monotonic outgoing revision
---@field ResultRevision? integer separate persistent monotonic terminal generation
---@field ResultCache? PW.InfectionResultCache server-owned terminal data until leaving POSTMATCH
---@field Terminal? PW.InfectionTerminal client accepted complete terminal snapshot only
---@field Assembly? PW.InfectionResultAssembly client partial bounded receive state
---@field ResetResults fun()
---@field PublishResults fun(summary: PW.InfectionSummary)
---@field SendResults fun(ply: Player)
---@field Identity fun(ply: Player): string
---@field Role fun(ply: Player): PW.InfectionRole?
---@field Active fun(): boolean
---@field Start fun(mode: PW.RoundBase): boolean
---@field Prepare fun(round: integer)
---@field Spawned fun(ply: Player)
---@field Death fun(victim: Player, attacker: Entity)
---@field Disconnect fun(ply: Player)
---@field EndRound fun()
---@field Clear fun()
---@field Snapshot fun(ply: Player): PW.InfectionSnapshot?
---@field Publish fun()
---@field Result fun(): PW.MatchResult

---@class PW
---@field InfectionAI? PW.InfectionAILib
---@field Infection? PW.InfectionLib
