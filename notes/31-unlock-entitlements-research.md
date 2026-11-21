# Unlocks beyond levels: current system and an entitlement design

Status: research and proposal, 2026-11-21. Not a decision. `design/06-progression.md` stays authoritative until the
user approves the revisions listed in [the change record](../changes/in-progress/unlock-entitlements.md). Line numbers
refer to branch `docs/plan-mwbase-stims-unlocks-challenges` at `cf7c4ed`; an implementer must re-check them.

## 1. Question

The user wants unlocks controlled programmatically, not only by player or weapon level: weapons, perks, equipment,
streaks, wildcards, attachments, camos, operators (`models`) and calling cards must be openable by any source, starting
with weekly challenge rewards (`changes/planned/weekly-challenges.md`, note 32, planned in parallel). This note
inventories every place where "is X unlocked or available" is decided today, the data flow, storage and trust model,
networking and tests, then proposes a generic design.

All paths below are relative to `addons/privatewar/lua/privatewar/` unless stated otherwise.

## 2. Current system

### 2.1 The authority today

There is one pure rule function and three public wrappers, all in the `progression` module:

| Function | File | Role |
| --- | --- | --- |
| `PW.Progression._IsUnlocked(view, kind, id)` | `modules/progression/sh_unlocks.lua:80-95` | Pure decision for an entity or an option |
| `PW.Progression._LockedOptions(view, weaponId, build)` | `sh_unlocks.lua:122-140` | Pure: locked option ids of a weapon build (curated level and the count rule) |
| `PW.Progression._AttachmentLimit(level, cap)` | `sh_unlocks.lua:53-55` | Pure count limit |
| `PW.Progression.IsUnlocked / LockedOptions / AttachmentLimit / GetWeaponLevel` | `modules/progression/shared.lua:68-84` | Shared wrappers; build the view with `viewOf(ply)` |
| `PW.Progression._ViewOf(store, ply, lookup)` | `modules/progression/init.lua:207-220` | Server view: level, weapon level, `unlockAll`, `maxAttachments`, `owned` (only while economy is active) |
| `PW.Progression._LocalView()` | `modules/progression/cl_init.lua:37-54` | Client view: levels from `pw_progression_levels`, `owned` from the local file |
| `PW.Progression._ViewFromLevels(levels, lookup, owned)` | `modules/progression/sh_storage.lua:130-136` | Builds a view from the levels message |
| `PW.Progression._OwnedActive()` | `shared.lua:55-58` | Purchases count only while the economy module is valid (06 d.6) |

The rules (`sh_unlocks.lua` header and `docs/api/progression.md` "Unlock checks"):

1. An entity of any registry kind is unlocked when the player level reaches its `Unlock` (integer or `{ level = N }`).
   No `Unlock` means open from the start.
2. A curated attachment (`Attachments[opt].Unlock`) or camo (`Camos[id].Unlock`) opens by weapon level. `Hidden`
   never opens, not even with `unlockall`.
3. An uncurated, non-cosmetic attachment opens by count: the weapon level is the number allowed, capped by
   `loadout.maxattachments`.
4. `progression.unlockall` opens rules 1 to 3; `Hidden` stays hidden.
5. While the economy module is active, an owned key `"<kind>:<id>"` opens the item (camo key
   `"camos:<weapon>:<option>"`), and an entity with `Price` and no `Unlock` is for sale only.

Evaluation order inside `_IsUnlocked` for entities: unknown entity, then `unlockAll`, then owned, then price-only,
then level. For options: unknown weapon, `Hidden`, owned, then `unlockAll` or weapon level.

### 2.2 Every decision site (grep of the whole `addons/` tree)

Unlock decisions:

