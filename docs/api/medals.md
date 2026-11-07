# Medals module API

Module `medals` (progression lane, T-4.11). Source: `06-progression.md` d.3 (medals are score events with
`Medal = true`; no `medals/` kind). Code: `lua/privatewar/modules/medals/`.

## Medals

Each medal id is also the id of a score event in `lua/privatewar/score_events/`, awarded through `PW.Score.Award`
(match score and XP; no weapon, so medals give no weapon XP).

| Id | Fires when | Points (= XP) |
| --- | --- | --- |
| `first_blood` | the first enemy kill of the match | 100 |
| `double_kill` | the second kill of a chain; each kill at most 4 s after the previous one | 50 |
| `triple_kill` | the third kill of a chain (no `double_kill` on that kill) | 100 |
| `revenge` | killing the enemy who killed you last (once per death) | 50 |
| `streak5` | every fifth kill without dying (5, 10, 15, ...) | 150 |
| `saviour` | killing an enemy who damaged a teammate of yours at most 5 s before the kill | 50 |

Only enemy kills count. Suicides, teamkills and world deaths earn nothing, use up no first blood, and reset the
victim's streak and chain. A kill can earn several medals; they are awarded in the order of the table above
(`first_blood`, `revenge`, `saviour`, then the multi-kill, then `streak5`).

## API

- `PW.Medals.Get(ply) -> { [id] = count }` (server): medals earned this match. A copy; empty table when none. Stays
  readable in `POSTMATCH`; reset when the match goes `LIVE` (from `PREMATCH`) and when the phase becomes `LOBBY`.
  Empty on a client.
- `PW.Medals.Ids`, `PW.Medals.Window` (4), `PW.Medals.SaviourWindow` (5), `PW.Medals.StreakStep` (5).

## Notifications and wire

- Notification `PW_Medal(ply, medalId)` (no return value), after the score award. Fired for bots too.
- Net message `pw_medal`, server to the owner only, humans only: one string, the medal id. The client keeps the last
  one in `PW.Medals.Last = { id, at }`. The HUD popups do not use it: they show medals from `pw_score_popup` (see
  `ui.md`, "Score popups and medals").
