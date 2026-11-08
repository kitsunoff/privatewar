# Modes API: `MODE`, score, rounds, playlists, vote

Status: frozen on 2026-11-07, changes only through the orchestrator.

Extended on 2026-11-07 after T-2.1, T-2.2 and T-2.3: the items of "Open in design" that the lane agents decided in
code (items 2, 3, 5, 6, 8, 9 and parts of item 1) are now in the main text. Extended again on 2026-11-07 after T-2.4,
T-2.5, T-2.6 and T-2.13 (Domination, Kill Confirmed, playlists, the `bots` placeholder, the vote and `PW_NextMatch`):
items 4, 7 and 14 and the event ids of item 1(a) that these tasks award are decided in code and moved to the main
text. The code wins over any description here. Items 11, 12 and 13 and the remaining event ids of item 1(a) are still
open. Decisions marked "lane agent" are gameplay or API details that the orchestrator recorded after the merge.

Contract for the `modes` lane (T-2.1 to T-2.6, T-2.13). It sits on top of `core.md` (kind `modes`, hook dispatch,
settings, phases and match, `PW.Call`) and `teams.md`; it does not repeat them. Where a name is not defined by a
design decision it is listed under "Open in design" at the end and is **not** part of the contract yet.

Every item cites its decision as `<file> d.<n>` (files under `design/`). Types of the existing code are in
`lua/privatewar/types/`; the types of the new items are written by the lane that implements them.

## Ownership

| Item | Lane | Where |
| --- | --- | --- |
| Kind `modes`, kind file | core (exists) | `lua/privatewar/kinds/modes.lua` |
| Modes `tdm`, `ffa`, `dom`, `kc`, abstract `round_base` | modes | `lua/privatewar/modes/` |
| Kind `playlists` (the declaration, exists) and playlist files | core files / modes | `lua/privatewar/kinds/playlists.lua`, `lua/privatewar/playlists/` |
| Modules `score`, `match_rules`, `vote`, `teams`, `playlists`, `bots` (placeholder), `kc_tags`, `dom_flags` | modes | `lua/privatewar/modules/<id>/` |
| Kind `score_events` (the declaration) | core files, see "Core changes needed" | `lua/privatewar/kinds/score_events.lua` |
| Event files `kill`, `headshot` | modes (T-2.1) | `lua/privatewar/score_events/` |
| Event files `dom_capture` (T-2.4), `kc_confirm`, `kc_deny` (T-2.5) | modes | `lua/privatewar/score_events/` |
| Other event files (assist, match win, medals, ...) | the lane that awards them; ids: "Open in design", item 1 | `lua/privatewar/score_events/` |

## `MODE` class table

Kind `modes` (`core.md` "Built-in kind `modes`"): folder `modes/`, class table `MODE`, never auto-subscribed
(`01-extensibility.md` d.18). An entity file is a single file or a folder (`01-extensibility.md` d.8).

### Fields

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `Name` | string | yes | Display name, a localisation key (`02-modes.md` d.7) |
| `Teams` | number | yes | Team count; `0` is FFA (`02-modes.md` d.6, d.7). The teams module reads it (`teams.md`) |
| `Description` | string | no | Text for the lobby and the vote (`02-modes.md` d.7). Type: see "Open in design", item 11 |
| `Icon` | string | no | Icon for the lobby and the vote (`02-modes.md` d.7). Type: see "Open in design", item 11 |
| `Short` | string | no | Short badge text for the mode icon in the lobby and the vote, for example `"TDM"`, `"DOM"`, `"KC"`. Fallback when absent: the initials of `Name`. Contract addition of D1 (`10-frontend.md` d.10). Read since U-4 by `PW.UI.Monogram(mode)` (`ui_kit/sh_models.lua`); the field is optional, every built-in mode sets it (`tdm` "TDM", `ffa` "FFA", `dom` "DOM", `kc` "KC") and the `modes` kind file does not validate it |
| `Base` | string | no | Id of the mode it inherits from; resolved after every file loaded (`01-extensibility.md` d.8) |
| `Abstract` | boolean | no | Usable as a base only; hidden from every list and from the vote (`00-core.md` d.4; generic for every kind) |
| `Settings` | table | no | Setting declarations, scope `match` only; merged along the `Base` chain (`01-extensibility.md` d.17; `core.md` "Settings") |
| `SettingDefaults` | table | no | `{ [fullId] = value }`: overrides defaults of module `match` settings for this mode (`01-extensibility.md` d.17) |
| `MapData` | boolean | no | `true`: the mode needs `MAP.Modes.<mode id>` on the map (`03-mapdata.md` d.6; see `map.md`) |
| `RoundsToWin` | integer | no | Only on modes with `Base = "round_base"`: rounds a team needs to win the match. Default 6; floored, at least 1 (`00-core.md` d.4 example; `TASKS.md` T-2.3). See "`round_base`" |
| `SwapSidesEvery` | integer | no | Only on modes with `Base = "round_base"`: swap the sides after every N completed rounds; default and `0` = never; the last round of the match is never followed by a swap (`TASKS.md` T-2.3). See "`round_base`" |

`MODE.ClassName` (the id), `BaseClass` and `IsValid` are set by the core (`core.md` "Fields every entity has").
`self:Setting(key)` is added by the core (`core.md` "Settings").

### Methods

All methods are called by the core or by modules through `PW.Call` (`00-core.md` d.6): `pcall`, one log line on an
error; an error in the active mode aborts the match (`01-extensibility.md` d.15; `core.md` "Entity calls").

| Method | Required | Realm | Contract |
| --- | --- | --- | --- |
| `MODE:Start()` | yes in practice | server | Called by the core on entering `LIVE` (`00-core.md` d.3). The mode owns everything inside `LIVE` |
| `MODE:Cleanup()` | yes in practice | server | Called by the core on leaving `LIVE`, only if `Start` ran (`00-core.md` d.3; `core.md` "Hooks", `PW_MatchEnd`) |
| `MODE:Think()` | no | server | Called by the core every tick during `LIVE` (`02-modes.md` d.7). A mode adds no `Think` hook of its own |
| `MODE:ValidateMapData(data)` | no | server | `data` is `MAP.Modes.<mode id>`. Returns `true`, or `false, reason` (`03-mapdata.md` d.6). Used with `MODE.MapData = true` |
| `MODE:BotObjectives(team)` | no | server | Returns the objective list of one team (see "`BotObjectives`"). Absent = no objectives (`07-bots.md` d.9, d.14) |
| `MODE:RoundWinner(timedOut)` | no | server | Only `round_base` and its children: the verdict of the running round. See "`round_base`" |
| `MODE:PW_<Name>(...)` | no | per hook | Default answer of a question hook or reaction to a notification hook. Called last, after every `hook.Add` listener (`02-modes.md` d.7; `01-extensibility.md` d.9, d.18) |

- `Start` and `Cleanup` are not in the `Required` list of the kind (the kind checks `Name` and `Teams` only,
  `core.md`). A mode without them runs a match that does nothing; the contract expects both.
- `MODE:PW_*` methods: only the hooks of the "Hooks" table below are defined by the design. A mode may define a
  method for any `PW_*` hook, including those of other subsystems (`02-modes.md` d.7, last bullet).
- A mode never calls `hook.Add` / `hook.Remove` in `Start` / `Cleanup` for `PW_*` hooks: it defines the method
  (`01-extensibility.md` d.9).
- A mode finishes the match with `PW.Match.Finish(result)` (`00-core.md` d.3; `core.md` "`PW.Match`"). The shape of
  `result`: "`PW.MatchResult`" below.

### `BotObjectives`

`MODE:BotObjectives(team)` (`07-bots.md` d.9, d.14). Called by the bot commander at 1 Hz per team through
`PW.Call`; the answer is a list (array) of objectives:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Stable id of the objective, for example `"flag_B"` |
| `pos` | `Vector` | Position |
| `radius` | number | Radius around `pos`, for example `160` |
| `action` | string | `"capture"`, `"defend"`, `"collect"`, `"deny"` or `"hold"`. S&D adds `"plant"` and `"defuse"` later |
| `weight` | number | `0..1`, importance for this team now |
| `want` | integer | Desired number of bots |

- The commander assigns bots using `weight`, `want`, distance and personality; the `objective` behaviour performs the
  `action` (`07-bots.md` d.14).
- MVP content (`07-bots.md` d.14): TDM and FFA return nothing. Domination returns one objective per flag: a flag that
  is not ours is `capture`; ours is `defend` with `want` at most a third of the team; ours under capture is `capture`
  with a high weight. Kill Confirmed returns one per tag: an enemy tag is `collect`, an own team's tag is `deny`,
  `want = 1`, weight grows with closeness; refreshed every second.
- The `team` argument is a team index (`teams.md`). FFA: see "Open in design", item 12.
- `dom` and `kc` implement `BotObjectives` (T-5.11): `dom` returns `PW.BotObjectives.DomObjectives` over the flags of the
  running match, `kc` returns `PW.BotObjectives.KCObjectives` over the tags on the ground, both for the given team (the
  rules above). `tdm` and `ffa` do not define it; the commander does not ask a mode for a bot without a team (FFA).

### Hooks a mode may answer

The hooks and their kind (question or notification, `01-extensibility.md` d.9) are listed once, in "Hooks" below.
Question: the first non-nil answer wins, the mode's method is the default. Notification: listeners must not return a
value, because a returned value stops the remaining listeners **and the mode's method**.

## Hooks

Dispatch rules are in `core.md` "Hook dispatch" (`PW.Ask` for questions, `PW.Notify` for notifications). The
active mode's method of the same name is called after the listeners.

