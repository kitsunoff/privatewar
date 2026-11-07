# Perk candidates

Research, 2026-11-07, against `main` at `2d71b09`. **Exploratory recommendations, not approved requirements.**
No implementation, design changes, game sessions or measurements accompany this note. Killstreaks are considered separately in [21-killstreak-candidates.md](21-killstreak-candidates.md).

## Scope and evidence

Prioritize distinct play styles for casual solo/friends versus convincing player bots on a Steam P2P listen server, with Steam Deck performance first.
Keep perks modular, client feedback in the Lua-only in-house UI and weapon-base integrations behind public adapters. No copied third-party code/assets, licensed presentation or new backend is needed.
`design/05-loadout.md` d.4 fixes groups; d.8 fixes cached stats and owner instances; d.11 fixes grenade inventory/cooking. Research is subordinate to those decisions.
Group assignments, Pick X costs, unlocks and numeric strengths are deliberately **not decided** here; similar benefits should compete within groups rather than quietly stack through new slots.

Evidence labels: **R** = verified repository behavior; **E** = accessed primary source; **P** = reasoned proposal; **G** = needs in-game proof.
`R/` below means `addons/privatewar/lua/privatewar/`; `A/` means `addons/privatewar-arc9/lua/privatewar/`; `G/` means `addons/privatewar/gamemodes/privatewar/gamemode/` (not an evidence label).
Paths and symbols/line numbers refer to the stated revision. Costs are qualitative, **unmeasured** estimates, not benchmark results.

## Shipped baseline: four perks, not four new suggestions

| Existing perk | Actual effect | Implementation |
| --- | --- | --- |
| Ready Up | Shorter sprint-to-fire, where supported | `R/perks/ready_up.lua:6`, `Stats.sprint_to_fire` |
| Sleight of Hand | Faster reload, where supported | `R/perks/sleight_of_hand.lua:6`, `Stats.reload_time` |
| Flak Jacket | Scales explosive damage to the owner | `R/perks/flak_jacket.lua:10-13`, instance `EntityTakeDamage` hook |
| Adrenaline | Kill-triggered capped personal healing timer | `R/perks/adrenaline.lua:11-15`, `OnKill` |

- **R:** `R/kinds/perks.lua`, `R/types/perks.lua` and [Perks API](../docs/api/perks.md) define `Group`, `Stats`, owner-local events and `OnEquip/OnUnequip`. They do not apply arbitrary stat names automatically.
- **R:** `R/modules/perks/shared.lua:_Multiply/PW.Stat` caches positive finite multipliers. `init.lua:Refresh/_Recompute` combines perks, registered stat sources and mode stats, forwarding only weapon keys. Recompute follows `PW_LoadoutGiven`; a class edit applies at the next spawn.
- **R:** `R/modules/loadout/init.lua:86-91` also recomputes after wildcard equip to cover listener ordering. Do not promise exactly one computation per spawn; the important property is event-driven caching, not per-frame aggregation.
- **R:** `PW.Stat` has no player movement/health/fall/damage consumer in this tree. `move_speed`, `fall_damage` or `damage_taken` in `Stats` alone therefore do nothing visible, despite the intended design examples. This is a feasibility gap, not permission to change `design/`.
- **R:** `shared.lua:_Targets`, used by the server dispatcher, selects only the relevant owner's `OnKill/OnDeath/OnDamaged/OnDealDamage`; post-damage events cannot prevent an already applied hit. Enemy/team checks still belong in a perk's eligibility rule: owner-local does not mean enemy-only.
- **R:** Perk instances/cache end on death, disconnect, new loadout and match end (`init.lua:_Clear`, `PostPlayerDeath`, `PW_MatchEnd`). `G/core/sh_instance.lua:Remove` clears hooks/timers, not arbitrary external state. There is no blanket proof that toggling the perks module/content off resets already-equipped stats/side effects; require explicit lifecycle tests and, if needed, a public disable-cleanup contract.

## Adapter and grenade constraints

