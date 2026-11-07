# Streaks API: the `streaks` kind, `PW.Streaks`, `PW.Reveal`

Status: added after T-4.6 (2026-11-07). The code wins over any description here.

Module `streaks` (`lua/privatewar/modules/streaks/`: `shared.lua` slots, settings, pure earning rules and wire,
`sh_reveal.lua` reveal rules and radar wire, `init.lua` server state and activation, `sv_reveal.lua` `PW.Reveal` and
jamming, `cl_init.lua` keys and radar data). Kind: `kinds/streaks.lua`. Streaks: `lua/privatewar/streaks/`. HUD:
`lua/privatewar/hud/streaks.lua`. Types: `lua/privatewar/types/streaks.lua`. Source decisions:
`design/05-loadout.md` d.9, d.10, `design/01-extensibility.md` d.12, d.16. It builds on `core.md` (`PW.Instance`,
`PW.Net.Receive`, settings), `loadout.md` (slots) and `modes.md` (`PW_ScoreEvent`).

## Kind `streaks`

One file per streak in `lua/privatewar/streaks/`, class table `STREAK`. Never auto-subscribed: using a streak
makes a `PW.Instance` of it. Enable ConVar `pw_streak_<id>_enabled`. The registry is `PW.Registries.streaks`.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `Name` | string | yes | Display name |
| `Kills` | number | yes | Cost when earned by kills |
| `OnEquip(owner)` | function | yes | The activation (runs when the instance is made) |
| `Score` | number | no | Cost when earned by score; default `Kills` x 100 |
| `Duration` | number | no | Seconds until the module ends the instance; default `PW.Streaks.DefaultDuration` (10) |
| `OnUnequip(owner)` | function | no | Runs when the instance ends |
| `BotShouldUse(bot)` | function | no | Whether a bot should use the streak now; absent means always |

## Slots

`streak1`, `streak2`, `streak3` (kind `streaks`, no filter, no group), labels `#pw.slot.streakN`. Streaks are outside
the Pick X budget and cost nothing. Defaults (loadout default and all presets): `uav`, `counter_uav`, `airstrike`.
The streak set (the ids in the three slots, sorted by cost) is read when the player spawns in LIVE; a class edit
applies on the next spawn.

## Settings

Module settings (scope `streaks.`):

| Id | Type | Default | Meaning |
| --- | --- | --- | --- |
| `streaks.earn` | enum `kills`, `score` | `kills` | `kills`: the counter grows by 1 on the score event `kill`; `score`: it grows by the points of every score event (`PW_ScoreEvent`) |
| `streaks.persist` | bool | false | Keep the counter after death |
| `streaks.chain` | bool | false | Kills and points made by streak damage count toward streaks |

Question `PW_StreaksPersist(ply)` (through `PW.Ask`): `true` keeps the counter after death even when
`streaks.persist` is false.

The cost of a streak is `Kills` in kills mode, `Score` (default `Kills` x 100) in score mode. A streak is earned when
the counter crosses its cost; the counter does not loop after the last streak. The counter resets on death unless
persisted. Counting works only in LIVE.

## `PW.Streaks`

Server:

| Function | Contract |
| --- | --- |
| `Use(ply, id) -> boolean` | Takes the streak `id` out of the inventory and activates it. `false` outside LIVE, for a dead player, or when the id is not in the inventory. Used by the key message and by bots |
| `Ready(bot) -> string?` | The first inventory id whose `BotShouldUse` agrees (or that has none); `nil` when none |
| `Give(ply, id) -> boolean` | Adds a streak to the inventory (tests, modes); `false` for an unknown id |
| `StreakDamage(fn, ...)` | Runs `fn(...)` with a depth counter: score events inside it are streak kills and do not count unless `streaks.chain` is set. Errors are printed, not thrown |
| `Jam(owner, duration)` | A Counter-UAV: hides the owner's side from hostile reveals and sends the jam notice to hostile players |
| `Enemies(owner) -> Player[]` | The living enemies of the owner (`PW.IsEnemy`) |
| `Viewer(owner) -> integer\|Player` | The reveal viewer of the owner: the team index when the team is active, else the owner |
| `Progress(ply) -> integer` | The counter |
| `Inventory(ply) -> string[]` | The held streak ids (oldest first) |
| `Set(ply) -> PW.StreakSetEntry[]` | The streak set `{ id, cost }`, sorted by cost |

The inventory keeps at most `MaxInventory` (15) streaks; the oldest is dropped. It resets when LIVE starts (from
PREMATCH), at the end of the match and on disconnect; death keeps it.

Client: `Progress(ply)`, `Inventory(ply)` and `Set(ply)` read the NW2 values below; `Blips()` the live radar blips
(`{ index, pos, ends }`), `Jammed() -> boolean`, `Selected` the selected inventory index (1-based, reset when LIVE ends).

The HUD radar draws `Blips()` and `Jammed()`: see `ui.md`, "Radar (element `radar`, T-6.6)".