| Site | What it decides | How |
| --- | --- | --- |
| `modules/loadout/sv_classes.lua:98-112` (`contextFor`) | Server context of one human: `ctx.isUnlocked`, `ctx.lockedOptions`, `ctx.attachmentLimit` | Wraps `PW.Progression`; `attachmentLimit` reads `progression.unlockall` directly and returns the weapon level |
| `modules/loadout/sh_classes_repair.lua:40` (`itemProblem`) | A locked item in any slot (weapons, perks, equipment, streaks, wildcards) is removed with reason `locked` | `ctx.isUnlocked(slot.kind, id)` |
| `modules/loadout/sh_gunsmith.lua:61-73` (`checkLocked`) | A locked curated option is removed from a build | `ctx.lockedOptions` one option at a time |
| `modules/loadout/sh_gunsmith.lua:94-118` (`counted`, `checkLimit`) | Uncurated options past the level limit are removed | Reads `Attachments[opt].Unlock`, `Cosmetic`, `Camos` directly |
| `modules/operators/init.lua:45-49` (`engineUnlocked`) | Server accepts an economy operator choice only when unlocked | `PW.Progression.IsUnlocked(ply, "models", id)` |
| `modules/operators/cl_init.lua:14-19` (`localUnlocked`) | Picker locks | Same, local player |
| `modules/economy/init.lua:125-139` (`_Context`) | Quote: `owned` (purchases) and `unlocked` (level only, owned forced off) | `_IsUnlocked` with `view.owned = false` |
| `modules/economy/sh_purchase.lua:36-46` (`ownedReason`) | `owned` and `unlocked` refusal reasons | The context above |
| `modules/ui_kit/cl_store.lua:46-60` (`LiveFacts`) | Store states | `IsOwned`, `IsUnlocked` |
| `modules/ui_kit/sh_store.lua:79-91, 299-303` | `owned` / `unlocked` / `locked` badges | The facts above |
| `modules/loadout_ui/cl_init.lua:111-114` (`LiveInput`) | Editor `ctx.isUnlocked` (client) | `PW.Progression.IsUnlocked(LocalPlayer(), ...)` |
| `modules/loadout_ui/sh_editor.lua:120-131, 175-185` | Locked rows and options | `ctx.isUnlocked` |
| `modules/autounlock/sh_rules.lua:285-296` (`_EntryFor`) | Which `Unlock` fields T-11.7 fills | Skips `Price` weapons and existing `Unlock`; soft registration |

Lock display (requirement text) is implemented three times, each re-parsing `Unlock` itself:

| Site | Text |
| --- | --- |
| `modules/loadout_ui/sh_editor.lua:35-50` (`required`, `LockText`) | `LV n` / "Unlocks at level n"; `STORE` / "Buy it in the store"; `LOCKED` |
| `modules/loadout_ui/sh_gunsmith.lua:28-42, 86-102, 145-158, 200-205` | `LV n` / "Unlocks at weapon level n"; `FULL` (count). Uses the weapon level and `unlockAll` from the view, ignores ownership |
| `modules/operators/shared.lua:25-32`, `sh_rules.lua:42-50, 169-177` | `<price> CR` / "Buy it in the STORE"; `LV n`. `tonumber(entity.Unlock)` ignores the `{ level = N }` form |
| `modules/ui_kit/sh_progress.lua:39-75` (`NextUnlocks`) | Next unlocks by level on PROGRESS |

Other places that look related but do not decide unlocks: `screens/loadout_gunsmith.lua:64, 177` (shows weapon level or
"everything unlocked"), `modules/loadout/sh_budget.lua:112-122` (camos and cosmetics are free in Pick X), and the
`PW.Economy.IsOwned` wrapper (`modules/economy/shared.lua:112-114`). Integration addons: `privatewar-arc9`,
`privatewar-infection` and `privatewar-dev` contain no unlock logic (only a dev screen sample string). The T-11.7
stat-based levels live in the core addon, `modules/autounlock/`.

Content that sets `Unlock` or `Price`: 12 perks (`Unlock = 1`), 4 support streaks (`Unlock = 1`), the fixture
`privatewar_fixtures/examples/weapons/weapon_smg1.lua` (`Unlock = 1`), models (`Price` 600 to 2000), cards (`Price` 150
to 450), bundles. No shipped file uses `Camos`. Equipment, wildcards and classes set neither.

