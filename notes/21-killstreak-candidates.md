# Killstreak candidates

Research, 2026-11-07, against `main` at `2d71b09`. **Exploratory recommendations, not approved requirements.**
No implementation, design changes, game sessions or measurements accompany this note. Perks are considered separately in [22-perk-candidates.md](22-perk-candidates.md).

## Scope and evidence

The target is casual solo/friends against convincing player bots on a Steam P2P listen server, with Steam Deck performance first.
Prefer useful ground/support effects, bounded simulation and Lua-only in-house UI; do not build a vehicle framework just to draw aircraft.
`design/05-loadout.md` d.9 fixes earning and instance semantics; d.10 puts AI-driven aircraft after MVP. These proposals do not reopen either decision.
All proposed costs, unlock levels, radii, timings, limits and perk interactions remain choices for later approval, not values specified here.

Evidence labels: **R** = verified repository behavior; **E** = accessed engine documentation; **P** = reasoned proposal; **G** = requires in-game proof.
Below, `R/` means `addons/privatewar/lua/privatewar/`; `G/` means `addons/privatewar/gamemodes/privatewar/gamemode/` (not the evidence label).
Code references are paths plus symbols or line numbers at the stated revision. Primary web sources and their access date are listed at the end.
Cost estimates are qualitative and **unmeasured**; low cost is not a guarantee of acceptable frame time.

## Shipped baseline and boundaries

- **R:** `R/streaks/uav.lua:18-22` periodically reveals enemies; `counter_uav.lua:7-10` jams hostile reveals; `airstrike.lua:54-67` schedules a line of explosions. There is no simulated aircraft in any of these three.
- **R:** `R/kinds/streaks.lua:8-11`, `R/types/streaks.lua` and [Streaks API](../docs/api/streaks.md) define `Name`, `Kills`, `Score`, `Duration`, `OnEquip`, `OnUnequip`, `BotShouldUse`. A new content file fits the registry, not necessarily the entire gameplay feature.
- **R:** `R/modules/streaks/shared.lua:_Gain/_Crossed/_AfterDeath` supports kill/score earning; thresholds do not loop. `init.lua:_OnScore/_OnDeath` resets progress on death unless persistence applies; unused inventory survives death. Streaks stay outside Pick X (`05-loadout.md` d.2, d.9).
- **R:** `init.lua:StreakDamage` suppresses progress only for score events synchronously inside its callback. Every later shell, bullet or projectile impact needs its own marked damage path; wrapping only activation is insufficient. Keep `streaks.chain` off by default.
- **R:** `init.lua:activate/Use` consumes inventory before activation, then ends the instance after `Duration`. It has no placement-refusal/refund transaction. Validate a deployment before consumption through a future public contract, not a client promise or a patched `Use` function.
- **R:** `G/core/sh_instance.lua:Remove` removes instance hooks/timers, not spawned entities. `R/modules/streaks/init.lua:PW_MatchEnd` ends activations; disconnect only clears inventory, and death only resets progress. Persistent objects need explicit `OnUnequip` removal and an owner-invalid policy.
- **R:** `PW.Reveal(viewer, targets, duration)` in `R/modules/streaks/sv_reveal.lua:102-119` sends only accepted targets to the viewer's humans and bots, filtering Counter-UAV. Never broadcast enemy lists or implement a separate hidden-position stream for a sensor.
- **R:** `R/modules/bots_loadouts/init.lua:PoolFor/Assign` supplies valid classes. `R/bot_behaviors/use_streak.lua` and [Bots API](../docs/api/bots-blackboard.md), "Kinds", reach `PW.Streaks.Ready/Use`; `BotShouldUse` currently returns only a decision, not a validated placement/target plan.
- **R:** `airstrike.lua:70-77` checks all enemies' live positions through `Enemies`, not the bot's contacts. Do not copy this omniscient eligibility check: new offensive targeting must use recognized sight, remembered positions or deliberate radar stimuli (`design/07-bots.md` d.2, d.7).
- **R:** Airstrike passes world as inflictor (`airstrike.lua:42-46`), while `R/modules/match_rules/init.lua:weaponOf` falls back to the attacker's active weapon when the inflictor is not a weapon. Consequently its kills can award held-gun XP. `StreakDamage` does not fix weapon XP attribution. Resolve damage provenance before expanding lethal streaks; preserve player score/XP while omitting unrelated weapon XP (`06-progression.md` d.3).

## Compact feasibility matrix

