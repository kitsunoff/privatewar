# Progression API

Module `progression` (T-4.9, `design/06-progression.md` d.1, d.2, d.4, d.8). Player XP comes from score events;
weapon XP comes from the weapon of an event. `PW.Unlocks` decides unlocks by level and other sources. Persistence and the 10 s
deltas are T-4.10 (section "Storage and deltas (T-4.10)"), the wallet (currency, purchases) is T-4.12 (section "Wallet (T-4.12)", sold by `economy.md`). Files: `lua/privatewar/modules/progression/` (`shared.lua`, `sh_curves.lua`,
`sh_unlocks.lua`, `sh_wallet.lua`, `sv_wallet.lua`, `sh_storage.lua`, `sv_storage.lua`, `cl_init.lua`, `init.lua`), HUD `lua/privatewar/hud/progression.lua`, types `lua/privatewar/types/progression.lua`.

## State

| Function | Contract |
| --- | --- |
| `PW.Progression.GetState(ply) -> PW.ProgressionState` | Server. A copy of the session state `{ xp = <total player XP>, weapons = { [weaponClass] = <total XP> } }`. A player without a state gets an empty one |
| `PW.Progression.SetState(ply, state)` | Server. Replaces progression state while preserving session grants and claims. Bad values (non-numbers, negatives, NaN, infinity) become 0, XP is floored, weapons with 0 XP are dropped; republishes the NW2 values. Sends no notification |
| `PW.Progression.AddXP(ply, amount, weaponClass?)` | Server. Adds `floor(amount * progression.xpscale)` XP to the player and, with a class, the same amount to the weapon; a scaled amount of 0 or less does nothing. Sends the notifications below |
| `PW.Progression.GetLevel(ply) -> integer` | Shared. Server: computed from the XP. Client: the NW2 value `pw_level` (default 1) |
| `PW.Progression.GetProgress(ply) -> into, need` | Client reads the NW2 values: XP into the current level and XP for the next one (`need` is 0 at the cap; defaults 0 and 1000) |
| `PW.Progression.GetWeaponLevel(ply, weaponClass) -> integer` | Server, and the local player on a client (see "Storage and deltas"). Level of the weapon from its XP (1 without XP) |

The XP keeps counting past the level cap; the bar stays full. A reload of the module keeps the sessions.

Only humans earn: the listener of `PW_ScoreEvent` ignores bots. The weapon class comes from the `weapon` argument of the
event (an invalid entity gives no weapon XP).

## Unlock authority and entitlements

`PW.Unlocks` lives in the progression module, not in a separate module or registry kind. An unlock is a decision; an
entitlement is a stored grant or purchase. Level conditions are computed, never stored as ownership, so curve changes
apply retroactively. The server is authoritative; shared queries on a client are for the local player.

### References and curation

Items use `PW.UnlockItem` (`{ kind, id, weapon? }`, the bundle item shape) or, where noted below, a key string.
Entity kinds are registry kinds except `bundles` and `classes`; examples are `weapons`, `perks`, `equipment`,
`streaks`, `wildcards`, `models` and `cards`. For `attachments` and `camos`, the item table requires `weapon` and its
`id` is the option id. Queries taking `kind, id` use `<weapon>:<option>` as the option id argument.
Canonical keys are `<kind>:<id>`, `attachments:<weapon>:<option>` and `camos:<weapon>:<option>`.
Keys match `^%l[%l_]*:[%w_%-%.:]+$` and are at most `PW.Progression.MaxKeyLength` (96) bytes.
`KeyOf` and `ParseKey` accept `camo` as an alias; stored and transmitted grant keys are canonical.
For live `Grant` and `Describe` resolution, use `camos` for entries in the weapon's `Camos`, and `attachments`
for all other offered or curated options, even when the adapter marks them cosmetic. The wrong namespace
does not resolve. Upload validation still retains well-formed keys independently of installed content.

