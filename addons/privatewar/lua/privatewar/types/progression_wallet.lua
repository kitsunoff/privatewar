---@meta
-- Types of the progression wallet (T-4.12, 06-progression.md d.6). Source: lua/privatewar/modules/progression/
-- (sh_wallet.lua: pure checks, merge and wire; sv_wallet.lua: server currency and purchases; the state, file, delta and
-- view types of progression.lua and progression_storage.lua gain the optional fields below, so a file or a state
-- without them (a v1 file) reads as zero currency and nothing owned).

---@class PW.ProgressionState
---@field currency? number total meta currency (0 when missing)
---@field owned? table<string, boolean> purchased items by "<kind>:<id>" (a camo is "camos:<weapon>:<option>")

---@class PW.ProgressionFile
---@field currency? number
---@field owned? table<string, boolean>

---@class PW.ProgressionPending
---@field earned number currency earned since the last delta
---@field spent number currency spent since the last delta
---@field owned table<string, boolean> items purchased since the last delta

---@class PW.ProgressionDelta
---@field earned? number
---@field spent? number
---@field owned? table<string, boolean>

---@class PW.ProgressionView
---Set only while the economy module is active: whether the item key was purchased. Without it prices are ignored.
---@field owned? fun(key: string): boolean

---@class PW.ProgressionStore
---@field ownedActive fun(): boolean whether purchases count (the economy module is active)

---@class PW.ProgressionStoreOpts
---@field ownedActive? fun(): boolean

---@class PW.ProgressionLib
---@field MaxCurrency number a currency total above this is absurd: 0
---@field MaxDeltaCurrency number the largest earned or spent value in one delta
---@field MaxOwned integer owned keys per file, upload or delta
---@field MaxKeyLength integer longest owned key
---Internal, pure: "<kind>:<id>".
---@field _OwnedKey fun(kind: string, id: string): string
---Internal, pure: the well-formed keys of a list or a key -> true map, the first limit in key order.
---@field _CheckOwned fun(raw: any, limit: integer): table<string, boolean>
---Internal, pure: a new set with the keys of both.
---@field _MergeOwned fun(current: table<string, boolean>, added: table<string, boolean>): table<string, boolean>
---Internal, pure: the keys of a set, sorted.
---@field _SortedOwned fun(owned: table<string, boolean>): string[]
---Internal, pure: currency + earned - spent, each bounded, clamped to 0..MaxCurrency.
---@field _CurrencyAfter fun(current: number?, earned: any, spent: any): number
---@field _WriteOwned fun(writer: PW.ProgressionWriter, owned: table<string, boolean>)
---@field _ReadOwned fun(reader: PW.ProgressionReader): table<string, boolean>
---Server. The currency of a player; a client answers for the local player from its file.
---@field GetCurrency fun(ply: Player): number
---Server. Adds currency (whole, above 0, capped at MaxCurrency); joins the next delta.
---@field AddCurrency fun(ply: Player, amount: number)
---Server. Takes currency; false and nothing taken when the player has less or the amount is not a whole number above 0.
---@field SpendCurrency fun(ply: Player, amount: number): boolean
---Server. Marks items owned by key; joins the next delta. Returns how many were new.
---@field GrantOwned fun(ply: Player, keys: string[]): integer
---Shared. Whether the item key ("<kind>:<id>") was purchased. A client answers for the local player.
---@field IsOwned fun(ply: Player, key: string): boolean
---Server. Sends the pending delta now (nothing when nothing is pending).
---@field Flush fun(ply: Player)
---Internal (server): wallet changes over a store.
---@field _AddCurrency fun(store: PW.ProgressionStore, ply: Player, amount: number)
---@field _SpendCurrency fun(store: PW.ProgressionStore, ply: Player, amount: number): boolean
---@field _GrantOwned fun(store: PW.ProgressionStore, ply: Player, keys: string[]): integer
---Internal: whether purchases count right now (the economy module is valid).
---@field _OwnedActive fun(): boolean
---Internal (server): the live session state of a player (created empty), and the pending delta (created empty).
---@field _StateOf fun(store: PW.ProgressionStore, ply: Player): PW.ProgressionState
---@field _PendingOf fun(store: PW.ProgressionStore, ply: Player): PW.ProgressionPending
---Internal (server): the live owned set of a player.
---@field _GetOwned fun(store: PW.ProgressionStore, ply: Player): table<string, boolean>