All rows are **new proposals**, not shipped items. Cost order is server / client / network / additional assets: L = low, M = moderate, H = high relative to existing streaks.
A stock model still needs a deliberately readable silhouette; asset availability and collision are **G**, not a licence to copy another game's content.

| Id | Candidate | Relative effort | Main missing piece | Estimated cost S/C/N/A |
| --- | --- | --- | --- | --- |
| K1 | Directional snapshot scan | Easy | Cone/LOS filter | L/L/L/none |
| K2 | Ammunition cache | Easy–medium | Capped reserve resupply + placement | L/L/L/stock |
| K3 | Medical station | Easy–medium | Shared heal arbitration + placement | L/L/L/stock |
| K4 | Ground sensor | Medium | Destroyable deployable + placement | M/L/L/stock |
| K5 | Portable barricade | Medium | Collision/placement and bot obstruction policy | L/M/L/stock |
| K6 | Projectile interception node | Medium–expensive | Public projectile interception contract | M/M/M/stock |
| K7 | Remote demolition charge | Medium | Second-action input + damage provenance | L/M/L/stock |
| K8 | Mortar suppression zone | Medium–expensive | Telegraphs, roof policy, bot avoidance | M/M/M/stock |
| K9 | Local electronics disruption | Medium, after deployables | Device allegiance/disable contract | L/M/L/none |
| K10 | Fixed automated sentry | Expensive, bounded prototype | Targeting, deployables, provenance | M/M/M/stock or original |
| K11 | Remote-operated gun | Expensive/defer | Input/camera ownership + bot control | M/M/M/original likely |
| K12 | Player-controlled recon drone | Expensive/defer | Flight, camera and safe reveal path | H/H/H/original likely |
| K13 | Autonomous escort aircraft | Defer | Air navigation/targeting/asset framework | H/H/H/original likely |

## Easy or relatively small candidates

### K1 — Directional snapshot scan

**P:** One intentional, owner-facing scan reveals enemies in a cone with LOS, rather than the UAV's repeated map-wide sweeps. It rewards choosing a lane; cover and Counter-UAV defeat it.
Reuse `PW.Reveal` and `PW.Streaks.Viewer`; add a pure cone/range selector plus budgeted server trace wrapper. No new wire is necessary if the existing radar presentation suffices.
Bots activate toward a recognized contact or an assigned lane, never an unseen nearest enemy. The same cone/LOS conditions apply; no navmesh dependency, works indoors subject to doors/glass trace policy (**G**, E2).
Cost: one bounded player pass/trace batch, existing cached radar, one recipient-scoped message, no new models; suitable for P2P. CUAV can make the scan empty, so UI feedback must be explicit without revealing how many enemies were hidden.

### K2 — Ammunition cache

**P:** Deploy a visible cache that replenishes ordinary weapon reserve, not magazines in hand or grenades. It extends firefights without improving accuracy; opponents can destroy it or contest access.
`ADAPTER:GetAmmoType/GetClip` ([Adapter API](../docs/api/adapter.md), "Ammo"/"State") can identify compatible reserve. `PW.WeaponAmmo.Give` is spawn-time weapon provisioning, **not** a public resupply API: add capped reserve addition and shared-ammo deduplication rules.
Bots can deploy by an objective/cover goal; receiving supply requires a new reachable support-goal behavior, not `use_streak` alone. Start with bounded nearby automatic receipt plus LOS if approved; no teleporting bots to caches.
Cost: low-rate local player checks, one stock static entity, sparse use/charge deltas; minimal effects. Placement needs floor/hull clearance (E2), cannot block a doorway; navmesh needed for deliberate bot visits, not passive receipt. No CUAV effect.

### K3 — Medical station

**P:** A temporary, destroyable station gradually heals nearby allies out of immediate combat; unlike Adrenaline it is location/team support, not a personal kill reward. Leaving its area or taking fire interrupts benefit.
`R/perks/adrenaline.lua:11-15` demonstrates capped owner healing, not a team-heal service. Add a plain-data eligibility/overlap reducer, placement validation and one heal owner so multiple stations/perks do not accidentally multiply healing.
Bots gain the same healing and may deploy at a defend goal; choosing to retreat to it requires a support objective contract. Do not grant bot-only health bonuses or instant cross-map station knowledge.
Cost: low-rate bounded player checks, existing health replication, one stock object and a cached allied HUD marker. Indoor-friendly; LOS prevents healing through floors. Navigation only for visits. Destroy/flush it, deny proximity; CUAV does not suppress physical healing.