| Hook | Type | Arguments | Answer or effect | Source |
| --- | --- | --- | --- | --- |
| `PW_CanRespawn` | question | `ply: Player` | `false` forbids the respawn; any other answer (`nil`, `true`) allows it. Mode defaults: `tdm` (and `ffa`) `true`, `round_base` `false`. Asked every dead tick by `match_rules` | `02-modes.md` d.7; `01-extensibility.md` d.9 |
| `PW_RespawnDelay` | question | `ply: Player` | Seconds (number). Asked once, on the first dead tick; a non-number answer means 3 s (`PW.MatchRules._DefaultDelay`). `tdm` answers `self:Setting("respawndelay")` | `02-modes.md` d.7 |
| `PW_SelectSpawn` | question | `ply: Player` | An entity, or a table `{ pos: Vector, yaw: number? }` (`PW.SpawnPoint`); anything else (`nil`) keeps the base gamemode's choice. The spawns module answers it with `PW.Spawns.Pick` (`map.md`); a mode may answer first. Fired by `match_rules` (see "Match rules module") | `02-modes.md` d.7; `03-mapdata.md` d.7 |
| `PW_IsEnemy` | question | `a: Player, b: Player` | `boolean`; documented in `teams.md` | `02-modes.md` d.6 |
| `PW_PlayerKilled` | notification | `victim: Player, attacker: Entity, dmg: CTakeDamageInfo` | The mode scores here; the default of `tdm`, `ffa` and `round_base` is `PW.MatchRules.ScoreKill`. Fired by `match_rules` from `DoPlayerDeath`, during `LIVE` only | `02-modes.md` d.7; `01-extensibility.md` d.9 |
| `PW_RoundStart` | notification | `round: integer, swapped: boolean` | Fired by `round_base` only, after the swap and the respawn; never in non-round modes | `00-core.md` d.4 |
| `PW_RoundEnd` | notification | `round: integer, winner: integer or false, wins: table<integer, integer>` | Fired by `round_base` only, before any swap; `winner` is a team index or `false` for a draw; `wins` is a copy of the rounds won by team index, including this round | `00-core.md` d.4; `01-extensibility.md` d.9 |
| `PW_ScoreValue` | question | `ply: Player, eventId: string, points: number` | A number replaces the points of the event; any other answer (`nil`) keeps them. `points` is `EVENT.Points` | `06-progression.md` d.3 |
| `PW_ScoreEvent` | notification | `ply: Player, eventId: string, points: number, xp: number, weapon: Weapon?` | Fired by the score module after an award, after the score was added; `points` and `xp` are the final values | `06-progression.md` d.3 |
| `PW_ScoreChanged` | notification | `ply: Player, score: integer, delta: number, team: integer?, teamScore: integer?` | The resulting score changed; fired right after `PW_ScoreEvent`. `score` is the player's new match score, `delta` the final points of the event, `team` the team index the points were added to (`nil` in FFA and outside teams `1..N`), `teamScore` the team's new score (`nil` with `team`) | `01-extensibility.md` d.9 |
| `PW_KCTagCollected` | notification | `collector: Player, victim: any, verdict: "confirm"\|"deny"` | Fired by the `kc_tags` module on a valid pickup of a Kill Confirmed tag, after the tag was removed; the verdict is `"confirm"` for an enemy of the victim, `"deny"` for a teammate or the victim. `victim` is the dead player entity as given to `Spawn`. `kc` scores here (see "Kill Confirmed"). Fired through `PW.Notify`, so the active mode's method runs after the listeners | `02-modes.md` d.5; T-2.5 |
| `PW_NextMatch` | question | `mode: table` (the mode of the match that just ended, `PW.ActiveMode`) | Asked by the core on the `VOTE` to `PREMATCH` step (timer end or `PW.Match.EndVote`). The answer is `{ mode = <mode entity>, map = <string?> }` (`PW.NextMatch`); `nil` repeats the mode on this map; any other answer is ignored with one log line and the mode repeats. The first non-nil answer wins. Answered by the vote module (see "Vote module"); a mode may answer it too. Documented in `core.md` "Hooks" | `08-lobby.md` d.5; `00-core.md` d.2 |
| `PW_CanPickup` | question | not specified: "Open in design", item 13 | Named as an example of a question hook | `01-extensibility.md` d.9 |

Hooks of other subsystems that a mode may also answer (documented by their lanes, listed so the modes lane knows
they exist): `PW_PlayerLoadout(ply)`, `PW_LoadoutCost(item)`, `PW_ValidateLoadout(ply, loadout)` (questions,
`05-loadout.md` d.1, d.6) and the `PW_Bot*` notifications (`07-bots.md` d.3). Core hooks (`PW_MatchStart`,
`PW_MatchEnd`, `PW_PhaseChange`, ...) are in `core.md` "Hooks".

## Score module

Module `score` (modes lane, T-2.1). Source: `06-progression.md` d.3.

### Kind `score_events`

Folder `score_events/`, class table `EVENT` (`01-extensibility.md` d.12 table, `06-progression.md` d.3). Data
only; no methods. The kind declaration is `lua/privatewar/kinds/score_events.lua` (`Global = "EVENT"`, never
auto-subscribed). `Required`: `Name` (string) and `Points` (number); `XP`, `Medal` and `Currency` are optional.

| Field | Type | Meaning | Source |
| --- | --- | --- | --- |
| `Name` | string | Display text, a localisation key (`"#pw.score.kill"`) | `06-progression.md` d.3 |
| `Points` | number | Match score; also streak progress in `score` streak mode | `06-progression.md` d.3 |
| `XP` | number? | XP; `nil` means the same as `Points` | `06-progression.md` d.3 |
| `Medal` | boolean | `true`: popup with icon and sound. Medals are events with `Medal = true`; there is no `medals/` kind | `06-progression.md` d.3 |
| `Currency` | number? | Optional meta currency; default is 10 % of XP | `06-progression.md` d.6 |

MVP event ids are named in `06-progression.md` d.3 as a list: kill, headshot, assist, point capture, tag confirmed,
tag denied, match win; medals: double kill, triple kill, revenge, first blood, 5-kill streak, saviour. `kill` and
`headshot` were written by T-2.1 (lane agent decision, `lua/privatewar/score_events/`):

| Id | `Name` | `Points` | `XP` | `Medal` |
| --- | --- | --- | --- | --- |
| `kill` | `#pw.score.kill` | 100 | `nil` (= points) | `false` |
| `headshot` | `#pw.score.headshot` | 50 | `nil` (= points) | `true` |

`headshot` is awarded in addition to `kill`. Ids of the other events that exist (lane agent decisions, T-2.4 and T-2.5):

| Id | `Name` | `Points` | `XP` | `Medal` | Awarded by |
| --- | --- | --- | --- | --- | --- |
| `dom_capture` | `#pw.score.dom_capture` | 200 | `nil` (= points) | `false` | `dom`: to every living player of the capturing team inside the flag when its owner changes ("point capture") |
| `kc_confirm` | `#pw.score.kc_confirm` | 100 | `nil` (= points) | `false` | `kc`: to the collector of an enemy's tag ("tag confirmed") |
| `kc_deny` | `#pw.score.kc_deny` | 50 | `nil` (= points) | `false` | `kc`: to the collector of a teammate's or one's own tag ("tag denied") |

The ids of the other events (assist, match win, the medals): "Open in design", item 1.

### `PW.Score.Award(ply, eventId, ctx?)`

- Called by modes and modules: `PW.Score.Award(ply, "kill", { weapon = wep })` (`06-progression.md` d.3).
- `ctx.weapon` (`Weapon?`): the weapon of the event. Weapon XP comes only from events awarded with a weapon
  (`06-progression.md` d.3).
- Server only. Returns `true, points, xp` (the final values) on success.
- An unknown or disabled event id, or an invalid player, is rejected (`TASKS.md` T-2.1, mandatory case): one log line
  (`score: unknown or disabled event <id>`), returns `false` and nothing else happens.
- Steps (`06-progression.md` d.3; `TASKS.md` T-2.1):
  1. Resolve the points: `EVENT.Points`, then the question hook `PW_ScoreValue(ply, eventId, points)`; a number answer
     replaces the value. `xp` is `EVENT.XP` when it is set (an answer never changes an explicit `XP`), else the final
     points.
  2. Add the match score to the player and, in a team mode, to the player's team: the team is `ply:Team()` when it is
     in `1..N` of the active teams (`PW.Teams.GetActive()`), else none (FFA, the free team, no teams module). Publish
     it through NW2.
  3. Fire the notification `PW_ScoreEvent(ply, eventId, points, xp, weapon)` with the final values.
  4. Fire the notification `PW_ScoreChanged(ply, score, delta, team, teamScore)` (see "Hooks").
- Order: score added and published, then `PW_ScoreEvent`, then `PW_ScoreChanged`. Consumers of the resulting score
  (score limit checks) listen to `PW_ScoreChanged`.
- Reading (shared): `PW.Score.Get(ply) -> integer` and `PW.Score.GetTeam(index) -> integer` (`0` when none). The
  server reads its store, a client the NW2 values: Int `pw_score` on each player and the global Int
  `pw_score_team_<index>`.
- Reset: the scores (and their NW2 values) are zeroed when `PREMATCH` turns into `LIVE` (before `MODE:Start`) and when
  the phase becomes `LOBBY`; they stay readable in `POSTMATCH` and `VOTE`.
- Listeners of `PW_ScoreEvent` (other lanes): progression (player XP, weapon XP when `weapon` is given), killstreaks
  in `score` mode (`05-loadout.md` d.9), HUD popups and medals, the announcer (`06-progression.md` d.3).
- `PW_ScoreEvent` is a notification: a listener must not return a value (`01-extensibility.md` d.9).
- Popup message `pw_score_popup` (T-6.4): after the notifications, one message to the owner of the award only, with
  `String` event id and `UInt(16)` points (clamped to 0..65535). Not sent for bots or for 0 points. The HUD side (merge,
  timings, medal queue) is in `ui.md`, "Score popups and medals".

## `PW.MatchResult`

The value a mode gives to `PW.Match.Finish(result)`; `PW_MatchEnd` receives it (`core.md` "Hooks"). Decided by the
lane agent of T-2.2 (type `PW.MatchResult`, `lua/privatewar/types/match_rules.lua`):

