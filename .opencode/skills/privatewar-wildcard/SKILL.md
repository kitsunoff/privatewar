---
name: privatewar-wildcard
description: Implement or change a Private War Pick X wildcard, WILDCARD ModifySlots rule, extra perk/attachment allowance, slot filter or wildcard stat composition. Use for Overkill/Perk Greed/Gunfighter-style work and validation/repair consistency, not for standalone perk events or weapon-base support.
---

# Private War wildcards

Read [shared workflow](../../../docs/agent-workflow.md), [loadout API](../../../docs/api/loadout.md) (Wildcards,
Pick X, validation, repair), [perks API](../../../docs/api/perks.md), [role policy](../../../docs/api/role-policy.md).
Decisions: `design/05-loadout.md` d.2–5, d.8, d.12, d.15; `design/01-extensibility.md` d.8, d.14–18.

## Ownership

Content: `addons/privatewar/lua/privatewar/wildcards/<unique_id>.lua`; tests:
`addons/privatewar/lua/tests/privatewar/wildcard_<topic>.lua`; types:
`addons/privatewar/lua/privatewar/types/wildcards.lua`. Inspect actual `wildcards/gunfighter.lua`,
`wildcards/perk_greed.lua`, `wildcards/overkill.lua`, kind `kinds/wildcards.lua` and
`modules/loadout/{sh_wildcards.lua,sh_budget.lua,sh_classes_repair.lua,init.lua}` under
`addons/privatewar/lua/privatewar/`. Shared loadout/perk/UI changes require explicit ownership; a new declaration
normally needs no core/validator rewrite, no net message and no new instance lifecycle.

## Workflow

1. Record git/base/status and inspect the requested effect against current slot declarations, validation, repair
   and Give consumers. Separate slot permission from actual engine support; accepting a slot need not equip it.
2. Declare owned files and non-goals. Determine count/filter/group/cap change, Pick X cost and allowed composition;
   use approved behavior and decide routine engineering details without a speculative questionnaire.
3. Use [test map](../../../docs/agent-test-map.md) for T-4.3 and preserve T-4.1/T-4.2/T-4.4/T-4.7/T-4.8.
   Write new allowance/denial/cost/removal/repair/error cases first against injected plain slot/catalogue/context data.
4. Implement `WILDCARD:ModifySlots(slots)` below and optional Stats. Add annotations for new fields, description,
   and class-editor model/validation tests. Check native Give path if adding a new slot rather than only changing one.
5. Run `nix develop --command make check`; only with explicit permission/free Deck observe RED/GREEN and
   `nix develop --command make test`. Inspect actual diff and runtime/UI composition without changing saved classes.
6. Report exact cases, actual gate counts/skips, example verification and pending CP-4/controller/perf checkpoints.

## Implementation contract

- Kind global `WILDCARD`, required `Name: string`, `ModifySlots: function`; optional `Description`, `Cost`, `Stats`.
  Registry `PW.Registries.wildcards`; no auto-subscription, not per-player `PW.Instance`. Enable ConVar
  `pw_wildcard_<id>_enabled` follows next-match snapshot, not instant toggle.
- `ModifySlots(self, slots)` mutates its scratch `table<string, PW.LoadoutSlot>` in place; return value is ignored.
  The loadout owner runs each unique selected wildcard in pick order on copies. Do not mutate declarations,
  registry entries, loadout, player state or globals. Guard missing slots; use finite bounded positive counts/caps.
  The callback can run repeatedly in server validation, repair and client/UI logic: no side effects or expensive work.
- Internal test seam `PW.Loadout._EffectiveSlots(slots, loadout, lookup, defaultCap?)` fills absent weapon caps
  from the setting before transforms, applies successful copies, then restores the wildcard slot itself.
  An exception discards that wildcard's whole scratch change, preserves other transforms, and is not a `PW.Call`
  permanent-disable path. No diagnostic/automatic disabling is promised. Do not rely on throwing for validation.
