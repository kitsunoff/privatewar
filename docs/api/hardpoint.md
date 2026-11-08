# Hardpoint API

Status: **frozen by orchestrator review; runtime implemented** in `modes/hardpoint.lua`,
`modules/hardpoint/` and `hud/hardpoint.lua`. Authored `gm_construct` data is included.
The earlier shared follower blocker is historical; current combined-base fixture evidence is recorded below.
Observed test-first RED: 1396 passed / 12 failed / 0 skipped before implementation; activation/wire RED:
1396 / 15 / 0. First runtime GREEN (before lifecycle/smoke additions): 1411 / 0 / 0.
Normal-input bot target: 1 / 0 / 0. Historical pre-mount combined run: 1472 / 1 / 9.
Historical mounted-source combined run: **1474 / 10 / 0** (passed / failed / skipped), 1484 cases / 125 groups.
Nine failures are mounted Infection rules/presentation with no runtime implementation; one is the generic projected
cylinder/frame-identity seam. Hardpoint itself is **24 / 1 / 0**, 25 cases. No mounted failure is disguised as a skip.
The original 1395 baseline cases remain passing and unchanged.

User-approved configurable preset (recorded during phase 1):

| Parameter | Approved default/policy |
| --- | --- |
| Zone duration | 60 seconds |
| Scoring | 1 team point per second of exclusive living occupancy |
| Score limit | 250 points |
| Match time | 600 seconds; compare final team scores |
| Equal final score | Draw |
| Additional personal rewards | None |
| Bot allocation scope | Go to the active zone; no early rotation/anchor complexity |
| First map | Three explicitly authored `gm_construct` zones, then human verification |
| Rotation | Authored array order, first index 1, deterministic wrap; next zone hidden until rotation |
| Respawn | Existing ordinary 3-second respawn and safe spawn system |
| Eligibility | Living roster participants who are not observers; no new god/protection exclusion |

Host settings `hardpoint.zonetime` (default 60, range 5..600 seconds), `hardpoint.scorelimit`
(250, 1..1000 points) and `hardpoint.timelimit` (600, 60..3600 seconds) are finite, positive and clamped.
Non-finite values are rejected; zero clamps to the positive minimum, never disables the limit.
Scoring is fixed at one whole point per verified second. No boundary/tie/sample policy settings are exposed.

## Approved scope and existing boundaries

Hardpoint ships in the main addon with two balanced teams and one active authored rotating zone.
Only exclusive living occupancy scores; empty or any opposing occupancy scores zero, including 3 versus 1.
No retained ownership, capture scalar or automatic conversion of Domination flags.
Domination's empty-owned-point scoring remains unchanged.

Use `MODE.Start/Cleanup/Think`, `PW.Call`, `MODE.MapData` and existing map filtering
(`02-modes.md` d.6/d.7; `03-mapdata.md` d.4/d.6/d.7).
Use `MODE:BotObjectives(team)` with existing `hold` actions (`07-bots.md` d.14).
Use the single HUD registry paint loop (`09-hud.md` d.3) and existing style/scaling (`10-frontend.md`).
The additional mode scope is authorized separately; this draft does not modify `02-modes.md` d.5.

## Typed seams

Declarations: `addons/privatewar/lua/privatewar/types/hardpoint.lua`.
`PW.Hardpoint` is optional, supplied by module `hardpoint`.

### Playtest guidance and pressure extension

The screen waypoint uses only the accepted current-zone snapshot, never a future zone or hidden actor data.
`ProjectWaypoint(right, up, forward, fov, width, height, out)` is pure camera-space projection with reusable output.
Onscreen bearings project normally; offscreen and behind bearings intersect a central HUD-safe rectangle and carry
a directional arrow angle. Exact-behind has a finite turn cue. Invalid coordinates hide and reset the output.
`Guidance(snapshot, phase, mode, playerVisible, ownTeam, distance, out)` returns the current zone id, relative control
palette token, `capture` / `defend` / `contested` label key and nearest-metre distance (Source units times 0.0254).
It hides outside active LIVE Hardpoint or for a dead, observing or nonparticipating viewer. The client confirms the
published HP score prefix in addition to the active snapshot, so a stale snapshot cannot appear in another mode.
HUD strings, fonts and polygons are prepared outside paint; the waypoint does not use depth/occlusion traces.
Existing score clocks and the optional world marker remain. Client visual acceptance is separate from pure math.

