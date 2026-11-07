# 04 — Weapons: weapon base adapters

Status: decided (in-game risks: `../notes/08-weapon-adapters.md` §7).

## Goal and scope

The gamemode core knows nothing about specific weapon bases. Each base is supported by an **adapter**:

- adapters ship as separate integration addons;
- the core ships one fallback adapter for plain SWEPs, so the game works with no weapon base installed. Clarified with the user on 2026-11-07: it is an ordinary entity of the kind `weapon_adapters` in `lua/privatewar/weapon_adapters/`, not a gamemode folder (`01-extensibility.md` d.5, d.8, d.16).

```text
lua/privatewar/weapon_adapters/
  sweps.lua    built-in fallback adapter for plain SWEPs (HL2 weapons and simple SWEPs)

Separate Workshop addons (integrations):
  privatewar-arc9      ARC9 adapter
  privatewar-mwbase    MW Base (mg_base) adapter
  privatewar-tfa       TFA adapter
```

## Decisions

### Registration

A weapon adapter is an ordinary entity of the kind `weapon_adapters` (see `01-extensibility.md`, decisions 8 and 16). It is registered SWEP-style:

```lua
-- lua/privatewar/weapon_adapters/arc9.lua (in the integration addon)
if not PW or PW.API ~= 1 then return end

ADAPTER.Priority = 100          -- higher wins when several adapters claim a class
function ADAPTER:IsAvailable() return ARC9 ~= nil end
function ADAPTER:Claims(class) ... end
-- see notes/08-weapon-adapters.md for the refined interface
```

The core skips adapters whose `IsAvailable()` returns false, and logs a single clear line per adapter at startup. Failures are not silent.

### Adapter interface

1. **Interface v1 = `../notes/08-weapon-adapters.md` §5, adapted to the SWEP style.**
   - Methods are written as `ADAPTER:Method(...)` (SWEP style, `01-extensibility.md` decision 8); `Priority` is a field.
   - No `apiVersion` field: adapters guard themselves with `PW.API` (`01-extensibility.md` decision 14).
   - Types (`PW.WeaponInfo`, `PW.Stats`, `PW.Build`, `PW.Slot`, `PW.Option`, `PW.FireInfo`, `PW.Recoil`, `PW.InputRules`) are taken as written in §5.
   - Required: `IsAvailable`, `Claims`, `ListWeapons`. Everything else is optional with a safe core default (§5).

   | Group | Methods |
   | --- | --- |
   | Discovery (required) | `IsAvailable`, `Claims(class)`, `ListWeapons()` |
   | Stats | `GetBaseStats(class)`, `GetLiveStats(wep)`, `PreviewBuildStats(class, build)`, `GetIcon(class)` |
   | Attachments (absent = no gunsmith for that weapon) | `GetSlots`, `GetOptions`, `Validate`, `Apply`, `SetCustomizationLocked` |
   | Ammo | `SuppressDefaultAmmo`, `GetAmmoType` |
   | State | `IsReloading`, `IsAiming`, `GetClip`, `CanFireNow` |
   | Bots | `PrepareForBot`, `GetFireInfo`, `GetRecoil`, `GetInputRules`, `BotAction` |
   | Kill info | `IsHeadshot`, `GetDisplayName` |
   | Stat modifiers | `InstallStatMods`, `RefreshStatMods`, `SupportedStatMods` (decision 6) |

   - Per-base implementation notes: `../notes/08-weapon-adapters.md` §5.1, bot shims §6.

### Customization ownership

2. **The gamemode owns attachments. No in-match customization, ever.**
   - Attachments are chosen only in the gamemode's gunsmith in the loadout menu (`05-loadout.md`, `10-frontend.md`) and applied server-side with `ADAPTER:Apply` at spawn.
   - Every adapter's `SetCustomizationLocked(true)` is applied for the whole session; the native customization menus (ARC9, TFA, MW Base) are always blocked. There is no "free customization" toggle.
   - Rationale: balance, attachment unlocks through progression, bots get real builds, and it closes the ARC9 receiver exploit (no ownership check, `../notes/08-weapon-adapters.md` §7.1).

### Weapon catalogue

3. **Weapons are a kind `weapons/` (id = SWEP class), registered declaratively or programmatically.**

   ```lua
   -- declarative: lua/privatewar/weapons/arc9_eft_ak74.lua
   WEAPON.Category = "ar"
   WEAPON.Name     = "AK-74"
   WEAPON.Unlock   = 4          -- read by 06-progression

   -- programmatic: any module, in the registration phase
   function MODULE:PW_RegisterWeapons(reg)
       for class, wtype in pairs(ARC9.SpawnableWeapons) do
           reg.Register({ Category = MapType(wtype) }, class, { soft = true })
       end
   end
   ```

   - **Registration phase.** SWEPs load after the gamemode, so the core, in `InitPostEntity`, calls `PW_RegisterWeapons(reg)` and then fires `PW_WeaponsLoaded`. Consumers (loadout, bots, HUD) wait for `PW_WeaponsLoaded`; registering from a module's own `InitPostEntity` hook is not used because hook order is undefined.
   - **`soft = true`:** if an entry with that id exists, only missing fields are filled; nothing is overwritten. Declarative files (loaded earlier) and explicit `Register` calls win; automatic registration fills gaps. Without `soft`, a registration replaces the entry (`01-extensibility.md` decision 12).
   - `PW_PreRegister` (`01-extensibility.md` decision 10) runs for every registration, including programmatic ones after the main load; `Base` of a late entry is resolved at registration time.
   - Every entry gets `pw_weapon_<class>_enabled` (`01-extensibility.md` decision 11), so the host can hide any weapon regardless of who registered it.
   - `Unlock` may be set by a curated file or by the integration module; if empty, `06-progression.md` decides the default.