| Field | Type | Meaning |
| --- | --- | --- |
| `reason` | string | Why the match ended: `"scorelimit"`, `"timelimit"` (kill-limit modes) or `"roundlimit"` (`round_base`); other modes may add their own |
| `teams` | boolean | `true`: ids in `winner` and `standings` are team indices; `false`: they are players (FFA) |
| `draw` | boolean | `true`: the top score is shared (or there is no standing), there is no winner |
| `winner` | `any?` | The standing id of the winner: a team index or a `Player`. `nil` on a draw |
| `standings` | `{ id: any, score: integer }[]` | Best first; equal scores keep the input order (team index order, or `UserID` order in FFA) |

`PW.MatchRules._Evaluate` checks the score limit before the time limit; a limit of `0` or less is off.

## Match rules module

Module `match_rules` (modes lane, T-2.2; `lua/privatewar/modules/match_rules/`). The glue between the engine and the
mode for kills, respawns and spawning, and the win rules of kill-limit modes (`tdm`, `ffa` and their children).
Source: `02-modes.md` d.5 to d.7, `00-core.md` d.3, d.5. Everything below happens during `LIVE` only; the engine
hooks go through `PW.HookFor`, so they stop while the module is disabled.

| Engine event | What the module does |
| --- | --- |
| `DoPlayerDeath` | Fires the notification `PW_PlayerKilled(victim, attacker, dmg)` |
| `PlayerDeathThink` | Respawn control: on the first dead tick asks `PW_RespawnDelay(ply)` (non-number: 3 s); once the delay has passed and `PW_CanRespawn(ply)` is not `false`, calls `ply:Spawn()`. Always blocks the base respawn on a key press |
| `Tick` | The same respawn control for every dead bot during `LIVE`: the engine runs no command, and so no `PlayerDeathThink`, for a dead player bot |
| `PlayerSelectSpawn` | Asks `PW_SelectSpawn(ply)`: a valid entity is used as the spawn point; a table with a `Vector` `pos` is applied when the player has spawned (`SetPos`, then the eye angle with `yaw`, default 0); anything else keeps the base choice. Not for map transitions |
| `PlayerSpawn` | Clears the respawn timer. In FFA moves the player to the free team before `GM:PlayerSpawn` |
| `PW_MatchStart` | Spawns every player in `UserID` order (FFA players are put in the free team first) |
| `PW_PhaseChange` | Zeroes the kill counts when `PREMATCH` turns into `LIVE` and on `LOBBY` |

- **FFA team.** `PW.MatchRules.FreeTeam = 1000`: a real engine team (`Free for all`), because with `GM.TeamBased` the
  base `GM:PlayerSpawn` makes a player of `TEAM_UNASSIGNED` or `TEAM_SPECTATOR` a spectator. It is outside `1..N`, so
  it is never a match team: no team score, everyone is an enemy (`teams.md`).
- **Scoring a kill** (`PW.MatchRules.ScoreKill(victim, attacker, dmg)`, the default of the `tdm`, `ffa` and `round_base`
  `PW_PlayerKilled` methods). Suicides, kills of a teammate (`PW.IsEnemy` false) and world kills score nothing.
  An enemy kill adds 1 to the attacker's kill count and, when the attacker is in a team `1..N`, to the team's count
  (CoD style: the limit counts kills, not points), then awards the score event `kill` and, when the victim's last hit
  group was the head, `headshot`, in that order, through `PW.Score.Award(attacker, id, { weapon = wep })`. The weapon
  is the inflictor when it is a weapon, else the attacker's active weapon.
- **Reading and NW2.** `PW.MatchRules.GetKills(ply)` and `GetTeamKills(index)` (shared, `0` when none; a client
  reads NW2): Int `pw_kills` on each player, global Int `pw_kills_team_<index>`. The global Float `pw_mode_ends` is
  the `CurTime()` at which the match ends by the time limit, `-1` without one.
- **HUD globals** (for `match_status`, `ui.md`): String `pw_hud_score` (the NW2 prefix of the per-team score of the
  running mode, `PW.MatchRules._HudScoreKey`) and Int `pw_hud_limit` (its score limit, `PW.MatchRules._HudScoreLimit`:
  `MODE.HudScoreLimit`, else `RoundsToWin`, else the `scorelimit` setting; `0` is none), both set at the match start
  and reset to the kill prefix and `0` in `PREMATCH` and `LOBBY`; at the match end Int `pw_result_winner`, Bool
  `pw_result_draw` and Int `pw_result_teams`.
- **Win check** (`PW.MatchRules.Check(mode, now, players?) -> PW.MatchResult?`): standings are the team kill counts
  (team modes) or the kill counts of every connected player (FFA); limits come from the mode settings `scorelimit`
  and `timelimit`; elapsed time is `now - mode._StartedAt` (`nil` `_StartedAt`: no result).

Modes `tdm` and `ffa` (`lua/privatewar/modes/tdm.lua`, `ffa.lua`; lane agent decisions):

- `tdm`: `Teams = 2`. `MODE:Start` stores `_StartedAt = CurTime()` and publishes `pw_mode_ends`; `MODE:Think` calls
  `PW.MatchRules.Check` and `PW.Match.Finish(result)` on a result; `Cleanup` clears both. A shared top score at the
  end is a draw. Settings in "Settings that belong to the modes lane".
- `ffa`: `Base = "tdm"`, `Teams = 0`; every player is an enemy, each player's kills count, the top player wins, a
  shared top score is a draw. It inherits everything and changes only `scorelimit` to 30 by default.

## `round_base`

Abstract mode `lua/privatewar/modes/round_base.lua` (modes lane, T-2.3). Source: `00-core.md` d.4.

- `MODE.Abstract = true`: absent from every list and from the vote.
- Implements the round loop, side swaps and the notifications `PW_RoundStart` / `PW_RoundEnd`. Round-based modes set
  `MODE.Base = "round_base"` and parameters only (`MODE.RoundsToWin`, `MODE.SwapSidesEvery`). `round_base` itself sets
  `Name`, `Teams = 2`, `RoundsToWin = 6`, `SwapSidesEvery = 0`.
- Swaps sides through the teams module: `PW.Teams.Swap()` (`teams.md`; `02-modes.md` d.6).
- In non-round modes the hooks never fire (`00-core.md` d.4). Modules that care about rounds (killcam, bots) listen
  to the two hooks.
- Order test (`TASKS.md` T-2.3): `PW_RoundStart` and `PW_RoundEnd` order is mandatory.

Settings (match scope, declared on `round_base`, inherited by the children as `<mode id>.<key>`; lane agent decision):

| Key | Type | Default | Range | Meaning |
| --- | --- | --- | --- | --- |
| `roundtime` | int | 120 | 0..600 | Round time in seconds; `0` = none |
| `intermission` | float | 5 | 1..30 | Seconds between rounds |

The loop (the state machine is pure data: `MODE._NewState`, `MODE._Step`; `Think` and `_Run` are thin glue):

1. `MODE:Start` builds the state before `PW_MatchStart`; the `match_rules` listener then spawns everyone
   (`core/sv_match.lua`, `enterPhase`). Round 1 starts on the first `Think` of `LIVE`: no respawn,
   `PW_RoundStart(1, false)`.
2. During a round every `Think` asks `MODE:RoundWinner(timedOut)`; `timedOut` is `true` once `roundtime` has passed
   (`roundtime = 0`: never). The answer: an integer team index `1..Teams` ends the round for that team; `false`
   ends it as a draw; `nil` goes on. Any other non-`nil` value counts as `false`. When the time is up and the answer
   is `nil`, the round is a draw.
3. Default `MODE:RoundWinner`: counts the living players of teams `1..Teams`. Among the teams that have players, the
   last team with a living player wins; if none is left it is a draw (`false`); fewer than two teams with players, or
   two or more teams still alive, is `nil` (and `false` when `timedOut`).
4. The round ends: the winner's `wins` grows (a draw adds nothing) and `PW_RoundEnd(round, winner, wins)` fires,
   before any swap. Then, if a team has `RoundsToWin` wins, `PW.Match.Finish(result)` is called with the result of
   "`PW.MatchResult`" (reason `"roundlimit"`, standings are the rounds won by team index) and the loop stops. A
   swap never follows the last round.
5. Otherwise an intermission of `intermission` seconds follows. If `SwapSidesEvery > 0` and the finished round number
   is a multiple of it, the sides are swapped when the intermission ends.
6. When the intermission ends: `PW.Teams.Swap()` if due (the `wins` move with the players: after a swap the wins of
   team `i` belong to team `i % Teams + 1`), then everyone respawns in `UserID` order, then
   `PW_RoundStart(round + 1, swapped)`; `swapped` is `true` when the sides were swapped just before this round.

- Order of one step: swap, respawn, `PW_RoundStart`; or `PW_RoundEnd`, `PW.Match.Finish`.
- Dead players stay dead during a round: `PW_CanRespawn` answers `false`. Kills are scored like in TDM
  (`PW_PlayerKilled` default is `PW.MatchRules.ScoreKill`).
- NW2 globals for HUDs (written after every step that did something, reset by `Cleanup`): Int `pw_round` (the current
  round, or the last one during an intermission, `0` before the first and after the match), Int
  `pw_round_wins_<team index>`, and the round end time in the match-end global `pw_mode_ends` (`CurTime()`; `-1`
  during the intermission and without a round time).
- The first mode that uses it is S&D, after MVP (`02-modes.md` d.5); no MVP mode inherits it. The `MODE` interface is
  designed so that S&D does not break the API.
- The loader checks `KIND.Required` on the file's own table before `Base` resolution (see "Core changes needed",
  item 2): a child mode must repeat `Name` and `Teams` today.

### Objective round lifecycle extension (frozen, implemented)

Orchestrator-approved extension (2026-11-08); tests precede implementation. Existing callers remain compatible.
Approved gameplay values are recorded in `design/02-modes.md` d.8; no `PW.API` bump.