The coordinator-frozen generic objective extension is `PW.BotObjective.urgency?: number`, finite and clamped 0..1.
Absent, mistyped or nonfinite urgency means the exact legacy behavior; malformed urgency never discards an otherwise
valid objective. The sanitized field passes through commander orders and local resolution without enemy metadata.
HP emits 1 for an empty, enemy-controlled or contested point, or while behind; a friendly leading hold emits 0.5.
Only the current visit is eligible. Opt-in objective rank 31 beats ordinary combat/chase rank 30, never survival 40.
A recognized visible threat at or within 400 units yields to ordinary combat, including during the cached rank
interval. Distant recognized contacts remain legal aim targets during objective movement through `ctx:SetTarget`;
the normal aim/fire/reaction/flash policy still decides whether a shot is allowed. No enemy contacts are invented.
Urgent travel releases a suspended direct strafe drive, avoids sprinting while aiming at a recognized enemy, and
does not chase distant enemies out of the active point. Non-opt-in DOM/KC/S&D selection remains unchanged.

Test-first native scope before implementation: 1 passed / 12 failed / 0 skipped across the initial 13 guidance and
pressure cases. A separate cached-near-threat regression was observed RED (7/1/0) before the safety correction.
The team smoke adds three teammates through ordinary LIVE engine spawns and the public board-provider seam;
at least two must hold both visits for 2 seconds, move through actual CUserCmd and travel more than 64 units.
It is team movement evidence, not opposing-team combat, all-zone fairness or a human playtest checkpoint.

| Surface | Contract |
| --- | --- |
| `Inside`, `Presence`, `ScoreDelta` | Pure finite cylinder/eligible actor reduction; score once per team tick, never per occupant. Presence has control/contest only, not a public member list. |
| `ValidateLayout(data)` | Structural validation usable for remote maps without loaded world/nav geometry, using the frozen bounds below. |
| `VisitAt(start, now, duration, count)` | Arithmetic ordered wrap; distinct monotonic visit for repeated zone ids, absolute deadlines without hitch drift. |
| `NewState(layout, rules, start, generation)`, `Step(state, sample)` | Pure mutable reducer and explicit effects. Rules contain only `pointTime`, `scoreLimit`, `matchTime`; the single boundary policy below is mandatory. |
| `ArrivalFits(zone, projected, radius)` | Necessary containment check on the whole horizontal arrival disc and projected height, after navigation projection. Does not itself implement shared follower enforcement. |
| `PublicSnapshot`, `AcceptSnapshot`, `View` | Allowlisted public state, ordered generation/visit/revision, cleanup tombstone, separate zone and match clocks. No occupants, counts, actor positions or actor identities. Reuse presentation output outside paint. |
| `ControlToken(control, contested, ownTeam)` | Pure relative style token: neutral `text`, contested `warning`, otherwise `team_friendly` / `team_enemy`; no dark engine team colours. |

`MAP.Modes.hardpoint = { zones = { ... } }`: a dense ordered array of 2..16 zone records.
Each has unique nonempty `id` (at most 32 bytes), finite `pos`, finite `0 < radius <= 4096`,
finite `above > 0`, finite `below >= 0`, total vertical extent `above + below <= 2048`.
Reject gaps, duplicate ids, malformed/non-finite dimensions/coordinates and bound violations.
At activation on the loaded map, also validate usable floor, hull clearance and bot nav reachability.
Remote structural validity does not prove playable geometry. `ValidateActivation(layout, probe)` checks each
structurally valid zone through a supplied cold probe. `CheckActivation(layout)` performs loaded-world floor,
standing-hull, projection and directed-nav checks, including routes from detected initial spawns.

## Observed occupancy and boundary order

Sample uniformly at approximately 0.1 seconds, reusing buffers; no hot-loop allocations.
Only observed completed intervals of exclusive occupancy accumulate credit, in whole one-second points.
The first sample establishes presence and awards nothing. Consecutive compatible control observations verify
their elapsed interval; empty/contested/changed control breaks continuity, and fractional credit cannot transfer
between teams or visits. The sample at a boundary is checked against the old zone before rotation.

1. Credit verified elapsed occupancy strictly before the boundary, including an interval ending exactly there.
   Full observed control from 0 through 60 seconds yields 60 points, not 59.
2. A departing old occupant or newly entered zone cannot supply a missing historical observation. The new visit
   starts from its actual sample, with no inherited credit; repeated timestamps do nothing.
3. An observation gap greater than 1 second discards pending fractional credit and rebases presence with no
   catch-up. Rotation and the match deadline remain absolute; compute skipped visits arithmetically.
4. A score-limit result before the match deadline finishes once, before any further rotation/action. At the
   deadline, credit the verified interval lying before it, then compare final scores; equal scores draw.
   Never score time after the deadline or emit rotation/actions after finishing.