`PW.UnlockField` is an integer, `false`, or a table `{ level?, hint?, reward? }`, with an integer or `false` for
`level`. Weapon options use the same forms in `Attachments[option].Unlock` and `Camos[id].Unlock`, with weapon levels.
Omitted `Unlock` is open unless the price-only rule applies. Numeric levels are floored; nonpositive levels,
a table with no level and unsupported types normalize to 0 (open). An invalid level on a registry definition logs
once per entity with `pw_debug` enabled. `false` and `{ level = false }` give no level
path; higher-priority sources still apply. `hint` is nonempty text or `#phrase` (at most 128 bytes), only used
while locked. `reward` is a valid source id for `ListRewards`, not an unlock condition. Soft registration
fills only `nil`, preserves explicit `false` and merges nested tables per key. Preset classes must not reference
`Unlock = false` items: players without the entitlement can lose access to the preset.

### Decision order

The first applicable rule wins:

| Order | Condition | Result | `PW.UnlockReason` |
| --- | --- | --- | --- |
| 1 | Malformed id, unknown kind or entity (or unknown weapon for an option) | Locked | `unknown` |
| 2 | Option has `Hidden = true` | Locked, never offered | `hidden` |
| 3 | `PW_UnlockOverride` answers a boolean | The returned boolean | `override` |
| 4 | `progression.unlockall` | Open | `unlockall` |
| 5 | Granted key | Open | `grant` |
| 6 | Purchased key, only while economy is active | Open | `purchase` |
| 7 | `Unlock = false` or `{ level = false }` | Locked | `grant_only` |
| 8 | Entity has `Price >= 1`, no declared `Unlock`, economy active | Locked | `price` |
| 9 | Compare the required level against the player level (entities) or weapon level (options) | Open if met, locked otherwise; level 0 is open | `level` / `weapon_level`, or `default` at 0 |

An uncurated attachment queried on its own is open by default. The level-based count is a property of a build.
Bot loadouts and operator choices do not call the authority, and bots cannot receive grants.

### Public API

All functions below are on `PW.Unlocks`. Shared queries use the human player's view; non-human or invalid players
retain the progression view's fallback. Only the server mutates grants and claims.

| Function | Contract |
| --- | --- |
| `IsUnlocked(ply, kind, id) -> boolean, PW.UnlockReason` | Shared. Decision and first applicable reason |
| `Requirement(ply, kind, id) -> PW.UnlockRequirement` | Shared. Decision and lock presentation |
| `LockText(req) -> string?, string?` | Shared, pure. Short badge and sentence, or `nil, nil` when unlocked or hidden |
| `IsEntitled(ply, kind, id) -> boolean` | Shared. Granted, or purchased while economy is active, independent of the decision |
| `ListEntitled(ply) -> table<string, PW.UnlockGrantMeta>` | Shared. Stored entitlements by key. Purchases have `source = "purchase"`, `at = 0`. Uploaded grants on the server have `source = "grant"`, `at = 0`; grants made in the current session retain their metadata |
| `ListUnlocked(ply, kind) -> string[]` | Shared. Sorted unlocked ids of enabled definitions; options use `<weapon>:<option>` and are enumerated from curation |
| `HasClaim(ply, grant) -> boolean` | Shared. Whether the grant id has been claimed (uploaded or recorded in the session on the server; local file on the client). On the server, wait for `IsReady` before checking |
| `IsReady(ply) -> boolean` | Server. True only for a human whose unlock upload was accepted |
| `Grant(ply, items, opts) -> integer, string?` | Server. Takes an array of `PW.UnlockItem` or key strings and `PW.UnlockGrantOptions`; returns newly added key count and refusal, if any |
| `Revoke(ply, items, opts) -> integer, string?` | Server. Same inputs; returns removed grant count and refusal, if any. Never removes purchases or claims |
| `KeyOf(item) -> string?` | Shared, pure. Normalizes a `PW.UnlockItem` or key string; `nil` when malformed |
| `ParseKey(key) -> string?, string?, string?, string?` | Shared, pure. `kind, id` and, for options, `weapon, option`; `nil` when malformed |
| `Describe(item) -> PW.UnlockItemView` | Shared. `{ key, kind, id, weapon?, name, valid }` for a `PW.UnlockItem` or key string; `valid` means it resolves on this host. Name comes from the definition, camo entry or option id |
| `ListRewards(source) -> PW.UnlockItem[]` | Shared. Enabled entities, curated attachments and camos with matching `Unlock.reward`, sorted by key; excludes hidden options |

