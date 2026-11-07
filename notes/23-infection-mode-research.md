# Infection mode: reference and feasibility

Status: **RESEARCH / NOT DECIDED**. Investigated 2026-11-07 against `main` at `2d71b09`.
This proposes new scope, not an approved change to the MVP or any decided rule.
No addon code was obtained, executed, copied or integrated; no game session was used.

Evidence labels: **Page** = Workshop description; **Metadata** = official Steam API response;
**Repo** = inspected Private War code/contracts; **Proposal** = independent recommendation;
**Unknown** = not established. Workshop claims are not source-code verification.
Repository implementation paths below start at `addons/privatewar/lua/privatewar/` unless stated otherwise.

## 1. Verified reference and access status

- **Page/Metadata:** item `3264552874`, Garry's Mod application `4000`, title prefix
  `[LambdaPlayers] Lambda Zombies`; its Russian subtitle means “Zombie mode with bots”.
- **Page/Metadata:** author profile `cutesune`, creator SteamID64 `76561198295050701`.
  The display name is stylized; the stable identifiers above identify the credited account.
- **Metadata:** created `2024-06-09T17:06:36Z`; updated `2024-06-12T14:19:34Z`;
  `file_size = 20344` bytes; `hcontent_file = 3153864683983483270`.
  The page displays `20.344 KB`, three change notes and the same dates in its displayed timezone.
  No semantic version is exposed by the inspected metadata.
- **Page:** required items are `[LambdaPlayers] Team System Module` (`2948760835`) and
  `Lambda Players | The Zeta Player Sequel` (`2947828836`). The description says its team system
  must be enabled during a round. This is an extension for Sandbox, not a Private War mode.
- **Page/Metadata:** the HTML contains removed/incompatible notices, while the API returns
  item `result = 1`, `visibility = 0`, `banned = 0`, empty `ban_reason` and a readable description.
  These are conflicting availability signals, not proof of a ban, safety or working compatibility.
- **Page:** “Open source addon” appears under plans. No source repository or explicit source/asset
  redistribution licence was found in the inspected description/links. A plan is not a licence grant.

### Retrieval record and limits

1. Checked the standard macOS Steam Workshop location for `4000/3264552874` and the usual
   user Steam directory; neither was present. No alternate local library was discovered there.
   `steamcmd` and `gmad` were not available on PATH; no Deck storage was accessed.
2. Workshop WebFetch returned HTTP 429; a direct HTTPS GET of the official English-language
   page succeeded. Official `GetPublishedFileDetails/v1/` POST with this one ID also succeeded,
   without login or API credentials. Both `filename` and `file_url` were empty: no direct payload URL.
3. Bounded public searches for the title, exact item ID and `lambda_zombies_startgame` found no
   attributable source repository. This is not proof that no public source exists.
4. The Valve SteamCMD documentation returned HTTP 403 through WebFetch and a bot-challenge
   page through HTTPS GET. No challenge was solved or bypassed.
5. Downloaded only Valve's official macOS **SteamCMD tool archive**, not the addon.
   Its SHA256 is `8ecc17c8988e5acadcc78e631c48490f76150f2dfaa6cf8d7b4b67b097bd753b`.
   A strict archive inspection rejected framework symlinks; member listing identified contained
   framework links. The subsequent isolated extraction/runtime command was refused by the
   worktree security guard because it could not verify a temporary `HOME` assignment.
   No SteamCMD executable ran; anonymous Workshop entitlement was therefore **not tested**.
   The guard was not bypassed and no account-based download was attempted.
6. The user subsequently requested a Deck-side SteamCMD attempt. After the coordinator granted the
   exclusive slot, a trusted temporary wrapper was prepared using the existing `common.sh`,
   `deck_lock` and `deck_run` helpers. The local worktree guard refused its Nix-wrapped shell
   invocation before execution because it could not verify that it stayed within Git boundaries.
   No SSH command ran, no Deck lock was acquired, and the slot was immediately returned.
   The refusal was not bypassed. This is a local execution blocker, not a remote Steam login error.
7. Page, metadata and tool-archive downloads remain in separate fresh OS temporary directories,
   outside Git. No addon archive was extracted and no downloaded addon code/configuration ran.
   No source filename, line number or addon checksum can honestly be reported.

Metadata response SHA256: `feeed7636888ffab2f12aa5d1a97b1f1b41f3ccd31bdafa071ae1e3fe9110fa1`.
It identifies this research snapshot, **not** the addon payload. The access blocker is an absent
public payload URL/source plus an unperformed, guard-blocked SteamCMD route; authentication
requirements, deletion and download entitlement remain unknown.

