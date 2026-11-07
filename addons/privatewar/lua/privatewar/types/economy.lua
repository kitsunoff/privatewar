---@meta
-- Types of the economy (T-4.12, 06-progression.md d.6). Source: lua/privatewar/modules/economy/ (shared.lua: settings,
-- API; sh_rotation.lua, sh_catalogue.lua, sh_purchase.lua: pure rules and wire; init.lua: server glue; cl_init.lua:
-- client requests) and the kinds bundles, models, cards (lua/privatewar/kinds/).

---One shop bundle, a file in lua/privatewar/bundles/ with a BUNDLE table. Data only. Items are { kind, id } (any kind
---with a registry), or { kind = "camos", weapon, id } for a weapon camo ("camo" is accepted as the kind too).
---@class PW.Bundle : PW.Entity
---@field Name string
---@field Price number currency, a whole number above 0
---@field Items table[] the entities and camos granted together
---@field Rarity? string "common", "rare", "epic" or "legendary" (display only)
---@field Description? string

---One playermodel ("operator"), a file in lua/privatewar/models/ with a MODEL table. Data only.
---@class PW.PlayerModel : PW.Entity
---@field Name string
---@field Model string model path, for example "models/player/swat.mdl"
---@field Price? number currency; a model with a Price and no Unlock is for sale only
---@field Unlock? integer|{ level: integer } player level
---@field Rarity? string
---@field Description? string

---One calling card, a file in lua/privatewar/cards/ with a CARD table. Data only.
---@class PW.CallingCard : PW.Entity
---@field Name string
---@field Material string material path, for example "icon16/medal_gold_1.png"
---@field Price? number
---@field Unlock? integer|{ level: integer }
---@field Rarity? string
---@field Description? string

---Entities by kind and id: the catalogue the pure functions read (the live one comes from the registries).
---@alias PW.EconomyCatalogue table<string, table<string, table<string, any>>>

---One thing a purchase grants. key is "<kind>:<id>"; a camo is kind "camos" with id "<weapon>:<option>".
---@class PW.EconomyItem
---@field kind string
---@field id string
---@field key string

---One offer of the store. A single offer sells one entity with a Price; a bundle offer sells its items.
---@class PW.EconomyOffer
---@field key string "<kind>:<id>" of the entity or bundle
---@field kind string
---@field id string
---@field name string
---@field price integer
---@field rarity? string
---@field bundle boolean
---@field items PW.EconomyItem[] what is granted (a single offer: itself)

---The offers of a catalogue: single entities with a Price and valid bundles, each sorted by key.
---@class PW.EconomyOffers
---@field singles PW.EconomyOffer[]
---@field bundles PW.EconomyOffer[]

---What the store screen shows on a date.
---@class PW.EconomyStoreView
---@field date string
---@field permanent PW.EconomyOffer[] single unlocks, always on sale
---@field featured PW.EconomyOffer[] the daily bundles
---@field weekly PW.EconomyOffer[] the weekly bundles

---What a quote reads about the player and the shop.
---@class PW.EconomyContext
---@field catalogue PW.EconomyCatalogue
---@field offered table<string, boolean> bundle keys on sale now
---@field owned fun(key: string): boolean
---@field unlocked fun(kind: string, id: string): boolean unlocked by level (purchases ignored)
---@field currency number

---A purchase that can go ahead.
---@class PW.EconomyQuote
---@field key string
---@field price integer
---@field grants string[] owned keys to record (a bundle: its items and the bundle itself)

---Server answer to a purchase request.
---@class PW.EconomyResult
---@field ok boolean
---@field key string
---@field reason string "" when ok; else one of "badkey", "unknown", "notoffered", "owned", "unlocked", "funds"
---@field currency integer the balance after the request

---@class PW.EconomyParams
---@field currencyRate number currency per XP of a score event without its own Currency
---@field matchBonus integer currency at the end of a match for a player who earned
---@field dailySlots integer
---@field weeklySlots integer

---Internal (server): the injectable edges of the economy.
---@class PW.EconomyStore
---@field read fun(id: string): any settings reader
---@field today fun(): string
---@field catalogue fun(): PW.EconomyCatalogue
---@field progression? PW.ProgressionStore the store the wallet lives in (nil: the live PW._Progression)
---@field eventCurrency fun(eventId: string): number? the Currency field of a score event
---@field notify fun(name: string, ...: any)
---@field sendResult fun(ply: Player, result: PW.EconomyResult)
---@field earned table<Player, number> currency earned this match, weak keys
---@field bonused table<Player, boolean> players paid the match bonus, weak keys

---@class PW.EconomyStoreOpts
---@field read? fun(id: string): any
---@field today? fun(): string
---@field catalogue? fun(): PW.EconomyCatalogue
---@field progression? PW.ProgressionStore
---@field eventCurrency? fun(eventId: string): number?
---@field notify? fun(name: string, ...: any)
---@field sendResult? fun(ply: Player, result: PW.EconomyResult)