- **R:** The six weapon keys are `reload_time`, `draw_time`, `ads_time`, `sprint_to_fire`, `recoil`, `spread` ([Adapter API](../docs/api/adapter.md), "Stat modifiers"). `PW.SetStatMods` is a composed output: an individual perk must not overwrite another perk's multipliers by calling it with a partial table.
- **R:** ARC9 is the installed repository integration. `A/modules/arc9/shared.lua:34-41` maps all six keys; `A/weapon_adapters/arc9/shared.lua:316-351` installs per-instance hooks and invalidates caches. Public upstream processing is verified in E6. Exact prediction/pack behavior remains **G**.
- **R:** `R/weapon_adapters/sweps.lua` has no stat-mod override; the fallback supports none. TFA and MW Base are planned but absent under `addons/`; `TASKS.md` "Blocked on the user" says their bases are not installed. Their perks are **blocked on installing suitable bases/packs and implementing/testing adapters**, not compatible by assertion. TFA sprint-to-fire, magazine size and RPM are outside the current contract.
- **R:** `R/modules/weapons_statmods/shared.lua:_Tick/tickPlayer` already performs a revision-driven refresh; the server skips unchanged swept revisions unless a weapon was equipped. Reuse this path; do not add a new per-tick scan for every stat perk.
- **R:** Grenade counts are equipment state mirrored to SWEP ammo, not ordinary reserve. `PW_EquipmentCount(ply, slot, itemId, count)` is asked once per life after perk/wildcard equip; first answer wins ([Equipment API](../docs/api/equipment.md), `R/modules/equipment/sh_grenades.lua:_CountFor`). It is not a mid-life refill service or an additive modifier chain.
- **R:** Humans release the held grenade SWEP to throw; only frag cooks. Holstering cancels without spend; death while cooking drops the live frag; bots use `PW.Equipment.Use` without cooking. Preserve fuse, attacker, grenade-weapon XP, last-grenade return and slot ammo synchronization (`05-loadout.md` d.11; `R/modules/equipment/sv_grenades.lua`).

## Compact feasibility matrix

All rows are **new proposals**. Model: S = cached stat, O = owner-local event/hook, W = world/team integration.
Cost order: server / client / network / additional assets. L = low, M = moderate; none means no new assets. Even low-cost hooks need profiling at realistic bot counts.

| Id | Candidate | Model / effort | Existing entry point; missing piece | Estimated cost S/C/N/A |
| --- | --- | --- | --- | --- |
| P1 | Extra equipment allowance | O / easy | `PW_EquipmentCount`; conflict policy | L/L/L/none |
| P2 | Faster weapon handling | S / easy, ARC9 | `draw_time`; no new stat contract | L/L/L/none |
| P3 | Faster sight acquisition | S / easy, ARC9 | `ads_time`; no new stat contract | L/L/L/none |
| P4 | Recoil discipline | S / easy, ARC9 | `recoil`; bot aim interaction proof | L/L/L/none |
| P5 | Kill-based scavenging | O / easy–medium | `OnKill`; capped ordinary-ammo service | L/L/L/none |
| P6 | Controlled landing | O / easy–medium | `GetFallDamage`; baseline damage ownership | L/L/L/none |
| P7 | Quiet movement | O+W / medium | Footstep hook; shared hearing filter | L/L/L/none |
| P8 | Radar concealment | W / medium | `PW.Reveal`; per-target eligibility contract | L/L/L/none |
| P9 | Flash resilience | O+W / medium | `Blind`; pre-application strength contract | L/L/L/none |
| P10 | Retaliation marker | O+W / medium | `OnDamaged`, `PW.Reveal`; safe target policy | L/L/L/none |
| P11 | Streak continuity | O / medium, balance risk | `PW_StreaksPersist`; death-order snapshot | L/L/L/none |
| P12 | Movement specialization | S+W / expensive/defer | `PW.Stat`; shared movement consumer | L/M/L/none |

## Easy or relatively small candidates

### P1 — Extra equipment allowance

**P:** Start a life with extra lethal or tactical uses. This creates a resource-oriented class, not quicker grenade throws or stronger blasts; opponents retain cover, distance and ordinary grenade counterplay.
Use an owner-filtered instance `PW_EquipmentCount` hook from `OnEquip`; no new stat name or SWEP patch. Decide which slot(s) qualify. Multiple perks/wildcards answering the same question are not composable today: approve mutual exclusion or a future deterministic count-composition contract.
Bots receive the same allowance through ordinary class application and `PW.Equipment.Use`; current `throw_equipment` only chooses lethal, so more tactical ammo does not establish tactical bot usage.
Cost: one spawn-time question, existing ammo/count HUD deltas, no new models/hot loop. Indoors extra frags amplify spam; balance by Pick X/group tradeoff, not secret bot restrictions. No map/navmesh dependency beyond existing throw navigation; P2P uses the existing authoritative spend path.

