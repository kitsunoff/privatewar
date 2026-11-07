---@meta
-- Types of the stat-based unlock levels (T-11.7; 06-progression.md d.2 revision 2026-11-07; docs/api/progression.md
-- "Automatic unlock levels"). Code: lua/privatewar/modules/autounlock/.

---Stat changes of one attachment option, as multipliers of the weapon's value (1 = no change, absent = no change).
---magazineAdd is a number of rounds. An option without any numeric stat has no PW.OptionStats (nil).
---@class PW.OptionStats
---@field damage? number
---@field range? number
---@field rpm? number
---@field recoil? number
---@field spread? number
---@field adsTime? number
---@field sprintToFire? number
---@field moveSpeed? number
---@field reloadTime? number
---@field magazineAdd? number

---One option of a slot, as the computation sees it. stats nil = the option has no numeric stats.
---@class PW.AutoUnlockOption
---@field id string
---@field stats? PW.OptionStats

---@class PW.AutoUnlockSlot
---@field id string
---@field options PW.AutoUnlockOption[] the non-cosmetic options of the slot

---One weapon, as the computation sees it.
---@class PW.AutoUnlockWeapon
---@field class string
---@field category string
---@field stats PW.Stats
---@field slots PW.AutoUnlockSlot[]
---@field starter? boolean a weapon of a preset class: open at level 1

---The weights of the formula (lib.Weights); every field has a clear name and a default recommendation.
---@class PW.AutoUnlockWeights
---Weight of each weapon feature in the power score: ttkNear, ttkMid, rpm, recoil, spread, adsTime, sprintToFire,
---moveSpeed.
---@field weapon table<string, number>
---Weight of each option stat in the stat gain: damage, range, rpm, recoil, spread, adsTime, sprintToFire, moveSpeed,
---reloadTime, magazine.
---@field option table<string, number>
---@field health number hit points of a target for the time to kill
---@field midRange number metres: the mid range of the time to kill
---@field defaultRpm number rate of fire for the time to kill when a weapon gives none
---@field defaultMagazine number magazine size for magazineAdd when a weapon gives none
---A category with at least this many weapons opens two at the first level, a smaller one opens one.
---@field openTwoFrom integer

---Level caps of the spreading.
---@class PW.AutoUnlockCaps
---@field maxLevel integer player levels 1..maxLevel for weapons
---@field maxWeaponLevel integer weapon levels 1..maxWeaponLevel for attachments

---@class PW.AutoUnlockReport
---@field weapons integer weapons that got a level
---@field categories integer
---@field options integer options that got a level
---@field noStats integer options without numeric stats (middle level of their slot)

---Raw features by weapon class (lib._WeaponFeatures of each).
---@alias PW.AutoUnlockFeatures table<string, table<string, number>>

---Levels by id (option id or class).
---@alias PW.AutoUnlockLevels table<string, integer>

---Levels of one slot's options and the number of options without stats.
---@class PW.AutoUnlockSlotRes
---@field levels PW.AutoUnlockLevels
---@field noStats integer

---The computed levels. The shape of the cache file's "result".
---@class PW.AutoUnlockResult
---@field weapons table<string, integer> class -> player level
---@field attachments table<string, table<string, integer>> class -> option id -> weapon level
---@field report PW.AutoUnlockReport

---The engine edges of a run; the tests pass fakes.
---@class PW.AutoUnlockEnv
---@field setting fun(id: string): any
---@field adapterFor fun(class: string): PW.Adapter?
---@field call fun(adapter: PW.Adapter, method: string, ...: any): any
---@field read fun(path: string): string?
---@field write fun(path: string, text: string)
---@field hash fun(text: string): string
---@field clock fun(): number seconds
---@field log fun(message: string)
---@field starters? fun(): table<string, boolean> classes open at level 1 (the weapons of the preset classes)

---What a run did.
---@class PW.AutoUnlockRun
---@field enabled boolean
---@field cacheHit boolean
---@field registered integer weapons whose entry got a soft registration
---@field ms number time spent, milliseconds
---@field result? PW.AutoUnlockResult

---@class PW.AutoUnlockLib
---The weights of the formula; defaults are a recommendation pending confirmation (the local checklist section 7).
---@field Weights PW.AutoUnlockWeights
---The cache file under data/.
---@field CachePath string
---Bumped when the computation changes, so old caches are recomputed.
---@field Version integer
---Computes and registers the levels softly in reg; uses the cache when its key matches. env defaults to the engine.
---@field Run fun(reg: PW.Registry, env?: PW.AutoUnlockEnv): PW.AutoUnlockRun
---Pure: the raw features of a weapon (higher is better; nil when the stat is missing).
---@field _WeaponFeatures fun(stats: PW.Stats, weights: PW.AutoUnlockWeights): table<string, number>
---Pure: power scores of the weapons of one category (features normalised within the category, missing = middle).
---@field _ScoreCategory fun(features: PW.AutoUnlockFeatures, weights: PW.AutoUnlockWeights): table<string, number>
---Pure: ids sorted weakest first; ties broken by id.
---@field _Rank fun(scores: table<string, number>): string[]
---Pure: levels of n ranked items: the first open at level 1, the rest spread evenly up to (not including) cap.
---@field _Spread fun(n: integer, open: integer, cap: integer): integer[]
---Pure: how many weapons of a category of n open at level 1 (1 or 2).
---@field _OpenCount fun(n: integer, weights: PW.AutoUnlockWeights): integer
---Pure: the stat gain of an option on a weapon (positive = stronger).
---@field _OptionGain fun(stats: PW.OptionStats, base: PW.Stats, weights: PW.AutoUnlockWeights): number
---Pure: weapon levels (1..n) of the options of one slot, and how many had no stats.
---@field _SlotLevels fun(s: PW.AutoUnlockSlot, b: PW.Stats, w: PW.AutoUnlockWeights, n: integer): PW.AutoUnlockSlotRes
---Pure: the whole computation.
---@field _Compute fun(list: PW.AutoUnlockWeapon[], w: PW.AutoUnlockWeights, c: PW.AutoUnlockCaps): PW.AutoUnlockResult
---Pure: a text with sorted keys for any plain value (the input of the cache key).
---@field _Canonical fun(value: any): string
---Pure: the cache key of a weapon set, attachment sets, weights and caps.
---@field _CacheKey fun(parts: table, hash: fun(text: string): string): string
---Pure: the table to register softly for one weapon, given its current entry (a weapon with a Price stays shop-only).
---@field _EntryFor fun(existing: table?, level: integer?, options: PW.AutoUnlockLevels?): table<string, any>?
---Internal, pure: every string of the Loadout of each preset class (registry of the kind classes).
---@field _PresetWeapons fun(classes: PW.Registry?): table<string, boolean>
---Internal: the engine edges.
---@field _DefaultEnv fun(): PW.AutoUnlockEnv

---Internal: state of the module (kept across a reload).
---@class PW.AutoUnlockStore
---@field last? PW.AutoUnlockRun the last run of this realm

---@class PW
---@field AutoUnlock PW.AutoUnlockLib
---@field _AutoUnlock PW.AutoUnlockStore internal
