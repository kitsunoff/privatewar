# Search and Destroy on `de_` maps: automatic site detection

**RESEARCH / NOT DECIDED.** Proposal only: no decision in `design/` changes, no frozen API changes and no
implementation is authorized by this note. Code inspected on `main` at `ee15cac`, 2026-11-11. No game, Deck,
GLuaTest or performance run was performed.

Path prefixes: `P = addons/privatewar/lua/privatewar/`, `C = addons/privatewar/gamemodes/privatewar/gamemode/core/`.

Evidence labels:

- **[code]**: read in this repository.
- **[source]**: stated explicitly by a primary source (URL given).
- **[inference]**: follows from sources, not stated by them.
- **[unverified]**: no source found; needs an in-game check (section 9).

## 1. Summary

1. Without a registered scripted entity, GMod does not create `func_bomb_target`, so `ents.FindByClass` cannot
   see bomb sites. A brush SENT named `func_bomb_target` must be registered before map entities spawn.
2. Original A/B labels can usually be reproduced: Counter-Strike labels the lowest entity index A and the highest B,
   unless nav place names override it. GMod does not load nav meshes from mounted games, and GMod-generated nav
   meshes have no place names, so only the entity order remains.
3. S&D cannot run on a map without a navmesh, even with humans only: activation requires nav areas for every point.
4. Offering every `de_` map before load conflicts with `design/03-mapdata.md` d.4/d.6 and `design/02-modes.md` d.8
   and changes frozen contracts (`docs/api/map.md`, `docs/api/modes.md`). It needs user approval.
5. Separate gap: an abort reason or a refused lobby start is only logged on the server; players never see it.

## 2. Current map discovery, filtering and match start [code]

- **Map list.** `PW.MapList.GetList()` is the union of maps with a Lua data file, maps with a configured prefix and
  the whitelist; `de_` is a default prefix (`P/modules/maplist/shared.lua:12-13`, `:82-100`). Discovery uses only
  `file.Find("maps/*.bsp")` (`P/modules/maplist/init.lua:9-11`); no BSP content is read.
- **Mode/map fit.** `PW.Map.ModeFits(mode, mapName)` (`P/modules/mapdata/shared.lua:288-301`) requires, for
  `MODE.MapData = true`, a map data file, an entry along the mode's `Base` chain and a passing `ValidateMapData`.
  A `de_` map without a file returns `false, "no map data"`.
- **Callers.** Playlists `defaultFits` (`P/modules/playlists/init.lua:71-79`); the vote through the playlist test
  (`P/modules/vote/init.lua:58-62`, `:171-172`, recheck `:215`); the server lobby start
  (`P/modules/lobby_ui/init.lua:139-163`); the **client** lobby picker (`P/modules/lobby_ui/cl_init.lua:122` →
  `P/modules/lobby_ui/shared.lua:74-82`). The client computes fit itself, so any pre-load rule must be shared,
  pure and identical in both realms. Map data files reach clients through `AddCSLuaFile`
  (`C/sh_loader.lua:113-128`).
- **Map change.** `PW.Match.Start(mode, map)` writes `data/privatewar/pending_match.json` and runs `changelevel`
  (`C/sv_mapchange.lua:201-214`); the new map applies it one tick after `InitPostEntity` and enters PREMATCH
  (`:272-300`, `:319`).
- **Mode start.** `MODE:Start` runs on entering LIVE (`C/sv_match.lua:128-131`), after the prematch wait and the
  countdown. The navmesh is read after `InitPostEntity`, retried up to five times (`P/modules/mapdata/init.lua:139-157`).
- **Failure path.** S&D `Start` calls `Validate` and `Activate` (`P/modes/snd.lua:31-39`); errors are caught by
  `PW.Call`, which aborts the match for the active mode (`C/sh_call.lua:28-38`). No crash, back to LOBBY.
- **Reason visibility.** `PW.Match.Abort` stores `abortReason` and logs it (`C/sv_match.lua:298-306`); nothing sends
  it to clients. A refused lobby start is only logged (`P/modules/lobby_ui/init.lua:159`).

### Proposed check points

| Stage | Where | Check |
| --- | --- | --- |
| Before load | `ModeFits`, shared | Authored data when present; otherwise candidate = `PW.Map.Id(map)` starts with `de_` and is not junk. Server additionally: no cached failure for this map version |
| After load, early | S&D server glue, once the navmesh is ready and S&D is pending or active | Detection plus full world validation; on failure abort in PREMATCH with a readable reason |
| LIVE start | `MODE:Start` (unchanged) | `Validate` + `Activate` as the last guard |
| UI | lobby | Show `abortReason` and start refusals (missing today) |