### P2 — Faster weapon handling

**P:** Shorter weapon draw/holster time makes switching to a sidearm more viable; it is different from Ready Up's sprint exit and Sleight of Hand's reload. Positioning, reload windows and weapon choice still matter.
Use `PERK.Stats.draw_time` through cached composition; ARC9 maps it to `DeployTime` (`A/modules/arc9/shared.lua:36`). Do not claim every base's holster animation changes merely because the generic key says draw/holster; verify the actual ARC9 pack.
Bots benefit only when they switch through existing inputs. Check whether tactic timing still waits longer than the new draw time; do not accelerate reaction or bypass `CanFireNow`.
Cost: existing stat revision replication/cache refresh only, no assets or bespoke client HUD. No world searches, navmesh or indoor restrictions. In P2P test remote animation/fire agreement and grenade selection/return; grenade SWEPs do not inherit ARC9 support.

### P3 — Faster sight acquisition

**P:** Reduce ADS transition time for deliberate aiming after movement; do not change focus error, turn rate, FOV or knowledge. Cover and forcing a reload still counter it; its balance cost is another perk in the same group. This is neither sprint-to-fire nor reload speed under another name.
Use `PERK.Stats.ads_time`; ARC9 maps `AimDownSightsTime` (`A/modules/arc9/shared.lua:37`), E6 verifies the stat pipeline. HL2 fallback has no equivalent effect; communicate unsupported bases in the class UI rather than show a false universal benefit.
Bots already aim through legal inputs; verify they cannot fire accurately before sight/fire gates allow it. Their human-like aim error must not be reset by this perk.
Cost: shared existing modifier path, sparse revision state, no new assets. Indoor/outdoor independent, no navmesh dependency. P2P prediction and actual ADS timing need manual proof per supported pack.

### P4 — Recoil discipline

**P:** Reduce weapon recoil for controlled sustained fire; unlike an accuracy cheat it must alter the same weapon property for humans and bots, without changing their difficulty parameters or granting perfect tracking.
Use `PERK.Stats.recoil` and ARC9's `Recoil` hook (`A/modules/arc9/shared.lua:39`, `SupportedStatMods`). No new API is needed for the base value, but pack-specific component behavior is **G**; do not assert reduced aim punch, camera shake or every recoil subcomponent.
`R/modules/bots_aim/init.lua` reads adapter recoil for compensation. Verify that lower weapon recoil plus compensation does not double-improve bot accuracy or destabilize aim; leave recognition/reaction unchanged. Short bursts and cover still counter sustained fire.
Cost: existing modifier/cache path, no scans/assets/new messages. No map/navmesh constraints; remote recoil behavior and client/server prediction need P2P checks. Select behind P2/P3 if this aim interaction remains uncertain.

### P5 — Kill-based scavenging

**P:** A qualifying enemy weapon kill restores a capped amount of ordinary reserve. It supports longer lives without Adrenaline's healing or unbounded grenades; no restoration on suicide, team kill or autonomous-streak kill. Denying kills and pressuring the owner before a refill counters it; reserves still have a ceiling.
`PERK:OnKill(owner, victim, dmg)` supplies the event, not ammunition mutation rules. Use adapter `GetAmmoType/GetClip` to identify valid weapon/ammo; add an explicit capped reserve helper, shared-ammo deduplication and kill-source eligibility. Do not call spawn-only `PW.WeaponAmmo.Give` to refill an existing gun.
Bots automatically benefit through the same event; no new pathfinding behavior is needed for this event-only version. Physical scavenger pickups would be a separate higher-cost choice requiring entity cleanup and bot collection goals.
Cost: one eligible kill calculation, existing reserve replication, no assets. No map/navmesh dependency; P2P authoritative kills only. Exclude grenade ammo and delayed/explosive non-weapon sources until provenance is reliable: `R/modules/match_rules/init.lua:weaponOf` otherwise falls back to the held gun.

