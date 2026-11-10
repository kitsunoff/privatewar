---@meta
-- Types of the bots_loadouts module (T-5.13; 05-loadout.md d.14). Code: lua/privatewar/modules/bots_loadouts/
-- (shared.lua: the pure pool, weights and pick; init.lua: the server glue, the players' pool and the hooks).

---Where a pool class comes from: the classes/ kind or the custom classes of the session's humans.
---@alias PW.BotClassSource "preset"|"players"|"generated"

---One class a bot may pick.
---@class PW.BotClassEntry
---@field ref string "preset:<id>" or "player:<SteamID64>:<n>"
---@field source PW.BotClassSource
---@field name string
---@field loadout PW.Loadout
---@field category? string explicit archetype for bot-only candidates (LMG and pistol-only included)

---A preset as plain data for the pool.
---@class PW.BotPresetClass
---@field id string the class id (ClassName)
---@field name string
---@field loadout PW.Loadout

---A human's custom class kept in the players' pool.
---@class PW.BotPlayerClass
---@field key string "<SteamID64>:<n>", n the position in the player's upload
---@field name string
---@field loadout PW.Loadout the player's repaired, available class (checked against the player's unlocks)

---The sources of bots.classes.
---@class PW.BotClassSources
---@field preset? boolean
---@field players? boolean

---The weapon category of a weapon id (nil when unknown).
---@alias PW.BotCategoryFn fun(id: string): string?

---@alias PW.BotPickClassFn fun(pool: PW.BotClassEntry[], weights: table<string, number>?, roll: number,
---  categoryOf: PW.BotCategoryFn): PW.BotClassEntry?

---Plain input of the pool.
---@class PW.BotPoolInput
---@field sources PW.BotClassSources
---@field presets PW.BotPresetClass[] in registry order
---@field players PW.BotPlayerClass[]
---@field check fun(loadout: PW.Loadout): boolean the match settings check (never progression)

---@class PW.BotLoadoutsLib
---The personality field with the class weights by the primary's weapon category ("class_weights").
---@field WeightsField string
---Pure: the sources of a bots.classes value; nil (no setting) is both.
---@field Sources fun(value: any): PW.BotClassSources
---Pure: the pool: enabled sources only, classes that pass check; presets in order, then players by key.
---@field BuildPool fun(input: PW.BotPoolInput): PW.BotClassEntry[]
---Append copies of provider candidates passing current match validation; existing entries stay untouched.
---@field AppendCandidates fun(pool: PW.BotClassEntry[], candidates: PW.BotClassEntry[],
---  check: fun(loadout: PW.Loadout): boolean)
---Pure: the weight of a class: weights[category of its primary], else 1; never below 0.
---@field Weight fun(entry: PW.BotClassEntry, weights: table<string, number>?, categoryOf: PW.BotCategoryFn): number
---Pure: the weighted pick for roll in [0, 1); an even draw when every weight is 0; nil for an empty pool.
---@field Pick PW.BotPickClassFn
---Pure: the class weights of a board's personality, nil when it has none.
---@field WeightsOf fun(board: { personality?: table<string, any> }): table<string, number>?
---Pure: the pool entry of a ref.
---@field Find fun(pool: PW.BotClassEntry[], ref: string?): PW.BotClassEntry?
---Pure: whether a bot picks again: always without a class in the pool, else when roll < chance.
---@field ShouldRepick fun(current: string?, pool: PW.BotClassEntry[], chance: number, roll: number): boolean
---Pure: the available custom classes of a player's class state, keyed "<owner>:<n>".
---@field _HarvestEntries fun(owner: string, state: PW.LoadoutClassState): PW.BotPlayerClass[]
---Server: takes the custom classes of a human (every human when nil) into the players' pool.
---@field Harvest fun(ply: Player?)
---Server: the pool of a bot under the current match settings.
---@field PoolFor fun(bot: Player): PW.BotClassEntry[]
---Server: gives a bot a class (keeps the current one unless the re-pick rule says otherwise); chance of re-picking.
---@field Assign fun(bot: Player, chance: number): PW.BotClassEntry?
---Server: drops the class of a bot (a new match).
---@field Clear fun(bot: Player)
---Server: the ref of a bot's class, nil when it has none.
---@field PickOf fun(bot: Player): string?

---Internal (server): the players' pool and the picks.
---@class PW.BotLoadoutsStore
---@field players table<string, PW.BotPlayerClass[]> by owner SteamID64; kept until the map changes
---@field picks table<Player, string> the ref per bot (weak keys)
---@field paused boolean true during a GLuaTest run (other groups expect the default loadout)

---@class PW
---@field BotLoadouts? PW.BotLoadoutsLib
---@field _BotLoadouts PW.BotLoadoutsStore internal (server)