This is conservative sampled occupancy, not continuous motion reconstruction. Tests use endpoint observations
and explicit gaps; no latest snapshot is retrospectively replayed over a stall.

## Shared bot integration and map ownership

The S&D/shared owner supplies `PW.BotCommander.Sanitize`, `Eligible` and `InvalidateObjective(id, revision)`.
Hardpoint emits `PW_ObjectiveInvalidated(id, revision)`; the commander consumes it through its helper, and the
brain can end the old frame. Objectives carry a current UserID `eligible` allowset,
`revision` and `zone = { pos, radius, above, below }`. Generic followers enforce projected **and actual**
cylinder containment. Invalidating a visit releases commander orders **and** goals through public `ClearGoal`.
The shared follower must record `frame.state.id` and `frame.state.revision` for matching running/suspended
brain invalidation. Through the integrated commander/brain commits, that S&D-owned follower implementation is
still missing: its legacy path accepts an outside projected goal and does not record the revision. The executable
HP seam case stays RED rather than silently accepting metadata declarations as enforcement.
Hardpoint emits one `hold` objective for the active visit, wants every eligible living bot of the requested team,
and invalidates the previous identity on rotation, finish and cleanup. Without the shared invalidation API,
`Objectives` fails closed with an empty list rather than claiming legacy metadata stripping is safe.
The existing `want = 0` sticky-hold case is characterization only, **not** runtime acceptance of rotation.
Do not access private bot stores, override generic defender/anti-dither policy or fabricate enemy contacts.

Requested central contract additions belong to the assigned shared owner, not this branch:
`docs/api/modes.md` (mode and public bot lifecycle seam), `map.md` (approved zone schema),
`bots-blackboard.md` (generic invalidation and containment contract). No central contract is changed here.

Hardpoint exclusively owns `maps/gm_construct.lua` across the mode lanes. Three ordered HP zones and two S&D
sites were authored after locked Deck floor/hull/nav observations, preserving DOM flags verbatim.
They are original authored points, not a DOM conversion. The S&D schema is
`MAP.Modes.snd = { sites = { { id, pos, radius, above, below, approach }, ... }, bomb = Vector(...),
spawns = { [side] = PW.SpawnPoint[] } }`, with side keys `1` and `2`. Six nonoverlapping standing-hull-checked
spawn points per side share the observed directed nav components. Human travel/vertical fairness is not certified.

## Networking and lifecycle

`Start(mode)`, `Think(mode)` and `Cleanup(mode)` back the ordinary mode lifecycle; `Objectives(mode, team)`
backs `BotObjectives`. State and actor/sample buffers belong only to Hardpoint. Presence/effect buffers are reused;
sampling uses `player.Iterator`, not entity searches. Kills retain TDM's normal score events, but HP points are
independent whole-team counters (`pw_hp_score_1`, `pw_hp_score_2`). Holding never emits a personal reward.
`MODE.HudScoreKey = "pw_hp_score_"` explicitly selects those objective counters for generic match status instead
of inherited TDM kills. The matching presentation regressions were observed RED (3/2/0 across the five-case group)
before the score-prefix and shared relative-palette runtime fix.

`pw_hp_state` is server-to-client only, written/read by `WriteSnapshot`/`ReadSnapshot`, in this exact order:

1. Generation `UInt(32)`, revision `UInt(32)`, visit `UInt(16)`, active `Bool`.
2. Active zone only: id `String` (authored 1..32 bytes), position `Vector`, radius/above/below `Float`.
3. Absolute zone and match deadlines `Float`, control `UInt(2)`, contested `Bool`, two scores `UInt(10)`.

The bounded message is below 1024 bits. It has no occupant list, actor/count data, next-zone index or geometry.
Changed control/contest, whole scores, rotation and finish publish a new revision; clocks never send countdown ticks.
Cleanup publishes one inactive higher-revision tombstone and repeated cleanup does nothing.
The client retains the generation fence across phase changes and rejects stale visits/revisions.

Late clients send empty `pw_hp_request` through `PW.Net.Receive`: any sender, `LIVE` only, twice per second,
maximum zero payload bytes, owned by the enabled module. The handler also requires exactly zero bits and a running
Hardpoint mode; it sends the current allowlisted snapshot only to the caller. Clients reject state above 1024 bits.
HUD drawing uses the single HUD registry loop and only the active point marker plus labelled ZONE/MATCH clocks.
Fresh-client 1280x720 evidence was inspected after the prefix/palette fix: the active marker and both clocks are
readable, and match status shows HP 7/0 rather than team kills 0/0. This is agent visual evidence, not the user's
manual checkpoint. Human-only stationary camera staging is not used as bot-movement evidence.