### 2.3 Bots

Bots are never checked against unlocks, by decision (`design/05-loadout.md` d.14 item 3, `design/06-progression.md`
d.7):

- `modules/bots_loadouts/init.lua` validates pool classes with `PW.Loadout.Validate` under match settings only; players'
  classes enter the pool already repaired for their owner.
- `modules/operators/sh_rules.lua` `BotPick` ignores locks.
- Progression and economy ignore bots (`init.lua:186-191`, `economy/init.lua:76-80`).
- The mandatory test `bots_loadouts.lua` "Mandatory (T-5.13): a player's class used by a bot is checked against match
  settings, not progression" stubs `PW.Progression.IsUnlocked` and asserts it is never called; the ARC9 generated
  loadout test `bots_arc9_generated_native.lua:110` does the same.

The refactor must keep this: no unlock call on any bot path.

### 2.4 Data flow

```text
client progression.json --pw_progression_upload--> server session state (xp, weapons, currency, owned)
                                                      |  _ViewOf -> IsUnlocked / LockedOptions
                                                      |  class repair (pw_loadout_classes, pick, spawn)
                                                      |  operator choice (pw_operator_model)
server gains (XP, currency, purchases) --pending--> pw_progression_delta (10 s, phase change, purchase) --> client file
server levels --pw_progression_levels--> client view (_LocalView) --> UI locks
```

- A purchase: `pw_economy_buy` → `_Buy` → `_SpendCurrency`, `_GrantOwned`, immediate `_Flush` → the client applies
  the delta to its file. `_GrantOwned` (`sv_wallet.lua:56-70`) is already a server-side "grant" primitive, but only for
  purchases and stored in the purchase set.
- A level change resends levels and refreshes classes (`sv_storage.lua:73-76`). A purchase does not call
  `RefreshClasses`; the class state catches up at the next refresh (upload, pick, phase change).
- The client view of `owned` comes from the client's own file, not from the server; both sides have the same set
  because the server's set started from the upload and every change travels in deltas.

### 2.5 Storage and trust

`design/06-progression.md` d.0 and d.5, `DESIGN.md` "Decided": progression is local per player, uploaded on join and
forgeable (accepted). Today:

- `data/privatewar/progression.json`, version 2: `{ v, xp, weapons, currency, owned = [keys], batch }`.
- The server sanity-checks shape and bounds only (`_CheckState`, `_CheckOwned`): numbers clamped, keys must match
  `^%l[%l_]*:[%w_%-%.:]+$`, at most 96 bytes, at most 256 keys (first ones in key order). It does not check that an
  owned key was really bought; a hand-edited file unlocks anything. Unknown keys (content not installed on this host)
  are kept, which is right: the client file is never rewritten from the server's view.
- What the host does validate is the use of an unlock: class repair, gunsmith checks and the operator check run on the
  server against the server's view. A forged client choice that the server's view considers locked is removed.
- Upload size: `UploadMaxBytes` is about 42 KB worst case (256 weapons and 256 keys); a net message is limited to
  64 KB.
- Version skew between friends' servers matters: client Lua comes from the server the player joins. An older server
  version runs its own `cl_init.lua`, reads the newer file with its own `_FileFromJson` and rewrites it with its own
  `_FileToJson`, dropping fields it does not know and capping `owned` at 256. Anything stored in `progression.json`
  that an old version does not understand is lost the first time the player plays on an old server. The wire format
  between one server and its clients never skews (same code).

### 2.6 Networking

| Message | Direction | Unlock content |
| --- | --- | --- |
| `pw_progression_upload` | C→S, once | `owned` keys |
| `pw_progression_delta` | S→C | `owned` keys added (purchases) |
| `pw_progression_levels` | S→C | Level, weapon levels, `unlockAll`, `maxAttachments` |
| `pw_economy_buy` / `pw_economy_result` | C→S / S→C | Purchase request and result |
| `pw_loadout_classes`, `pw_loadout_pick`, `pw_loadout_class_state` | both | Classes repaired with unlocks; state with reasons |
| `pw_operator_model` | C→S | Choice checked against unlocks |

