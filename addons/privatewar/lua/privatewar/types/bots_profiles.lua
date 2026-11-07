---@meta
-- Types of the bot profiles (T-5.12; 07-bots.md d.10, d.15; docs/api/bots-blackboard.md "Kinds"). Code:
-- lua/privatewar/modules/bots/sh_profiles.lua (the pure rules), data: lua/privatewar/bot_difficulties/ and
-- lua/privatewar/bot_personalities/, kinds: lua/privatewar/kinds/bot_*.lua.

---@alias PW.BotProfileKind "difficulty"|"personality"
---@alias PW.BotPersonalityType "active"|"stationary"

---A difficulty tier file (class table DIFFICULTY in bot_difficulties/<tier>.lua). Every field except Name and
---Description is a number (headshot_allowed is "no", "rifles" or "yes") read by a bots_* module.
---@class PW.BotDifficulty : PW.Entity
---@field Name string display name
---@field Description? string
---@field [string] any

---A personality file (class table PERSONALITY in bot_personalities/<id>.lua).
---@class PW.BotPersonality : PW.Entity
---@field Name string display name
---@field Description? string
---@field type PW.BotPersonalityType only a "stationary" personality runs camp
---@field [string] any

---Class table inside a bot_difficulties/ file.
---@type PW.BotDifficulty
DIFFICULTY = nil

---Class table inside a bot_personalities/ file.
---@type PW.BotPersonality
PERSONALITY = nil

---@class PW.BotProfilesLib
---The tier a board without a difficulty reads ("regular").
---@field Fallback string
---The setting value that gives every bot a tier of its own ("mix").
---@field Mix string
---Weights of the tiers for "mix", by tier id (a tier without a weight counts 1).
---@field MixWeights table<string, number>
---Personalities per team: active and stationary counts of the 4:1 rule (07 d.10).
---@field Ratio { active: integer, stationary: integer }
---Entity fields that are not profile data (ClassName, Name, ...); the field test skips them.
---@field MetaFields table<string, true>
---What each consumer declared, by kind, then by consumer id.
---@field Declared table<PW.BotProfileKind, table<string, string[]>>
---Declares the profile fields a consumer reads (at load time). Reading goes through Pick; the test fails for a data
---field nobody declared and for a declared field a file lacks.
---@field Reads fun(kind: PW.BotProfileKind, consumer: string, fields: string[])
---Declared fields to the consumers that read them.
---@field Readers fun(kind: PW.BotProfileKind): table<string, string[]>
---Pure: the sorted data fields of a profile entity (without the meta fields and functions).
---@field Fields fun(entity: table): string[]
---Pure: the problems of a set of files against the declared reads: a data field nobody reads, and a declared field a
---file lacks (empty when the files and the consumers agree).
---@field Audit fun(kind: PW.BotProfileKind, entities: table[]): string[]
---The enabled entities of the kind, sorted by id (empty before the registries exist).
---@field Entities fun(kind: PW.BotProfileKind): PW.Entity[]
---The tier entity for an id; the regular tier for nil or an unknown id.
---@field Tier fun(id: string?): table
---@field TierExists fun(id: any): boolean
---Pure: the declared fields as a table, taken from the difficulty when it has a field of the same type, else from
---the tier (regular when nil or unknown).
---@field Pick fun(fields: string[], difficulty: table?, tier: string?): table<string, any>
---A plain copy of an entity's data fields (plus ClassName and Name): the full table a board holds.
---@field Snapshot fun(entity: table): table<string, any>
---Pure: the tier id for a setting value; "mix" picks by MixWeights with roll in [0, 1); an unknown value is Fallback.
---@field ResolveTier fun(value: any, roll: number): string
---Pure: "stationary" when adding one more bot keeps the team at 4 active : 1 stationary or better, else "active".
---@field NextType fun(active: integer, stationary: integer): PW.BotPersonalityType
---A personality entity of the type chosen by roll in [0, 1) (sorted by id); nil when none is enabled.
---@field PickPersonality fun(kind: PW.BotPersonalityType, roll: number): PW.Entity?

---@class PW
---@field BotProfiles PW.BotProfilesLib
---@field BotDifficulties? PW.Registry the bot_difficulties kind registry
---@field BotPersonalities? PW.Registry the bot_personalities kind registry
