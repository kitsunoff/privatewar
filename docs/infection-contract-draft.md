# Infection addon: Phase 1 contract draft

Status: historical Phase 1 proposal; generic surfaces are now **FROZEN, NOT IMPLEMENTED**.
Canonical corrections: [teams API](api/teams.md), [player overrides API](api/player-overrides.md),
[operators API](api/operators.md). Declarations and functional tests precede production.
No observed game RED, GREEN, manual HUD approval or gameplay completion is claimed.

## Approved boundary and scaffold

Infection is a separate optional addon, `addons/privatewar-infection/`, discovered by the existing
loader and offered through the existing lobby. It is not a new engine gamemode. No core branch on
an Infection id, built-in path shadowing, framework dependency, external asset or copied code is allowed
(`01-extensibility.md` d.4/d.5/d.8/d.14/d.16; `07-bots.md` d.2/d.3/d.7/d.16).
The Workshop reference in note 23 was not downloaded or source-audited; no additional research is needed.

Approved in the implementation brief: three rounds by default, configurable including one; reseed each
round, preferably avoiding repetition when possible; either actor type can be seeded; survivor death
changes the participant to infected until the next round; reset roles/loadouts/bot state each round;
all converted means infected victory; survivors at the deadline means survivor victory; round results
and a final summary. These supersede the older single-round recommendation, not unrelated design rules.

User-confirmed correction/preset: 120 s round, one random initial infected, 3 s infected respawn;
joiners wait for the next round; every survivor death converts, including world/suicide without
infection credit; no new XP or money awards. Infected have **400 maximum/spawn HP**, built-in
`weapon_fists`, a stock HL2 zombie **player** model, and **1.15 times ordinary walk AND run speed**.
Jump and fist damage are unchanged. Apply identically to humans and bots, not as AI bonuses.
No crowbar or ordinary-health infected preset is proposed. Final personal scoring and exact
deadline/disconnect/reconnect edge policies still need agreement.

The scaffold has an addon manifest and a type-only Lua file. It registers nothing, changes no gameplay
and is not a playable addon release. Proposed unique ids: mode `pw_infection`, module
`pw_infection_rules`, HUD `pw_infection_status`, behavior `pw_infection_pursuit`.
`mode_infection.lua` contains only optional-boundary tests; gameplay assertions must precede implementation
after the freeze. Presence is determined from the mounted mode source, not a successful registry lookup.
The mode is deliberately a single-file entity so the presence test has one authoritative path.
An installed source with missing registration or broken inheritance fails, never skips.

## Minimum teams surface requested for freeze

Keep balanced initial assignment exactly as it is, before `MODE:Start`; the mode then makes validated
transitions in initial preparation. Existing ordinary modes retain balance and smallest-team placement.
No generic role registry is needed: roles are mode-owned, relationships still use `PW.IsEnemy`.

Proposed server-only signatures, to be declared in `types/teams.lua` only after approval:

```lua
---@alias PW.TeamTransitionReason "round_prepare"|"role_change"|"late_join"|"replacement"
---@alias PW.TeamPolicy "balanced"|"managed"
---@alias PW.TeamTransitionNotification fun(ply: Player, from: integer, to: integer, reason: PW.TeamTransitionReason)
---@alias PW.CanRunBotBehaviorQuestion fun(bot: Player, behaviorId: string): boolean?

---@class PW.TeamsLib
---@field Transition fun(ply: Player, team: integer, reason: PW.TeamTransitionReason): boolean, string?

---@class PW.Mode
---@field TeamPolicy? PW.TeamPolicy -- nil means balanced; initial assignment remains balanced
---@field PW_CanChangeTeam? fun(self: PW.Mode, ply: Player, from: integer, to: integer, reason: PW.TeamTransitionReason): boolean?
---@field PW_SelectLateTeam? fun(self: PW.Mode, ply: Player): integer|false|nil
```