## Medium candidates with explicit contracts

### K4 — Ground sensor

**P:** A destructible local sensor repeatedly reveals nearby hostiles; walls/height/LOS policy determines coverage, not the whole map. It creates a contestable object instead of a stronger UAV.
`R/streaks/uav.lua:RevealEnemies` supplies the reveal cadence pattern; use `PW.Reveal` so CUAV filters humans and bot stimuli identically. Add deployable health, allegiance, placement, instance-owned removal and a local candidate filter; no direct bot-blackboard writes.
Bots deploy from their current defend/contact goal; attacking a sensor requires non-player-device targeting, which current player-contact perception does not provide. Until that exists, do not claim bots can counter it intelligently.
Cost: bounded scheduled player checks/traces, stock static model, scoped radar messages, sparse health state. Works indoors if floor/LOS policy is explicit; never assume sphere distance distinguishes floors. Navmesh only for chosen placement/visits. Destroy, relocate or jam it.

### K5 — Portable barricade

**P:** Place finite-health directional cover; flank it, shoot it down or use explosives. It changes lines of fire, not damage immunity or invulnerable collision tricks.
Reuse the activation instance, not a pre-existing shield API (none is present). New contracts: legal footprint/slope, occupied exits, damageability, ownership and safe failure before inventory spend. `util.TraceHull` tests axis-aligned clearance, not an arbitrary rotated cover shape (E2).
Bots need obstruction-aware repathing and a way to choose/use the new cover; existing navmesh paths and cover searches are not proof that dynamic props work. Without these, restrict the prototype rather than advertise symmetric bot use.
Cost: static server collision is relatively small; client geometry/visibility needs proof, sparse health networking, stock model only if collision is trustworthy. Tight corridors, stairs and doorways are high-risk; reject unsafe placement. CUAV irrelevant; P2P peers must see identical collision.

### K6 — Projectile interception node

**P:** Destroy a limited number of eligible incoming projectiles near the node. Bullets, hitscan explosions and arbitrary third-party rockets are not automatically interceptable; overwhelm or shoot the node to counter it.
`R/modules/throwables/init.lua:throw/detonate` owns `pw_grenade` fuses but exposes no public interception registration/cancel contract. Add explicit projectile allegiance, owner/inflictor and cancellation semantics; do not scan every entity each tick or remove unknown SWEP entities.
Bots benefit from the same protection and deploy near a defended goal; deliberate node targeting needs the device contract from K4. Enemy/friendly and cooked-death-drop grenades need explicit policies preserving `05-loadout.md` d.11.
Cost: a bounded registered-projectile set, limited traces, small effects and sparse interception events; stock static node. Indoors require LOS so it cannot intercept across floors. No navmesh for interception. CUAV irrelevant; cross-base support remains opt-in and unverified.

### K7 — Remote demolition charge

**P:** Place a visible charge and later choose when to detonate it: a trap with player agency, not another automatic strike. Opponents spot/disarm/shoot it or stay outside its warning area.
`PW.Throw` is a timed projectile helper, not remote detonation. Add a validated second-action/inventory interaction, device lifecycle and damage provenance; each actual explosion must enter `StreakDamage`, not just placement. E1/E3 support damage mutation/blast attribution, not our score semantics.
Bots need a plant/detonate behavior driven by contacts/LOS or a disclosed sensor trigger, never a hidden exact-position test. Reusing `BotShouldUse` alone cannot express a second action.
Cost: one object, one bounded trigger action, stock explosion; low idle network load. Legal floor placement works indoors but wall shielding needs smoke tests. Navmesh only for planting goals; CUAV does not jam a physical trigger unless a later electronic rule is approved.

### K8 — Mortar suppression zone

**P:** Warn an area, then deliver spaced impacts that force movement; the meaningful difference from the shipped line airstrike is sustained area denial with readable escape opportunities, not a renamed explosion pattern.
Reuse pure point generation and instance timers from `airstrike.lua`, but add safe target validation, a shared warning-zone representation, sky/roof policy and per-impact provenance. E3 confirms blast LOS checks; it does not prove roofs behave as desired.
Bots choose known/remembered enemy or objective positions and need a hazard-avoidance/navigation-cost contract for counterplay. Do not turn a warning into precise enemy knowledge. Humans need an accessible Lua HUD/world warning, not only an audio cue.
Cost: scheduled traces/explosions and recipient-scoped warning updates; avoid persistent smoke/particles. Outdoors first; reject or clearly refuse roofed targets before spend. Requires navmesh for bot escape, not impact geometry; P2P clients must receive warnings before damage. CUAV blocks radar, not shells.