## 2. Observed player loop: description only

**Page:** the host configures the extension in a Lambda Players “Lambda Zombies” panel.
Named controls specify human/zombie team names, initial zombie health and initial zombie count.
`lambda_zombies_startgame` starts an epidemic round; `lambda_zombies_selectrandomzombie`
selects a random Lambda or player for conversion; `lambda_zombies_allzombietohumans` cures zombies.
The description therefore supports a human/zombie role-switching concept with seeded infection.
It does **not** establish whether infection requires a hit, a kill, a particular weapon or proximity.

**Page:** extension hooks advertise before/after human and zombie conversion, first infection,
role-specific thinking and victory events. Examples include `LambdaZombiesBeforeSetZombie`,
`LambdaZombiesAfterSetHuman`, `LambdaZombiesFirstInfection` and `LambdaZombiesHumanWin`.
The text for `LambdaZombiesZombieWin` says “when zombies are defeated”, contradicting its name;
no win-condition conclusion should be drawn from that wording.
Multiplayer is claimed but described as not battle-tested. A “Hero” Lambda is a future plan.

**Unknown:** actual state machine, automatic first-infected selection, timer policy, death/respawn
conversion, movement/melee/equipment, late join, disconnect recovery, HUD/net format and bot AI.
Screenshots and description do not verify those mechanisms; no playtest was performed.

## 3. Source architecture: inspection incomplete

No Lua files from item `3264552874` were downloaded or inspected. Consequently there is no
source architecture audit, proven hook dispatch order, damage attribution audit or performance result.
The page exposes a **framework-facing interface**, not its implementation.

**Repo:** `DESIGN.md`, “Decided”, requires real `Player` bots through `player.CreateNextBot`
and `StartCommand`; `design/07-bots.md` d.2–3 requires virtual-gamepad control and existing layers.
**Page:** this addon requires Lambda Players and its Team System Module. Its named hooks are
Lambda-specific, not `PW_*` contracts. A Lambda or NextBot entity must not replace Private War's
player bots. The dependency's precise entity model was not independently source-audited here;
there is no evidence that this extension is a drop-in for Private War's `Player` architecture.

**Proposal:** transfer only the general infection mechanic into independently authored `MODE`
rules and player-bot behaviour. Do not import Lambda globals, teams, commands, entities or assets.
Workshop availability is not permission to redistribute source or assets. Mechanic inspiration is
not a legal clearance; avoid third-party branding/content and obtain permission where necessary.
The repository's no-third-party-code-copy rule remains binding regardless of a later licence discovery.

## 4. Private War integration: reusable surfaces and actual gaps

**Repo:** `design/02-modes.md` d.5 lists MVP modes and S&D as the first post-MVP mode.
Infection is an additional proposal, not an already scheduled/approved next implementation.
`docs/api/modes.md`, `teams.md`, `loadout.md` and `bots-blackboard.md` freeze shared contracts;
changes require the orchestrator and gameplay decisions require the user.

| Area | Existing evidence | Consequence for Infection |
| --- | --- | --- |
| Lifecycle | `modes/tdm.lua:17–46`, `modes/ffa.lua:5–11`; `Start`, `Think`, `Cleanup`, `PW.Match.Finish` | Own only `LIVE`; retain core lobby, preparation, postmatch and vote. No independent engine Think loop. |
| Rounds | `modes/round_base.lua:135–156, 167–230, 246–252` | Reuse the abstract round machinery, but override elimination and respawn rules. Default last-team-alive logic and no respawn are wrong for renewable infected lives. |
| Start order | `modules/match_rules/init.lua:135–146`; `round_base.lua:180–182` | Match-start listeners spawn everyone before mode `Start`; later rounds respawn before `PW_RoundStart`. Role setup in those mode callbacks alone is too late for the first loadout/spawn. |
| Teams | `modules/teams/init.lua:33–44, 97–104, 124–130`; `design/02-modes.md` d.6 | Normal assignment is balanced across humans and bots. One infected versus many survivors needs explicit approval of a mode-specific exception and a public placement/transition contract, not a silent replacement of balancing. |
| Relationships | `PW.IsEnemy`, `PW_IsEnemy` in `docs/api/teams.md` | Keep all friendly/enemy checks on that surface. Independent role flags without matching team consumers would desynchronise HUD, spawn and AI assumptions. |
| Death/respawn | `modules/match_rules/init.lua:144–176`; `PW_PlayerKilled`, `PW_CanRespawn`, `PW_RespawnDelay` | Let the existing respawner drive both humans and dead bots. Gate by round phase and pending conversion; never immediately `Spawn()` inside the death notification. |
| Loadout | `PW_PlayerLoadout`, `PW.Loadout.Resolve/Give`, `PW_LoadoutGiven`, `docs/api/loadout.md` | A mode-provided table replaces the class, including bot classes; it is trusted and unvalidated. Establish roles before all consumers resolve it; preserve the saved human class. |
| Mode examples | `modes/kc.lua:116–120`, `modes/dom.lua:122–205` | KC composes kill scoring and its rule; DOM shows separate objective victory. Infection must not inherit a TDM kill-limit win or score every conversion as a weapon kill. |
| Spawns | `modules/spawns/init.lua:116–148, 153–158` | `PW.Spawns.Pick(ply, opts)` exists, but the module already answers `PW_SelectSpawn` before the mode. A mode answer alone cannot reliably tune its default; an approved tuning surface is a contract gap. |
| Bot state | `modules/bots_manager/init.lua:185–196`; `docs/api/bots-blackboard.md` | Manager refreshes board team periodically, not atomically with conversion. Contact, order, hunt, target and movement owners need a coordinated role-change invalidation; the mode must not write their private stores. |
| Join replacement | `docs/api/modes.md`, “Join in progress”; `bots-blackboard.md`, manager rules | Default late placement and smallest-team bot replacement do not preserve asymmetric infected/survivor counts. Resolve the policy before enabling join-in-progress. |