`Transition` requires an enabled teams module, active valid mode, `LIVE`, valid admitted non-spectating player,
finite integer destination in `1..N`, valid reason, and an explicit `true` from the question
`PW_CanChangeTeam(ply, from, to, reason)`. First non-nil answer wins: an earlier false blocks, a later
false cannot override an earlier true. `nil` does not authorize. Dead participants and initial pre-spawn
observer bodies remain eligible. Invalid input or reentrant transition returns `false, reason` before mutation
or notifications. An authorized same-team request succeeds without events. It does not spawn, heal,
give a loadout, score, or change a saved class. No client team-changing message is introduced.
No public team transition is a security boundary against arbitrary server Lua.

Successful changed-team order, synchronously before return:

1. Notification `PW_PlayerTeamChanging(ply, from, to, reason)`: brain stops affected action stacks,
   including `OnEnd` callbacks, while the old relationship still exists. Never convert inside a
   death listener before death-time score/perk callbacks have completed.
2. Teams module alone calls `SetTeam(to)`.
3. Notification `PW_PlayerTeamChanged(ply, from, to, reason)`: each owner clears its own stale state;
   the manager mirrors the new engine team immediately, not at the next periodic reconciliation.

Both notifications use `PW.Notify`; listeners return nothing, never yield, start replacement actions,
or initiate another transition. The two phases avoid `OnEnd` restoring a goal after another owner's
reset. Post-change reset handlers may clear only, without order dependence. This is synchronous
invalidation, not transactional rollback of third-party listener errors; existing hook error semantics
remain unchanged. No addon accesses `PW._Bot*` or writes another module's blackboard fields.
Both notification signatures are `PW.TeamTransitionNotification` above.

The changed player's relationships affect **other bots too**, even when the changed player is human.
Conservative initial implementation: reset relationship-dependent state for every managed bot on a
changed-team event, bounded by player slots, without granting new contacts. Do not just reset the victim.

| Owner | Before-change work | After-change owned invalidation |
| --- | --- | --- |
| `bots_manager` | none | mirror `board.team` from the player immediately |
| `bots_brain` | stop full stacks, top first, through ordinary lifecycle | target, behavior, owned intent channels, cached evaluations and cooldown state |
| `bots_perception` | none | contacts, memory, reaction snapshots, delayed sharing queues and perception debug state |
| `bots_aim` | none | target overrides, spring/fire state and attack/view intent channels |
| `bots_goal` | none | goal/path and pending path handle, follower state and owned movement/button channels; discard old callbacks |
| `bots_input` | none | cached weapon selection, scripted override and pending slide/input state |
| `bots_commander` (SND owner) | none | orders, hunt slots and retained assignment state, including references to the changed player |

Same-team participants still need reset between rounds. Request a common pre-respawn preparation
notification from the SND owner (below), reusing the owners' reset helpers, not a fake team change.
Pending asynchronous callbacks must be cancelled or generation-checked so they cannot restore stale state.
Missing optional bot modules make no callback and must not break the transition.

## Late placement, replacement and behavior eligibility

`TeamPolicy = "managed"` is a mode-local opt-in, not global balance removal. It retains initial balance;
on later placement, `PW_SelectLateTeam(ply)` supplies a validated team or `false` to defer. A missing,
invalid or refused managed placement must not fall back to smallest-team assignment or spawn a player
into play. A balanced mode keeps today's behavior. Spectators stay excluded. The mode's roster must
be ready before loadout resolution regardless of hook iteration order.

This needs a serialized lobby/spawn/bot-manager agreement, not just a teams helper. In particular,
the manager currently kicks from the smallest team on human join. It must not use that heuristic for
managed modes without a frozen replacement policy. The approved JIP policy is to wait for the next round;
freeze its spectator-to-roster admission order plus reconnect/disconnect and bot quota handling.
Request a typed replacement-selection seam only if that frozen quota policy actually needs one;
do not silently rebalance role populations or remove an arbitrary last infected.

