---
name: privatewar-perk
description: Implement or change a Private War perk, PERK stat multiplier, owner-only kill/damage effect, equipment-count contribution or perk compatibility description. Use for passive and event-driven perk work, including cleanup and role composition; not for a wildcard's slot rules alone.
---

# Private War perks

Read [shared workflow](../../../docs/agent-workflow.md), [perks API](../../../docs/api/perks.md),
[equipment API](../../../docs/api/equipment.md), [player overrides](../../../docs/api/player-overrides.md) and
[role policy](../../../docs/api/role-policy.md). Decisions: `design/05-loadout.md` d.4, d.8, d.16;
`design/04-weapons.md` d.6; `design/00-core.md` d.11. Existing twelve-perk balance is frozen, not a tuning backlog.

## Ownership

Content: `addons/privatewar/lua/privatewar/perks/<unique_id>.lua`; tests:
`addons/privatewar/lua/tests/privatewar/perk_<topic>.lua`; types:
`addons/privatewar/lua/privatewar/types/perks.lua`. Inspect kind `addons/privatewar/lua/privatewar/kinds/perks.lua`
and owner `addons/privatewar/lua/privatewar/modules/perks/{shared.lua,init.lua,sh_effects.lua,sv_effects.lua}`.
Real examples are `perks/ready_up.lua`, `perks/adrenaline.lua`, `perks/flak_jacket.lua`, `perks/stockpile.lua`
under the content directory's parent. Core instances, ammo, reveal, player overrides, streaks and UI consumers
remain their owners' responsibility; request assignment for new seams rather than writing foreign private stores.

## Workflow

1. Record git/base/current implementation and approved perk effect. Choose data-only stats, convenience event or
   instance hook based on actual consumers, not an invented stat key. Read the nearest implemented perk and tests.
2. Declare content/test/type ownership, supported actors/bases, group/cost/unlock and non-goals. Determine which
   existing owner applies effects and which lifecycle boundaries must revoke them.
3. Use [test map](../../../docs/agent-test-map.md) for verbatim T-4.4 and T-11.17 requirements; add failing new
   declaration/composition/owner/cleanup cases before implementation. Use two owners to detect cross-player leaks.
4. Implement through PERK data or owner-local instance callbacks below, annotate fields, add honest descriptions
   and compatibility UI model tests. Keep pure eligibility/math separate from native mutation.
5. Run `nix develop --command make check`; only with explicit permission/free Deck observe RED/GREEN and
   `nix develop --command make test`. Review native human/bot effect parity and eventual approved screenshots.
6. Report exact assertions, results/skips and pending CP-4/role/visual/performance checks; do not equate mocks with playability.

## Implementation contract

- Required `Name: string`, `Group: number` (ordinary groups 1..3). Optional `Description`, `Cost` (Pick X default 1),
  `Unlock`, `Stats`. Registry is `PW.Registries.perks`, **not** `PW.Perks` (that is the module library).
  Kind never auto-subscribes; the perks owner creates one `PW.Instance` per equipped perk on `PW_LoadoutGiven`.
- `Stats` are positive finite multipliers. `PW.Stat(ply, stat, base)` reads cached product: perks × registered
  stat-source tables × mode. No per-tick aggregation; refresh on loadout/spawn, explicit removal/disable recompute.
  A new arbitrary key has no effect without an assigned consumer. Weapon keys are sent as one composed table by
  the owner; never call partial `PW.SetStatMods` from a perk and erase the others.
- Supported keys come from `ADAPTER:SupportedStatMods()`; HL2 fallback supports none. Only ARC9 is currently
  implemented for weapon stat effects; do not assert TFA/MW compatibility. Use
  `PW.LoadoutUI.PerkDescription(definition, selectedWeaponClasses)` warnings rather than silently dropping picks.