4. **A weapon base integration = one addon with a module and an adapter.**

   ```text
   privatewar-arc9/lua/privatewar/
     modules/arc9/shared.lua          MODULE: base ConVars (arc9_atts_nocustomize 1), bot shims, weapon registration
     weapon_adapters/arc9.lua         ADAPTER: Claims, Apply, GetFireInfo, ...
   ```

   - The module owns everything base-specific; the adapter stays a separate entity because loadout, bots and HUD look up the adapter for a weapon class (`Claims`, `Priority`).
   - The core knows nothing about any base; it only provides the registration phase, the `soft` rule, `PW_PreRegister` and per-entry ConVars.

5. **Weapon packs and bases mix freely.** Installed integrations are all active at once. Restrictions are match settings of the loadout module, usable in Game Setup and in playlists: an allowed-bases filter (`weapons.bases`, default all) and a banned-weapons list. Details in `05-loadout.md`.

### Weapon stat modifiers

6. **Per-player weapon stat modifiers: values in replicated player state, adapters only wire the base.**
   - New optional adapter methods (shared, default no-op): `ADAPTER:InstallStatMods(wep)` (once per weapon instance on both realms, idempotent), `ADAPTER:RefreshStatMods(wep)` (after the owner's modifier revision changed), `ADAPTER:SupportedStatMods()` (keys this base honours, for UI and perk descriptions).
   - A server-only "apply" call cannot reach client-predicted code on any of the three bases, hence this shape (`../notes/12-weapon-stat-modifiers.md` §6.1).
   - Keys (multipliers, absent = 1.0): `reload_time`, `draw_time`, `ads_time`, `sprint_to_fire`, `recoil`, `spread`.
   - Values live on the **player** as NW2 floats plus a revision counter written last (`PW.SetStatMods(ply, mods)` on the server, `PW.GetStatMod(ply, key)` shared). A weapon picked up by another player reads its new owner's values automatically. Removal = `PW.SetStatMods(ply, {})`.
   - A shared check refreshes weapons whose owner's revision moved (server: all players; client: `LocalPlayer()` only).
   - Per-base mechanism: ARC9 — per-instance `<Stat>Hook` functions plus `DoInvalidateCache` (a global `ARC9_<Stat>Hook` is unreliable because of ARC9's "no modifiers" fast path, `sh_0_stats.lua:316,431`); MW Base — `OnBuildCustomizedGun` scaling `Animations.*.Fps` plus `BuildCustomizedGun`; TFA — `TFA_GetStat` / `TFA_AnimationRate` hooks.
   - Excluded from MVP: `sprint_to_fire` on TFA (hardcoded constant), magazine size (attachments do that), damage (applied once in the core damage hook instead, base-agnostic), reload/recoil/spread on plain SWEPs and HL2 weapons, RPM.
   - Details, per-base sketches and in-game checks: `../notes/12-weapon-stat-modifiers.md`.

### Performance profile

7. **ARC9 performance profile: the host setting `arc9.perf`, `deck` by default** (user decision 2026-11-07; `DESIGN.md` global rule 7, optimisation first).
   - `deck` (default): the client sets `arc9_tpik_others 0`, `arc9_lod_distance 0.4`, `arc9_cheapscopes 1`, `arc9_fx_rtvm 0`, `arc9_muzzle_others 0`, `arc9_eject_fx 0` (visuals); the server sets `arc9_bullet_physics 0` (hitscan) and `arc9_ricochet 0`. Penetration (`arc9_mod_penetration`) is not touched and stays on: measured on the Steam Deck it adds no server Lua time and no p99 (`../docs/perf-report.md`, "ARC9 performance profile").
   - `off`: restores the original ARC9 values, then leaves ARC9 alone. There is no third value (user decision 2026-11-07).
   - Each realm sets its own ConVars (client ConVars on each client, server ConVars on the server); the values it replaced are saved and restored on `ShutDown`, like the HUD ConVars. The precache ConVars are not part of the profile and are not restored.
   - Crash safety (user decision 2026-11-07): when `deck` is first applied, each realm writes the original values to a file in its own `data/` (`privatewar/arc9_perf_server.json`, `privatewar/arc9_perf_client.json`). If that file still exists when the mode starts again (no clean `ShutDown`), its values are restored first, then the profile applies again. A clean `ShutDown` restores and deletes the file. Same pattern as the testgate ConVar backup (`convars_backup.json`).
   - The setting is a `server` scope setting, shown in the Host section of SETTINGS with a description of the trade (the optional settings `description` field, user decision 2026-11-07).

## Interfaces

See decision 1.

## Performance budget

TBD.

## Security

Required security setting for ARC9: `arc9_atts_nocustomize 1` for the whole session (decision 2: the gamemode always owns builds). ARC9's `arc9_networkweapon` receiver does not check weapon ownership (`lua/arc9/server/sv_net.lua:37-45`, verified).

## Open questions

1. ~~Adapter API v1~~ Closed: decision 1 (verified against the sources in `../notes/08-weapon-adapters.md`; in-game risks in its §7).

## Research

- `../notes/12-weapon-stat-modifiers.md` (per-player weapon stat modifiers)
- `../notes/08-weapon-adapters.md`
