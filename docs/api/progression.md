# Progression API

Module `progression` (T-4.9, `design/06-progression.md` d.1, d.2, d.4). Two layers for the MVP: the player level (XP from
score events) and the weapon level (XP of the weapon of an event), plus `progression.unlockall`. Persistence and the 10 s
deltas are T-4.10 (section "Storage and deltas (T-4.10)"), the wallet (currency, purchases) is T-4.12 (section "Wallet (T-4.12)", sold by `economy.md`). Files: `lua/privatewar/modules/progression/` (`shared.lua`, `sh_curves.lua`,
`sh_unlocks.lua`, `sh_wallet.lua`, `sv_wallet.lua`, `sh_storage.lua`, `sv_storage.lua`, `cl_init.lua`, `init.lua`), HUD `lua/privatewar/hud/progression.lua`, types `lua/privatewar/types/progression.lua`.

## State

| Function | Contract |
| --- | --- |
| `PW.Progression.GetState(ply) -> PW.ProgressionState` | Server. A copy of the session state `{ xp = <total player XP>, weapons = { [weaponClass] = <total XP> } }`. A player without a state gets an empty one |
| `PW.Progression.SetState(ply, state)` | Server. Replaces the state (the shape T-4.10 stores). Bad values (non-numbers, negatives, NaN, infinity) become 0, XP is floored, weapons with 0 XP are dropped; republishes the NW2 values. Sends no notification |
| `PW.Progression.AddXP(ply, amount, weaponClass?)` | Server. Adds `floor(amount * progression.xpscale)` XP to the player and, with a class, the same amount to the weapon; a scaled amount of 0 or less does nothing. Sends the notifications below |
| `PW.Progression.GetLevel(ply) -> integer` | Shared. Server: computed from the XP. Client: the NW2 value `pw_level` (default 1) |
| `PW.Progression.GetProgress(ply) -> into, need` | Client reads the NW2 values: XP into the current level and XP for the next one (`need` is 0 at the cap; defaults 0 and 1000) |
| `PW.Progression.GetWeaponLevel(ply, weaponClass) -> integer` | Server, and the local player on a client (see "Storage and deltas"). Level of the weapon from its XP (1 without XP) |

The XP keeps counting past the level cap; the bar stays full. A reload of the module keeps the sessions.

Only humans earn: the listener of `PW_ScoreEvent` ignores bots. The weapon class comes from the `weapon` argument of the
event (an invalid entity gives no weapon XP).

## Unlock checks

| Function | Contract |
| --- | --- |
| `PW.Progression.IsUnlocked(ply, kind, id) -> boolean` | Server. `kind` is a registry kind (`weapons`, perks, equipment, streaks, wildcards: any kind with a registry), `"attachments"` or `"camos"`. For the last two `id` is `"<weapon>:<option>"`. An unknown entity or a malformed id is not unlocked |
| `PW.Progression.LockedOptions(ply, weaponId, build) -> table<string, boolean>` | Server. The option ids of `build` (`slot -> option\|false`) that are locked: curated options by their `Unlock`, the others by the count limit (below) |
| `PW.Progression.AttachmentLimit(ply, weaponId) -> integer` | Server. How many uncurated, non-cosmetic attachments the weapon may hold: the weapon level capped by `loadout.maxattachments` (the cap itself with `unlockall`) |

Rules (`sh_unlocks.lua`):

1. An entity is unlocked when the player level reaches its `Unlock` (an integer or `{ level = N }`). An entity without
   `Unlock` is open from the start (no kind has a hidden default level), so a pack works without markup.
2. A curated attachment (`Attachments[option].Unlock`) or camo (`Camos[id].Unlock`) is unlocked by the weapon level.
   `Hidden` never unlocks, not even with `unlockall`.
3. An attachment without a curated `Unlock` is unlocked by count: the weapon level is the number of such attachments a
   build may hold (level 1 allows 1), capped by `loadout.maxattachments`; options are counted in slot-name order and the
   ones past the limit are locked. Cosmetic options (a `Cosmetic` flag, or listed in `Camos`) are not counted.