`PW.UnlockGrantOptions` requires a `source` matching `^%l[%l_]*$` (at most 16 bytes; for example `challenge`,
`event` or `admin`). Its optional `grant` id must match `^[%w_%-%.:]+$` (at most 64 bytes); `Grant` uses it
for idempotency; `Revoke` uses only `source`. An empty array with a grant id records a claim without adding items
(`0, nil` on first claim; `0, "claimed"` on repeat). Existing keys keep their metadata. A new grant must resolve on
the host; upload and revocation can retain or remove well-formed keys for absent content.

`Grant` refusals: `bot`, `badplayer`, `notready`, `badsource`, `badgrant`, `badkey`, `unknown`, `toomany`,
`full`, `claimed`. `Revoke` refusals: `bot`, `badplayer`, `notready`, `badsource`, `badkey`.
Before the accepted upload, both return `0, "notready"` for a valid human without mutating, flushing,
refreshing or notifying. A successful grant flushes the pending delta at once. A grant or revoke that changes
keys refreshes classes and notifies; a claim-only grant does not send an item notification.

To award items, XP or currency together, defer the **entire** reward until `IsReady`. Then check the claim,
queue XP with `PW.Progression.AddXP` and currency with `PW.Progression.AddCurrency`, and call `Grant` last.
With a successful grant the items, claim and balances travel in one delta; the client persists the claim first.
For a balance-only reward use an empty item array and a grant id. Grants and claims are forgeable by design, like
progression; there is no new host setting.

```lua
-- Server: after PW.Unlocks.IsReady(ply) and the claim check.
local added, refusal = PW.Unlocks.Grant(ply, {
    { kind = "camos", weapon = "arc9_eft_ak74", id = "gold" },
    { kind = "models", id = "reaper_operator" }
}, { source = "challenge", grant = "weekly:2026-W47:headshots_50" })
```

### Requirements and hooks

`PW.UnlockRequirement` has `unlocked`, `reason`, optional `level` or `weaponLevel` for the corresponding level reason,
`price` when the item can be bought now, `hint` (question answer, otherwise the spec hint), and `lockText` and `text`.
The view-free static fallback uses the definition for pure UI inputs without a live requirement function.

| Locked reason | `lockText` | `text` |
| --- | --- | --- |
| `level` | `LV <n>` | `Unlocks at level <n>` |
| `weapon_level` | `LV <n>` | `Unlocks at weapon level <n>` |
| `price`, or `grant_only` with `price` | `<n> CR` | `Buy it in the STORE for <n> CR` |
| `grant_only` without `price` | `REWARD` | The hint (a `#phrase` resolved by the UI), or `Earned as a reward` |
| `override` | `LOCKED` | `Locked on this server` |
| `unknown` | `LOCKED` | `Not available` |
| `hidden`, or any unlocked result | `nil` | `nil` |

| Hook | Dispatch | Arguments | Contract |
| --- | --- | --- | --- |
| `PW_UnlockOverride` | Shared question (`PW.Ask`) | `ply, kind, id` | `true` opens, `false` locks, `nil` continues. Called after the unknown and Hidden checks. Providers must agree across realms |
| `PW_UnlockHint` | Shared question (`PW.Ask`) | `kind, id` | Optional hint for locked requirements; nonempty text or `#phrase`, at most 128 bytes |
| `PW_UnlockGranted` | Server and client notification (`PW.Notify`) | `ply, keys, source, grant?` | Newly added keys only. Client groups by source and grant id |
| `PW_UnlockRevoked` | Server and client notification (`PW.Notify`) | `ply, keys, source` | Removed keys only. Both realms report the revoking operation's source, not the original grant's. Client groups by revoking source |

Client notifications run after applying the delta for the local player. Server commands `pw_unlock_grant <player> <key>`,
`pw_unlock_revoke <player> <key>` and `pw_unlock_list <player>` use `pw_unlocks_admin` (default `superadmin`).
The target is a user id or exact name; command grants and revocations use source `admin`.

## Unlock checks

