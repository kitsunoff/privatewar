---@meta
-- Types of the STORE and PROGRESS tabs (T-7.5; 06-progression.md d.4, d.6; 10-frontend.md d.1). Source:
-- lua/privatewar/modules/ui_kit/sh_store.lua and sh_progress.lua (pure, shared); screens
-- lua/privatewar/screens/store_home.lua, store_bundle.lua and progress_home.lua.

---State of a store offer for the local player, in the order the server's quote checks it.
---"pending": a request for it is in flight; "owned": bought (a bundle: its key or every item); "unlocked": the level
---already unlocks a single entity; "funds": the price is above the balance; "buyable": none of these.
---@alias PW.UIStoreState "pending"|"owned"|"unlocked"|"funds"|"buyable"

---The rotation a bundle is featured in.
---@alias PW.UIStoreRotation "featured"|"weekly"

---What the store model reads about the local player.
---@class PW.UIStoreFacts
---@field currency number the balance
---@field owned fun(key: string): boolean purchased ("<kind>:<id>")
---@field unlocked fun(kind: string, id: string): boolean unlocked for the player (level, purchase or unlockall)
---@field pending? string the key of a purchase request in flight

---One group of the store: a rotation (featured, weekly) or the permanent offers of one kind.
---@class PW.UIStoreSection
---@field id string "featured", "weekly" or "kind:<kind>"
---@field title string
---@field offers PW.EconomyOffer[]
---@field cards PW.UICard[] one card per offer, same order
---@field empty boolean
---@field note? string the text of an empty rotation
---@field countdown? string time to the next rotation ("13h 20m"), rotations only

---The Buy button of an offer.
---@class PW.UIStoreButton
---@field label string
---@field locked boolean
---@field reason? string why it is locked (hint bar)

---A message after a purchase request (the answer, or a timeout).
---@class PW.UIStoreMessage
---@field ok boolean
---@field text string