Proposed question `PW_CanRunBotBehavior(bot: Player, behaviorId: string) -> boolean?`: `false` rejects,
otherwise unchanged eligibility. The brain applies it to candidates, running frames and ChangeTo /
SuspendFor / resume admission, not merely initial selection; rejected cached evaluations are discarded.
The active mode implements role eligibility through the ordinary default-answer mechanism. No built-in
brain branch mentions Infection. A missing eligibility provider preserves ordinary behavior.
Behavior admission must enforce the approved fists-only infected role without overriding other modules.

## Dependencies to request from other owners

- **SND / common rounds:** freeze a child preparation method before the first match-start loadout and
  after any swap but before every later playable respawn. Add a public preparation notification for
  module-owned reset of unchanged participants. A failed/terminal preparation must prevent the next
  spawn/round-start event. Infection must not read private round state or implement another round loop
  (`00-core.md` d.3/d.4; `02-modes.md` d.7).
- **SND / common rounds:** fixed total round limit, distinct from rounds-to-win; default remains
  unchanged for existing children. Infection needs total 3 by default and 1 supported, no early finish
  from accumulating wins, final result exactly once. Freeze exact field/method and result-summary seam.
  Changing cohorts mean team-index wins alone do not define a personal final outcome.
- **SND / commander:** subscribe to the approved transition/preparation events and clear orders/hunt
  in their own module. Infection does not edit commander or objective behavior.
- **Loadout/equipment/streak owners:** separately approve public role revocation/recompute seams.
  `PW_PlayerLoadout` replaces a class but does not revoke retained streak inventory or active effects;
  delayed equipment grants must recheck the current life/round. No new XP/money is approved; do not
  invent broader perk/streak inventory or active-effect policy beyond the fists-only role restriction.
  Death-time allegiance must be scored before conversion; a proposed post-death notification must
  respect the existing full listener dispatch, not depend on notification listener order.

## Generic player overrides and rollback: additional freeze request

Existing `PW.Stat` multiplies cached numbers but there is no general consumer that applies role
maximum health or walk/run speed. Do not assume registering a stat source changes engine movement.
The operators module already owns `PlayerSetModel`; do not add a competing model hook or mutate
`operators.model`, `cl_playermodel`, saved classes, or private operator/perk stores.

Proposed mode-neutral surface (names not frozen):

```lua
---@class PW.PlayerOverrideProfile
---@field maxHealth? number -- finite positive; Infection supplies 400
---@field spawnHealth? number -- finite positive, <= maxHealth; apply once per new life, not every refresh
---@field walkSpeedMult? number -- finite positive; Infection supplies 1.15
---@field runSpeedMult? number -- finite positive; Infection supplies 1.15

---@alias PW.PlayerOverridesQuestion fun(ply: Player): PW.PlayerOverrideProfile?
---@alias PW.PlayerModelOverrideQuestion fun(ply: Player): string?

---@class PW.PlayerOverridesLib
---@field Refresh fun(ply: Player): boolean, string?
---@field Release fun(ply: Player): boolean

---@class PW.OperatorsLib
---@field Refresh fun(ply: Player): boolean, string?
```

New optional generic module `player_overrides` owns capture/apply/restore of health/max-health and
walk/run speeds. It asks `PW_PlayerOverrides(ply)` through the usual public question path, validates
the entire profile before mutation, and applies relative to an ordinary-life baseline, never the
already-multiplied values. Repeated refresh must not heal or compound speed. No jump, fist damage,
bot-specific scaling, healing timer or private stat access is introduced.

Operators asks `PW_PlayerModelOverride(ply)` before its usual choice, validates a returned player-model
path against `player_manager.AllValidModels()` and `util.IsValidModel`, otherwise logs once and uses
the ordinary operator. `PW.Operators.Refresh` reapplies through that same owner; it never writes the
saved operator choice. A missing override restores the ordinary choice, including the bot's existing
session choice. Invalid NPC-only paths such as `models/zombie/classic.mdl` are not acceptable substitutes.