| Function | Contract |
| --- | --- |
| `PW.Progression.IsUnlocked(ply, kind, id) -> boolean` | Shared compatibility wrapper. Returns only the first result of `PW.Unlocks.IsUnlocked` |
| `PW.Progression.LockedOptions(ply, weaponId, build) -> table<string, boolean>` | Shared wrapper for `PW.Unlocks.LockedOptions`. Set of locked option ids in `build` (`slot -> option\|false`) |
| `PW.Progression.AttachmentLimit(ply, weaponId) -> integer` | Shared wrapper for `PW.Unlocks.AttachmentLimit`. Weapon level capped by `loadout.maxattachments` (the cap itself with `unlockall`) |

Rules (`sh_unlocks.lua`):

1. Evaluate hidden options, attachments with explicit `Unlock`, listed camos and entitled options through the
   authority. The server enforces camo levels and honours grants and active purchases on options. Hidden never opens.
2. Otherwise uncurated attachments unlock by count. The weapon level is the number allowed (level 1 allows 1), capped
   by `loadout.maxattachments`; count in slot-name order. Entitled and cosmetic options are not counted.
3. With `unlockall`, the count limit becomes the cap. The server applies build legality, progression and the separate
   match cap through `PW.LoadoutContext` ([loadout API](loadout.md)).

Wrappers look up `PW.Unlocks` at call time. Consumers keep their no-progression fallback: no progression lock.

## Automatic unlock levels (T-11.7)

Source: `design/06-progression.md` d.2 revision 2026-11-07 (the weights are pending confirmation, the local manual checklist (not published)
section 7). Module `autounlock` (`lua/privatewar/modules/autounlock/`: `shared.lua` glue, `sh_rules.lua` pure rules),
namespace `PW.AutoUnlock`, types `lua/privatewar/types/autounlock.lua`. Generic: it works on any weapon adapter that
gives stats; the adapter methods it uses are `GetBaseStats`, `GetSlots`, `GetOptions` and the optional
`GetOptionStats`, `GetOptionSetKey` (`adapter.md`, "Option stats").

It fills the unlock fields the rules above read, with a `soft` registration, so hand curation always wins, field by
field and option by option:

- `Unlock` of a weapon: a player level in `1..progression.maxlevel`;
- `Attachments[option].Unlock`: a weapon level in `1..progression.maxweaponlevel` (the authority then applies instead
  of the count rule). Only `nil` is filled; explicit `false` and table forms are preserved.

### When and what

1. On `PW_WeaponsLoaded` of each realm (both realms compute, because the checks answer on the client too). Not in
   `PW_RegisterWeapons`: the order of its listeners is undefined, and only after the phase are the catalogue fills and
   every hand curation in the registry.
2. Candidates: the entries of the weapons registry with a `Category` and a `Kind` other than `melee`, `throwable` and
   `other`. A weapon with a `Price` gets nothing (an undeclared `Unlock` keeps the price-only rule). Cosmetic slots and options get nothing
   (unchanged rule). Only the slots of `GetSlots(class, nil)` are covered; options of nested slots opened by a build
   stay under the count rule.
3. Setting `progression.autounlock` (server, bool, default on). Off: nothing is registered, attachments unlock by count
   as before. It is read once per run: a change takes effect at the next map or `pw_reload`.

### Formula (`sh_rules.lua`)

1. Weapon features, higher is better: minus the time to kill near and at the mid range, rate of fire, minus recoil,
   minus spread, minus ADS time, minus sprint-to-fire time, move speed. Time to kill is
   `(max(1, health / damage) - 1) * 60 / rpm` with continuous shots to kill, so more damage always helps; the mid-range
   damage is interpolated between `damageNear` at `rangeNear` and `damageFar` at `rangeFar`.
2. Each feature is normalised within the category to `0..1` (min-max); a missing value, or a category where all values
   are equal, counts as `0.5`. The power score is the weighted sum (`PW.AutoUnlock.Weights.weapon`).
3. Weapons are ranked weakest first, ties by class. The first 1 (fewer than `openTwoFrom` = 4 weapons in the category)
   or 2 open at level 1; the other `r` get `1 + round((cap - 1) * i / (r + 1))`, `i = 1..r`.
