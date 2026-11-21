# Programmatic unlocks and entitlements

Status: `planned`

Recorded: 2026-11-21

Approval (2026-11-22): the user approved every design change proposed in this record and the recommended
default of every open question, except where an answer below says otherwise. This approves the design
direction for implementation; push, PR, merge to `main` and publication still need separate approval.

Research: [notes/31-unlock-entitlements-research.md](../../notes/31-unlock-entitlements-research.md) (current system,
every decision site, defects found, comparison with other games).

This record is tracking, not authorization: it does not authorize implementation, changes to decided design or frozen
API contracts, Steam Deck access or publication. Each needs the user's explicit approval. Line numbers were taken at
`cf7c4ed` on branch `docs/plan-mwbase-stims-unlocks-challenges`; re-check them before editing. Paths without a prefix
are relative to `addons/privatewar/lua/privatewar/`.

Dependent work: the weekly challenges record (`changes/planned/weekly-challenges.md`, note 32, planned in parallel)
grants its rewards through the interface in section 10. Nothing in this record depends on it.

## 1. User request

- [ ] Recorded: "In the future I want a refactor so that items are unlockable not only by level: in general it should be
  possible to control programmatically what is unlocked and what is not. This can be weapons, perks, skins (camos,
  operators) and so on." Weekly challenges will then grant unlocks (weapons, skins and others) as rewards; this
  refactor is their foundation (a reward is a granted entitlement).

## 2. Design changes requiring approval

All in `design/06-progression.md` unless stated. Proposed wording; the user may change it. Nothing in `design/` is
edited by this record.

- [ ] **New d.8 "Unlock authority and entitlements"** (proposed text):
  1. One authority answers whether an item is unlocked for a player and why: `PW.Unlocks` (progression module).
     Items are entities of any registry kind and weapon options (`attachments`, `camos`, keyed `<weapon>:<option>`).
  2. Sources, in this order; the first that decides wins: unknown item (locked); `Hidden` option (never offered, beats
     everything); the `PW_UnlockOverride` question hook (addons); `progression.unlockall`; a granted entitlement; a
     purchased entitlement (only while the economy module is active, d.6); `Unlock = false` (no level path, locked);
     price-only (d.6); player level for entities, weapon level for options; no `Unlock` means open.
  3. Entitlements are stored ownership records: purchases (d.6) and grants. Any code may grant or revoke a grant
     through the API (challenge rewards, events, battle pass, admin commands). Grants are idempotent by grant id.
     Revoke removes grants only, never purchases.
  4. Levels stay computed conditions and are never stored as entitlements, so curve changes apply retroactively.
  5. The authority also gives the requirement of a locked item for the UI ("Unlocks at level 20", "Buy it in the STORE
     for 600 CR", a reward hint).
  6. Bots are never checked against unlocks (unchanged, `05-loadout.md` d.14) and cannot receive grants.
- [ ] **d.1** first bullet, replace "Player level (XP) unlocks entities through their `Unlock` field" with: "Player level
  (XP) unlocks entities through their `Unlock` field; other sources (purchases, grants, `unlockall`, addons) follow
  d.8." Replace "After MVP: prestige, challenges (for example "100 headshots" → camo)" with "After MVP: prestige;
  challenges grant entitlements through d.8".
- [ ] **d.2** add the `Unlock` forms: "`Unlock` is an integer, `{ level = N }`, `false` (only an entitlement opens it),
  or a table with `level` (integer or `false`) and an optional `hint` (text or `#phrase` shown while locked). The same
  forms apply to attachment and camo curation." Replace "Camos ... MVP unlocks them by weapon level only; challenge
  unlocks come later" with "Camos unlock by weapon level or by an entitlement (d.8); the server enforces camo levels
  like attachment levels. An entitled option is not counted toward the weapon-level attachment count."
- [ ] **d.5** add: "Granted entitlements live in a second client file `data/privatewar/unlocks.json` (grants with
  source, time and grant id; claimed grant ids), uploaded on join in its own message and changed through the same
  deltas. `progression.json` keeps its format (version 2). A separate file keeps grants safe when the player joins a
  server running an older version." Replace "At match end the client receives a summary (XP earned, levels gained,
  unlocks)" with "(XP earned, levels gained)" unless the user keeps unlocks in the summary (open question 12).
- [ ] **d.6** replace "an item is unlocked if the level is reached **or** it was bought" with "an item is unlocked by
  any source of d.8; a purchase counts only while the economy module is active, a grant always counts". Add: "An item
  the player already owns or was granted cannot be bought (reason `owned`)."
- [ ] **d.7** replace "owned or free ones are selectable, locked purchasable ones show as locked with their price (or
  level)" with "unlocked ones (d.8) are selectable; locked ones show their requirement (price, level or reward)".
- [ ] `design/05-loadout.md` d.12: no wording change (the server already checks "entities exist, budget, unlocks");
  confirm that "unlocks" now means d.8, including camo levels and entitlements.
- [ ] `DESIGN.md` "Decided" (progression forgeable): no change; `unlocks.json` is forgeable too.

## 3. Target architecture

### 3.1 Modules and ownership

- [ ] `PW.Unlocks` is a shared namespace implemented inside `modules/progression/` (progression lane): it needs the
  progression state, store, deltas and upload. No new module, no new kind.
- [ ] `PW.Progression.IsUnlocked`, `LockedOptions`, `AttachmentLimit` stay as compatible wrappers (first return value
  only) that look up `PW.Unlocks` at call time.
- [ ] Presence semantics stay as today: callers keep their "no progression module, nothing locked" fallback.
- [ ] Consumers in other lanes change only their call sites: `modules/loadout/` (loadout lane), `modules/operators/`
  (loadout/ui per T-11.9), `modules/loadout_ui/`, `modules/ui_kit/`, `hud/`, `screens/` (ui lane),
  `modules/economy/` (progression lane). The orchestrator owns `docs/api/` and `TASKS.md` changes.
- [ ] Rejected alternative (record only): a kind `unlock_sources/`. Predicates need private per-player data, and all
  known future sources are grant producers; `PW_UnlockOverride` covers computed addon rules (open question 4).

### 3.2 Item references and keys

- [ ] Kind names are registry kind names: `weapons`, `perks`, `equipment`, `streaks`, `wildcards`, `models`, `cards`
  (any registry kind except `bundles` and `classes`), plus `attachments` and `camos`.
- [ ] A key is `"<kind>:<id>"` exactly as today's owned keys (`sh_wallet.lua:17-25`): options are
  `"attachments:<weapon>:<option>"` and `"camos:<weapon>:<option>"`. Same pattern `^%l[%l_]*:[%w_%-%.:]+$`, at most
  `MaxKeyLength` (96) bytes.
- [ ] APIs that take items accept the bundle item shape (`docs/api/economy.md` "Kinds"), so challenge rewards and
  bundles share one format:

```lua
---@class PW.UnlockItem                 -- schema, same shape as a bundle Items entry
---@field kind string                  -- registry kind, "attachments", "camos" ("camo" accepted as an alias)
---@field id string                    -- entity id, or the option id for attachments and camos
---@field weapon? string               -- required for attachments and camos
```

### 3.3 The `Unlock` field schema

