# Map API: `MAP`, map data, spawns, `pw_mark`, map list, navmesh generation

Status: frozen on 2026-11-07, changes only through the orchestrator.

Extended on 2026-11-07 after T-2.7, T-2.8, T-2.9 and T-2.11: the items of "Open in design" that the lane agents
decided in code (items 1, 3, 4, 5 and 8, and the function set of item 11) are now in the main text. Extended again on
2026-11-07 after T-2.4, T-2.10 and T-2.12 (`PW.Map.ModeFits`, `pw_mark`, navmesh generation): items 2, 6 and 9 are
decided in code and item 10 is partly done. The code wins over any description here. Values marked "lane agent" are
gameplay or API details the orchestrator recorded after the merge.

Contract for the `map` lane (T-2.7 to T-2.12). It sits on top of `core.md` and `modes.md`. Every item cites its
decision as `<file> d.<n>` (files under `design/`). What the design leaves open is listed under "Open in design" at
the end and is **not** part of the contract yet.

## Ownership

| Item | Lane | Where |
| --- | --- | --- |
| Kind `maps` (the declaration) | core files, see "Core changes needed" | `lua/privatewar/kinds/maps.lua` |
| Map files | map | `lua/privatewar/maps/<map>.lua` |
| Module `mapdata`: `PW.Map`, auto-detection, the spawn layers, the navmesh area cache and the navmesh fallback sampling | map | `lua/privatewar/modules/mapdata/` |
| Module `spawns`: `PW.Spawns` | map | `lua/privatewar/modules/spawns/` |
| Module `maplist`: `PW.MapList` | map | `lua/privatewar/modules/maplist/` |
| Module `navgen`: navmesh generation only (T-2.12; the fallback sampling is in `mapdata`) | map | `lua/privatewar/modules/navgen/` |

Module ids are the directory names of `TASKS.md` "Lanes and ownership" (`modules/mapdata/`, `modules/spawns/`,
`modules/maplist/`, `modules/navgen/`); the namespace of each is below. The design says "the map module" and "the `spawns` module"
(`03-mapdata.md` d.6, d.7).

## Principles

- The game works on any map. Map data is optional and improves a map; its absence never blocks play
  (`03-mapdata.md` d.1).
- Source layers, a higher layer overrides a lower one (`03-mapdata.md` d.3):
  1. the Lua map file `lua/privatewar/maps/<map>.lua`;
  2. auto-detection from map entities (team spawns of CS:S, HL2DM and TF2; DM spawns from `info_player_deathmatch`);
  3. the fallback: spawn points from random navmesh areas (FFA-style dynamic spawn).
- A generator of objective points is after MVP; the layer model leaves room for it as the
  lowest-priority source (`03-mapdata.md` d.4).
- The map module only stores mode data; it does not know what a "Domination flag" is (`03-mapdata.md` d.6).

## Kind `maps` and the `MAP` table

Folder `maps/`, class table `MAP`, data only (`03-mapdata.md` d.2). The id is the map name (`game.GetMap()`), as
for every kind (`01-extensibility.md` d.8). Shipped by map packs or written by anyone; there is no editor in MVP
(`03-mapdata.md` d.2).

```lua
-- lua/privatewar/maps/de_dust2.lua
MAP.Spawns = {
    [1] = { { pos = Vector(-1200, 2400, 64), yaw = 90 }, ... },
    [2] = { ... },
}
MAP.Modes = {
    dom = { flags = { A = Vector(...), B = Vector(...), C = Vector(...) } },
}
```

| Field | Type | Meaning | Source |
| --- | --- | --- | --- |
| `Spawns` | `table<integer, { pos: Vector, yaw: number }[]>` | Spawn points by team index; `[1]`, `[2]` in the example | `03-mapdata.md` d.2 |
| `Modes` | `table<string, table>` | Mode-specific data by mode id (`MAP.Modes.<mode id>`); opaque to the map module | `03-mapdata.md` d.2, d.6 |

- No required fields: map data is optional (`03-mapdata.md` d.1).
- Other fields are not specified (landing zones, a generator output): `03-mapdata.md` "Goal and
  scope" mentions landing zones; no field is designed.
