# Search and Destroy: implementation research

**RESEARCH / NOT DECIDED.** Original implementation proposal, not a rule change or implementation authorization.
Base inspected: `integration/current-work`, `3754fe2ed359c069034568d88054f24aabb1562d`, 2026-11-07.
No gameplay code, copied addon code, assets, engine runs or performance measurements accompany this note.
Repository evidence below uses `P = addons/privatewar/lua/privatewar/` and
`C = addons/privatewar/gamemodes/privatewar/gamemode/core/`; paths after these prefixes are source citations.

## 1. Scope and fixed constraints

S&D is already the first post-MVP mode in `design/02-modes.md` d.5, using `round_base`.
Its detailed rules are not decided there. Familiar commercial defaults are not requirements.
`02-modes.md` d.6 keeps balanced human/bot assignment, N-team infrastructure and `PW.IsEnemy` checks;
this proposal uses two teams, with attack/defense as side roles, not humans versus bots.
`03-mapdata.md` d.4/d.6 hides an objective mode without valid authored data; “any map” does not promise S&D everywhere.
`07-bots.md` d.2/d.7 forbids hidden enemy knowledge and privileged bot interaction shortcuts.
Frozen APIs may change only through the orchestrator; this document defines no new contract.

## 2. Confirmed capability and gap matrix

| Concern | Existing evidence | S&D consequence / missing capability |
| --- | --- | --- |
| Match lifecycle | `C/sv_match.lua:128–132,158–159`, `enterPhase`, `transition` | Phase notification precedes mode `Start`, which precedes `PW_MatchStart`; initialize roles/sites in `Start` before initial spawn. |
| Round loop | `P/modes/round_base.lua:135–156,176–189`, `_Step`, `_Run` | Round wins, intermission, swap and finish exist; objective state and pre-respawn preparation do not. |
| Verdict and timeout | `round_base.lua:196–230`, `RoundWinner`, `Think` | Default elimination is wrong after planting; `_Step` converts an undecided timeout to draw. Returning nil cannot keep a planted round alive past roundtime. |
| Respawn | `P/modules/match_rules/init.lua:151–176`; `round_base.lua:250` | `PW_CanRespawn = false` covers dead humans and bots, not initial/explicit `Spawn` calls or active-round late join. |
| Side identity | `docs/api/teams.md`, `PW.Teams.Swap`; `round_base.lua:119–126` | Players and round wins move between team indices. Side roles must remain explicit; do not double-swap the cohorts. |
| Spawns | `P/modules/spawns/init.lua:116–167`, `prepare`, `PW_SelectSpawn` | First-spawn memory resets per match, not per round; module answers before the mode default. A mode method alone cannot reliably force side spawns. |
| Map compatibility | `docs/api/map.md`, `PW.Map.ModeFits`, `GetModeData` | Filtering and Base fallback exist; sites, interaction positions, safe bomb reset and authoring validation need their own schema. |
| Objective actions | `P/bot_behaviors/objective.lua:12–13,72–94` | Walking/guarding exist; carrying, planting and holding use to defuse do not. |
| Assignment | `P/modules/bots_commander/init.lua:79–87,107–119` | Sanitization keeps only six objective fields; carrier eligibility or interaction metadata would be discarded. |
| HUD / scoring | `P/modules/match_rules/shared.lua:31–48`; `docs/api/modes.md` | Round score prefix and match result work; bomb state, side labels and concurrent clocks need mode UI. |

**Important correction to earlier research:** at the inspected base, `notes/23-infection-mode-research.md` and
`docs/api/modes.md` “round_base” described initial spawn before `Start`; a separate documentation correction fixes this.
The core actually does the reverse. Later rounds still swap, respawn, then notify `PW_RoundStart`;
site/roster/reset work placed only in that notification is too late for the spawn itself.

## 3. Recommended minimum rule bundle, subject to approval

Recommend a two-team, one-life round mode with authored sites, one shared attacking-team bomb,
continuous hold-to-interact, no persistent partial interaction progress, finite attack and fuse deadlines,
round wins and periodic side swaps. No numerical defaults are selected here.
Keep normal validated classes/perks/equipment initially; explicitly decide streak availability and round persistence.
Do not implement the bomb by spending a lethal slot, cooking a grenade or abusing a player grenade SWEP.
A dedicated authoritative objective record owns it; an optional lightweight entity represents a dropped/planted object.
Minimum playable delivery includes bots, readable controller interaction and latejoin state, not a human-only prototype.
Defer manual passing, defuse kits, alternate bomb types, overtime variants and new progression rewards.

