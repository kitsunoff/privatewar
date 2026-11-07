# Gameplay: next implementation briefs

Baseline: `6e4d49a`, inspected source, tests and API contracts, not task-status labels.
This condenses existing notes [21](../notes/21-killstreak-candidates.md),
[22](../notes/22-perk-candidates.md), [23](../notes/23-infection-mode-research.md),
[24](../notes/24-search-and-destroy-research.md) and [25](../notes/25-hardpoint-research.md).
No new research, gameplay implementation, measurements or approval is implied.

## Execution contract

Paths below use exact repository prefixes: **P** = `addons/privatewar/lua/privatewar/`,
**T** = `addons/privatewar/lua/tests/privatewar/`,
**C** = `addons/privatewar/gamemodes/privatewar/gamemode/core/`,
**A** = `addons/privatewar-arc9/lua/privatewar/`. Paths marked **new** are proposed files;
other owned paths exist. Ownership is for future individual tasks, not concurrent permission.
Shared files must be serialized; `docs/api/` amendments belong to an orchestrator-assigned contract task.
Any new public surface also needs its explicitly assigned type file and frozen API contract before implementation.

Write the named GLuaTest cases first; names below are proposed, not claimed to exist or pass.
Keep every mandatory case in `TASKS.md`; the regression sets below supplement, never replace them.
Use pure shared reducers and thin engine glue, validated bounded messages, legal bot knowledge and inputs.
Do not change `design/`, weaken tests, bypass gates or implement an unresolved choice.
At each human checkpoint stop all lanes for the user's report; no automated run substitutes for it.
Future implementation requires `nix develop --command make check` and `make test` with `pipefail`,
one Deck owner, and a separate reviewed feature branch. This document itself needs no Deck run.
Future UI work must be scheduled around the separately owned health/ammo HUD task; no redesign is included here.

## 1. First perks: three independent content slices

**Fixed:** `design/05-loadout.md` d.4/d.8/d.11; `design/04-weapons.md` d.6;
`design/00-core.md` d.11; contracts `docs/api/perks.md`, `equipment.md`, `adapter.md`, `loadout.md`.
`P/modules/perks/init.lua` composes perk/source/mode products and forwards weapon keys.
`P/modules/equipment/init.lua` asks `PW_EquipmentCount` once per life after equip;
that question uses first-answer-wins, not an additive chain. Arbitrary `PW.Stat` names have no automatic consumer.

### P1 — Extra equipment allowance

- **Depends/owns:** approved slot, amount, group/cost/unlock and conflict policy;
  **new** `P/perks/equipment_allowance.lua`, **new** `T/perks_equipment_allowance.lua` only.
  Use an owner-filtered instance hook; preserve SWEP ammo as authoritative count.
- **Tests:** `Allowance: only the owner and approved slots receive the extra count`;
  `Allowance: repeated loadout give cannot refill the same life`;
  `Allowance: death clears the hook and the next life recomputes the count`;
  `Allowance: conflicting count providers follow the approved policy`.
- **Unapproved:** recommend mutual exclusion with other count providers for this slice;
  deterministic composition instead requires a separate equipment API task, not hook-order reliance.
- **Human barrier:** human and bot allowance, both grenade types, switching/cooking/death drop and last-use return.

### P2 — Draw speed; P3 — ADS speed (separate commits)

- **Depends/owns:** approved magnitudes/group/cost/unlock;
  **new** `P/perks/fast_draw.lua`, **new** `T/perks_fast_draw.lua` for P2;
  **new** `P/perks/fast_ads.lua`, **new** `T/perks_fast_ads.lua` for P3.
  Use only `Stats.draw_time` / `Stats.ads_time`; never call `SetStatMods` with a partial table.
  ARC9 already maps these to `DeployTime` / `AimDownSightsTime` in `A/modules/arc9/shared.lua`;
  no adapter change belongs to these content tasks.
- **Tests:** P2 `Draw: perk wildcard and mode multiply without replacing reload mods`;
  P3 `ADS: perk wildcard and mode multiply without replacing draw mods`;
  each file also has `Lifecycle: removal restores identity without repeated scaling`.
