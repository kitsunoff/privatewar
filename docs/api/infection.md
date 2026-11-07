# Infection integration

Optional addon root: `addons/privatewar-infection/`. Design: `02-modes.md` d.8.
The declarations ship with the addon in `lua/privatewar/types/pw_infection.lua`.
An absent addon leaves `PW.Infection`, `PW.InfectionRules`, `PW.InfectionAI` and
`PW.InfectionPresentation` absent. Do not require them from ordinary content.

## Ownership and lifecycle

| Entity | Id | Responsibility |
| --- | --- | --- |
| Mode | `pw_infection` | Child of `round_base`, role policies and terminal personal-result transform |
| Module | `pw_infection_rules` | Pure rules, server roster and revisioned private-to-recipient snapshots |
| Behavior | `pw_infection_pursuit` | Infected legal-contact pursuit through normal goal/aim/input APIs |
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

## Tests and limitations

- `mode_infection.lua`: optional source boundary, seed, conversion, exact outcomes and personal standings.
- `infection_presentation.lua`: generic operator override and allowlisted snapshot decisions.
- `infection_runtime.lua`: preset, fists adapter, roster validation, codec/tombstone and legal contacts.
- `infection_lifecycle.lua`: installed common-loop integration, spawn ordering, admission, role stats,
  model fallback, intermission, disabled/missing owners and cleanup.
- `infection_melee_smoke.lua`: real-engine legal-sight pursuit, movement and two native fist hits through
  the ordinary writer. Initial placement and a stationary durable target are fixture setup only; the
  measured actor receives no forced target, scripted attack, injected damage or teleport.
- Generic cases remain mandatory with the addon absent: `teams_transition.lua`, `player_overrides.lua`,
  `infection_role_transition.lua`, `role_policy.lua` and `bots_tactics_reset.lua`.

Source presence, not successful API registration, determines optional-addon test absence. A mounted
broken implementation fails. No automated suite substitutes for the human HUD, gameplay or P2P checkpoint.
Post-implementation type/full game gates and the removal-between-startups matrix are not yet verified.
