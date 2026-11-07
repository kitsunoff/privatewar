# 10 — changelevel, state carry-over, client readiness and phase sync

Research for `design/00-core.md` open questions 3 and 4. Target: a player-hosted **listen server** (Steam P2P), bots made with `player.CreateNextBot`. Phase machine: `LOBBY → PREMATCH → LIVE → POSTMATCH → VOTE → LOBBY|PREMATCH`.

Evidence labels:

- `[wiki]`: wiki.facepunch.com page (fetched 2026-11-06 with `?format=text`);
- `[src]`: source file and line in `Facepunch/garrysmod` or `ValveSoftware/source-sdk-2013` on GitHub;
- `[forum/issue]`: URL;
- `[inference]`: my reasoning from the evidence;
- `[unverified]`: plausible, no source found; must be checked in game.

Source versions used:

- `Facepunch/garrysmod` at `ad80234` (2026-10-15);
- `ValveSoftware/source-sdk-2013` at `e1f1fd4` (server game DLL only; the GMod engine is closed source).

## TL;DR

| # | Question | Verdict |
| --- | --- | --- |
| 1 | Lua state and clients on `changelevel` | Both server and client Lua states are destroyed and rebuilt (`ShutDown` → new `Initialize`). Human clients stay connected and reload the new map without returning to the menu. On P2P this is the intended behaviour, but there is a 2026 report that after `changelevel` nobody can join a P2P server. Must be tested on the current build. |
| 2 | `player.CreateNextBot` bots on `changelevel` | No source found. Whether they are dropped or carried over as engine fake clients is `[unverified]`. In both cases their Lua state is lost. Design: reconcile bots on the new map (kick extras or adopt them, create missing ones), do not rely on either behaviour. |
| 3 | Carrying state across `changelevel` | Simplest: a JSON file in `data/` written just before `changelevel` and read in `Initialize`/`InitPostEntity`. PData/`sql` (`sv.db`) for per-player data. Engine ConVars very likely keep their value. `game.SetGlobalState` survives level changes in Source but only holds on/off/dead. No `changelevel` argument channel exists. |
| 4 | "Client fully loaded" | `PlayerInitialSpawn` runs before the client finishes loading. Net messages sent then are not lost, but `LocalPlayer()` may still be NULL on the client. The standard pattern is still client `InitPostEntity` → net message to server. There is no `PlayerFullLoad`/`ClientFullyInitialized` hook. `ClientSignOnStateChanged` (2021) exists but cannot give a Player object. |
| 5 | Phase networking | `SetGlobal2*` values reach late joiners automatically (available in client `InitPostEntity`), are sent once per change, and ignore PVS. A client callback works through `EntityNetworkedVarChanged`, which `Entity(0):SetNW2VarProxy` uses. Pitfalls: the hook fires **before** the value is stored, fires again on every full update with `oldval = nil`, and there is no ordering guarantee relative to net messages. Recommendation: phase, end time and a sequence number in NW2 globals, with the HUD reading them on demand. Do not split one state change across NW2 and a net message. |

## 1. `changelevel` on a listen server

### 1.1 Lua state is reset on both realms

- `GM:ShutDown` is "Called whenever the Lua environment is about to be shut down, for example on map change", realm **Shared** [wiki `GM:ShutDown`].
- So any state that must survive has to be saved to disk before the change and restored on the new map (for example in `InitPostEntity`) [inference].
- Client side: the client re-runs the whole Lua loading order (`includes/init.lua` → base `cl_init.lua` → autorun → gamemode `cl_init.lua`) [wiki `Lua_Loading_Order`]. Client `GM:Initialize` and `InitPostEntity` run again on the new map [inference].
- `CurTime()` is per level, so any absolute end time from the old map is meaningless on the new one [inference].

### 1.2 Human clients stay connected

