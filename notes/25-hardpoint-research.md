# Hardpoint: implementation research

**RESEARCH / NOT DECIDED.** Original implementation plan, not authorization to implement Hardpoint or alter decisions.
Base inspected: `integration/current-work`, `3754fe2ed359c069034568d88054f24aabb1562d`, 2026-11-07/08.
No gameplay code, downloaded addons/assets, game runs or performance measurements accompany this study.
Repository citations use `P = addons/privatewar/lua/privatewar/` and
`C = addons/privatewar/gamemodes/privatewar/gamemode/core/`.
Mode concepts below are proposals from genre knowledge, not an attempt to reproduce one commercial ruleset exactly.

## 1. Constraints and recommended first scope

`design/02-modes.md` d.5 schedules S&D first after MVP; Hardpoint is additional scope requiring user approval.
`02-modes.md` d.6 already decides balanced human/bot teams and `PW.IsEnemy` relationship checks.
Recommend two teams, one active authored zone, fixed authored rotation, finite point lifetime, immediate control,
no retained capture progress, no points while empty or contested, and normal delayed respawns.
Recommend score-limit or finite match-time termination with a draw on an equal final score; no overtime initially.
Active and next-zone locations are public; recommend a pre-announcement window and an always-visible ordered list,
subject to user approval of that information policy. No timing, score, reward or unlock numbers are set here.
Keep normal validated classes and current spawn protection settings; do not add free equipment or mode-specific buffs.
Bot play, objective HUD and joining-in-progress must ship with the first playable implementation.

FFA is technically possible as a separate variant, not a trivial `Teams = 0` change:
commander currently supplies no objective orders to unteamed bots; player scoring, presence identities,
HUD standings and contested-player rules would need explicit contracts (`docs/api/modes.md`, FFA open item 12).
N-team infrastructure is retained, but do not claim N-team Hardpoint validation from two-team tests.
Defer shuffled rotations, capture-time variants, moving zones, special spawn anchors, overtime and new progression awards.

## 2. Existing capability and gap matrix

| Concern | Confirmed evidence | Reuse boundary / gap |
| --- | --- | --- |
| Lifecycle | `C/sv_match.lua:128–132,158–159,337` | `PW_PhaseChange`, mode `Start`, then `PW_MatchStart`/spawn; mode `Think` only in `LIVE`. No private engine Think hook needed. |
| Respawns and classes | `P/modes/tdm.lua`; `P/modules/match_rules/init.lua:151–176`; `docs/api/loadout.md` | TDM delay and `PW_CanRespawn` can be reused; kill-limit `Think` must not be inherited as Hardpoint victory. |
| Objective standings | `P/modes/dom.lua:117–140,181–205` | Own team scores, publish and `_Evaluate` pattern exist; do not use personal `PW.Score` totals or kills as hold score. |
| Presence | `P/modules/dom_flags/shared.lua:24–57`, `_Inside`, `_Infos`, `_Presence` | Alive/non-observer filtering and bounded player snapshot are useful patterns; fixed cylinder lacks per-zone geometry, walls and floor separation. |
| Capture | `P/modes/dom.lua:38–60`, `_Step`, `_Contested`, `_Hold` | Dom retains ownership and scores empty points; both conflict with the proposed occupancy-only Hardpoint. |
| Map filtering | `docs/api/map.md`, `PW.Map.ModeFits`, `GetModeData` | Existing Custom/vote/playlist compatibility applies; zone/rotation schema and validators do not exist. |
| Spawn safety | `P/modules/spawns/init.lua:116–158`, `Pick`, `PW_SelectSpawn` | Existing distance/LOS/hull scoring works; objective-relative weighting/anchor selection is not a public option. |
| Bot actions | `P/bot_behaviors/objective.lua:12–13,72–94` | `hold` walks inside a zone; `defend` guards outside. Retake, rotation deadlines and occupancy-aware slot allocation need policy. |
| Commander | `P/modules/bots_commander/shared.lua:83–143`; `init.lua:79–87,117` | Hard-coded defender share, sticky active holds and stripped metadata prevent assuming full mode-specific allocation works. |
| Score HUD | `P/modules/match_rules/shared.lua:31–48`; `P/hud/match_status.lua:84–93,200–208` | `HudScoreKey` allows own score bars; one shared mode deadline does not describe both point and match clocks. |

`docs/api/modes.md` describes the existing Dom rules precisely: signed scalar, capped net capture speed,
retained owner, equality-based contest and periodic held-flag scoring. These are not a generic zone-control engine.
Keep Dom behavior/tests unchanged. Reuse public surfaces or propose an approved extraction of pure geometry;
reading another mode's private `_Flags` or mutating its helpers would violate module isolation.