### P6 — Controlled landing

**P:** Reduce fall damage without changing falling speed, physics or bot jump skill. The tradeoff is a specialized safety perk versus generally useful combat perks; it does not make cliffs valid navigation routes.
E5 verifies server `GM:GetFallDamage` can return a numeric damage override. No current `fall_damage` consumer exists: introduce a public baseline fall-damage application point, apply the cached multiplier once and preserve the gamemode/map's normal result. A perk returning its own arbitrary formula would risk replacing unrelated rules.
Bots receive the same damage reduction, but current navigation does not plan perk-specific drops. Leave routing unchanged initially; investigate only if an explicit perk-aware traversal contract is later approved.
Cost: landing-event work only, ordinary health replication, no assets. Multilevel maps matter; flat maps make it weak. Client landing sound/view feedback and other fall-damage addons require proof, not promises; no additional network state or P2P input loop.

## Medium candidates requiring public integration points

### P7 — Quiet movement

**P:** Reduce or suppress movement sound without invisibility. Sight, gunfire and physical collision still reveal the owner; it must affect enemy humans and bot hearing consistently.
E2 verifies `PlayerFootstep` can mute stock footsteps, but it is predicted and runs on both realms in multiplayer. Perk instances are server-side today: add replicated active eligibility and realm-correct sound behavior, not a client-only cosmetic mute.
`R/modules/bots_perception/init.lua:241-245` independently broadcasts sprint footsteps. Relying on hook order/early return can suppress some listeners and not others: add an explicit shared footstep/hearing eligibility contract. Do not write bot memory directly or erase existing legitimate contacts.
Cost: event-only eligibility, cached per-player state and sparse changes, no assets. Tight interiors amplify value; no navmesh dependency. P2P host, remote observer and bot listener must agree. Weapon-base custom movement sounds need opt-in evidence; stock-hook coverage is not universal compatibility.

### P8 — Radar concealment

**P:** Hide the owner from deliberate radar detection, optionally only under a later-approved movement condition. Visual spotting, sound, damage direction and existing memories remain; this is a personal perk, not team-wide Counter-UAV.
`R/modules/streaks/sv_reveal.lua:PW.Reveal` filters team jamming but has no per-target perk eligibility question. Add a documented filter before both human packets and bot stimuli, with a reveal-source descriptor if different sensors must differ. Never filter only the client HUD.
Bots with the perk are concealed by the same rule; enemy bots retain sight/hearing and may search their last known point. Do not delete contacts simply because a UAV pulse now omits a target.
Cost: a bounded check on existing reveal cadence, no extra enemy-position stream/assets. CUAV remains an independent team filter; no bypass by a future ground sensor. No navmesh/indoor restriction except the chosen sensor rules; stale blip expiry and P2P recipient safety require tests.

### P9 — Flash resilience

**P:** Reduce flash strength/duration without removing all tactical counterplay. It must reduce both the human screen/audio response and the corresponding bot impairment, not just the visible white overlay.
`R/modules/throwables/init.lua:Blind` computes duration, sends `pw_blind`, sets DSP and only then notifies `PW_Blinded`. That notification is **not** a veto or modifier. Add a pre-application owner-local strength contract and one authoritative duration mapping; do not wrap `Blind` or patch another module.
[Equipment API](../docs/api/equipment.md), "PW_Blinded", and the perception implementation show no bot blind-response consumer yet. Bot use therefore requires implementing ordinary flash impairment first; a perk alone cannot meaningfully resist an effect bots do not suffer.
Cost: one flash-event calculation and existing small message, no assets. Flash LOS/angle still applies in rooms/multilevel maps; no navmesh dependency. Check DSP cleanup, stacked flashes and P2P latency; source damage hooks cannot replace a non-damaging flash contract.

### P10 — Retaliation marker