| Signature | Meaning |
| --- | --- |
| `MODE:PrepareRound(round: integer, swapped: boolean)` | Optional server method, no return. Initialize the round roster, role/loadout facts and objective generation before any playable spawn. Absent = no-op. Called through `PW.Call`; the later base loop must stop after error/abort invalidates its state/mode. Initial-spawn failure gating needs the narrow ownership approval below. |
| `MODE:RoundWinner(timedOut: boolean) -> integer or false or nil, deferTimeout?: boolean` | Existing first return unchanged. Only second return **exactly `true`**, with nil verdict, prevents the base timeout draw for this step. Explicit team/draw verdict wins even when deferral is true. No stored/sticky overtime flag; the child must opt in on every step. |
| `MODE.RoundLimit: integer?` | Optional fixed **total completed** round limit, including draws. Absent or `0` keeps `RoundsToWin` unchanged. Positive value selects fixed-total semantics instead of first-to-wins: no early finish from `RoundsToWin`. At the limit, standings use wins, highest wins wins, shared highest is a draw; existing `reason = "roundlimit"`. Children set the field before calling base `Start`; no new base setting/default. |
| `MODE:FinalizeRounds(defaultResult: PW.MatchResult) -> PW.MatchResult?` | Optional terminal transform, once before Finish. Absent/nil preserves the default. A returned result must have the existing result shape; invalid output/error aborts without Finish or another round. Allows changing cohorts to return personal standings (`teams = false`) instead of retroactive current-team victory. |
| `PW_RoundPreparing(round, swapped)` | Notification before child `PrepareRound`; brain stops its stack here. |
| `PW_RoundPrepared(round, swapped)` | Notification after successful child preparation, before any playable spawn; each layer resets only its owned state here. Never emitted after preparation failure/abort. |
| `PW.MatchRules.Spawn(ply: Player)` | Server wrapper: one engine `ply:Spawn()`, then synchronous `PW_PlayerSpawned(ply)` after engine/base/loadout initialization returns. Route controlled initial, round and delayed human/bot respawns through it; no duplicate gives. |

Order, preserving existing public notification timing:

1. Initial: teams assigned in `PW_PhaseChange` → base `Start` builds the existing `starting` state →
   `PW_RoundPreparing` → `PrepareRound(1, false)` → `PW_RoundPrepared` → `PW_MatchStart` initial spawns →
   first `Think` emits `PW_RoundStart(1, false)`.
   There is no extra base respawn and no second preparation on that first `Think`; round 0 until then is unchanged.
2. Later: `PW_RoundEnd` → intermission → due side swap and wins migration →
   `PW_RoundPreparing` → `PrepareRound(nextRound, swapped)` → `PW_RoundPrepared` → ordered respawns → `PW_RoundStart`.
3. Terminal: credit round once → `PW_RoundEnd` → optional `FinalizeRounds` → `PW.Match.Finish` once; no next preparation, swap,
   respawn, notification or repeated win credit. Abort/cleanup invalidates outstanding work.

Pure seams: `_NewState(n, toWin, swapEvery, time, pause, roundLimit?)` adds one trailing optional
argument; `_Step(state, now, verdict, deferTimeout?)` adds one trailing optional argument. `_Run` handles later
preparation before its existing respawn. `Think` forwards both verdict returns. Ordinary children, existing
five/three-argument callers, timeout-draw tests, round event arguments and `RoundsToWin` results stay unchanged.

Exact tests-first assertions live in `tests/privatewar/round_objective_lifecycle.lua`: deadline equality and late
steps stay alive only with explicit deferral; removal of deferral draws immediately; `Think` forwards deferral;
preparation runs once before initial spawn and after each later swap/before respawn; terminal repeated steps
credit no additional win or action; fixed totals 1/3 ignore early first-to-wins, count draws, finish once and
create no fourth/second round; tied fixed-total standings draw; absent/zero total keeps first-to-wins behavior.
The original 23 shared lifecycle/objective cases were observed RED before runtime (22 failures, one legacy
compatibility pass), then passed with all 1395 baseline cases. Existing T-2.3 cases are retained unchanged.
This shared-seam evidence is not a completed-mode or human-checkpoint claim.

Initial failure protection is owned by `core/sv_match.lua` after `Start`: inspect the actual pending abort/phase
request, not only `IsValid` (active mode errors queue abort without disabling it). No initial match-start/spawn
notification is emitted after failed/aborted preparation. The spawn wrapper does not guarantee an external
addon's direct `ply:Spawn()` path; a post-base fallback for such calls needs separate explicit ownership.

`FinalizeRounds` may return only a dense, best-first standings array with unique identities and finite integer
scores. Team identities are positive finite integers; personal identities are Player entities, not SteamID
strings. Saved positive integer UserIDs remain valid personal identities: the existing `_ResultFields` publisher
already accepts a numeric winner independently of its `teams` flag. Player/numeric aliases are normalized to
UserID for duplicate and membership checks, not to calculate standings. A connection-validity requirement is
not added: a departed participant may remain through its saved identity. A non-draw winner must be a member at the unique top;
a draw has no winner and represents a shared top or empty standings. This validates the existing shape; it does
not calculate or replace a child's standings, award rewards or reinterpret its result.

### S&D map shape (frozen, authored)

`MAP.Modes.snd = { sites = PW.SNDSite[], bomb = Vector,
spawns = table<integer, PW.SpawnPoint[]> }`. Each proposed `PW.SNDSite` is
`{ id: string, pos: Vector, radius: number, above: number, below: number, approach: Vector }`:
unique stable id, marker/plant cylinder, explicit vertical bounds, and a reachable plant approach inside that
volume. `bomb` is the authored initial/recovery ground point; `spawns` uses side team indices, not cohorts.
All vectors/dimensions must be finite; radii positive, vertical bounds nonnegative. No dimensions, site count
or positions are chosen here. Cross-map `ValidateMapData` is structural only; current-map ground/hull/nav/LOS
validation is a separate activation check. Do not edit the shared map until the orchestrator serializes it.
This shape introduces no automatic map fallback; invalid out-of-world/unreachable bomb drops recover at `bomb`.

### Search and Destroy implementation boundary

The concrete `snd` child uses `round_base` and the approved preset in `design/02-modes.md` d.8. Its module
`snd` separates shared plain-data rules (`Validate`, `NewRound`, `Step`, `Death`, `Disconnect`, `Admit`,
`Snapshot`, `Objectives`, `HudText`) from world/input/replication wrappers. Types are in `types/snd.lua`.
`Step` returns the round verdict and explicit planted-timeout deferral; it never awards rewards or damages players.

The server roster binds a stable participant identity to the current connection UserID and a once-only life ticket.
JIP/reconnect/replacement cannot reuse that ticket; the next round rebuilds the roster before playable spawning.
The mode uses generic admission/quota and reversible equipment/effect APIs from [role policy](role-policy.md),
without accessing foreign private stores. Unused earned streak inventory is retained.

Every round uses the authored side-indexed spawn pool through the ordinary scoring/hull picker. The optional
`PW.SpawnPickOpts.spawns` replaces only the source pool; `first = true, all = false` retains side selection after
swaps. The spawns listener honors a mode's explicit `PW_SelectSpawn` before its generic default. Current-map
activation separately checks ground, standing hulls, site sight lines and mutual directed nav routes.

`PW_CanTakeDamage(victim, attacker, damage) -> boolean?` is a server question at the match-rules damage boundary
during LIVE; exactly false vetoes player damage, nil preserves ordinary behavior. S&D vetoes intermission and
non-roster life damage. Round end removes owned throwable projectiles and ends active equipment/streak effects;
ordinary non-round modes keep their existing lifecycle.

Recipient-specific `pw_snd_state` snapshots carry a bounded fixed shape with round generation and serial,
phase, deadline/fuse, site, optional attacker-only carrier/drop position and local held-action progress. There is
no client request, table serialization or hidden enemy payload. Planted bomb position/fuse are public to both
teams; defenders get no hidden carrier/drop objective coordinates. The physical bomb uses ordinary entity sight.
The client rejects stale generation/serial values; draw-independent labels are shared, draw-ready data is cached
outside HUDPaint. Implementation/gate evidence does not pass visual, spectator/P2P or human mode checkpoints.

### Restricted spectator policy (frozen, tests first)

Server question `PW_SpectatorPolicy(ply) -> PW.SpectatorPolicy?`, with
`{ restricted = true, eligible = { [currentUserID] = true } }`. Nil preserves ordinary roaming parking. Any
malformed non-nil policy fails closed to a fixed neutral view with no followed entity; an empty allow-set does
the same. Only positive integer UserIDs whose value is exactly true are admitted, bounded to 128 entries.

The lobby owner applies the policy synchronously before choosing a roaming camera in `enginePark`, through
public `PW.Jip.RefreshSpectator(ply) -> handled`. It changes only camera state, not teams, bodies, admission,
weapons or classes. A living valid eligible target is followed in-eye; an authorized current target is retained,
otherwise the lowest eligible live UserID is selected. No caller/client target argument is accepted. Unexpected
fields such as a forged `target` do not bypass the allow-set. Pure choice: `PW.Jip.SpectatorChoice`.

Death, disconnect, team-changing/changed and round-preparing/prepared events refresh restrictions through the
same owner; the visibility boundary rejects unauthorized observer targets before using them. The S&D provider
derives eligibility only from its current own-team roster, current connection identities and living bodies,
excluding enemies, dead/disconnected members and unknown JIP/replacement identities. No foreign private store
or timer-based overwrite of a roaming camera is used. This completes an approved privacy rule, not a new mode.

## Domination

Mode `dom` (modes lane, T-2.4; `lua/privatewar/modes/dom.lua`) and module `dom_flags` (`lua/privatewar/modules/dom_flags/`).
Source: `02-modes.md` d.5, d.7; `03-mapdata.md` d.2, d.4, d.6. Lane agent decisions unless a design item is cited.