Before each playable loadout/model/stats application the round/role decision must be committed.
The new module must cooperate with ordinary spawn initialization, not race engine hooks or capture
400/1.15 as the next baseline. Role removal, next round, abort, match end and Infection to TDM/FFA
release all override state and restore baseline max/current health and walk/run speeds; normal
operator/class choices survive. Missing provider on the next game session leaves ordinary behavior.
Do not restore a dead life's snapshot into a new life or resurrect a dead player during cleanup.
**Frozen rollback:** restore living baseline maximum/speeds, clamp current HP down only, never heal;
dead release never revives, new life never restores old-life current HP. Capture ordinary postspawn
baseline per life through SND-owned `PW.MatchRules.Spawn` / `PW_PlayerSpawned`, then apply spawn HP once.

Targeted source verification: `docs/api/core.md` documents `weapon_fists` at weapon-registration time,
and the [official built-in SWEP](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/lua/weapons/weapon_fists.lua)
was read without copying it. The class is `weapon_fists`, not a new `gmod_fists` weapon. Actual installed
registration remains a runtime assertion at `PW_WeaponsLoaded`. Candidate stock player model:
`models/player/zombie_classic.mdl`; mounted registration/asset and animation verification remain
pending. A targeted upstream model-list lookup returned 404, then GitHub tree discovery returned 403;
that route stopped after two failures. No Deck access or new broad reference-addon research occurred.
The safe fallback is the unchanged ordinary operator with a diagnostic, never an external download.

## Exact shared production paths requested, not yet authorized

Prefix **P** = `addons/privatewar/lua/privatewar/`. No file in this section is edited in Phase 1.

- `P/modules/teams/shared.lua`, `P/modules/teams/init.lua`, `P/types/teams.lua`, `docs/api/teams.md`:
  validated transition and managed placement contract.
- `P/modules/bots_manager/init.lua`: immediate team mirror and eventual approved quota placement.
  Request `shared.lua` plus `P/types/bots_manager.lua` only if replacement planning requires them.
- `P/modules/bots_brain/init.lua`, `shared.lua` and `sh_stack.lua` if needed by the actual admission
  path; `P/types/bots_brain.lua`: stop/invalidation and behavior admission (confirm helpers before edits).
- `P/modules/bots_perception/init.lua`, `P/types/bots_perception.lua`;
  `P/modules/bots_aim/init.lua`, `P/types/bots_aim.lua`;
  `P/modules/bots_goal/init.lua`, `P/types/bots_goal.lua`;
  `P/modules/bots_input/init.lua`, `P/types/bots_input.lua`: only owned invalidation handlers/types.
- `docs/api/bots-blackboard.md` stays SND-owned; submit the approved signatures to that owner.
  No separate generic roles module or `roles.md` is proposed.
- Additional requested paths for the approved role preset: new `P/modules/player_overrides/shared.lua`,
  `P/modules/player_overrides/init.lua`, `P/types/player_overrides.lua`, `docs/api/player-overrides.md`;
  existing `P/modules/operators/init.lua`, `P/modules/operators/shared.lua`,
  `P/modules/operators/sh_rules.lua`, `P/types/operators.lua`, `docs/api/operators.md` for the
  validated appearance question and public refresh. No operators UI/settings edits are requested.
  Request new `T/player_overrides.lua` for generic apply/rollback cases; module ownership is not granted yet.
- New tests only: `T/teams_transition.lua`, `T/infection_role_transition.lua`,
  `T/infection_presentation.lua`, existing scaffold `T/mode_infection.lua`, where
  **T** = `addons/privatewar/lua/tests/privatewar/`. Shared test files remain untouched.

## Test-first queue after freeze

These are required future assertions, **not implemented/passing cases**. Do not turn open policy
choices into runnable expected behavior before approval. Keep all existing mandatory tests.