All use explicit `net.Write*` (global rule 4).

### 2.7 Defects and inconsistencies found

1. **Camo levels are not enforced on the server.** `_LockedOptions` checks only `Attachments[opt].Unlock`; a camo
   listed in `Camos` is treated as cosmetic and skipped (`sh_unlocks.lua:131-138`). Only the gunsmith UI locks it
   (`loadout_ui/sh_gunsmith.lua:35-36, 89`). No shipped weapon uses `Camos`, so there is no live impact yet; it matters
   as soon as camos become rewards.
2. **Owned options are ignored by build validation and by the gunsmith UI.** `_IsUnlocked("attachments"|"camos")`
   honours ownership, but `_LockedOptions` (the function the loadout uses) does not, and the UI reads only the weapon
   level. A purchased curated attachment below its level is removed on save. Bundles can sell camos today.
3. **Three copies of the requirement text**, and `operators/shared.lua:30` drops `{ level = N }`.
4. **`IsUnlocked` returns only a boolean**; every consumer re-derives the reason from the raw fields, so a new source
   (grant) would have to be taught to every UI file.
5. **No refresh after a purchase**: the class state shows a bought item as locked until the next refresh.
6. **Store copy assumes level is the only other source**: "Unlocked by your level" (`ui_kit/sh_store.lua:32, 203,
   234`); a granted item would be mislabelled.

### 2.8 Tests that cover unlocks today

| File | Cases |
| --- | --- |
| `lua/tests/privatewar/progression.lua` | "Unlock by curation: the player level for entities, the weapon level for options and camos"; "Unlock by count: the weapon level is the number of uncurated attachments, capped by the setting"; "Level from kills: weapon XP of kills raises the weapon level that the count rule reads"; "unlockall opens every level gate and the count limit; Hidden stays hidden"; "The public API exists and the classes repair uses the unlock context"; "Settings: the coefficients and unlockall come from the reader, the design defaults fill the rest" |
| `progression_storage.lua` | "Levels for the client: player level, weapon levels above 1, unlockall and the attachment cap"; "Client IsUnlocked: the view built from the received levels answers like the server"; "Join upload: validated and clamped, accepted once, then levels sent and classes refreshed"; "Level up: classes are refreshed and the levels resent at once; a plain gain does neither"; "Wire: upload, delta, levels and summary survive encode and decode"; "Wire: a forged count cannot make the decoder read past the size bound"; "File: JSON shape round trip; a malformed file gives an empty progression"; "The public API exists: MatchSummary on both realms, the client-side unlock checks" |
| `economy.lua` | "Purchase: deducts the currency, marks the item owned, and the unlock check answers true"; "Purchase: insufficient funds are rejected and nothing changes"; "Purchase: a bundle grants all its items and itself for one price"; "Purchase: bad keys, unknown offers, owned items and items the level already unlocks are refused"; "Purchase: the client file applies the purchase through the delta path, once"; "Storage: a v1 file (no currency, no purchases) loads with zero currency; the file round trips"; "SetState: currency and owned are clamped (negative, NaN, fractions, bad keys, too many)"; "Wallet: spending needs a whole amount the player can pay; granting counts only new items"; "Unlock rules: a priced entity without Unlock is for sale only; no economy, no prices"; "Unlock rules: a purchased camo opens, a Hidden camo stays hidden even when owned"; "Wire: state, delta, request and result survive encode and decode; a forged owned count is bounded" |
| `autounlock.lua` | "Spread: levels 1..55, 1-2 weapons per category open at level 1"; "Attachments: an option without numeric stats gets the middle level and is counted"; "Starters: weapons of the preset classes open at level 1 and count toward the open weapons"; "Run: soft registration, hand curation wins option by option"; "Merge: a weapon with a Price stays shop-only; curated fields are never overwritten"; "Setting off: no levels, the unlock by count stays"; plus the score, cache and live cases of the same file |
| `gunsmith.lua` | "Validate on save: a build of offered, unlocked, compatible options is accepted as it is"; "Validate on save: unknown, locked, conflicting and over-the-limit options are rejected"; "The attachment limit includes wildcards (match cap) and progression (weapon level)" |
| `loadout_classes.lua` | "Repair: unavailable items are removed and the rest is kept" |
| `ui_classes_gunsmith.lua` | "Allowed items: locked items are greyed with their unlock level, banned ones with the reason"; "Gunsmith: slots with their options, a curated option locked by its weapon level, Hidden skipped"; "Gunsmith: the weapon level limits uncurated attachments; a swap in the same slot stays allowed" |
| `ui_store_progress.lua` | "Store states: owned, unlocked by level, not enough currency, buyable, pending"; "Store states: a bundle is owned by its key or when every item is owned; never 'unlocked'"; "Bundle details: items with names, kinds, owned/unlocked/locked states and previews"; "Next unlocks: only above the current level, the closest first, Hidden left out" |
| `operators_names.lua` | "The list has the stock models and the economy models; owned and free ones open, others locked"; "Picker cards: Auto first, locked cards show the price or level and cannot be selected"; "Server: malformed, unknown and unowned requests preserve the previous choice and model"; "Ownership is checked at each request and spawn; later unavailable choices safely fall back"; "Bots get a valid model from the list (locks ignored) and keep it" |
| `bots_loadouts.lua`, `bots_arc9_generated_native.lua` | The T-5.13 mandatory case above; the ARC9 generated pool never calls `IsUnlocked` |
| `core_registry.lua` | "Soft registration fills only missing fields, per nested key, never overwrites" |

