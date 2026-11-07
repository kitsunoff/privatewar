# Hardpoint API

Status: **frozen by orchestrator review; runtime implemented** in `modes/hardpoint.lua`,
`modules/hardpoint/` and `hud/hardpoint.lua`. Authored `gm_construct` data is included.
Shared commander containment/invalidation integration and normal-input smoke acceptance remain separate gates.
Observed test-first RED: 1396 passed / 12 failed / 0 skipped before implementation; activation/wire RED:
1396 / 15 / 0. First runtime GREEN (before lifecycle/smoke additions): 1411 / 0 / 0.

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

| Surface | Contract |
| --- | --- |
| `Inside`, `Presence`, `ScoreDelta` | Pure finite cylinder/eligible actor reduction; score once per team tick, never per occupant. Presence has control/contest only, not a public member list. |
| `ValidateLayout(data)` | Structural validation usable for remote maps without loaded world/nav geometry, using the frozen bounds below. |
| `VisitAt(start, now, duration, count)` | Arithmetic ordered wrap; distinct monotonic visit for repeated zone ids, absolute deadlines without hitch drift. |
| `NewState(layout, rules, start, generation)`, `Step(state, sample)` | Pure mutable reducer and explicit effects. Rules contain only `pointTime`, `scoreLimit`, `matchTime`; the single boundary policy below is mandatory. |
| `ArrivalFits(zone, projected, radius)` | Necessary containment check on the whole horizontal arrival disc and projected height, after navigation projection. Does not itself implement shared follower enforcement. |
| `PublicSnapshot`, `AcceptSnapshot`, `View` | Allowlisted public state, ordered generation/visit/revision, cleanup tombstone, separate zone and match clocks. No occupants, counts, actor positions or actor identities. Reuse presentation output outside paint. |

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

The S&D/shared owner supplies `PW.BotCommander.Sanitize`, `Eligible` and `InvalidateObjective(id, revision)`;
the latter emits `PW_ObjectiveInvalidated(id, revision)`. Objectives carry a current UserID `eligible` allowset,
`revision` and `zone = { pos, radius, above, below }`. Generic followers enforce projected **and actual**
cylinder containment. Invalidating a visit releases commander orders **and** goals through public `ClearGoal`.
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
it is neither a skipped placeholder nor evidence until its real run passes. No teleport, direct damage,
fabricated contacts or foreign private-store access occurs in its asserted movement path.
Preserve all 1395 baseline cases, especially T-2.4, T-2.9, T-5.10/11 and T-8.4, XP/streaks and health/ammo HUD.

After implementation: run full game gates, then stop for the human checkpoint: vertical/outnumbered contest,
map geometry and spawn travel fairness, one-bot rotation, objective marker and two readable clocks,
host/P2P join/abort cleanup and target-hardware profile. Existing HUD manual approval is still pending.