- **Support/choice:** ARC9 advertises both keys through `SupportedStatMods`; fallback SWEPs support neither;
  TFA/MW integrations are absent, not verified compatible. Recommend an unsupported-base warning, not class rejection.
  If existing UI cannot express it, first assign **new** `T/perks_support_ui.lua` and
  `P/modules/loadout_ui/sh_editor.lua` to a serialized UI task after contract review.
  Its case is `Support: draw and ADS descriptions identify unsupported selected weapon adapters`.
- **Human barrier:** ARC9 host/P2P prediction and actual draw/ADS timing, bot ordinary fire gates,
  fallback warning and grenade return. Draw support does not prove faster holstering.

**Preserve for P1–P3:** T-4.3, T-4.4, T-4.5, T-3.5, T-11.4 in `T/wildcards.lua`, `perks.lua`,
`equipment.lua`, `weapons_statmods.lua`, `grenades_inventory.lua`; especially
`PW.Stat: multiplies the perk, wildcard and mode multipliers`,
`PW.Stat: recomputed on spawn and loadout change only, cached otherwise`,
`Refresh: called once per revision per weapon, install once per weapon`,
and every existing cooking/fuse/attacker/ammo assertion.

## 2. Support streaks before lethal expansion

**Fixed:** `design/05-loadout.md` d.9/d.10; `design/00-core.md` d.11;
`design/07-bots.md` d.2/d.7/d.14; contracts `docs/api/streaks.md`, `adapter.md`, `bots-blackboard.md`.
Costs, durations, caps, reward events and every numeric strength below require approval.
No aircraft/drone/controller framework; lethal deployables wait for provenance and perceived bot counterplay.

| Small task | Dependencies and exact owned paths | Proposed GLuaTest cases |
| --- | --- | --- |
| K1 directional snapshot | Approve cone/range/LOS and empty-scan feedback. **New** `P/streaks/directional_scan.lua`, **new** `T/streak_directional_scan.lua`. Reuse `PW.Reveal` for packets and bot stimuli. | `Scan: cone range and LOS filter targets before disclosure`; `Scan: Counter-UAV filters human packets and bot stimuli`; `Scan: bot direction uses contacts or a public lane not hidden enemies` |
| K2a transactional deployment | Approve refusal/refund, ownership/team-change/disconnect policy. `P/modules/streaks/init.lua`, `P/types/streaks.lua`, **new** `P/modules/streaks/sh_deployment.lua`, `P/modules/streaks/shared.lua`, **new** `T/streak_deployment.lua`. Orchestrator freezes `docs/api/streaks.md` first. | `Deployment: invalid floor hull or blocked exit spends no inventory`; `Deployment: accepted placement spends exactly once`; `Deployment: expiry destruction disconnect disable and match end remove owned entities and timers` |
| K2b ammunition cache | K2a plus approved reserve cap, shared-ammo deduplication, receipt/LOS/charges. **New** `P/streaks/ammo_cache.lua`, **new** `P/modules/weapons_ammo/sh_resupply.lua`, `P/modules/weapons_ammo/shared.lua`, `P/types/weapons_ammo.lua`, **new** `T/streak_ammo_cache.lua`. Freeze capped resupply in `docs/api/adapter.md` first. | `Cache: shared ammo is replenished once and clamped to cap`; `Cache: clips and grenade ammo never refill`; `Cache: only eligible nearby allies receive supply` |
| K3 medical station | K2a plus approved out-of-combat delay, heal rate, overlap arbitration and score policy. **New** `P/streaks/medical_station.lua`, **new** `T/streak_medical_station.lua`. Put its pure reducer in the shared content file; no generic heal framework yet. | `Medical: damage range and LOS interrupt eligibility`; `Medical: overlapping stations do not multiply approved healing`; `Medical: health never exceeds maximum` |
| K4 ground sensor | K2a plus approved floor/LOS coverage, health and public device-perception contract. **New** `P/streaks/ground_sensor.lua`, **new** `T/streak_ground_sensor.lua`. Device-counterplay ownership is a prerequisite contract task, not permission to write bot private state. | `Sensor: walls floors and Counter-UAV obey approved filtering`; `Sensor: destruction and expiry stop all pulses`; `Sensor: hidden device creates no bot contact before perception` |

