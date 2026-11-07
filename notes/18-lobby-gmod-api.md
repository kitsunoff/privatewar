# 01 — Garry's Mod Lua API for an in-game lobby browser and "join lobby"

Research date: 2026-11-03.

Sources used:

- Official wiki, raw page text fetched with `https://wiki.facepunch.com/gmod/<Page>?format=text`.
- `Facepunch/garrysmod` repository, shallow clone at commit `ad8023410600199ad9a12444bc496b9d65226a82` (2026-10-15). Paths below are relative to `garrysmod/` in that repo.
- `Facepunch/garrysmod-issues` and `Facepunch/garrysmod-requests` trackers (via `gh`).
- Official changelog: <https://gmod.facepunch.com/news/october-2016-update>.

Evidence labels used in this file:

- **[wiki]**, **[repo]**, **[issue]**, **[changelog]**: backed by that primary source.
- **[inference]**: my conclusion from the cited sources; not stated directly by them.
- **UNVERIFIED**: no primary source found. Needs an in-game test.

---

## Verdict table

| # | Capability | Verdict | Key source |
| --- | --- | --- | --- |
| 1 | Force-connect a player with `connect` from client or server Lua | **Impossible** (`connect` is on the blocked list) | wiki `Blocked_ConCommands` |
| 2 | Ask the player to connect to another server (`permissions.AskToConnect`) | **Possible with caveats** (confirmation dialog; player may tick "Don't ask again for this server") | wiki `permissions.AskToConnect`; repo `lua/menu/openurl.lua` |
| 3 | `permissions.AskToConnect("p2p:<steamid64>")` (join a P2P listen server) | **UNVERIFIED** (not documented; needs test) | — |
| 4 | Pass a server password through `AskToConnect` | **No argument for it**; setting client `password` convar first is UNVERIFIED | wiki `permissions.AskToConnect` |
| 5 | Redirect via `gui.OpenURL("steam://connect/...")` | **Impossible** (URL must start with `http://` or `https://`) | wiki `gui.OpenURL` |
| 6 | Query the Steam master server list (`serverlist.*`) from client/server Lua | **Impossible** (menu realm only) | wiki `serverlist`, `serverlist.Query` |
| 7 | Change the GMod main menu from a Workshop gamemode/addon | **Impossible** (only background images, logo, New Game settings) | wiki `States`; repo `lua/menu/mainmenu.lua` |
| 8 | HTTP from client and server Lua (`HTTP`, `http.Fetch`, `http.Post`) | **Possible with caveats** (no private/local IPs; `-allowlocalhttp` dedicated only; large bodies fail) | wiki `Global.HTTP`, `http.Fetch` |
| 9 | WebSockets | **Impossible on clients from Workshop**; server only with manually installed binary module | wiki `Global.require`; GWSockets README |
| 10 | Client-side Steam auth ticket for a backend | **Impossible** (open feature request) | requests #2279 |
| 11 | Server-side verified SteamID | **Possible** (`NetworkIDValidated`, `IsFullyAuthenticated`) — but on a listen server the host controls this code | wiki |
| 12 | Steam friends list, invites, Steam lobbies, rich presence from Lua | **Impossible** (only `Player:GetFriendStatus` for players on the same server) | wiki `steamworks`, `Player:GetFriendStatus` |
| 13 | Steam P2P listen servers (no port forwarding) | **Possible** (`p2p_enabled`, `p2p_friendsonly`, set in the New Game menu) | repo `html/js/menu/control.NewGame.js`; changelog Oct 2016 |
| 14 | P2P listen servers visible in the server browser / master list | **Likely no** (indirect evidence only) | requests #853 (open) |
| 15 | Friend joins host via Steam friends list "Join Game" | **Possible** (engine rich presence; not controllable from Lua) | requests #1164 |
| 16 | Several matches inside one server (instancing) | **Possible with caveats** (transmission + collision + PVS + traces + sounds must all be filtered by your code) | wiki `SetPreventTransmit`, `ShouldCollide` |
| 17 | Change map from server Lua (`changelevel`) | **Possible** (`changelevel` is not on the blocked list; `map` is) | wiki `Blocked_ConCommands` |
| 18 | Set `sv_password` / `hostname` at runtime from server Lua | **Possible** (not blocked); custom gate via `GM:CheckPassword` | wiki `GM:CheckPassword` |
| 19 | Change `maxplayers` at runtime | **Impossible** (`maxplayers` is blocked; fixed at server start) | wiki `Blocked_ConCommands` |
| 20 | Launch processes / start new servers from Lua | **Impossible** (`os` library reduced to date/time) | wiki `os` |
| 21 | Anti-cheat-grade progression stored on a player-hosted server | **Impossible** (host runs and can modify server Lua and `sv.db`) | [inference] from wiki `States`, `cookie` |
| 22 | In-game lobby UI with Derma or DHTML (CEF) | **Possible** (CEF 86 on Windows; Awesomium on some Linux) | wiki `HTML_Web_Engine`, `DHTML` |

