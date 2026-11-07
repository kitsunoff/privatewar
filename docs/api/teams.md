# Teams module API

Status: added after T-1.16 (2026-11-06); extended with `PW.Teams.Swap` after T-2.3 (2026-11-07). The teams module is a module, not core: `lua/privatewar/modules/teams/`
(`shared.lua`, `init.lua`). Types: `lua/privatewar/types/teams.lua`. Source decisions: `design/02-modes.md` d.6,
`design/08-lobby.md` d.4, `design/00-core.md` d.9.

A mode declares `MODE.Teams = N` (`0` = FFA). Teams are indices `1..N`; names and colours are cosmetic defaults
(`Team <i>`, set up in the engine team table on first use).

## Availability

- `PW.Teams` and `PW.IsEnemy` exist only when the module is loaded. If the module is missing they are `nil`:
  callers must check (`if PW.IsEnemy ~= nil then ...`).
- Disabling the module (`pw_module_teams_enabled 0`) does not remove the API, but from the next match it stops
  assigning teams, placing late joiners, publishing `pw_teams` and answering `PW_PendingTeams`.

## Functions

| Function | Realm | Contract |
| --- | --- | --- |
| `PW.Teams.GetActive() -> integer[]` | shared | The list `{ 1, ..., N }` of the current match; empty in FFA and outside a match. The returned table is cached and shared: do not modify it |
| `PW.Teams.Smallest() -> integer?` | shared | The active team with the fewest players (by `Player:Team()` of every player); ties go to the lowest index; `nil` when there are no active teams |
| `PW.Teams.Swap(players?) -> integer` | server | Swaps the sides for round modes (`modes.md` "`round_base`", T-2.3): every player of an active team moves one team along, team `i` to `i + 1` and the last team to `1` (two teams: a plain swap). Players outside `1..N` keep their team. `players` defaults to every connected player (in `UserID` order). Returns how many players changed team. `N` is `#PW.Teams.GetActive()`; with no active teams it moves nobody and returns `0` |
| `PW.IsEnemy(a, b) -> boolean` | shared | Asks the question hook `PW_IsEnemy(a, b)` first; a boolean answer wins (other answers are ignored). Otherwise: the same player is never an enemy; with no active teams (FFA, or outside a match) everyone else is an enemy; else players on different teams are enemies |

Internal, pure: `PW.Teams._SwapMap(n)` is the table team to destination team; `_SwapAssignment(n, assignment)` is a
swapped copy of an assignment (entries outside `1..n` are kept); `_SwapPlayers(n, players)` is `Swap` over `n` teams.

Where `N` comes from:

- Server: `PW.ActiveMode.Teams` (rounded down; not a number or negative → 0). `PW.ActiveMode` is set from
  `PREMATCH` to the return to `LOBBY`, so the server sees `N` during `PREMATCH`, `LIVE`, `POSTMATCH` and `VOTE`.
- Client: the NW2 global `pw_teams` (int). The server writes `N` on `PREMATCH → LIVE` and `0` on entering
  `LOBBY`. Clients therefore see `0` during the first `PREMATCH` and the previous `N` during `POSTMATCH`, `VOTE`
  and a rotation's `PREMATCH`.

## Hooks

| Hook | Type | Arguments | Contract |
| --- | --- | --- | --- |
| `PW_IsEnemy` | question, via `PW.Ask` | `a: Player, b: Player` | Return `true` or `false` to decide; `nil` falls through to the rule. The active mode may define it |

The module also listens to core hooks (auto-subscribed `PW_*` methods): `PW_PhaseChange`,
`PW_PendingMatchApplied`, and answers the core question hook `PW_PendingTeams` (see `core.md`).

## Assignment (server)

- When the phase goes `PREMATCH → LIVE`, in the module's `PW_PhaseChange` listener, so before `MODE:Start`. Then
  `pw_teams` is published.
- Every player (bots included), in `UserID` order, so the result is deterministic.
- Each player's preference: for a human, the team restored from the pending file if there is one, else the
  current `Player:Team()`; for a bot, the current team.
- A preference in `1..N` is kept while the teams can still end balanced (every team ends with `floor(P/N)` or one
  more player); the others fill the smallest team, ties to the lowest index.
- In FFA (`N = 0`) nobody gets a team: players keep whatever team they had.
- The restored preferences are used once: cleared after the assignment and on entering `LOBBY`.

## Late join (server)

- `PlayerSpawn` hook added through `PW.HookFor(MODULE, ...)` (`core.md` "Auto-subscription"; runs before
  `GM:PlayerSpawn`, and stops while the module is disabled): during `LIVE`, with `N > 0` and the
  module enabled, a player whose team is not in `1..N` goes to the smallest team among the other players.
- `PW.Teams._PlaceLate(ply, players) -> integer?` does the placement. It places nobody (returns `nil`) when there are no
  active teams, and **skips a join-in-progress spectator**: a player on `TEAM_SPECTATOR` or with the NW2 bool
  `pw_spectating` set (`modes.md` "Join in progress") stays out of the teams until the next match. The spectator is also
  not counted as a member of a team: it holds no team in `1..N`.
- Note: `GM.TeamBased = true` makes the base `GM:PlayerSpawn` spawn a player without a team as a spectator; in
  FFA the module assigns no team, so FFA spawning is handled by the `match_rules` module: it puts FFA players in the free team
  `PW.MatchRules.FreeTeam` (1000, outside `1..N`) before `GM:PlayerSpawn` (`modes.md` "Match rules module").

## Pending match file (server)

- `PW_PendingTeams(mode)`: team by SteamID64 of the **humans** only, for teams in `1..N` of the target mode
  (`mode.Teams`). Bots are never written. Returns `nil` when the result is empty, so the core writes `{}`.
- The teams are the players' current teams, so a map change from `LOBBY` carries the teams of the last match.
- `PW_PendingMatchApplied(pending)`: restores `pending.teams` (keys of digits, integer teams `>= 1`) as
  preferences for the next assignment.

## Internal

`PW.Teams._TeamCount`, `_Assign`, `_Smallest`, `_Counts`, `_IsEnemyRule`, `_ForFile`, `_FromFile`,
`_AssignPlayers`, `_PlaceLate`, `_NewStore`, `_CountKey` and the state `PW._Teams` are internal
(`design/01-extensibility.md` d.14).
