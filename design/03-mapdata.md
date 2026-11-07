# 03 — Map data

Status: decided (in-game checks in `../notes/11-navmesh-generation.md`).

## Goal and scope

Per-map data: spawns, objective points, landing zones; generators from node graph / navmesh.

## Decisions

1. **The game must work on any map.** Map-specific data is optional and improves a map; its absence never blocks play.

2. **Map data is a Lua file per map: the kind `maps/` (data only).**

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

   - The id is the map name (`game.GetMap()`), like every other kind (`01-extensibility.md` decision 8).
   - Shipped by map packs or written by anyone; no in-game editor in MVP.

3. **Sources, in priority order (a higher layer overrides a lower one):**
   1. Lua map file (`lua/privatewar/maps/<map>.lua`).
   2. Auto-detection from map entities: team spawns from CS:S (`info_player_terrorist` / `info_player_counterterrorist`), HL2DM and TF2 spawn entities, DM spawns from `info_player_deathmatch`.
   3. Fallback for maps without data: spawn points from random navmesh areas, choosing a point far from enemies (FFA-style dynamic spawn).
   - If a map has no navmesh, `nav_generate` can build one, but it is slow (minutes) and not always good. How the host is told about this is open.

4. **Objective modes are hidden on maps without their data.** For example Domination is offered only on maps whose data provides flags. A generator of objective points comes after MVP; the layer model leaves room for it as a lowest-priority source.

5. **Authoring tool instead of an editor:** a debug console command

   ```text
   pw_mark spawn 1      prints { pos = Vector(...), yaw = 90 } for the current position
   pw_mark dom A        prints a bare Vector(...), the same format as a flag in decision 2
   ```

   The author stands at the spot, runs the command and pastes the line into the Lua map file. About 20 lines instead of an editor UI. Requires a privilege (`00-core.md` decision 7). Clarified with the user on 2026-11-07: `pw_mark dom <letter>` outputs a bare `Vector`, not `{ pos, yaw }`.

6. **A mode declares whether it needs map data; the mode validates it.**

   ```lua
   -- modes/dom.lua
   MODE.MapData = true    -- needs MAP.Modes.dom on the map

   function MODE:ValidateMapData(data)   -- data = MAP.Modes.dom
       if not data.flags or table.Count(data.flags) < 2 then
           return false, "Domination needs at least 2 flags"
       end
       return true
   end

   function MODE:Start()
       local flags = PW.Map.GetModeData(self.ClassName).flags
   end
   ```

   - With `MODE.MapData = true` the mode is offered on a map only if `MAP.Modes.<mode id>` exists and passes `ValidateMapData`: in Custom, in the vote and in playlists. TDM, FFA and Kill Confirmed do not set it: spawns exist on every map (decision 3).
   - The map module only stores the table; it does not know what a "Domination flag" is (same principle as the core not knowing mode rules).
   - Inheritance: a mode without its own entry uses the entry of its `Base` chain (`hardcore_dom` → `MAP.Modes.dom`).
   - A playlist with `Maps = nil` automatically uses only maps that fit its modes.
   - Invalid data: one log line (map, mode, reason), the mode is hidden on that map (`01-extensibility.md` decision 15 behaviour).

7. **Spawn selection: a `spawns` module with a scoring picker; modes call it.**
   - The mode answers `PW_SelectSpawn`; the shared logic lives in the `spawns` module as `PW.Spawns.Pick(ply, opts)`. Modes tune it through `opts` (for example FFA disables the teammate bonus).
   - Candidates:
     - first spawn of the match: the team's own zone, if the map has one (Lua map file or CS:S-style entities);
     - respawns: every spawn point of the map (dynamic spawning, CoD TDM style);
     - maps without data: about 200 points sampled once from navmesh areas at map load (skip areas that are too small, underwater or too steep).
   - Scoring of a candidate:

     ```text
     score = + distance to nearest enemy          (farther is better)
             − heavy penalty if an enemy has line of sight to the point
             + bonus for teammates nearby          (team modes)
             − penalty if the point was used recently
             + small random jitter
     ```

   - Evaluate a random sample of about 8 candidates, pick the best; check the chosen point with a hull trace so a player never spawns inside another.
   - Enemy checks go through `PW.IsEnemy` (`02-modes.md` decision 6).
   - Cost: up to 8 candidates × 16 enemies = 128 traces per respawn; respawns are rare (a few per second with bots), within budget.
   - Spawn protection: `match` setting `spawns.protection`, 0–5 s, default 0 (as in CoD); removed early when the player fires.

