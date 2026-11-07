# Hardpoint API proposal

Status: **DRAFT, not frozen**. Phase 1 contains declarations and test-first scaffolds only;
no production mode, module, settings, map layout or codec is implemented.
Runtime RED has not been observed. Synthetic fixture numbers are not gameplay defaults.

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
| First map | Explicitly authored `gm_construct` layout, then human verification |

The declared `pointTime`, `tickInterval`, `tickPoints`, `scoreLimit`, `matchTime` names are proposed schema keys;
the approved numbers above are no longer open questions. Exact setting ranges and zero/off semantics need freeze.

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

## Proposed typed seams

Declarations: `addons/privatewar/lua/privatewar/types/hardpoint.lua`.
`PW.Hardpoint` is optional and deliberately absent until review. All functions below are proposed, not frozen.

| Surface | Contract proposal |
| --- | --- |
| `Inside`, `Presence`, `ScoreDelta` | Pure finite cylinder/eligible actor reduction; score once per team tick, never per occupant. Presence has control/contest only, not a public member list. |
| `ValidateLayout(data, limits)` | Structural validation usable for remote maps without loaded world/nav geometry. Required bounds are passed explicitly. |
| `VisitAt(start, now, duration, count)` | Arithmetic ordered wrap; distinct monotonic visit for repeated zone ids, absolute deadlines without hitch drift. Ordering is proposed pending approval. |
| `NewState(layout, rules, start, generation)`, `Step(state, sample)` | Pure mutable reducer and explicit effects. Terminal latch emits at most one result; no replay of unsampled occupancy. All values/policies are required parameters. |
| `ArrivalFits(zone, projected, radius)` | Necessary containment check on the whole horizontal arrival disc and projected height, after navigation projection. Does not itself implement shared follower enforcement. |
| `PublicSnapshot`, `AcceptSnapshot`, `View` | Allowlisted public state, ordered generation/visit/revision, cleanup tombstone, separate zone and match clocks. No occupants, counts, actor positions or actor identities. Reuse presentation output outside paint. |

Proposed `MAP.Modes.hardpoint = { zones = { ... } }`: dense ordered records with unique nonempty `id`,
finite `pos`, positive finite `radius`/`above`, finite nonnegative `below`.
Reject gaps, duplicate ids, malformed/non-finite dimensions/coordinates and approved-bound violations.
Minimum zone count and size/id/array bounds need review; test-only bounds are explicit fixtures.
At current-map start, additionally validate usable floor/hull and bot reachability; remote structural validity
does not prove playable geometry. No map file is changed in phase 1.

The test reducer policies `rotationBoundary`, `deadlineBoundary`, `limitPrecedence`, `tieWinner` and
`maxSampleGap` are injection seams, **not** approved host settings or a promise to ship multiple rulesets.
Freeze one approved policy and simplify these seams before production implementation.

## Decisions required before implementation

Freeze exact rotation/deadline/score precedence; hitch sampling and sample cadence; respawn delay and protected
occupancy; ordered rotation/minimum layout and geometry bounds; next-zone disclosure; setting ranges/zero semantics.
No implicit TDM/Domination defaults may answer these remaining questions. The main preset above is approved.

Recommended for review, not decided: absolute authored order; rotation/deadline excludes same-time old-zone
scoring; skip unsampled score intervals; existing safe dynamic spawns. No early rotation/anchor allocation is needed.
The Hardpoint owner will author the first `gm_construct` layout after contract freeze, never derive it from DOM
flags. The same owner will add the approved two S&D sites in a separate commit after the S&D owner freezes its schema.

## Shared bot requests to the orchestrator

1. `Assign.keep` retains an in-radius `hold` even at `want = 0`. The characterization test specifies this for
   one, two and three bots; withdrawing the obsolete visit id releases it on the next normal commander pass.
   Immediate rotation/abort release still needs owner-provided generic invalidation of orders **and goals**.
2. Shared navigation projection and objective drift can exit the authoritative cylinder. Ask the shared bot owner
   for a typed containment/arrival validation extension preserved by sanitization; do not send guessed extra fields.
3. Keep all bot-store ownership intact. Hardpoint never reads/writes private commander/brain/goal stores,
   never overrides global anti-dither/defender caps and never fabricates enemy contacts.

Requested central contract additions belong to the assigned shared owner, not this branch:
`docs/api/modes.md` (mode and public bot lifecycle seam), `map.md` (approved zone schema),
`bots-blackboard.md` (generic invalidation and containment contract). No central contract is changed here.

## Test-first evidence and remaining work

`mode_hardpoint.lua` has the five requested rule/map intent names; `hardpoint_presentation_bots.lua`
has the three pure bot/presentation intent names. They intentionally reference absent declared helpers.
The map case covers structural rejection, `ModeFits` and existing Custom-start/vote/playlist filters with synthetic
data. Real mode registration, sparse/malformed layouts, current-world checks, approved-preset wiring and equal-score
draw assertions, exact match deadline ordering and protected actors await contract freeze and implementation.
The snapshot case tests a pure allowlist, not an implemented wire codec, request validation or real late joining.
The bot characterization does not prove immediate runtime hold/goal cancellation or legal-input movement.

`Hardpoint: bot holds then rotates through normal inputs` is recorded as a deferred smoke intent in the test file,
not a fake passing or skipped case. Add the real shared-bot smoke after contract/map freeze and Deck authorization.
Preserve all 1395 baseline cases, especially T-2.4, T-2.9, T-5.10/11 and T-8.4, XP/streaks and health/ammo HUD.

After implementation: run full game gates, then stop for the human checkpoint: vertical/outnumbered contest,
map geometry and spawn travel fairness, one-bot rotation, objective marker and two readable clocks,
host/P2P join/abort cleanup and target-hardware profile. Existing HUD manual approval is still pending.