- [ ] Normalised by one pure function `PW.Unlocks._Spec(unlock)` into:

```lua
---@class PW.UnlockSpec                 -- schema of a normalised Unlock field
---@field level integer|false          -- 0 = open; N = level N; false = no level path (entitlement only)
---@field hint? string                 -- shown while locked; plain text or "#phrase", at most 128 bytes
---@field reward? string               -- informational: the grant source that rewards it ("challenge"); pattern of a source
---@field declared boolean             -- the raw field was not nil (needed by the price-only rule)

---@alias PW.UnlockField integer|false|{ level?: integer|false, hint?: string, reward?: string }   -- accepted raw forms
```

- [ ] Every form and its mapping (backward compatible: all existing forms keep their meaning):

| Raw `Unlock` | Today | After | Notes |
| --- | --- | --- | --- |
| `nil` | Open; with `Price` and economy active: for sale only | `{ level = 0, declared = false }`, same price-only rule | Unchanged |
| `12` | Level 12 | `{ level = 12 }` | Floored; 0 or below means 0 |
| `{ level = 12 }` | Level 12 | `{ level = 12 }` | Unchanged |
| `false` | Treated as 0 (open) | `{ level = false }`: only a grant or a purchase opens it | New meaning; no shipped file uses it (verify with grep) |
| `{ level = false, hint = "..." }` | Open | Entitlement only, with hint | New |
| `{ level = 20, hint = "..." }` | Level 20 | Level 20, hint shown while locked | New key |
| `{ level = false, reward = "challenge" }` | Open | Entitlement only; listed by `ListRewards("challenge")` (weekly bonus pool) | New key; `reward` never opens anything by itself |
| `{ hint = "..." }` (no level) | Open | Open (`level = 0`); the hint is unused | Documented |
| `true`, a string, other types | Open | Open (`level = 0`), one debug log line per entity | Unchanged result |

- [ ] Attachment and camo curation (`Attachments[opt].Unlock`, `Camos[id].Unlock`) accept the same forms; the level is
  the weapon level.
- [ ] `soft` registration (`01-extensibility.md`, `docs/api/core.md` `Register`): the registry keeps `false` (it fills
  only `nil`) and merges nested tables per key. T-11.7 (`modules/autounlock/sh_rules.lua:285-296`) writes `Unlock` only
  when it is `nil` and writes options as `{ Unlock = level }`; a hand-curated `false` or table form therefore always
  wins. A soft table `Unlock` merged into an existing table `Unlock` combines keys (intended, documented).
- [ ] Content rule (documented in `docs/api/progression.md`): preset classes (`classes/`) must not reference
  `Unlock = false` items, or the preset becomes unavailable for players without the grant.

### 3.4 Sources and precedence

- [ ] The pure decision `PW.Unlocks._Decide(view, kind, id) -> boolean, PW.UnlockReason` evaluates in this order; the
  first row that applies returns:

| Order | Condition | Result | Reason |
| --- | --- | --- | --- |
| 1 | Malformed id, unknown kind or entity (options: unknown weapon) | locked | `unknown` |
| 2 | Option curated `Hidden = true` | locked | `hidden` |
| 3 | `view.override(kind, id)` returns a boolean | that boolean | `override` |
| 4 | `view.unlockAll` | open | `unlockall` |
| 5 | `view.granted(key)` | open | `grant` |
| 6 | `view.owned ~= nil and view.owned(key)` (economy active) | open | `purchase` |
| 7 | Spec `level == false` | locked | `grant_only` |
| 8 | Entity, `Unlock` not declared, `Price >= 1`, `view.owned ~= nil` | locked | `price` |
| 9 | Entity: `view.level >= level`; option: `view.weaponLevel(weapon) >= level` | open or locked | `level` / `weapon_level` (`default` when the level is 0) |

```lua
---@alias PW.UnlockReason "unknown"|"hidden"|"override"|"unlockall"|"grant"|"purchase"|"grant_only"|"price"
---| "level"|"weapon_level"|"default"
```

- [ ] An uncurated attachment keeps today's answer for a single option (open, `default`); the count rule stays a
  property of a build (`LockedOptions`, section 3.8).
- [ ] The view gains optional fields; the existing fields and `owned` keep their names and meaning, so existing pure
  tests that build views keep working:

```lua
---@class PW.ProgressionView            -- schema; new fields marked NEW
---@field level integer
---@field weaponLevel fun(weaponId: string): integer
---@field lookup PW.LoadoutLookup
---@field unlockAll boolean
---@field maxAttachments integer
---@field owned? fun(key: string): boolean                    -- purchases; nil while the economy module is inactive
---@field granted? fun(key: string): boolean                  -- NEW: grants; nil = none
---@field override? fun(kind: string, id: string): boolean?   -- NEW: PW_UnlockOverride bound to the player
---@field hint? fun(kind: string, id: string): string?        -- NEW: PW_UnlockHint (requirements only)
```

### 3.5 Requirement (for the UI)

```lua
---@class PW.UnlockRequirement          -- schema
---@field unlocked boolean
---@field reason PW.UnlockReason
---@field level? integer               -- the player level asked for (reason "level")
---@field weaponLevel? integer         -- the weapon level asked for (reason "weapon_level")
---@field price? integer               -- set when the item can be bought now (Price >= 1, economy active, not owned)
---@field hint? string                 -- PW_UnlockHint answer, else the spec hint
---@field lockText? string             -- short badge; nil when unlocked or hidden
---@field text? string                 -- one sentence; nil when unlocked or hidden
```

- [ ] Texts (one pure formatter `PW.Unlocks.LockText(req) -> lockText, text`; existing UI strings kept where tests
  assert them):

| Reason | `lockText` | `text` |
| --- | --- | --- |
| `level` | `LV <n>` | `Unlocks at level <n>` |
| `weapon_level` | `LV <n>` | `Unlocks at weapon level <n>` |
| `price` | `<n> CR` | `Buy it in the STORE for <n> CR` |
| `grant_only` with `price` | `<n> CR` | `Buy it in the STORE for <n> CR` (the hint, if any, as a second line in the details panel) |
| `grant_only` with a hint | `REWARD` | the hint (a `#phrase` resolved by the UI) |
| `grant_only` without a hint | `REWARD` | `Earned as a reward` |
| `override` | `LOCKED` | `Locked on this server` |
| `unknown` | `LOCKED` | `Not available` |
| `hidden`, any unlocked reason | nil | nil |

- [ ] A view-free variant `PW.Unlocks._StaticRequirement(entity, isOption)` gives the same texts from the definition
  alone (used when a UI input has no requirement function, so the existing UI tests stay valid).

### 3.6 Storage, version and migration

- [ ] `progression.json` is unchanged: version 2, `owned` keeps purchases only (`docs/api/progression.md` "File").
  No version bump, no migration of this file.
- [ ] New client file `data/privatewar/unlocks.json` (`PW.Unlocks.FilePath = "privatewar/unlocks.json"`,
  `PW.Unlocks.FileVersion = 1`):