- `MODE.Base = "tdm"`, `Teams = 2`, `MapData = true`. Inherits the TDM kill scoring, the `timelimit` and `respawndelay`
  settings and the result shape (`PW.MatchRules._Evaluate`, "`PW.MatchResult`"). Kills still score `kill` and
  `headshot`.
- Settings (`match`): `dom.scorelimit` (inherited, default 200, range 10..1000, counts **points**, not kills),
  `dom.capturerate` (float, default 10, 1..100), `dom.tickinterval` (float, default 5, 1..30). `dom.timelimit` and
  `dom.respawndelay` are the TDM declarations.

### Map data

`MAP.Modes.dom = { flags = { A = Vector(...), B = Vector(...), ... } }` (`map.md`): flag letter (any string key) to a bare
`Vector` (`03-mapdata.md` d.2, d.5). `MODE:ValidateMapData(data)` returns `false` and a reason for: no `flags` table
(`Domination needs a flags table`), a key that is not a string or a value that is not a `Vector`
(`flag <key> must be a letter and a Vector`), or fewer than 2 valid flags (`Domination needs at least 2 flags`);
otherwise `true`. `dom._ParseFlags(data) -> { letter, pos }[]` (pure) returns the valid flags sorted by letter.
The mode is offered on a map only when `PW.Map.ModeFits` accepts the data (`map.md`).

### Capture math

One signed scalar per flag in `[-100, 100]`: `+100` is team 1, `-100` is team 2 (`dom._Step`, `dom._Owner`, pure):

- `dom._Step(value, plus, minus, rate, dt)`: `plus` and `minus` are the numbers of living players of team 1 and
  team 2 inside the flag. With `diff = plus - minus`, the value moves by `sign(diff) * rate * min(|diff|, 3) * dt` and is
  clamped to `[-100, 100]`. It does not move when `diff` is 0 (contested, or nobody inside); it never decays.
- `dom._Owner(value, owner)`: `1` when `value >= 100`, `2` when `value <= -100`, else the old owner. A flag starts
  at value 0 with owner 0 (nobody); the owner changes only at the far end, so a flag under attack keeps scoring for
  its owner until it is lost, and it never becomes neutral again.
- The capture step runs every `dom.StepEvery` (0.2) seconds in `MODE:Think` over every flag, with `dt` the real time since the
  last step. `rate` is `dom.capturerate`.
- Owner change: the score event `dom_capture` is awarded to every living player of the new owner team inside the
  flag at that step; the flag entity's network vars are updated.
- Points: every `dom.tickinterval` seconds (at least 1) each flag with an owner adds `dom.TickPoints` (1) to the
  owner team's score (`dom._Hold`, pure). The score limit and the standings use these points
  (`dom._Standings`).

### Presence (module `dom_flags`)

`PW.DomFlags` (shared; `nil` without the module): `Class = "pw_dom_flag"`, `Radius = 160`, `Above = 128`, `Below = 64`.
A player is inside a flag when the horizontal distance to the flag is at most `Radius` and the height difference is
between `-Below` and `+Above` (`_Inside`, a cylinder). Only living players that are not observers count
(`_Infos(players)`). `_Presence(points, infos)` returns, per point, `counts` and `members` by team index. It is one pass over
the player list per capture step: no `ents.Find*` and no triggers.

| Function | Realm | Contract |
| --- | --- | --- |
| `PW.DomFlags.Spawn(letter, pos) -> PW.DomFlag?` | server | Creates the flag entity at `pos` with letter, value 0, owner 0 |
| `PW.DomFlags.RemoveAll()` | server | Removes every flag (called by `MODE:Cleanup`) |
| `PW.DomFlags.GetAll() -> PW.DomFlag[]` | shared | The valid flags (server: spawned; client: networked) |

The entity `pw_dom_flag` (`base_anim`, not spawnable): not solid, `EF_NODRAW`, `TRANSMIT_ALWAYS`. Network vars:
String `Letter`, Float `Value` (the scalar), Int `OwnerTeam` (0 or the team index), Bool `Contested`. The client draws a glow and
the letter above the flag in the owner team colour (white when nobody holds it); the HUD element is described in `ui.md`,
"Domination points".

`Contested` (T-6.5, set by the presence pass through `SetContested(dom._Contested(plus, minus))`): true while both teams
have living players inside the flag and their counts are equal (`dom._Contested`, pure: `plus > 0 and plus == minus`).
The scalar does not move in that state. It is false when the flag is empty or one side is ahead.

### Published values

| Key | Kind | Meaning |
| --- | --- | --- |
| `pw_dom_score_<team>` | global NW2 Int | The team's points; `dom.GetScore(index)` (shared) reads it. Written at `Start` (0), on every point tick that changed a score and at `Cleanup` (0) |
| `pw_mode_ends` | global NW2 Float | As in TDM: the time-limit end, `-1` without one |

## Kill Confirmed

Mode `kc` (modes lane, T-2.5; `lua/privatewar/modes/kc.lua`) and module `kc_tags` (`lua/privatewar/modules/kc_tags/`).
Source: `02-modes.md` d.5, d.7; `01-extensibility.md` d.17. Lane agent decisions unless a design item is cited.

- `MODE.Base = "tdm"`, `Teams = 2`; no `MapData`. Settings (`match`): `kc.scorelimit` (inherited, default 65, counts
  **confirms**), `kc.taglifetime` (int, default 0, 0..300 seconds; `0` means until picked up or the match ends).
  `kc.timelimit` and `kc.respawndelay` are the TDM declarations.
- Every death drops a tag: `MODE:PW_PlayerKilled` first runs `PW.MatchRules.ScoreKill` (the kill still scores `kill`
  and `headshot` but does not count toward the limit), then `PW.KCTags.Drop(victim, kc.taglifetime)`. This happens for
  every death, a suicide or a teamkill included.
- `MODE:PW_KCTagCollected(collector, victim, verdict)` (the notification in "Hooks") counts the pickup: a `"confirm"` adds 1
  to the confirms of the collector's team (team index `1..N`, else none) and awards `kc_confirm` to the collector; a
  `"deny"` awards `kc_deny` and changes no confirm. The confirm count is kept in `kc._Confirms` and published.
- The result and the end check are TDM's (`PW.MatchRules._Evaluate` over `kc._Standings(confirms, teamCount)`):
  score limit by confirms, then time limit; a shared top score is a draw.
- `MODE:Cleanup` removes every tag and resets the values.
- Pure helpers: `kc._Apply(confirms, verdict, index) -> eventId`, `kc._TeamIndex(teamId, n)`, `kc._Standings`.
- Published: global NW2 Int `pw_kc_confirms_<team>` (`kc.GetConfirms(index)`, shared; written at `Start` (0), on every
  confirm and at `Cleanup` (0)) and the match-end global `pw_mode_ends` as in TDM.

### Tags (module `kc_tags`)

`PW.KCTags` (shared; `nil` without the module). The module knows nothing about scoring: a pickup fires
`PW_KCTagCollected` and the active mode scores there.

| Field or function | Realm | Contract |
| --- | --- | --- |
| `Class = "pw_kc_tag"`, `MaxTags = 64`, `GroundTrace = 256`, `Mins = Vector(-20, -20, 0)`, `Maxs = Vector(20, 20, 48)` | shared | Gameplay values: entity class, the most tags alive at once, the distance below the victim the tag is snapped to the ground, the pickup box |
| `Spawn(pos, victim, lifetime) -> PW.KCTag?` | server | Creates a tag at `pos`; with `MaxTags` alive the oldest is removed first; `lifetime` 0 = no expiry. `nil` when the entity could not be created |
| `Drop(victim, lifetime) -> PW.KCTag?` | server | `Spawn` at the ground under the dead player (a brush trace down `GroundTrace`, else the player position) |
| `RemoveAll()` | server | Removes every tag |
| `GetAll() -> PW.KCTag[]` | shared | The valid tags, oldest first (server: spawned and not collected; client: networked) |

The pure rules `_Verdict(info)`, `_ExpireAt(now, lifetime)`, `_Expired(at, now)` and `_Evict(count, max)` are internal.

The entity `pw_kc_tag` (`base_anim`, not spawnable): a trigger (`SetTrigger`, not solid), `EF_NODRAW`, `TRANSMIT_ALWAYS`.
Network vars: Entity `Victim`, Float `ExpireAt` (`CurTime()`, 0 = never). The client draws a bobbing glow: gold for an
enemy's tag (a pickup confirms), blue for a teammate's or one's own (a pickup denies).