A first attempt on an unverified map can only fail after loading; this cannot be avoided without reading the BSP of
an unloaded map. A failure cache makes it a one-time cost.

## 3. What S&D consumes [code]

Schema of `MAP.Modes.snd` (`P/modules/snd/shared.lua:26-70`, `P/maps/gm_construct.lua:24-49`):

```lua
snd = {
    sites = { -- exactly 2, dense
        { id = "A", pos = Vector(), radius = 160, above = 96, below = 16, approach = Vector() },
        { id = "B", pos = Vector(), radius = 160, above = 96, below = 16, approach = Vector() },
    },
    bomb = Vector(), -- initial and recovery point
    spawns = { [1] = { { pos = Vector(), yaw = 0 } }, [2] = { { pos = Vector(), yaw = 0 } } },
}
```

- `id` is 1–32 characters and unique; `approach` must be inside the site cylinder (`Inside`, `P/modules/snd/shared.lua:6-10`).
- A completed plant moves the bomb to `site.approach` (`P/modules/snd/sh_round.lua`, plant branch); bots use it as
  the objective position (`P/modules/snd/sh_objectives.lua:26`).
- Team 1 always attacks (`P/modules/snd/sh_objectives.lua:45-49`); side swaps move players between team indices
  (`P/modes/round_base.lua:280`). So `spawns[1]` are attacker spawns, matching `info_player_terrorist` → 1 and
  `info_player_counterterrorist` → 2 (`P/modules/mapdata/shared.lua:15-17`).
- `PW_SelectSpawn` uses only `state.map.spawns` with `first = true, all = false` (`P/modes/snd.lua:126-133`).
  When every sampled candidate is hull-blocked, `_Choose` returns nil (`P/modules/spawns/shared.lua:154-174`) and
  the mode errors, which aborts the match. Valid spawns per side must therefore be at least the largest team size.

`Activate` (`P/modules/snd/sv_world.lua:44-63`) checks the bomb, every site `pos`/`approach` and **every** spawn:
in world, floor within 16 units with normal z ≥ 0.7, standing hull clear, nav area within 128 units, mutual nav
reachability with the bomb area, and approach-to-site sight. Any failure is an `assert`. Two risks on large maps:
the BFS stops at 10000 areas (`sv_world.lua:32`), which gives false failures, and it runs two BFS per point at the
start of LIVE (cost not measured).

Client: site markers read `PW.Map.GetModeData("snd")` (`P/modules/snd/cl_init.lua:38-45`), so server-generated data
would show no markers; the HUD line "SITES A / B" is hard-coded (`P/modules/snd/sh_round.lua`, `HudText`). The
`pw_snd_state` snapshot has a frozen fixed shape without sites (`P/modules/snd/sv_snapshot.lua`,
`docs/api/modes.md:434-439`).

Sites are public facts under `02-modes.md` d.8, so they may be replicated globally. Options: Global2 variables
(site count, id, position, radius; automatically delivered to late joiners, cleared in `Cleanup`) or a small
`pw_snd_sites` message validated like `cl_init.lua:53-79`. Recommendation: Global2 variables plus a shared
`PW.SND.Sites()` accessor (authored data first, then replicated data). Carrier and dropped-bomb positions stay out.

## 4. `func_bomb_target` in GMod