K2b uses capped ordinary reserves, not spawn-time `PW.WeaponAmmo.Give`. Start with approved passive nearby receipt;
deliberate bot visits require a separately frozen support-goal contract, not teleportation.
Each K1–K4 checkpoint: host/P2P plus bots, team/FFA, indoor/multilevel placement, controller feedback,
late join and abort cleanup; profile simultaneous instances before increasing caps.
K4 additionally requires a real bot attacking a perceived device before claiming intelligent counterplay.

**Provenance prerequisite, before any new lethal item:** owned `P/modules/match_rules/init.lua`,
`P/modules/streaks/init.lua`, `P/types/streaks.lua`, **new** `T/streak_damage_provenance.lua`;
orchestrator owns `docs/api/modes.md` / `streaks.md` contract agreement.
`weaponOf` currently falls back to the active gun for a non-weapon inflictor; `StreakDamage` marks only its
synchronous callback. Proposed cases: `Provenance: delayed impact credits owner player XP but no held weapon XP`;
`Provenance: switching death disconnect and world fallback preserve approved attribution`;
`Provenance: each delayed impact respects chain off and chain on`.
Choose explicit per-impact source metadata and owner-invalid semantics before coding; do not erase legitimate grenade XP.
Human barrier: delayed kill while switching/dead and readable device damage/counterplay.

**Preserve:** all T-4.6 cases in `T/streaks.lua` (kills/score, reset, kept unused inventory, persist, chain,
instance duration), T-6.6 radar/CUAV, T-2.1 awards, T-4.9 weapon-context XP and T-5.7 legal stimuli.
In particular preserve `Mandatory: streak kills do not chain unless streaks.chain is on` and
`PW.Reveal: sends only the given targets to the viewer's players and feeds its bots`.

## 3. Hardpoint: authored occupancy, not renamed Domination

**Decision gate:** additional mode authorization and priority relative to already-decided S&D-first
(`design/02-modes.md` d.5). Recommended bundle, still unapproved: two teams, one authored rotating zone,
fixed public order, only exclusive living occupancy scores; empty or any opposing occupancy scores nothing,
even 3 versus 1. Approve timing/cadence, boundary/hitch ordering, score/time/ties, protected occupancy,
next-zone disclosure, maps, personal rewards (recommend none initially) and bot rotate/anchor allocation.
Retain `design/02-modes.md` d.6, `design/03-mapdata.md` d.4/d.6/d.7 and `design/07-bots.md` d.14.

- **H1 rules/map slice:** owns **new** `P/modes/hardpoint.lua`, `P/maps/gm_construct.lua`,
  **new** `T/mode_hardpoint.lua`. Dependencies: approved geometry/schema in `docs/api/map.md` / `modes.md`.
  Validate ordered unique zone ids, finite dimensions/height and current-world reachability;
  unsupported map pairs stay hidden, never convert Dom flags automatically.
  Cases: `Hardpoint: empty and unequal contested occupancy score zero`;
  `Hardpoint: dead observers and other floors never count`;
  `Hardpoint: rotation wraps and exact boundary scoring follows approved precedence`;
  `Hardpoint: stalls cannot backfill unsampled occupancy or finish twice`;
  `Hardpoint: invalid authored layouts are hidden in Custom vote and playlists`.
- **H2 bot/UI slice:** after H1 and approved allocation/snapshot seams, owns
  `P/modules/bots_commander/shared.lua`, `P/modules/bots_commander/init.lua`,
  `P/bot_behaviors/objective.lua`, `P/types/bots_commander.lua`, `P/types/bots_objectives.lua`, **new** `P/modules/hardpoint/shared.lua`,
  **new** `P/modules/hardpoint/init.lua`, **new** `P/modules/hardpoint/cl_init.lua`,
  **new** `P/hud/hardpoint.lua`, **new** `T/hardpoint_presentation_bots.lua`.
  Cases: `Hardpoint: rotation releases sticky holds including tiny teams`;
  `Hardpoint: projected arrival is inside the authoritative zone`;
  `Hardpoint: late snapshot rejects stale visits and transmits no occupants`;
  `Hardpoint: bot holds then rotates through normal inputs` (smoke).
  Commander currently strips extra fields and retains active holds; merely lowering `want` does not fix this.