### K9 — Local electronics disruption

**P:** Temporarily disable nearby hostile sensors/sentries/interceptors without hiding ordinary players or replacing Counter-UAV. Physical cover remains useful; spreading devices and leaving the burst area counters it.
No device-disable API exists. After K4/K10, introduce an explicit opt-in device registry with allegiance, LOS and reversible disabled state; no broad `ents.Find*`/class-name guessing and no claim to disable ARC9/TFA/MW weapons.
Bots may activate against a device they perceived; new device contacts/priority are necessary. They should not know every deployed object at creation. A disabled device must recover or end deterministically when the burst instance ends.
Cost: one bounded device query, cheap stock pulse, sparse disable/restore deltas. Indoor/floor LOS policy matters; no navmesh for the burst. CUAV has no automatic interaction; keep the two effects distinct.

## Expensive options and honest deferrals

### K10 — Fixed automated sentry

**P:** A stationary, destroyable gun watches a limited arc, turns visibly and acquires with delay. Flanks, cover, explosives and K9 counter it; it must not inherit an omniscient player list as target lock.
Add device targeting/LOS, turn/acquisition rules, shot provenance and trace scheduling. `PW.Streaks.StreakDamage` wraps every shot's damage; `match_rules:weaponOf` still needs a no-held-gun-XP path. No existing turret API or reusable non-player bot controller was found.
Bots can place it near a recognized defend lane but need device counterplay as targets; player bots remain virtual-gamepad actors (`07-bots.md` d.2), while the sentry is a separate explicitly limited weapon entity.
Cost: bounded periodic scans/traces, turn/fire deltas and stock/original model/sounds. Avoid physics ragdolls and continuous muzzle particles. Indoor placement is feasible only with clearance and obstruction tests; navmesh for bot approach/flanking, not sentry aiming. CUAV must not affect optical LOS unless explicitly chosen.

### K11 — Remote-operated gun

**P:** The owner trades mobility/awareness for manual control of a fixed gun; the exposed body and gun remain destroyable. Unlike K10, the reward is control, not automatic kills.
Requires camera/input arbitration with the existing single camera owner (`DESIGN.md`), validated aim/fire commands, exit/death/disconnect restoration and damage provenance. `PW.Streaks.Use` and the current key message do not implement this mode.
Bots require a distinct operate/exit behavior using legal perceived targets; there is no ready-made bot remote-control path. Do not silently replace manual control with omniscient automation for bots.
Cost: continuous input and aim replication plus a second view; assets likely need original work. Indoor wall/camera clipping and P2P latency make it a poor first batch. No flight/navmesh dependency for the gun; navmesh for bot access. CUAV is not a blanket input jammer.

### K12 — Player-controlled recon drone

**P:** A vulnerable flying camera lets its operator scout/mark what its camera can actually see. No damage and no automatic through-wall tracking; losing body awareness and shooting down the drone provide counterplay.
Requires controlled movement/collision, camera ownership, server-authorized camera LOS and a public reveal-origin contract. Existing `PW.Reveal` takes current target positions, not arbitrary camera snapshots. CUAV must still filter marks, not be bypassed by a custom wire.
Bots need a bounded scout task and flight pathing; ground navmesh does not describe air clearance. Current player-bot navigation is not an aircraft controller. An unattended decorative model supplies none of this gameplay.
Cost: moving entity, continuous control/camera rendering and networking, original readable assets. Ceilings, skyboxes and small interiors are severe constraints; opt-in prototype only after ground options. P2P input delay and host/client view consistency need dedicated checkpoints.

### K13 — Autonomous escort aircraft

**P:** A helicopter-like escort could visibly patrol, acquire LOS targets and be destroyed. It is plausible GLua work, not a cheap use of existing streaks, and is explicitly post-MVP (`05-loadout.md` d.10).
Needs flight corridors/collision, target acquisition, anti-air counterplay, damage attribution, asset/sound work and caps. Ground navmesh, `BotShouldUse` and a stock flying model do not supply those systems; generic stock NPC behavior is not evidence of fair Private War integration.
Bots could activate it using the ordinary inventory path, but its autonomous controller and bot responses still need new contracts. No secretly upgraded bot targeting; consider outdoor-map eligibility before inventory consumption.
Cost: potentially high server traces, client effects/audio and movement replication; incompatible indoor maps need exclusion. CUAV interaction with sensors versus optical fire is undecided. Defer until measured headroom and a specific gameplay need justify it.