- Source semantics: `changelevel` keeps clients connected. They go through the sign-on states again. `SIGNONSTATE_CHANGELEVEL = 7` exists in the enum used by `GM:ClientSignOnStateChanged` [wiki `Enums/SIGNONSTATE`].
- "`SIGNONSTATE_FULL` is set when the client joins the server or when the map changes, so it's once per map unless they rejoin" [forum/issue https://github.com/Facepunch/garrysmod-requests/issues/718#issuecomment-822009213].
- Lua changes the map with `RunConsoleCommand("changelevel", map)` or `game.LoadNextMap`, and connected players simply load the next map [wiki `game.LoadNextMap`; inference].
- `changelevel` is **not** on the `RunConsoleCommand` block list; `map` is ("Could forcibly load a map without the client wanting to") [wiki `Blocked_ConCommands`]. So Lua must use `changelevel`, not `map`.
- Each player gets `PlayerInitialSpawn` again on the new map. Its `transition` argument is for `trigger_changelevel`-style transitions and should be `false` for a console `changelevel` [wiki `GM:PlayerInitialSpawn`; inference for the console case].
- New since 2025-11-28: `game.GetMapChangeCount()` returns 1 on the first map of the session and grows on each `changelevel`/`map` [wiki `game.GetMapChangeCount`]. Useful to tell "fresh boot" from "after our changelevel".
- A client that does not have the target map must download it. On a P2P listen server there is no FastDL, so maps must come from Workshop (`resource.AddWorkshop`) or be installed already [inference].

### 1.3 Steam P2P specifics and known issues

- In April–May 2026, after a netcode update, P2P joins broke ("invalid sequence ack nr"). Facepunch pushed a fix on 2026-04-29. A follow-up comment on the same issue says: "doing changelevel causes no one able to join that p2p server, whether during the changelevel itself, or from joining off the host's 'Join game' option on Steam". That issue was closed without a reply to this comment [forum/issue https://github.com/Facepunch/garrysmod-issues/issues/6832].
- Related reports from the same period: friends stuck on the loading screen, worked around with `net_maxfragments 4000` and then fixed by Facepunch [forum/issue https://github.com/Facepunch/garrysmod-issues/issues/6845]; P2P netcode still bad for high-ping peers on x86-64 in 2026-09 [forum/issue https://github.com/Facepunch/garrysmod-issues/issues/7042].
- `retry` on a listen server with P2P guests kicks the host from their own server [forum/issue https://github.com/Facepunch/garrysmod-issues/issues/5109]. Never use `retry`/`reconnect` as a "reload" tool.
- Generic `changelevel` crash and content reports (not P2P-specific): client crashes during `changelevel` on x86-64 [forum/issue https://github.com/Facepunch/garrysmod-issues/issues/5917]; models packed into BSPs broken after `changelevel` [forum/issue https://github.com/Facepunch/garrysmod-issues/issues/2650].
- Whether already-connected P2P clients follow the host through `changelevel` on the **current** build is `[unverified]`. The report in #6832 is about new joins, and it is unclear whether it still happens.

## 2. `player.CreateNextBot` bots on `changelevel`

- The wiki page says nothing about map changes. It only says to remove bots with `Player:Kick`, not `Entity:Remove`, that they use player slots, and that they are UnAuthed [wiki `player.CreateNextBot`].
- No issue on `Facepunch/garrysmod-issues` mentions bots and `changelevel` together (searched "changelevel bots", "CreateNextBot", "map change bot"). The `CreateNextBot` issues found are: crash when the edict limit is hit (#6475), segfault when called too early in autorun (#5534, now a non-fatal error), and empty bot names in `player_activate` (#6001).
- Bot creation can fail (slots full, server not ready), so code must handle `player.CreateNextBot` returning NULL [inference].
- Public bot addons do not assume either behaviour: they count existing bots on the new map after a short delay and add or kick bots against `player.GetBots()` up to a quota.
- In plain Source, fake clients created by the server DLL can survive a level change as clients. If GMod does this, the bot `Player` entities would come back with a **fresh Lua state** (no brain tables, no team assignment), and `PlayerInitialSpawn` would run for them again [inference; GMod engine not available].
- Verdict: `[unverified]` whether bots are dropped or kept. Design for both.

## 3. Carrying state across `changelevel`

| Mechanism | Survives `changelevel` | Pros | Cons | Evidence |
| --- | --- | --- | --- | --- |
| JSON file in `data/` (`file.Write`) | Yes (disk) | Any table; trivial; readable for debugging; common practice in public addons | Survives a crash too, so a stale file can be applied on the next boot; needs a validity check | [wiki `file.Write`]; [inference] |
| `sql` / PData (`sv.db`) | Yes (disk) | Per-player key/value; SteamID64 keyed | SQL quoting; overkill for one blob; bots are UnAuthed, so per-bot PData is meaningless | [wiki `Player:SetPData`] |
| Server ConVar set from Lua (non-archived) | Very likely yes (engine object; `CreateConVar` returns an existing ConVar unchanged) | No file; visible in console | Strings only; `server.cfg`/`game.cfg` may run again on map load and override; leaks into the next session if the process keeps running | [wiki `Global.CreateConVar`] "If a ConVar already exists ... return the already existing ConVar without modifying it"; `exec game.cfg` in `GameInit` (`gameinterface.cpp:857-858`) [src]; survival of a **Lua-created** non-archived value [unverified] |
| `game.SetGlobalState` | Yes in Source: global states are reset in `GameInit`/`GameShutdown` ("NOT on level transitions within a game") | No disk | Only `GLOBAL_OFF/ON/DEAD` per name; would need many names to encode data; GMod behaviour [unverified] | `source-sdk-2013 src/game/server/gameinterface.cpp:854-876` [src]; [wiki `game.SetGlobalState`] |
| `changelevel` arguments | No | — | `changelevel <map> [landmark]` only; no free-form payload; the command line cannot be changed at runtime | [inference] |
| Lua globals, `GetGlobal*`, NW/NW2 | No | — | Destroyed with the Lua state / entity list | [wiki `GM:ShutDown`] |

Verdict: **a JSON file in `data/` is the simplest channel** for a "next match" payload. ConVars and global states cannot carry structured data cleanly [inference].

## 4. Detecting "client fully loaded"

- `GM:PlayerInitialSpawn` "is called before the player has fully loaded, when the player is still in seeing the `Starting Lua` screen". Net messages sent there "**won't** be lost and the client still should receive it", but they can arrive before client `InitPostEntity`, when `LocalPlayer()` may be NULL [wiki `GM:PlayerInitialSpawn`, linking https://github.com/Facepunch/garrysmod-requests/issues/718].
- The wiki gives two patterns on that page [wiki `GM:PlayerInitialSpawn`]:
  - **with networking (standard)**: client `hook.Add("InitPostEntity", ...)` → `net.Start(...)`/`net.SendToServer()`; the server marks the player ready in `net.Receive`;
  - **without networking**: queue the player in `PlayerInitialSpawn`, and treat the first `StartCommand` with `not cmd:IsForced()` as "loaded".
- `GM:InitPostEntity` (client): from here `LocalPlayer()` is valid, but the client only knows entities in the spawn point's PVS [wiki `GM:InitPostEntity`].
- `gameevent player_activate`: "called almost directly after `GM:PlayerInitialSpawn` in the same tick ... players may not have finished loading" [wiki `gameevent/player_activate`]. It is not a readiness signal.
- `gameevent OnRequestFullUpdate`: the first one per client means net messages will be received, but it "**won't** be called reliably" with `sv_parallel_sendsnapshot` [wiki `gameevent/OnRequestFullUpdate`; forum/issue https://github.com/Facepunch/garrysmod-issues/issues/6465].
- `GM:ClientSignOnStateChanged(userID, old, new)` (added 2021.03.31, shared): "You cannot get a valid player object from the userID at any point during this hook" [wiki `GM:ClientSignOnStateChanged`; forum/issue https://github.com/Facepunch/garrysmod-issues/issues/4899]. Facepunch added it as the answer to the "PlayerFullyConnected" request [forum/issue https://github.com/Facepunch/garrysmod-requests/issues/718#issuecomment-765869031]. Server-side `SIGNONSTATE_FULL` comes **before** the player entity exists [same thread, comment 821201408].
- `GM:PlayerFullLoad` and `GM:ClientFullyInitialized` do **not** exist (wiki returns "Page Not Found") [wiki].
- Another workable client-side trigger is the first client `GM:SetupMove`, after which the server can send a full state update [inference].
- Reliability caveat: 1–5 % of clients in one gamemode never got their ready message through. The suggested fix was to repeat the message until the server acks it [forum/issue https://github.com/Facepunch/garrysmod-issues/issues/5081].
- Bots never run client Lua. They must count as ready as soon as they exist [inference].

## 5. Networking phase and end time

### 5.1 `SetGlobal2*` (NW2 globals)

- `SetGlobal2*` works like `Entity(0):SetNW2*`, so the values are readable with `Entity(0):GetNW2*` [wiki `Networking_Usage` § NW2].
- "All NW2 values will be accessible clientside when the `GM:InitPostEntity` hook is called". So late joiners and players reloading after `changelevel` get them automatically [wiki `Networking_Usage` § NW2].
- A value is sent only when it changes, once, not re-sent every 10 s like NW1. "All SetGlobal2* functions will update the value clientside, and it will ignore the PVS" [wiki `Networking_Usage` § NW2].
- Transport: an NW2 var is sent as an entity message with the entity snapshots. It is the same delivery class as other entity state, not the reliable `net` stream [wiki `Networking_Usage` § NW2; ordering consequence is inference].
- Types: Angle, Boolean, Entity, Float, Int, String, Vector [wiki `Global.SetGlobal2Var`]. `Global2Float` is 32-bit (`3.3` reads back as `3.2999999523163`) [wiki `Global.GetGlobal2Float`]. That is fine for `CurTime()`-based end times within one map (`CurTime` restarts per level) [inference].
- Limits: one shared NW2 string table of 4095 keys, keys up to 1023 chars, string values up to 511 chars. Too many NW2 changes at once can trigger `SV_PackEntity: SendTable_Encode returned false` and kill the server [wiki `Networking_Usage` § NW2 limits/errors]. A handful of phase keys is negligible.
- Issue #5455 (NW2 mixed up on **Lua-based** entities) does not apply to the world entity [wiki `Entity:SetNW2VarProxy`; inference].

### 5.2 Change callback on the client

- `Entity:SetNW2VarProxy(key, fn)` stores `fn` in `ent.NWVarProxies` and is driven by the `EntityNetworkedVarChanged` hook [src `garrysmod/lua/includes/extensions/entity.lua:628-664`]. Only one proxy per key; it is realm-local [wiki `Entity:SetNW2VarProxy`].
- Use on the world entity: `Entity(0):SetNW2VarProxy(key, ...)` registered in client `InitPostEntity`. No official statement that it works for `SetGlobal2*` keys. Since globals are world-entity NW2 vars, it should [inference]. Check it in game (see below).
- `GM:EntityNetworkedVarChanged` pitfalls [wiki `GM:EntityNetworkedVarChanged`]:
  - it fires **before** the client value changes: `GetGlobal2*` inside the callback returns the **old** value; use the `newval` argument;
  - on every full update (join, `cl_fullupdate`, heavy packet loss) it fires for **all** NW2 vars with `oldval = nil`, so the callback must be idempotent;
  - it is NW2-only.
- A proxy registered in client `InitPostEntity` misses the initial values, which are already in place at that point. Read the current values once after registering [inference].

### 5.3 Compared with a net message on join and on change

| Aspect | NW2 globals | Net message (on ready + on change) |
| --- | --- | --- |
| Late joiners / after `changelevel` | Automatic | Must be sent from the "ready" handler [inference] |
| Callback | `EntityNetworkedVarChanged` / proxy, with the pitfalls above | `net.Receive`, explicit and ordered with other net messages |
| Atomic multi-field update | No: each key can arrive in a different snapshot [inference] | Yes: one message carries phase, end time and mode |
| Ordering vs other net messages | Not guaranteed [inference] | Ordered within the reliable stream [inference] |
| Code size | Smallest | Larger: a ready handshake is needed |

Global values do not need a resend from the ready handler: the wiki states that they are synced automatically on connect [wiki `Networking_Usage` § NW2].

## Recommendations for design/00-core.md

### R1. Persist the next match in one JSON file

1. Before `changelevel`, the server writes `data/cod/pending_match.json` (`file.CreateDir("cod")`, `file.Write`) with:

   ```json
   {
     "v": 1,
     "map": "cod_crash",
     "mode": "tdm",
     "bots": 6,
     "settings": { "scoreLimit": 75, "timeLimit": 600 },
     "teams": { "76561198000000000": 1 },
     "createdAt": 1793952000,
     "mapChangeCount": 1
   }
   ```

2. Then `RunConsoleCommand("changelevel", map)` behind a `COD.mapChanging` guard. Write the file **before** the command, not in `ShutDown`, so that a failed `changelevel` does not lose it.
3. On the new map (server `GM:Initialize`), read the file, then remove it, and accept it only if all of these hold:
   - `game.GetMap() == data.map`;
   - `game.GetMapChangeCount() == data.mapChangeCount + 1` (fails on a fresh boot after a crash);
   - `os.time() - data.createdAt < 120`;
   - `data.v` is known.

   **Corrected by an in-game check (2026-11-06):** read the file one tick after server `InitPostEntity`, not in
   `GM:Initialize`; the map change count is not updated yet in either hook. See "Verified in game (2026-11-06)".
4. Valid → set phase `PREMATCH` with that mode/settings. Invalid or missing → `LOBBY`.
5. If `changelevel` fails (map missing): after about 10 s still on the old map, clear the guard and return to `LOBBY` with an error [inference].
6. Do not use ConVars, `game.SetGlobalState` or PData for this payload. Use PData/`sql` only for long-lived per-player data (progression), which is a separate topic.

### R2. Bots: reconcile, never assume

1. Store the bot count (and optional names/teams) in the pending file.
2. In `InitPostEntity` + `timer.Simple(1, ...)` (a short delay so the new map settles), compare `player.GetBots()` with the target:
   - adopt existing bots and re-initialise their Lua state (brain, team), because Lua tables are gone in any case;
   - create missing ones with `player.CreateNextBot`, and handle a `NULL` return (slots full or server not ready);
   - remove extras with `Player:Kick`, never `Entity:Remove`.
3. Bots count as "loaded" immediately.

### R3. Loaded clients: InitPostEntity handshake with retry

1. Client `InitPostEntity` → `cod_client_ready` (through `COD.Net.Receive` with `phases = any`, `rate = 2`). Resend every 2 s until the server answers `cod_client_ready_ack`. This covers the 1–5 % loss in issue #5081.
2. Server: `ply.codReady = true` on receipt, then send that player whatever is not in NW2 (loadout, mode-specific tables).
3. `PREMATCH` waits for `every human with codReady` **or** 60 s, then starts the countdown. The set of humans is `player.GetHumans()` at check time. Players who disconnect drop out of it, and players who are still connecting count as "not ready".
4. Do not use `ClientSignOnStateChanged`, `player_activate` or `OnRequestFullUpdate` as the ready signal. Reasons are in section 4.

### R4. Phase networking: NW2 globals as the single source of truth

1. The server sets `SetGlobal2String("cod_phase", phase)`, `SetGlobal2Float("cod_phase_end", CurTime() + dur)` (or `-1`), and `SetGlobal2Int("cod_phase_seq", n)`. These are the only writes, done in one `COD.SetPhase` function, and always in the order end → phase → seq.
2. Clients:
   - the HUD reads `GetGlobal2Float("cod_phase_end") - CurTime()` every frame; no timer pushes;
   - one `Entity(0):SetNW2VarProxy("cod_phase_seq", ...)` (or a filtered `EntityNetworkedVarChanged` hook) fires `hook.Run("COD_PhaseChanged", ...)`;
   - the handler must be idempotent, take values from `newval` or defer one frame (`timer.Simple(0, ...)`) before reading the other keys, because the hook fires before the value is stored and keys may arrive in different snapshots;
   - after registering the proxy in `InitPostEntity`, run the handler once with the current values.
3. Do not send the same transition through a net message in parallel. If a mode needs a payload that must arrive **with** the phase change (for example the end-of-match scoreboard), send it as a net message that carries its own phase/seq. The client applies it when its seq matches.
4. Set the NW2 values in or after server `InitPostEntity`, not in `GM:Initialize` (see "To verify").

## To verify in game

All tests: host = listen server from the main menu, `maxplayers 8`, P2P on, gamemode loaded, `developer 1`. A second account on another network is needed for P2P items.

1. **Lua reset on both realms** (Q1). Server: `hook.Add("ShutDown","t",function() print("SV shutdown", CurTime()) end)`; client: the same with `print("CL shutdown")`. Run `changelevel gm_flatgrass`. Expect both prints, then `GM:Initialize` runs again on both, and a global set before (`lua_run TESTVAR=1`, `lua_run_cl TESTVAR=1`) is `nil` afterwards.
2. **P2P guest follows changelevel** (Q1). The guest joins via P2P. The host runs `lua_run RunConsoleCommand("changelevel","gm_construct")`. Record whether the guest loads the new map without a menu, the time it takes, and any `invalid sequence ack nr` lines. Repeat 5 times. Then a **third** account tries to join after the change (issue #6832 symptom).
3. **Bots across changelevel** (Q2). `lua_run for i=1,3 do player.CreateNextBot("B"..i) end`, then `changelevel`. On the new map, in `InitPostEntity` and again 2 s later, print `#player.GetBots()`, their names and `EntIndex`, and whether `PlayerInitialSpawn` fired for them. If they survive, check that they spawn, move under `StartCommand` and take damage.
4. **Lua-created non-archived ConVar** (Q3). `CreateConVar("cod_test","0")` in the gamemode, `lua_run RunConsoleCommand("cod_test","5")`, `changelevel`, then `cod_test` in console. Expect `5`. Also check whether a `listenserver.cfg`/`server.cfg`/`game.cfg` exec appears in the console log on map load.
5. **`game.SetGlobalState`** (Q3, optional). `lua_run game.SetGlobalState("cod_x", GLOBAL_ON)`, `changelevel`, then `lua_run print(game.GetGlobalState("cod_x"))`. Expect `1` (GLOBAL_ON) if Source behaviour holds.
6. **Pending-file guard** (R1). Write the file, kill the game process instead of changing level, start a new game. Expect `LOBBY`, since `GetMapChangeCount() == 1`.
7. **Ready handshake timing** (Q4). Log server-side time of `PlayerInitialSpawn`, `player_activate`, `ClientSignOnStateChanged` (each state) and `cod_client_ready` arrival for a guest joining fresh and after `changelevel`. Use `net_fakelag 200` and `net_fakeloss 5` on the guest to test the retry.
8. **Global2 proxy on the world** (Q5). Client in `InitPostEntity`: `Entity(0):SetNW2VarProxy("cod_phase_seq", function(e,k,o,n) print("proxy", k, o, n, GetGlobal2Int("cod_phase_seq")) end)`. Server: `lua_run SetGlobal2Int("cod_phase_seq", 1)`, then `2`. Expect the proxy to fire with `o=nil/1`, `n=1/2`, and `GetGlobal2Int` inside to print the **old** value. Then run `cl_fullupdate` on the client and expect the proxy to fire again with `o=nil`.
9. **Late joiner gets NW2** (Q5). Set the three phase keys, then let the guest join. In client `InitPostEntity`, print `GetGlobal2String("cod_phase")` and `GetGlobal2Float("cod_phase_end") - CurTime()`. Expect correct values without any net message.
10. **NW2 set too early** (R4). Set a Global2 var in server `GM:Initialize` and another in `InitPostEntity`, then join. Check that both arrive. If the first does not, keep the rule "set in or after `InitPostEntity`".
11. **Ordering NW2 vs net** (Q5). Server, in one tick: `SetGlobal2Int("k", n)` then `net.Start("t") net.WriteUInt(n,16) net.Broadcast()`. Client: log `SysTime()` for the NW2 proxy and for `net.Receive`, over 100 iterations with `net_fakelag 100`. Record which arrives first and how often the order flips.

## Verified in game (2026-11-06)

1. **`game.GetMapChangeCount()` lags on the new map** (R1). On the new map it still returns the old value in
   `GM:Initialize` and in server `InitPostEntity`; it grows by 1 only from the first tick. Measured on the Steam
   Deck under Proton: `29` in `InitPostEntity`, `30` on the next frame. Therefore the pending file must be read one
   tick after `InitPostEntity` (`timer.Simple(0, ...)`), not in `GM:Initialize` as R1 step 3 said.
