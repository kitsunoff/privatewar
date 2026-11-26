---@meta

---@alias PW.ChallengeTier "easy"|"medium"|"hard"
---@alias PW.ChallengeScope "cumulative"|"match"|"round"|"life"
---@alias PW.ChallengeCount 1|"value"
---@alias PW.ChallengeCombine "all"|"any"
---@alias PW.ChallengePool "weekly"|"none"
---@alias PW.ChallengeParamSource "categories"|"weapons"|"modes"|"playlists"
---@alias PW.ChallengeParams table<string, string>
---@alias PW.ChallengeValue string|number|boolean

---@class PW.ChallengeEvent
---@field type string
---@field player Player
---@field value number
---@field mode string
---@field modeBase string[]
---@field playlist string "" for Custom
---@field match integer
---@field week integer
---@field time number
---@field victim? Player
---@field victimBot? boolean
---@field weapon? string
---@field weaponCategory? string
---@field weaponKind? PW.WeaponKind
---@field attachments? table<string, boolean>
---@field headshot? boolean
---@field distance? number metres
---@field ads? boolean
---@field crouch? boolean
---@field airborne? boolean
---@field explosive? boolean
---@field streakKill? boolean
---@field streak? string
---@field lifeKills? integer
---@field aliveTime? number
---@field scoreEvent? string
---@field medal? string
---@field objective? string
---@field won? boolean
---@field draw? boolean
---@field placement? integer
---@field suicide? boolean
---@field data? table<string, PW.ChallengeValue>

---@class PW.ChallengeEventType
---@field fields? table<string, "string"|"number"|"boolean">
---@field label? string

---@class PW.ChallengeWindow
---@field count integer
---@field seconds number

---@class PW.ChallengeResetRule
---@field Event string
---@field Filters? table<string, any>

---@class PW.ChallengeObjective
---@field Event string|string[]
---@field Filters? table<string, any>
---@field Filter? fun(self: PW.Challenge, ev: PW.ChallengeEvent, params: PW.ChallengeParams): boolean?
---@field Count? PW.ChallengeCount
---@field Scope? PW.ChallengeScope
---@field Target integer|table<PW.ChallengeTier, integer>
---@field Within? PW.ChallengeWindow
---@field ResetOn? PW.ChallengeResetRule[]
---@field Label? string

---@class PW.ChallengeRequires
---@field modes? string[]
---@field playlists? string[]
---@field categories? string[]
---@field kinds? table<string, string[]>
---@field events? string[]

---@class PW.ChallengeParam
---@field values? string[]|fun(): string[]
---@field source? PW.ChallengeParamSource
---@field names? table<string, string>

---The entitlement item shape, without a dependency on the entitlement module.
---@alias PW.ChallengeRewardItem { kind: string, id: string, weapon: string? }

---@class PW.ChallengeReward
---@field xp? integer
---@field currency? integer
---@field items? PW.ChallengeRewardItem[]
---@field duplicateCurrency? integer

---Declarative class table in lua/privatewar/challenges/<id>.lua.
---@class PW.Challenge : PW.Entity
---@field Name string
---@field Description string
---@field Icon? string
---@field Tiers? PW.ChallengeTier[]
---@field Weight? number
---@field Group? string
---@field Pool? PW.ChallengePool
---@field Requires? PW.ChallengeRequires
---@field Params? table<string, PW.ChallengeParam>
---@field Mode? PW.ChallengeCombine
---@field Objectives? PW.ChallengeObjective[]
---@field Event? string|string[]
---@field Filters? table<string, any>
---@field Filter? fun(self: PW.Challenge, ev: PW.ChallengeEvent, params: PW.ChallengeParams): boolean?
---@field Count? PW.ChallengeCount
---@field Scope? PW.ChallengeScope
---@field Target? integer|table<PW.ChallengeTier, integer>
---@field Within? PW.ChallengeWindow
---@field ResetOn? PW.ChallengeResetRule[]
---@field Rewards? PW.ChallengeReward|table<PW.ChallengeTier, PW.ChallengeReward>

---@alias PW.ChallengeEventTypes table<string, PW.ChallengeEventType>
---@alias PW.ChallengePredicate fun(facts: table<string, any>): boolean
---@alias PW.ChallengeBinder fun(params: PW.ChallengeParams): PW.ChallengePredicate

---@class PW.ChallengeFilterContext
---@field events string[]
---@field params table<string, PW.ChallengeParam>
---@field custom PW.ChallengeEventTypes

---@class PW.ChallengeTextContext
---@field targets integer[]
---@field params PW.ChallengeParams
---@field names? table<string, table<string, string>>

---@class PW.ChallengeCompiledReset
---@field event string
---@field bind PW.ChallengeBinder