4. Option stat gain: `sum(weight * sign * ln(multiplier))` (`Weights.option`; sign +1 for damage, range, rate of fire,
   move speed, -1 for recoil, spread, ADS, sprint-to-fire and reload time) plus `weight * ln((mag + add) / mag)` for
   `magazineAdd`. Options are ranked within each slot and spread the same way with none open at level 1. An option
   without numeric stats gets the middle of the levels of its slot (the middle of `1..cap` when no option of the slot
   has stats) and is counted in the report. An option in several slots of a weapon takes its lowest level.

Default weights (recommendation, pending confirmation):

| Group | Weights |
| --- | --- |
| `weapon` | `ttkNear` 0.30, `ttkMid` 0.25, `rpm` 0.05, `recoil` 0.15, `spread` 0.05, `adsTime` 0.10, `sprintToFire` 0.05, `moveSpeed` 0.05 |
| `option` | `damage` 1.0, `range` 0.4, `rpm` 0.6, `recoil` 0.8, `spread` 0.5, `adsTime` 0.6, `sprintToFire` 0.4, `moveSpeed` 0.5, `reloadTime` 0.3, `magazine` 0.3 |
| other | `health` 100, `midRange` 20 m, `defaultRpm` 600, `defaultMagazine` 30, `openTwoFrom` 4 |

### Cache

`data/privatewar/unlocks_cache.json` (`PW.AutoUnlock.CachePath`): `{ key, version, result }`, `result` being
`{ weapons = { [class] = level }, attachments = { [class] = { [option] = level } }, report }`. The key is a SHA-256 of
a canonical text of: `PW.AutoUnlock.Version`, the weights, the two caps, the sorted `class|category` list and
`<adapter id>:<GetOptionSetKey()>` of every adapter of those weapons. A matching key skips the computation (no stat,
slot or option is read); a mismatch recomputes and overwrites the file. Each run logs one line:
`[PW] autounlock: <n> weapons in <k> categories, <m> options (<x> without numeric stats: middle level of their slot),
<r> entries registered softly; cache hit|miss, <t> ms`.

| Function | Contract |
| --- | --- |
| `PW.AutoUnlock.Run(reg, env?) -> PW.AutoUnlockRun` | Computes or loads the levels and registers them softly in `reg`; `env` (settings, adapter lookup and call, file read and write, hash, clock, log) defaults to the engine. Returns `{ enabled, cacheHit, registered, ms, result? }`; the last run is `PW._AutoUnlock.last` |
| `PW.AutoUnlock.Weights` | The weights table above (one table, clear names) |

## Networking

NW2 Ints on the player, written by the server for the owner's HUD (the storage messages are listed in the next section):

| Key | Value |
| --- | --- |
| `pw_level` | Player level |
| `pw_xpin` | XP into the current level |
| `pw_xpneed` | XP for the next level, 0 at the cap |

They are published on every XP change, on `SetState` and on the player's first spawn.

## Notifications

No return value (`PW.Notify`).

| Hook | Arguments | When |
| --- | --- | --- |
| `PW_ProgressionXP` | `ply, xp, weaponClass?` | After every gain; `xp` is the scaled amount |
| `PW_ProgressionLevelUp` | `ply, level, oldLevel` | The player level grew (a gain can skip levels) |
| `PW_ProgressionWeaponLevelUp` | `ply, weaponClass, level, oldLevel` | The weapon level grew |

## Storage and deltas (T-4.10)

Source: `design/06-progression.md` d.5. The player's progression lives on the client; the server stores nothing between
sessions. Code: `sh_storage.lua` (pure: checks, delta apply, file shape, wire encoding), `sv_storage.lua`, `cl_init.lua`.

### Files

`data/privatewar/progression.json` on the client (`PW.Progression.FilePath = "privatewar/progression.json"`):

```json
{ "v": 2, "xp": 12345, "weapons": { "weapon_smg1": 4000 }, "currency": 250, "owned": ["models:swat"],
  "batch": { "session": 123, "seq": 7 } }
```

- `xp` is the total player XP, `weapons` the total XP per weapon class, `currency` the meta currency and `owned` the
  sorted list of purchased keys (T-4.12, "Wallet (T-4.12)"). The file version is `PW.Progression.FileVersion` (2); a v1
  file has neither field and loads with 0 currency and nothing owned.
