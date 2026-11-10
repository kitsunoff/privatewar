# Performance report (T-10.4)

Final load test and profiler pass, 2026-11-07. Steam Deck, Proton, listen server, `maxplayers 12`, `gm_construct`.
Targets: `DESIGN.md` "Performance rules", `design/07-bots.md` "Performance budget" (`bots.tickbudget` 2 ms per
tick), `design/09-hud.md` (no allocations in `HUDPaint`), `design/00-core.md` d.6 (profiler).

## Summary

- The server Lua cost is small on average: 0.5 to 0.9 ms of the 15.2 ms tick (66 tick), p99 2 to 3.5 ms. The bot
  scheduler stays inside its budget: 0.12 to 0.25 ms per tick on average, p99 below 1.9 ms; 0.1 to 0.7 % of the
  ticks go over 2 ms, always because one job alone is longer than the budget.
- The worst finding was a stall, not a steady cost: every bot death built the bot class pool, which took about
  200 ms (one frozen frame of a fifth of a second per death, and about 2.2 s at the start of every match when all 11
  bots get a class in one tick). Root cause: `PW.Setting` rebuilt the whole settings index on every call outside the
  match snapshot. Fixed in the core: the pool now takes 14 to 26 ms, `PW.Setting` about 14 µs instead of 260 to
  290 µs.
- The largest steady allocation of the server was the stat mods sweep (`GetWeapons` for every player every tick,
  about 1.5 MB/s). Fixed: 81 µs per tick to about 3 µs, about 0 KB/s.
- The host's client runs at 110 to 130 fps (7.8 to 9.1 ms per frame on average, p99 11 to 14 ms). Our Lua is 0.35 to
  0.6 ms of it: the HUD (0.25 to 0.30 ms) and, in Domination, the flag drawing (0.22 ms).
- Lua net traffic with an idle host is close to zero: the gamemode sends only event messages (popups, hitmarkers,
  reveals) and the idle host earns none. NW2 traffic is engine side and not measured.

## Method

### Scenario

- 11 bots and the host (12 of 12 slots): `bots.fill 12` and, for the test only, `PW.BotsManager._FreeSlots = 0` (the
  manager normally keeps one slot free, which caps the bots at 10 with one human).
- TDM and DOM on `gm_construct`, score limit 1000 and no time limit, so the match does not end during the run.
- Each mode: start, wait 60 s (PREMATCH, countdown, every bot spawned), profile 180 s of LIVE, then
  micro-benchmarks, then `pw_abort`.
- The host is idle (nobody plays on the Deck): it stands, dies and respawns; its client draws the HUD (radar, popups,
  match status, DOM flags in DOM). `pw_bot_debug 0`.
- Every Deck action goes through the repository scripts under the Deck lock: `snap.sh` (deploy and map reload so the
  client runs the deployed code) and `cmd.sh` (the dev bridge).

### Profiler (dev only, never shipped)

`addons/privatewar-dev/lua/autorun/pw_profile.lua` with the pure aggregation in
`addons/privatewar-dev/lua/privatewar_dev/profile_stats.lua` (tests: `lua/tests/privatewar/dev_profile.lua`).

- `pw_dev_profile start <tag>` / `pw_dev_profile stop` on the server (bridge, server console or listen host); it
  starts and stops the host's client too (`pw_dev_profile_cl`). Reports go to the console as
  `[PW] profile <tag> <realm> ...` lines (`scripts/deck/logs.sh --once`).
