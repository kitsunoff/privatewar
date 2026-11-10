---
name: privatewar-weapon-adapter
description: Implement or change a Private War weapon-base adapter or integration addon, including catalogue discovery, gunsmith Apply/Validate, customization locks, stat mods and bot input compatibility. Use whenever adding support for a weapon base or fixing its integration; not for a perk declaration alone.
---

# Private War weapon adapters

Read [shared workflow](../../../docs/agent-workflow.md) and [adapter API](../../../docs/api/adapter.md).
Decisions: `design/04-weapons.md` d.1–7, `design/01-extensibility.md` d.8, d.14–18,
`design/05-loadout.md` d.15. ARC9 is implemented; TFA and MW Base are future integrations, not proven support.

## Ownership

One approved integration addon: `addons/privatewar-<base>/lua/privatewar/weapon_adapters/<id>/shared.lua`,
server `init.lua`, optional `cl_init.lua`; subsystem module under that addon's `lua/privatewar/modules/<id>/`.
Inspect actual reference: `addons/privatewar-arc9/lua/privatewar/weapon_adapters/arc9/shared.lua`, `init.lua` and
`addons/privatewar-arc9/lua/privatewar/modules/arc9/`. Do not assume the older `arc9.lua` sketch is the current file.
Types: `addons/privatewar/lua/privatewar/types/adapter.lua`, `weapons.lua`, `weapons_statmods.lua`; base-specific
types follow `types/arc9.lua`. Tests: `addons/privatewar/lua/tests/privatewar/integration_<base>.lua`.
Core fallback is `addons/privatewar/lua/privatewar/weapon_adapters/sweps.lua`. Core, loadout, bot writer and shared
API changes are not automatically owned; get assignment first. Do not edit the third-party base or copy its source.

## Workflow

1. Record git/base/status, requested base/version and approved behavior. Inspect public base tables/methods and current
   types/tests; research sketches are hypotheses, not permission to guess APIs. Identify dependency-absent behavior.
2. Declare addon/type/test ownership and non-goals. Inventory needed methods, realms, public evidence, supported
   stat keys and lock/restoration responsibilities. No weapon-base branching in generic core/loadout/bots.
3. Use [test map](../../../docs/agent-test-map.md) for T-3.1–T-3.8; write new pure helper and integration tests first.
   Test absent/malformed/disabled/error cases plus real mounted-pack bot weapons; restore all changed settings.
4. Implement required discovery, then optional build/ammo/stat/bot methods below and a base-specific module. Add
   annotations and UI compatibility descriptions; use shared pure helpers and thin native wrappers.
5. Run `nix develop --command make check`; only with explicit permission/free Deck run RED/GREEN,
   `nix develop --command make test`, native lock attempts, prediction/screenshot/performance checks.
6. Report exact installed dependency/evidence, assertions, results/skips, API limits and pending CP-3 human checks.

## Implementation contract

- Loader supplies `ADAPTER`; required methods: `IsAvailable() -> boolean`, `Claims(class, swep?) -> boolean`,
  `ListWeapons() -> PW.WeaponInfo[]`; shared. `Priority: number`, higher wins, tie lowest id. Registry
  `PW.WeaponAdapters`; lookup `PW.Adapters.For(weaponOrClass)`. Missing base must return false without indexing it.
- Consumers call `PW.Adapters.Call(adapter, method, ...)` / `CallFor(weaponOrClass, method, ...)`: `PW.Call` failure
  isolation plus defaults. A failed adapter is disabled; fallback remains usable. Never call optional methods directly.
  Invalidate/rebuild lookup/catalogue caches on current hooks rather than retain stale registry tables after reload.
- `ListWeapons` excludes abstract/base/nonspawnable/admin-only entries and returns
  `{ class, name, kind, category?, slot }` (`slot` 1 primary, 2 secondary, 3 equipment). No early SWEP discovery.
  `weapons_catalog` calls it in `PW_RegisterWeapons(reg)` after InitPostEntity, then `PW_WeaponsLoaded` fires.
  Module curation uses `reg.Register(tbl, class, { soft = true })`; preserve nested Attachments/Camos/Unlock.
