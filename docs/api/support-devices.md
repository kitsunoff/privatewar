# Support streaks and owned devices

Status: frozen implementation contract for the approved K1–K4 slice (2026-11-08).
This contract is tests-first; it does not claim the runtime or its in-game checks exist yet.
Existing [streaks](streaks.md), [role policy](role-policy.md) and [bots](bots-blackboard.md)
contracts remain authoritative outside the additions below. No aircraft or lethal content is included.

## Content and balance

All four entries have `Unlock = 1`; streak slots remain outside Pick X.

| Id | Name | Kills / score | Lifetime | Rules |
| --- | --- | --- | --- | --- |
| `directional_scan` | Directional Scan | 2 / 200 | One snapshot | Owner-facing cone, **90 degrees total**, range 1800, current LOS; reveal 1.5 s |
| `ammo_cache` | Ammunition Cache | 4 / 400 | 45 s | Radius 160, LOS, automatic allied receipt; one ordinary magazine per ammo type, recipient cooldown 5 s, 10 receipts, reserve cap 3 magazines |
| `medical_station` | Medical Station | 5 / 500 | 30 s | Radius 180, LOS, 5 HP/s after 5 s without damage; overlapping stations use maximum rate, not sum |
| `ground_sensor` | Ground Sensor | 4 / 400 | 30 s | Radius 600, vertical difference at most 128, current LOS, pulse every 2 s, blip 2.1 s |

Scans and sensors use `PW.Streaks.Viewer` and `PW.Reveal(viewer, targets, seconds, owner)`.
The shared reveal owner applies Counter-UAV and every target-concealment policy before **both**
human packets and bot stimuli. Support content never implements an alternate position wire.
Scan feedback is always generic (`SCAN ACTIVATED`); neither hidden nor empty results disclose counts.
Sensor expiry/destruction removes its outstanding source-owned blips as well as stopping pulses.

Physical devices have 100 HP and visible, valid stock models, with collision matching the visible footprint.
They have a readable owner/kind/remaining-time marker. No foreign assets are copied.
They cannot be friendly-damaged by default; hostile player damage uses `PW.IsEnemy(attacker, owner)`.
World damage may destroy them. Destruction, supply and healing award no score, XP or money.
FFA supply/healing is owner-only, not merely `not PW.IsEnemy` with an absent teams module.

## Transactional activation

`STREAK:Prepare(owner) -> table?` is optional. Without it, existing streak activation is unchanged.
For a definition with `Prepare`, nil/false or an error refuses activation without removing inventory.
The returned table is server-only and becomes `instance.Activation` **before** `OnEquip` runs.
No client-provided placement or target list is accepted. A per-owner activation guard rejects recursive use.
If `OnEquip` fails or removes its instance (for example entity creation fails), inventory remains unchanged;
all partial owned resources are removed. A valid accepted instance consumes exactly one inventory entry.

The device content's `Prepare` calls `PW.Devices.Prepare(owner, kind)` and `OnEquip` calls
`PW.Devices.Create(instance, kind, instance.Activation)`. Both reject stale/invalid placement and cap races.
Creation failure ends the instance. Only successful activation publishes inventory changes.

Preparation validates finite origin/aim/floor vectors, local deployment distance, current line to the floor,
world-supported floor, slope at most 20 degrees, full device hull clearance and a player-sized surrounding
exit footprint. Floors/footprint corners must support the device; sky, water, moving props, blocked exits,
cliffs, nonfinite traces and an occupied footprint refuse. The owner is excluded from traces, not other players.
At most one active device per owner per kind; at most eight devices globally. Limits are checked before spending.
No replacement silently destroys an existing device. Bots use the same authoritative preparation.

## Device owner

New module `modules/support_devices/`, types `types/support_devices.lua`, namespace `PW.Devices`.
The registry is bounded to eight live records; it is **not** an omniscient bot contact list.

| Function | Contract |
| --- | --- |
| `Prepare(owner, kind) -> placement?, reason?` | Server-only local floor/hull/exit validation and capacity check; no allocation or inventory change |
| `Create(instance, kind, placement) -> record?` | Revalidate, create the stock entity, register it with absolute expiry and owner allegiance; nil on failure |
| `Remove(record)` | Idempotently remove its entity, registry entry, source effects and owning activation |
| `List() -> record[]` | Server-only bounded live registry, read-only; discovery callers must independently validate range/FOV/LOS |
| `RemoveOwner(owner)` | Remove only that owner's active devices; never unused inventory |
| `Clear()` | Remove all devices, preserving unused streak inventory |

Each record contains `owner`, `kind`, `entity`, `position`, `team`, `ends`, `instance` and server-only receipt state.
The registry owns cleanup; the instance's `OnUnequip` calls back into idempotent removal.
Expiry is absolute `CurTime`, never extended by a delayed timer or owner respawn.
Owner death does not remove devices while allegiance is unchanged. Owner disconnect, team change,
role prohibition, module/content disable, round preparing, match end, map cleanup and shutdown remove them.
Cleanup must still run when the owning module becomes invalid; a validity-aware maintenance wrapper owns
that check rather than relying solely on a disabled module's subscribed hooks.
Relationship and ordinary-round cleanup never call global inventory reset.

