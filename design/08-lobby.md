# 08 — Lobby and hosting

Status: decided (in-game tests listed under Open questions).

## Goal and scope

Hosting, Steam P2P join, the in-game pre-match lobby, map/mode vote.

## Decisions

- Hosting is player-hosted listen servers with Steam P2P; no backend for the MVP.

1. **MVP = level 0 (zero backend).** The host starts New Game with our gamemode; friends join through Steam "Join Game". The optional lobby directory with lobby codes (level 1 in `../notes/17-lobby-and-join-flow.md`) comes after MVP. Rationale: the primary use case is solo or a few friends vs bots (`../DESIGN.md`, Goal).

2. **Entry hints instead of silent failures.**
   - Singleplayer (`game.SinglePlayer()`): bots cannot be created there (`../notes/17-lobby-and-join-flow.md`, fact 6). Instead of the lobby, one screen explains: "To play with bots: New Game → pick the mode → Max Players 12 or more", with a picture of the menu.
   - P2P off (`p2p_enabled 0`): the lobby shows a hint on how to enable it, for hosts who want to invite friends; it does not block solo play.
   - `maxplayers` below the requested `bots.fill`: a warning (`02-modes.md` decision 4).
   - The addon ships a recommended `.cfg`: `maxplayers 12`, `p2p_enabled 1`, `p2p_friendsonly 1`.

3. **Lobby screen: own operator in the centre (MWR style) and a party list (other CoDs).**

   ```text
   ┌───────────────────────────────────────────────────────────┐
   │ [blurred orbit over the map]                              │
   │                                                           │
   │   PLAYLIST: Shipment 24/7        PARTY (3/12)             │
   │   MAP: Shipment  MODE: TDM       ● Host      Lv 34  READY │
   │                                  ● Friend1   Lv 12        │
   │        ┌─────────┐               ● Friend2   Lv 51  READY │
   │        │ YOUR    │               + 9 bots                 │
   │        │ OPERATOR│                                        │
   │        │ + GUN   │               [GAME SETUP] (host)      │
   │        └─────────┘                                        │
   │   [CLASSES] [STORE] [PROGRESS]   [START] (host)  [READY]  │
   └───────────────────────────────────────────────────────────┘
   ```

   - Players are not spawned during `LOBBY`; the background is a blurred camera orbit over the current map.
   - Centre: the local player's operator (`models/`) holding the primary weapon of the selected class. Rendered only on that client from local data (`classes.json`, `progression.json`); nothing is networked. The same scene is reused by the gunsmith preview (`10-frontend.md`).
   - Right: the party list (name, level, ready, host marker) and a "+N bots" line; bots are not listed individually.
   - Rejected: a squad line-up of every member's operator and weapon. It would require networking every member's cosmetics and attachment builds and assembling other players' weapons with attachments on each client (hard with ARC9/TFA).
   - Everyone: classes and gunsmith, store, progression, ready flag (informational, `00-core.md` decision 5).
   - Host (privileges, `00-core.md` decision 7): playlist or Custom, map and mode, Game Setup, after-match behaviour (lobby or rotation), Start.
   - Screens are built from registries: Game Setup from `Settings` (`01-extensibility.md` decision 17), gunsmith from adapters, store from `bundles/`. A module adds its own screen through the `screens/` kind.
   - Split of responsibility: `08-lobby` decides what the lobby contains and its rules; `10-frontend` decides how it is drawn (widget kit, operator scene, animations).

4. **Joining and leaving mid-match.**

   | Situation | What happens |
   | --- | --- |
   | Join during `LOBBY` or `PREMATCH` | Normal join: lobby, or wait for the start |
   | Join during `LIVE` | Straight into the match: the `teams` module puts the player into the smaller team and one bot of that team is kicked (`bots.fill` quota); normal spawn with the selected class |
   | Join during `POSTMATCH` or `VOTE` | Sees the summary and the vote, may vote, enters the next match with everyone |
   | Leave during `LIVE` | The `bots.fill` quota adds a bot for the free slot |
   | Host leaves | The server closes and everyone disconnects; GMod has no host migration (`../notes/17-lobby-and-join-flow.md`, fact 5) |

   - `server` setting `lobby.joininprogress` (bool, default on). When off, a player joining during `LIVE` spectates until the next match.
   - A bot replaced by a human is kicked; its scoreboard entry disappears (as in CoD).

5. **Vote rules** (on top of `00-core.md` decision 5 and `02-modes.md` decisions 2 and 5b: `vote.options` map + mode pairs sampled from the active playlist by weight, 15 s, random tie-break).
   - The vote ends early when every human has voted.
   - Bots do not vote.
   - "Same map and mode again" is not offered by default; `server` setting `vote.allowrepeat`.
   - The host may skip the vote with "Pick myself" (privilege) and set the next match directly.
   - The last 2 played maps are excluded; the rule switches itself off when the playlist has fewer than 3 maps (so "24/7" playlists keep working).
   - Players may change their vote until the timer ends; votes are visible to everyone, as in CoD.

## Interfaces

TBD.

## Performance budget

TBD.

## Security

TBD.

## Open questions

None open for design. In-game tests (verification, not design questions):

1. From `../notes/17-lobby-and-join-flow.md` (block level 1 only): `AskToConnect` with a `p2p:` address; host SteamID64 as the P2P address; P2P reliability behind NAT; bots on a P2P listen server.
2. Early test: a P2P guest follows `changelevel`, and a new guest can join after it (garrysmod-issues #6832 comment). Steps: `../notes/10-changelevel-and-phase-sync.md`, "To verify in game", item 2. If it fails, apply the fallback in `00-core.md` decision 9.

## Research

- `../notes/17-lobby-and-join-flow.md`
- `../notes/18-lobby-gmod-api.md`
- `../notes/19-lobby-backend.md`