Text state outline (proposal):

```text
core PREMATCH -> LIVE
round prepare -> active/unplanted -> planted -> resolved -> intermission -> prepare
                         |              |
                 timeout/elimination  fuse/defuse/elimination
bomb assigned -> carried -> dropped -> carried -> planted -> removed
core abort / match finish -> cancel interactions, invalidate round token, clear objective
```

Round state remains inside core `LIVE`; intermission is not a core phase transition.
Give every action a match/round generation and every life an eligibility token; reject stale work after resolution.
Only one objective record may be carried, dropped or planted, never separate overlapping bombs.

## 4. Deterministic clocks and adjudication

Use server `CurTime` deadlines for round, plant hold, fuse, defuse hold and intermission.
Clients interpolate display only; do not send countdown messages each frame or trust client elapsed time.
Facepunch documents a synchronized game clock affected by time scaling and pause [E1]; this is not wall time.
Recommend one pure reducer over timestamped validated intents, life state and deadlines, with one terminal verdict.
Death/use hooks record facts; they must not independently finish the round or award the same plant twice.
The following is a coherent candidate precedence bundle, **requiring user approval**, not an engine guarantee:

1. Apply deaths, disconnects and invalid-actor cancellation before a same-tick interaction completion.
2. Plant/defuse completes only if continuously valid and its completion timestamp is strictly before its deadline;
   equality loses to the deadline. A completion recorded before a deadline survives a delayed reducer call.
3. An accepted plant replaces the attack clock with the fuse; a defuse resolves before any later explosion.
4. Unplanted: no attackers means defender win; no defenders means attacker win; both eliminated means draw.
5. Planted: all attackers dead does not end the round; defenders must still defuse. No living defenders means
   attacker win, unless both sides have just died, in which case the planted objective still resolves for attackers.
6. Before planting, round expiry is defender win; after planting, fuse expiry is attacker win.
   Reaching the required round wins finishes once; no extra swap/spawn follows.

The both-dead and last-defender proposals above are balance choices, not consequences of `round_base`.
A different last-defender rule (wait for the fuse) is feasible but changes spectator waiting time and cleanup timing.
Do not “fix” the base fallback by ignoring `timedOut`: `_Step` still forces a draw at its own deadline.
Prefer an approved child-aware timeout/round-preparation seam preserving existing base tests and notifications;
alternatively a child-owned objective clock with the base clock disabled needs explicit API/HUD review, not private-field hacks.
Server stalls must neither invent completed holds nor grant a reset timer; test boundary timestamps and exactly-once output.

## 5. Bomb, sites and interaction validation

Proposed mode map data: stable site ids with display position, plant volume and reachable interaction positions;
side spawn groups and a safe initial/drop-recovery position. Field names and accepted shapes remain unfrozen.
Separate remote-map structural validation from current-map world/nav/hull checks: `ModeFits` can inspect other maps
without having their BSP geometry loaded. Reject malformed/non-finite vectors, duplicate ids and unusable rotation-free sites.
For the initial variant recommend two authored sites; site count remains a user decision, not a reused Dom requirement.
Validate floor, hull clearance, approach paths, vertical bounds and interaction LOS at runtime before activation.
Do not infer bomb sites merely from CS spawn entities, an arbitrary nav centre or Dom flag letters.

- At round preparation choose a living eligible attacker as carrier deterministically, with an approved human/bot policy;
  do not always privilege the listen host or silently force a human to carry.
- Pickup requires alive, non-observer, enrolled attacker, active unplanted round, range and clear usable ground.
  Two simultaneous pickups resolve by a documented stable key; the loser gets no ownership or reward.
- Carrier death/disconnect drops once at the last validated ground point; invalid entity handles are not ownership ids.
  Outside world, water, pits, moving props and blocked ground use a validated recovery point, not unbounded teleport search.