## Test-first evidence and remaining work

`mode_hardpoint.lua` retains all five requested rule/map intent names, and adds approved settings/bounds,
subsecond continuity, boundary departure/new-zone entry and deadline/draw cases.
`hardpoint_presentation_bots.lua` retains the three pure bot/presentation intent names.
Map filters use synthetic data and existing Custom/vote/playlist callers. `hardpoint_integration.lua` covers
activation rejection, the actual bounded wire codec and loaded-map authored geometry. `hardpoint_lifecycle.lua`
characterizes start/cleanup idempotence, activation failure and reward separation; these glue cases were added
after implementation, unlike the reducer and activation/wire test-first cases.

`hardpoint_bot_smoke.lua` contains executable `Hardpoint: bot holds then rotates through normal inputs`.
It uses a real player bot, actual scheduler/commander/objective/follower/input code and a public board-provider
fixture, observing both cylinder occupancy and actual user commands. It fails if the shared seam is missing;
it is neither a skipped placeholder nor evidence for general projection safety. The real target passed with
5.9 / 2.1 seconds of occupancy at visits 1 / 2, 1291 movement commands and 2977 units of travel in 29.689 seconds.
That historical full run also passes it: 9.3 / 2.1 seconds, 933 movement commands, 2566 units of travel, visit 2 reached.

Independent combined-base review subsequently exposed a fixture setup defect: outside `LIVE`, the ordinary spawn
selector declines selection, so the engine can choose a distant arbitrary map spawn. The corrected smoke scopes
the public match phase getter to `LIVE` and installs the actual HP mode before bot creation and initial spawn;
the phase getter and previous mode are restored after the case. It records initial body/team/observer/held/nav state.
No private phase store, production spawn policy or authored map data is changed, and no fixture spawn pool is used.
On the combined base plus the approved common lobby cleanup, the native two-group scope passes **15 / 0 / 0**;
HP holds **14.3 / 2.0 seconds** with **702 movement commands**, **2159 units** of displacement and visit 2 reached.
The 20-second rotation, 75-second case timeout, 65-second journey bound, both 2-second holds, movement and score
assertions remain unchanged. There is no teleport during the measured journey. This controls a subsystem fixture;
it does not establish production random-spawn/all-zone travel fairness or replace human playtesting.
The subsequent unfiltered combined run, with a 480-second whole-run budget and unchanged case timeouts, completes
**1587 / 8 / 0**, 1595 cases / 138 groups in **239.707 seconds**. All Hardpoint cases pass, including the shared
seam and native smoke: **10.5 / 2.0 seconds**, **947 movement commands**, **2423 units**, visit 2.
Combat-moves also passes. Remaining failures are three ARC9 integration cases, two Infection lifecycle cases and
native bot goal/engagement/combat cases; the combined suite is not GREEN. No cause is asserted for those failures,
and no out-of-scope fixture or production code is changed to suppress them.
No teleport, direct damage,
fabricated contacts or foreign private-store access occurs in its asserted movement path.

Latest executable case map:

| Test file (`lua/tests/privatewar/`) | Cases | Latest result |
| --- | --- | --- |
| `mode_hardpoint.lua` | 10 | pass: preset, occupancy, height, ordered rotation, boundaries, stalls, continuity, deadline/draw, schema and filtering |
| `hardpoint_presentation_bots.lua` | 5 | pass: score prefix, relative palette, legacy sticky-hold characterization, arrival geometry, allowlisted/stale snapshots and two clocks |
| `hardpoint_integration.lua` | 3 | pass: activation rejection, actual codec, real authored-map activation / preserved DOM |
| `hardpoint_lifecycle.lua` | 5 | pass: cleanup, once-only invalidation, request rejection, activation failure, no hold rewards |
| `hardpoint_bot_smoke.lua` | 1 | pass: real normal-input hold then rotation |
| `hardpoint_shared_seam.lua` | 1 | **fail**: generic follower accepts an out-of-cylinder projected arrival disc; also requires frame id/revision |

Preserve all 1395 baseline cases, especially T-2.4, T-2.9, T-5.10/11 and T-8.4, XP/streaks and health/ammo HUD.

After implementation: run full game gates, then stop for the human checkpoint: vertical/outnumbered contest,
map geometry and spawn travel fairness, one-bot rotation, objective marker and two readable clocks,
host/P2P join/abort cleanup and target-hardware profile. Existing HUD manual approval is still pending.