## 3. Minimal loop and deterministic ordering

Text state outline (proposal):

```text
core PREMATCH -> LIVE -> POSTMATCH -> existing lobby/vote flow
mode initialize -> active point -> advance ordered index -> active point -> ...
active occupancy: empty | team-controlled | contested
score/time terminal result -> stop rotation and scoring -> cleanup
abort/module error -> cleanup, no extra award or pending point activation
```

At `Start`, validate current-world feasibility, initialize score/timing state and publish the first point
before `PW_MatchStart` causes the match spawn. There is no round loop and no `PW_RoundStart` requirement.
Each point has a stable authored id plus a visit generation; repeating the same id later is a distinct visit.
A pure state step takes timestamps, filtered presence and rules; engine glue samples players and executes its outputs.

Recommended control definition, requiring approval:

- Only one team has eligible members inside: controlled by that team, regardless of its head count.
- Both teams have any eligible member inside: contested, no team scores, even if one side outnumbers the other.
- Empty: neutral and no scoring; previous control does not persist for score purposes.
- Dead, observing, out-of-match or wrong-generation players never count; invulnerability policy needs confirmation.

That differs intentionally from Dom, where `_Contested(plus, minus)` is true only at equal nonzero counts
and unequal numbers still move its capture scalar. Hardpoint needs no scalar unless the user chooses a capture delay.
For scoring propose a fixed due-time cadence and one award to the controlled team per eligible tick,
not multiplied by occupants; points and cadence remain settings to decide.
Do not repeatedly award personal XP to every player merely because the reducer runs again.

Candidate boundary policy, to approve before implementation:

1. Commit the current validated life/presence snapshot; no death hook directly increments hold score.
2. Process scheduled events by their timestamp, not callback arrival order. A score tick strictly before rotation
   belongs to the old point; at exactly rotation time the old point gets no tick and the new visit begins neutral.
3. End-of-match time excludes scoring at or after that timestamp. Apply all teams' valid same-time deltas together,
   then check score limit before time-limit standings, matching `_Evaluate` precedence.
4. If a score tick ends the match, do not rotate or emit another active-point notification afterward.
5. Do not catch up missed scoring from only the latest presence snapshot after a stall. Skip unsampled intervals
   rather than retroactively crediting a team that just entered. Rotation stays on its absolute schedule.

The final point is a deliberate conservative approximation, not a claim of continuously measured occupancy.
Test and disclose skipped intervals; a future occupancy-event accumulator is an alternative if the user requires exact hold time.
Do not let `next = now + duration` silently drift the point schedule after every hitch; cap boundary processing work,
compute skipped visits arithmetically and derive the active id/deadline once. Publish only the final current snapshot.
Use server `CurTime` gameplay deadlines, not `RealTime` or a per-frame countdown broadcast [E1].

## 4. Map schema, authoring and fallback

Proposed `MAP.Modes.<mode id>` data contains an explicit ordered zone-id list and zone records with
name/marker, centre, horizontal shape and vertical bounds; names and field identifiers are not frozen contracts.
Recommend finite cylinders for the first version, authored to avoid walls and stacked floors;
boxes or compound polygons can follow only if real maps require them. A huge radius is not a room boundary.
Keep marker position separate from the navigable goal where necessary; arrival radius must lie inside the scoring volume.

Structural validation must work for remote maps in `ModeFits` without their geometry loaded:
nonempty finite records, unique ids, positive bounded dimensions, valid order references and enough distinct zones
to make rotation meaningful. Recommend multiple distinct zones; exact minimum is a user choice.
Reject duplicate consecutive ids unless the chosen rotation model explicitly allows them; wrap order deterministically.
At current-map start additionally check floor/hull clearance, player access and bot nav reachability,
vertical overlap, dangerous ground and usable approaches. A valid Lua Vector alone proves none of these.
Missing/unreachable nav must not trigger automatic generation; retain the existing lobby warning/generation flow.

`design/03-mapdata.md` d.4/d.6 requires authored objective data and hides unsupported mode/map pairs.
Recommend no silent Dom-to-Hardpoint conversion: Dom vectors contain neither safe zone extents nor a validated route.
An explicit later generator could propose a layout for human approval under the existing lowest-priority layer model;
it cannot promise fair play on every map. This does not block TDM/FFA/KC on unsupported objective maps.
`pw_mark` supports spawn/dom/header only (`docs/api/map.md`, “pw_mark”);
a mode-aware zone/extent/order authoring extension needs orchestrator approval and parse/round-trip tests.
A full in-game editor is not part of the minimum slice. Ship at least one checked authored layout with the mode,
not a mode that appears in the registry but has no playable supported map.