**Proposal:** start with a single round per match (`RoundsToWin = 1`, no side swap), using
`round_base` only after the setup-order gap is addressed. This avoids inventing aggregate cohort
wins while players change sides. Multiple rounds need role reset **before** respawn, not merely
an after-respawn `PW_RoundStart` reaction. No proposed new hook name is an existing API.

## 5. Recommended minimum rules, subject to approval

Roles are **survivor** and **infected**, not “human” and “bot”: either actor type can hold either role.
Proposed initial seeding is a random eligible participant with an injectable PRNG, leaving at least
one survivor. Do not promise “all friends versus infected bots”: that conflicts with the decided
no-human-grouping policy (`02-modes.md` d.6) and needs a separate user decision.
A forced bot seed for solo practice could be an explicitly approved later variant.

| Event | Proposed minimum semantics; all are undecided gameplay choices |
| --- | --- |
| Preparation | Use core `PREMATCH`; require enough active participants for both roles. Assign roles before playable spawning. Start a finite chase deadline once the round is active; no extra grace-stage timer initially. |
| Infection | A survivor death during the active round creates exactly one pending infected life; conversion is death-based, not every melee touch. Never heal/teleport a living victim as an infection shortcut. |
| Infected death | Remain infected, respawn through the shared delay path. A moment with no infected currently alive does not award a survivor win while infected respawns are pending. |
| Survivor win | At the deadline, at least one eligible survivor remains; infected elimination alone is not a win. Define deadline-versus-lethal-hit ordering explicitly. |
| Infected win | No surviving or pending survivor lives remain after committed death/conversion events. Converted victims must leave the survivor count while waiting to respawn. |
| Suicide/world death | Recommend conversion to prevent suicide-based escapes, with no infection credit. Teamkills and invalid attackers must not grant infection credit; friendly-fire policy still needs approval. |
| Simultaneous events | Commit once per life, then evaluate victory from the resulting snapshot. Stop accepting scoring, conversion and respawn actions after round end/abort. |
| Respawn | Infected only during active play, with a configurable delay and normal safe spawn. No unlimited survivor respawns; no respawn during intermission/postmatch. |
| Late human join | Recommend spectating until the next match initially, respecting the existing server setting rather than silently changing it. A mode-specific restriction and slot/quota semantics need an approved contract. |
| Disconnect/quota | Reconcile before declaring “no infected”. If the last infected leaves, propose reseeding an eligible participant; if impossible, abort/draw rather than waiting forever. Define whether replacements inherit departed roles. |
| Reconnect | Do not let reconnect restore a survivor life; for the first slice the spectator policy closes this route. Clean stale entity references; do not trust a recycled entity index. |

**Proposal:** survivor weapons come through existing loadout/adapter rules; infected get an explicit
melee-only loadout using an existing stock melee weapon first. No new model/sound/material pack,
throwing knife, health regeneration, special jumps, barriers, classes or last-survivor buff initially.
Exact health, speed, damage, initial count, time, delay, bans and rewards require approval/tuning.
Any later role stat applies equally to human and bot occupants: never a bot-only buff (`07-bots.md` d.2).
Optional later variants: multiple seeds, fixed infected-bot practice, limited throwable, curated survivor
loadouts, multi-round personal scoring, hero/last-survivor rules. None follows from the reference page.