4. `progression.unlockall` opens rules 1 to 3 (the count limit becomes the cap). `Hidden` stays hidden.

The server decides (the loadout module uses these checks through `PW.LoadoutContext`: `isUnlocked`, `lockedOptions`; see
`loadout.md`). Since T-4.10 the same functions also answer on a client for the local player, from the levels the server
sent (see below).

## Automatic unlock levels (T-11.7)

Source: `design/06-progression.md` d.2 revision 2026-11-07 (the weights are pending confirmation, the local manual checklist (not published)
section 7). Module `autounlock` (`lua/privatewar/modules/autounlock/`: `shared.lua` glue, `sh_rules.lua` pure rules),
namespace `PW.AutoUnlock`, types `lua/privatewar/types/autounlock.lua`. Generic: it works on any weapon adapter that
gives stats; the adapter methods it uses are `GetBaseStats`, `GetSlots`, `GetOptions` and the optional
`GetOptionStats`, `GetOptionSetKey` (`adapter.md`, "Option stats").

It fills the unlock fields the rules above read, with a `soft` registration, so hand curation always wins, field by
field and option by option:

- `Unlock` of a weapon: a player level in `1..progression.maxlevel`;
- `Attachments[option].Unlock`: a weapon level in `1..progression.maxweaponlevel` (rule 2 then applies instead of the
  count rule 3).

### When and what

1. On `PW_WeaponsLoaded` of each realm (both realms compute, because the checks answer on the client too). Not in
   `PW_RegisterWeapons`: the order of its listeners is undefined, and only after the phase are the catalogue fills and
   every hand curation in the registry.
2. Candidates: the entries of the weapons registry with a `Category` and a `Kind` other than `melee`, `throwable` and
   `other`. A weapon with a `Price` gets nothing (it stays shop-only, rule 5). Cosmetic slots and options get nothing
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

### File

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

### Net messages

The wallet fields (currency, owned keys, the delta's `earned` and `spent`) are added to the upload and the delta by T-4.12, see
"Wallet (T-4.12)"; the rows below show the T-4.10 fields. All four use explicit `net.Write*` (no `net.WriteTable`).

| Message | Direction | When | Fields |
| --- | --- | --- | --- |
| `pw_progression_upload` | client to server | `InitPostEntity`, once | `xp` UInt(32), `count` UInt(16), `count` x (`class` string, `xp` UInt(32)); the top 256 weapons by XP |
| `pw_progression_delta` | server to the owner | every 10 s, on every phase change (never empty) | `session` UInt(32), `seq` UInt(32), `xp` UInt(32), `count` UInt(16), `count` x (`class` string, `xp` UInt(32)) |
| `pw_progression_levels` | server to the owner | after the upload, on every level change (player or weapon), on entering `PREMATCH` (one frame after, when the settings snapshot is taken) | `level` UInt(16), `unlockAll` bool, `maxAttachments` UInt(8), `count` UInt(16), `count` x (`class` string, `level` UInt(16)); only weapons above level 1 |
| `pw_progression_summary` | server to the owner | at `POSTMATCH`, after the last flush | `xp` UInt(32), `levelBefore` UInt(16), `levelAfter` UInt(16), `count` UInt(16), `count` x (`class` string, `before` UInt(16), `after` UInt(16)), `medals` UInt(8), `medals` x (`id` string, `count` UInt(16)) |

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
  `GetWeaponLevel(ply, weaponClass)` have the same contracts as on the server; with `unlockall` `IsUnlocked` is true
  (except `Hidden`).
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
| `unlockall` | bool | false | | Everything unlocked, XP still counts |
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

Unlock rule 5 (`IsUnlocked`): while the economy module is active, an owned item is unlocked (a Hidden camo or attachment
stays hidden), and an entity with a `Price` and no `Unlock` is for sale only (locked until bought, open with
`unlockall`). With the economy module disabled prices are ignored and rule 1 stands.