Spawn fairness: start with existing dynamic spawn scoring and hull checks (`03-mapdata.md` d.7).
It knows live enemies internally for safety; this must not become bot target knowledge or replicated enemy coordinates.
There is no objective-relative “anchor team” or spawn-flip API today; do not promise commercial-style spawn control.
Measure both teams' travel times to every point, vertical shortcuts, first spawns and repeated deaths near exits.
If tuning is necessary, the spawns listener answers before the mode default; a new mode method alone will be preempted.
An approved options seam is preferable to copying the picker or disabling its LOS/hull safety.

## 5. Bots: hold, break, rotate and anchor

Minimum allocation is not “send every bot to the active centre”. Recommend separate occupancy and approach goals:
one or a small group enters to score, others cover entrances/flanks; a losing team sends a coordinated break group;
near rotation a limited group moves to the next announced point, while an anchor watches a reachable approach.
Numbers, pre-rotation time and anchor share are balance decisions; with one bot, score/contest takes priority over empty anchoring.
`hold` can represent in-zone occupancy; an active-point break may initially use the existing approach behavior.
Do not advertise advanced coordinated clearing until a real smoke and human test demonstrate it.

Existing limitations must be tested rather than concealed:

- `Assign.keep` preserves an in-radius `capture`/`hold` order without checking new wants; lowering `want` alone
  will not release the current hill occupants to rotate (`P/modules/bots_commander/shared.lua:130–143`).
- Orders with the same id/action can persist for the configured hold period; use visit-specific ids and withdraw
  obsolete objectives so a full rotation does not accidentally revive an old assignment.
- `defend` share caps at a third of managed bots, counting dead bots in team size, and may be zero for tiny teams.
  This Dom-oriented cap is not automatically suitable for hill defense/anchoring.
- Sanitization keeps id/position/radius/action/weight/want only; phase, eligibility and deadlines would be lost.
  Mode policy cannot assume commander reads extra properties. Contract extensions need explicit ownership.
- Brain combat currently outranks objective (`docs/api/bots-blackboard.md`, “Kinds”); unbroken combat/search may
  prevent any scoring or timely rotation. Urgent objective selection needs tests without removing self-preservation.
- `objective.lua` picks random interior/guard points without room-aware geometry; nav projection can place a bot
  outside a narrow scoring zone or behind a wall. Arrival must be checked against the authoritative volume.

Only active/next public zone facts and legal `board.contacts`/memory may guide tactical decisions.
Occupancy status may tell a bot that a point is contested or enemy-controlled if humans see that same signal;
it must not reveal individual hidden opponents, their count, their route or exact coordinates.
Equipment throws at remembered contacts stay within normal input rules; do not inject live enemy positions through objectives.
Prefer adding typed mode allocation policy and shared geometric arrival checks through the orchestrator,
not mode-written `board.order`, privileged teleports or global changes to Dom defender settings.

## 6. UI and scoped replication

Reuse team score bars with an explicit own `HudScoreKey`; keep scorelimit and match-time settings visible in Game Setup.
Provide current zone id/name, control/contested/empty state, point timer and match timer with distinct labels,
next-zone pre-announcement/rotation position and controller-readable guidance. No fake capture-progress bar is needed.
A progress ring/bar may represent point lifetime only if labeled as time, not ownership capture.
Keep markers/fonts/materials cached and pure HUD view-model logic shared for server-side tests.
Use original built-in presentation; no new required fonts, models, web UI or Workshop dependency.

Replicate a full public snapshot on join/reload plus state-change deltas:
match generation, active visit/id, public layout/next id when allowed, deadlines, control enum and team scores.
Clients render from authoritative deadlines, never increment score locally. Reject stale visit packets.
Do not transmit a membership list, raw presence counts or enemy positions to implement a control badge.
A globally visible static point entity can be acceptable; global dynamic enemy-tracking NW2 fields cannot.
Explicit bounded codecs and `PW.Net.Receive` validation apply to any new requests; no `net.WriteTable`.
Core JIP on should spawn normally under existing team/bot replacement rules; off remains next-match spectator.
The new client must reconstruct the current visit, not restart pointtime or rotation when receiving its snapshot.

## 7. Equipment, rewards and lifecycle