---@class PW.ChallengeCompiledObjective
---@field events string[]
---@field targets table<PW.ChallengeTier, integer>
---@field label? string
---@field scope PW.ChallengeScope
---@field count PW.ChallengeCount
---@field within? PW.ChallengeWindow
---@field bind PW.ChallengeBinder
---@field reset PW.ChallengeCompiledReset[]
---@field filter? fun(self: PW.Challenge, ev: PW.ChallengeEvent, params: PW.ChallengeParams): boolean?

---The original resolved definition and its precompiled objectives.
---@class PW.ChallengeTemplate
---@field id string
---@field definition PW.Challenge
---@field tiers PW.ChallengeTier[]
---@field group string
---@field weight number
---@field pool PW.ChallengePool
---@field mode PW.ChallengeCombine
---@field params table<string, PW.ChallengeParam>
---@field objectives PW.ChallengeCompiledObjective[]

---@class PW.ChallengeCandidate
---@field template PW.ChallengeTemplate
---Resolved available values after host catalogue checks. An absent map uses unsourced static lists only.
---@field values? table<string, string[]>

---@class PW.ChallengeSelectOptions
---@field count? integer
---@field bonusNeeded? integer
---@field seed? integer
---@field bonusPool? PW.ChallengeRewardItem[]
---@field tierDefaults? table<PW.ChallengeTier, PW.ChallengeReward>

---@class PW.ChallengeInstance
---@field id string template id followed by one dot-separated value per sorted parameter key
---@field template string
---@field tier PW.ChallengeTier
---@field params PW.ChallengeParams
---@field targets integer[]
---@field reward PW.ChallengeReward

---@class PW.ChallengeWeek
---@field index integer
---@field label string
---@field startsAt integer
---@field endsAt integer
---@field seed integer
---@field items PW.ChallengeInstance[]
---@field bonus { needed: integer, reward: PW.ChallengeReward }

---@class PW.ChallengeProgress
---@field values integer[]
---@field targets integer[]
---@field done boolean

---@class PW.ChallengeProgressPlan
---@field index integer
---@field entries table<string, PW.ChallengePlannedItem>
---@field byType table<string, PW.ChallengeRoutes>
---@field needed integer

---@class PW.ChallengeProgressState
---@field index integer
---@field items table<string, PW.ChallengeItemProgress>
---@field completed integer
---@field bonus boolean

---@class PW.ChallengePlannedObjective
---@field id string
---@field slot integer
---@field target integer
---@field scope PW.ChallengeScope
---@field count PW.ChallengeCount
---@field within? PW.ChallengeWindow
---@field matches PW.ChallengePredicate

---@class PW.ChallengePlannedItem
---@field mode PW.ChallengeCombine
---@field objectives PW.ChallengePlannedObjective[]

---@class PW.ChallengeRoutes
---@field increments PW.ChallengePlannedObjective[]
---@field resets { objective: PW.ChallengePlannedObjective, matches: PW.ChallengePredicate }[]

---@class PW.ChallengeCounter
---@field best number
---@field run? number
---@field times? number[]

---@class PW.ChallengeItemProgress
---@field counters PW.ChallengeCounter[]
---@field remaining integer
---@field done boolean

---@alias PW.ChallengeProgressBoundary "match_start"|"match_end"|"round_start"|"round_end"|"death"|"team_change"|"spawn"

---@class PW.ChallengeAdvance
---@field completed string[]
---@field bonus boolean

---@class PW.ChallengeFileItem
---@field p integer[]
---@field done? boolean

---@alias PW.ChallengeFileItems table<string, PW.ChallengeFileItem>

---@class PW.ChallengeFileWeek
---@field index integer
---@field items PW.ChallengeFileItems
---@field bonus? boolean

---@alias PW.ChallengeFileWeeks table<string, PW.ChallengeFileWeek>

---@class PW.ChallengeBatch
---@field session integer
---@field seq integer

---@class PW.ChallengeFile
---@field v integer
---@field weeks PW.ChallengeFileWeeks
---@field batch? PW.ChallengeBatch

---@class PW.ChallengeDelta : PW.ChallengeBatch
---@field label string
---@field index integer
---@field items PW.ChallengeFileItems
---@field bonus boolean

---@class PW.ChallengeWireState
---@field week PW.ChallengeWeek
---@field items PW.ChallengeFileItems
---@field bonus boolean

---@class PW.ChallengeMatchContext
---@field mode string
---@field modeBase string[]
---@field playlist string

