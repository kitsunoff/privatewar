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

---@class PW.ChallengesLib

---@class PW
---@field Challenges? PW.ChallengesLib

---@type PW.Challenge
CHALLENGE = nil