```lua
---@class PW.UnlocksFile                -- schema of unlocks.json
---@field v integer                    -- 1
---@field grants table<string, PW.UnlockGrantMeta>   -- key -> meta
---@field claims table<string, integer>              -- grant id -> unix time it was claimed
---@field batch PW.ProgressionBatch                  -- last applied delta, same rule as progression.json

---@class PW.UnlockGrantMeta
---@field source string                -- "challenge", "event", "admin", ...; pattern ^%l[%l_]*$, at most 16 bytes
---@field at integer                   -- unix time of the grant (server os.time()), 0 when unknown
---@field grant? string                -- grant id, pattern ^[%w_%-%.:]+$, at most 64 bytes
```

```json
{ "v": 1,
  "grants": { "camos:arc9_eft_ak74:gold": { "source": "challenge", "at": 1763700000, "grant": "weekly:2026-W47:3" } },
  "claims": { "weekly:2026-W47:3": 1763700000 },
  "batch": { "session": 123, "seq": 7 } }
```

- [ ] Limits (constants on `PW.Unlocks`): `MaxGrants` 384, `MaxClaims` 256, `MaxSourceLength` 16,
  `MaxGrantIdLength` 64, `MaxHintLength` 128, `MaxGrantPerCall` 32, `MaxDeltaGrants` 32, `MaxDeltaRevokes` 32,
  `MaxDeltaClaims` 8. Key length and pattern reuse `PW.Progression.MaxKeyLength` and the owned-key pattern.
- [ ] Reading: a missing, empty, non-JSON or wrong-shaped file reads as empty; entries with a bad key, source, grant id
  or time are dropped; over `MaxGrants` the first keys in key order are kept; over `MaxClaims` the newest by time are
  kept (ties by id). A hand-edited file never errors.
- [ ] Migration from the current format: none needed. A client with only `progression.json` v1 or v2 has purchases in
  `owned` (listed as entitlements with source `purchase`) and no grants. The new file is created on the first applied
  grant delta.
- [ ] Version skew: an older server version never reads or writes `unlocks.json`, so grants survive; they are simply
  not honoured on that server.

### 3.7 Network messages

No `net.WriteTable`; explicit `net.Write*`; receivers through `PW.Net.Receive`.

- [ ] **`pw_unlocks_upload`** (new), client to server, sent at `InitPostEntity` right after `pw_progression_upload`.
  `PW.Net.Receive` with `who = "any"`, `rate = 0.5`, `maxLen = PW.Unlocks.UploadMaxBytes`, `owner` = the progression
  module. Accepted once per connection. Payload: `version` UInt(8) (1); `grants` UInt(16), then that many key
  strings; `claims` UInt(16), then that many grant id strings. Grant metadata is not uploaded (the server does not need
  it). `UploadMaxBytes = 1 + 2 + MaxGrants * (MaxKeyLength + 1) + 2 + MaxClaims * (MaxGrantIdLength + 1)` = 53 893.
  Validation: a count above its maximum makes the decoder stop and keep nothing of that list; every key and id is
  checked like the file; duplicates collapse. Keys of content not installed on this host are kept.
- [ ] Merge on upload: the session grants and claims become the union of the upload and anything granted before it
  arrived; a `Revoke` before the upload is refused (`notready`). Then classes are refreshed (`store.refresh(ply)`).
- [ ] **`pw_progression_delta`** (extended), server to owner, appended after the existing `owned` list:
  `granted` UInt(8) (at most `MaxDeltaGrants`) x (`key` string, `source` string, `grant` string, empty when none,
  `at` UInt(32)); `revoked` UInt(8) (at most `MaxDeltaRevokes`) x `key` string; `claims` UInt(8) (at most
  `MaxDeltaClaims`) x (`grant` string, `at` UInt(32)). Counts are capped on both sides. The worst-case delta stays
  below 64 KB (about 9.5 KB added).
- [ ] The client applies the unlocks part with its own batch check on `unlocks.json` (union of grants keeping the
  existing meta of a key already present, removal of revoked keys, claims added and pruned), writes the file once per
  applied delta and fires `PW_UnlockGranted` and `PW_UnlockRevoked` locally.
- [ ] Write order on the client (weekly challenges D-WC6): for one delta, `unlocks.json` (claims and grants) is written
  before `progression.json` (XP and currency). A crash between the two writes can lose that reward's XP and currency
  but never applies them twice, because the claim is already persisted.
- [ ] Reward batching: `Grant` flushes the player's pending delta. A caller that also pays XP or currency for the same
  reward queues them first (`PW.Progression.AddXP`, `AddCurrency`) and calls `Grant` last, so claim, items, XP and
  currency travel in one batch.
- [ ] `pw_progression_levels`: unchanged. The client knows `unlockall` from it and evaluates hooks locally.
- [ ] `pw_economy_buy` and `pw_economy_result`: unchanged wire; the reason `owned` now also covers granted items.

### 3.8 Server validation of client choices

- [ ] Class repair (`pw_loadout_classes`, `pw_loadout_pick`, phase change, refresh): `ctx.isUnlocked` answers through
  the authority (grant-only items removed as `locked` until granted).
- [ ] Gunsmith builds: `PW.Progression.LockedOptions` judges each option through `_Decide` when the option is curated
  (`Attachments[opt].Unlock ~= nil`), listed in `Camos`, or entitled; this enforces camo levels on the server and
  honours purchased and granted options (fixes defects 1 and 2 of the research). Other non-cosmetic options are
  counted; entitled options are not counted. The loadout context gains `entitledOption(weaponId, option) -> boolean`
  so `modules/loadout/sh_gunsmith.lua` `counted` skips entitled options.
- [ ] Operator choice (`pw_operator_model`): through the authority at request and at every spawn (unchanged flow).
- [ ] Economy quote: `unlocked` = `_Decide` on a view without entitlements (level, default, unlockall, override);
  `owned(key)` = purchased or granted.
- [ ] After a grant, a revoke or a purchase the server calls `store.refresh(ply)` (classes re-checked at once).
- [ ] Calling cards have no consumer yet; when one is added it must check the authority on the server.

## 4. Public API

Server functions mutate; shared functions answer on the server for any human and on a client for the local player.

