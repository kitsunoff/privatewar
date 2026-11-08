# Infection integration

Optional addon root: `addons/privatewar-infection/`. Design: `02-modes.md` d.8.
The declarations ship with the addon in `lua/privatewar/types/pw_infection.lua`.
An absent addon leaves `PW.Infection`, `PW.InfectionRules`, `PW.InfectionAI` and
`PW.InfectionPresentation` absent. Do not require them from ordinary content.

## Approved playtest revision — first native hit and survivor distance

The 2026-11-08 revision to `02-modes.md` d.8 replaces death-required native-melee conversion with immediate
first-hit conversion. The native-hit smoke observed RED before implementation: the first real fist hit
left the target a survivor. Pure touch and survivor-policy/escape cases also observed RED. The runtime
now implements the revision. The scoped installed-game gate passes 99/0/0, including native first-hit
conversion, the corrected death-credit policy and real survivor retreat with native gunfire while moving.
Fresh-client before/after role views were inspected; a native hit changed the human to 400 HP, fists and
the zombie player model with zero death/spawn, position/velocity delta or control change. The normal full
regression and independent review gates remain required. Agent inspection does not pass a human checkpoint.

The existing generic `match_rules` `EntityTakeDamage` boundary asks
`PW_CanTakeDamage(target, attacker, damage)`. A false answer cancels damage before a lethal hit can kill.
No new generic damage hook or foreign function wrapper is required. The mode veto
establishes the actual owned native `weapon_fists` inflictor, attacker/current life, positive finite
hit damage and an admitted living enemy before changing roles. Merely holding fists is not provenance.
The current [upstream stock fists](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/lua/weapons/weapon_fists.lua)
supply a weapon inflictor and use default `DMG_GENERIC`; requiring `DMG_CLUB` would reject real punches.
The installed-engine smoke must verify that provenance, rather than assuming upstream is runtime evidence.
World/player-inflictor guesses, wrong ownership/weapon, blast/bullet/fall, non-hits, stale
life/roster events, intermission and deadline-equal/later events cannot trigger contact conversion or credit.

An accepted hit cancels damage and applies the live role synchronously through public team, revocation,
loadout, operator and stat owners. Preserve the victim's life generation, alive state, position, velocity
and eye/control state. The role intentionally initializes 400 health once on conversion; this is not an
ordinary stat Refresh, which must remain non-healing. Remove cached survivor perk multipliers before
applying the infected baseline. Repeated callbacks cannot reinitialize health, credit twice or reseal results.
World/suicide death conversion and infected death's 3-second respawn remain separate unchanged policies.

The pure contract `Touch(round, victimId, victimLife, attackerId, attackerLife, now) -> boolean`
accepts an already-proven native hit, validates current living/present opposite roles and life generations,
resolves the deadline first, then converts without setting `deadLife` or changing `life`/`alive`.
Only the initial infected earns the infected-victory personal win; converted players do not inherit one.

`pw_infection_escape` is an addon-owned survivor Action, separate from infected pursuit. It consumes
perceived enemy snapshots through the public brain ctx and uses bounded local walkability probes and
`SetGoal`/`Intent`/`SetTarget`. A walking retreat retains normal aim/fire eligibility; a safe range does
not become an approach. A dry weapon does not justify a forward melee charge. No direct attack bit,
snap view, enemy world-position lookup, private-board mutation or difficulty override is permitted.
The existing infected pursuit and native input-release contracts remain mandatory.

`Infection fallback death: an unproven infected attack cannot fabricate contact infection credit`
observed RED against the retained attacker-role-only credit path. The correction preserves any-death
conversion but credits only accepted live native contact; the case subsequently passed in the 98/0/0 gate.

## Ownership and lifecycle

| Entity | Id | Responsibility |
| --- | --- | --- |
| Mode | `pw_infection` | Child of `round_base`, role policies and terminal personal-result transform |
| Module | `pw_infection_rules` | Pure rules, server roster and revisioned private-to-recipient snapshots |
| Behavior | `pw_infection_pursuit` | Infected legal-contact pursuit through normal goal/aim/input APIs |
| Behavior | `pw_infection_escape` | Survivor bounded local retreat and legal independent aim/fire |
| Adapter | `pw_infection_fists` | Native fists release-between-shots input rule; never changes damage |
| HUD | `pw_infection_status` | Own role, counts, timer, personal wins and informational infections |