- Plant requires current carrier, correct site volume/position, held use and valid stance/range/LOS throughout the hold.
  Defuse requires a living defender near the planted bomb under the same authoritative hold validation.
- Release, movement out of range, death, weapon/input conflicts, role change, disconnect or round end cancels the hold.
  Decide whether damage alone cancels and whether looking away matters; do not silently add either rule.
- Permit one defuser at a time; define stable arbitration and handoff with no shared partial progress.
  Verify stale pickup/use requests cannot revive a resolved bomb or refresh its fuse.

`GM:PlayerUse` repeats while use remains held and returns false to deny use [E2]; callback count is not elapsed time.
Evaluate an engine-use entity versus existing `IN_USE` input with thin wrappers in a prototype test.
Neither the wiki nor the present mode API proves that the desired marker-only entity is a reliable use target.
`pw_mark` currently supports only spawn/dom/header (`docs/api/map.md`, “pw_mark”); extending its output/parse tests,
not building a full editor, is the smallest authoring addition. No S&D map is promised by this research.

## 6. Lives, spectators and round-boundary leakage

Freeze the eligible round roster independently of the currently connected entity list.
`round_base:RoundWinner` counts currently present players; disconnecting the last member otherwise changes elimination semantics.
Recommend a late join waits until the next round when `lobby.joininprogress` is on;
when it is off the existing next-match spectator policy must stay intact unless the user changes it.
That round-aware join policy is a missing seam, not covered by denying dead respawns.
Keep balanced placement through `teams`; spectators must not consume live slots or cause premature bot replacement.
Reconnect by SteamID64 must not grant a second life, new bomb or duplicate reward; bot replacement also needs a life token.
Use team-only chase or another explicitly approved spectator policy; current JIP roaming is not secure competitive spectating.
No proposal here assumes host migration; a listen host leaving ends the session.

During intermission core phase is still `LIVE`: death scoring, equipment and streak checks are not automatically blocked.
`match_rules:DoPlayerDeath` dispatches `PW_PlayerKilled`; `round_base:PW_PlayerKilled` calls `ScoreKill` unconditionally.
`P/modules/streaks/init.lua:103–145,189–191,239–251` resets on match/death, not round hooks;
`P/modules/throwables/init.lua:112–122` clears thrown projectiles at match end, not round end.
Plan an approved round-active gameplay gate for damage, interactions, score and activations, plus boundary cleanup.
Clear pending throws, flashes, planted visuals, reveal instances and stale bot goals before the next playable round.
Do not presume a `PW_RoundEnd` listener returning a value can veto other listeners; it is a notification.
Keep objective victory counters separate from `PW.Score` personal/team points. Plant/defuse XP and streak gains are open;
objective awards must omit `ctx.weapon` so they do not accidentally grant the active gun weapon XP.
`ScoreKill` falls back to the active weapon for non-weapon inflictors (`match_rules/init.lua:49–54`);
any damaging bomb blast needs attribution tests and a user decision, or initially remain a non-damaging round result.

## 7. Bot completion and fair information

Attack: select one eligible carrier, choose a reachable site, escort without colliding with the carrier,
retrieve a team-known drop, plant through the same hold-use rules, then guard approaches and the planted objective.
Defense: distribute site guards, react to legal contacts, retake a publicly announced planted site,
reserve one defuser and assign protection; reassign promptly after death or an unreachable approach.
A solo remaining bot must still plant/defuse, not allocate itself only an escort/guard role.
Public site locations, attack/defense role, round/fuse deadlines and announced planted site are objective facts;
enemy carrier coordinates, hidden drops and defuser identity are not automatically public.
Propose team-only carried/dropped bomb information for attackers and public planted position; approval is needed.
Combat uses `board.contacts`/memory and legal stimuli, not a bomb objective's enemy entity live position.

`MODE:BotObjectives(team)` cannot currently express carrier-only eligibility; sanitizer discards extra fields.
`plant`/`defuse` are anticipated in `design/07-bots.md` d.14, not implemented input behaviors;
`objective.lua` merely walks unknown actions to the position. Carry/escort also need contract design.
Commander `keep` preserves active holds and otherwise keeps orders for its configured hold period;
`defend` caps at a third of managed bots (`P/modules/bots_commander/shared.lua:83–143`).
Do not bypass the cap by renaming every guard to hold or overwrite another layer's `board.order` from the mode.
Request typed eligibility/action/phase-aware reassignment through the orchestrator, with tests for tiny teams and all difficulties.