```lua
---@class PW.UnlocksLib
---Shared. The decision and its reason (section 3.4). A non-human or invalid player answers as today's view does.
---@field IsUnlocked fun(ply: Player, kind: string, id: string): boolean, PW.UnlockReason
---Shared. The requirement of an item for the UI (section 3.5).
---@field Requirement fun(ply: Player, kind: string, id: string): PW.UnlockRequirement
---Shared, pure. Short badge and sentence of a requirement; nil, nil when unlocked or hidden.
---@field LockText fun(req: PW.UnlockRequirement): string?, string?
---Shared. Purchased (economy active) or granted.
---@field IsEntitled fun(ply: Player, kind: string, id: string): boolean
---Shared. Every entitlement by key. Server: grants have source "grant" and at 0 unless granted this session.
---@field ListEntitled fun(ply: Player): table<string, PW.UnlockGrantMeta>
---Shared. The enabled ids of a kind that are unlocked for the player, sorted.
---@field ListUnlocked fun(ply: Player, kind: string): string[]
---Shared. Whether a grant id was already claimed.
---@field HasClaim fun(ply: Player, grant: string): boolean
---Server. Grants items; idempotent by opts.grant. Returns how many keys were new, and a refusal reason or nil.
---Refusals: "bot", "badplayer", "badsource", "badgrant", "badkey", "unknown", "toomany", "full", "claimed".
---Flushes the delta at once, refreshes classes, fires PW_UnlockGranted when at least one key was new.
---@field Grant fun(ply: Player, items: (PW.UnlockItem|string)[], opts: PW.UnlockGrantOptions): integer, string?
---Server. An empty item list with opts.grant records only the claim (XP-only or currency-only rewards): returns 0, nil
---the first time and 0, "claimed" afterwards.
---Server. Removes grants (never purchases; claims stay). Refusals: "bot", "badplayer", "badsource", "badkey", "notready".
---@field Revoke fun(ply: Player, items: (PW.UnlockItem|string)[], opts: PW.UnlockGrantOptions): integer, string?
---Shared, pure. The key of an item, nil when malformed.
---@field KeyOf fun(item: PW.UnlockItem|string): string?
---Shared, pure. kind, id (and weapon, option for options) of a key; nil when malformed.
---@field ParseKey fun(key: string): string?, string?, string?, string?
---Shared. Display data of an item for previews (name from the entity, the camo entry or the option id).
---@field Describe fun(item: PW.UnlockItem|string): PW.UnlockItemView
---Shared. Every enabled entity, curated attachment and camo whose Unlock spec has reward == source, sorted by key.
---@field ListRewards fun(source: string): PW.UnlockItem[]
---Constants (section 3.6)
---@field FilePath string
---@field FileVersion integer
---@field UploadMaxBytes integer
---@field MaxGrants integer
---@field MaxClaims integer
---@field MaxGrantPerCall integer

---@class PW.UnlockGrantOptions
---@field source string                -- pattern ^%l[%l_]*$, at most 16 bytes ("challenge", "event", "admin")
---@field grant? string                -- grant id; a claimed id makes Grant a no-op answering "claimed"

---@class PW.UnlockItemView
---@field key string
---@field kind string
---@field id string
---@field weapon? string
---@field name string
---@field valid boolean                -- resolves on this host
```

- [ ] Internal pure functions (underscore, tested): `_Spec`, `_Decide`, `_Requirement(view, kind, id)`,
  `_StaticRequirement`, `_CheckGrants`, `_CheckClaims`, `_FileFromJson`, `_FileToJson`, `_ApplyDelta`,
  `_EncodeUpload`, `_DecodeUpload`, `_EncodeDeltaPart`, `_DecodeDeltaPart`, server `_Grant(store, ply, items, opts)`,
  `_Revoke`, `_OnUpload(store, ply, raw)`.
- [ ] Hooks (`PW.Ask` for questions, `PW.Notify` for notifications; documented in `docs/api/progression.md`):

| Hook | Kind | Realm | Arguments | Return | When |
| --- | --- | --- | --- | --- | --- |
| `PW_UnlockOverride` | question | shared | `ply, kind, id` | `true` opens, `false` locks, `nil` continues | Every decision, after `Hidden`. Listeners must answer the same on both realms (the server is authoritative) |
| `PW_UnlockHint` | question | shared | `kind, id` | `string?` | When building a requirement of a locked item; the weekly challenges module answers for its rewards |
| `PW_UnlockGranted` | notification | server and client | `ply, keys, source, grant?` | none | Server: after `Grant` added at least one key. Client: after a delta added keys (one call per `source` and `grant` group), `ply` is the local player |
| `PW_UnlockRevoked` | notification | server and client | `ply, keys, source` | none | After `Revoke` removed at least one key; client after the delta applied |

- [ ] Admin console commands (server, privilege `pw_unlocks_admin`, default `superadmin`; pattern of
  `modules/bots_goal/sv_command.lua`): `pw_unlock_grant <player> <key>` (source `admin`), `pw_unlock_revoke <player>
  <key>`, `pw_unlock_list <player>`. Player by user id or exact name.
- [ ] Settings: none new (open questions 1 and 3).

## 5. Files to create or modify

All paths verified to exist except those marked new.

- [ ] New `modules/progression/sh_unlock_spec.lua`: `_Spec`, `_StaticRequirement`, `LockText`, `KeyOf`, `ParseKey`.
- [ ] Modify `modules/progression/sh_unlocks.lua`: `_Decide`, `_Requirement`; `_IsUnlocked` returns `(_Decide(...))`
  only; `_LockedOptions` per section 3.8; remove the local `required` (`:22-30`).
- [ ] New `modules/progression/sh_entitlements.lua`: file shape, checks, delta apply, upload and delta wire parts.
- [ ] New `modules/progression/sv_entitlements.lua`: session grants and claims, `_Grant`, `_Revoke`, upload receiver,
  pending and flush fields, notifications, admin commands (or `sv_unlock_command.lua` if over 500 lines).
- [ ] New `modules/progression/cl_entitlements.lua`: file read and write, upload, delta apply, client notifications.
- [ ] Modify `modules/progression/shared.lua`: create `PW.Unlocks`, `AddCSLuaFile` and `include` the new shared files,
  public functions, wrappers.
- [ ] Modify `modules/progression/init.lua` (`stateOf`, `_SetState`, `_ViewOf`), `sv_storage.lua` (`_PendingOf`,
  `_Flush`, `_OnUpload`), `sh_storage.lua` (`_EncodeDelta`, `_DecodeDelta`, `_ViewFromLevels`), `cl_init.lua`
  (`_LocalView`, delta receiver, upload), `sv_wallet.lua` (no logic change; `_GetOwned` stays purchases only).
- [ ] Modify `modules/economy/init.lua` (`_Context`, `_Buy` refresh), `modules/economy/shared.lua` (doc comment).
- [ ] Modify `modules/loadout/sv_classes.lua` (`contextFor`), `modules/loadout/sh_gunsmith.lua` (`counted`).
- [ ] Modify `modules/operators/shared.lua`, `sh_rules.lua`, `init.lua`, `cl_init.lua`.
- [ ] Modify `modules/loadout_ui/sh_editor.lua`, `sh_gunsmith.lua`, `cl_init.lua`.
- [ ] Modify `modules/ui_kit/sh_progress.lua`, `sh_store.lua`, `cl_store.lua`; `modules/hud/sh_popups.lua` and
  `hud/popups.lua` (unlock popup); `screens/loadout_editor.lua`, `screens/loadout_gunsmith.lua`,
  `screens/loadout_operator.lua`, `screens/store_bundle.lua` for the `NEW` badge.
- [ ] Modify `modules/autounlock/sh_rules.lua` only if the new regression case fails (expected: no change).
- [ ] Types (LuaLS, mandatory type check): new `types/unlocks.lua` (`PW.UnlocksLib`, `PW.UnlockSpec`,
  `PW.UnlockReason`, `PW.UnlockRequirement`, `PW.UnlockItem`, `PW.UnlockItemView`, `PW.UnlockGrantOptions`,
  `PW.UnlockGrantMeta`, `PW.UnlocksFile`, `PW.Unlocks` field on `PW`); modify `types/progression.lua`
  (`PW.ProgressionView` new fields, `PW.ProgressionState` `grants`, `claims`), `types/progression_storage.lua`
  (`PW.ProgressionDelta`, `PW.ProgressionPending` new lists, `PW.ProgressionLocal.unlocks`), `types/weapons.lua`
  (`Unlock` of `PW.Weapon`, `PW.AttachmentCuration`, `PW.CamoCuration` as `PW.UnlockField`), `types/economy.lua`
  (`PW.PlayerModel.Unlock`, `PW.CallingCard.Unlock`), `types/perks.lua` (`Unlock`), `types/loadout.lua`
  (`PW.LoadoutContext.entitledOption`, `requirement`), `types/loadout_ui.lua`, `types/operators.lua`
  (`PW.OperatorEconomyInput` requirement), `types/ui_store.lua`, `types/hud_popups.lua` (kind `"unlock"`).