---@class PW.ChallengeServerDeps
---@field utc fun(): integer
---@field clock fun(): number
---@field phase fun(): PW.PhaseName
---@field players fun(): Player[]
---@field isPlayer fun(ply: Player): boolean
---@field catalogue fun(): PW.ChallengeCandidate[]
---@field options? fun(): PW.ChallengeSelectOptions
---@field matchContext fun(): PW.ChallengeMatchContext
---@field schedule fun(name: string, interval: number, times: integer, run: fun())
---@field log fun(message: string)
---@field sendState fun(owner: Player, state: PW.ChallengeWireState)
---@field sendProgress fun(owner: Player, items: PW.ChallengeFileItems)
---@field sendDelta fun(owner: Player, delta: PW.ChallengeDelta)

---@class PW.ChallengeConnection
---@field rewards? table<string, PW.ChallengePendingReward>
---@field upload? PW.ChallengeFileWeeks validated, bounded rows; projected only when their week is active
---@field progress PW.ChallengeProgressState
---@field dirty table<string, boolean>
---@field persist boolean
---@field lastSend? number
---@field batch? PW.ChallengeBatch
---@field presentAt? number
---@field spawnedAt? number
---@field lifeKills integer
---@field attachments table<string, table<string, boolean>>

---@class PW.ChallengePendingReward
---@field reward PW.ChallengeReward
---@field busy? boolean

---@class PW.ChallengeServer
---@field deps PW.ChallengeServerDeps
---@field players table<Player, PW.ChallengeConnection>
---@field week PW.ChallengeWeek
---@field templates table<string, PW.ChallengeTemplate>
---@field modes table<string, PW.ChallengeCombine>
---@field plan PW.ChallengeProgressPlan
---@field match? PW.ChallengeMatchContext
---@field serial integer
---@field roundOpen boolean
---@field backwardsLogged boolean
---@field weaponFacts table<string, { category: string?, kind: PW.WeaponKind? }>

---@alias PW.ChallengeEventFacts table<string, any>
---@alias PW.ChallengeEventCallback fun(ply: Player, kind: string, facts?: PW.ChallengeEventFacts)

---@alias PW.ChallengeWireWriter fun(value: integer, width: integer)
---@alias PW.ChallengeWireReader fun(width: integer): integer

---@class PW.ChallengeWriteWire
---@overload fun(message: "upload", payload: PW.ChallengeFileWeeks, write: PW.ChallengeWireWriter)
---@overload fun(message: "state", payload: PW.ChallengeWireState, write: PW.ChallengeWireWriter)
---@overload fun(message: "progress", payload: PW.ChallengeFileItems, write: PW.ChallengeWireWriter)
---@overload fun(message: "delta", payload: PW.ChallengeDelta, write: PW.ChallengeWireWriter)

---@class PW.ChallengeReadWire
---@overload fun(message: "upload", bits: integer, read: PW.ChallengeWireReader): PW.ChallengeFileWeeks?
---@overload fun(message: "state", bits: integer, read: PW.ChallengeWireReader): PW.ChallengeWireState?
---@overload fun(message: "progress", bits: integer, read: PW.ChallengeWireReader): PW.ChallengeFileItems?
---@overload fun(message: "delta", bits: integer, read: PW.ChallengeWireReader): PW.ChallengeDelta?

---@alias PW.ChallengePlanFn fun(week: PW.ChallengeWeek, templates: table<string, PW.ChallengeTemplate>,
---    rounds: boolean): PW.ChallengeProgressPlan
---@alias PW.ChallengeAdvanceFn fun(plan: PW.ChallengeProgressPlan, state: PW.ChallengeProgressState,
---    ev: PW.ChallengeEvent): PW.ChallengeAdvance
---@alias PW.ChallengeResetFn fun(plan: PW.ChallengeProgressPlan, state: PW.ChallengeProgressState,
---    boundary: PW.ChallengeProgressBoundary)
---@alias PW.ChallengeProgressReadFn fun(plan: PW.ChallengeProgressPlan, state: PW.ChallengeProgressState,
---    id: string): PW.ChallengeProgress?
---@alias PW.ChallengeUploadFn fun(weeks: PW.ChallengeFileWeeks, active: PW.ChallengeWeek,
---    modes: table<string, PW.ChallengeCombine>): PW.ChallengeFileWeek

