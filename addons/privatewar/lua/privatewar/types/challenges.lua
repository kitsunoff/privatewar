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

---@class PW
---@field Challenges? PW.ChallengesLib

---@type PW.Challenge
CHALLENGE = nil