Pure predicates live in `modules/streaks/sh_deployment.lua` (`PW.SupportStreaks`):
`Placement(facts) -> accepted, reason?`, `Capacity(records, owner, kind) -> boolean`,
`ScanEligible(origin, direction, target, visible)`, `SensorEligible(origin, target, visible)`,
`SupportEligible(facts)` (owner, recipient, teams, allied, alive, allowed, distance, radius, visible),
`ReceiptReady(charges, last, now)`, `HealAmount(health, maximum, lastDamage, now, dt, rates)` and
`ScanDirection(origin, facing, contacts, publicPoint?) -> Vector`.
`EndReason(facts) -> string?` checks absolute expiry, owner validity, unchanged team, content/module enable
and role allowance without looking at owner life/health. `DamageAllowed(hostilePlayer, world)` rejects
friendly/unknown attackers and accepts hostile players or world damage. Lifecycle event cleanup still removes
actual resources; these predicates are not a replacement for round/match/map/shutdown hooks.
`Placement` reads trace facts, never performs engine traces. `Capacity` reads only active records.
`HealAmount` reduces rates by maximum and clamps to missing health; nonfinite/negative input yields zero.
Elapsed healing steps are capped to one second; placement is at most 192 units from the owner's eye origin.
Receipt state advances only when the ammo service actually adds ordinary reserve; an empty/full recipient
does not consume a charge or begin its cooldown. Ten receipts are global to one cache, not per recipient.

## Ammunition dependency

The perks lane owns the capped ordinary-reserve API and adapter documentation.
The cache consumer requests **one magazine, maximum three reserve magazines**, once per eligible receipt.
That service owns ordinary weapon classification, magazine size, shared-ammo deduplication and reserve clamping.
It must not call spawn-time `Give`, modify clips, or supply grenade/launcher/equipment ammo.
The exact committed API must be integrated before writing the cache consumer; this document deliberately
does not name a missing ammo method as implemented. Tests here do not substitute a fake successful cache
consumer for the required real-service integration.

## Healing eligibility

Dead recipients and recipients for whom `PW_CanUseLoadoutKind(ply, "streaks")` is exactly false cannot receive
station healing or cache supply. This keeps optional infected-role restrictions generic, without mode-id tests.
Damage timestamps are recorded by the support owner for humans and bots equally. Positive damage interrupts
eligibility immediately; healing resumes at equality with the five-second deadline. Maximum health is read live.
One arbitration pass applies the maximum eligible station rate per recipient, never one heal per station.
Hitches cannot backfill healing through an unobserved combat interval; elapsed healing steps are bounded.

## Bot device perception and counterplay

New module `modules/bots_devices/` owns `PW.BotDevices` and its own bounded per-bot device contacts.
New behavior `bot_behaviors/attack_device.lua` is its only combat consumer.
No existing player contacts, aim overrides, commander orders or private stores are written.

`PW.BotDevices.Contact(bot) -> contact?` exposes only a hostile device legally recognized through that bot's
FOV, range and current LOS after its normal reaction delay. The module inspects at most one registry candidate
per bot per scheduled pass; it never uses `ents.Find*`. A candidate outside sight produces no contact.
`Perceivable(eye, facing, point, range, fov, visible)` is the shared pure geometry predicate.
`Recognized(firstSeen, now, delay, visible)` gates recognition and resets acquisition on lost sight.
`AttackWanted(playerThreat, deviceVisible)` is false whenever a recognized player fight has priority.

The behavior keeps player combat/survival priority. On loss of current device LOS it stops firing, not chasing
hidden coordinates. It uses the existing pure spring/settle/fire controller (`PW.BotAim`) over a legally perceived
point, writes ordinary `ctx:Intent()` view/buttons and lets the existing `bots_input` writer issue `CUserCmd`.
It never uses the dev/test aim override, direct damage, `SetPos`, fabricated radar stimuli or a foreign board store.
The behavior owns its attack bit only while running and releases it on end/suspend/death/invalidation.
The required engine smoke must observe native weapon fire destroying a genuinely perceived device;
a pure intent assertion, scripted test override or direct damage is not proof of that smoke.

Scan direction uses only recognized contacts' stored positions, a known public objective/lane or current facing.
No nearest-unseen-enemy query is allowed. Device placement is local from current facing/cover/public objective;
this slice implements nearby automatic receipt, not deliberate visits or teleportation.

## Verification status

Keep all mandatory T-4.6, T-6.6 and T-5.7 cases unchanged. New tests are in
`streak_deployment.lua`, `streak_directional_scan.lua`, `streak_ammo_cache.lua`,
`streak_medical_station.lua`, `streak_ground_sensor.lua` and `bots_support_devices.lua` under
`lua/tests/privatewar/`. Pure cases supplement, not replace, engine placement, cleanup, input-combat
and client-visible marker/feedback cases. No passes, performance numbers or screenshots are claimed here.
Human/P2P, controller, multilevel/indoor, optional-adapter and late-join checks remain manual until observed.