- The class table of the kind is `MAP`. `01-extensibility.md` d.12 lists the class table of `maps/` as "data only";
  `03-mapdata.md` d.2 (the subsystem's own decision, which d.12 defers to) and `TASKS.md` use `MAP`.
- Enable ConVar `pw_map_<id>_enabled` follows from `Global = "MAP"` (`01-extensibility.md` d.11).
- Ids are lowercase letters, digits and `_` (`core.md` "Entity files"). The map data file id is derived from the map
  name: see "Map data file id".
- `PW.Maps` is the registry accessor (`PW.Loader.AccessorName`); the module namespace is `PW.Map` (singular).
- The `PW_PreRegister` hook runs on map files like on every entity (`01-extensibility.md` d.10): another addon can
  patch someone else's map data.

## `PW.Map` (module `mapdata`)

Types: `lua/privatewar/types/map.lua`.

| Function | Realm | Contract |
| --- | --- | --- |
| `PW.Map.AnyTeam` | shared | The constant `0`: the team index of spawn points that belong to no team (FFA and deathmatch spawns); usable by every team |
| `PW.Map.Id(mapName) -> string` | shared | The map data file id of a map name (see "Map data file id") |
| `PW.Map.Get(mapName?) -> MAP?` | shared | The map data entry of a map (default: the current map, `game.GetMap()`), looked up by `PW.Map.Id`. `nil` without a file or when the entry is disabled |
| `PW.Map.GetModeData(modeId) -> table?` | shared | The `MAP.Modes.<modeId>` table of the current map. Returns the first existing entry along the mode's `Base` chain: `hardcore_dom` has no entry, its base `dom` has one, so it gets `MAP.Modes.dom`. `nil` when no mode of the chain has an entry, when the map has no data file, or when the entry is not a table (`03-mapdata.md` d.6) |
| `PW.Map.GetSpawns() -> table<integer, { pos: Vector, yaw: number }[]>` | server | The spawn points of the current map by team index, after the layers of "Spawn sources". Empty when no layer has a point. Do not modify the result |
| `PW.Map.GetDetectedSpawns() -> ...` | server | Layer 2 only: the auto-detected spawn points, grouped like `Spawns`. Collected once per map at `InitPostEntity` (and on first use if the cache is empty); the cache survives `pw_reload`. Do not modify the result |
| `PW.Map.GetNavSamples() -> { pos: Vector, yaw: number }[]` | server | The navmesh fallback points (layer 3), any team. Empty without a navmesh or before the navmesh was read. Do not modify the result |
| `PW.Map.ModeFits(mode, mapName) -> boolean, string?` | shared | Whether a mode is offered on a map, for any map that has a data file (not only the current one); see "`MODE.MapData` and `MODE:ValidateMapData`" |
| `PW.Map.PauseNav(paused)` | server | Navmesh generation (`navgen`, below) calls it: `true` pauses the fallback sampler and drops the cached navmesh areas (the generation destroys the navmesh; `GetNavAreas` is empty, the already sampled points stay); `false` resumes it. The map reloads when generation ends, which starts the sampling over |
| `PW.Map.GetNavAreas() -> CNavArea[]` | server | Every navmesh area, read once after the map loaded (`navmesh.GetAllNavAreas` allocates a new table each call, so read this instead; for the bots). Empty without a navmesh or before it was read. Do not modify the result |

- Intended call: `PW.Map.GetModeData(self.ClassName).flags` inside `MODE:Start()` (`03-mapdata.md` d.6).
- The `Base` chain is the mode's resolved `BaseClass` chain (`core.md` "Fields every entity has").
- `PW.Map.Get(mapName)` reads the entry of any map that has a data file (the registry holds every map file); the query
  "is mode X offered on map Y" is `PW.Map.ModeFits`.

### `MODE.MapData` and `MODE:ValidateMapData`

Declared by the mode (`modes.md`), evaluated by the map lane (`03-mapdata.md` d.6):

```lua
MODE.MapData = true    -- needs MAP.Modes.dom on the map

function MODE:ValidateMapData(data)   -- data = MAP.Modes.dom
    if not data.flags or table.Count(data.flags) < 2 then
        return false, "Domination needs at least 2 flags"
    end
    return true
end
```

- With `MODE.MapData = true` the mode is offered on a map only if `MAP.Modes.<mode id>` exists (through the `Base`
  walk) and passes `ValidateMapData`: in Custom, in the vote and in playlists (`03-mapdata.md` d.6).
- TDM, FFA and Kill Confirmed do not set it: spawns exist on every map (`03-mapdata.md` d.3, d.6).
- A mode with `MapData = true` and no `ValidateMapData`: an existing entry is accepted (the method is optional,
  `modes.md`).
- A playlist with `Maps = nil` uses only maps that fit its modes (`03-mapdata.md` d.6; `modes.md` "Playlists").
- Invalid data: one log line (map, mode, reason); the mode is hidden on that map (`03-mapdata.md` d.6;
  `01-extensibility.md` d.15 behaviour).
- `ValidateMapData` is called through `PW.Call` (`00-core.md` d.6). An error in a mode that is not the active mode
  disables that mode until the map changes (`core.md` "Entity calls"), one log line; for the active mode it aborts
  the match. Validation is therefore a lobby and vote operation, run before a mode becomes active.
- Test (`TASKS.md` T-2.4, T-2.7): `ValidateMapData` rejects fewer than 2 flags; the mode is hidden on a map without
  data; `GetModeData` walks the `Base` chain.

### `PW.Map.ModeFits(mode, mapName)`

Decided (lane agent, T-2.4); the cross-map query of the lobby, the vote and the playlists (`PW.Lobby._Fits`, the playlists
module's fits test; the vote asks the latter). `mode` is the mode table, `mapName` any map name. Returns `true`, or `false` and
a reason:

| Case | Result |
| --- | --- |
| `mode.MapData ~= true` | `true` (no data needed) |
| the map has no data file (`PW.Map.Get` is `nil`) | `false`, `no map data` |
| no `MAP.Modes.<id>` along the mode's `Base` chain (the same walk as `GetModeData`) | `false`, `no data for <mode id>` |
| the mode has no `ValidateMapData` method | `true` |
| `PW.Call(mode, "ValidateMapData", data)` returns `true` | `true` |
| any other answer | `false`, the reason it gave (`ValidateMapData failed` when it is not a string); one log line per map and mode pair (`map <map>: invalid data for mode <id>, the mode is hidden there: <reason>`), not repeated |

Absent data is not logged, only invalid data is. The test does not check that the map is installed or that the mode is
enabled: its callers do (`modes.md` "Playlists").

## Spawn sources

Module `mapdata` (T-2.7) builds the spawn list of the current map from the layers above (`03-mapdata.md` d.3).

- Layer 1, the map file: `MAP.Spawns`. Only valid points count: a team index that is an integer `>= 0`, a list of
  tables with a `Vector` `pos` (`yaw` a number, else `0`); invalid points and empty lists are dropped. When at least
  one valid point exists, layer 1 is the result as it is (it replaces layers 2 and 3, nothing is merged).
- Layer 2, auto-detection (`PW.Map._SpawnClasses`, lane agent decision, T-2.7): the engine teams 2 and 3 of CS:S
  (T, CT), HL2DM (Combine, Rebels) and TF2 (RED, BLU) become teams 1 and 2.

  | Entity class | Team |
  | --- | --- |
  | `info_player_terrorist`, `info_player_combine` | 1 |
  | `info_player_counterterrorist`, `info_player_rebel` | 2 |
  | `info_player_teamspawn` (TF2) | `TeamNum` keyvalue 2 gives 1, 3 gives 2; any other value gives `0` |
  | `info_player_deathmatch` | `0` (`PW.Map.AnyTeam`) |
  | `info_player_start`, `gmod_player_start` | `0`, generic: used only when the map has none of the other classes |

  Records of other classes are ignored. The pure function is `PW.Map._SpawnTeam(class, teamNum?)`; grouping is
  `_GroupSpawns` (`TASKS.md` T-2.7, mandatory case). The list is the research list of `notes/11-navmesh-generation.md`
  ("Recommendations", step 4).
- Layer 3, the fallback (lane agent decision, T-2.8): about 200 points sampled from navmesh areas, see "Navmesh
  fallback" below. It is added only when layer 2 has fewer than `PW.Map._NavRules.minSpawns` (8) points in total: the
  samples are appended to the `AnyTeam` (0) list, the team lists of layer 2 are kept.

### Navmesh fallback

Thresholds `PW.Map._NavRules` (lane agent decision, T-2.8; `03-mapdata.md` d.7):

| Field | Value | Meaning |
| --- | --- | --- |
| `minSide` | 32 | An area narrower than this on either side is too small (units; the player hull is 32 wide) |
| `maxSlope` | 30 | An area steeper than this is too steep (degrees, from the plane of its four corners) |
| `count` | 200 | At most this many samples |
| `minSpawns` | 8 | Fewer detected points than this add the samples (see layers) |
| `budgetMs` | 100 | Time one sampling pass should stay under (checked by the in-game smoke test) |

- An area is excluded when it is too small, steep, underwater, or has the crouch attribute (`NAV_MESH_CROUCH`).
- The samples are the centres of the eligible areas, spread evenly over the list (one slot per point); a centre where
  a standing player hull does not fit (a hull trace at the centre lifted by the step height, `MASK_PLAYERSOLID`) is
  replaced by the next area of its slot. Each point faces the middle of all samples.
- The sampling runs once per map, in the first `Think` after `InitPostEntity` (the engine loads the `.nav` after it;
  retried up to 5 times, 1 s apart, while the area count is 0). The areas are cached for `PW.Map.GetNavAreas`. Without
  a navmesh: one log line (`map <name>: no navmesh; navmesh spawn fallback unavailable`), no samples.
- Pausing the sampler during navmesh generation (`notes/11-navmesh-generation.md`, "What the server does on confirm",
  step 2): `PW.Map.PauseNav(true)`, called by the `navgen` module (see "Navmesh generation").

## `PW.Spawns.Pick(ply, opts)` (module `spawns`)

`PW.Spawns.Pick(ply, opts?) -> { pos: Vector, yaw: number }?` (server) is the shared logic behind `PW_SelectSpawn`
(`03-mapdata.md` d.7). Types: `lua/privatewar/types/spawns.lua`.

- The module answers the question hook `PW_SelectSpawn(ply)` itself (a module listener, during `LIVE`, for player
  entities only) with `Pick(ply)` and default `opts`; the hook is fired by the `match_rules` module from
  `GM:PlayerSelectSpawn` (`modes.md` "Match rules module"), which applies the `{ pos, yaw }` answer when the player
  spawns. A mode may answer the hook first, or call `Pick` with its own `opts`.
- Return value: a new table `{ pos, yaw }` (`PW.SpawnPoint`), or `nil` (no `mapdata` module, the map has no point, or
  every sampled point is hull-blocked): the base gamemode then chooses. The chosen point is remembered as recently
  used.

`opts` (all optional; lane agent decision, T-2.9):

| Field | Default | Meaning |
| --- | --- | --- |
| `first` | `true` while the player has not spawned during this `LIVE` | The first spawn of the match: use the team's own zone |
| `all` | `true` for respawns and for modes without teams, else `false` | Use every point of the map |
| `teamBonus` | `true` when the active mode has teams (FFA: `false`) | Reward nearby teammates |
| `sample` | `PW.Spawns.Budget.sample` (8) | Number of candidates to evaluate |
| `enemies`, `mates` | the living players of the match | Lists of `{ pos, eye?, dir? }` actors instead of the living enemies and teammates (measurement, tests) |

Candidates (lane agent decision, T-2.9):

- the pool comes from `PW.Map.GetSpawns()`. With `all = false` (the first spawn of a team mode): the points of
  `ply:Team()` plus the `AnyTeam` points; when the team has no points, every point. With `all = true` (respawns, FFA):
  every point of every team, including `AnyTeam`;
- a random sample of `sample` distinct points is drawn from the pool;
- a respawn therefore uses the whole map, and a map without data uses the points of the layers above.

Candidates (`03-mapdata.md` d.7):

- the first spawn of the match: the team's own zone, if the map has one (Lua map file or CS:S-style entities);
- respawns: every spawn point of the map (dynamic spawning, CoD TDM style);
- maps without data: the points sampled from the navmesh (see above).

Scoring of a candidate (`03-mapdata.md` d.7):

```text
score = + distance to nearest enemy          (farther is better)
        - heavy penalty if an enemy has line of sight to the point
        + bonus for teammates nearby          (team modes)
        - penalty if the point was used recently
        + small random jitter
```

The weights are `PW.Spawns.Weights` (lane agent decision, T-2.9; units are Hammer units and seconds):

| Weight | Value | Use |
| --- | --- | --- |
| `distCap` | 3000 | The distance to the nearest enemy counts up to this value (also the value without enemies) |
| `los` | 5000 | Penalty when an enemy has line of sight to the point |
| `losFacing` | 2000 | Extra penalty when the point is visible and an enemy looks toward it |
| `facingCos` | 0.5 | Cosine of the half angle of "looks toward" (enemy aim vector against the direction to the point) |
| `mateRadius` | 1000 | A teammate within this distance counts as nearby |
| `mate` | 300 | Bonus per nearby teammate (team modes only) |
| `mateMax` | 3 | At most this many teammates count |
| `recent` | 2500 | Penalty of a point picked just now; falls linearly to 0 over `recentWindow` |
| `recentWindow` | 10 | Seconds |
| `jitter` | 200 | Upper bound of the random bonus (uniform, per candidate) |
| `eyeHeight` | 64 | Height above a point at which line of sight is checked |

- Evaluate a random sample of 8 candidates and pick the best. The candidates are probed best first (score without
  line of sight): a hull trace first (a standing player hull at the point lifted by 8 units, `MASK_PLAYERSOLID`) so a
  player never spawns inside another (`03-mapdata.md` d.7), then line of sight traces from the enemies, nearest
  first, to the point plus `eyeHeight`; a visible point is scored again with the penalty. The probing stops when no
  remaining candidate can beat the best. A hull-blocked point is never chosen (`TASKS.md` T-2.9).
- Enemy checks go through `PW.IsEnemy` (`teams.md`; `02-modes.md` d.6; `03-mapdata.md` d.7). Never `Team()`
  comparisons.
- The teammate bonus applies in team modes only; FFA disables it through `opts` (`03-mapdata.md` d.7; `TASKS.md`
  T-2.9).
- Cost budget `PW.Spawns.Budget` (lane agent decision, T-2.9; the design's bound is 8 times 16 = 128 traces):
  `sample` 8 candidates; `maxEnemies` 16 living enemies considered (scoring and line of sight); `maxTraces` 64 line
  of sight traces per pick, past it a candidate counts as seen; `maxMs` 5 ms, the limit of one pick in the in-game
  measurement. The hull traces come on top (at most one per candidate). Pure scoring logic (`_Score`, `_Choose` over an
  injected probe) is separate from the traces (thin glue, `CLAUDE.md` rule 4); `TASKS.md` T-2.9 tests the scoring with
  fake enemies. The cost of the last pick is in `PW._Spawns.stats`.
- Enemies and teammates are the living players other than `ply` and not `TEAM_SPECTATOR`: teammates are those for
  whom `PW.IsEnemy` is `false`.
- FFA spawning: the base `GM:PlayerSpawn` spawns a player without a team as a spectator because `GM.TeamBased` is
  `true` (`teams.md`, "Late join"). The `match_rules` module handles it by putting FFA players in a free team
  (`modes.md` "Match rules module"); `Pick` for FFA uses every point of the map (`all` defaults to `true` without
  teams) with no teammate bonus.

### Spawn protection

- `match` setting `spawns.protection` (full id; the owner is the module `spawns`, `01-extensibility.md` d.17): float,
  default 0, range 0 to 5 s (`03-mapdata.md` d.7).
- On every `PlayerSpawn` during `LIVE` the player gets protection until `CurTime() + spawns.protection` (none when the
  value is 0). While it lasts, `EntityTakeDamage` on the player is blocked (the hook returns `true`). It ends early
  when the player fires (`KeyPress` `IN_ATTACK`) and is dropped by the first damage after the time has passed.
- NW2: the player's Float `pw_spawn_protect` is the end time (`CurTime()`), `0` without protection.
  `PW.Spawns.ProtectedUntil(ply) -> number` (shared) reads it. The value is not cleared when the time passes: compare
  it with `CurTime()`.
- The module state (recent points, who spawned, protection) is reset when `PREMATCH` turns into `LIVE` and on `LOBBY`.

Mandatory cases (`TASKS.md` T-2.9): scoring prefers far-from-enemy; penalises enemy line of sight; rewards nearby
teammates only in team modes; a recently used point is penalised; a hull-blocked point is never chosen.

## Map data file id

Orchestrator decision: a map data file id is the map name lowercased, with every character outside `[a-z0-9_]`
replaced by `_`. For example `de_dust2` stays as it is and `cs-office.v2` becomes `cs_office_v2`. `PW.Map` looks the
file up by that id.

## `pw_mark`

Console command of the module `mapmark` (T-2.10; `lua/privatewar/modules/mapmark/`, namespace `PW.MapMark`, types
`lua/privatewar/types/mapmark.lua`): an authoring tool instead of an editor (`03-mapdata.md` d.5). The author stands at
the spot, runs the command and pastes the line into the Lua map file.

```text
pw_mark spawn [team]   prints a comment and { pos = Vector(...), yaw = 90 } for the current position and view yaw
pw_mark dom <letter>   prints a comment and a bare Vector(...), the same format as a flag in `MAP.Modes.dom.flags`
pw_mark header         prints the file path and MAP.Name = "<map>" for a new map file
```

- `spawn [team]`: `team` is an integer `0..16`, default `1`; `0` is `PW.Map.AnyTeam` (any team). Output, two lines:
  `-- MAP.Spawns[<team>]`, then `{ pos = Vector(x, y, z), yaw = n }`.
- `dom <letter>`: one letter `A` to `Z` (any case, printed uppercase). Output: `-- MAP.Modes.dom.flags.<L>`, then a bare
  `Vector(x, y, z)` (decided, `03-mapdata.md` d.5, clarified with the user on 2026-11-07: not `{ pos, yaw }`).
- `header`: `-- lua/privatewar/maps/<PW.Map.Id(map)>.lua`, then `MAP.Name = "<map name>"`.
- The position is the caller's `GetPos()` and the yaw is `EyeAngles().y`, normalised to `[-180, 180)` with at most one
  decimal; coordinates have at most two decimals, without trailing zeros.
- Only the kinds `spawn` and `dom` exist: the map module does not know mode rules (`03-mapdata.md` d.6), so a mode
  cannot add its own `pw_mark` kind yet.
- Privilege `pw.map.mark` (`PW.MapMark.Privilege`, default `superadmin`, `00-core.md` d.7). A player without it is
  refused with one log line (`[PW] pw_mark denied for <nick>`). The server console has no position and is refused with a
  message.
- Output goes to the caller's console (`HUD_PRINTCONSOLE`) and to the server log. Wrong arguments print the usage line to
  the caller (`usage: pw_mark spawn [team] | pw_mark dom <letter> | pw_mark header`) and print no entry.
- Pure functions (shared): `PW.MapMark.Format(kind, pos, yaw) -> string`, `Parse(line) -> PW.MapMarkEntry?, string?` (the
  inverse of `Format`, so the output parses back into map data: mandatory case `TASKS.md` T-2.10),
  `ParseArgs(args) -> PW.MapMarkArgs?, string?` and `_Build(args, pos, yaw, mapName) -> string[]?`; `_Command(ply, args,
  out?)` is the command logic.

`lua/privatewar/maps/gm_construct.lua` is test content in this format: the three flags `A`, `B`, `C` of Domination on
`gm_construct`, each exactly on an `info_player_start` (A and C are the two spawns farthest apart, B is the one nearest to
their midpoint). Its spawns stay auto-detected (`03-mapdata.md` d.3), so `dom` is offered there (`PW.Map.ModeFits` accepts the data).

## Map list

Curated union, plus "Show all" in Custom (`03-mapdata.md` d.9). Mandatory case (`TASKS.md` T-2.11): the union of
data maps, prefixes and whitelist; junk patterns always excluded. Module `maplist` (T-2.11), namespace
`PW.MapList`; types `lua/privatewar/types/maplist.lua`.

| Source | What is included |
| --- | --- |
| Maps with a Lua data file | Everything described by map pack authors |
| Maps with PvP prefixes | `de_`, `cs_`, `dm_`, `ctf_`, `koth_`, `cp_` "and similar"; the prefix list is a `server` setting |
| Host whitelist | Any map the host adds by hand (`gm_construct`, an RP map); a `server` setting, persisted |

- The vote, the rotation and playlists with `Maps = nil` use only this union (`03-mapdata.md` d.9).
- Custom has a "Show all maps" toggle: the host may pick any installed map for one match; it is not added to the
  list (`03-mapdata.md` d.9).
- Never shown, even with "Show all": `background*`, `d1_*`, `d2_*`, `d3_*`, `ep1_*`, `ep2_*`
  (`03-mapdata.md` d.9).
- Only installed maps are ever listed: a map with a data file that is not installed (no `maps/<name>.bsp` in `GAME`)
  is not in the list.
- Both settings are `server` settings (ConVars, archived, `core.md` "Settings"), type `set` (lane agent decision,
  T-2.11):

  | Full id | ConVar | Default | Meaning |
  | --- | --- | --- | --- |
  | `maplist.prefixes` | `pw_maplist_prefixes` | `de_`, `cs_`, `ar_`, `fy_`, `dm_`, `tdm_`, `ctf_`, `koth_`, `cp_`, `pl_`, `plr_`, `arena_`, `sd_` | The PvP prefixes: a map whose lowercase name starts with one is listed (`de_` lists `de_dust2`) |
  | `maplist.whitelist` | `pw_maplist_whitelist` | empty | Map names the host added by hand |

- The junk patterns `PW.MapList.JunkPatterns` (Lua patterns over the lowercase name), never listed, also not by
  "Show all": `^background`, `^d1_`, `^d2_`, `^d3_`, `^ep1_`, `^ep2_` (from the design) and `^credits$`, `^test_`,
  `^test$`, `^intro$` (the lane agent's reading of "and the like"). Junk wins over all three sources.
- The union matches the data maps by the map data file id (`PW.Map.Id`) of the installed name: the enabled entries of
  the `maps` registry.

| Function | Realm | Contract |
| --- | --- | --- |
| `PW.MapList.Filter(sources) -> string[]` | shared | Pure. `sources = { installed, data, prefixes, whitelist }`: the installed names, the data file ids, the prefixes and the whitelist (sets as `{ [id] = true }` lookups or plain lists). Returns the curated list: unique, sorted, the installed spelling |
| `PW.MapList.IsJunk(mapName) -> boolean` | shared | Pure, case-insensitive |
| `PW.MapList.GetList() -> string[]` | server | The curated list from `file.Find("maps/*.bsp", "GAME")`, the enabled `maps` registry entries and the two settings. Reads the disk on every call (a lobby and vote operation, not a hot path) |
| `PW.MapList.GetInstalled() -> string[]` | server | Every installed map except junk, sorted: the list of "Show all maps" |
| `PW.MapList.IsListed(mapName) -> boolean` | server | Whether the map is in `GetList()` |
| `PW.MapList.DefaultPrefixes`, `JunkPatterns` | shared | The tables above |

## Navmesh generation

Module `navgen` (T-2.12; `lua/privatewar/modules/navgen/`, namespace `PW.NavGen`, types
`lua/privatewar/types/navgen.lua`). Sources: `03-mapdata.md` d.8; `notes/11-navmesh-generation.md`.

Design rules (`03-mapdata.md` d.8) and how the code meets them:

- Maps without a navmesh: warn, offer generation, never generate automatically. The lobby marks such a map with the
  line `No navmesh: bots and dynamic spawns unavailable.` (`PW.Lobby._NavLine`, `ui.md`).
- The Generate button is shown to a holder of the privilege, only in `LOBBY`, only for the current map, after a
  warning dialog (the lobby, `ui.md`). The server checks everything again (below).
- No Lua "finished" hook exists; the engine saves `garrysmod/maps/<map>.nav` and runs `changelevel` to the same map by
  itself. The module never calls `navmesh.Load()`, `navmesh.Save()` or its own `changelevel`, and does not offer
  incremental generation (`notes/11` "Things not to do").
- The navmesh is server-only; other players do not need the file. A one-time cost per map.

### Privilege, message, command

| Item | Contract |
| --- | --- |
| Privilege `pw.map.navgen` | `PW.NavGen.Privilege`, default `superadmin` (`00-core.md` d.7) |
| Net message `pw_navgen_start` | Client to server, through `PW.Net.Receive` (module-owned): who `pw.map.navgen`, phases `LOBBY`, 1 per s, `maxLen` 8 bytes. Payload `WriteBool(fast)`, `WriteBool(force)`. The shipped lobby always sends `force = false` |
| Console command `pw_navgen [fast] [force]` | `fast` turns on the fast mode, `force` allows generation on a map that already has a navmesh. From a player it needs the privilege; the server console is always allowed (and its position is not used as a seed). The `LOBBY` phase is checked for both |

### Starting (`PW.NavGen._Start(ply, fast, force) -> boolean, string?`, internal)

`_MayGenerate(facts)` (pure) refuses, in this order, with the reason: `privilege`, `phase` (not `LOBBY`), `busy` (a
generation or a map change is running), `navmesh exists` (the map has areas and `force` is not set). A refusal logs one line
(`navmesh generation from <nick> refused: <reason>`) and changes nothing. Further reasons: `no seeds`, `marker` (the marker file
could not be written), `engine` (the engine did not start). Then, in this order:

1. Seeds: one per spawn entity of every class of `PW.Map._SpawnClasses` (`PW.Map._Collect()`; `PW.NavGen._Seeds(records,
   classes)` is the pure selection), each traced to the floor (a brush trace from 8 units above the entity down 4096 units,
   rejecting a start inside the solid), plus the caller's position when the caller stands on the ground. `navmesh.BeginGeneration()`
   silently does nothing without walkable seeds, so zero seeds is a refusal.
2. The marker is written (below) before anything else changes.
3. The module is generating (`PW.NavGen.IsGenerating()` is true), the stored result is cleared, every bot is kicked
   (`navmesh generation`), the map data sampler is paused (`PW.Map.PauseNav(true)`), the start is logged, and the lobby state is
   sent again to every human (the navmesh line shows "generating").
4. Fast mode: `sv_cheats 1`, `nav_max_view_distance 1` and `nav_generate_fencetops 0`.
5. One tick later: `navmesh.ClearWalkableSeeds()`, `navmesh.AddWalkableSeed(pos, normal)` for each seed,
   `navmesh.BeginGeneration()`. If the engine is not generating right after that, the start is undone: the marker is deleted,
   `sv_cheats` is restored when the fast mode had turned it on, `PW.Map.PauseNav(false)`, and the failure `Navmesh generation
   on <map> could not start: the engine found no walkable start point.` is stored, logged and shown in the lobby.

Bot creation itself is not paused: no bot module exists yet (`Open in design`, item 10).

### Marker `data/privatewar/navgen.json`

Written at the start, deleted when it has been read after the reload (or when the start failed). JSON (`PW.NavGenMarker`):

| Field | Type | Meaning |
| --- | --- | --- |
| `v` | number | Format version, `PW.NavGen.Version` = 1 |
| `map` | string | The map the generation started on (`game.GetMap()`) |
| `startedAt` | number | `os.time()` at the start |
| `fast` | boolean | The fast mode was used |
| `cheatsWasOn` | boolean | `sv_cheats` was on before the start (restored to off only when it was off) |

`PW.NavGen._ValidateMarker(marker, { map, now, areas }) -> outcome, reason?` (pure): `"stale"` with the reason `corrupt`
(not a table, `v` not a number, or any other field of the wrong type), `version` (`v` is not 1), `map` (another map) or `age`
(older than `PW.NavGen.MaxAge` = 6 hours, or from the future); otherwise `"success"` when `areas > 0`, else `"failure"`.
`_Encode(marker)` and `_Decode(text)` are the JSON forms. A stale marker is ignored: it is deleted, and one log line
(`navmesh generation marker ignored (<reason>): <text>`) is written; no result is shown.

### After the reload

The engine reloads the map and the Lua state starts over. From `InitPostEntity` the module checks the marker in `Think`, every
second, at most 5 times (the engine loads the `.nav` after `InitPostEntity`, so `navmesh.GetNavAreaCount()` is 0 at first):
without a marker nothing happens; with a marker and no areas it waits until the last try; then `_Check(final)` deletes the
marker, validates it, restores `sv_cheats` if needed, stores the result, logs it and sends the lobby state to every human. The
result text (`_ResultText`): success `Navmesh generated for <map>: <n> areas.`, failure `The last navmesh generation on <map>
did not finish. Try again, try fast mode, search the Workshop for "<map> navmesh", or pick another map.` The stored result is
shown in the lobby until the next generation starts or the map changes.

### API

| Function | Realm | Contract |
| --- | --- | --- |
| `PW.NavGen.Privilege`, `Version`, `MaxAge` | shared | `"pw.map.navgen"`, `1`, `21600` (seconds) |
| `PW.NavGen.IsGenerating() -> boolean` | server | `true` from the start until the reload: the module's own flag or `navmesh.IsGenerating()`. The lobby and the playlists refuse a match start while it is `true` (`ui.md`, `modes.md`) |
| `PW.NavGen.LobbyInfo(ply) -> PW.LobbyNav` | server | The navmesh block of the lobby state for one player: `areas` (navmesh area count), `generating`, `canGenerate` (`_MayGenerate` for this player now, without `force`), `fastDefault` (one human or fewer: the fast mode checkbox starts checked, `PW.NavGen._FastDefault(humans)`), `result` (the stored text, `""` for none) |
| `PW.Map.PauseNav(paused)` | server | See "`PW.Map` (module `mapdata`)" |

The lobby block of `pw_lobby_state`, the dialog and the lobby refusal are in `ui.md`.

Mandatory cases (`TASKS.md` T-2.12): marker validation (success, failure, stale marker); seeds generated for every spawn
entity class; no generation without the privilege or outside `LOBBY`.

## Hooks

The map lane defines no new hooks in the design. It takes part in:

| Hook | Type | Arguments | Role | Source |
| --- | --- | --- | --- | --- |
| `PW_SelectSpawn` | question | `ply: Player` | The spawns module answers it with `PW.Spawns.Pick`; a mode may answer first. Returns an entity or `{ pos, yaw? }`. Fired by the `match_rules` module (`modes.md`) | `02-modes.md` d.7; `03-mapdata.md` d.7 |
| `PW_IsEnemy` | question | `a, b` | Used by `Pick`; documented in `teams.md` | `03-mapdata.md` d.7 |
| `PW_RegistriesLoaded` | notification | none | After it every `maps/` entry is registered and `Base` is resolved (`core.md`) | `01-extensibility.md` d.5 (open question 5) |

## Core changes needed

1. **Kind declaration file** `lua/privatewar/kinds/maps.lua`: `Folder = "maps"`, `Global = "MAP"`; no `Required`
   (`03-mapdata.md` d.1); `Subscribe` omitted (`"never"`, data only). The core lane's directory; the orchestrator
   adds the file before T-2.7.
2. **Map ids.** Closed by the orchestrator decision in "Map data file id": the id is the normalised map name, so no
   change of the id rule is needed.
3. ~~`PW_SelectSpawn` integration with `GM:PlayerSelectSpawn`~~ Not in the core: the `match_rules` module hooks
   `PlayerSelectSpawn` and `PlayerSpawn` (`modes.md`); the `spawns` module answers the hook.
4. **`KIND.Required`** will be validated after `Base` resolution (wave 0); the `maps` kind has no `Required` today.
5. **Bot pause during generation** needs a switch the bots module (P5) reads (`03-mapdata.md` d.8, "Bots are kicked
   and bot creation is paused"). Partly done: `navgen` kicks the bots and pauses the map data sampler; the switch for
   bot creation is not designed (item 10). Nothing to pause before P5.

## Open in design

Nothing here is invented. Each item says what is missing and which task it blocks.

- **Details are decided by the lane agent.** The API details and defaults listed here (names, return types, event
  points, thresholds, magazine counts) are decided by the lane agent of each task. The agent documents them and
  reports them; the orchestrator writes them into this contract after the merge. Only gameplay-changing choices go
  to the user.

1. ~~**`opts` of `PW.Spawns.Pick`.**~~ Decided (lane agent, T-2.9), see "`PW.Spawns.Pick(ply, opts)`".
2. ~~**Queries across maps.**~~ Decided (lane agent, T-2.4): `PW.Map.ModeFits(mode, mapName)`, see "`PW.Map.ModeFits`".
3. ~~**Entity class to team mapping.**~~ Decided (lane agent, T-2.7), see "Spawn sources".
4. ~~**Navmesh sampler thresholds.**~~ Decided (lane agent, T-2.8), see "Navmesh fallback".
5. ~~**Return value of `Pick` and `PW_SelectSpawn`; who fires the hook; FFA spawning.**~~ Decided (lane agent, T-2.2,
   T-2.9): `{ pos, yaw }` or an entity; `match_rules` fires the hook and spawns FFA players; FFA uses every point of
   the map (`AnyTeam` points are team 0 of `PW.Map.AnyTeam`).
6. ~~**Privilege and message names**~~ Decided (lane agent, T-2.10, T-2.12): `pw.map.mark`, `pw.map.navgen`, the message
   `pw_navgen_start` and the console commands `pw_mark` and `pw_navgen`; see "`pw_mark`" and "Navmesh generation".
7. ~~`pw_mark` output~~ Closed: the `dom` output is a bare `Vector` (`03-mapdata.md` d.5). Decided (lane agent, T-2.10):
   the line goes to the caller's console and the server log; only `spawn` and `dom` exist, a mode cannot add a kind yet.
8. ~~**Map list settings and API.**~~ Decided (lane agent, T-2.11), see "Map list": data maps must be installed;
   "Show all" is `PW.MapList.GetInstalled`.
9. ~~**Navgen marker.**~~ Decided (lane agent, T-2.12): the fields `v`, `map`, `startedAt`, `fast`, `cheatsWasOn`, the
   validation, the 6 hour staleness limit, version 1 and the up to 5 checks after `InitPostEntity`; see "Marker `data/privatewar/navgen.json`".
10. **Bot pause during generation.** Partly done (T-2.12): the bots are kicked and the map data sampler is paused. The
    mechanism to stop bot creation is still open and blocks the bots lane (P5) and CP-2 item 5 only if bots exist then.
11. ~~**`PW.Map` function set.**~~ Decided (lane agent, T-2.7, T-2.8): see "`PW.Map` (module `mapdata`)" and
    "Map list", and `PW.Map.ModeFits` (item 2).
