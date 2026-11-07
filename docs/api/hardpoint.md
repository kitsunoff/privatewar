# Hardpoint API

Status: **frozen by orchestrator review of phase 1**. Declarations and tests only;
no production mode, module, settings, map layout or codec is implemented. Runtime RED is still pending
the explicit Hardpoint Deck slot. No production logic before observed RED.

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
`PW.Hardpoint` is optional and deliberately absent until observed RED and subsequent implementation.

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
Remote structural validity does not prove playable geometry. No map file changes in this tests-only phase.

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

The S&D/shared owner supplies concrete APIs for a UserID eligibility set plus revision, sanitized typed cylinder
containment, and generic objective id/revision invalidation releasing commander orders **and** goals through
public `ClearGoal`. Arrival constraints survive navigation projection and fallback. Hardpoint waits for that
owner's actual API/commit before consumption or new-seam tests; it never invents extra metadata fields.
The existing `want = 0` sticky-hold case is characterization only, **not** runtime acceptance of rotation.
Do not access private bot stores, override generic defender/anti-dither policy or fabricate enemy contacts.

Requested central contract additions belong to the assigned shared owner, not this branch:
`docs/api/modes.md` (mode and public bot lifecycle seam), `map.md` (approved zone schema),
`bots-blackboard.md` (generic invalidation and containment contract). No central contract is changed here.

Hardpoint exclusively owns `maps/gm_construct.lua` across the mode lanes. Author three HP zones and the
approved two S&D sites only after actual Deck floor/hull/nav observations, in a separate map commit preserving
DOM flags verbatim. No automatic DOM conversion or assumed playable coordinates. The S&D schema is
`MAP.Modes.snd = { sites = { { id, pos, radius, above, below, approach }, ... }, bomb = Vector(...),
spawns = { [side] = PW.SpawnPoint[] } }`; keep synthetic test positions until real geometry is observed.

## Test-first evidence and remaining work

`mode_hardpoint.lua` retains all five requested rule/map intent names, and adds approved settings/bounds,
subsecond continuity, boundary departure/new-zone entry and deadline/draw cases.
`hardpoint_presentation_bots.lua` retains the three pure bot/presentation intent names.
Tests intentionally reference absent declared helpers. Map filters use synthetic data and existing Custom/vote/
playlist callers. Real activation geometry, actual shared bot-seam release/containment and smoke await their owners.
The snapshot case tests a pure allowlist, not an implemented wire codec, request validation or real late joining.
The bot characterization does not prove immediate runtime hold/goal cancellation or legal-input movement.

`Hardpoint: bot holds then rotates through normal inputs` is recorded as a deferred smoke intent in the test file,
not a fake passing or skipped case. Add the real shared-bot smoke after the shared API/map pass and Deck grant.
Preserve all 1395 baseline cases, especially T-2.4, T-2.9, T-5.10/11 and T-8.4, XP/streaks and health/ammo HUD.

After implementation: run full game gates, then stop for the human checkpoint: vertical/outnumbered contest,
map geometry and spawn travel fairness, one-bot rotation, objective marker and two readable clocks,
host/P2P join/abort cleanup and target-hardware profile. Existing HUD manual approval is still pending.