---@class PW.ChallengesLib
---Monday-based week index for a UTC Unix timestamp.
---@field WeekIndex fun(unixUtc: number): integer
---The ISO 8601 week label, using the calendar year of the Thursday.
---@field WeekLabel fun(index: integer): string
---Start inclusive, end exclusive, in UTC Unix seconds.
---@field WeekBounds fun(index: integer): integer, integer
---Validates and compiles a resolved template, or returns a rejection reason. Custom types come from the caller.
---@field _Compile fun(id: string, raw: any, customTypes?: PW.ChallengeEventTypes): PW.ChallengeTemplate?, string?
---@field _ArrayLength fun(value: any): integer?
---@field _CompileFilters fun(filters: any, ctx: PW.ChallengeFilterContext): PW.ChallengeBinder?, string?
---@field _FormatText fun(text: string, template: PW.ChallengeTemplate, ctx: PW.ChallengeTextContext): string
---@field _MaxInstanceId integer
---Select from validated templates with availability already resolved; no clock, registries or global RNG.
---@field _Select fun(i: integer, pool: PW.ChallengeCandidate[], opts: PW.ChallengeSelectOptions): PW.ChallengeWeek
---@field _ProgressPlan PW.ChallengePlanFn
---@field _NewProgress fun(plan: PW.ChallengeProgressPlan, saved?: PW.ChallengeFileWeek): PW.ChallengeProgressState
---@field _AdvanceProgress PW.ChallengeAdvanceFn
---@field _ResetProgress PW.ChallengeResetFn
---@field _ReadProgress PW.ChallengeProgressReadFn
---@field _SaveProgress fun(plan: PW.ChallengeProgressPlan, state: PW.ChallengeProgressState): PW.ChallengeFileWeek
---@field _Migrate fun(raw: any): PW.ChallengeFile
---@field _FileFromJson fun(json: string?): PW.ChallengeFile, boolean
---@field _FileToJson fun(file: PW.ChallengeFile, currentIndex: integer, readOnly?: boolean): string?
---@field _ApplyDelta fun(current: PW.ChallengeFile, delta: PW.ChallengeDelta): PW.ChallengeFile, boolean
---@field _UploadWeek PW.ChallengeUploadFn
---@field _ReadWire PW.ChallengeReadWire
---@field _WriteWire PW.ChallengeWriteWire
---@field _MaxStateBits integer
---@field _MaxWireFields integer
---@field _ValidWireUInt fun(value: any, width: integer): boolean
---@field _ValidWireKey fun(value: any): boolean
---@field _ValidWireRewardItem fun(value: any): boolean
---@field _ValidWireReward fun(reward: PW.ChallengeReward): boolean
---Exact payload length, including any bonus item, for admission before starting a state message.
---@field _StateBits fun(state: PW.ChallengeWireState): integer
---@field _InstanceBits fun(instance: PW.ChallengeInstance): integer
---@field _StateShareBits fun(count: integer, bonusPool: PW.ChallengeRewardItem[]): integer
---@field FileVersion integer
---@field FilePath string
---@field UploadMaxBytes integer
---@field _MaxWeeks integer
---@field _MaxItems integer
---@field _MaxObjectives integer
---@field _MaxCount integer
---@field _MaxUInt32 integer
---@field _ValidWeekLabel fun(label: any): boolean
---@field _ValidInstanceId fun(id: any): boolean
---@field _BoundCounter fun(value: any): integer
---@field GetWeek? fun(): PW.ChallengeWeek?
---@field GetActive? fun(): PW.ChallengeInstance[]
---@field GetProgress? fun(ply: Player, id: string): PW.ChallengeProgress?
---@field ProgressInterval number
---@field _NewServer fun(deps: PW.ChallengeServerDeps): PW.ChallengeServer
---@field _ScheduleServer fun(server: PW.ChallengeServer)
---@field _RefreshWeek fun(server: PW.ChallengeServer, refreshCatalogue?: boolean)
---@field _ChallengeConnection fun(server: PW.ChallengeServer, ply: Player): PW.ChallengeConnection
---@field _ChallengeHuman fun(server: PW.ChallengeServer, ply: Player): boolean
---@field _ChallengeParticipant fun(server: PW.ChallengeServer, ply: Player): boolean
---@field _OpenMatch fun(server: PW.ChallengeServer)
---@field _AcceptUpload fun(server: PW.ChallengeServer, ply: Player, rows: PW.ChallengeFileWeeks)
---@field _SendChallengeState fun(server: PW.ChallengeServer, ply: Player)
---@field _FlushChallengeProgress fun(server: PW.ChallengeServer, ply: Player, force?: boolean)
---@field _FlushChallengeDelta fun(server: PW.ChallengeServer, ply: Player)
---@field _FlushChallenges fun(server: PW.ChallengeServer, view: boolean, file: boolean, force?: boolean)
---@field _ChallengeBoundary fun(server: PW.ChallengeServer, ply: Player, boundary: PW.ChallengeProgressBoundary)
---@field _ChallengeEvent fun(server: PW.ChallengeServer, ply: Player, kind: string, facts?: PW.ChallengeEventFacts)
---@field _ChallengeCatalogue fun(): PW.ChallengeCandidate[]
---@field _QueueChallengeReward fun(server: PW.ChallengeServer, ply: Player, week: PW.ChallengeWeek, id: string)
---@field _RetryChallengeRewards fun(server: PW.ChallengeServer)

---@class PW
---@field Challenges? PW.ChallengesLib
---@field _ChallengeServer? PW.ChallengeServer

---@type PW.Challenge
CHALLENGE = nil
