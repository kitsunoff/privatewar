# Perks API: the `perks` kind, slots, `PW.Stat`

Status: added after T-4.4 (2026-11-07). The code wins over any description here.

Module `perks` (`lua/privatewar/modules/perks/`: `shared.lua` slots, group rule, multiplier chain, `PW.Stat`; `init.lua`
server state, instances and hooks). Kind: `lua/privatewar/kinds/perks.lua`. Perks: `lua/privatewar/perks/`. Types:
`lua/privatewar/types/perks.lua`. Source decisions: `design/05-loadout.md` d.4, d.8, `design/01-extensibility.md` d.12, d.16.
It builds on `loadout.md` (slots, validation, `PW_LoadoutGiven`), `adapter.md` (`PW.SetStatMods`) and `core.md`
(`PW.Instance`, `PW.HookFor`).

## Kind `perks`

One file per perk in `lua/privatewar/perks/`, class table `PERK`. Never auto-subscribed (`KIND.Subscribe = "never"`):
the module makes a per-player instance (`PW.Instance`) of every equipped perk. Enable ConVar `pw_perk_<id>_enabled`.
The registry is `PW.Registries.perks`; `PW.Perks` is the module library.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `Name` | string | yes | Display name |
| `Group` | number | yes | The perk slot group it fits (1 to 3) |
| `Description` | string | no | Text for the UI |
| `Cost` | number | no | Pick X cost (default 1, see `loadout.md` "Pick X") |
| `Stats` | `table<string, number>` | no | Multipliers by stat id, read through `PW.Stat`; weapon keys also go to `PW.SetStatMods` |

Methods, all optional. The module calls the event methods only for the owner of the instance; the owner is the
first argument.

| Method | Called when |
| --- | --- |
| `PERK:OnEquip(owner)` | The instance is created (from `PW.Instance`) |
| `PERK:OnUnequip(owner)` | The instance ends (from `PW.Instance`) |
| `PERK:OnKill(owner, victim, dmg)` | The owner killed `victim` (not itself) |
| `PERK:OnDeath(owner, attacker, dmg)` | The owner died |
| `PERK:OnDamaged(owner, attacker, dmg)` | The owner took damage (after it was applied) |
| `PERK:OnDealDamage(owner, victim, dmg)` | The owner damaged `victim` (not itself) |

For any other hook, subscribe from `OnEquip` with `self:Hook(name, fn)`; it ends with the instance. `self:Timer` works
the same way (see `core.md`, instances).

## Slots and the group rule

The module declares `perk1`, `perk2`, `perk3` (kind `perks`, `group` = 1, 2, 3, label `#pw.slot.perkN`), at load and
again on `PW_RegistriesLoaded`. A `PW_ValidateLoadout` listener of the module checks that every perk in a perks-kind
slot has the slot's `Group`; a mismatch rejects the loadout with a reason such as
`sleight_of_hand is a group 2 perk, slot perk1 takes group 1`. A class with a wrong-group perk is shown `N/A` with
that reason; it is not repaired. A slot declared without `group` accepts any perk.

## Stats: `PW.Stat(ply, stat, base) -> number`

Returns `base` times the cached multiplier of `stat` for the player (`base` when there is none). The multiplier of a
stat is the product of, in this order:

1. the `Stats` of the player's equipped perks;
2. the tables returned by the registered stat sources, in sorted order of source id;
3. `PW.ActiveMode.Stats`, when the active mode has a `Stats` table (mode multipliers).

Only positive finite numbers count. The product is commutative; the order only fixes iteration.

Weapon keys (`reload_time`, `draw_time`, `ads_time`, `sprint_to_fire`, `recoil`, `spread`, or the keys of
`PW.StatMods._Keys` when present) are also sent to the weapon base through `PW.SetStatMods(ply, mods)`, only when
they changed. A base honours a key only if its adapter lists it in `SupportedStatMods`. **The HL2 fallback adapter
supports no stat mods, so the stat perks (Ready Up, Sleight of Hand) have no visible effect on HL2 weapons.** Player
stats (such as `move_speed`) are computed and readable through `PW.Stat`, but nothing applies them yet.

## `PW.Perks`

| Function | Contract |
| --- | --- |
| `PW.Perks.Get(ply) -> string[]` | Server. A copy of the ids of the player's equipped perks; empty when none |
| `PW.Perks.Refresh(ply, loadout)` | Server. Ends the old instances, makes instances for the perks in the loadout (slot order; unknown ids skipped) and recomputes the stats |
| `PW.Perks.StatSource(id, fn)` | Registers (or replaces) a stat source: `fn(ply)` returns a list of `table<string, number>` multiplier tables, or nothing. A source that errors is skipped. This is the hook point for the wildcards (T-4.3): the loadout module registers the source `wildcards` (see `loadout.md`, "Wildcards"). The group rule is judged by `PW.Loadout._EffectiveSlots`, so a wildcard such as `perk_greed` (second perk in `perk1`) is accepted |
| `PW.Perks.Slots` | `{ "perk1", "perk2", "perk3" }` |

## When it recomputes

The only trigger is the notification `PW_LoadoutGiven(ply, loadout)`, fired at the end of `PW.Loadout.Give` (see
`loadout.md`): the spawn in LIVE, or a mode giving a new loadout. A class edit therefore applies on the next spawn.
A stat source whose answer changes later is not polled; call `PW.Perks.Refresh` or give the loadout again.

## Instance cleanup

The instances of a player end on death (`PostPlayerDeath`), disconnect (`PlayerDisconnected`), the end of the match
(`PW_MatchEnd`) and when a new loadout is given. Death, disconnect and match end also clear the cached stats and send
empty weapon mods. Hooks and timers made through `self:Hook` and `self:Timer` end with the instance.

## Sample perks

| Id | Group | Effect |
| --- | --- | --- |
| `ready_up` | 1 | `Stats = { sprint_to_fire = 0.6 }` (fire 40% sooner after sprinting) |
| `flak_jacket` | 1 | `OnEquip` hooks `EntityTakeDamage` through `self:Hook` and scales explosive damage to the owner by 0.5 |
| `sleight_of_hand` | 2 | `Stats = { reload_time = 0.65 }` (reload 35% faster) |
| `adrenaline` | 3 | `OnKill` starts a timer: 8 ticks of 0.25 s, 5 health each (40 over 2 s), capped at max health; stops when the owner dies |

Presets: Assault `flak_jacket`, `sleight_of_hand`, `adrenaline`; Close quarters and Run and gun `ready_up`,
`sleight_of_hand`, `adrenaline` (see `loadout.md`).

## Mandatory cases

`TASKS.md` T-4.4 (tests in `lua/tests/privatewar/perks.lua`): the group rule, the multiplier chain, owner-only events,
instance cleanup, recompute on `PW_LoadoutGiven`. Manual checks: the local manual checklist (not published), section "Perks (T-4.4)".