| Claim | Label |
| --- | --- |
| An entity class without a factory prints `Attempted to create unknown entity type %s!` and is not created ([util.cpp](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/util.cpp), [mapentities.cpp](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/mapentities.cpp)); GMod prints it for TF2 entities ([issue 6544](https://github.com/Facepunch/garrysmod-issues/issues/6544)) | source |
| Without a SENT, `ents.FindByClass("func_bomb_target")` is empty. Facepunch TTT states CS:S/TF2 entities need a SENT "else they will just error out" (`Facepunch/garrysmod`, `garrysmod/gamemodes/terrortown/gamemode/ent_replace.lua`, `dummify`) | inference |
| Type `brush` is "A serverside only trigger entity" ([wiki](https://wiki.facepunch.com/gmod/Scripted_Entities)) | source |
| A map-placed brush SENT receives its `*N` brush model and bounds automatically (TTT `ttt_traitor_check` reads `OBBMins`/`OBBMaxs` without setup; [issue 4121](https://github.com/Facepunch/garrysmod-issues/issues/4121)) | inference |
| A brush without an `origin` key rotates around the map origin; use world bounds (`WorldSpaceAABB` or `LocalToWorld` of the OBB) | source (issue 4121) |
| `GetBrushPlaneCount` counts only non-nodraw surfaces ([wiki](https://wiki.facepunch.com/gmod/Entity:GetBrushPlaneCount)); trigger brushes may report 0, so do not rely on it | source / inference |
| Gamemode `entities/` loads after `init.lua` ([wiki](https://wiki.facepunch.com/gmod/Lua_Loading_Order)); map entities spawn later | source / inference |
| A Lua reload does not re-create skipped entities; `game.CleanUpMap` respawns map entities ([wiki](https://wiki.facepunch.com/gmod/game.CleanUpMap)) | inference / source |
| Keyvalues: `targetname`, `bomb_mount_target`, `heistbomb` (unused), `StartDisabled`; inputs include `Enable`/`Disable`. No A/B label on the entity ([VDC](https://developer.valvesoftware.com/wiki/Func_bomb_target)) | source |
| One brush entity may consist of several disjoint brushes ([VDC](https://developer.valvesoftware.com/wiki/Brush_entity)); its AABB then spans the gap | source / inference |
| Entities per site and number of sites on specific official maps; disabled sites and class preservation in CS:GO ports; the point variant `info_bomb_target` | unverified |

Consequences: register an inert brush SENT `func_bomb_target` only if the class is not already registered by
another addon (no touch logic, no draw, keep `targetname` and `StartDisabled` from `ENT:KeyValue`). Read world AABB,
centre and height from it. The registration affects every mode on `de_` maps; the entity is server-only and inert.

## 5. Site names

| Source | Label | Available in GMod |
| --- | --- | --- |
| CS rule: lowest entity index is A, highest is B; overridden by the place name of the nearest nav area (`Bombsite`/`BombsiteA` → A, any other → B) ([VDC](https://developer.valvesoftware.com/wiki/Func_bomb_target)) | source | Entity order yes; place names only with a CS nav mesh |
| Mounted-game `.nav` files are intentionally not loaded ([issue 6544](https://github.com/Facepunch/garrysmod-issues/issues/6544)) | source | No; GMod-generated meshes carry no places |
| CS:GO overview files with `bombA_x`/`bombB_x` | source | Another game's files; do not use |
| `targetname` | author-defined | Heuristic only |

Proposal: group entities into sites (section 7), order them by the smallest `Entity:MapCreationID()` in each group,
label the first A and the second B (the CS default rule), and apply the place-name override when a nav mesh with
`BombsiteA`/`BombsiteB` places is loaded (for example a manually copied CS nav file).

Limits: that `MapCreationID` order equals the CS entity index order is an inference (both follow the entity lump
order) and needs an in-game check. Maps whose authors set labels through CS nav places may get swapped letters on a
GMod-generated mesh; this cannot be detected before load. Neutral labels `1`/`2` are an alternative and a user decision.
Bots always attack `sites[1]` (`P/modules/snd/sh_objectives.lua:49`), so the order also fixes the bot attack target.

## 6. Site, approach and bomb points

Assumption: a navmesh is required, because `Activate` rejects every point without one.

1. **Site point.** Nav areas whose centre lies inside the group AABB in XY and in `[mins.z - 64, maxs.z]`, sorted by
   distance to the AABB centre, then by area id. For the first N (for example 16): trace to the floor, check hull and
   mutual reachability; the first pass gives `pos = approach` (as on `gm_construct`), which makes the sight check
   trivial. Stacked sites are handled by `above`/`below`.
2. **Dimensions.** `radius` = half the shorter AABB side, clamped (for example 96–320); `above = clamp(maxs.z - pos.z, 72, 256)`;
   `below = clamp(pos.z - mins.z, 16, 64)`. `approach` stays inside by construction.
3. **Bomb.** The valid attacker spawn nearest to the attacker spawn centroid; it already passed every check and matches
   the CS convention.
4. **Spawns.** Filter by floor, hull and reachability instead of failing on the first bad point; a side is usable only
   with at least the expected team size of valid points (threshold is a user decision; minimum `ceil(maxplayers / 2)`).

When checks reject data:

- Bounded candidate search; when exhausted, reject the map with a reason such as
  "site B: no grounded, hull-clear nav point inside the bomb volume".
- Reachability failures usually come from gaps in a generated mesh (stairs, missing seeds). Proposal: navgen also adds
  walkable seeds at bomb target centres (`P/modules/navgen/init.lua:160-175`); a map-lane change.
- Replace the capped per-point BFS with forward and reverse reachability sets computed once (reverse edges from one
  pass over all areas). This removes the 10000-area false failures and most of the cost.
- Do not relax the checks: they prevent unreachable plants and stuck bombs.

Humans-only play: today S&D without a navmesh is impossible [code]. Either keep the navmesh mandatory with a clear
reason and the existing Generate flow (recommended), or replace nav checks with traces for humans-only matches, in
which case `DropPoint` always returns the bomb point (`P/modules/snd/sv_world.lua:72-73`). The latter changes the frozen
activation contract.

Bot consequences: one objective point per site (attackers converge on it, defenders hold the centre); an approximate
cylinder can exceed the real volume or include a wall; generated meshes can strand bots; the attack always targets
`sites[1]`. All of this needs the human checkpoint.

## 7. Minimal architecture (proposal)

1. **SENT registration** in the `snd` module's shared load (as `P/modules/dom_flags/shared.lua:116`): brush
   `func_bomb_target`, only when the class is free.
2. **Pre-load candidate**, shared and pure: optional `MODE:MapCandidate(mapName) -> boolean`; S&D returns true for a
   non-junk `de_` map. `ModeFits` asks it only when no authored data exists along the `Base` chain, so the map module
   stays a store (d.6) and the `de_` knowledge stays in the mode. Authored data has priority: with `MAP.Modes.snd`
   present, detection never runs; invalid authored data hides the mode without falling back (recommendation).
3. **Pure core** `PW.SND.Derive(input) -> data | nil, reason` over plain data: target AABBs with `MapCreationID` and
   `targetname`, detected spawns, nav area data and injected probes (floor, hull, reachability). Output uses the
   authored schema and must pass the existing `Validate`. Grouping: equal non-empty `targetname`, or AABBs that
   intersect after expanding by 128 units. Exactly two groups, otherwise "found N bomb sites, S&D needs 2".
4. **Thin server glue** runs when the navmesh is ready and S&D is pending or active. It needs a public readiness
   signal from mapdata (`PW.Map.IsNavReady()` or a hook); the S&D module must not read `PW._Map`. The result goes into
   a new lowest layer, `PW.Map.SetGeneratedModeData("snd", data)`; `GetModeData` returns authored data first
   (room for this layer is reserved by `03-mapdata.md` d.4).
5. **Cache** `data/privatewar/snd_auto.json`: `map → { v, ok, reason, bspSize, bspTime, navTime }` (file metadata,
   not BSP content). The server hides maps with a known failure. Geometry is recomputed each load. Keeping the client
   picker consistent requires sending statuses in the lobby state (a lobby wire change); a first-stage alternative is
   to list the map and refuse with a visible reason.
6. **Errors**: abort in PREMATCH with a readable reason; show `abortReason` and start refusals in the lobby; no `assert`
   in the detection path, only `nil, reason`.
7. **Client**: Global2 sites, `PW.SND.Sites()`, HUD labels from site ids.

### Tests (GLuaTest, tests first)

Pure:

- Candidate: `de_` and `DE_X` yes; `cs_`, `dm_` and junk no.
- Authored data wins; invalid authored data hides the mode without automatic fallback.
- Modes without `MapCandidate` (Domination, Hardpoint) stay hidden on `de_` maps without data; a `Base` child of `snd`
  inherits the rule.
- Grouping: several entities per site, shared `targetname`, distant entities are separate sites; one or three sites
  are rejected with a reason.
- Naming by `MapCreationID` is deterministic for any input order; the place-name override works.
- Site point: AABB centre inside a wall moves to the next candidate; exhausted candidates give a reason;
  `radius`/`above`/`below` stay in bounds; `approach` is inside.
- Spawn filtering and the team-size threshold; the bomb is the nearest valid attacker spawn.
- Output passes the existing `Validate`.
- Cache invalidation by version, size and time; corrupt JSON is ignored.
- Reachability: reverse edges, no 10000-area cap, one-way links.

Glue and engine:

- SENT registration does not overwrite a foreign class.
- `GetModeData` returns authored data before generated data.
- A PREMATCH failure aborts with a readable reason instead of an error in LIVE.
- Global2 sites are cleared in `Cleanup`; the client rejects malformed values.
- Lobby, vote and playlist fit agree on client and server.

The mandatory T-11.12 cases in `TASKS.md` stay unchanged.

## 8. Approvals needed and side effects

| Item | Where |
| --- | --- |
| Objective mode without authored data; generator "after MVP"; mode hidden without data | `design/03-mapdata.md` d.4, d.6 |
| "Two authored sites", "recover at the authored point" | `design/02-modes.md` d.8 |
| Frozen: `ModeFits` semantics, new data layer, navmesh readiness signal | `docs/api/map.md` |
| Frozen: S&D activation, snapshot shape, HUD | `docs/api/modes.md:424-439` |
| New SENT on every `de_` map; navgen seeds | lane owners: map (`mapdata`, `navgen`), modes (`snd`), mode HUD |
| Labels when unsure (A/B or 1/2), spawn threshold, navmesh mandatory, fallback on invalid authored data | user decisions |

Risks of resolving every `de_` map before load:

- A generic rule in `ModeFits` would wrongly offer Domination, Hardpoint and Infection on `de_` maps; the rule must
  belong to S&D only.
- Playlists with `Maps = nil` and the vote fill with unverified `de_` maps; a rotation drops to LOBBY on the first
  failing map. The cache makes this one-time but not zero. Falling back to another mode on the same map is a core change.
- `de_` maps for other games and ports without `func_bomb_target` always fail after load.
- The client picker disagrees with the server when only the server has the failure cache.

## 9. Pending in-game checks (not run; need the user's permission and a free Deck)

Maps: CS:S `de_dust2`, `de_dust`, `de_aztec`, `de_cbble`, `de_inferno`, `de_nuke` (stacked sites), `de_train`,
`de_prodigy`, `de_piranesi`, `de_chateau`, `de_tides`, `de_port`; one CS:GO port from the Workshop; one `de_` map without
a `.nav`.

Commands (bridge prefix `lua <code>`):

1. Without a SENT: `print(#ents.FindByClass("func_bomb_target"))`; expect the console line
   `Attempted to create unknown entity type func_bomb_target!`.
2. With a SENT:

   ```lua
   for _, e in ipairs(ents.FindByClass("func_bomb_target")) do print(e:EntIndex(), e:MapCreationID(), e:GetModel(), e:WorldSpaceAABB()) print(e:LocalToWorld(e:OBBMins()), e:LocalToWorld(e:OBBMaxs()), e:GetSolid(), e:GetName()) end
   ```

3. Navmesh and places: `print(navmesh.IsLoaded(), navmesh.GetNavAreaCount())`, then collect `area:GetPlace()` over all areas.
4. A/B order: compare the `MapCreationID` order with the commonly known site names.
5. Cost of the current `Activate` on `de_dust2` with a navmesh (`pw_profile 1`); area count against the 10000 cap.
6. Confirm that the SENT neither blocks players nor renders.

## Sources

Accessed 2026-11-11. VDC pages were read through Wayback Machine snapshots because the site refuses automated fetches.

- [Source SDK 2013 `util.cpp`](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/util.cpp),
  [`mapentities.cpp`](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/mapentities.cpp),
  [`nav_file.cpp`](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/nav_file.cpp).
- [garrysmod-issues 6544](https://github.com/Facepunch/garrysmod-issues/issues/6544),
  [4121](https://github.com/Facepunch/garrysmod-issues/issues/4121),
  [2762](https://github.com/Facepunch/garrysmod-issues/issues/2762).
- Facepunch wiki: [Scripted Entities](https://wiki.facepunch.com/gmod/Scripted_Entities),
  [Lua Loading Order](https://wiki.facepunch.com/gmod/Lua_Loading_Order),
  [Entity:WorldSpaceAABB](https://wiki.facepunch.com/gmod/Entity:WorldSpaceAABB),
  [Entity:GetBrushPlaneCount](https://wiki.facepunch.com/gmod/Entity:GetBrushPlaneCount),
  [game.CleanUpMap](https://wiki.facepunch.com/gmod/game.CleanUpMap),
  [CNavArea:GetPlace](https://wiki.facepunch.com/gmod/CNavArea:GetPlace).
- VDC: [func_bomb_target](https://developer.valvesoftware.com/wiki/Func_bomb_target),
  [Brush entity](https://developer.valvesoftware.com/wiki/Brush_entity),
  [NAV file format](https://developer.valvesoftware.com/wiki/NAV_(file_format)).
- Facepunch `garrysmod` repository: `garrysmod/gamemodes/terrortown/gamemode/ent_replace.lua`,
  `garrysmod/gamemodes/terrortown/entities/entities/ttt_traitor_check.lua`,
  `garrysmod/gamemodes/base/entities/entities/base_brush.lua` (read, not copied).

Method: local inspection of design, contracts, source and tests; no third-party implementation copied.