- [ ] API docs (orchestrator, frozen contracts): `docs/api/progression.md` (new section "Unlock authority and
  entitlements", rewritten "Unlock checks", storage and net tables, wallet rule 5 wording, content rule for presets),
  `docs/api/economy.md` (unlock wording, `owned` covers grants, `Unlock` forms), `docs/api/loadout.md` (context fields,
  `lockedOptions` now enforces camos and entitlements), `docs/api/operators.md` (lock text from the requirement,
  `Unlock` forms), `docs/api/core.md` (`PW.Weapon.Unlock` type), `docs/api/ui.md` (store texts, `NextUnlocks` skips
  grant-only, unlock popup, `NEW` badge), `docs/api/perks.md` and `docs/api/streaks.md` (only if they state the
  `Unlock` type), `docs/api/README.md` (progression row).
- [ ] `TASKS.md` "Mandatory test cases": add the cases of section 8 (orchestrator). `docs/agent-test-map.md`: add the
  new test files. `changes/INDEX.md`: link this record (not edited by the planning agent).
- [ ] Tests: new `lua/tests/privatewar/unlocks.lua`, `unlocks_storage.lua`, `unlocks_ui.lua`; modify
  `autounlock.lua` (one case), `gunsmith.lua:127`, `bots_loadouts.lua:252`, `bots_arc9_generated_native.lua:110`
  (stub target, section 6 note).

## 6. Call-site migration

| Current site | After |
| --- | --- |
| `modules/progression/shared.lua:55-58` `_OwnedActive` | Unchanged; feeds `view.owned` (purchases) |
| `shared.lua:60-66` `viewOf` | Builds the view with `granted`, `override`, `hint` |
| `shared.lua:68-70` `PW.Progression.IsUnlocked` | Wrapper: first value of `PW.Unlocks.IsUnlocked` |
| `shared.lua:72-80` `LockedOptions`, `AttachmentLimit` | Unchanged signatures over the new `_LockedOptions` |
| `sh_unlocks.lua:22-30` `required` | `PW.Unlocks._Spec(unlock).level` |
| `sh_unlocks.lua:66-95` `optionUnlocked`, `_IsUnlocked` | `_Decide`; `_IsUnlocked` returns its first value |
| `sh_unlocks.lua:122-140` `_LockedOptions` | Per-option `_Decide` for curated, camo and entitled options; count the rest |
| `init.lua:79-89` `stateOf` | Adds `grants`, `claims` (empty sets for old sessions) |
| `init.lua:123-137` `_SetState` | Keeps session `grants` and `claims` (`SetState` does not replace them) |
| `init.lua:207-220` `_ViewOf` | Adds `granted`, `override` (`PW.Ask("PW_UnlockOverride", ply, ...)`), `hint` |
| `cl_init.lua:37-54` `_LocalView` | Adds `granted` from `unlocks.json`, `override`, `hint` |
| `cl_init.lua:76-82` delta receiver | Also `_ApplyDelta` of the unlocks part, write `unlocks.json`, client notifications |
| `cl_init.lua:103-105` upload | Also sends `pw_unlocks_upload` |
| `sh_storage.lua:130-136` `_ViewFromLevels` | Optional `granted` parameter |
| `sh_storage.lua:206-224` `_EncodeDelta`, `_DecodeDelta` | Append `_EncodeDeltaPart`, `_DecodeDeltaPart` |
| `sv_storage.lua:36-43` `_PendingOf` | Adds `granted`, `revoked`, `claims` |
| `sv_storage.lua:80-95` `_Flush` | Sends the new lists; "never empty" also counts them |
| `sv_wallet.lua:56-70` `_GrantOwned` | Unchanged (purchases) |
| `modules/economy/init.lua:125-139` `_Context` | `owned` = purchased or granted; `unlocked` = `_Decide` without entitlements |
| `economy/init.lua:141-156` `_Buy` | Also `store.refresh(ply)` after a purchase |
| `economy/shared.lua:112-114` `IsOwned` | Unchanged (purchases only); comment points to `PW.Unlocks.IsEntitled` |
| `economy/sh_purchase.lua:36-46` `ownedReason` | Unchanged code; `ctx.owned` now includes grants |
| `modules/loadout/sv_classes.lua:98-112` `contextFor` | `PW.Unlocks.IsUnlocked`; adds `entitledOption`, `requirement`; `attachmentLimit` unchanged |
| `loadout/sh_classes_repair.lua:40` | Unchanged (`ctx.isUnlocked`) |
| `loadout/sh_gunsmith.lua:61-73` `checkLocked` | Unchanged (now also catches camos and honours entitlements) |
| `loadout/sh_gunsmith.lua:94-105` `counted` | Also false when `ctx.entitledOption(weaponId, option)` |
| `modules/operators/init.lua:45-49` `engineUnlocked` | `PW.Unlocks.IsUnlocked(ply, "models", id)` |
| `operators/cl_init.lua:14-19` `localUnlocked` | Same, local player |
| `operators/shared.lua:25-32` `economyInput` | Drops `tonumber(entity.Unlock)`; adds `requirement` from `PW.Unlocks.Requirement` or `_StaticRequirement` |
| `operators/sh_rules.lua:42-50, 169-177` `economyEntry`, `lockOf` | `PW.Unlocks.LockText(requirement)`; existing `2000 CR` and `LV 12` texts kept |
| `modules/loadout_ui/sh_editor.lua:35-50` `required`, `LockText` | `ctx.requirement(kind, id)` when present, else `_StaticRequirement(entity, false)`, through `PW.Unlocks.LockText` |
| `loadout_ui/sh_editor.lua:120-131, 175-185` | Use the requirement text; adds `new` flag (section 9) |
| `loadout_ui/cl_init.lua:111-114` `LiveInput` | `ctx.isUnlocked`, `ctx.requirement` from `PW.Unlocks` |
| `loadout_ui/cl_init.lua:132-158` `weaponProgress`, `LiveGunsmith` | Adds `input.optionRequirement(optionId)` from `PW.Unlocks.Requirement(LocalPlayer(), "attachments"/"camos", ...)` |
| `loadout_ui/sh_gunsmith.lua:28-42, 86-102, 145-158, 200-205` | Curated, camo and entitled options use `input.optionRequirement` when present (else today's weapon-level rule); entitled options not level-counted |
| `modules/ui_kit/sh_progress.lua:39-75` `unlockLevel`, `NextUnlocks` | `PW.Unlocks._Spec`; `level == false` items left out |
| `ui_kit/cl_store.lua:46-60` `LiveFacts` | `owned = IsOwned or granted` (via `PW.Unlocks.IsEntitled` on the key) |
| `ui_kit/sh_store.lua:32, 203, 234` | "Unlocked by your level" → "Already unlocked" (level, grant or unlockall) |
| `modules/autounlock/sh_rules.lua:285-296` `_EntryFor` | Unchanged; covered by a new regression case |
| `screens/progress_home.lua:93` | Unchanged call |
| `modules/bots_loadouts/*`, `operators/sh_rules.lua` `BotPick`, `privatewar-arc9` bot loadouts | Unchanged: no unlock call |

- [ ] Test stub note: `gunsmith.lua:127` stubs `PW.Progression.IsUnlocked` to open everything, and the two bot tests stub
  it to count calls. When a caller moves to `PW.Unlocks`, stub `PW.Unlocks.IsUnlocked` as well (both names) so the
  assertions keep their strength. Never weaken or drop an assertion.

## 7. Implementation steps

Each step: tests first (RED for the right reason), code, `nix develop --command make check` clean, one commit
(`git commit --signoff`, semantic message, trailer `Assisted-by: LLM`). The game keeps working after every step.

- [ ] 0. Obtain approval of section 2, of the `docs/api/` changes, and implementation authorization. Create a feature
  branch from `main`. Read `AGENTS.md` "Coding skills", `docs/agent-workflow.md`, `docs/agent-test-map.md`.
- [ ] 1. Types: `types/unlocks.lua` and the type field changes of section 5 (no behaviour). Commit
  `feat(progression): add unlock authority types`.
- [ ] 2. `sh_unlock_spec.lua`: `_Spec`, `KeyOf`, `ParseKey`, `_StaticRequirement`, `LockText` with the
  `unlocks.lua` cases 1, 9 (static part), 13. Commit.
- [ ] 3. `_Decide` and `_Requirement` in `sh_unlocks.lua`; `_IsUnlocked` delegates. Cases 2 to 8, 9; all existing
  `progression.lua` and `economy.lua` unlock cases stay green unchanged. Add the `autounlock.lua` regression case.
  Commit.
- [ ] 4. `_LockedOptions` per section 3.8 and the loadout `entitledOption` context field; cases 10, 11; existing
  `gunsmith.lua` and `progression.lua` count cases green. Two commits: progression lane, then loadout lane
  (`sh_gunsmith.lua` `counted`, `sv_classes.lua` field only).
- [ ] 5. `sh_entitlements.lua` pure part: file, checks, claims pruning, delta apply, wire. `unlocks_storage.lua` cases
  8 to 12. Commit.
- [ ] 6. `sv_entitlements.lua`: state, `_Grant`, `_Revoke`, upload receiver, pending and flush, refresh,
  notifications; `sh_storage.lua` delta extension; `init.lua`, `sv_storage.lua` edits. Cases 1 to 7, 13, 19, 20 (server half). Commit.
- [ ] 7. `cl_entitlements.lua` and `cl_init.lua`: file IO, upload, delta apply (unlocks file before progression
  file), client notifications; `unlocks_storage.lua` case 20 (client half). Commit.
- [ ] 8. `PW.Unlocks` public façade in `shared.lua`, hooks `PW_UnlockOverride` and `PW_UnlockHint` wired into the
  views; wrappers; `ListRewards`; `unlocks.lua` cases 12, 14, 15, 16. Commit.
- [ ] 9. Economy: `_Context` and `_Buy` refresh; `unlocks_storage.lua` case 18; all `economy.lua` cases green. Commit.
- [ ] 10. Loadout `contextFor` to `PW.Unlocks` (+ `requirement`), with the stub-target updates; `unlocks_storage.lua` cases 14, 16. Commit
  (loadout lane).
- [ ] 11. Operators to `PW.Unlocks` and requirement texts; `unlocks_storage.lua` case 15; all `operators_names.lua` cases green. Commit.
- [ ] 12. UI: editor and gunsmith requirement texts, store texts, `NextUnlocks`; `unlocks_ui.lua` cases 1 to 5.
  Commit (ui lane).
- [ ] 13. UI: `NEW` badge and the unlock popup; `unlocks_ui.lua` cases 6, 7. Commit (ui lane).
- [ ] 14. Admin commands; `unlocks_storage.lua` case 17. Commit.
- [ ] 15. Docs (`docs/api/*`, `TASKS.md` mandatory cases, `docs/agent-test-map.md`) by or with the orchestrator.
  Commit `docs: document unlock authority and entitlements`.
- [ ] 16. Gates (section 12), then stop at the human checkpoint.

## 8. Mandatory test cases

GLuaTest, `addons/privatewar/lua/tests/privatewar/`. A step is not done without its cases; never drop or weaken one.

Existing cases that must stay green (and are not edited except the stub targets named in section 6):

- [ ] T-4.9 (`progression.lua`): "Unlock by curation: the player level for entities, the weapon level for options and
  camos"; "Unlock by count: the weapon level is the number of uncurated attachments, capped by the setting"; "Level from
  kills: weapon XP of kills raises the weapon level that the count rule reads"; "unlockall opens every level gate and
  the count limit; Hidden stays hidden"; "The public API exists and the classes repair uses the unlock context".
- [ ] T-4.10 (`progression_storage.lua`): "Delta apply: additive to player XP and per weapon, pure (the input file is not
  changed)"; "Join upload: validated and clamped, accepted once, then levels sent and classes refreshed"; "Levels for the
  client: player level, weapon levels above 1, unlockall and the attachment cap"; "Client IsUnlocked: the view built
  from the received levels answers like the server"; "Wire: upload, delta, levels and summary survive encode and
  decode"; "Wire: a forged count cannot make the decoder read past the size bound"; "File: JSON shape round trip; a
  malformed file gives an empty progression".
- [ ] T-4.12 (`economy.lua`): "Purchase: deducts the currency, marks the item owned, and the unlock check answers true";
  "Purchase: insufficient funds are rejected and nothing changes"; "Purchase: a bundle grants all its items and itself
  for one price"; "Purchase: bad keys, unknown offers, owned items and items the level already unlocks are refused";
  "Purchase: the client file applies the purchase through the delta path, once"; "Storage: a v1 file (no currency, no
  purchases) loads with zero currency; the file round trips"; "Unlock rules: a priced entity without Unlock is for sale
  only; no economy, no prices"; "Unlock rules: a purchased camo opens, a Hidden camo stays hidden even when owned";
  "Wire: state, delta, request and result survive encode and decode; a forged owned count is bounded".