---The Buy flow of one screen: at most one request in flight.
---@class PW.UIStorePurchase
---@field pending? string the key sent
---@field sentAt? number when it was sent (seconds, the caller's clock)
---@field message? PW.UIStoreMessage the last answer

---What a preview panel shows: a player model or a material.
---@class PW.UIStorePreview
---@field type "model"|"material"
---@field path string

---One item of a bundle (bundle details).
---@class PW.UIStoreItem
---@field key string
---@field kind string
---@field id string
---@field name string
---@field label string the kind, singular ("Model", "Calling card")
---@field state "owned"|"unlocked"|"locked"
---@field preview? PW.UIStorePreview

---Store view model (pure). Currency is shown as "<n> CR".
---@class PW.UIStoreLib
---@field Currency string the currency suffix, "CR"
---@field RequestTimeout number seconds before an unanswered request is dropped
---@field KindOrder string[] the kinds shown first, in order (models, cards, camos)
---@field FormatNumber fun(value: number): string floored, thousands separated by commas
---@field PriceText fun(price: number): string "2,400 CR"
---@field KindLabel fun(kind: string, plural?: boolean): string "Model"/"Models", "Calling card"/"Calling cards", ...
---Seconds from now (Unix seconds) to the next rotation: "daily" at 00:00 UTC, "weekly" on Monday 00:00 UTC.
---@field SecondsToRotation fun(now: number, period: "daily"|"weekly"): number
---@field CountdownText fun(seconds: number): string "2d 4h", "13h 20m", "4m 05s"
---@field OfferState fun(offer: PW.EconomyOffer, facts: PW.UIStoreFacts): PW.UIStoreState
---@field OfferCards fun(offers: PW.EconomyOffer[], facts: PW.UIStoreFacts): PW.UICard[]
---@field Sections fun(store: PW.EconomyStoreView, facts: PW.UIStoreFacts, now: number): PW.UIStoreSection[]
---@field SectionCards fun(sections: PW.UIStoreSection[]): PW.UICard[]
---@field BuyButton fun(offer: PW.EconomyOffer, state: PW.UIStoreState, currency: number): PW.UIStoreButton
---@field NewPurchase fun(): PW.UIStorePurchase
---Sends the request (send(key)) when the offer is buyable and nothing is in flight; true when sent.
---@field Request fun(purchase: PW.UIStorePurchase, offer: PW.EconomyOffer, state: PW.UIStoreState,
---send: fun(key: string), now: number): boolean
---Records the server's answer: clears the request and returns the message.
---@field OnResult fun(purchase: PW.UIStorePurchase, result: PW.EconomyResult, name: string): PW.UIStoreMessage
---Drops a request older than RequestTimeout; true when it did.
---@field Expire fun(purchase: PW.UIStorePurchase, now: number): boolean
---@field ResultText fun(result: PW.EconomyResult, name: string): string
---@field Preview fun(kind: string, entity?: table<string, any>): PW.UIStorePreview?
---@field ItemViews fun(offer: PW.EconomyOffer, lookup: PW.LoadoutLookup, facts: PW.UIStoreFacts): PW.UIStoreItem[]
---@field ItemCards fun(items: PW.UIStoreItem[]): PW.UICard[]
---@field RotationOf fun(store: PW.EconomyStoreView, key: string): PW.UIStoreRotation?
---Info rows of a bundle: PRICE, RARITY, ITEMS and, in a rotation, LEAVES IN.
---@field BundleRows fun(offer: PW.EconomyOffer, items: PW.UIStoreItem[], rotation?: PW.UIStoreRotation,
---now: number): { [1]: string, [2]: string }[]

---Client glue (cl_store.lua).
---@class PW.UIStoreLib
---Client. The enabled entities of every registry (kind -> id -> entity).
---@field LiveCatalogue? fun(): PW.EconomyCatalogue
---@field LiveLookup? fun(): PW.LoadoutLookup
---Client. The local player's balance, purchases, unlocks and the request in flight.
---@field LiveFacts? fun(): PW.UIStoreFacts
---Client. Pushes the bundle details screen (store_bundle) for a bundle key on the open root.
---@field OpenBundle? fun(key: string)
---@field TakeBundle? fun(): string?
---Client. Sends the purchase request through PW.Economy.RequestBuy when the offer is buyable; true when sent.
---@field Buy? fun(offer: PW.EconomyOffer): boolean
---Client. The confirm dialog of a purchase; done runs after the request was sent.
---@field ConfirmBuy? fun(offer: PW.EconomyOffer, done?: fun())
---Client. Drops an unanswered request (RequestTimeout) and redraws the open screen.
---@field Tick? fun()
---Client. Sets the cards of a PWCardList, in place when the ids did not change (the focus survives).
---@field UpdateCards? fun(list: Panel, cards: PW.UICard[], selected?: string) list: a PWCardList
---@field _purchase? PW.UIStorePurchase the client's Buy flow, shared by the store screens
---@field _bundle? string the bundle key given to OpenBundle

---A preview of a store item: a player model (PWOperator), a card material, or "NO PREVIEW"; a title strip below.
---@class PWStorePreview : Panel
---@field SetPreview fun(self: PWStorePreview, preview?: PW.UIStorePreview, title?: string, subtitle?: string)

---A horizontal bar in the accent colour with a centred label.
---@class PWProgressBar : Panel
---@field SetProgress fun(self: PWProgressBar, fraction: number, label?: string)

---The level card of the PROGRESS tab.
---@class PW.UIProgressLevel
---@field title string "LEVEL 7"
---@field xpText string "1,200 / 7,000 XP", "Max level" at the cap
---@field fraction number 0..1, 1 at the cap
---@field maxed boolean

---One entity unlocked by a higher player level.
---@class PW.UIProgressUnlock
---@field kind string
---@field id string
---@field name string
---@field level integer

---One weapon of the weapon levels list.
---@class PW.UIProgressWeapon
---@field id string the weapon class
---@field name string
---@field xp number total XP
---@field level integer
---@field into number XP into the level
---@field need number XP for the next level, 0 at the cap
---@field fraction number
---@field maxed boolean

---Progress view model (pure).
---@class PW.UIProgressLib
---@field LevelView fun(level: integer, into: number, need: number): PW.UIProgressLevel
---Entities of a catalogue whose Unlock level is above the level, the closest first (ties: name, kind, id).
---Hidden entities are left out; limit caps the count.
---@field NextUnlocks fun(catalogue: PW.EconomyCatalogue, level: integer, limit?: integer): PW.UIProgressUnlock[]
---@field UnlockRows fun(unlocks: PW.UIProgressUnlock[]): { [1]: string, [2]: string }[]
---Every weapon of the registry plus every class with XP, highest level first (ties: XP, name).
---@field Weapons fun(weapons: table<string, table<string, any>>, xp: table<string, number>,
---levelOf: fun(xp: number): integer, number, number): PW.UIProgressWeapon[]
---@field WeaponCards fun(rows: PW.UIProgressWeapon[]): PW.UICard[]
---Rows of the last match summary; nil without one.
---@field SummaryRows fun(summary?: PW.ProgressionSummary, nameOf?: fun(class: string): string):
---{ [1]: string, [2]: string }[]?

---@class PW.UILib
---@field Store? PW.UIStoreLib
---@field Progress? PW.UIProgressLib