- `batch` is the id of the last delta applied: a delta with the same `session` and a `seq` not above it is a duplicate
  and is ignored. A missing or bad file reads as an empty one; bad values (negative, NaN, too large, non-numbers) become
  0 or are dropped, so a hand-edited file never causes an error.
- The file is written after every applied delta.

Grants and claims are kept separately in `data/privatewar/unlocks.json`
(`PW.Unlocks.FilePath = "privatewar/unlocks.json"`, `PW.Unlocks.FileVersion = 1`):

```json
{ "v": 1,
  "grants": { "camos:arc9_eft_ak74:gold": { "source": "challenge", "at": 1763700000, "grant": "weekly:2026-W47:3" } },
  "claims": { "weekly:2026-W47:3": 1763700000 },
  "batch": { "session": 123, "seq": 7 } }
```

- `grants` maps keys to `PW.UnlockGrantMeta` (`source`, Unix time `at` with 0 for unknown, optional `grant` id).
  `claims` maps grant ids to Unix claim times. Times are unsigned 32-bit integers. Source, grant id and key
  validation use the patterns and byte limits in [Unlock authority and entitlements](#unlock-authority-and-entitlements).
- Missing, empty, non-JSON or wrong-shaped files read as empty. Bad entries are dropped. Over `MaxGrants` (384), keep
  the first valid keys in key order. Over `MaxClaims` (256), keep the newest claims, ties by ascending id.
  `PW.Unlocks.MaxSourceLength` is 16, `MaxGrantIdLength` 64, `MaxHintLength` 128 and `MaxGrantPerCall` 32.
- `unlocks.json` has its own batch check. An applied unlock delta keeps existing grant metadata, removes revoked
  keys, adds and prunes claims, and writes once before the progression file is written. If a crash occurs
  between writes, the claim is already persisted: the reward's XP or currency can be lost, not paid twice.
- No `progression.json` migration or version bump: v1 starts without purchases; v2 retains its purchases. A player
  without `unlocks.json` starts with no grants or claims. The first applied unlock delta creates the file.
  Older servers neither use nor discard the separate file.

### Net messages

The wallet fields (currency, owned keys, the delta's `earned` and `spent`) are added to the upload and the delta by T-4.12, see
"Wallet (T-4.12)"; the existing progression rows below show the T-4.10 fields. All use explicit `net.Write*`
(no `net.WriteTable`).

| Message | Direction | When | Fields |
| --- | --- | --- | --- |
| `pw_progression_upload` | client to server | `InitPostEntity`, once | `xp` UInt(32), `count` UInt(16), `count` x (`class` string, `xp` UInt(32)); the top 256 weapons by XP |
| `pw_unlocks_upload` | client to server | `InitPostEntity`, after `pw_progression_upload`; accepted once per connection | `version` UInt(8) (1), grant count UInt(16) then key strings, claim count UInt(16) then grant id strings. No grant metadata |
| `pw_progression_delta` | server to the owner | every 10 s, on every phase change (never empty) | `session` UInt(32), `seq` UInt(32), `xp` UInt(32), `count` UInt(16), `count` x (`class` string, `xp` UInt(32)) |
| `pw_progression_levels` | server to the owner | after the upload, on every level change (player or weapon), on entering `PREMATCH` (one frame after, when the settings snapshot is taken) | `level` UInt(16), `unlockAll` bool, `maxAttachments` UInt(8), `count` UInt(16), `count` x (`class` string, `level` UInt(16)); only weapons above level 1 |
| `pw_progression_summary` | server to the owner | at `POSTMATCH`, after the last flush | `xp` UInt(32), `levelBefore` UInt(16), `levelAfter` UInt(16), `count` UInt(16), `count` x (`class` string, `before` UInt(16), `after` UInt(16)), `medals` UInt(8), `medals` x (`id` string, `count` UInt(16)) |

`pw_progression_delta` appends the following fields after the wallet's `owned` list, in order. They count toward
the nonempty check (a claim alone can flush); counts are capped on both sides and the full delta stays below 64 KB.

| List | Count | Entry |
| --- | --- | --- |
| `granted` | UInt(8), `MaxDeltaGrants` (32) | `key` string, `source` string, `grant` string (empty when absent), `at` UInt(32) |
| `revoked` | UInt(8), `MaxDeltaRevokes` (32) | `key` string, revoking `source` string |
| `claims` | UInt(8), `MaxDeltaClaims` (8) | grant id string, `at` UInt(32) |

The unlock upload uses `PW.Net.Receive`, `who = "any"`, `rate = 0.5`, owner the progression module,
`maxLen = PW.Unlocks.UploadMaxBytes` (`1 + 2 + 384 * (96 + 1) + 2 + 256 * (64 + 1)` = 53,893 bytes).
The receiver rejects invalid versions and out-of-bounds counts without reading past the bound, validates each key
and id, collapses duplicates and retains valid keys for content not installed on this host. An accepted upload
installs the validated sets as the initial state, marks `IsReady` true and refreshes classes. There is no union
with early grants or claims: operations before readiness are refused. New keys at capacity return `full`, without
evicting uploaded keys.

### Server rules

1. The upload is accepted once per connection (a second one is ignored). The receiver is rate limited (0.5 s) and bounded
   by `PW.Progression.UploadMaxBytes`.
2. Clamping (`sh_storage.lua`): total XP at most `MaxXP` = 1e9 (and 0 or more, not NaN); an XP in a delta at most
   `MaxDeltaXP` = 1e7; at most `MaxWeapons` = 256 weapons (the highest XP are kept); a class name of 1 to
   `MaxClassLength` = 64 bytes; at most `MaxMedals` = 64 medal kinds in a summary. A value out of range counts as 0. A
   forged upload is accepted (the design accepts forgery); only the sizes are bounded.
3. Every XP gain joins the player's pending delta; `FlushInterval` = 10 s and each phase change send it with a batch id
   (a random `session` per connection, `seq` + 1 each time). Nothing is sent when nothing is pending.
4. The match record starts at `PW_MatchStart`: XP gained, the player level at the first XP of the match and each weapon
   level at its first XP.
5. A level change (player or weapon) calls `PW.Loadout.RefreshClasses(ply)`, so a class that became available is
   marked at once (it no longer waits for the next refresh).

### Client view

On a client the checks answer for the local player from the last `pw_progression_levels` (before the first message: the
NW2 level, no weapon levels, `progression.unlockall` from the setting, 5 attachments):

- `PW.Progression.IsUnlocked(ply, kind, id)`, `LockedOptions(ply, weaponId, build)`, `AttachmentLimit(ply, weaponId)` and
  `GetWeaponLevel(ply, weaponClass)` have the same contracts as on the server. `PW.Unlocks` also reads local grants
  and active purchases and asks the shared policy hooks locally.
- `PW.Progression.GetLocalFile() -> PW.ProgressionFile?` is the loaded file (nil before the first load).

### Match summary

`PW.Progression.MatchSummary(ply) -> PW.ProgressionSummary?`: on the server computed for any player; on a client the
last one received (`nil` before the first `POSTMATCH`).

```lua
{
    xp = 1250,                -- XP gained this match
    levelBefore = 3, levelAfter = 4,
    weapons = { { class = "weapon_smg1", before = 2, after = 3 } },   -- only weapons that levelled up, by class
    medals = { { id = "first_blood", count = 1 } }                    -- by id; from PW.Medals.Get(ply)
}
```

A player without a match record gets `xp = 0`, both levels equal and no weapons. On receiving the message the client
prints `[PW] match summary: +<xp> XP, level <a> -> <b>, <n> weapon level up(s), <m> medal kind(s)` and fires the
notification `PW_ProgressionSummary(summary)` (no return value). The postmatch screen is T-7.7.

## Settings

Server scope, ids `progression.<name>`:

| Name | Type | Default | Range | Meaning |
| --- | --- | --- | --- | --- |
| `unlockall` | bool | false | | Opens every recognized, non-hidden item unless overridden; XP still counts |
| `maxlevel` | int | 55 | 1 to 1000 | Player level cap |
| `xpbase` | float | 1000 | 1 to 1000000 | Player curve base |
| `xpexp` | float | 1.2 | 0 to 4 | Player curve exponent |
| `maxweaponlevel` | int | 30 | 1 to 1000 | Weapon level cap |
| `weaponxpbase` | float | 500 | 1 to 1000000 | Weapon curve base |
| `weaponxpexp` | float | 1.1 | 0 to 4 | Weapon curve exponent |
| `xpscale` | float | 1 | 0 to 100 | Multiplier of every XP gain |
| `autounlock` | bool | true | | Automatic unlock levels from weapon stats (T-11.7); read at the next map or reload |

## Curves

XP to the next level `L` is `floor(base * L ^ exponent)`; both layers start at level 1 with 0 XP, and level `N` is
reached after the sum over levels `1..N-1`.

- Player: `1000 * L ^ 1.2`, maximum level 55.
- Weapon: `500 * L ^ 1.1`, maximum level 30.

Note: `design/06-progression.md` d.4 states "about 12 000" XP to the next level at level 55, but the formula gives about
122 584. The implementation follows the formula; the contradiction is open and listed in the local manual checklist (not published), section 7.

## HUD

`hud/progression.lua` (order 15, phases `PREMATCH`, `LIVE`, `POSTMATCH`): a thin full-width XP bar along the bottom edge
of the screen, the shown level at its left end and the next level at its right end (`MAX` at the cap), from the local
player's NW2 values. The fill eases toward the new value and wraps through full on a level-up. A higher player level in
a `pw_progression_levels` message than in the previous one queues a LEVEL UP popup; the first message after joining is
only the baseline. Details: `ui.md`, "Bottom XP bar and LEVEL UP (element `progression`)".

The server sends no message of its own for `PW_ProgressionLevelUp` (it is a server notification only); the HUD uses
`pw_progression_levels`, which the server sends to the owner on every level change and after the join upload. The
client reads the last decoded message from `PW.Progression._Local.levels` (a new table per message).

## Wallet (T-4.12)

Source: `design/06-progression.md` d.6. The meta currency and the purchased items are part of the state, the client file
and the deltas (code: `sh_wallet.lua` pure, `sv_wallet.lua` server). The economy module (`economy.md`) earns, sells and
rotates; progression only keeps the numbers safe.

- State and file: `currency` (a whole number) and `owned` (a set of keys `"<kind>:<id>"`; a camo is
  `"camos:<weapon>:<option>"`; in the file a sorted list). The file version is 2; a v1 file (no fields) loads with 0
  currency and nothing owned.
- Clamping: a currency outside 0 to `MaxCurrency` (1e9), NaN or not a number is 0, fractions are floored (also in
  `SetState` and the upload); an owned key must match `^%l[%l_]*:[%w_%-%.:]+$`, at most `MaxKeyLength` (96) bytes, at
  most `MaxOwned` (256) keys (the first ones in key order). A delta bounds `earned` and `spent` by `MaxDeltaCurrency` (1e7).
- Delta: `earned`, `spent` and `owned` join the pending delta; the client applies
  `currency = clamp(currency + earned - spent, 0, MaxCurrency)` and the union of `owned`, idempotent per batch id.
- Wire: the upload gains `currency` UInt(32) and `owned` (`count` UInt(16), `count` x key string); the delta gains
  `earned` UInt(32), `spent` UInt(32) and `owned`. `UploadMaxBytes` includes them (below 65536).

| Function | Contract |
| --- | --- |
| `PW.Progression.GetCurrency(ply) -> number` | Server: the session currency. Client: the local file (0 before it loads) |
| `PW.Progression.AddCurrency(ply, amount)` | Server. Adds a whole amount of 1 or more (capped at `MaxCurrency`); joins the next delta |
| `PW.Progression.SpendCurrency(ply, amount) -> boolean` | Server. False and nothing taken for a non-whole, non-positive or too large amount |
| `PW.Progression.GrantOwned(ply, keys) -> integer` | Server. Marks keys owned; returns how many were new; joins the next delta |
| `PW.Progression.IsOwned(ply, key) -> boolean` | Shared (a client answers for the local player) |
| `PW.Progression.Flush(ply)` | Server. Sends the pending delta now |

Wallet ownership is purchases only. While economy is active, purchases and the price-only rule participate in the
[unlock decision](#decision-order); disabling economy ignores both, but grants and the remaining sources still apply.
Higher-priority rules, including Hidden and overrides, still apply to purchased items.
