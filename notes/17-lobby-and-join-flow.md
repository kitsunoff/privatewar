# Research: lobby and join flow for a casual CoD-in-GMod

## Goal

- A casual "CoD in Garry's Mod", playable solo with bots or with friends.
- Matches are hosted by players on **listen servers**, the way CoD private matches work.
- No dedicated infrastructure. Anti-cheat against hosts is not a goal.

## Notes

| File | Scope |
| --- | --- |
| [`18-lobby-gmod-api.md`](18-lobby-gmod-api.md) | What Lua can and cannot do: P2P, connect, discovery, HTTP, Steam social, trust (verdict table on top) |
| [`19-lobby-backend.md`](19-lobby-backend.md) | Do we need a backend, a minimal lobby directory, hosting options; dedicated-server appendix (Agones etc.) |

## Facts that shape the design

1. **Steam P2P works for listen servers.**
   - It was added in the 2016-10-10 update and is controlled by the convars `p2p_enabled` and `p2p_friendsonly`. Both are set from the New Game menu (verified in `garrysmod/html/js/menu/control.NewGame.js:191-192`).
   - Friends join through the Steam friends list ("Join Game"). No port forwarding is needed.
   - `connect p2p:<host SteamID64>` is documented only on forums.
   - Stability is reported as uneven.
2. **Lua cannot do discovery or Steam social:**
   - `serverlist.*` exists only in the menu realm;
   - there is no A2S, no Steam lobbies, no friends list, no invites or rich presence;
   - Workshop content cannot change the main menu.
3. **Moving a player to another server** is possible only through `permissions.AskToConnect(address)` (client realm).
   - The player sees a confirmation prompt.
   - `connect` from Lua has been blocked since 2021-01-27.
   - Whether `AskToConnect` accepts a `p2p:` address is **untested**.
4. **P2P servers are most likely not listed in the public server browser.** An in-game list of strangers' lobbies therefore needs an external HTTP directory.
5. **The host leaving ends the match.** There is no host migration, and `maxplayers` is fixed when the host starts the game.
6. **Solo with bots** needs a local listen server with `maxplayers > 1`. Singleplayer has one slot, and `player.CreateNextBot` fails there.
7. **There is no trust in the host.** The host controls the server Lua and `sv.db`, and no Lua API exists for Steam auth tickets. Any progression stored or validated on the host is forgeable. This is accepted for this project.

## Recommended design

### Level 0: zero backend (MVP)

1. **Hosting.** The host starts GMod → New Game → our gamemode, with P2P on (optionally friends-only) and `maxplayers` 8–16.
   - Ship a `.cfg` or document recommended settings.
   - Optionally add an in-game hint that detects `p2p_enabled == 0` and tells the host how to turn it on.
2. **Joining.** Friends click "Join Game" in Steam.
3. **In-game pre-match lobby (the "game within a game").** The server stays in a `LOBBY` match phase:
   - players see a CoD-style lobby screen (party list, mode, map, bot count, teams, loadout editing, a ready toggle);
   - the host or an admin picks the mode and map; bots fill the empty slots;
   - "Start" moves to `WARMUP → LIVE`;
   - after the match comes `POSTROUND`, then a map or mode vote, then back to `LOBBY`;
   - a map change uses `changelevel`, which is allowed from Lua; the lobby state survives it through a small JSON in `data/`.
4. **Progression.** Each player's profile is stored client-side (`data/<gm>/profile.json`) and sent to the host on join. The host keeps it only for the session.
   - It is forgeable, which is acceptable.
   - This makes progression follow the player across hosts, instead of keeping a separate copy per host.
5. **Solo.** The player starts a local game with `maxplayers > 1` and P2P off. It is the same gamemode and the same lobby, only with bots.

### Level 1: optional lobby directory

For a "Browse lobbies" tab with public lobbies, add a tiny HTTP directory.

- **Host side:** the listen server sends a heartbeat every 30–60 s with name, mode, map, players and max players, a code, and the host SteamID64 as the P2P address. Entries expire through a TTL.
- **Client side:** the client does `GET /lobbies` and joins through `permissions.AskToConnect("p2p:<steamid64>")`, but only if the in-game test passes. Otherwise it shows "Add the host as a friend in Steam" with the host's name and profile link.
- **Lobby codes:** a short code (for example `K7Q2`) maps to a SteamID64. This works around the missing Steam invites.
- **Hosting:** a Cloudflare Worker + Durable Object managed with OpenTofu fits the free tier. Workers KV does not fit because of its write limits. Alternative: a self-hosted Go service behind a Cloudflare Tunnel.
- **Abuse protection** stays minimal: rate limiting per IP, a TTL, and a size cap. The directory is untrusted, best-effort data.

### Not doing

- Dedicated match servers, Agones, or a matchmaking service such as Nakama or Open Match. If this is ever needed, see the appendix of [`19-lobby-backend.md`](19-lobby-backend.md).
- Central or anti-cheat progression.

## Must test in game (blocks Level 1, not Level 0)

1. `permissions.AskToConnect("p2p:<steamid64>")`: does it work, or is the address rejected?
2. Is the P2P address of a listen server really the host's SteamID64?
3. Do P2P and friends-only join work reliably: two accounts on different networks, behind NAT?
4. Do `player.CreateNextBot` bots work on a P2P listen server (they should, since they are server-side)?
5. HTTP from the client realm to a public HTTPS endpoint: response size and rate limits in practice.