- [ ] T-11.7 (`autounlock.lua`): "Run: soft registration, hand curation wins option by option"; "Merge: a weapon with a
  Price stays shop-only; curated fields are never overwritten"; "Setting off: no levels, the unlock by count stays";
  and every other case of the file.
- [ ] T-4.8 (`gunsmith.lua`): "Validate on save: a build of offered, unlocked, compatible options is accepted as it is";
  "Validate on save: unknown, locked, conflicting and over-the-limit options are rejected"; "The attachment limit
  includes wildcards (match cap) and progression (weapon level)".
- [ ] T-4.7 (`loadout_classes.lua`): "Repair: unavailable items are removed and the rest is kept".
- [ ] T-5.13 (`bots_loadouts.lua`): "Mandatory (T-5.13): a player's class used by a bot is checked against match
  settings, not progression" (stub both `PW.Progression.IsUnlocked` and `PW.Unlocks.IsUnlocked`, assert zero calls).
- [ ] UI and operators: `ui_classes_gunsmith.lua` "Allowed items: locked items are greyed with their unlock level,
  banned ones with the reason", "Gunsmith: slots with their options, a curated option locked by its weapon level, Hidden
  skipped", "Gunsmith: the weapon level limits uncurated attachments; a swap in the same slot stays allowed";
  `ui_store_progress.lua` "Store states: owned, unlocked by level, not enough currency, buyable, pending", "Next unlocks:
  only above the current level, the closest first, Hidden left out"; `operators_names.lua` "Picker cards: Auto first,
  locked cards show the price or level and cannot be selected", "Server: malformed, unknown and unowned requests
  preserve the previous choice and model", "Bots get a valid model from the list (locks ignored) and keep it".