**P:** Taking qualifying enemy damage briefly marks the attacker for the owner/team, trading an exposed perk slot for information. This is an intentional new reveal, not a reason to network every attacker's hidden position continuously.
Use owner `OnDamaged` then `PW.Reveal(PW.Streaks.Viewer(owner), targets, duration)`; team recipients and CUAV already exist. Add pure eligibility: enemy, living valid attacker, allowed damage provenance, cooldown and preferably current LOS. No read of unseen exact positions to choose a target other than the explicit damage source.
Bots receive the same radar stimulus; existing damage awareness is only directional (`R/modules/bots_perception/shared.lua:DamageStimulus`), so this proposal adds genuine team information. Do not silently reinterpret all damage as exact wallhack knowledge.
Cost: bounded event-time LOS check plus existing scoped radar message, no assets. Cover and CUAV counter it; indoors use LOS to avoid free cross-floor reveals. Navmesh irrelevant. Consent to precise versus direction-only intelligence is consequential: direction-only human UI needs a new contract instead of `PW.Reveal`.

### P11 — Streak continuity

**P:** Keep the owner's earned-progress counter through death, without extra damage, cheaper thresholds or default streak chaining. It offers an accessible support-oriented build but may dominate long casual matches.
`PW_StreaksPersist(ply)` is already asked by `R/modules/streaks/init.lua:_OnDeath`; `PERK:OnEquip` can register an owner-filtered question hook. However both perk removal and streak reset listen to `PostPlayerDeath`: do not assume the persistence hook survives until queried. A documented pre-cleanup owner snapshot/order contract is needed.
Bots use the same continuity and ordinary `BotShouldUse` path. Progress does not loop after the last threshold (`streaks/shared.lua:_Crossed`); retaining progress is not unlimited repeated rewards and must not be presented as such.
Cost: death-event state only, existing HUD/NW2 inventory path, no assets/map/navmesh restrictions. CUAV affects resulting reveals normally, not earning. Avoid inventing score penalties or alternate prices; approve the balance and death ordering before implementation.

## Expensive or defer

### P12 — Movement specialization

**P:** A mobility-oriented class could improve ordinary movement while giving up another perk; it is not extra bot speed, teleportation or reduced reaction time. Humans and bots must use the same movement rules.
`PW.Stat(owner, "move_speed", base)` can compute a value, but no consumer applies it and client `PW.Stat` has no server cache. A new shared/predicted movement owner and replicated resolved values are needed; do not independently overwrite base/weapon movement every tick.
Coordinate sprint, crouch, weapon speed penalties, existing bot movement and optional Quick Slide public integration (`design/07-bots.md` d.13). No verified universal sprint-stamina, ADS-strafe or slide-cooldown adapter key exists. Treat these variants as blocked pending public-API evidence, not compatible extras.
Cost: arithmetic may be small but client prediction/integration risk is materially higher; use spawn/loadout recompute, no scans or assets. Navmesh jump/drop assumptions, stairs, doors and indoor collision need proof. P2P movement corrections and camera feel are acceptance barriers; defer until a single movement contract is agreed.

## Recommended first sequence

1. **P1 equipment allowance:** gives an immediate non-weapon-base class distinction; settle first-answer conflicts, then test cooking/count/return invariants.
2. **P2 handling:** exercise an existing ARC9 stat path; show unsupported-base feedback instead of promising a universal effect.
3. **P3 sight acquisition:** another distinct input transition through the same safe modifier composition; verify prediction before further weapon-stat content.
4. **P5 scavenging:** create capped ordinary-ammo supply once, shared with a future ammunition cache; wait for reliable kill provenance rather than refilling grenades by accident.
5. **P6 controlled landing:** establish a narrow event-time player-stat consumer only after agreeing baseline fall-damage ownership. If baseline integration is unresolved, stop at four instead of silently replacing it with a broader movement system.

P4 is a low-code alternative after bot compensation checks. P7/P8 are attractive stealth choices but need explicit hearing/reveal contracts; P9 is blocked on normal bot flash behavior. These are priorities for discussion, not additions to `TASKS.md`.
Every accepted perk ships class descriptions, clear supported-base/slot limitations and any temporary-effect cues using the existing Lua UI; no separate frontend framework.

## Regression ideas and manual checkpoints