## Recommended first sequence

1. **K1 snapshot scan:** smallest new gameplay loop; validate safe human/bot disclosure and Counter-UAV without world entities.
2. **K2 ammunition cache:** establish transactional placement, owned deployables and capped ordinary-ammo resupply. Do not replenish grenades through raw SWEP ammo.
3. **K3 medical station:** reuse placement/lifecycle, add overlap/combat eligibility; verify that it helps objectives rather than indefinite camping.
4. **K4 ground sensor:** add destructibility, safe radar pulses and perceived device counterplay; then reuse this foundation rather than duplicating it.
5. **K10 sentry, conditional prototype:** only after damage provenance, bounded targeting and bot counterplay are solved. If these gates fail, stop at four; do not substitute an aircraft.

These are recommendations for discussion, not scheduled tasks. Every accepted feature includes class description, ready/invalid-placement feedback, ownership/expiry cues and bot-facing rules through the Lua UI and public contracts.

## Regression ideas and manual checkpoints

- **Pure first:** extend `lua/tests/privatewar/streaks.lua` patterns for cone/LOS eligibility, team/FFA isolation, jam expiry, placement validity and deterministic support overlap/caps. Keep engine traces in thin wrappers and client rules in `sh_` files.
- **Earning:** kills versus score, crossed thresholds once, death reset, retained unused rewards, persist, inventory cap, and `chain=false/true`; add delayed-impact cases so activation scope cannot falsely pass the no-chain test.
- **Attribution:** grenade inflictors stay grenades; sentry/charge/mortar kills credit their owner and player XP but not the gun currently held. Test weapon switching, dead owner, disconnected owner, world fallback and score/medal callbacks after the damage scope.
- **Lifecycle:** expiry, owner death/respawn/disconnect/team change, object destruction, module/content disable, round/match end and map cleanup. Assert hooks/timers/entities/disabled effects are gone; `PW.Instance` alone is not the entity cleanup assertion.
- **Bot smoke:** a legal class earns/uses a reward, supports an ally, avoids an announced strike and attacks a perceived device. Compare with an identical hidden enemy: no earlier eligibility or pre-aim. Existing `streaks.lua`, `bots_loadouts.lua` and `equipment.lua` tests are starting points, not proof for new behavior.
- **Manual barrier before rollout:** host plus one P2P friend; solo-with-bots listen server (`maxplayers > 1`); FFA/team modes; indoor/outdoor/multilevel maps, doors, sky and missing navmesh. Verify placement cancellation, controller hints, CUAV, readable warnings, late join and phase transitions.
- **Measure later, not now:** record baseline then each feature with equal bot/map conditions; inspect profiler timings, scheduled trace/entity counts, client frame pacing and network bursts. Exercise simultaneous instances and host pause/resume/end-session; agree limits only from those results. No performance figures are claimed here.

## Consequential choices still open

- Approve support benefit/receipt rules, station overlap and support score awards. New support events could feed score-mode streaks unless their provenance is deliberately handled; no automatic farming/chaining loop.
- Decide deployment failure/refund, team switch and owner-disconnect semantics; do not assume an active reward dies with its owner's life.
- Decide sensor wall/floor policy, device perception/counterplay, and whether electronic disruption affects control links at all. Preserve Counter-UAV's existing reveal filtering unless a separate design change is approved.
- Choose whether a fifth lethal candidate is worth the provenance and bot work. No unlock levels, kill/score prices or map-wide entity limits are fixed by this research.

## Accessed primary sources

Accessed 2026-11-07; these verify engine primitives, not feasibility or performance of an entire feature.

- **E1:** <https://wiki.facepunch.com/gmod/GM:EntityTakeDamage> — mutate existing damage; returning true blocks it; recursively damaging the same victim is unsafe.
- **E2:** <https://wiki.facepunch.com/gmod/util.TraceHull> — axis-aligned hull sweep/occupancy, no hitbox test; server tracing preferred for authoritative placement.
- **E3:** <https://wiki.facepunch.com/gmod/util.BlastDamage> — distinct inflictor/attacker, blast damage and LOS checking. No assumed penetration/falloff formula or reliance on a newly added optional parameter.
- **E4:** <https://wiki.facepunch.com/gmod/Entity:SetNW2Float> — changes replicate subject to PVS; unchanged values do not resend; documented warning about Lua entities. Use explicit scoped messages where required, not NW2 as a secret-position transport.