- [ ] Core (`core_registry.lua`): "Soft registration fills only missing fields, per nested key, never overwrites".

New cases, `unlocks.lua` (pure, both realms' shared code):

- [ ] 1. "Spec: nil, integer, { level = N }, false, { level = false } and hint normalise; anything else is open"
- [ ] 2. "Decide: any source opens; the reason names the first source that did"
- [ ] 3. "Decide: Hidden beats every source, including unlockall, grants and the override hook"
- [ ] 4. "Decide: Unlock = false opens only through a grant or a purchase, never by level"
- [ ] 5. "Decide: unlockall opens grant-only items and every level gate"
- [ ] 6. "Decide: grants count with the economy module disabled; purchases do not"
- [ ] 7. "Decide: a priced entity without Unlock stays for sale only; a grant opens it"
- [ ] 8. "Hook: PW_UnlockOverride true opens and false locks after Hidden; nil keeps the rules"
- [ ] 9. "Requirement: level, weapon level, price, reward hint and the PW_UnlockHint answer, with their lock texts"
- [ ] 10. "LockedOptions: a curated camo above the weapon level is locked on the server; an entitled one is open"
- [ ] 11. "LockedOptions: an entitled uncurated attachment does not count toward the weapon level limit"
- [ ] 12. "Compatibility: PW.Progression.IsUnlocked, LockedOptions and AttachmentLimit answer like PW.Unlocks"
- [ ] 13. "Keys: KeyOf and ParseKey accept the bundle item shape, the camo alias and attachments; malformed items give nil"
- [ ] 14. "Describe: names of entities, camos and options; an unknown item is marked invalid"
- [ ] 15. "ListUnlocked: the enabled ids of a kind that are unlocked, sorted"
- [ ] 16. "ListRewards: entities, attachments and camos with a matching reward source, sorted by key; reward alone opens
  nothing"

New cases, `unlocks_storage.lua` (server glue with fake stores; one engine smoke reusing a shared bot):

- [ ] 1. "Grant: adds new keys once; a repeated grant id adds nothing and answers claimed"
- [ ] 2. "Grant: refuses bots, bad sources, bad grant ids, malformed and unknown items, too many items and a full set"
- [ ] 3. "Revoke: removes grants only, never purchases; revoking twice removes nothing more"
- [ ] 4. "Grant and revoke: the delta carries them and the client file applies them once per batch id"
- [ ] 5. "Grant: classes are refreshed at once and PW_UnlockGranted fires with the new keys, source and grant id"
- [ ] 6. "Upload: keys and claims are validated, bounded, accepted once and merged with grants made before it"
- [ ] 7. "Upload: keys of content not installed on this host are kept"
- [ ] 8. "Migration: a v2 progression.json with owned keys and no unlocks.json lists purchases as entitlements; nothing is
  lost and progression.json stays at version 2"
- [ ] 9. "Migration: a v1 progression.json still loads with no entitlements"
- [ ] 10. "Malformed: a missing, empty, non-JSON or wrong-shaped unlocks.json reads as empty; bad entries are dropped"
- [ ] 11. "Claims: past MaxClaims the oldest are pruned by time, ties by id"
- [ ] 12. "Wire: the unlocks upload and the delta extension survive encode and decode; forged counts are bounded"
- [ ] 13. "Net: pw_unlocks_upload is registered with an owner, a rate and the size bound; a second upload is ignored"
- [ ] 14. "Server rejects a locked loadout choice: a grant-only item in an uploaded class is repaired away until granted"
- [ ] 15. "Server rejects a locked operator: a grant-only model choice is refused until granted"
- [ ] 16. "Bots unaffected: bot pools and bot operators never call PW.Unlocks.IsUnlocked; Grant refuses bots"
- [ ] 17. "Admin commands: the privilege is checked; grant, revoke and list work on a shared player"
- [ ] 18. "Economy: a granted item counts as owned in a quote; a purchase refreshes the classes"
- [ ] 19. "Claim only: an empty grant with a grant id records the claim once; HasClaim answers on both realms"
- [ ] 20. "Batching: XP and currency queued before a Grant travel in its delta; the client writes unlocks.json before
  progression.json"

New cases, `unlocks_ui.lua` (pure UI models, server runner):

- [ ] 1. "Editor: a locked item shows the requirement lock text and reason (level, price, reward)"
- [ ] 2. "Gunsmith: a granted curated option above the weapon level is open; a locked camo shows its weapon level"
- [ ] 3. "Operator picker: a grant-only model shows its reward text; a granted model is selectable"
- [ ] 4. "Store: a granted item is OWNED and its texts no longer mention the level"
- [ ] 5. "Next unlocks: grant-only items are left out; table and integer levels both count"
- [ ] 6. "NEW badge: a granted, unseen key is new; marking it seen clears it; purchases are not new"
- [ ] 7. "Toast: a granted delta queues one unlock popup per grant group with the item name and source text"

New case, `autounlock.lua`:

- [ ] "Merge: Unlock = false and table forms are never overwritten by the stat-based levels"

## 9. UI part

Every feature ships its own UI part (`TASKS.md`, "UI grows together with features"). Pure models in `sh_` files,
drawing in screens; kit components only (`docs/api/ui.md`).

- [ ] Locked items say why and how, from `PW.Unlocks.Requirement` through `PW.Unlocks.LockText`: LOADOUT editor
  options and row problems, gunsmith options (curated, camo and entitled options; `FULL` for the count rule stays the
  gunsmith's own text), operator picker cards and details, store bundle item views. A reward hint appears in the
  details panel (`SetWarning` or the existing reason line).
- [ ] `NEW` badge: client seen-set keys `unlock:<key>` in `data/privatewar/ui_seen.json` (`PW.UI.Seen` in `modules/ui_kit/sh_models.lua`,
  `PW.UI.SeenSet` and `PW.UI.SaveSeen` in `modules/ui_kit/cl_root.lua`). An item is new when it is granted (in `unlocks.json`) and its key is not seen. The badge shows on the
  card (`badge = "NEW"`) in the editor options, gunsmith options, operator picker and store item views; the LOADOUT tab
  shows the existing tab `new` dot while any granted item is unseen. Focusing or selecting the card marks it seen
  (gamepad focus included). Purchases are not new (the player just bought them).
- [ ] Toast: on the client `PW_UnlockGranted`, queue one popup per grant group in the medal popup queue
  (`modules/hud/sh_popups.lua`, new entry kind `"unlock"` next to `"levelup"`): title `UNLOCKED`, the item name
  (`PW.Unlocks.Describe`) or `<n> items`, and the source text (`challenge` → "Challenge reward", `event` → "Event
  reward", `admin` → "Granted by the host", other → "Reward"). Shown in `PREMATCH`, `LIVE`, `POSTMATCH`; in the lobby
  the `NEW` badge is enough.
- [ ] Store copy: "Unlocked by your level" → "Already unlocked"; the `owned` state covers granted items ("You own
  this item").
- [ ] PROGRESS "Next unlocks": level-gated items only; grant-only items never appear there.
- [ ] Human checkpoint items are in section 12.

## 10. Interface for weekly challenges

The challenge system (server) calls only the public API; it never touches progression state or files directly.

- [ ] Reward items are `PW.UnlockItem` tables (the bundle item shape). A reward-only item is declared with
  `Unlock = false` (optionally `{ level = false, hint = "#pw.challenge.reward_hint" }`).
- [ ] Granting on completion (server):

```lua
-- schema of the calls, not an implementation
local added, refusal = PW.Unlocks.Grant(ply, {
    { kind = "camos", weapon = "arc9_eft_ak74", id = "gold" },
    { kind = "models", id = "reaper_operator" },
}, { source = "challenge", grant = "weekly:2026-W47:headshots_50" })
-- added: number of new keys; refusal: nil, or "claimed" when this grant id was already applied, "bot", "full", ...
```

- [ ] Idempotency: the grant id is the claim; a retried or duplicated completion is a no-op (`0, "claimed"`). The
  challenge module does not keep its own "claimed" flag for item rewards. `PW.Unlocks.HasClaim(ply, grantId)` answers
  "already claimed" on the server (upload plus session) and on the client (local file).
- [ ] Rewards without items (XP or currency only): `PW.Unlocks.Grant(ply, {}, { source = "challenge", grant = id })`
  records the claim alone. Order for one reward: `AddXP`, `AddCurrency`, then `Grant` (which flushes), so everything
  travels in one delta batch; the client persists the claim before the XP and currency (section 3.7).
- [ ] Bonus pool: items declared `Unlock = { level = false, reward = "challenge" }` are listed by
  `PW.Unlocks.ListRewards("challenge")` (sorted by key); the challenge module picks from that list.
- [ ] Reward preview (client UI of the challenges screen): `PW.Unlocks.Describe(item)` for the name and validity,
  `PW.Unlocks.IsUnlocked(LocalPlayer(), kind, id)` for an `OWNED` or `UNLOCKED` badge, `PW.UI.Store.KindLabel(kind)` and
  `PW.UI.Store.Preview(kind, entity)` (existing, `modules/ui_kit/sh_store.lua`) for the kind label and the model or material preview.
- [ ] Locked-item hints: the challenge module answers `PW_UnlockHint(kind, id)` for items that are rewards of active
  challenges (for example "Weekly challenge: 50 headshots"), so the loadout and operator screens say how to get them.
- [ ] Notification for its own UI: `PW_UnlockGranted(ply, keys, source, grant)` with `source == "challenge"`.
- [ ] Choosing a reward the player does not have yet: `PW.Unlocks.ListUnlocked(ply, kind)` and `IsEntitled`.

## 11. Open questions

Each has a recommended default; the user decides.

- [ ] 1. Trust: should a host be able to ignore grants on their server (setting `progression.grants`)? Recommended:
  no setting now; grants are forgeable like the rest (d.0), and `unlockall` already covers the opposite need.
- [ ] 2. Is `Revoke` needed? Recommended: yes, grants only, for admin correction and tests; purchases are never revoked;
  claims stay after a revoke.
- [ ] 3. Should a host be able to lock specific items (a deny list)? Recommended: no setting now; the
  `PW_UnlockOverride` hook covers addons; revisit with a concrete need.
- [ ] 4. Source registry: a file kind `unlock_sources/` or fixed order plus hook? Recommended: fixed order plus hook
  (section 3.4); every known producer is a grant.
- [ ] 5. Do grants count with the economy module disabled? Recommended: yes; only purchases depend on the economy module
  (d.6 unchanged for purchases).
- [ ] 6. `MaxGrants` 384 (one upload under 64 KB) with the refusal `full`: acceptable for now, with a chunked upload as a
  follow-up when needed? Recommended: yes.
- [ ] 7. Must a granted item resolve on the host? Recommended: `Grant` refuses unknown items (catches typos); uploaded
  keys of content not installed are kept.
- [ ] 8. `NEW` badge for items unlocked by a level-up too? Recommended: grants only in this change; level-up `NEW` as a
  follow-up.
- [ ] 9. Should the entitlement layer record claims (idempotency by grant id)? Recommended: yes (section 10).
- [ ] 10. Admin console commands in the gamemode (not only the dev addon)? Recommended: yes, `superadmin` privilege; they
  also make the checkpoint testable.
- [ ] 11. Accept the behaviour changes found in the research: camo levels enforced on the server, purchased options
  honoured by build validation, classes refreshed after a purchase? Recommended: yes.
- [ ] 12. Postmatch summary list of unlocks (d.5 mentions "unlocks")? Recommended: out of scope; a follow-up can add
  "UNLOCKED" rows from level-ups and grants.
- [ ] 13. Bots: keep `IsUnlocked` unspecialised for bots (it is never called on bot paths)? Recommended: keep; tests
  assert zero calls.

## 12. Gates

- [ ] Before every commit: `nix develop --command make check` clean (glualint, `lua-language-server --check`,
  markdownlint, rules: no `net.WriteTable`, files at most 500 lines, functions at most 60 lines). Never `--no-verify`.
- [ ] Before acceptance or merge, with pipefail:

```bash
set -o pipefail
nix develop --command make check
nix develop --command make test
```

- [ ] `make test` runs on the Steam Deck: obtain the user's explicit permission and confirmation that the Deck is free
  before running it (`docs/agent-workflow.md`). A timeout, a missing dependency or zero selected cases is not a pass.
- [ ] Human checkpoint (the user tests in GMod, listen server with a friend or a second client where noted):
  1. `pw_unlock_grant <me> camos:<weapon>:<camo>` during a match: the `UNLOCKED` toast appears; the camo is usable in
     the gunsmith and shows `NEW` until focused.
  2. A grant-only item (`Unlock = false`) shows `REWARD` and its hint in LOADOUT and cannot be equipped until granted;
     after the grant it is equipped and survives a respawn.
  3. Reconnect: the grant persists (`data/privatewar/unlocks.json` exists); on a second friend's server it is honoured.
  4. `pw_unlock_revoke`: the item is locked again and the class is repaired with the reason shown.
  5. A level-locked weapon and a priced operator still show `LV <n>` and `<n> CR`; a purchase still works and the
     class state updates at once.
  6. `progression.unlockall` on: everything, grant-only items included, is open; `Hidden` options stay hidden.
  7. Bots keep getting loadouts and operators as before.
  8. Controller: the `NEW` badge clears on gamepad focus; the toast does not steal focus.
  9. Optional (version skew): join a server running the previous build, play a match, return: grants are intact.
- [ ] Record the user's checkpoint result separately; automated results do not replace human acceptance.