Pickup (server, on the engine's touch; the toucher is always checked, never trusted):

1. The tag is already collected: nothing. The victim entity is gone (left the server): the tag is removed without a
   verdict.
2. The toucher must be a valid player, alive and not an observer; anything else picks nothing up.
3. The verdict is `"confirm"` when `PW.IsEnemy(toucher, victim)`, else `"deny"` (a teammate, or the victim).
4. The tag is marked collected, removed, and then the notification `PW_KCTagCollected(collector, victim, verdict)` fires.

A tag with a lifetime removes itself at its expiry time (its own think is scheduled at that time; a tag without a
lifetime never thinks).

## Playlists

Kind `playlists/`, class table `PLAYLIST`, data only (`02-modes.md` d.2; `01-extensibility.md` d.12 table). Modes
lane, T-2.6. The kind declaration is `lua/privatewar/kinds/playlists.lua` (`Global = "PLAYLIST"`, `Subscribe = "never"`,
`Required = { Name = "string", Modes = "table" }`; `Maps` and `Settings` are optional). The per-entry enable ConVar
`pw_playlist_<id>_enabled` follows from `Global` (`core.md` "Enable ConVars"); a disabled Lua playlist is not listed.
The module `playlists` (`lua/privatewar/modules/playlists/`) validates the rest, because it needs the settings schema
and the modes registry.

```lua
-- lua/privatewar/playlists/shipment_247.lua
PLAYLIST.Name  = "Shipment 24/7"
PLAYLIST.Modes = { tdm = 1, dom = 1, kc = 1 }       -- mode id -> weight
PLAYLIST.Maps  = { "pw_shipment" }                  -- map pool; nil = every map that supports the mode
PLAYLIST.Settings = {                               -- match-scope overrides, full setting ids
    ["tdm.scorelimit"] = 100,
    ["bots.fill"]      = 24,
}
```

| Field | Type | Meaning | Source |
| --- | --- | --- | --- |
| `Name` | string | Display name | `02-modes.md` d.2 |
| `Modes` | `table<string, number>` | Mode id to weight; the vote and the start sample by weight | `02-modes.md` d.2 |
| `Maps` | `string[]?` | Map pool. `nil`: the curated map list (`PW.MapList.GetList`, `map.md`), filtered to the maps that fit each mode | `02-modes.md` d.2; `03-mapdata.md` d.6, d.9 |
| `Settings` | `table<string, any>` | Match-scope overrides by **full** setting id (`tdm.scorelimit`, `bots.fill`) | `02-modes.md` d.2, d.5a |

- A preset is a playlist with one mode (Hardcore TDM: `Modes = { tdm = 1 }`, `Settings = { ["health.hardcore"] = true }`);
  there is no separate preset concept (`02-modes.md` d.2).
- No player-count field and no vote-size field: the number of players is `bots.fill` in `Settings`, the vote size is
  the `server` setting `vote.options` (`02-modes.md` d.5a, d.5b).
- `maxplayers` cannot be changed from Lua: a playlist's player count is "fill with bots up to N". If the server has
  fewer slots, the lobby warns ("`<name>` expects `<fill>` players, the server has `<maxplayers>`"; `PW.Playlist._Items`)
  (`02-modes.md` d.4).
- Shipped playlists (`lua/privatewar/playlists/`, on `gm_construct` and `gm_flatgrass`): `free_for_all` ("Free for all",
  `ffa`, `bots.fill = 8`, `ffa.scorelimit = 25`) and `tdm_ffa` ("TDM & FFA", `tdm` and `ffa` at weight 1,
  `bots.fill = 12`).

### Validation

`PW.Playlist.Normalize(raw, facts?) -> PW.PlaylistData?, string?` is the one validation of a playlist, Lua file and JSON
alike (`02-modes.md` d.3: same fields, same validation). On the first problem it returns `nil` and a message. `facts`
(`PW.PlaylistFacts`: known mode ids, the settings index, the validator) is filled by the server; without a field the
matching check is skipped. The result is a clean copy (`Name`, `Modes`, `Maps`, `Settings`; `Settings` is `{}` when absent).

| Field | Rule |
| --- | --- |
| `Name` | A non-empty string of at most 64 characters |
| `Modes` | A non-empty table. Every key is a mode id (lowercase letters, digits, `_`) and, with `facts.modes`, a known mode (`Modes: unknown mode <id>`). Every weight is a finite number above 0 |
| `Maps` | `nil` (the key is missing), else a non-empty list of map names (1 to 64 letters, digits, `_` and `-`). An empty list is an error: leave the key out for "every map that fits". Not a list: an error |
| `Settings` | `nil` gives `{}`. Else every key is a full id `owner.key` (lowercase letters, digits, `_`), the value is not `nil`, the setting exists, its scope is `match` (`server` and `client` settings are rejected) and the value passes `PW.Settings._Validate`; the stored value is the validated and clamped one |

### Host-saved playlists (JSON)

`data/privatewar/playlists/<id>.json` (`PW.Playlist.DataDir = "privatewar/playlists"`), read next to the Lua playlists
(`02-modes.md` d.3). The id is the file name without `.json`: lowercase letters, digits and `_`, at most 64 characters
(`PW.Playlist.FileId(fileName)` returns it, else `nil`; a file with another name is rejected with a log line).

```json
{ "Version": 1, "Name": "My match", "Modes": { "tdm": 1 }, "Maps": ["gm_construct"], "Settings": { "tdm.scorelimit": 50 } }
```

- Format version: `PW.Playlist.Version = 1`. `Version` is optional on reading and must equal 1 when present; `ToJson` always
  writes it.
- `PW.Playlist.FromJson(text, facts?) -> PW.PlaylistData?, string?`: rejects an empty text, text that does not parse,
  a top level that is not an object, an unsupported `Version` and any key other than `Version`, `Name`, `Modes`, `Maps`
  and `Settings` (`unknown field <key>`); then runs `Normalize`. The messages of the first three start with
  `invalid JSON:` (`TASKS.md` T-2.6, mandatory case).
- `PW.Playlist.ToJson(data) -> string` writes `Version`, `Name`, `Modes`, `Maps`, `Settings` as pretty JSON.
- `PW.Playlist.Save(id, data, dir?) -> boolean, string?` (server): validates the id (the file name rule above) and
  the data, creates the folder and writes `<id>.json`; returns `false` and the reason otherwise. No lobby control calls it
  yet ("Save as..." of `02-modes.md` d.3 is not in the UI).
- A rejected file is skipped with one log line (`playlist file <dir>/<name> rejected: <reason>`); `LoadDir` also returns
  the list of rejections.

### Custom

The host picks one mode and one map and edits Game Setup by hand (`02-modes.md` d.1). Custom is the lobby row `@custom`
(`PW.Playlist.CustomRow`) and the state "no active playlist" (`pw_playlist_active` empty). The lobby shows the playlist
list and the generated Game Setup form (`ui.md`). A mode with `MapData = true` is offered on a map only if the map data
is valid (`map.md`, `PW.Map.ModeFits`).

### `PW.Playlist` (module `playlists`)

Shared unless stated. Types: `lua/privatewar/types/playlists.lua`.

| Function | Realm | Contract |
| --- | --- | --- |
| `Version`, `DataDir`, `Privilege`, `CustomRow` | shared | Constants: `1`, `"privatewar/playlists"`, `"pw.match.start"`, `"@custom"` |
| `Normalize`, `FromJson`, `ToJson`, `FileId` | shared | See "Validation" and "Host-saved playlists" |
| `PickWeighted(weights, rng) -> string?` | shared | Pure. Samples a key of `table<string, number>` by weight over a sorted id list; keys with a weight at or below 0 are ignored; `nil` for none. `rng()` returns a number in `[0, 1)` |
| `Sample(data, opts) -> PW.PlaylistPick?, string?` | shared | Pure. `opts = { rng, maps?, fits? }`: the pool is `data.Maps`, else `opts.maps`, filtered by `fits(mode, map)`. A mode with no fitting map is dropped; the mode is picked by weight, then the map uniformly. `nil` and `no mode of the playlist is offered on any map` when nothing is left. Returns `{ mode, map }` |
| `GetList() -> PW.PlaylistEntry[]` | server | The enabled Lua playlists (`PW.Playlists` registry, id = file name) plus the JSON ones (`LoadDir`), each validated; an invalid Lua playlist is skipped with a log line. A JSON file whose id equals a Lua playlist is skipped (the Lua one wins). Sorted by `Name`, then id. An entry is `{ id, source = "lua" or "json", Name, Modes, Maps, Settings }` |
| `Get(id) -> PW.PlaylistEntry?` | server | One entry of `GetList` |
| `LoadDir(dir?) -> PW.PlaylistEntry[], PW.PlaylistFileError[]` | server | The JSON playlists of a folder under `data/` and the rejected files |
| `Save(id, data, dir?)` | server | See "Host-saved playlists" |
| `Pick(id) -> PW.PlaylistPick?, string?` | server | `Sample` over the playlist with the real pool (`PW.MapList.GetList()`) and the real fits test |
| `GetActive() -> string`, `SetActive(id)` | server | The ConVar `pw_playlist_active` (below); `""` is Custom |
| `Start(id) -> boolean, string?` | server | Starts the playlist (below) |
| `GetState() -> PW.PlaylistListState?`, `Request()`, `SendPick(id)`, `SendStart(id)`, `OnChange` | client | The last list the server sent; the three client messages; a callback the lobby sets |

The fits test of the server: the map is installed (`maps/<map>.bsp` in `GAME`), the mode is in
`PW.Modes.GetEnabledList()`, and a mode with `MapData = true` passes `PW.Map.ModeFits` (`map.md`).

`PW.Playlist.Start(id)`:

1. Refused with `navmesh generation running` while `PW.NavGen.IsGenerating()` (`map.md`).
2. Refused for an unknown id, or when `Sample` finds nothing.
3. Every entry of `Settings` is applied through `PW.Settings.Set(fullId, value)` (a pending `match` value); a value that is
   not accepted is logged and skipped.
4. The playlist becomes active (`SetActive(id)`), one log line `playlist <id> starts <mode> on <map>`, then
   `PW.Match.Start(mode, map)` (`core.md`; another map goes through "Map change").

ConVar `pw_playlist_active` (server, `FCVAR_ARCHIVE`, default `""`): the id of the active playlist, `""` for Custom. It is
archived because a match start may change the map. An id the list no longer knows is shown as Custom. The vote
samples from the active playlist (see "Vote module").

### Net messages (module `playlists`)

Client to server, all through `PW.Net.Receive`; the module owns them (dropped while it is disabled):

| Message | Who | Phases | Rate | maxLen | Payload |
| --- | --- | --- | --- | --- | --- |
| `pw_playlist_request` | any | `LOBBY`, `PREMATCH` | 4 per s | 16 bytes | none; answered with `pw_playlist_list` to the caller |
| `pw_playlist_pick` | `pw.match.start` | `LOBBY` | 4 per s | 256 bytes | `WriteString(id)`, `""` = Custom. An unknown id is refused with a log line. Sets `pw_playlist_active` and answers the caller with `pw_playlist_list`; other players are not updated |
| `pw_playlist_start` | `pw.match.start` | `LOBBY` | 2 per s | 256 bytes | `WriteString(id)`; `PW.Playlist.Start(id)`. A refusal is logged |

The module declares the privilege `pw.match.start` with default `superadmin` (the same name as the lobby's start
privilege, `ui.md`).

Server to client `pw_playlist_list` (explicit writes, no `net.WriteTable`), in this order:

1. `WriteUInt(n, 8)` (capped at 255), then per playlist `WriteString(id)`, `WriteString(name)`, `WriteString(summary)`,
   `WriteUInt(fill, 8)`. `summary` is `"<mode ids by id> on <N maps | 1 map | all maps>"`; `fill` is the playlist's
   `bots.fill`, 0 when it sets none, clamped to 0..255.
2. `WriteString(active)`: the active id, `""` for Custom.
3. `WriteBool(canPick)`: `pw.match.start` of the receiver.

### `bots.fill` and `bots.difficulty` (module `bots`)

Module `bots` (`lua/privatewar/modules/bots/shared.lua`) is a placeholder: it declares the match settings and has no bot
code. Decided (`02-modes.md` d.5a and `07-bots.md` d.3, clarified with the user on 2026-11-07): one module `bots` owns the
bot settings (full id `<owner>.<key>`); the `bots_*` modules of `07-bots.md` d.3 are its sub-modules.

| Full id | Scope | Type | Default | Range or options | Meaning |
| --- | --- | --- | --- | --- | --- |
| `bots.fill` | `match` | int | 12 | 0..128 | Fill with bots up to N players in total, humans included, capped by `maxplayers` (`02-modes.md` d.5a) |
| `bots.difficulty` | `match` | enum | `regular` | `recruit`, `regular`, `hardened`, `veteran` | The bot difficulty tier (`07-bots.md` d.10, d.15). The option list is fixed here; the tiers will be a data kind `bot_difficulties` (`07-bots.md` d.10) and the list will then have to come from it |

## Vote module

Module `vote` (modes lane, T-2.13; `lua/privatewar/modules/vote/`). Source: `00-core.md` d.2, d.5; `02-modes.md` d.2, d.5b;
`08-lobby.md` d.5. Types: `lua/privatewar/types/vote.lua`. Lane agent decisions unless a design item is cited.

Rules (`08-lobby.md` d.5, `TASKS.md` T-2.13, mandatory cases):

- The vote runs in the `VOTE` phase, which exists only with the host setting "rotation with vote" (`pw_aftermatch
  rotation`, `00-core.md` d.2; `core.md` "Phases and match"). Entering `VOTE` opens a session (when the active mode is
  one of the real `modes` registry); leaving it closes the session.
- Options are map and mode pairs. The source is the active playlist (`pw_playlist_active`): its `Modes` with weights and its
  `Maps`, or the curated map list (`PW.MapList.GetList`) when `Maps = nil`. **In Custom** (no active playlist) the
  only mode is the mode of the match that just ended, on the curated map list. A pair is a candidate only if
  the playlists module's fits test accepts it (installed map, enabled mode, `MapData` rule, `03-mapdata.md` d.6).
- The number of options is `vote.options` (default 3, `02-modes.md` d.5b). Fewer are offered when fewer pairs exist; the
  options are distinct pairs. If there are none, the session is not opened (one log line `vote: nothing to offer, the same
  mode repeats`) and the core repeats the mode (`PW_NextMatch` answers `nil`).
- The vote lasts `pw_vote_time` (15 s default, `core.md` "ConVars"). A tie (also no votes at all) is broken at random among
  the tied options (`00-core.md` d.5).
- The vote ends early when every human has voted (at least one human). Bots never vote (`08-lobby.md` d.5).
- A player may change the vote until the vote ends; the new vote replaces the previous one. A player who disconnects
  loses the vote. Everyone sees the number of votes per option and the own vote; who voted for what is not sent
  (`08-lobby.md` d.5).
- Recent maps: the maps of the last 2 matches (`PW.Vote.RecentCount`) are excluded when the candidates cover at least 3
  distinct fitting maps; below that the rule switches itself off (`08-lobby.md` d.5). The list is the archived ConVar
  `pw_vote_recent` (comma-separated map names, newest first); the map of every match that goes `PREMATCH` to `LIVE` is
  pushed to it, so it survives the map change and a restart.
- "Same map and mode again" is not offered unless `vote.allowrepeat` is on (`08-lobby.md` d.5).
- Weights: the weight of a mode is shared among its allowed maps, so every mode keeps its playlist weight whatever the
  number of its maps. Options are drawn without replacement. When the exclusions leave nothing, the recent-maps rule and
  then the repeat rule are dropped, in that order.
- The host may skip the vote with "Pick myself" (privilege `pw.vote.pick`, `00-core.md` d.7): the pick ends the vote at
  once and is the next match (`08-lobby.md` d.5).
- A mode with `MapData = true` is a candidate on a map only if the map data is valid (`03-mapdata.md` d.6).

### How the vote hands the next match to the core

The vote module answers the question hook `PW_NextMatch(mode)` (`core.md` "Hooks") with a module method: the host's pick,
else the winner of the tally, as `{ mode = <mode entity>, map = <string> }` (`PW.NextMatch`). The result is decided once
per session. When the mode is no longer a registered mode the answer is `nil` and the same mode repeats. The core starts
the answer through its usual path, including a map change (`core.md` "Phases and match"). The vote ends early through
`PW.Match.EndVote()`.

### `PW.Vote` API

Types in `lua/privatewar/types/vote.lua`. Pure functions are shared; server functions need the module's server part.

| Function | Realm | Contract |
| --- | --- | --- |
| `Privilege`, `RecentCount` | shared | `"pw.vote.pick"`, `2` |
| `Candidates(input) -> PW.VoteOption[]` | shared | Pure. `input = { modes, maps, fits?, recent, current?, allowRepeat, count, rng }`; the rules above |
| `PushRecent(list, map)`, `FormatRecent(list)`, `ParseRecent(text)` | shared | Pure. The recent list (newest first, no duplicates, at most 2) and its ConVar text; invalid names are skipped |
| `NewSession(options)`, `Cast(session, voter, isBot, index)`, `Tally(votes, count)`, `Winner(counts, rng)`, `Humans(players)`, `AllVoted(humans, votes)` | shared | Pure. `Cast` returns `false` and `"bot"`, `"ended"` or `"index"` when refused |
| `Open() -> PW.VoteSession?`, `Close()`, `Result() -> PW.NextMatch?` | server | Open the session and send the state to every human, close it, the decided next match |
| `SendVote(index)`, `SendPick(option)`, `Request()`, `Open()`, `Close()` | client | The three messages and the vote screen (`ui.md`) |

Server internals `_Cast`, `_Pick`, `_Played`, `_SendState`, `_RegisterNet`, `_NewStore`, and the pure `_Encode`, `_Decode`, `_Model` are
not contract. A vote through `_Cast` ends the session when `AllVoted`; `PW.Match.EndVote` is the store's `endVote`.

### Net messages (module `vote`)

Client to server, all through `PW.Net.Receive`, phase `VOTE`; the module owns them:

| Message | Who | Rate | maxLen | Payload |
| --- | --- | --- | --- | --- |
| `pw_vote_cast` | any (bots are refused by `Cast`) | 4 per s | 4 bytes | `WriteUInt(index, 8)`, the 1-based index of the option |
| `pw_vote_pick` | `pw.vote.pick` | 2 per s | 160 bytes | `WriteString(mode id)`, `WriteString(map)`. The mode must be an enabled mode and the pair must fit (installed map, `MapData` rule); the pair need not be one of the options. A refusal is logged |
| `pw_vote_request` | any | 2 per s | 8 bytes | none; answered with `pw_vote_state` to the caller |

After an accepted `pw_vote_cast`, and when the session opens, the server sends `pw_vote_state` to every human.
`pw_vote_state` (server to client), in this order: `WriteUInt(n, 8)`, then per option `WriteString(mode id)`,
`WriteString(mode display name)`, `WriteString(map)`, `WriteUInt(votes, 8)` (clamped 0..255); then `WriteUInt(mine, 8)` (the
receiver's own option, 0 for none) and `WriteBool(canPick)` (`pw.vote.pick` of the receiver).

The privilege `pw.vote.pick` is declared by the module with default `superadmin`.

### Settings

Both are `server` settings (ConVars `pw_vote_options` and `pw_vote_allowrepeat`, replicated and archived, `core.md`
"Settings"):

| Full id | Scope | Type | Default | Range | Source |
| --- | --- | --- | --- | --- | --- |
| `vote.options` | `server` | int | 3 | 1..8 | `02-modes.md` d.5b |
| `vote.allowrepeat` | `server` | bool | `false` | | `08-lobby.md` d.5 |

ConVar `pw_vote_recent` (server, `FCVAR_ARCHIVE`, default `""`): see "Rules".

## Join in progress (module `lobby`)

Module `lobby` (`lua/privatewar/modules/lobby/`: `shared.lua` the pure decision, `init.lua` the server glue; T-8.4;
`design/08-lobby.md` d.4). The module is named `lobby` only so that its setting has the id the design gives it,
`lobby.joininprogress`; the lobby screens are the module `lobby_ui` (`ui.md`). Global `PW.Jip` (shared).

Setting `lobby.joininprogress`: scope `server`, bool, default `true`, label `Join in progress`.

- On (default): a human joining during `LIVE` plays. The teams module places the player in the smaller team on spawn
  (`teams.md` "Late join") and the bots manager kicks a bot of that team (`bots-blackboard.md`).
- Off: the human spectates until the next match. The player is remembered in the store, put on `TEAM_SPECTATOR` with no
  weapons and no bot targeting (`SetNoTarget(true)`), in roaming observer mode only (`OBS_MODE_ROAMING`; no chase view),
  and the NW2 bool `pw_spectating` of the player is set. A bot never counts as a spectator.

| Name | Realm | Contract |
| --- | --- | --- |
| `PW.Jip.NetBool` | shared | `"pw_spectating"`: the NW2 bool of the player that is `true` while the server holds the player out of the match. Read it with `Player:GetNW2Bool(PW.Jip.NetBool, false)` |
| `PW.Jip.Notice` | shared | The HUD notice text, `Spectating — you join next match` |
| `PW.Jip._Decide(facts) -> "normal"\|"play"\|"spectate"` | shared | Pure. `facts = { phase, enabled, human }`: `"normal"` outside `LIVE`; `"spectate"` for a human with the setting off during `LIVE`; otherwise `"play"` |
| `PW.Jip._ReleasesOn(phase) -> boolean` | shared | Pure. `true` for `LOBBY` and `PREMATCH` |
| `PW.Jip._Unspawns(phase, oldPhase?) -> boolean` | shared | Pure (T-11.10). `true` when entering `LOBBY` from a match phase; `false` for the first lobby (no old phase) and every other phase |

Server behaviour (hooks of the module, through `PW.HookFor`):

- `PlayerInitialSpawn`: `_Decide`; on `"spectate"` the player is stored and `pw_spectating` is set.
- `PlayerSpawn`: a stored player is parked one tick later (after the other `PlayerSpawn` listeners; the teams module
  would otherwise have placed the player).
- `PW_CanRespawn(ply)`: `false` for a stored player, so a round or respawn rule never brings the player in.
- `PW_PhaseChange`: entering `LOBBY` or `PREMATCH` releases every spectator (team reset, `UnSpectate`, targeting back,
  `pw_spectating` cleared), so the next match starts with them as normal players. Entering `LOBBY` from a match also
  unspawns every player, bots included, one tick later (T-11.10, `design/08-lobby.md` d.3 "players are not spawned
  during `LOBBY`"): `SetTeam(TEAM_UNASSIGNED)`, then `Spawn()`, so the base gamemode makes a spectator with no model
  and no weapons, the same state as the first lobby after the map loads.
- Consumers of the flag: the teams module (`_PlaceLate` skips them, `teams.md`), the bots manager (not a human of the
  quota) and the HUD element `spectating` (`ui.md`).

Internal: `PW._Jip` (the store with injectable engine calls, including `players` and `unspawn`), `_NewStore`, `_OnJoin`,
`_OnSpawn`, `_CanRespawn`, `_OnPhase`, `_OnLobby`.

## Settings that belong to the modes lane

Cited by the design with their full ids; the declarations (min, max, labels) live in the mode and module files.

| Full id | Scope | Source |
| --- | --- | --- |
| `tdm.scorelimit` (int, default 75, 10..1000, counts kills), `tdm.timelimit` (int, default 600, 0..3600, `0` = none), `tdm.respawndelay` (float, default 3, 0..30) | `match` | `01-extensibility.md` d.17 (example); T-2.2 |
| `ffa.scorelimit`: inherits from `tdm` and sets the default to 30 (range 10..1000); `ffa.timelimit` and `ffa.respawndelay` inherit the `tdm` declarations | `match` | T-2.2 |
| `<mode id>.roundtime` (int, default 120, 0..600, `0` = none), `<mode id>.intermission` (float, default 5, 1..30) of the children of `round_base` | `match` | T-2.3 |
| `kc.scorelimit`: inherits and sets the default to 65 (counts confirms); `kc.taglifetime` (int, default 0, 0..300, `0` = until picked up or the match ends) | `match` | `01-extensibility.md` d.17; T-2.5 |
| `dom.scorelimit`: inherits and sets the default to 200 (counts points); `dom.capturerate` (float, default 10, 1..100), `dom.tickinterval` (float, default 5, 1..30) | `match` | T-2.4 |
| `vote.options` (int, default 3, 1..8), `vote.allowrepeat` (bool, default `false`) | `server` | see "Vote module" |
| `lobby.joininprogress` (bool, default `true`) | `server` | `08-lobby.md` d.4; T-8.4; see "Join in progress" |
| `bots.fill` (int, default 12, 0..128), `bots.difficulty` (enum `recruit`, `regular`, `hardened`, `veteran`, default `regular`) | `match` | `02-modes.md` d.5a; see "Playlists" |

The settings of FFA beyond these are the mode's own data (not a cross-lane contract). The capture math of Domination
is in "Domination" (`TASKS.md` T-2.4: `rate × min(diff, 3)`, the limit `±100`; the rate is `dom.capturerate`).

## Core changes needed

1. **Kind declaration files** in `lua/privatewar/kinds/` (the core lane's directory, `TASKS.md` "Lanes and
   ownership"): `playlists.lua` (`Folder = "playlists"`, `Global = "PLAYLIST"`) and `score_events.lua`
   (`Folder = "score_events"`, `Global = "EVENT"`). `Subscribe` can stay omitted (`"never"`): both are data. The
   `Required` lists: `score_events` `Name` and `Points` (item 1b), `playlists` `Name` and `Modes`. The orchestrator adds the files before the lane starts T-2.1 / T-2.6.
   Enable ConVars follow from `Global`: `pw_playlist_<id>_enabled`, `pw_event_<id>_enabled`
   (`01-extensibility.md` d.11; `core.md` "Enable ConVars"). Done: both files exist; `playlists.lua` requires
   `Name` and `Modes` ("Playlists").
2. **`KIND.Required` is checked before `Base` resolution** (`sh_loader.lua`, `loadEntity`, `core.md` "Entity
   files"). A mode that inherits `Name` or `Teams` from its base is rejected by the loader, although
   `00-core.md` d.4 says a round mode "only sets parameters". Either the loader checks after `Base`
   resolution, or every child repeats the required fields. Decided: `KIND.Required` will be validated after `Base`
   resolution (wave 0).
3. ~~A team swap function~~ Done: `PW.Teams.Swap` (`teams.md`).
4. ~~**VOTE hand-over.**~~ Done (T-2.13): the core asks the question hook `PW_NextMatch(mode)` at the end of `VOTE` and
   starts the answer through its usual path, including a map change; `PW.Match.EndVote()` ends `VOTE` early. See
   "Vote module" and `core.md` "Phases and match". "Pick myself" is the privilege `pw.vote.pick` and the message
   `pw_vote_pick`.
5. **Entity ids.** Core ids are lowercase letters, digits and `_` (`core.md` "Entity files"); relevant for map
   files (`map.md`), not for modes.

## Open in design

Nothing here is invented. Each item says what is missing and which task it blocks.

- **Details are decided by the lane agent.** The API details and defaults listed here (names, return types, event
  points, thresholds, magazine counts) are decided by the lane agent of each task. The agent documents them and
  reports them; the orchestrator writes them into this contract after the merge. Only gameplay-changing choices go
  to the user.

1. **Score event ids and ownership.** (a) Partly decided: `dom_capture`, `kc_confirm` and `kc_deny` exist (T-2.4, T-2.5),
   see "Score module". Still open: the ids of the other MVP events (assist, match win, medals): `06-progression.md`
   d.3 names them in prose. Blocks the progression lane. ~~(b) The `Required` list of the kind~~
   decided: `Name`, `Points`. ~~(c) Who writes the event files~~ decided for `kill` and `headshot` (T-2.1 wrote
   them); the other files belong to the lane that awards them.
2. ~~**Score API details.**~~ Decided (lane agent, T-2.1), see "`PW.Score.Award`" and "Hooks": return value
   `true, points, xp`; `PW_ScoreValue` never changes an explicit `XP`; order score, `PW_ScoreEvent`,
   `PW_ScoreChanged`; arguments of `PW_ScoreChanged`; reading with `PW.Score.Get` and `GetTeam`.
3. ~~**`result` of `PW.Match.Finish(result)`**~~ Decided (lane agent, T-2.2), see "`PW.MatchResult`".
4. ~~**Playlist `Required` list** and the enable ConVar use.~~ Decided (lane agent, T-2.6): `Required = { Name, Modes }`,
   the enable ConVar `pw_playlist_<id>_enabled` hides a Lua playlist; see "Playlists".
5. ~~**Arguments of `PW_RoundStart` / `PW_RoundEnd`**~~ Decided (lane agent, T-2.3), see "Hooks".
6. ~~**`round_base` details.**~~ Decided (lane agent, T-2.3), see "`round_base`" (`SwapSidesEvery`, end conditions)
   and `PW.Teams.Swap` in `teams.md`.
7. ~~**Playlist loader surface.**~~ Decided (lane agent, T-2.6): `PW.Playlist` functions, the file name rule, `Version = 1`
   and the validation rules; see "Playlists".
8. ~~**Who fires `PW_PlayerKilled`** and `PW_CanRespawn` / `PW_RespawnDelay` and who respawns players~~ Decided
   (lane agent, T-2.2): the `match_rules` module, see "Match rules module".
9. ~~**Return type of `PW_SelectSpawn`**~~ Decided (lane agent, T-2.2, T-2.9): an entity or `{ pos, yaw? }`, see
   "Hooks".
10. ~~Owner of module id `bots`~~ Closed: one module `bots` owns the bot settings, the `bots_*` modules are its
    sub-modules (`02-modes.md` d.5a, `07-bots.md` d.3).
11. **Types of `MODE.Description` and `MODE.Icon`** (string localisation key, material path). Does not block. The code
    today: every mode file sets `Description` to a plain English string (not a localisation key); no file sets `Icon`;
    nothing reads either yet. Not decided.
12. **FFA and `BotObjectives(team)`**: the argument for `Teams = 0` and the empty answer (`nil` or `{}`). Does not
    block (no FFA objectives in MVP); blocks bots lane P5 detail.
13. **`PW_CanPickup`**: arguments and who fires it (named only in `01-extensibility.md` d.9). Does not block P2;
    blocks the weapons or loadout lane if they use it.
14. ~~**Vote module surface.**~~ Decided (lane agent, T-2.13): the functions, the net messages, `vote.allowrepeat` off by
    default, and the candidates in Custom (the mode of the match that just ended on the curated map list); see "Vote
    module".