| File | Cases to write before production |
| --- | --- |
| `teams_transition.lua` | authorization/veto; malformed/disabled/FFA/spectator/out-of-phase requests mutate nothing; same-team no-op; reentrancy denied; synchronous changing/set/changed order; ordinary balance unchanged; managed placement never silently balances |
| `infection_role_transition.lua` | conversion once per life; full stale-state invalidation for the converted bot and every other bot targeting a converted human/bot; no delayed sharing/path/input resurrection; death-time allegiance scored first; 400 HP, 1.15 walk/run, unchanged jump/damage, built-in fists and validated zombie player model for both actor types; no inherited forbidden firearms/grenades/streak effects; each optional bot module absent independently |
| `mode_infection.lua` | roles before initial loadout and every round respawn; human or bot seed; nonrepeat when possible; exactly 3 rounds by default and exactly 1 when configured; reset roles/loadouts/bots each round; pending infected respawn never awards survivor victory; all-converted/deadline finish once; approved world-death/disconnect/deadline precedence; round results and approved final summary |
| `infection_presentation.lua` | approved role/count/deadline and personal-summary snapshot only; stale round revisions ignored; no hidden enemy positions; cleanup removes Infection presentation |
| `player_overrides.lua` | ordinary baseline captured once; refresh neither heals nor compounds speed; restore max/current HP and walk/run on release/abort/round/mode change; no old-life resurrection; operator choice/classes unchanged; invalid/missing zombie player asset falls back with diagnostic; missing optional provider preserves ordinary behavior |

Engine smoke after explicit Deck grant: normal `CUserCmd` movement and actual stock melee damage,
both actor types in both roles, optional ARC9 absent, no direct damage/teleport/bonus bot stats.
World-death conversion without credit is approved by the corrected preset above.

Modularity acceptance matrix, all pending runtime evidence:

1. Base without the addon preserves all 1395 baseline cases; new boundary cases do not replace them.
2. Installed addon registers and can start in the standard lobby; source present but registration
   missing is a failure, not a skipped/absent-addon case.
3. Infection to TDM, FFA, abort, and next round restores classes/stats/teams/HUD and leaves no
   stale hooks/timers/bot state. Compare saved user classes, not only equipped weapons.
4. Removing the addon **between game sessions** leaves the base working. No hot-unmount promise.
5. Missing base/API disables the addon with a clear diagnostic. Missing ARC9 remains playable.

## Tooling facts and remaining approvals

Read-only verification: `scripts/package/build.sh` auto-discovers addon directories, copies only
allowed sources and adds GPL licence/notices to each package. Its main-addon source excludes tests;
`scripts/deck/deploy.sh` copies the whole base addon including tests. Neither was deployed here.
New addon directories mount at game startup, not merely `pw_reload`. No restart is authorized here.
An addon manifest without any Lua fails the current packaging self-test, hence the type-only scaffold.
No packaging script/test changes are included or requested without exact follow-up scope approval.
No new third-party material is introduced; the root GPL-3.0-or-later licence applies.

Approved follow-up: fewer than two participants aborts to lobby with explanation (a host plus a bot is
enough); last infected disconnect awards survivors, pending infected respawn does not; exact deadline
wins precedence and terminal results cannot change. Reconnect cannot gain a new life. Personal round
wins belong only to a surviving survivor or an initial seed when infected win; conversions never gain
retroactive wins. Final standings use personal round wins, shared top is a draw; infections are only
informational. Infected have no perks/grenades/streak inventory or active effects. Generic owner paths
are authorized; SND still owns rounds/match_rules/core/commander/objective, HP owns its map.
SND frozen names: PrepareRound, RoundLimit, FinalizeRounds, PW_RoundPreparing/PW_RoundPrepared and
PW.MatchRules.Spawn/PW_PlayerSpawned. Their implementation is an external integration dependency;
never duplicate the loop or access private round state. The pending HUD human checkpoint remains
pending. No push/PR/main merge is authorized. Observed RED and the complete runtime matrix are pending.