- **Preserve/barrier:** T-2.4 in `T/mode_dom.lua`, especially
  `Scoring per held point: each owned flag adds the tick points to its team` (Dom intentionally scores empty owned flags),
  plus T-2.9 spawns, T-5.10/11 objective/commander and T-8.4 JIP.
  Human barrier after H2: outnumbered contest, vertical volumes, spawn travel fairness, one-bot rotation,
  two distinct clocks/markers, P2P join/abort and target-hardware profile. Never modify Dom to fit Hardpoint.

## 4. Search and Destroy: lifecycle before bomb content

**Fixed:** first post-MVP mode, `round_base`, balanced teams, mode-owned rounds;
`design/02-modes.md` d.5/d.6/d.7, `design/00-core.md` d.3/d.4,
`design/03-mapdata.md` d.4/d.6, `design/07-bots.md` d.2/d.14;
contracts `docs/api/modes.md`, `map.md`, `teams.md`, `loadout.md`, `bots-blackboard.md`.
**Unapproved bundle:** authored sites, two teams, one bomb, one life, continuous held-use/no partial progress.
Approve site count, carrier selection/drop visibility/recovery, durations/cancellation, swaps/wins,
spectator/JIP/reconnect rules, round inventory cleanup and exact death/plant/defuse/fuse precedence.
Recommend planted fuse replaces round expiry (including after attackers die), non-damaging result initially.

- **S1 lifecycle seam:** owns `P/modes/round_base.lua`, `P/types/rounds.lua`,
  **new** `T/round_objective_lifecycle.lua`; orchestrator first freezes `docs/api/modes.md`.
  Actual `_Step` forces draw when timed out and verdict nil; `_Run` swaps then respawns then notifies.
  Initial core order is phase notification → `MODE:Start` → `PW_MatchStart`/spawn, not its reverse.
  Add an approved child-aware timeout and preparation-before-respawn seam without changing default behavior.
  Cases: `Round objective: planted overtime survives the base deadline`;
  `Round objective: prepare follows swap and precedes every playable respawn`;
  `Round objective: terminal verdict prevents another swap spawn or award`.
- **S2 bomb/roster slice:** after S1, owns **new** `P/modes/snd.lua`, `P/maps/gm_construct.lua`,
  **new** `P/modules/snd/shared.lua`, **new** `P/modules/snd/init.lua`,
  **new** `P/modules/snd/cl_init.lua`, **new** `P/hud/snd.lua`, **new** `T/mode_snd.lua`.
  Cases: `SND: one bomb survives competing pickups and carrier death disconnect`;
  `SND: held interactions cancel on invalid actor range release and round generation`;
  `SND: exact plant defuse fuse and death boundaries resolve once`;
  `SND: reconnect and replacement cannot grant a second life`;
  `SND: snapshots disclose only approved carrier drop and spectator information`.
  Round-active gates for score/damage/streaks/projectiles and roster-aware spawning require separately assigned
  `P/modules/match_rules/init.lua`, `P/modules/lobby/init.lua`, `P/modules/streaks/init.lua`,
  `P/modules/throwables/init.lua`, `P/modules/spawns/init.lua` after contract review; S2 cannot silently patch them.
- **S3 bot interaction slice:** after S2 and typed eligibility/action agreement, owns
  `P/modules/bots_commander/init.lua`, `P/modules/bots_commander/shared.lua`,
  `P/bot_behaviors/objective.lua`, `P/types/bots_commander.lua`, `P/types/bots_objectives.lua`, **new** `T/bots_snd.lua`.
  Cases: `SND bots: sole attacker carries plants and guards through shared input rules`;
  `SND bots: sole defender holds use to defuse and death promptly reassigns`;
  `SND bots: sanitizer preserves approved eligibility without leaking hidden enemies`.
  `plant`/`defuse` are anticipated by design, not implemented by today's walk-to-position behavior.