---

## 0. Player-hosted lobbies (top priority)

Scope: matches are hosted by players on their own listen servers. No dedicated infrastructure.

### 0.1 Steam P2P networking for listen servers

1. **GMod supports Steam P2P for listen servers.** The New Game screen has two checkboxes: "Peer-To-Peer" and "Peer-To-Peer: Friends Only". [repo]
   - `html/template/newgame.html` lines ~73–79: checkboxes bound to `ServerSettings.p2p_enabled` and `ServerSettings.p2p_friendsonly`, shown only when `MaxPlayers > 1`.
   - `html/js/menu/control.NewGame.js` lines ~191–195: on start the menu runs `p2p_enabled`, `p2p_friendsonly`, `sv_lan`, `maxplayers`, then `map`.
   - `resource/localization/en/main_menu.properties` lines 66–67: `p2p_server=Peer-To-Peer`, `p2p_server_friendsonly=Peer-To-Peer: Friends Only`.
2. **Exact convars:** `p2p_enabled` (0/1) and `p2p_friendsonly` (0/1). [repo] `lua/menu/mainmenu.lua` function `UpdateServerSettings()` reads both with `GetConVarString`.
3. **P2P and LAN are mutually exclusive in the UI.** `CheckboxCheck()` in `control.NewGame.js` turns off `p2p_enabled` when `sv_lan` is enabled and the other way round. "Friends only" is disabled unless P2P is enabled. [repo]
4. **When it was added:**
   - `p2p_friendsonly` was added in the October 2016 update: "Peer-To-Peer friends only mode - Enable this to only allow friends to join your games" and "Added p2p_friendsonly ConVar". [changelog] <https://gmod.facepunch.com/news/october-2016-update>
   - The date `p2p_enabled` itself was added: **UNVERIFIED** (a 2016 Steam forum comment says "July update"; not a primary source).
5. **Dedicated servers:** command-line flag `-p2p` "Allows clients to connect to the server using p2p. This has been broken for a good while" [wiki `Command_Line_Parameters`]. Issue #6461 (closed 2025-08) shows the dedicated server prints `connect p2p:<steamid>`; robotboy655 fixed missing Linux DS P2P code on `dev`. [issue] <https://github.com/Facepunch/garrysmod-issues/issues/6461>. Not relevant for player-hosted, but proves the address syntax.
6. **Join syntax:** `connect p2p:<steamid64>`. Evidence:
   - Issue #6461: server prints "Run the following command in a client's console to connect: `connect p2p:12345678987654321`" (also quoted in requests #2031). [issue]
   - Issue #2896: server log `Client "Hoxton" connected (p2p:76561198068070226)`. [issue]
   - Whether the P2P address of a **listen** server is the host's own SteamID64: **UNVERIFIED** ([inference]: likely, since the listen server uses the host's Steam account; test it).