`MODE:Start` checks required owners and native fists, then starts the sole common round loop.
`PrepareRound` builds the new identity roster before every playable spawn, releases old stat overrides,
admits waiting players through `PW.Jip.Admit` and places them through the teams owner. No private
base stores, saved classes, operator settings, commander orders or foreign board fields are mutated.
Pending quota departures are excluded through the manager's owner API, not a foreign-store read.

`PW_PlayerSpawned` records a new life after ordinary spawn initialization. The player-overrides owner
applies 400 spawn/max health and 1.15 times the ordinary walk/run baseline once per life. Refresh never
heals or compounds speed. Operators owns model validation/application and preserves the saved choice;
the addon additionally checks idle/movement sequences and releases the zombie override on incompatibility.

Death is deduplicated by stable identity and life generation. Deadline resolution occurs before death
or disconnect mutation. Conversion uses the synchronous teams transition and public revocation APIs;
the unified reset notifications invalidate each bot layer's own state, including asynchronous work.
`PW_RoundEnd` seals one completed round, clears live equipment and ends active streak effects without
consuming unused survivor streak inventory. The common loop alone advances, respawns or finishes.
`FinalizeRounds` returns personal standings with `teams = false`; no parallel round loop exists.

`Cleanup` removes the role provider state before requesting ordinary stats/models from their owners,
revokes remaining role effects and sends a revisioned inactive snapshot. It is idempotent and never
spawns, heals or restores an old life's health. Generic match-end reset belongs to each base bot owner.
Ordinary next-match assignment/loadout remains owned by teams/loadout, including FFA's free team.

A stable cleanup-only `PW_EntityDisabled` listener survives rules-module unsubscription. It releases
addon state on exact active-mode or required-owner disable, ignores unrelated definitions, and does not
spawn, grant effects or drive gameplay. A still-running mode observes missing state on its next ordinary
Think and requests a safe abort outside the cleanup notification. Repeated disable is idempotent.

## Addon API

`PW.Infection.Role(ply) -> "survivor" | "infected" | nil` returns a role only for the currently bound,
present roster entity. Reconnecting with the same stable human identity does not bind a current-round
life. `Active() -> boolean` additionally requires the owning active mode and LIVE phase.

`Snapshot(ply) -> PW.InfectionSnapshot?` is server-side and recipient-specific. It contains only revision,
round, remaining role counts, deadline, own role/waiting status, personal wins, own infection count and
intermission status. Reading one's history does not admit a waiting reconnect. No roster, enemy identity,
contact, target, path, location or enemy position is transmitted. `State` is owner-private in practice;
its annotations aid the addon implementation, not a foreign mutation API.

`PW.InfectionPresentation.Accept(current, incoming)` validates bounded integer counts, finite deadlines,
role values and increasing revisions, returning an allowlisted snapshot or nil. `Encode/Decode` use
small typed reader/writer interfaces; validation precedes writing. `pw_infection_state` is server-to-client
only: revision is 32 bits, active is 1 bit, counts/round/wins are 8 bits, deadline is a float, own role is
2 bits, intermission is 1 bit and informational infection count is 16 bits. An inactive tombstone sends
only revision and active; old active packets cannot resurrect presentation after cleanup.

Pure rules are `PickSeed`, `NewRound`, `Death`, `Disconnect`, `Winner` and `Summary`. They operate on
plain identity-keyed data, never engine entities. Humans use SteamID64 identities, bots their session
UserID. At result publication the addon maps identities back to current actors or saved numeric UserIDs
for departed participants; it never calls a method on a departed invalid player.

`PW.InfectionPresentation.Results(rows, ownId)` is the addon-owned pure final presenter. It copies and
allowlists public row identity/name, wins, public final K/D and informational infections, ranks by wins
alone, and assigns shared places to ties. Infection count never decides a tie. The addon consumes
`PW_PostmatchGathered` to replace only its result, sections and `ROUND WINS` metric label. It does not
wrap UI functions or award artificial score/XP. Ordinary modes keep their existing ordering and labels.