- Built-in `wildcard` slot holds at most two ids; duplicates, unknown ids, wrong kinds and over-count are rejected.
  No callback can raise its own wildcard allowance. Removing a wildcard restores ordinary slots; unavailable
  picks/extra slots repair away, but an over-budget class is marked N/A, not silently trimmed to budget.
- Costs include wildcard plus extra allowed picks, default 1 each; streaks remain free; cosmetic attachments are
  free and do not count toward caps. `loadout.budget = 0` removes only budget, not bans/group/count/cap rules.
  `loadout.maxattachments` is match cap; progression trim is a separate earlier gunsmith check. Do not bypass either.
- Perk group rules use effective slots too. Optional Stats feed registered `wildcards` source on `PW_LoadoutGiven`;
  `PW.Stat` multiplies with perks/mode. Only positive finite values contribute; unsupported adapter keys need honest
  descriptions. Do not call `PW.SetStatMods` independently or aggregate per tick.
- Test/UI may use internal pure seams; third-party content uses only WILDCARD fields/ModifySlots and documented
  public APIs. Never reach into `_Wildcards` or another owner's stores from new content.
- Important existing limit: server `PW.Loadout.Give` iterates declared slot order, not arbitrary effective new slots.
  Changing existing counts/filters is not proof a newly added weapon slot will Give. A requested new-slot runtime
  feature needs explicitly owned consumer/UI/wire work and tests; do not silently claim it works from validation alone.
- Role policy can forbid wildcard equip; the loadout owner clears its cache on role change/match end and the perk
  owner handles stats. Missing/disabled definitions must fail normal lookup. Do not promise eager cleanup on every
  reload path without a regression proving that path; pure transforms themselves keep no runtime state.

## Minimal example (inspected pattern, not executed here)

Approved extra-primary-attachment declaration at `addons/privatewar/lua/privatewar/wildcards/example_cap.lua`:

```lua
WILDCARD.Name = "Example Cap"
WILDCARD.Description = "One more attachment on the primary weapon."
WILDCARD.Cost = 1
---@param slots table<string, PW.LoadoutSlot>
function WILDCARD:ModifySlots(slots)
    local slot = slots.primary
    if slot == nil then return end
    slot.maxattachments = (slot.maxattachments or 0) + 1
end
```

Setup: loader, built-in loadout/wildcards kind, declared primary/wildcard slots; shared pure callback. This mirrors
Gunfighter's existing cap pattern, without its recoil Stats, and is not permission to add redundant content.
Write task-specific tests using `wildcards.lua`'s `baseSlots`, fake catalogue and injected context pattern.
Expected: base cap N becomes N+1 only with the pick; wildcard costs 1, attachment costs still count; N+2 rejected,
removal restores N, declared slots unchanged. Run the authorized full `make test` command above; a real gunsmith
requires a mounted adapter and independently legal/unlocked options, not just strings in a pure fixture.

## Tests first

Preserve all named `wildcards.lua` cases in the test map. Add missing-slot no-op, repeated deterministic calls,
input nonmutation, two-wildcard order, partial-change-then-error rollback and invalid/disabled-definition cases.
Cover full `Validate`/Cost/repair agreement, group restrictions, budget 0, cosmetic caps, bans and progression limit
interaction. For Stats add perk × wildcard × mode and removal/role-disable coverage with no stale owner effect;
for a new slot explicitly prove Give, editor, bounded wire and bot class consumers, not only effective-slot math.

## Stop conditions

Stop for decided-rule conflicts, unavailable required permission, unassigned shared contract/consumer work,
impossible mandatory assertions or unresolved API after inspection. Do not add a parallel validator, globally
change slots, make wildcards free implicitly, extend the wildcard slot, modify saved classes to hide errors,
add unbounded network structures or auto-access Deck/publish. Report environmental failure after two attempts.
