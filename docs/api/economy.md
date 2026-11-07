# Economy API

Module `economy` (T-4.12, `design/06-progression.md` d.6). A meta currency earned through score events, `Price` on
entities, purchases through a validated net request, shop bundles and a date-seeded rotation. Disabling the module leaves
level-only unlocks (prices and purchases stop counting in `PW.Progression.IsUnlocked`). The currency and the purchased
items are stored by progression (see "Wallet (T-4.12)" in `progression.md`). The store screen is T-7.5 and reads this API.

Files: `lua/privatewar/modules/economy/` (`shared.lua`, `sh_rotation.lua`, `sh_catalogue.lua`, `sh_purchase.lua`,
`init.lua`, `cl_init.lua`), kinds `lua/privatewar/kinds/bundles.lua`, `models.lua`, `cards.lua`, samples in
`lua/privatewar/bundles/`, `models/`, `cards/`, types `lua/privatewar/types/economy.lua`.

## Kinds

| Kind | Folder | Class table | Required | Optional |
| --- | --- | --- | --- | --- |
| `bundles` | `bundles/` | `BUNDLE` | `Name`, `Price` (number), `Items` (table) | `Rarity`, `Description` |
| `models` | `models/` | `MODEL` | `Name`, `Model` (model path) | `Price`, `Unlock`, `Rarity`, `Description` |
| `cards` | `cards/` | `CARD` | `Name`, `Material` (material path) | `Price`, `Unlock`, `Rarity`, `Description` |

All three are data, never auto-subscribed, with the per-entity enable ConVar named after the class table in lowercase:
`pw_bundle_<id>_enabled`, `pw_model_<id>_enabled`, `pw_card_<id>_enabled`.

- `Items` of a bundle: `{ kind = "<registry kind>", id = "<id>" }`, or `{ kind = "camos", weapon = "<id>", id = "<camo>" }`
  (`"camo"` is accepted as the kind). A bundle with an item that does not resolve, an empty one or one that nests a bundle
  is not offered.
- A `Price` of 1 or more (floored) makes any entity of any kind a single offer. An entity with a `Price` and no `Unlock` is
  for sale only; with an `Unlock` it is also unlocked by level.
- Samples (stock content only): playermodels `swat`, `urban`, `riot`, `combine_elite` (`models/player/*.mdl`), cards
  `gold_medal`, `bomb`, `lightning` (`icon16/*.png`), bundles `operator_pack`, `shadow_ops`, `elite_force`. The bundles
  also reference content of other modules: `operator_pack` holds the perk `adrenaline`, `elite_force` the streak `uav` and
  the equipment `frag`, so they are offered only while those entities exist. Prices: models 600 to 2000, cards 150 to 450,
  bundles 700 to 2400.
- Equipping a model or a card is not part of T-4.12 (no consumer yet).

## Earning

| Source | Amount |
| --- | --- |
| A score event of a human | `EVENT.Currency` when set, else `floor(xp * economy.currencyrate)` (default 0.1). `xp` is the event's XP before `progression.xpscale` |
| End of match (`POSTMATCH`) | `economy.matchbonus` (default 100), once, only to a player who earned currency in the match |

Bots earn nothing. Amounts below 1 are dropped.

## Settings

Server scope, ids `economy.<name>`:

| Name | Type | Default | Range | Meaning |
| --- | --- | --- | --- | --- |
| `currencyrate` | float | 0.1 | 0 to 10 | Currency per XP of an event without its own `Currency` |
| `matchbonus` | int | 100 | 0 to 100000 | End-of-match bonus |
| `dailyslots` | int | 2 | 0 to 16 | Bundles featured per day |
| `weeklyslots` | int | 1 | 0 to 16 | Bundles featured per week |

## Rotation

A pure function of the date: `Featured` (daily) and `Weekly` pick `slots` bundles out of the valid bundles. A date is
`"YYYY-MM-DD"` in UTC; a week starts on Monday. The pick does not depend on the order the catalogue is listed in, so the
server and every client compute the same shop. The same date gives the same bundles; another date gives another selection.
A bundle can be bought only while it is featured today or this week; single offers are always on sale.

## API

| Function | Contract |
| --- | --- |
| `PW.Economy.Today() -> string` | Shared. Today's date, UTC |
| `PW.Economy.GetStore(date?) -> PW.EconomyStoreView` | Shared. `{ date, permanent, featured, weekly }`, offers sorted by key; today by default |
| `PW.Economy.GetOffer(key) -> PW.EconomyOffer?` | Shared. `{ key, kind, id, name, price, rarity?, bundle, items }` |
| `PW.Economy.Featured(date?)`, `PW.Economy.Weekly(date?)` | Shared. The bundle keys of the daily and the weekly selection |
| `PW.Economy.GetCurrency(ply) -> number` | Shared (a client answers for the local player) |
| `PW.Economy.IsOwned(ply, kind, id) -> boolean` | Shared. Purchased (not the level unlock; for that use `PW.Progression.IsUnlocked`) |
| `PW.Economy.Buy(ply, key) -> boolean, string?` | Server. The reason on failure |
| `PW.Economy.RequestBuy(key)` | Client. Sends the request; the answer is the notification `PW_EconomyResult(result)` and `PW.Economy.LastResult` |

Keys are `"<kind>:<id>"` (`"models:swat"`, `"bundles:operator_pack"`).

Purchase rules (`_Quote`), the first failing reason is returned:

| Reason | Meaning |
| --- | --- |
| `badkey` | Not a string of the form `"<kind>:<id>"`: the kind is lowercase letters and `_`, the id letters, digits and `_` |
| `unknown` | No such offer (no price, an unresolved bundle, a missing entity) |
| `notoffered` | A bundle the rotation does not feature today |
| `owned` | The key is owned; a bundle whose items are all owned |
| `unlocked` | A single entity the player's level already unlocks |
| `funds` | The price is above the currency |

A bundle is charged in full even when some items are owned; it grants every item and itself. A successful purchase
deducts the currency, records the keys as owned, sends the progression delta at once (the client file applies it through
the delta path) and fires the server notification `PW_EconomyPurchase(ply, key, price)`.

## Net messages

Explicit `net.Write*`, no `net.WriteTable`.

| Message | Direction | Fields |
| --- | --- | --- |
| `pw_economy_buy` | client to server | `key` string. `PW.Net.Receive`: `who = "any"`, rate 2 per second, `maxLen` = `PW.Economy.RequestMaxBytes` (97), owner = the module (dropped while disabled) |
| `pw_economy_result` | server to the owner | `ok` bool, `key` string, `reason` string, `currency` UInt(32) |

`PW.Economy.RequestMaxBytes` (97) bounds the message, so a forged long key is dropped before the handler. The server decodes the key, then `_Quote` validates it; a malformed key, a bot sender or an unaffordable offer changes
nothing.