- Build keys/options are opaque strings; false clears. `GetSlots(class, build?) -> PW.Slot[]`,
  `GetOptions(class, slotId) -> PW.Option[]`, `Validate(class, build) -> clean, rejectedBySlot` (server, static
  save-time check), `Apply(wep, build) -> stuckBuild` (server, live constraints and replication). Return actual
  installed options, not requested options; class repair sends one message for conflicts. Never share mutable
  attachment instance tables between weapons or mutate a stored SWEP table while building one weapon.
- `SetCustomizationLocked(locked)` is idempotent server API; enforce true for the session through the base's public
  permission/lock path. A no-op default is not security proof. No native-menu/free-customization toggle. Test the
  base's native customization path, including restored client presets. Restore only owned session state on shutdown.
- Core owns ammo: `SuppressDefaultAmmo(wep)` prevents delayed base ammo; `GetAmmoType(wep)` returns ammo id.
  Give through `PW.WeaponAmmo.Give(ply, class, opts?)`; do not refill grenades/ordinary reserve independently.
- Shared `InstallStatMods(wep)` once/idempotent and `RefreshStatMods(wep)` on revision; read only
  `PW.GetStatMod(wep:GetOwner(), key)`. `SupportedStatMods() -> table<string, boolean>` advertises only proven keys.
  Wire both realms for prediction; owner transfer/removal resets correctly. Preserve the pack's own public stat
  callbacks. This is base API composition, not detouring another Private War module. Damage is not multiplied here.
- Server `PrepareForBot(ply, wep)` once per Give; `GetFireInfo(wep)`, `GetRecoil(wep)`, `GetInputRules(wep)` use
  typed shapes in adapter.md. `BotAction(ply, wep, action, arg)` returns true only when the action happened.
  Preserve semi-shot release, reload taps, forbidden buttons, sprint/fire timing and repeated selection through
  the existing CUserCmd writer. No bot damage/aim/cadence cheats or direct combat calls when input can express them.
- Performance: catalogue/option discovery is cached outside hot loops; invalidate against actual content changes.
  Cheap selected-option checks must preserve full discovery semantics, including mutable blacklist/cosmetic state.
  Use the shared measurement workflow; no blanket claim of compatibility from a pure mock.

## Skeleton (not runnable integration)

Destination: `addons/privatewar-<base>/lua/privatewar/weapon_adapters/<id>/shared.lua`.
Loader provides `ADAPTER`. Replace the marker/base checks and implement discovery against verified public API;
this fail-closed skeleton intentionally lists nothing until completed. No new base global is assumed.

```lua
if not PW or PW.API ~= 1 then return end
ADAPTER.Priority = 100
---@return boolean
function ADAPTER:IsAvailable() return false end
---@param class string
---@param swep table?
---@return boolean
function ADAPTER:Claims(class, swep) return false end
---@return PW.WeaponInfo[]
function ADAPTER:ListWeapons() return {} end
```

Complete the module/lock/build/ammo/stat/bot methods as required by the requested scope, annotate new fields and
add pure plus mounted-pack integration cases. After authorized `make test`, expected result is a registered adapter,
correctly curated catalogue and working native build/lock/stat/input assertions; absence selects fallback safely.
The skeleton alone proves none of those runtime capabilities.

## Tests first

Preserve exact T-3.1–T-3.5 regression names in the test map and all five T-3.6–T-3.8 mounted integration clauses.
New integration tests also cover API guard, missing base, error-disable/fallback, repeated reload/lock/install,
owner changes, unsupported keys, delayed default ammo and two independent builds of one class.
Human checks: actual client prediction/timings, native customization refusal, bot firing/reload, removal/startup and
representative pack performance. No mounted dependency means native tests pending, not compatible by assertion.

## Stop conditions

Stop if the base's required public API cannot be verified, lock cannot enforce decided ownership, a new shared
contract/foreign path is needed without assignment, mandatory coverage is impossible, or permission is missing.
Do not vendor/fork/detour the base, bypass type rules, invent a base method, deploy automatically or claim absent
TFA/MW support. Report environment failures after two attempts.