Mandatory cases in `TASKS.md`: T-4.9 ("unlock by curation vs unlock by count; `unlockall`"), T-4.10 (storage), T-4.12
("purchase deducts and unlocks"), T-11.7 ("registration is `soft`, so a hand-curated `Unlock` wins option by option;
the host setting off falls back to unlock by count"), T-5.13 (bots not checked against progression).

## 3. How others model it (short)

General industry knowledge, not verified for this note:

- **Call of Duty (MW2019, MWII/MWIII).** Sources: player rank (weapons, perks, equipment, streaks), weapon level
  (attachments), weapon challenges (camos), store bundles and blueprints (an item is usable before its rank unlock),
  battle pass tiers, limited-time events, and in MWII cross-weapon conditions (levelling one weapon unlocks another).
  The UI always says how to get a locked item: "Reach level 20", "Complete: 50 headshots", "Available in the store".
- **Common pattern** (game account services such as Steam Inventory and Epic ownership records, and in-house
  progression systems):
  1. *Conditions* are computed from progress (level, stats) and are not stored, so a curve change applies
     retroactively.
  2. *Entitlements* are stored ownership records with a source, a time and a grant id for idempotency and audit.
  3. Access is the union (OR) of conditions and entitlements, with a deny layer on top (hidden, banned, region) and an
     operator override.
  4. A grant from a reward system is idempotent by its grant id, so a retried claim never double-grants.
- Applied here: levels and weapon levels stay computed conditions; purchases and grants are entitlements; `Hidden`
  is the deny layer; `unlockall` and an addon hook are the override layer. Battle pass, events, challenges and admin
  commands all become entitlement producers, so none of them needs its own predicate in the core.

## 4. Proposed design (summary)

Full rails in the change record. Key points:

1. **One authority** `PW.Unlocks` (shared namespace implemented inside `modules/progression/`, progression lane):
   `IsUnlocked(ply, kind, id) -> boolean, reason`, `Requirement(ply, kind, id) -> PW.UnlockRequirement` for the UI,
   `Grant`, `Revoke`, `HasClaim`, `IsEntitled`, `ListEntitled`, `Describe`. `PW.Progression.IsUnlocked`,
   `LockedOptions` and `AttachmentLimit` stay as compatible wrappers.
2. **Keep the `(kind, id)` signature** instead of an item-ref table: it is what every caller uses, it allocates nothing,
   and the existing key form `"<kind>:<id>"` (camo `"camos:<weapon>:<option>"`) already encodes the parent weapon.
   Kinds are the registry kind names (`weapons`, `perks`, `equipment`, `streaks`, `wildcards`, `models`, `cards`) plus
   the pseudo-kinds `attachments` and `camos`. For APIs that take items (grants, previews) accept the bundle item shape
   `{ kind, id, weapon? }` (`docs/api/economy.md`), so challenge rewards and bundles share one item format.
3. **Fixed ordered sources, not a new kind.** Evaluation order: unknown, `Hidden` (deny), `PW_UnlockOverride` hook,
   `unlockall`, grant entitlement, purchase entitlement (economy active), `Unlock = false` (grant only), price-only,
   level or weapon level. A file kind `unlock_sources/` was considered and rejected for now: a predicate needs private
   per-player data, and every known future source (challenge, event, battle pass, admin) is a grant producer. The
   override hook covers addons that need a computed rule.
4. **Item schema**: keep integer and `{ level = N }`; add `false` (no level path; only an entitlement opens it) and the
   table keys `level = false` and `hint = "<text or #phrase>"`. `soft` registration keeps working because the registry
   preserves `false` and T-11.7 writes only when `Unlock == nil`.
5. **Storage without migration risk**: grants live in a new client file `data/privatewar/unlocks.json` (version 1:
   `grants` with source, time and grant id; `claims`; `batch`). `progression.json` stays at version 2 and keeps
   purchases in `owned`. An older server version never touches the new file, so grants survive version skew; no
   progression file migration is needed.
6. **Networking**: new `pw_unlocks_upload` (C→S, once, keys and claim ids only, bounded under 64 KB); the existing
   `pw_progression_delta` gains `granted`, `revoked` and `claims` lists (same batch idempotency). Grants flush at once,
   then classes are refreshed (fixes defect 5 for grants and purchases).
7. **Validation**: the server keeps validating every use (class repair, gunsmith, operator). `LockedOptions` becomes
   per-option through the authority, so camo levels and entitlements are enforced on the server (defects 1 and 2);
   entitled uncurated options do not count toward the level limit.
8. **Trust**: unchanged; `unlocks.json` is forgeable like the rest (d.0). The server checks shape and bounds and, for
   `Grant`, that the item resolves.
9. **Bots**: unchanged; no unlock call on bot paths; `Grant` refuses bots.
10. **UI**: one requirement formatter replaces the three copies; locked items say why and how; granted items get a
    `NEW` badge (client seen-set `unlock:<key>` in `ui_seen.json`) and a HUD toast through the medal popup queue.

## 5. Risks

1. Preset classes containing a grant-only item become unavailable for players without the grant; content authors must
   not put `Unlock = false` items into presets (documented rule, test in the record).
2. A `soft` registration that sets a table `Unlock` on an entry that already has a table `Unlock` merges keys (registry
   `fillMissing`), for example `{ level = 10 }` plus `{ hint = "x" }`. That is the intended per-key semantics; it is
   documented, not prevented.
3. `IsUnlocked` gains a hook call per check. UI lists call it per option; this is a question hook with few listeners.
   No allocation is added on the hot path; the gunsmith already builds tables per refresh.
4. Moving camo enforcement to the server changes behaviour for any third-party weapon entry that curates `Camos` with
   levels: saved builds with such camos below the level are now repaired. Intended (the UI already showed them locked).
5. Multi-lane change (progression, loadout, ui, operators). Steps in the record are grouped so each lane's files change
   in their own commits; the orchestrator owns the `docs/api/` updates.