- **Preserve/barrier:** T-2.3, T-1.12, T-2.9, T-5.2/7/11, T-8.4 and grenade/streak lifecycle cases.
  Keep `T/round_base.lua` case `Round time: when it is up an undecided round is a draw; 0 means no round time`
  for ordinary children. Human barrier after S3: host/P2P/controller holds, planted overtime, side swaps,
  both join policies, restricted spectator view, invalid drop recovery and no intermission combat leakage.

## 5. Infection: explicit roles, not a Workshop port

The Workshop reference was **not downloaded or source-audited**; no implementation/asset reuse is authorized.
Approve additional scope and an explicit asymmetric exception to balanced teams (`design/02-modes.md` d.6).
Recommend one round, random eligible seed (human or bot), survivor death converts once, renewable infected lives,
survivors win at deadline; world/suicide converts without credit; initial stock melee infected and ordinary survivor classes.
Seed count, health/speed, timer/death precedence, last-infected departure, JIP/replacement and rewards remain unapproved.
Fixed seams: `design/00-core.md` d.3/d.4, `design/05-loadout.md` d.1/d.8/d.9/d.11,
`design/07-bots.md` d.2/d.3/d.7/d.16; APIs `modes.md`, `teams.md`, `loadout.md`, `bots-blackboard.md`.

- **I1 role/life/result slice:** after approved public team/role-transition, allowance/revocation and outcome contracts,
  owns **new** `P/modes/infection.lua`, **new** `T/mode_infection.lua`.
  Cases: `Infection: seeded roles exist before first loadout resolution`;
  `Infection: each survivor life converts once including world death without credit`;
  `Infection: pending infected respawns do not cause survivor victory`;
  `Infection: deadline last survivor and disconnect follow approved precedence`;
  `Infection: converted players retain their personal outcome not merely winning current team`.
- **I2 atomic transition/bot slice:** after I1 and orchestrator-frozen contracts, owns
  `P/modules/teams/init.lua`, `P/modules/bots_manager/init.lua`, `P/modules/bots_brain/init.lua`,
  `P/modules/bots_perception/init.lua`, `P/modules/bots_commander/init.lua`,
  `P/types/bots_brain.lua`, `P/types/bots_commander.lua`, `P/types/bots_perception.lua`,
  **new** `P/bot_behaviors/infected_pursuit.lua`, **new** `T/infection_role_transition.lua`.
  Coordinate each store's owner: invalidate contacts/targets/action stack/orders/hunt/goals/intents on conversion,
  not periodic team refresh or mode-written private state. Enforce the approved infected loadout and already-earned
  streak/equipment policy through separately assigned public revocation seams; clearing class slots is insufficient.
  Cases: `Infection: conversion atomically invalidates stale allied targets orders and inputs`;
  `Infection: infected loadout cannot inherit firearms grenades or forbidden streak effects`;
  `Infection: kill callbacks use death-time allegiance before conversion`;
  `Infection: bot pursues only legal contacts and attacks through normal melee inputs` (smoke).
- **Presentation prerequisite/barrier:** separately assign **new** `P/modules/infection/shared.lua`,
  **new** `P/modules/infection/init.lua`, **new** `P/modules/infection/cl_init.lua`,
  **new** `P/hud/infection.lua`, **new** `T/infection_presentation.lua` after outcome/snapshot approval;
  case `Infection: late snapshot shows role counts deadline and personal result without hidden positions`.
  Preserve T-1.16 normal balance, T-4.1 mode loadout replacement, T-4.6 retained rewards outside role restrictions,
  T-5.1/2/7/9 and T-8.4. Human barrier: both actor types in both roles, P2P join/reconnect/disconnect,
  cramped melee endgame, safe spawns/protection, optional ARC9 absent, abort and personal result clarity.

## 6. T-11.10: reopen only demonstrated gaps

`TASKS.md` marks it done, but its mandatory (b)/(d)/(e) are not all implemented at this baseline.
The postmatch duration reducer and shared START formatter exist; do not rewrite them or claim that
the historical regression was observed failing in this review. Existing source is evidence, not a fresh runtime pass.