7. **Joining from the Steam friends list ("Join Game")** works through engine-level rich presence. robotboy655 in requests #1164: "Added basic support for this to Dev branch. As far as I can tell joining friends from friends list does work properly." [issue] <https://github.com/Facepunch/garrysmod-requests/issues/1164>. Lua cannot read or set this rich presence (see §5).
8. **Known P2P limitations:**
   - `net.Start(name, true)` (unreliable) messages are "insanely degraded" on P2P servers — issue #4980, **open** since 2021. Use reliable net messages. [issue] <https://github.com/Facepunch/garrysmod-issues/issues/4980>
   - P2P connection stuck at "retrieving server info" — issue #6546, open (2025-10). [issue]
   - Lua file limit complaints for P2P — requests #2131, open. [issue]
   - Detecting P2P from Lua: no `game.Peer2Peer()`; requests #2492 open. robotboy655: "There's functionally no difference between a normal listen server and a P2P one". Workaround suggested in the thread: `not game.IsDedicated() and not game.SinglePlayer() and GetConVar("p2p_enabled"):GetBool()`. [issue] <https://github.com/Facepunch/garrysmod-requests/issues/2492>
   - Friends-only is enforced by the engine; a 2016 report of failures (#2896) was caused by a third-party addon. [issue]
9. **Does `permissions.AskToConnect` accept a `p2p:` address?** **UNVERIFIED.** Facts:
   - The wiki says: "If a port is not given, the default `:27015` port will be added." [wiki] If this is applied to `p2p:7656...`, the address could become invalid. Must be tested.
   - The menu dialog calls `serverlist.PingServer( self:GetURL(), ... )` to show server info (`lua/menu/openurl.lua`, `PANEL:LoadServerInfo`). For a `p2p:` address the ping may show "Server failed to respond!" even if connect works. [repo] + [inference]
   - Then it calls `permissions.Connect(address)` (Menu realm). [repo]

### 0.2 Discovery of player-hosted (listen / P2P) servers

1. **Master server list from game Lua: impossible.** `serverlist` is a "Menu state library to query the master server list"; `serverlist.Query` realm: Menu. Valid `Type` values: `internet`, `favorite`, `history`, `lan`. [wiki `serverlist`, `Structures/ServerQueryData`] The menu realm cannot be modified by Workshop content (see §6).
2. **Do P2P listen servers appear in the internet list?** **Likely no — UNVERIFIED.** Indirect evidence: request #853 "List friends' P2P servers on the server-list somewhere" is still open (2016). [issue] <https://github.com/Facepunch/garrysmod-requests/issues/853>. There is no "friends" category in the menu server browser code (`html/js/menu/control.Servers.js`, `lua/menu/mainmenu.lua` `GetServers`). [repo]
3. **Only Lua-accessible way to advertise:** the host's server realm (or client realm) sends an HTTP request to an external directory (§3). There is no Steam matchmaking/lobby API in Lua (§5). So "no dedicated infrastructure" is not fully achievable: you need at least a small public HTTP directory (any serverless endpoint works). [inference]
4. **Client reading the list:** client realm `http.Fetch` to the same directory, render in Derma/DHTML, then `permissions.AskToConnect(address)`. [wiki] Address format for P2P: see §0.1 item 9 (UNVERIFIED).
5. **What the host can learn about itself:** `LocalPlayer():SteamID64()` / `Player:IsListenServerHost()` (Shared) [wiki]; `game.GetIPAddress()` returns "x.x.x.x:x" but returns `0.0.0.0:port` too early on first start (bug #3001), and "loopback" in singleplayer [wiki]. What it returns on a P2P listen server behind NAT: **UNVERIFIED**.

### 0.3 Invites

1. No Lua API for Steam invites, rich presence, friends list, or Steam lobbies. The `steamworks` library contains only Workshop/UGC functions plus `RequestPlayerInfo`/`GetPlayerName` (19 functions; none with Invite, Lobby, RichPresence, AuthTicket in the name). [wiki `steamworks`]
2. Feature requests for a built-in lobby (#3385, #3386) were **closed** in 2026-09 without implementation. [issue] <https://github.com/Facepunch/garrysmod-requests/issues/3385>, <https://github.com/Facepunch/garrysmod-requests/issues/3386>
3. Workarounds:
   - Players use the Steam friends list "Join Game" (engine rich presence, §0.1 item 7).
   - In-game "invite code": host publishes `p2p:<steamid64>` (or IP) to your HTTP directory under a short code; the friend enters the code in your in-game UI → `permissions.AskToConnect`. [inference]
   - Copy-to-clipboard of `connect p2p:<id>` (`SetClipboardText` is used by the menu itself in `openurl.lua`) and the player pastes into console manually. [repo] + [inference]
   - `Player:GetFriendStatus()` (Client realm) only works for players already on the same server. [wiki]

### 0.4 Listen-server specifics

1. Host identity: `game.IsDedicated()` is false on listen and singleplayer [wiki `game.IsDedicated`]. `Player:IsListenServerHost()` (Shared) is true for the host, always true in singleplayer, false on dedicated [wiki].
2. Host realms: "the server and client are one and the same in singleplayer and for listen server hosts" (for console commands). [wiki `Global.RunConsoleCommand`]
3. `maxplayers` is chosen in the New Game menu (options 1, 2, 4, 8, 16, 32, 64, 128 in `control.NewGame.js` lines 64–71) [repo] and cannot be changed from Lua (`maxplayers` is blocked) [wiki `Blocked_ConCommands`]. `maxplayers 1` = singleplayer; P2P/hostname options are hidden then (`ng-show="MaxPlayers > 1"`). [repo]
4. Map change: server Lua can `RunConsoleCommand("changelevel", map)`; `map` is blocked, `changelevel` is not on the list. [wiki `Blocked_ConCommands`] Also `game.LoadNextMap()` (Server). [wiki]
5. Host leaves: the server runs inside the host's game process, so when the host disconnects or quits, the server ends and all clients are disconnected. There is no host-migration API. **UNVERIFIED by a primary document** — [inference] from the listen-server model above. Plan the match flow for it (results upload on host exit cannot be guaranteed).
6. `retry` is not on the blocked list (also noted in requests #2089). [wiki] Issue #5109 (closed): `retry` on a listen server quit the server and crashed when hosting again. [issue]
7. Custom admission: `GM:CheckPassword( steamID64, ipAddress, svPassword, clPassword, name )` is called for every **non-local** player and can return `false, "reason"`. [wiki] Default implementation in `gamemodes/base/gamemode/init.lua` (~lines 124–141) only compares `sv_password`. [repo]

### 0.5 Trust model for player-hosted matches

1. The host runs the server realm on their own machine. They can run any server Lua (e.g. via addons) and edit their own files. [inference] from wiki `States`.
2. Persistence options:
   - `sql` / `Player:SetPData` / `util.SetPData`: `sv.db` on the server (host's disk), `cl.db` on the client. "PData is not networked from servers to clients!" [wiki `Player:SetPData`]
   - `cookie` library: `garrysmod/sv.db` (server), `garrysmod/cl.db` (client), `garrysmod/mn.db` (menu). [wiki `cookie`]
   - `file.Write` to `DATA` (`garrysmod/data/`). [wiki `File_Search_Paths`]
   - All of these are on machines controlled by players. Any progression stored or validated there can be forged. [inference]
3. External backend with HTTP: the backend sees requests from clients and hosts but **cannot verify identity**: there is no Lua API for Steam auth tickets (requests #2279 open; robotboy655: "I don't really see a way to implement this to 'minimize abuse'"). [issue] <https://github.com/Facepunch/garrysmod-requests/issues/2279>
4. Consequence: with player hosts, cross-match progression (unlocks, XP) can only be "cosmetic/trust-based", or verified by an out-of-game Steam login (e.g. Steam OpenID in a browser via `gui.OpenURL`, then a code typed back into the game). The OpenID flow is a standard Steam web feature and is **not documented by GMod sources**; treat as [inference]. Even then, match results reported by a host remain forgeable.

---

## 1. Moving a player to another server

### 1.1 `connect` is blocked

- `Blocked_ConCommands` [wiki] <https://wiki.facepunch.com/gmod/Blocked_ConCommands>: "list of all concommands and convars blacklisted from being ran or changed with `RunConsoleCommand`, `game.ConsoleCommand` and `Player:ConCommand`". Entries relevant here:
  - `connect` — "Could connect to specified server without the client's consent."
  - `askconnect_accept` — "Could accept a redirect request without the client wanting to be redirected."
  - `map`, `maxplayers`, `killserver`, `lua_run_cl`, `exec`, `alias`, `bind`, `name`, `sv_cheats`, `quit`, `gameui_hide`, `gameui_preventescapetoshow`.
  - Not on the list: `retry`, `disconnect`, `changelevel`, `sv_password`, `hostname`, `password`.
- Errors: `RunConsoleCommand: Command is blocked! (<name>)`; `ConCommand blocked! (<name>)`. [wiki]
- `Player:SendLua` (Server, script ≤ 6000 bytes) runs client Lua [wiki], so it is subject to the same block. [inference]

### 1.2 `permissions` library

| Function | Realm | Behaviour |
| --- | --- | --- |
| `permissions.AskToConnect(address)` | Client | "Requests the player to connect to a specified server. The player will be prompted with a confirmation window." Adds `:27015` if no port. |
| `permissions.IsGranted(permission)` | Client and Menu | Added 2021.06.09. Valid: `"connect"`, `"voicerecord"`. |
| `permissions.EnableVoiceChat(enable)` | Client | Prompt; used by TTT traitor voice. |
| `permissions.Grant(permission, temporary)` | Menu | Grants to the current server. |
| `permissions.Revoke(permission, ip)` | Menu | |
| `permissions.Connect(ip)` | Menu | Used internally by `AskToConnect`. |
| `permissions.GetAll()` | Menu | Permanent ones stored in `settings/permissions.bin`, keyed by server IP. |

Sources: wiki pages `permissions.*`; `Global.RequestConnectToServer` (Menu, internal): "If the server has the permission "connect" granted, it will instantly connect you to the server. If the permission is not granted ... it opens a confirmation window".

Exact behaviour from `lua/menu/openurl.lua` [repo]:

1. `RequestConnectToServer(serverip)` (called from engine): if `permissions.IsGranted("connect")` → `permissions.Connect(serverip)` immediately; else open the "askconnect" dialog.
2. Dialog text: title "Do you want to connect to this server?", text "The server you are playing on has requested you to connect to the following server. Do you wish to continue?" (`main_menu.properties` lines 467–468). It pings the target and shows `name, players/maxplayers, map, ping` or "Server failed to respond!".
3. Buttons: **Disconnect**, **Nope**, **Yes**, checkbox **"Don't ask again for this server"**. The Yes button is disabled for the first 1 second (`self.StartTime + 1 > SysTime()`).
4. Yes + checkbox → `permissions.Grant("connect", false)` = permanent grant for the **current** server; later `AskToConnect` calls from that server connect without a prompt. Without checkbox → temporary (session) grant.
5. Nope + checkbox → denial remembered in `RememberedDenials` for the session, keyed by `type|address|engine.CurrentServerAddress()`.
6. Only one dialog at a time; repeated calls with the same address are ignored while open.
7. The dialog closes if the game UI is hidden (`AlwaysThink`).

Answers to the questions:

- Password: no password argument. [wiki] Whether running `RunConsoleCommand("password", "...")` on the client before `AskToConnect` works: **UNVERIFIED** (`password` is not on the blocked list). Alternative: do not use passwords; gate with `GM:CheckPassword` against a roster.
- Rate limits: none in Lua besides the single-dialog rule and the 1-second Yes delay. [repo] Engine-side limits: **UNVERIFIED**.
- Dedicated vs listen: no difference documented. In singleplayer the Disconnect button is hidden when `!IsInGame()`; whether `AskToConnect` works from singleplayer: **UNVERIFIED**.

### 1.3 Other ways

- `gui.OpenURL(url)` — Client and Menu. "URL to open, it has to start with either `http://` or `https://`." Clientside asks for confirmation. So `steam://connect/...` is not allowed. [wiki] A web page opened in the overlay that itself redirects to `steam://connect`: **UNVERIFIED**.
- Kick message: `Player:Kick(reason)` / `game.KickID(id, reason)` (Server) only show text (~498/483 chars). It can tell the player an address to type; it cannot redirect. [wiki]
- `Player:Redirect` does not exist on the wiki (page not found). Request #2089 asks for `Player:Reconnect` (open). [issue]

## 2. Server discovery from game Lua

- `serverlist.*` — Menu only (see §0.2). Menu code using it: `lua/menu/mainmenu.lua` (`GetServers` → `serverlist.Query`, `serverlist.PingServer`, `serverlist.PlayerList`, `serverlist.IsServerFavorite`). [repo]
- `GetServers` is a menu-state global defined in `lua/menu/mainmenu.lua`, not an engine API for game Lua. [repo]
- Client and server realms cannot query the master server through any documented API. [wiki: no Shared/Client function found] Use your own HTTP directory.

## 3. HTTP and realtime

- `HTTP(parameters)` — realm "Shared and Menu"; returns `false` if not queued (e.g. `-disablehttp`). [wiki `Global.HTTP`]
- `http.Fetch` / `http.Post` — "Shared and Menu"; wrappers around `HTTP` in `lua/includes/modules/http.lua`. [wiki, repo]
- Methods: GET, POST, HEAD, PUT, DELETE, PATCH, OPTIONS. Fields: `url`, `parameters`, `headers`, `body`, `type` (default `text/plain; charset=utf-8`), `timeout` (default 60). [wiki `Structures/HTTPRequest`]
- Private networks: "HTTP-requests to destinations on private networks (such as `192.168.0.1`, or `127.0.0.1`) won't work. To enable ... use `-allowlocalhttp`. (Dedicated servers only)". `Command_Line_Parameters`: "This only works on the server." [wiki] Consequence for player hosting: the backend must have a public address.
- Status ≥ 400 still calls success; failure messages `invalid url`, `invalid request` ("Steam HTTP lib failed to create a HTTP request"), `error`, `unsuccessful`. [wiki `http.Fetch`] → HTTP goes through Steam's HTTP library. [inference]
- Large bodies "may return an `unsuccessful` error. Try using the Range header". Exact size limit: **UNVERIFIED**.
- Duplicate header names unsupported (bug #2232). Blacklisted headers: host, expect, content-length, proxy-authenticate, accept-charset, connection, accept-encoding, origin, date. [wiki]
- Request rate limits: none documented — **UNVERIFIED**. Steam HTTP domain allowlist: none documented — **UNVERIFIED**.
- WebSockets: `require` — "Binary modules can't be installed as part of an addon and have to be put directly into `garrysmod/lua/bin/`" [wiki `Global.require`]. GWSockets README: server binary `gmsv_gwsockets_*`, client works if renamed `gmcl_gwsockets_*` but must be installed manually. <https://github.com/FredyH/GWSockets>. So: Workshop clients cannot use websockets. Player hosts also would have to install a binary manually. Realtime for clients = HTTP polling, or a WebSocket inside a DHTML page (CEF supports WebSocket; Awesomium status UNVERIFIED) with `AddFunction` bridging to Lua. [inference]

## 4. Identity

- Engine verifies SteamID server-side: `GM:NetworkIDValidated(name, steamID, ownerID)`, `Player:IsFullyAuthenticated()` ("always be true for singleplayer and the listen server host"), `Player:OwnerSteamID64()` (family sharing). [wiki]
- No client auth ticket API (requests #2279 open). [issue]
- Implication on dedicated servers you control: route backend calls through the game server (server holds the API secret, sends validated SteamIDs). On player-hosted servers the host holds that code, so this does **not** give trust (§0.5). [inference]

## 5. Steam social features in Lua

- `Player:GetFriendStatus()` — Client; returns "friend", "blocked", "none", "requested", "error_nofriendid". Only for `Player` entities on the server. [wiki]
- `steamworks` — 19 functions, Workshop/UGC + `RequestPlayerInfo` (Client and Menu) / `GetPlayerName`. No friends list, invites, rich presence, or lobbies. [wiki]
- Friends permission request #2060 closed as duplicate; robotboy655 points to `GetFriendStatus`. [issue]
- Rich presence exists at engine level (requests #1164, #1292) but has no Lua API. [issue]

## 6. Menu realm

- Wiki `States`: "Menu modifications and addons are not officially supported, thus running menu state code requires overriding one of the engine's Lua files." Menu state files: `lua/includes/init_menu.lua`, `lua/derma/init.lua`, `lua/menu/menu.lua`, `lua/vgui/*.lua`. [wiki]
- `lua/menu/menu.lua` includes a fixed list of files; no addon autorun. [repo]
- What a gamemode can change in the menu: `gamemodes/<gm>/backgrounds/*.jpg` (`lua/menu/mainmenu.lua` ~line 147), `gamemodes/<gm>/logo.png` (`html/template/main.html` line 8), `icon24.png` in server browser, and New Game `"settings"` from `gamemodes/<gm>/<gm>.txt` (`UpdateServerSettings`). [repo]
- Conclusion: the lobby browser must run in the client realm, inside a running game session. With player hosting, that session can be the player's own singleplayer/listen session started with your gamemode (the "hub" is local). [inference]

## 7. In-game UI

- Derma: native, always available. [wiki]
- `HTML` (Client) / `DHTML` (Client and Menu): web engine; "Running Lua code is disabled by default" (`DHTML:SetAllowLua`). `DHTML:AddFunction(library, name, callback)` must be called after the document loads; return values via a JS callback are relevant for the x86-64/CEF branch (issue #3995 link in wiki). `asset://garrysmod/...` for local files. Blocked URL extensions: `.exe .bat .dll .zip .mp3 .swf`. [wiki `DHTML`, `DHTML:AddFunction`, `HTML`]
- Web engine [wiki `HTML_Web_Engine`]: Windows (all branches) CEF 86; Linux `main`/`dev` Awesomium (Chromium 17-like, TLS 1.0 only); Linux `x86-64` and macOS CEF 80 (crash on launch; fixed by third-party GModPatchTool → CEF 137). Recommended detection: check user agent for "awesomium".
- Recommendation: Derma for the core lobby flow (works everywhere); DHTML optional. [inference]

## 8. Several matches inside one server

- `Entity:SetPreventTransmit(player|CRecipientFilter|table, bool)` — Server; must also be applied to children; table/filter since March 2024; issue #1736. Only blocks transmission, cannot whitelist a `TRANSMIT_NEVER` entity. [wiki, `Controlling_Entity_Transmission`]
- `Entity:SetCustomCollisionCheck` + `GM:ShouldCollide` — must return consistent results; call `Entity:CollisionRulesChanged`; bug #642 "can cause all physics to break". [wiki]
- `GM:SetupPlayerVisibility` / `AddOriginToPVS` for PVS. [wiki]
- Still shared and needing manual filtering: bullets/traces, sounds, effects, voice/chat, map entities and map logic, edict and player limits (`maxplayers` ≤ 128 from menu). [inference]
- Existing public library: `FJS-01/FJS-DIMENSION-API` (GitHub, 5 stars, README: "UNSTABLE - ACTIVE DEVELOPMENT"). Not evaluated. A well-known mature dimensions addon: **not found**.
- Relevance for player hosting: one listen server = one match is simpler; instancing only makes sense for a "party lobby + match" in the same session. [inference]

## 9. Server-side controls

- `changelevel` — allowed (not blocked); `map` — blocked. [wiki]
- `sv_password` — not blocked; settable at runtime from server Lua. `GM:CheckPassword` for custom gating. [wiki]
- `maxplayers` — blocked; fixed at start. `game.MaxPlayers()` (Shared) reads it. [wiki]
- `game.GetIPAddress()` — Shared; bug #3001 (`0.0.0.0:port` early on first start). [wiki]
- Heartbeat: `timer` + `HTTP` POST from server realm to the backend. [wiki] (Public backend only.)
- Launching processes: `os` library "only used in Garry's Mod for date & time operations". [wiki `os`] Binary modules could, but require manual install in `lua/bin`. [wiki `Global.require`]

---

## Open items to test in-game

1. `permissions.AskToConnect("p2p:<steamid64>")` — does it connect, or does the `:27015` default break it?
2. Is a listen server's P2P address the host's SteamID64?
3. `RunConsoleCommand("password", x)` on the client before `AskToConnect` — is it used for the connect?
4. `permissions.AskToConnect` from singleplayer (local "hub").
5. Do P2P listen servers appear in `internet` server list queries?
6. `game.GetIPAddress()` value on a P2P listen host behind NAT.
7. HTTP response size limit and any rate limiting.