## 6. Bots, loadout systems, scoring and map safety

**Repo:** `design/07-bots.md` d.5–9, d.13–14; `docs/api/bots-blackboard.md`, “Intent”,
“Mode objectives” and “Commander”: `MODE:BotObjectives(team)` provides positions and actions
`capture/defend/collect/deny/hold`, not a dynamic enemy-entity pursuit contract.
Do not pass hidden survivor coordinates as objectives or fake map-wide stimuli.
`PW.Bot.AddStimulus`, `SetGoal` and the existing perception/contact memory remain the knowledge path.

**Proposal:** survivor bots initially reuse combat/cover/search. Infected need a role-aware melee
pursuit and search policy: approach remembered/visible contacts, navigate around obstacles, stop
sprinting before attack and avoid firearm-range camping/cover-reload behaviour. Existing `melee`
is close-range, not proof of end-to-end infection AI. Preserve commander hunt-slot fairness;
a horde focus-fire exception is not approved. A role-aware behaviour admission/reset contract is
needed to prevent generic behaviours or old orders winning after conversion.
Use `intent.weapon/buttons`, adapter input/fire rules and shared melee handling; no direct AI damage.

**Repo:** equipment resolves slots on `PlayerSpawn` and grants grenade weapons one tick after
`PW_LoadoutGiven` (`modules/equipment/init.lua:94–116, 184–205`). Perks refresh on
`PW_LoadoutGiven`, clear after death and include uniform `MODE.Stats`
(`modules/perks/init.lua:75–96, 169–205`). Streak death handling resets progress but retains earned
inventory; use checks phase/alive/inventory, not role (`modules/streaks/init.lua:129–135, 189–200`).

**Proposal:** decide perk/equipment/streak allowances as a complete role policy, visible in Game Setup
and loadout UI. Clearing infected streak slots alone does not revoke held streaks or active effects.
A supported role-change revocation path is missing; do not call private `_Clear` functions from a mode.
Uniform `MODE.Stats` cannot express different per-role stats by itself; use an approved public source
and lifecycle recomputation, or keep ordinary stats initially. Keep ARC9 optional through its adapter;
absence of any external base must leave a playable stock-weapon mode.

**Repo:** `PW_PlayerKilled` reaches module listeners before the mode's method. `ScoreKill` tests
`PW.IsEnemy` at call time and uses a weapon inflictor, otherwise the attacker's active weapon
(`modules/match_rules/init.lua:66–87`). Progression consumes `PW_ScoreEvent`; weapon context can
grant weapon XP (`docs/api/modes.md`, “Score module”). Changing teams first can suppress a legitimate
kill or misclassify delayed damage. Perk callbacks must still see the pre-conversion relationship.

**Proposal:** retain a death-time record of victim role/life, credited attacker, attacker role and
inflictor; score once before applying the relationship change. Preserve projectile/thrower attribution
across later conversion/disconnect and never credit the attacker's newly held weapon for old damage.
Separate survival outcome, infection credit and ordinary kill events; infection without a valid enemy
attacker grants no credit. Reward values and progression eligibility remain open; prevent repeat-life
and reseeding farming. Do not use accumulated team kill score as the infection win condition.

**Proposal:** postmatch needs an explicit personal outcome (survived, converted, initial infected,
joined late), not simply “your current team won”: a converted victim may now occupy the winning
infected team. Existing team-index `PW.MatchResult` is insufficient for that interpretation.
Agree result/HUD semantics before persistent win awards or multi-round standings.

**Repo:** `design/03-mapdata.md` d.1, d.3, d.7–8 provides optional map data, map/navmesh fallback,
hull-safe scored spawns and host-approved nav generation. Keep `MapData` optional initially.
**Proposal:** use normal spawn distance/LOS/hull checks, not corpse spawning or teleport-to-target.
Check seed separation and simultaneous respawn occupancy; never force an infected into a blocked spot.
Spawn protection must not permit a protected melee infection. No safe candidate needs a bounded retry
or explicit fallback/abort policy; do not bypass the hull check to keep the round moving.
Navmesh absence permits human play with entity spawns, not functional bot pursuit. Validate that
camping positions, stairs, doors and survivor routes are actually reachable; ladders are not planned
by the current bot graph. Never auto-generate navmesh, unlock doors or ban maps silently.

## 7. Cost and player-hosted constraints

**Inference, unmeasured:** role/life state and count updates are small relative to existing player
simulation; melee-heavy clustering, repeated safe-spawn traces and frequent A* repaths may be costly.
Cache counts and perform bounded/event-driven reconciliation; do not scan all entities every tick.
Reuse the scheduler budget/profiler rather than promising a particular bot count or frame rate.