- Zero cost while stopped: nothing is wrapped, no hook exists.
- While running:
  - every `hook.Add` callback is wrapped with a `SysTime()` timer and a `collectgarbage("count")` delta, keyed
    `<owner>@<event>` (owner: the string id, or `<kind>:<ClassName>` for an entity); rescanned every second;
    times are inclusive (a hook that dispatches another hook includes it);
  - every bot scheduler entry (`PW._BotSchedulerState`) and FIFO job is wrapped the same way, keyed
    `sched:<id prefix>` (`brain`, `perception`, `tactics`, `job`; `table` is the `bots_goal` path follower, whose
    id is its state table);
  - `net.Start` and the send functions are wrapped: bytes (`net.BytesWritten`) times human recipients per message;
  - every frame: the interval between frames, the top-level Lua hook time of the frame, the heap growth, the
    scheduler's last tick (`lastTickMs`), and on the client `RealFrameTime()`;
  - `pw_profile 1` (the core's `PW.Call` timings, `00-core.md` d.6) and `PW.Profile.Get()` in the report.
- Report: per series n, average, p50, p95, p99, max; per hook ms per second, calls per second, µs per call, ms per
  frame, longest call, KB allocated per second; the top hooks, owners, allocators, `PW.Call` entities and net
  messages.

### Limits of the method

- A listen server has no Lua access to the engine's own frame cost: `engine.ServerFrameTime` does not exist there.
  The server "frame" numbers are the interval between server `Think` calls (it follows the host's render frames on a
  listen server) and the Lua time spent in hooks. Engine work (physics, bot movement, traces' C++ part) is only
  visible as interval spikes.
- The load is not deterministic: how many bots see an enemy changes the aim and perception cost by a factor of 10
  between runs (TDM `bots_aim` was 25 µs per tick in a quiet run and 345 µs in a busy one). Fixed costs are
  therefore also measured with micro-benchmarks in the same game (`SysTime()` over 200 to 2000 calls).
- Wrapping costs about 1 µs per hook call; the allocation probe was added after the baseline run (the baseline has
  heap growth per realm, not per hook).
- Bots rarely kill each other on `gm_construct` in 3 minutes (0 to a few deaths per run), so death-time costs come
  from the micro-benchmarks.

## Numbers

### Server, per tick (ms)

| Run | Lua hooks avg | p95 | p99 | max | Scheduler avg | p95 | p99 | Over budget | Heap growth |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TDM before | 0.737 | 1.448 | 2.514 | 20.6 | 0.146 | 0.561 | 0.982 | 24 of 12067 | 2603 KB/s |
| DOM before | 0.527 | 1.150 | 2.040 | 16.6 | 0.115 | 0.573 | 0.945 | 15 of 12000 | 2379 KB/s |
| TDM after 1 (quiet) | 0.495 | 1.045 | 1.629 | 222.8 | 0.127 | 0.502 | 0.895 | 7 of 12000 | 2254 KB/s |
| DOM after 1 | 0.916 | 2.008 | 3.665 | 38.7 | 0.249 | 1.026 | 1.891 | 82 of 12067 | 2929 KB/s |
| TDM after 2 (busy) | 0.886 | 1.813 | 3.435 | 35.2 | 0.242 | 1.023 | 1.845 | 73 of 12000 | 2220 KB/s |
| DOM after 2 | 0.741 | 1.456 | 2.813 | 35.8 | 0.184 | 0.784 | 1.577 | 49 of 12000 | 1708 KB/s |
| TDM final | 0.836 | 1.694 | 2.946 | 22.5 | 0.215 | 0.839 | 1.548 | 40 of 12000 | 2086 KB/s |
| DOM final | 0.483 | 0.980 | 1.608 | 15.7 | 0.148 | 0.493 | 0.879 | 13 of 12000 | 1098 KB/s |

"After 1": the aim, win check and input fixes. "After 2": plus the stat mods fix. "Final": plus the settings index
fix. The 222.8 ms maximum of "TDM after 1" is the one bot death of that run: `bots_loadouts@PostPlayerDeath` took
212 ms (the class pool, fixed in "final").

Server tick interval (66 tick, 15.15 ms): average 15.0 ms in every run; p99 19 to 21 ms; maxima 28 to 47 ms besides
the death stall (final runs: p99 19.5 and 21.0 ms, max 35.5 and 31.3 ms).

### Server, top hooks (µs per call; one call per tick unless noted)

| Hook | TDM before | DOM before | After (runs 2 and final) | Note |
| --- | --- | --- | --- | --- |
| `bots_aim@Tick` | 266 | 114 | 25 to 345 | scales with bots that see a target; the params cache is a fixed saving (below) |
| `bots_scheduler@Think` | 150 | 117 | 117 to 252 | includes every bot tick and job it runs |
| `weapons_statmods@Think` | 81 (1.5 MB/s) | 81 | 3 to 28 (0.1 KB/s) | fixed |
| `PW.Match@Think` (`MODE:Think`) | 82 (tdm 54) | 53 (dom 25) | 54 to 68 (tdm 26) | the win check no longer sorts players in team modes |
| `bots_nav@Think` | 61 | 60 | 55 to 88 | cost-layer baking every tick |
| `bots_input@StartCommand` (per bot) | 24 | 20 | 19 to 29 | 140 to 260 KB/s |
| `sched:brain` (per bot tick, 10 Hz) | 22 | 30 | 22 to 49 | max 19 ms |
| `sched:perception` (per bot tick, 10 Hz) | 23 | 10 | 8 to 36 | |
| `sched:job` (`A*` slices, cover search) | 158 | 173 | 168 to 509 | max 15 to 20 ms: a job longer than the budget |

### Micro-benchmarks (in game, LIVE, 12 players)

| Cost | Before | After |
| --- | --- | --- |
| `PW.Setting` of a server-scope setting | 260 to 293 µs | 14 µs |
| `PW.Setting` of a match setting outside the snapshot (lobby) | 262 µs | 14 µs |
| Bot class pool (`PW.BotLoadouts.PoolFor`, every bot death; 11 per match start) | 194 to 222 ms | 14 to 26 ms |
| `progression.IsUnlocked` (47 calls per pool) | 4.4 ms | (follows `PW.Setting`) |
| Aim difficulty params per bot per tick (`ParamsFor` vs cached) | 0.8 to 2.2 µs and one 15-field table | 0.04 to 0.08 µs, no table |
| Stat mods tick, 12 players | 81 µs (profiled) | 2.5 to 3 µs |
| Team-mode win check (`modes:tdm` `Think`) | 53.5 µs | 25.9 µs |

### Client (host, HUD on)

| Run | Frame avg (ms) | p95 | p99 | max | Lua hooks avg | p99 | `HUDPaint` | Heap growth |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TDM before | 7.76 | 9.95 | 11.31 | 31.0 | 0.338 | 0.488 | 0.248 | 1528 KB/s |
| DOM before | 8.43 | 10.36 | 12.12 | 27.0 | 0.599 | 0.865 | 0.294 | 1747 KB/s |
| TDM after 2 | 8.54 | 10.78 | 12.93 | 47.2 | 0.355 | 0.519 | 0.253 | 1459 KB/s |
| DOM after 2 | 8.71 | 10.84 | 12.88 | 49.2 | 0.612 | 0.902 | 0.301 | 1686 KB/s |
| TDM final | 8.29 | 10.54 | 12.40 | 37.2 | 0.351 | 0.510 | 0.250 | 1509 KB/s |
| DOM final | 8.01 | 9.92 | 11.78 | 29.8 | 0.585 | 0.859 | 0.293 | 1834 KB/s |

No client code was changed; the client differences are run-to-run noise (what the host's camera sees).

HUD elements per frame (`PW.Call` timings, µs): `match_status` 64 to 77, `radar` 66 to 68, `dom` 61 (two calls),
`equipment` 25, `progression` 20 to 24, `streaks` 12, `popups` 4, `spectating` 3, `hitmarker` 1. DOM flags in the
world (`dom_flags@PostDrawTranslucentRenderables`): 0.22 ms per frame, five calls per frame.

### Net

Server to clients, Lua messages, 180 s per mode: only `DeathNoticeEvent` (engine Lua, 20 B, 0.01 per s). The
gamemode's messages are event driven (score popups, hitmarkers, reveals, class state, vote, lobby) and go to humans
only; an idle host earns none. `pw_bot_debug 1` adds its overlay message at 4 Hz (not measured here). Engine NW2
traffic (phase, scores, stat mods, streak state) is not visible to the Lua wrapper.

## Fixes

| Fix | Files | Effect |
| --- | --- | --- |
| Settings index reused while the mode and module lists hold the same entities (identity compare; a re-registration, re-resolution, disable or reload changes the lists) | `gamemodes/privatewar/gamemode/core/sh_settings_store.lua`, `lua/privatewar/types/settings.lua` | `PW.Setting` 260 to 290 µs to 14 µs; bot class pool 200 ms to 14 to 26 ms per bot death (2.2 s to about 0.2 s at match start) |
| Stat mods: the server reads a player's weapons only after a revision change or a `WeaponEquip` (the client path is unchanged) | `lua/privatewar/modules/weapons_statmods/shared.lua` | 81 µs and about 1.5 MB/s per tick to about 3 µs and 0 KB/s |
| Aim: difficulty params cached per bot (rebuilt when its difficulty copy, tier or tier entity changes); the aim debug record reused | `lua/privatewar/modules/bots_aim/init.lua`, `lua/privatewar/types/bots_aim.lua` | one 15-field table per bot per tick less (about 730 tables/s) |
| Team-mode win check builds no sorted player list (the standings of a team mode are the team kills) | `lua/privatewar/modules/match_rules/init.lua` | `modes:tdm` `Think` 53.5 µs to 25.9 µs |
| Input writer: rules that `_Rules` already merged are not merged again | `lua/privatewar/modules/bots_input/shared.lua` | one rules table per bot per tick less |

Tests: `lua/tests/privatewar/perf_hotpaths.lua` pins each fix (same answers, without the per-tick work);
`lua/tests/privatewar/dev_profile.lua` covers the profiler aggregation.

## Remaining hot spots (ranked)

1. **Bot class pool on every bot death, 14 to 26 ms.** `PoolFor` harvests every human's class state on every call
   (`docs/api/bots-blackboard.md` item 13: "taken whenever a pool is built"), and `ClassState` re-validates every
   class with about 50 unlock checks. With a human killing bots every few seconds this is still a visible hitch on a
   weak CPU. Options (contract change, orchestrator): harvest on upload, pick and level-up instead of per pool; or
   cache the pool per tick and per human state revision. A further core step: a registry revision counter so that
   `PW.Setting` does not call `GetList` twice per lookup (the remaining 14 µs).
2. **Scheduler jobs longer than the budget.** `sched:job` (`A*` slices, cover search), `sched:brain` and
   `sched:perception` reach 15 to 20 ms in single calls; 0.1 to 0.7 % of the ticks exceed 2 ms. The `A*` slice limit (150 expansions or 1 ms) does not
   hold under load or a GC step lands inside it. Next step: log the job kind of every over-budget tick and slice the
   long ones; check whether the spikes coincide with GC steps.
3. **`bots_aim@Tick`: up to 345 µs per tick and about 1 MB/s** when many bots fight. Per aim step it allocates the
   knowledge table, the `Lead` and `Step` option tables, a line-of-fire closure with its trace tables, an `Angle` for
   the view and two `Vector`s for the chest point. Reuse per-bot scratch tables and cache the head bone id.
4. **Client `HUDPaint` 0.25 to 0.30 ms per frame and 50 to 95 KB/s** (the design rule is no allocation in
   `HUDPaint`). `match_status` and `radar` are 65 to 75 µs each. Find the allocating element with the profiler's
   alloc ranking per element (wrap `PW.Call` for `hud:*`), then cache.
5. **Client DOM flags 0.22 ms per frame and 250 KB/s** in Domination. `PostDrawTranslucentRenderables` runs five
   times per frame (water reflection and refraction passes included), and the colour lookup per flag per pass
   (`team.GetColor`, which returns a copy) is the likely allocator. Cache the team colours; consider skipping
   non-main views.
6. **Client stat mods `Think`: 240 KB/s** (`GetWeapons` of the local player every frame). The server fix needs
   `WeaponEquip`, which is server only; a client equivalent (weapon count or `HUDWeaponPickedUp`) is needed.
7. **`bots_input@StartCommand` 19 to 29 µs per bot per tick, 140 to 260 KB/s**: the adapter's input rules are
   rebuilt per bot per tick, plus the facts and output tables. Cache the rules per weapon and adapter.
8. **`bots_nav@Think` 55 to 88 µs per tick** even without path requests (cost-layer baking every tick). Bake only
   when a layer changed.
9. **`PW.Match@Think` 54 to 68 µs per tick**: `MODE:Think` reads two settings through `mode:Setting` and builds the
   standings tables every tick. A once-per-0.1 s check would change when a match ends, so it is left for the modes
   lane.

## ARC9 (T-3.6 follow-up, 2026-11-07)

Same scenario (TDM, `gm_construct`, 9 bots and the host, 180 s of LIVE). In the ARC9 run every bot got an ARC9 AR or
SMG (MW2019 and Modern Warfare Classic packs) with one attachment; the HL2 run used the preset classes.

| Run | Server interval avg / p99 / max (ms) | Server Lua hooks avg / p99 / max (ms) | Client frame avg / p99 / max (ms) |
| --- | --- | --- | --- |
| ARC9 | 15.0 / 56.0 / 673 | 3.49 / 27.1 / 628 | 51.2 / 165 / 691 |
| HL2 | 15.0 / 25.3 / 107 | 2.39 / 5.9 / 87 | 17.5 / 33.5 / 121 |

- The long stalls are ARC9's first `Give` of a weapon class: 281 ms on average for the first copy of a class, 3.5 ms
  for the next one (micro-benchmark, 6 AR classes). `modules:loadout@PlayerLoadout` reached 622 ms. The adapter's
  `Apply` is 1.8 ms of it.
- The client frame is mostly engine rendering of the ARC9 world models: our client Lua is 2.7 ms of 51 ms;
  `ARC9_TranslucentDraw` 0.23 ms and `ARC9_TPIK` 0.19 ms per call are the largest Lua parts.
- Server-side ARC9 Lua: `ARC9.SetupMove` 58 µs per player tick, `ARC9_DoPhysBullets` up to 69 ms in one tick.
- Fixed in the integration: the loadout checks asked the adapter for the same slot and option lists for every class
  and option, and every answer copied the SWEP table and walked all ARC9 attachments. With the host's four classes in
  the bot pool, `PoolFor` took 84 to 114 ms (every bot death); with the memo it takes 19 to 21 ms, the same as with HL2
  classes.

ARC9 settings that reduce the cost (the precache pair is always set; the rest, except penetration, is the `deck`
performance profile below):

| ConVar | Realm | Value | Effect |
| --- | --- | --- | --- |
| `arc9_precache_wepmodels_onstartup`, `arc9_precache_attsmodels_onstartup` | server | 1 | moves the first-`Give` model loads to the map load; set by the gamemode (below) |
| `arc9_tpik_others` | client | 0 | no hand IK on other players (bots) |
| `arc9_lod_distance` | client | 0.3 to 0.5 | simpler world models at a distance |
| `arc9_cheapscopes`, `arc9_fx_rtvm` | client | 1, 0 | cheaper scopes, no render-target viewmodel |
| `arc9_muzzle_others`, `arc9_eject_fx` | client | 0 | fewer effects from other players' shots |
| `arc9_bullet_physics` | server | 0 | hitscan bullets instead of simulated ones (changes gameplay) |
| `arc9_ricochet`, `arc9_mod_penetration` | server | 0 | fewer traces per shot (changes gameplay) |

The integration sets the precache pair (`PW.Arc9.PrecacheConVars`). They are server ConVars (archived and replicated),
not client ones; ARC9 reads them once, about 1 s after its Lua loads on every map load, and then precaches the weapon
view models and the attachment models on the server. The integration sets them when its module loads and again on
`PW_WeaponsLoaded`; when ARC9 had not created them yet at that point, they take effect from the next map load (ARC9
archives them). They are not restored on `ShutDown`: a precache only moves load time to the map start.

## ARC9 performance profile (T-11.8, 2026-11-07)

`DESIGN.md` global rule 7 (optimisation first) and `design/04-weapons.md` d.7: the host setting `arc9.perf`,
`deck` by default, `off` restores the player's own ARC9 values. The ConVars, their realms and the crash-safe backup
are in `docs/api/adapter.md`, "ARC9 session ConVars".

| ConVar | Realm | `deck` value |
| --- | --- | --- |
| `arc9_tpik_others` | client | 0 |
| `arc9_lod_distance` | client | 0.4 |
| `arc9_cheapscopes` | client (unreplicated ConVar of each realm; the client's scope code reads it) | 1 |
| `arc9_fx_rtvm` | client | 0 |
| `arc9_muzzle_others` | client | 0 |
| `arc9_eject_fx` | client | 0 |
| `arc9_bullet_physics` | server (replicated) | 0 |
| `arc9_ricochet` | server (replicated) | 0 |
| `arc9_mod_penetration` | server (replicated) | not touched (stays on, measured below) |

### Penetration cost

Steam Deck, Proton, listen server, `gm_construct`, TDM, 9 bots and the idle host, the `deck` profile on (hitscan,
no ricochets). A dev-bridge timer gave every living bot an ARC9 AR or SMG (MW2019 and Modern Warfare Classic packs)
once a second whenever it held anything else (its probe line was filtered out of the log, so the share per moment
was not recorded); the bots fired about 13 to 17 bullets per second in total (`bots_perception@EntityFireBullets`
calls). Four 120 s profiles
in one match, alternating `arc9_mod_penetration` 1, 0, 1, 0 so that drift in the fight does not favour one side.

| Run | Penetration | Server Lua hooks avg / p95 / p99 / max (ms) | Server interval p99 / max (ms) | Client frame avg / p99 (ms) |
| --- | --- | --- | --- | --- |
| on 1 | 1 | 2.921 / 4.673 / 6.173 / 90.1 | 38.4 / 116.4 | 37.5 / 89.2 |
| off 1 | 0 | 2.955 / 4.746 / 6.435 / 48.8 | 37.5 / 73.4 | 38.8 / 81.8 |
| on 2 | 1 | 2.898 / 4.522 / 6.203 / 78.6 | 31.5 / 88.8 | 30.6 / 65.7 |
| off 2 | 0 | 2.868 / 4.636 / 6.341 / 38.6 | 36.4 / 222.1 | 35.0 / 75.0 |

- Average server Lua time: 2.910 ms with penetration, 2.912 ms without: no difference (threshold: 0.5 ms).
- p99: 6.17 and 6.20 ms with penetration, 6.44 and 6.34 ms without: not higher with penetration.
- The maxima of the "on" runs (90.1 and 78.6 ms) are `bots_loadouts@PostPlayerDeath` (84.7 and 73.7 ms in one call:
  the bot class pool on a bot death, hot spot 1 above), not the fire path. The server interval (which also covers
  engine work and Lua outside hooks, such as the weapon's bullet callback) shows no rise with penetration either.
- **Decision: penetration stays on in the `deck` profile.**

Side notes from the same runs (not penetration):

- ARC9's own `ARC9.SetupMove` costs about 37 ms per second on the server (60 µs per player tick, 10 players), the
  largest single server hook; the bot scheduler is about 53 ms per second.
- The host's client ran at 30.6 to 38.8 ms per frame with the `deck` profile. The ARC9 run above (before the profile)
  was 51.2 ms; the runs are not an A/B pair (other camera, other fights), so this is a hint, not a measurement of the
  profile. A profile A/B with a fixed camera is the manual check in the local manual checklist (not published) section 40 item 11.7.

## Infection cover-search opt-out (2026-11-10)

The generic `PW_CanSearchBotCover` veto changes search admission only; Infection returns false only for
infected. Goals, paths, intents, behavior eligibility and FIFO/A* scheduling are unchanged.
This is a bounded diagnostic, **not evidence of a causal pursuit-speed improvement**.

### Method and retained control

- Steam Deck, Proton, `gm_construct`, one human survivor and 1/2/5/10 infected bots. Initial world-death
  conversions and fixed navmesh-projected placement are fixture setup, before capture. Both arms have identical
  measured starting positions. Measured actors receive no forced contact, target, goal, behavior, aim, input,
  difficulty or teleport; human inputs are untouched. Capture stops at round completion or 20 seconds.
- Sight-only control: `5e12641`, whose production addon code is identical to `9896b49` (on `05df8c1`).
  Candidate: `ee9b4ea`. No unresolved tracking implementation is included. Passive dev instrumentation was
  committed before deployment (`de22b90`, `77e151a`, corrected at `090df21` and retained in the control).
- FIFO source classification and enqueue/dequeue timing are sampled without wrappers or extra traces.
  Completed observed jobs reconcile exactly with scheduler `jobsRun` deltas in all six accepted captures.
  Counts are **callbacks**, not proof each callback performed a search. FIFO waits are frame-sampled estimates,
  not exact enqueue timestamps; low job counts make percentile comparisons particularly weak.
- Zero movement is summed **bot-seconds**, from alive initial infected only: neutral movement commands in
  `SetupMove`, and horizontal physical speed at most 1 unit/s, respectively. Path cancellations are navigation
  service counter deltas. Native melee is the first observed positive native-fist enemy hit, not a range proxy.
  Native-hit `CurTime` timestamps are consistently 0.045 s beyond the last Think-domain elapsed timestamp;
  retain that hook-domain timing limitation. Other bots' time-to-hit is censored at round completion.
- An earlier four-count control (`sight_only`) is retained but discarded for comparison: a post-placement pause
  allowed bots to move before capture. The corrected captures start at the placement boundary. Personalities,
  existing memory, phase offsets and random decisions are not paired, and there is one accepted capture per cell.

### Accepted observations

`A` is sight-only; `B` adds the opt-out. Durations are Think-domain simulation seconds. FIFO statistics cover
all completed jobs; the one-job B sample at N=1 is not a latency distribution.

| Infected / arm | Duration (s) | Cover / path callbacks | FIFO mean / p95 / max (ms) | Zero command / velocity (bot-s) | Path cancels | First native hit (s) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 / A | 9.030 | 14 / 1 | 14.700 / 16.940 / 29.387 | 0 / 0.015 | 0 | 9.075 |
| 1 / B | 8.235 | 0 / 1 | 16.533 / 16.533 / 16.533 | 0 / 0.030 | 0 | 8.280 |
| 2 / A | 8.010 | 33 / 4 | 16.870 / 17.483 / 32.717 | 0.135 / 0.030 | 0 | 8.055 |
| 2 / B | 7.935 | 0 / 3 | 17.008 / 16.822 / 17.532 | 0.045 / 0.015 | 0 | 7.980 |
| 5 / A | 7.830 | 82 / 56 | 30.213 / 65.767 / 82.734 | 2.580 / 0.030 | 2 | 7.875 |
| 10 / A | 7.710 | 95 / 170 | 29.274 / 66.275 / 84.116 | 8.445 / 0.330 | 2 | 7.755 |

B at N=2 required one retry because the human was selected as initial infected. At N=5 both permitted
attempts selected the human, so the fixture rejected them **before measurement**. The matrix stopped at
the two-attempt boundary: **B at N=5 is unavailable; B at N=10 was not attempted**. No seed, role or behavior
was forced to bypass that stop. The earlier discarded N=1 control also needed one seed-selection retry.

The accepted small-count runs show zero infected cover callbacks with the veto, versus 14 and 33 without it.
They do not establish lower FIFO wait, less immobility or faster pursuit: the samples are small, durations and
behavior histories differ, and the requested large-count A/B cells remain incomplete. No trace-time, CPU-time,
framerate or gameplay-acceptance benefit is claimed. The remaining matrix is an incomplete verification item,
not a passed checkpoint.

### Regression evidence

The tests-first full installed-game run was RED **1912/4/0** (passed/failed/skipped): exactly the new
opt-out, execution, lifecycle and Infection-provider assertions failed. The first implementation run was
**1915/1/0**: its only failure was the new equipment-count fixture using a callable-table stub where the
runtime intentionally requires `isfunction`. The corrected fixture proves that a stale lethal count is
refreshed to its real zero inventory; no production guard or inherited assertion was weakened.

The completed unfiltered `gm_construct` regression passed **1916/0/0**, 187 groups, **191.431 seconds**;
`make check` also passed. Generic enqueue/execution veto, absent/nil/true fallback, non-cover fact refresh,
conversion/reset token ownership and failure isolation are covered by `bots_cover_policy.lua`; the
Infection-only provider is covered by `infection_rush_policy.lua`. Existing tactics-reset, scheduler and
actual A* slicing/cancellation/FIFO assertions remain intact. Temporary explicit-only capture probes are
removed after measurement; their committed history and the sight-only control retain reproducibility.

## Manual checks

For the local manual checklist (not published) (owned by the docs lane):

1. Play 10 minutes of TDM on the Deck with `bots.fill 12` (10 bots and the host; the manager keeps one slot free) and
   kill bots often: no hitch when a bot dies, no hitch at the start of the match.
2. Same in Domination: the flags draw smoothly, the frame rate holds while capturing.
3. Perks that change stat mods (for example Sleight of Hand): pick up a weapon from the ground and reload it; the
   modifier applies to the picked-up weapon at once.
4. Change `bots.difficulty` in the lobby between matches: the bots' aim follows the new tier in the next match.
5. Profiler: `scripts/deck/cmd.sh "pw_dev_profile start t1"`, play, `scripts/deck/cmd.sh "pw_dev_profile stop"`,
   then `scripts/deck/logs.sh --once | grep "profile t1"` shows the server and client reports.