`pw_infection_results` is a separate server-to-client terminal-only channel. It retains copied public
metadata for departed participants, not stale player entities. A reconnect's association to its historical
row is supplied by the server; an unadmitted late viewer has association 0. SteamIDs remain server-only.
The same revision and complete row set are used for both initial and late delivery. Packets carry at most
64 rows, each name at most 256 bytes (long names use a safe fallback without UTF-8 slicing); total metadata
is bounded to 4096 rows. Header: revision 32 bits, active bool, recipient association 32 bits, total and
offset 13 bits each, chunk length 7 bits. Rows: UserID 32 bits, string name, bot bool, wins 8 bits,
infections/kills/deaths 16 bits each. Only a complete contiguous same-generation assembly becomes visible;
stale, duplicate, gapped or inconsistent chunks cannot mix revisions or resurrect cleared results.

The final cache survives normal mode Cleanup for POSTMATCH/late join, and is cleared on the next lobby,
prematch/new match or rules-owner disable. `PW_PostmatchDataChanged` rebuilds an already open summary
when a complete terminal snapshot arrives late. No per-frame Gather loop or hidden live information is added.

## Tests and limitations

- `mode_infection.lua`: optional source boundary, seed, conversion, exact outcomes and personal standings.
- `Touch` cases distinguish live contact conversion from retained world/suicide death policy;
  they cover same-life deduplication, invalid participants, strict deadline and initial-seed-only wins.
- `infection_presentation.lua`: generic operator override and allowlisted snapshot decisions.
- `infection_runtime.lua`: preset, fists adapter, roster validation, codec/tombstone and legal contacts.
- `infection_lifecycle.lua`: installed common-loop integration, spawn ordering, admission, role stats,
  model fallback, intermission, disabled/missing owners and cleanup.
  First-hit cases use the actual generic damage-owner callback for nonlethal bot and lethal human
  hits, provenance rejection, live-state preservation, public revocation/cached stats, role admission and
  once-only terminal results. The prior death/respawn fixtures remain for the unchanged fallback policy.
- `infection_escape.lua`: registered-Action contracts for survivor retreat, retained legal aim,
  dry/reloading weapons, bounded blocked-navigation handling, perceived-only admission and owned cleanup.
- `infection_results.lua`: bounded terminal codec/assembly, departed identities and reconnect binding,
  authoritative personal ordering and optional owner admission into the generic Gather extension.
- `ui_postmatch_extension.lua`: actual client Gather paths and event-driven late-root rebuild.
- `infection_melee_smoke.lua`: revised real-engine legal-sight pursuit/movement and first native fist hit
  through the ordinary writer, followed by alive conversion with zero death/spawn and preserved motion/control.
  This explicitly supersedes the old two-applied-damage-hit premise, not legal-input/pursuit assertions.
  Initial placement and a stationary target are fixture setup only; the measured attacker receives no
  forced target, scripted attack, injected damage or teleport. The revised smoke observed RED before
  implementation, then passed after implementation. The additional real-survivor case passes actual
  survivor-owned displacement, attack while moving and native gun damage; its fixture selects a supported
  local retreat corridor instead of a blocked roof edge. Opponent knockback cannot satisfy its movement
  assertion. The measured actor has no forced contact, target, attack, aim override or scripted movement.
  Both native cases restore their state and use public coroutine frame boundaries to wait for every exact
  owned bot identity to disconnect, including when an assertion fails, before the next case may allocate.
- Generic cases remain mandatory with the addon absent: `teams_transition.lua`, `player_overrides.lua`,
  `infection_role_transition.lua`, `role_policy.lua` and `bots_tactics_reset.lua`.

Source presence, not successful API registration, determines optional-addon test absence. A mounted
broken implementation fails. No automated suite substitutes for the human HUD, gameplay or P2P checkpoint.
The removal-between-startups matrix remains unverified without a separate authorized restart. Prior
source-absent baseline evidence is distinct from a disabled-addon test. Agent image inspection does not
pass a human checkpoint.