| Requirement | Actual contradiction / test gap | Narrow recommendation; approval boundary |
| --- | --- | --- |
| Minimum delay | `C/sv_mapchange.lua:21–22,220–224`: range 0..60; nonpositive delay calls `_Begin` immediately, without announcement. `T/match_flow_ui.lua:233–265` explicitly expects this. `docs/api/core.md` “Delayed change” also documents immediate zero. | Positive minimum is already required by mandatory (d); choose its exact value (recommend 1 s), then reconcile contract and contradictory assertions. Preserve cancellation/guard/persistence tests, not the obsolete zero-delay expectation. |
| Popup expiry | `P/modules/lobby_ui/sh_flow.lua:72–79`: only a negative/missing timestamp hides it; after end it remains at 0. `runScheduled` leaves announcement set on successful `_Begin`; failure clears it later. Existing popup test never checks expiry. `docs/api/ui.md` says nil without announcement, omitting deadline expiry. | Require `now < changeAt` for popup visibility, including equality/late frames; do not change the separately clamped START countdown. Expiry is already mandatory, not a new gameplay choice. |
| Common lobby entry | `P/modules/lobby/shared.lua:39–41` excludes first entry; `init.lua:57–63,120–127` uses explicit unspawn only on returns. `T/match_flow_ui.lua:268–309` expects first entry false and proves calls to SetTeam/Spawn, not identical body state on both paths. Initial entry relies on base gamemode behavior. | Unify explicit lobby-entry handling for initial and returning humans/bots without recursive spawning; test both entry paths and body/weapons/observer outcome. This implements mandatory (b), not a changed lobby policy. |
| Measured width plus padding | `P/modules/hud/sh_popups.lua:138–152` uses measured max text width × max scale, but no box padding. `LevelUpMargin` is distance to screen edge, not text padding. `P/hud/popups.lua:123–146` measures text and disables clipping; `T/hud_xpbar.lua:249–285` tests synthetic width/scale containment, not positive padding or real font bounds/shadow. | Preserve measurement/matrix fix; add scaled padding and shadow allowance, test all animation scales/resolutions, then inspect real font rendering. Exact padding is an implementation detail unless it changes approved appearance. No wider HUD redesign. |

**Future repair ownership (not this document's changes):** `C/sv_mapchange.lua`,
`P/modules/lobby_ui/sh_flow.lua`, `P/modules/lobby/shared.lua`, `P/modules/lobby/init.lua`,
`P/modules/hud/sh_popups.lua`, `P/hud/popups.lua`, `P/types/hud_popups.lua`,
`T/match_flow_ui.lua`, `T/hud_xpbar.lua`; contract reconciliation through the orchestrator only.
Dependencies: `design/00-core.md` d.5/d.9/d.10, `design/10-frontend.md` d.1/d.13,
T-7.7/U-5 and existing T-11.10 contract review. Serialize popup files with the upcoming HUD agent.
Proposed cases: `Map change: zero and negative delays announce the same clamped positive deadline`;
`Map popup: visible before deadline and absent at or after deadline`;
`Lobby entry: initial and postmatch humans and bots use the same body cleanup path`;
`LEVEL UP: measured text plus padding and shadow fit every animation scale at 720p 800p and 1080p`.
Preserve T-1.12/T-1.14, T-6.4/T-11.3 queue order/expiry, T-7.7 and every noncontradictory T-11.10 assertion.
Human barrier: timed results → lobby/vote, initial/returning bodies and operator panel,
delayed map announcement with P2P guest, LEVEL UP at the three resolutions and maximum pop scale.

## Smallest approval queue

1. Perks: select slots/count conflict policy, draw/ADS strengths/groups/costs/unlocks and unsupported-base warning.
2. Support streaks: authorize K1–K4 order, prices/timings, placement/lifecycle and supply/heal/sensor rules;
   agree damage provenance before any lethal expansion. No aircraft.
3. Modes: retain S&D-first or explicitly reprioritize; approve each compact rule bundle above before its code.
   Hardpoint needs authored layouts/timing/rewards/bot allocation; S&D needs overtime/lives/interactions/spectators;
   Infection needs asymmetric roles/conversion/allowances/JIP/personal outcomes.
4. T-11.10: choose the positive minimum delay and reconcile the contradictory API/test descriptions.
   Popup expiry, common lobby entry and measured-width padding are approved requirements, not new design questions.