**Proposal:** the server owns seeding, deaths, conversion, time and results. Clients receive role/count,
stage/deadline and personal outcome snapshots/deltas, not hidden enemy positions or full tables.
Reuse timer/HUD registries with cached resources; deliver role, survivor count, conversion notice and
spectator instructions with the first playable slice. No client may request “infect player” or grant a role.
Any new client request needs `PW.Net.Receive` permission/state/rate/value validation.

**Inference, unmeasured:** a stock-asset version has little new asset-download cost; its real server,
client and network costs still require measurement under a crowded endgame and join/respawn burst.
The listen host simulates AI while rendering and serving Steam P2P peers: CPU spikes and upload
constraints matter. There is no backend, host migration or authority transfer in this proposal.
Respect `bots.fill`, the reserved join slot, `maxplayers` and Singleplayer's inability to create bots;
never silently increase slots or replace the bot manager with Lambda entities.

## 8. Verification, slices and decisions needed

Recommended test matrix, **not executed**:

- **Pure GLuaTest, TDD first:** deterministic seed eligibility/count bounds; insufficient participants;
  one conversion per life; all death/attacker categories; delayed projectiles; pending-respawn counts;
  last survivor/deadline ordering; disconnect/reseed/quota reconciliation; no actions after finish;
  role resets before loadout; enemy checks; result attribution; role-policy cleanup; bounded codecs and
  late-join snapshot; HUD models; missing optional modules. Keep existing mandatory cases unchanged.
- **Engine smoke:** human/bot deaths use the same respawner; infected use real melee and move on
  navmesh; correct first loadout; no firearm/grenade/streak leakage; same-frame spawn occupancy;
  cooked grenade attribution; blocked/unreachable spawns; no-navmesh humans-only; cleanup on abort,
  reload and mode switch; no stale AI targeting after conversion. Few scenarios, generous timeouts.
- **Human checkpoint barrier:** solo/listen-host and friend over P2P; both roles playable and readable;
  late join/reconnect/disconnect; endgame camping/reachability; spawn protection; stock-only and ARC9;
  profiler/network comparison and client frame pacing on target hardware. Stop lanes for sign-off.

Proposed dependent slices: (1) user rule decisions and orchestrator-frozen contracts; (2) pure round,
role/life/result model and tests; (3) server hooks, role-aware loadout/respawn plus minimal HUD;
(4) bot admission/pursuit/state invalidation and smoke tests; (5) join/quota/attribution/revocation
hardening, then the human checkpoint and measurements. No slice is approved by this research.

Consequential user questions, in priority order:

1. Approve Infection as new scope and an asymmetric-role exception to balanced assignment? Should
   seeding include humans, or should a separately approved practice variant force an infected bot?
2. Confirm death-based conversion, renewable infected lives, deadline survival and suicide/world-death
   policy, including simultaneous deadline/death and last-infected disconnect rules?
3. Single round first? How should converted players' personal result and any progression rewards work?
4. Are joiners spectators, infected, or exact role-preserving bot replacements; which server setting wins?
5. Which loadouts/perks/equipment/streaks are allowed per role, including already earned/active effects?
6. What role stats, timing and spawn-protection rules should be tested? No final numbers are proposed here.

## Sources and method

Primary sources accessed on **2026-11-07**:

- [Reference Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3264552874&l=english).
- [Official item metadata endpoint](https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/):
  POST `itemcount=1`, `publishedfileids[0]=3264552874`; snapshot digest recorded above.
- [Steam Remote Storage API documentation](https://partner.steamgames.com/doc/webapi/ISteamRemoteStorage):
  confirms POST method and item-ID parameters; does not document a payload-URL guarantee.
- [Team System dependency](https://steamcommunity.com/workshop/filedetails/?id=2948760835) and
  [Lambda Players dependency](https://steamcommunity.com/workshop/filedetails/?id=2947828836): identities
  verified from the reference page's required-item links; dependency source was not inspected.
- [Valve SteamCMD documentation](https://developer.valvesoftware.com/wiki/SteamCMD): access blocked/challenged.
- [Official SteamCMD macOS tool archive](https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz):
  tool only, not an addon source; download/inspection limits recorded above.

Local primary evidence: `DESIGN.md`; `design/02-modes.md`, `03-mapdata.md`, `07-bots.md`;
`TASKS.md` handover, mandatory cases, testing and Phase 11; the four API contracts and implementation
paths cited above. Public source searches were bounded and inconclusive, not a substitute for inspection.
No implementation, design/API changes, redistribution, subscription, upload or game tests formed part of this work.