## `PW.Reveal(viewer, targets, duration) -> integer`

Server. The only path that sends enemy positions (`DESIGN.md` net rule). `viewer` is a player or a team index; the
positions of the visible `targets` go to the human players of the viewer's side, and the viewer's bots get a `radar`
stimulus (`PW.Bot.AddStimulus`). A target hidden by an active Counter-UAV of the target's side is filtered out. At most
127 blips per message. Returns the number revealed.

## Net messages

`pw_streak_use` (client to server, `PW.Net.Receive`: any player, LIVE only, 4 per second, 1 byte): `UInt(4)`, the
1-based inventory index of the streak to use.

`pw_reveal` (server to client): `UInt(1)` kind.

- Kind 0, blips: `UInt(9)` duration in tenths of a second, `UInt(7)` count, then per blip `UInt(8)` entity index and
  three `Int(15)` coordinates (x, y, z) in units of 2 world units (rounded, clamped).
- Kind 1, jam: `UInt(9)` duration in tenths of a second.

## NW2 values of the player

| Key | Type | Content |
| --- | --- | --- |
| `pw_streak_n` | int | The counter |
| `pw_streak_inv` | string | Inventory ids, comma-separated |
| `pw_streak_set` | string | Streak set as `id:cost` pairs, comma-separated |

Written only when they change.

## Keys

`pw_key_streak` (default `5`) uses the selected streak; `pw_key_streak_next` (default `6`) selects the next one (cycles).
The console commands `pw_streak` and `pw_streak_next` do the same. While the inventory is not empty (during LIVE) the
binds of these keys, `slot5` and `slot6`, are swallowed; with an empty inventory they switch weapons as usual.

## HUD

`hud/streaks.lua` (order 31, LIVE; pure rules `modules/hud/sh_streaks.lua`, layout `PW.HUD.Streaks`, types
`types/hud_streaks.lua`): up to three squares on the right edge above the equipment lines, one per streak of the set,
the cheapest at the bottom. Each square shows a short label (`UAV`, `CUAV`, `AIR`; another streak: the first four
letters of its name) and its cost. A progress bar to the left fills from the bottom with the counter: it reaches the
centre of a square exactly at that square's cost, is linear between two squares and stays full after the last one
(the counter does not loop).

| Square state | When | Look |
| --- | --- | --- |
| `locked` | Counter below the cost, none held | Dim |
| `spent` | Counter at or past the cost, none held (used) | Dim, muted label |
| `ready` | Held, not selected | Lit (accent border), next-key hint `[6]` on the left |
| `selected` | Held and selected (`PW.Streaks.Selected`) | Accent fill, use-key hint `[5]` on the left |

A held streak stays lit after death, when the counter is back at zero. With Button hints `gamepad` and the d-pad on,
the hints are `[D-UP]` and `[D-RIGHT]`. More than one copy held shows `x2` in the square's corner. Above the squares:
the radar notice (`UAV ONLINE`, `RADAR JAMMED`) and, when the selected streak is not in the set (earned before a
class change), its line `[5] NAME`. Everything is rebuilt only when an input changes; a frame allocates nothing.

Pure functions on `PW.HUD`: `_StreakSquares(view, out) -> count`, `_StreakAnchor(index, size, gap)`,
`_StreakFill(squares, count, progress, cfg) -> 0..1`, `_StreakHint(state, keys) -> string`,
`_StreakShort(id, name)`, `_StreakOrphan(squares, count, view) -> id?`. Tests:
`lua/tests/privatewar/hud_streaks_v2.lua`.

## The streaks

| Id | Cost (kills / score) | Duration | Effect |
| --- | --- | --- | --- |
| `uav` | 3 / 300 | 30 s | Reveals the living enemies to the owner's side at activation and every 3 s; blips live 3.5 s |
| `counter_uav` | 4 / 400 | 25 s | The owner's side is hidden from hostile reveals; hostile players get a jam notice |
| `airstrike` | 5 / 500 | 4 s | The owner's aim point and direction fix a line. After a 2 s delay, 5 bombs 200 units apart explode, one every 0.3 s; each is `util.BlastDamage` of 220 within radius 300, attributed to the owner inside `StreakDamage` (it can hurt the owner) |

Bot rule: a bot uses UAV and Counter-UAV whenever it has them (`BotShouldUse` is always true). It uses an airstrike
only when its aim point is at least 500 units away and an enemy stands within 450 (1.5 x radius) of that point.

## Bots

See `bots-blackboard.md`: `PW.BotObjectives.ReadyStreak` calls `PW.Streaks.Ready`, `UseStreak` calls `PW.Streaks.Use`.

## Mandatory cases

`TASKS.md` T-4.6 (tests in `lua/tests/privatewar/streaks.lua`). Manual checks: the local manual checklist (not published), sections "Kill streaks
(T-4.6)" and "Kill streaks: squares and bar".