---Economy module (06-progression.md d.6). Currency is stored by progression (PW.Progression.GetCurrency and the
---wallet functions); this module earns it, sells, rotates. Server notification (no return value):
---PW_EconomyPurchase(ply, key, price). Client notification: PW_EconomyResult(result). Net: pw_economy_buy (client to
---server: key string), pw_economy_result (server to the owner: ok bool, key string, reason string, currency u32).
---@class PW.EconomyLib
---Shared. Today's date, UTC, "YYYY-MM-DD".
---@field Today fun(): string
---Shared. The store on a date (today by default): permanent offers, the daily and the weekly bundles.
---@field GetStore fun(date?: string): PW.EconomyStoreView
---Shared. One offer by key ("models:swat", "bundles:neon_reaper"), nil when unknown or an invalid bundle.
---@field GetOffer fun(key: string): PW.EconomyOffer?
---Shared. The keys of the daily and the weekly bundles on a date.
---@field Featured fun(date?: string): string[]
---@field Weekly fun(date?: string): string[]
---Shared. The currency of a player (a client answers for the local player).
---@field GetCurrency fun(ply: Player): number
---Shared. Whether the item was purchased (a client answers for the local player).
---@field IsOwned fun(ply: Player, kind: string, id: string): boolean
---Server. Buys the offer for the player. Returns true, or false and the reason (see PW.EconomyResult).
---@field Buy fun(ply: Player, key: string): boolean, string?
---Client. Asks the server to buy the offer (the answer is the notification PW_EconomyResult).
---@field RequestBuy fun(key: string)
---Client. The last answer of the server to a request (nil before the first one).
---@field LastResult? PW.EconomyResult
---@field RequestMaxBytes integer maxLen of pw_economy_buy
---Internal: the module is valid (purchases count in IsUnlocked).
---@field _Active fun(): boolean
---@field _Module? PW.Module
---Internal, pure: the settings as numbers.
---@field _Params fun(read: fun(id: string): any): PW.EconomyParams
---Internal, pure: days since 1970-01-01 of a "YYYY-MM-DD" date, nil when malformed.
---@field _DayNumber fun(date: any): integer?
---Internal, pure: the week (Monday start) a day number belongs to.
---@field _WeekNumber fun(day: integer): integer
---Internal, pure: slots ids out of the catalogue ids in a seeded order (the input order does not matter).
---@field _Rotate fun(seed: number, ids: string[], slots: number): string[]
---Internal, pure: the daily and the weekly selection for a date.
---@field _Featured fun(date: string, ids: string[], slots: number): string[]
---@field _Weekly fun(date: string, ids: string[], slots: number): string[]
---Internal, pure: the entity of a kind and id, nil when unknown.
---@field _LookupOf fun(catalogue: PW.EconomyCatalogue): PW.LoadoutLookup
---Internal, pure: the offers of a catalogue.
---@field _Offers fun(catalogue: PW.EconomyCatalogue): PW.EconomyOffers
---Internal, pure: the store of a date over a catalogue.
---@field _BuildStore fun(catalogue: PW.EconomyCatalogue, date: string, dailySlots: number, weeklySlots: number):
---PW.EconomyStoreView
---Internal: the catalogue of the live registries (enabled entities).
---@field _LiveCatalogue fun(): PW.EconomyCatalogue
---Internal, pure: can the player buy the key; the quote, or nil and the reason.
---@field _Quote fun(ctx: PW.EconomyContext, key: string): PW.EconomyQuote?, string?
---Internal, pure wire.
---@field _EncodeRequest fun(key: string, writer: PW.ProgressionWriter)
---@field _DecodeRequest fun(reader: PW.ProgressionReader): string
---@field _EncodeResult fun(result: PW.EconomyResult, writer: PW.ProgressionWriter)
---@field _DecodeResult fun(reader: PW.ProgressionReader): PW.EconomyResult
---Internal (server).
---@field _NewStore fun(opts?: PW.EconomyStoreOpts): PW.EconomyStore
---@field _Context fun(store: PW.EconomyStore, ply: Player): PW.EconomyContext
---@field _Buy fun(store: PW.EconomyStore, ply: Player, key: string): boolean, string
---@field _OnRequest fun(store: PW.EconomyStore, ply: Player, key: string): boolean, string
---@field _OnScoreEvent fun(store: PW.EconomyStore, ply: Player, eventId: string, points: number, xp: number)
---@field _BeginMatch fun(store: PW.EconomyStore)
---@field _OnPostmatch fun(store: PW.EconomyStore)

---@class PW
---@field Economy? PW.EconomyLib the economy module
---@field _Economy? PW.EconomyStore internal

---Class tables inside bundles/, models/ and cards/ files.
---@type PW.Bundle
BUNDLE = nil
---@type PW.PlayerModel
MODEL = nil
---@type PW.CallingCard
CARD = nil
