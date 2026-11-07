# 09 - Lua file shadowing between addons and the gamemode

Read-only research for `design/01-extensibility.md`, decision 8 ("Consequence (accepted): two addons shipping the same
`<kind>/<id>.lua` path shadow each other ... lets a Workshop addon replace a built-in entity on purpose") and open
question 11. Nothing was run in game.

Evidence labels:

- **[wiki]**: Facepunch wiki, raw text fetched 2026-11-06 via `https://wiki.facepunch.com/gmod/<Page>?format=text`.
- **[src]**: source of public repositories. `gmod:` = the public repository `Facepunch/garrysmod` at commit
  `ad80234` (2026-10-15), `gmad:` = the public repository `Facepunch/gmad` master, `include/AddonWhiteList.h`
  (fetched raw from GitHub).
- **[forum/issue]**: GitHub issue or forum thread, with URL.
- **[inference]**: follows from the cited evidence, not observed.
- **[unverified]**: not found in any source; the engine (filesystem, mounting, Lua datapack) is closed source.

## TL;DR

| # | Question | Verdict |
| --- | --- | --- |
| 1 | Which same-path file wins on the server | One file wins (first search path in mount order). Addons are searched before loose `garrysmod/` files [wiki]. Between Workshop addons the order is "the order Steam gives them" (subscription order or the user's Steam load order) [forum/issue]. Legacy folder vs Workshop `.gma` order: [unverified]. Not documented as a contract; not controllable by the addon author. |
| 2 | Which file the client runs in multiplayer | The client runs only what the server sent through `AddCSLuaFile` (the Lua string table / datapack); `LUA` on the client lists only those files [forum/issue]. With `sv_allowcslua 0` local client addons cannot inject or override files under that path [wiki + forum/issue]. The server's winner is what every client gets [inference]. Singleplayer / listen host: the client sees the local filesystem, same winner as the server [inference]. |
| 3 | Are `gamemodes/<gm>/...` files on `LUA` | Yes, as `<gm>/gamemode/...` (vanilla TTT scans `terrortown/gamemode/lang/*.lua` with `"LUA"`) [src]. `gamemodes/<gm>/entities/{weapons,entities,effects}` are merged into the `LUA` root as `weapons/...` etc. [wiki + src]. Convention for addon-extensible content: ship it under `lua/<gm>/...` in the same Workshop item, as public gamemodes that ship content under `lua/` do. |
| 4 | Can a gamemode-type Workshop addon ship `lua/` | Yes. The gmad whitelist allows `lua/*.lua` regardless of `addon.json` `type` [src]. Restriction: inside `gamemodes/<gm>/` only `gamemode/*.lua` and `entities/{effects,weapons,entities}/*.lua` are allowed Lua locations, so a custom folder like `gamemodes/<gm>/modes/` would be rejected [src]. |
| 5 | Can an addon reliably win shadowing | No. Between two Workshop addons the winner depends on each machine's Steam mount order, which neither author controls [forum/issue + inference]. Treat same-path replacement as non-deterministic and not as an API. |

## 1. Same relative path in several mounted addons (server realm)

### Evidence

1. The filesystem is one merged virtual tree; same path means one file wins.
   - [wiki] `Global.include`, note on the argument: "the filesystem is shared across all addons, so a file named
     `lua/config.lua` in your addon may be overwritten by the same file in another addon." The same note is on
     `Global.AddCSLuaFile`.
   - [wiki] `Lua_Loading_Order`: "GMod combines all scripts into a virtual filesystem (one folder).
     `addon/myaddon/lua/entities/` and `gamemodes/base/gamemode/entities/entities/` will be merged with
     `lua/entities/`, so therefore the same path and name will override and/or conflict."
2. Precedence is search-path order.
   - [wiki] `File_Search_Paths`: `LUA` resolves to `lsv` / `lcl` / `LuaMenu` by realm; the `path` console command
     lists every search path, and "Content from paths that appear first will override content from paths that
     appear last."
   - [wiki] `Filesystem` (page marked unfinished): the `GAME` path is searched in this order: all `thirdparty`
     paths (including the virtual `garrysmod/workshop` folder), then `garrysmod/overrides/`, then `garrysmod/`,
     then mounted games, `download/`, `fallbacks/`.
   - [forum/issue] robotboy655 (Facepunch contributor) in
     <https://github.com/Facepunch/garrysmod-issues/issues/5481>: "Addon content should take precedence over local
     loose files in mounting order, see File_Search_Paths."
   - So an addon file beats a loose file in `garrysmod/lua/` or `garrysmod/gamemodes/` [wiki + forum/issue].
     Whether the `lsv` path follows exactly the same order as `GAME` is [unverified]; the wiki only documents
     `GAME` and `MOD` order.
3. Order between Workshop addons.
   - [forum/issue] robotboy655 in <https://github.com/Facepunch/garrysmod-issues/issues/5664>: "Addons are mounted
     in the exact order Steam gives them to the game." In #5709
     (<https://github.com/Facepunch/garrysmod-issues/issues/5709>): "The addon order is exactly as you have set it
     in your Steam Workshop mount order" (a Steam client feature, "more of a complaint to Valve").
   - [forum/issue] TiberiumFusion in #5664, tested with `whereis`: "If A and B both have the same file, and I sub
     to B first then A second, the colliding file from B will mount and the file from A will not, regardless of
     which addon has a higher/lower UGC ID." The same issue documents a period (December 2023) when the client
     realm mounted in UGC-id order instead, which Valve later reverted. So the order has changed silently before.
   - [forum/issue] robotboy655 in #5664: an addon that contains a non-whitelisted file is not mounted at all, which
     also changes who wins a collision.
   - [src] `gmod:garrysmod/lua/menu/problems/problems.lua:280-315` handles the engine hook `OnNotifyAddonConflict`
     (`addon1`, `addon2`, `fileName`) and shows the menu problem "Addon '%s' probably conflicts with addon '%s' due
     to both having the following files" (`gmod:garrysmod/resource/localization/en/main_menu.properties:122`).
     The engine therefore detects same-path collisions between Workshop items and treats them as a problem, not
     as a feature. Menu realm only, client machine only.
4. Legacy `garrysmod/addons/<folder>` vs Workshop `.gma`: no source states the relative order [unverified]. A 2017
   community thread claims legacy folders load alphabetically by folder name
   (<https://forums.ulyssesmod.net/index.php/topic,10343.0.html>) - user advice, not documentation [forum/issue].
5. Dedicated servers: order of Workshop items mounted from `host_workshop_collection` is [unverified].
6. `file.Find(..., "LUA")` returns the merged directory listing, one entry per name. Evidence is indirect: Sandbox
   (`gmod:garrysmod/gamemodes/sandbox/entities/weapons/gmod_tool/stool.lua:146`) iterates the result and includes
   each name once; duplicates would double-register tools [inference]. `include(path)` of that name loads
   the winning file only [wiki, `Global.include` note].

### Verdict

Deterministic per machine at a given moment (first search path wins), but the order is decided by the Steam client
mount order / subscription order, not by the addon author, is not documented as a stable contract, and has
changed once without notice. Addon over loose base files is documented; legacy vs Workshop is not.

## 2. Client realm in multiplayer

### Evidence

1. [forum/issue] robotboy655, <https://github.com/Facepunch/garrysmod-issues/issues/5481>: "Clientside, the `LUA`
   path will only include files that are `AddCSLuaFile()`'d." and "In multiplayer clientside Lua files are only
   loaded from the string table which is populated by `AddCSLuaFile`." The issue shows `file.Exists(..., "LUA")`
   returning `true` on the server and `false` on the client for a file that the client has locally (mounted with
   `game.MountGMA`) but the server did not send.
2. [wiki] `Global.include`: "This function will try to load local client file if `sv_allowcslua` is **1**."
   So with `sv_allowcslua 0` local files are not used.
3. [src] `gmod:garrysmod/gamemodes/sandbox/entities/weapons/gmod_tool/stool.lua:150`: "In multiplayer, the
   clientside filename is always lowercase (due to the Lua datapack)". The client listing comes from the datapack,
   not from the client's disk.
4. [forum/issue] <https://github.com/Facepunch/garrysmod-issues/issues/1798>: file contents received from the server
   "don't actually exist anywhere on the file system"; `file.Read` on the client fails for them.
5. Which version is sent: `AddCSLuaFile(path)` resolves `path` on the server's `lsv` search path, so it sends the
   same file the server's `include` sees [inference]; no source states it directly [unverified].
6. Singleplayer and the listen-server host: the client realm reads the local filesystem (issue #5471 is a
   singleplayer-only `LUA` path bug, <https://github.com/Facepunch/garrysmod-issues/issues/5471>), so the host's
   own mount order applies to both realms [inference].

### Verdict

In multiplayer with `sv_allowcslua 0`, the client's set of Lua files under `lua/<gm>/...` equals what the server
sent; local client addons cannot add or override them [forum/issue + wiki]. `sv_allowcslua 1` opens the door to
local files [wiki]. This is a consistency guarantee, not a security boundary against cheats [inference].

## 3. Gamemode folders on the `LUA` path

### Evidence

1. `gamemodes/<gm>/gamemode/` is visible on `LUA` with the relative path `<gm>/gamemode/...`.
   - [wiki] `Global.include`: "Absolute paths for gamemode files must include `<gamemode_folder_name>/gamemode/`."
   - [src] `gmod:garrysmod/gamemodes/terrortown/gamemode/lang_shd.lua:11-12`:
     `file.Find(dir .. "/gamemode/lang/*.lua", "LUA")` with `dir = GM.FolderName`.
   - Whether files directly under `gamemodes/<gm>/` (outside `gamemode/`) are on `LUA` as `<gm>/...` is
     [unverified]; it is irrelevant for Workshop because gmad rejects them (question 4).
2. `gamemodes/<gm>/entities/` is merged into the `LUA` root while the gamemode is active.
   - [wiki] `Lua_Loading_Order` note quoted in question 1.
   - [wiki] `Structures/SWEP`, `Folder`: "This should always be `weapons/weapon_myweapon`".
   - [src] Sandbox's tool gun lives in `gmod:garrysmod/gamemodes/sandbox/entities/weapons/gmod_tool/` with stools in
     `.../gmod_tool/stools/`, and `stool.lua:146` scans `SWEP.Folder .. "/stools/*.lua"` on `"LUA"`. That single
     scan finds both the gamemode's stools and addons' `lua/weapons/gmod_tool/stools/*.lua` [src + inference].
3. Convention for addon-extensible content: a public gamemode can ship one Workshop item with both
   `gamemodes/<gm>/` and `lua/<gm>/<kind>/`, keep its built-in content in `lua/<gm>/<kind>/`, and scan that folder
   on `"LUA"`; third-party addons drop files in the same `lua/` folder. TTT2 is one public gamemode that ships
   content under `lua/` this way. This is the same pattern as decision 8.

### Verdict

Use `lua/<gm>/<kind>/` for built-in content, shipped inside the gamemode's Workshop item. The
`gamemodes/<gm>/gamemode/...` alternative works on `LUA` but has a different prefix, so the scanner would have to
scan two roots.

## 4. `lua/` inside a gamemode-type Workshop addon

### Evidence

1. [wiki] `Workshop_Addon_Creation`: allowed top-level folders are `backgrounds`, `data_static`, `gamemodes`, `lua`,
   `maps`, `materials`, `models`, `particles`, `resource/fonts/`, `resource/localization/`, `scenes`,
   `scripts/vehicles/`, `sound`. `type` is metadata (one of `ServerContent`, `gamemode`, ...); the page lists no
   rule that ties allowed folders to `type`.
2. [src] `gmad:include/AddonWhiteList.h`:
   - line 16: `"lua/*.lua"` (any depth; the wildcard also matches `lua/autorun/...`);
   - lines 53-56: `"gamemodes/*/gamemode/*.lua"`, `"gamemodes/*/entities/effects/*.lua"`,
     `"gamemodes/*/entities/weapons/*.lua"`, `"gamemodes/*/entities/entities/*.lua"`. No other Lua location under
     `gamemodes/*/` is allowed;
   - line 105: "This whitelist only serves to warn about bad files at upload stage - the game has its own
     whitelist." The game's own whitelist is closed source [unverified], and per #5664 an addon with a
     non-whitelisted file is not mounted at all [forum/issue].
3. Public gamemodes that ship content under `lua/` (question 3) are working examples of a gamemode addon that
   ships `lua/`.
4. [wiki] `Steam_Workshop_Rules`: the `gamemode` tag must not be abused (content packs must use `ServerContent`).
   An extension pack for our gamemode should be tagged accordingly, not `gamemode` [wiki + inference].

### Verdict

Allowed, no type-based restriction. Do not put Lua in custom folders under `gamemodes/<gm>/` (for example
`gamemodes/<gm>/modes/`); gmad rejects them.

## 5. Can an addon reliably win shadowing

### Evidence

1. Workshop vs Workshop: the winner is the item mounted first on that machine, and the order comes from the Steam
   client (subscription order or the user's Steam "load order") [forum/issue, #5664, #5709]. The authors of the two
   addons do not control it. On a dedicated server the operator's setup decides it, and its rule is [unverified].
2. If the gamemode itself is distributed as a Workshop item (the normal case), its built-in `lua/<gm>/modes/tdm.lua`
   and a third-party `lua/<gm>/modes/tdm.lua` are two Workshop files of equal standing. The "addon beats loose base
   files" rule from question 1 does not help, because the built-in is not a loose file [inference].
3. The rule "addon beats loose files" makes the replacement reliable only when the gamemode is installed loose in
   `garrysmod/gamemodes/` (development checkout, or a server that extracted it) [wiki + inference]. Note that loose
   install puts built-ins under `garrysmod/lua/<gm>/` only if the gamemode copies them there; a gamemode folder
   alone cannot ship `lua/` [inference].
4. Renaming tricks (number prefixes on folder names) affect only legacy folders, are community advice, and do not
   apply to Workshop items [forum/issue, Ulysses thread].
5. The engine reports collisions as a "probably conflicts" problem to the player (question 1, item 3), so a
   deliberate replacement by path will show a warning in the main menu of every client that subscribed to both
   items [src + inference].
6. In multiplayer the server's winner is propagated to clients (question 2), so server and clients agree. The
   result is still not predictable for the addon author [inference].

### Verdict

No reliable way. Shadowing by identical path is non-deterministic from the author's point of view and is flagged
by the engine as an addon conflict.

## Implications for design/01-extensibility.md decision 8

1. The first half of the accepted consequence holds: two addons shipping the same `<kind>/<id>.lua` shadow each
   other and only one file is loaded and registered [wiki + src].
2. The second half does not hold as a supported mechanism: "a Workshop addon may replace a built-in entity on
   purpose by shipping its own `modes/tdm.lua`" works only if Steam happens to mount that addon before the
   gamemode's Workshop item on the server (and on the host in listen/singleplayer). It is not deterministic, it
   can change without notice, and it triggers the main-menu "addon conflict" warning.
3. Suggested change (for the design owner to decide):
   - Keep shadowing as a documented accepted risk ("two items with the same path: undefined which one wins; do
     not do this").
   - Remove "Same-path file - Replace an entity completely" from the extension-mechanisms table, or mark it
     "unsupported".
   - Supported ways to replace a built-in: ship the replacement under a different id with `Base = "<builtin>"`
     and veto the built-in in `COD_PreRegister` (return `false` for `kind, id`), or patch the built-in's fields in
     `COD_PreRegister`. Both are deterministic because they do not depend on file mount order.
   - Optional: the core can detect a shadowed built-in on the server by comparing `file.Find` with an `"<gm-title>"`
     search path (the per-addon search path named after the GMA title, wiki `File_Search_Paths`) and log a
     warning. This is [unverified] for loose installs and is a nice-to-have only.
4. Decision 8's layout (`lua/<gm>/<kind>/`, built-ins inside the gamemode's Workshop item) is confirmed as viable
   and matches how public gamemodes ship content under `lua/` (questions 3 and 4). This closes the second half of open question 11.

## To verify in game

Run on a listen server, then repeat on a dedicated server with a client connected.

1. Workshop vs Workshop order:
   - Create two local GMAs with `gmad.exe create` (A and B), each with `lua/codtest/modes/tdm.lua` that prints its
     own name at include time.
   - Mount both with `game.MountGMA` in order A, B on the server, then call `include("codtest/modes/tdm.lua")`.
     Record which name prints. Repeat with order B, A.
   - Also run `whereis lua/codtest/modes/tdm.lua` and `path` in the console; record where the `lsv` entries of A, B
     and `garrysmod/` appear.
   - Caveat: `game.MountGMA` order is not the same mechanism as Steam subscription order; for the real case,
     publish two private Workshop items, subscribe in both orders and repeat.
2. Legacy folder vs Workshop: put the same file in `garrysmod/addons/codtest_legacy/lua/codtest/modes/tdm.lua`
   and in one mounted Workshop item; check which one `include` loads and which one `whereis` reports.
3. Loose base vs addon: put the file in `garrysmod/lua/codtest/modes/tdm.lua` and in a legacy addon folder;
   confirm the addon wins (expected from the wiki).
4. Client consistency: on a dedicated server with `sv_allowcslua 0`, `AddCSLuaFile` the winning file; on the
   client, mount a GMA that contains a different `lua/codtest/modes/tdm.lua`, reconnect, and confirm the client
   runs the server's version and `file.Find("codtest/modes/*", "LUA")` on the client lists only server-sent files.
5. Conflict warning: subscribe to two Workshop items with the same Lua path and confirm the main-menu
   "probably conflicts" problem appears.
6. Dedicated server order: with two items in `host_workshop_collection`, swap their position in the collection and
   record which file the server loads.

### Verified in game (2026-11-07, Steam Deck, Proton)

Listen server on the Steam Deck (Windows build through Proton). Measured with `scripts/deck/cp1.sh`, steps 7.1
and 7.3: the script builds temporary GMAs and a temporary legacy addon folder, mounts the GMAs with
`game.MountGMA` through the dev command `pw_cp1_mount`, and reads the winner from what `include` of the shared
path returns (`pw_cp1_include`). `whereis` and `path` were not recorded.

| Test above | `cp1.sh` step | Result |
| --- | --- | --- |
| 1, Workshop vs Workshop order (`game.MountGMA` part) | 7.1 "test 1, GMA vs GMA (game.MountGMA)" | Two GMAs with the same Lua path: **the last mounted GMA wins** (mount A, B: B; mount B, A: A) |
| 2, legacy folder vs Workshop | 7.3 "test 2, legacy addon folder vs mounted GMA" | A legacy `addons/<folder>` and a GMA with the same Lua path: **the legacy folder wins** |

Naming: the script numbers the tests as this section does, but names them by mechanism. Its test 1 is only the
`game.MountGMA` half of test 1 here; its test 2 uses a GMA mounted with `game.MountGMA` in place of a subscribed
Workshop item. Both results therefore describe `game.MountGMA`, not Steam's subscription mount order. The
"last mounted wins" result also differs from the "first search path wins" reading of question 1, which was about
Steam's mount order.

Still open:

1. Tests 1 and 2 with real Workshop items (`cp1.sh` 7.2 and 7.4, MANUAL).
2. Test 4 on a dedicated server with `sv_allowcslua 0` (`cp1.sh` 7.5, MANUAL; the script's instructions use a
   client legacy folder in place of a client-mounted GMA).
3. Tests 3, 5 and 6 are not part of `cp1.sh`.