- **Pure/TDD first:** extend `lua/tests/privatewar/perks.lua` patterns for group rejection, wildcard/mode products, positive-finite filtering, owner routing and recompute only on life/loadout events. New eligibility/composition rules belong in `sh_` helpers with thin engine wrappers.
- **Stat lifecycle:** multiply rather than replace, reset to identity on death/loadout removal, no repeated scaling after refresh/pickup, same result across source order; test module/content disable and re-enable, not just normal death. Verify missing optional modules do not break spawn.
- **Ammo:** test enemy versus ally/suicide/streak kill, shared ammo, full reserves and invalid/clipless weapons; grenade SWEPs never gain scavenged ammo. For P1 test both slots, repeated loadout give in one life, wildcard conflicts and next-life reset using `equipment.lua`/`grenades_inventory.lua` coverage.
- **Cooking regression:** holster cancels with no spend, overcook and cooked-death drop preserve fuse/attacker, last grenade returns to the previous weapon, bot `PW.Equipment.Use` uses the authoritative count. A stockpile perk must not rescale live fuses or replenish on each weapon select.
- **Knowledge:** quiet footsteps produce matching human/bot results independent of hook order; radar concealment filters packets and stimuli, not legitimate sight or memory; retaliation has no ally/spam/unapproved hidden-position leak; CUAV still filters every deliberate reveal.
- **Damage/status:** preserve attacker/inflictor and avoid recursive damage (E1); compute fall scaling once; flash resistance precedes screen/DSP/bot effects and cleans up on death/disable. Test persistence under both possible death-listener orders; a lucky hook order is not a contract.
- **Bot smoke:** validate classes through `bots_loadouts.lua`; an equipped perk affects normal inputs/events and ends on death. No improved difficulty parameters, new knowledge or free inventory unavailable to human owners.
- **Manual barrier:** ARC9 supported pack plus HL2 fallback, host and P2P friend, team/FFA, new life/class/round, grenade switching/cooking, remote ADS/draw/recoil, stairs/falls and multilevel interiors. If later installed, TFA/MW packs require their own adapter tests and client prediction checkpoints.
- **Measure later:** compare identical map/bot conditions without and with perks; inspect profiler work per event, existing modifier refresh counts, client frame pacing and network bursts on simultaneous spawns/kills. No game tests or measurements were run for this note.

## Consequential choices still open

- Assign groups and choose conflicting benefits (especially extra equipment versus grenade-oriented wildcards); decide whether unsupported weapon bases make a class unsuitable or merely show a warning.
- Choose scavenging eligibility/caps and whether a no-pickup event version is desirable; accept fall-baseline integration before advertising fall protection.
- Choose stealth scope, radar-source exceptions and retaliation precision. No decision here changes existing Counter-UAV or bot fairness rules.
- Approve persistence balance/death ordering and whether movement complexity is worth implementing. No unlock levels, costs, magnitudes or timings are fixed by this research.

## Accessed primary sources

Accessed 2026-11-07. Engine facts do not establish whole-feature compatibility or measured performance.

- **E1:** <https://wiki.facepunch.com/gmod/GM:EntityTakeDamage> — editable pre-damage event, true cancels damage; recursively damaging the same victim is unsafe. Post-damage observation is a different stage.
- **E2:** <https://wiki.facepunch.com/gmod/GM:PlayerFootstep> — predicted, both realms in multiplayer; returning true mutes normal sound. Does not guarantee all third-party movement sounds or our independent bot hearing are covered.
- **E3:** <https://wiki.facepunch.com/gmod/Entity:SetNW2Float> — PVS-dependent replication, no resend for unchanged values, warning for Lua entities. Replicate only required perk state, never enemy coordinates as a workaround.
- **E4:** <https://wiki.facepunch.com/gmod/util.TraceHull> — server-authoritative clearance tests; a hull is axis-aligned, not a guarantee of perk-aware navigation.
- **E5:** <https://wiki.facepunch.com/gmod/GM:GetFallDamage> — server hook with numeric damage override. This does not prove a particular baseline formula or client landing response.
- **E6:** <https://raw.githubusercontent.com/necoarctic/ARC-9/main/lua/weapons/arc9_base/sh_0_stats.lua> — public `GetProcessedValue`, per-instance stat hook processing and `DoInvalidateCache`; mutable upstream source, not a frozen compatibility promise. The initial historical-owner `sh_stat.lua` URL returned 404 and supplied no evidence.