- Server events: `OnEquip(owner)`, `OnUnequip(owner)`, `OnKill(owner, victim, dmg?)`,
  `OnDeath(owner, attacker, dmg?)`, `OnDamaged(owner, attacker, dmg?)`, `OnDealDamage(owner, victim, dmg?)`.
  Owner filters are supplied by the module, not global listeners on the definition. Methods store state on `self`.
  Additional callbacks use `self:Hook(name, fn)` / `self:Timer(delay, reps, fn)`; callback first argument is instance.
  An event firing does not imply enemy/direct-weapon eligibility: check `PW.IsEnemy` and proven provenance as needed.
- Cleanup: death, disconnect, loadout replacement, match end, role revoke and definition/module disable must retire
  effects, hooks, timers, cached and replicated flags. Failed constructors must not appear equipped.
  `OnUnequip` runs once even for failure; make it safe on partially initialized state. Re-enable does not re-equip
  an old life. Do not register a global forever hook or timer for each perk player.
- Movement uses `PW.PlayerOverrides`, relative to ordinary baseline; never multiply current speeds or heal on
  refresh. Preserve 400 HP/1.15 role composition and rollback. Equipment additions use
  `PW.Equipment.CountSource(ply, id, fn?)` after the existing first-answer question; never refill midlife or replace
  another perk's answer. Read equipment.md's exact signature and Stockpile implementation before using it.
- Reserve effects use `PW.WeaponAmmo.Resupply(ply, weapons, opts?)`; eligibility/weapon XP uses
  `PW.WeaponAmmo.DamageWeapon(owner, dmg)`. Do not substitute the active weapon for world/streak/projectile damage.
  Reveal uses `PW.Reveal` and `PW_CanReveal` before coordinates/packets/bot stimuli; preserve Ghost and CUAV.
  No hidden enemy knowledge, bot-only bonuses or difficulty changes. Death persistence uses the streak owner,
  sampled before perk cleanup; role revoke is not death persistence.

## Minimal example (inspected pattern, not executed here)

An approved data-only draw-time perk at `addons/privatewar/lua/privatewar/perks/example_draw.lua`:

```lua
PERK.Name = "Example Draw"
PERK.Description = "Draw weapons 25% faster where supported by the weapon adapter."
PERK.Group = 2
PERK.Cost = 1
PERK.Unlock = 1
PERK.Stats = { draw_time = 0.75 }
```

Setup: loader plus built-in perks/loadout/statmods modules; shared declaration, server equipping. This is the
existing Quick Draw pattern, not authorization to create a duplicate. Complete new task-specific declaration,
group-validation, composition and unsupported-base tests before using the requested id. A class with
`perk2 = "example_draw"` should yield `PW.Stat(owner, "draw_time", 1) == 0.75` when equipped, identity after removal;
HL2 must warn/no visible timing benefit, not pretend support. Run the authorized full `make test` command above.
For an event example inspect Adrenaline's actual timer and Flak Jacket's owner-filtered instance hook rather
than copying a callback with undefined owner/global PERK state.

## Tests first

Preserve `perks.lua` exact group, multiplication, recomputation, owner-only event and death-cleanup cases from the
test map. Add new perk cases: independent owners, bad/nonfinite stats, perk × wildcard × role/mode composition,
partial constructor failure, repeated removal, disable/revoke/round/reload, no other-owner mutation and human/bot parity.
Preserve T-11.17 suites for equipment counts, flash/fall/movement, reserve/provenance, Ghost/retaliation/continuity
and support descriptions when touching their seams. Native first/repeated-spawn tests must show one grant per life.

## Stop conditions

Stop for a frozen-effect/design conflict, nonexistent consumer/public API, unassigned owner/contract edit, impossible
mandatory case or missing permission. No direct third-party stat edits, partial weapon-mod writes, competing
movement/model hooks, replacing equipment-count answers, per-frame player scans or automatic Deck/publication.
After two environmental attempts, report evidence instead of weakening tests.