## 8. UI, replication and cost

Keep existing round-win bars via `pw_round_wins_`; add round/side text, alive counts, site markers,
bomb state, active interaction prompt/progress, attack-versus-fuse clock, intermission and waiting-for-next-round text.
Use original text/icons and built-in materials/fonts; no copied presentation or new required asset pack.
Replicate public objective generation/state/site/deadlines and deltas, with a complete latejoin snapshot.
Send carrier/drop visibility only to approved teammates; do not put hidden positions in globally transmitted entity vars.
Interactions need no client authority; any optional request uses `PW.Net.Receive` state/length/rate/value checks.
Shared HUD model functions must cover absent/disabled modules, expired timestamps and stale generation rejection.

Expected qualitative cost: low objective simulation and net volume, moderate bot/LOS/spawn integration effort.
Use cached sites, one roster snapshot per bounded update, squared-range filters and traces only for active interactors;
no per-frame `ents.Find*`, unbounded floor searches or new all-enemy polling. One bomb entity is enough.
Round-wide simultaneous spawn/loadout grants can spike existing weapon costs; measure on target hardware later.
P2P latency, use prediction, sound clarity and reconnect behavior remain unverified; no performance claim is made.

## 9. Test-first slices and human barrier

1. **Decisions/contracts:** approve the bundle below; orchestrator records map, clock, life/join and bot action seams.
2. **Pure round/bomb reducer:** GLuaTest table cases before implementation: every state transition, exact deadlines,
   same-tick lethal/plant/defuse/fuse, all attackers dead after plant, last defender, both dead, draw and final win.
3. **Map and life glue:** test validation/filtering on Custom/vote/playlists, role setup before initial spawn,
   preparation after swap but before later spawn, side-zone selection, roster and reconnect/bot-replacement eligibility.
4. **Objective interaction:** test one bomb invariant, simultaneous pickup/defuse arbitration, cancellation,
   carrier disconnect/death, invalid-ground recovery, stale callbacks and idempotent cleanup/abort/module failure.
5. **Bots plus UI together:** test carrier eligibility survives sanitizer, urgent reassignment, no hidden contacts,
   shared HUD/codec snapshot and deltas, observer exclusions, no enemy-coordinate transmission or weapon-XP leakage.
6. **Engine integration/smoke:** reuse shared test bots with generous timeouts for a plant/defuse path and a round swap;
   preserve `round_base.lua`, `respawn_regression.lua`, `bots_behaviors_objective.lua` and streak regression coverage.
7. **Human checkpoint, all lanes stop:** host plus P2P friend, controller hold/release and latency, latejoin both policies,
   death/reconnect/side swap, planted spectator information, unreachable/drop recovery and next-round cleanup.
   Inspect screenshots and profile objective/bot/spawn cost before choosing timing values or declaring playability.

## 10. Prioritized decisions and evidence limits

**P0:** approve objective/elimination/timeout precedence, side-swap cadence and win/draw structure;
site count/interaction bounds; next-round JIP and reconnect eligibility; initial carrier and drop visibility/recovery.
**P1:** hold durations and cancellation rules; streak/equipment persistence/availability; bomb blast damage/attribution;
XP/score awards, spectator restrictions and abandoned-team behavior. Numeric values and unlocks remain unset.
**P2:** passing, kits, overtime and richer audio. They are not prerequisites for the recommended first slice.

Method: local design/contracts/source/test inspection; no third-party implementation copied or downloaded.
Earlier Infection research was used only to locate shared risks; lifecycle claims were checked independently.
External engine references accessed 2026-11-07 (only facts described above are relied on):

- [E1: Facepunch, CurTime](https://wiki.facepunch.com/gmod/Global.CurTime).
- [E2: Facepunch, GM:PlayerUse](https://wiki.facepunch.com/gmod/GM:PlayerUse).

The standard bomb-round concept is a proposal from genre knowledge, not a sourced promise of exact commercial rules.
No GLuaTest/game/deploy run was performed for this docs-only study; future slices require the full project gates.