8. **Maps without navmesh: warn, offer generation, never auto-generate.**
   - Navmesh is needed for bot navigation (`07-bots.md`) and for the dynamic-spawn fallback (decision 3).
   - The lobby marks such a map: "no navmesh: bots and dynamic spawns unavailable".
   - The host can press "Generate" (privilege, `00-core.md` decision 7), only in `LOBBY` and only for the current map, after a warning: it takes from about a minute to over an hour on huge maps, the game stutters heavily, large maps can crash (out of memory), and the map reloads when done.
   - Facts (`../notes/11-navmesh-generation.md`): `navmesh.BeginGeneration()` needs no `sv_cheats`; it needs walkable seeds (the core adds one per spawn entity of decision 3 via `navmesh.AddWalkableSeed`, otherwise generation silently does not start); it runs incrementally (about 30 ms per frame), so the game stutters rather than freezes; the engine saves `garrysmod/maps/<map>.nav` and runs `changelevel` to the same map by itself; there is no Lua "finished" hook.
   - Completion is detected after the reload through a marker file `data/privatewar/navgen.json` plus `navmesh.GetNavAreaCount() > 0`; the host sees success or failure with retry options.
   - Bots are kicked and bot creation is paused during generation. Optional "fast mode" (`nav_max_view_distance 1`, needs a temporary `sv_cheats 1`) is offered as a checkbox, default off when other humans are connected.
   - The full button flow (preconditions, dialog text, server steps, post-reload handling, things not to do) is in `../notes/11-navmesh-generation.md`, "Recommendations".
   - The result is a one-time cost per map on the host's computer; other players do not need the file (navmesh is server-only).
   - Without generation the map is playable by humans only, with spawns from map entities (`info_player_start` and others).
   - Generation is never started automatically, so the host's game never freezes unexpectedly.

9. **Map list: a curated union, plus "show all" in Custom.**

   | Source | What is included |
   | --- | --- |
   | Maps with a Lua data file | Everything described by map pack authors (best fit) |
   | Maps with PvP prefixes | `de_`, `cs_`, `dm_`, `ctf_`, `koth_`, `cp_` and similar; they have spawn entities (decision 3). The prefix list is a `server` setting |
   | Host whitelist | Any map the host adds by hand (`gm_construct`, an RP map). A `server` setting, persisted |

   - The vote, rotation and playlists with `Maps = nil` use only this union.
   - Custom has a "Show all maps" toggle: the host may pick any installed map for one match; it is not added to the list.
   - Obvious junk is never shown, even with "Show all": `background*`, `d1_*`, `d2_*`, `d3_*`, `ep1_*`, `ep2_*`.
   - Rationale: players have hundreds of maps (campaign, RP, build); an unfiltered list makes the vote and "all maps" playlists useless.

## Interfaces

TBD.

## Performance budget

TBD.

## Security

TBD.

## Open questions

1. ~~How a mode declares which map data it needs~~ Closed: decision 6.
2. ~~Spawn selection logic~~ Closed: decision 7.
3. ~~Maps without navmesh~~ Closed: decision 8 (research `../notes/11-navmesh-generation.md`).
4. ~~Map list~~ Closed: decision 9.

## Research

- `../notes/11-navmesh-generation.md` (navmesh generation flow)