Hold score must be a separate mode counter, as Dom uses `_Scores`; kills may keep ordinary personal score/XP.
The existing score event pipeline also feeds scorestreaks and progression (`docs/api/modes.md`, “Score module”);
reusing it for every hold tick would change rewards and streak rate, not merely update team standings.
Recommend no new personal hold rewards until user rules define anti-farming/eligibility and event values.
Any objective event should omit `ctx.weapon`; objective time must not level the gun in hand by accident.
`TASKS.md` Phase 11 already records airstrike weapon-XP attribution as an open issue; do not duplicate that bug.

Perks/equipment refill and streak persistence retain their current contracts initially;
point rotation is not a new life and must not refill grenades, heal players, clear earned inventory or reset progression.
Smoke/flash, damage resistance, grenade denial, UAV/counter-UAV and airstrike must be tested at the zone:
existing reveal/perception rules still apply and static objective knowledge does not bypass camouflage/reveal rules.
There is no approved rule that camping loses score or that defenders must move; judge occupancy, not play style.
At match end/abort remove mode objective visuals/timers/state, cancel pending score work and leave no stale bot orders.
`PW_MatchEnd` already clears throwable entities and streak instances
(`P/modules/throwables/init.lua:112–122`, `P/modules/streaks/init.lua:247–251`); rotation must not call it.
Mode cleanup should be idempotent and tolerate absent optional modules, without claiming ownership of their private state.

## 8. Cost, test-first slices and checkpoint

Expected cost is low for one active volume: one bounded-rate pass over cached eligible players, then simple arithmetic.
Do not scan all entities/zone combinations every frame. Filter squared horizontal distance and height before optional traces;
cache authored geometry, reuse presence buffers and only re-evaluate inactive zones for authoring, not scoring.
Net volume should be small state deltas and occasional snapshots; client HUD allocates no per-frame tables.
Bot routes, cover searches, spawn traces and weapon grants are likely more expensive than zone arithmetic;
this is a qualitative expectation, not measured performance. Profile target-hardware counters and P2P traffic later.

1. **User/orchestrator gate:** approve scope, rule bundle, map model, timing precedence, spawn and bot policy seams.
2. **Pure rules, tests first:** empty/own/enemy/unequal contest, dead/observer filtering, vertical/radius boundaries,
   wraparound, pre-announcement, exact rotation/score/time boundaries, skipped intervals, score/time ties and one finish.
3. **Map/schema slice:** test malformed/non-finite dimensions, duplicate/missing ids, Base fallback, remote-map validation,
   Custom/vote/playlist filtering and authoring round-trip; add one checked original layout, no automatic fallback.
4. **Server/HUD slice together:** own counters/prefix/deadlines, existing respawn delay, initialization before spawn,
   latejoin snapshot and stale visit rejection, rate/length/state checks, no hidden-member data, idempotent abort/reload.
5. **Bots:** pure assignment cases for tiny/full teams, early rotation, sticky hold release, dead role replacement,
   unreachability and legal knowledge; shared-bot smoke reaches/holds one point, then moves on rotation with generous timeout.
6. **Regression:** retain `mode_dom.lua`, `hud_dom.lua`, `bots_commander.lua`, `bots_behaviors_objective.lua`,
   `match_rules.lua`, `respawn_regression.lua` and streak/progression tests; no weakening existing mandatory cases.
7. **Human checkpoint, stop all lanes:** listen host plus P2P friend, controller/readability screenshots,
   join on/off, latency/reload, vertical geometry, contest while outnumbered, travel/spawn-flip fairness,
   bots choosing score versus combat, explosives/streak pressure and target-hardware profile before balancing numbers.

## 9. Prioritized decisions and sources

**P0:** authorize Hardpoint and sequencing relative to S&D; two-team immediate occupancy rules;
rotation ordering/next-point disclosure; score/time/tie and hitch-boundary semantics; authored geometry and minimum layout.
**P1:** pointtime, scoring cadence/amount, scorelimit/timelimit, respawn/spawn fairness, rotate/anchor allocation,
spawn-protected occupancy and optional personal rewards/streak interactions. No values or unlocks are finalized here.
**P2:** overtime, shuffled routes, FFA and special spawn anchors; none is necessary for the recommended first version.

Method: inspected decided design, frozen API docs, actual mode/respawn/map/spawn/HUD/commander source and existing tests.
`notes/23-infection-mode-research.md` helped locate shared seams; mode-specific claims above were independently checked.
External engine reference accessed 2026-11-07; no commercial rules or third-party implementation were imported:

- [E1: Facepunch, CurTime](https://wiki.facepunch.com/gmod/Global.CurTime): synchronized gameplay clock;
  time scaling and pause affect it. This does not establish ordering between engine callbacks.

No GLuaTest/game/deploy run was performed for this docs-only study; those remain future implementation gates.
