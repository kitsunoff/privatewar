# MW Base integration and Steam Deck performance profile (T-3.8)

Status: `planned`

Recorded: 2026-11-21

Approval (2026-11-22): the user approved every design change proposed in this record and the recommended
default of every open question, except where an answer below says otherwise. This approves the design
direction for implementation; push, PR, merge to `main` and publication still need separate approval.

Related: [TFA integration](tfa-integration.md) shares the `PW.WeaponConVars` helper defined here (§6.5); whichever
change lands first creates it. Weapon and attachment unlocks stay compatible with
[programmatic unlocks](unlock-entitlements.md).

Research: [MW Base research](../../notes/29-mwbase-research.md) (cited below as `notes/29 §N`), with
[`notes/08`](../../notes/08-weapon-adapters.md) §3 and §6.3 and [`notes/12`](../../notes/12-weapon-stat-modifiers.md)
§3. This record is tracking, not authorization: it does not authorize implementation, design changes, installing
Workshop items, Steam Deck access, pushing or publication. It replaces the MW Base half of
[`changes/blocked/weapon-integrations.md`](../blocked/weapon-integrations.md) once the orchestrator updates that
record and [`changes/INDEX.md`](../INDEX.md); this record does not edit them.

Rails for the implementing agent: every name, path, value and order below is decided here or listed as an open
question. Do not invent a different name, add a ConVar, or change a value. Where a step says "verify", stop and
report when the installed MW Base differs from this record; do not adapt silently.

## 1. User request

- [ ] Integrate MW Base (the `mg_base` weapon base, Workshop 2459720887) into Private War, install it and test it on
  the Steam Deck.
- [ ] Most important: study what MW Base costs and what can be cut, and make the Private War Deck performance
  profile cut it hard, so MW Base does not lag on a Steam Deck. The `deck` profile cuts everything that costs frame
  time; quality stays opt-in (`DESIGN.md` global rule 7).

## 2. Design changes requiring approval

Implementation must not start before the user approves items 1 and 2. Item 3 is a lane-internal choice recorded for
the reviewer.

1. **Extend `design/04-weapons.md` d.7 to MW Base** (new decision text for the orchestrator to write after approval):
   a host setting `mwbase.perf` with values `deck` (default) and `off`, the same apply, restore and crash-safe
   backup rules as `arc9.perf`, with the ConVar and per-weapon values of §6 of this record. Without approval the
   integration ships with no performance profile.
2. **Per-weapon cuts through `OnBuildCustomizedGun`** (`notes/29 §6`): MW Base has no ConVar for reverb, ricochet,
   shell effects, tracers or penetration. The `deck` profile sets public per-instance fields and per-instance
   method overrides (`CreateAndResumeReverbJob`, `HandleEjection`, optionally `FireTracer`) on each MW weapon from a
   `hook.Add("OnBuildCustomizedGun", ...)` listener. MW Base documents this hook as the extension point for
   third-party stat changes; no MW Base file is edited and no global function is replaced. It is still a new kind of
   integration technique for this project, so it needs approval.
3. **Shared ConVar swap helper (lane decision, weapons lane):** generalize the pure parts of
   `addons/privatewar-arc9/lua/privatewar/modules/arc9/sh_perf.lua` and `PW.Arc9._SwapConVars` into
   `addons/privatewar/lua/privatewar/modules/weapons_core/sh_convars.lua` (`PW.WeaponConVars`). Reason: a second
   copy of the crash-safe save and restore logic would double the places where a crash-safety bug can hide; the
   lanes table gives `modules/weapons_*` to the weapons lane, which also owns both integrations; the helper lives in
   `weapons_core`, which every adapter already needs, so disabling an optional module cannot break it. ARC9 is
   **not** migrated in this change (its T-11.8 cases stay untouched); an ARC9 migration is a separate follow-up.
4. `docs/api/adapter.md` is frozen; the orchestrator adds an "MW Base session ConVars" subsection after the merge
   (step 11 drafts the text). No contract method is added or changed.

## 3. Prerequisites

- [ ] User approval of §2 items 1 and 2, and answers to §10 questions 1 to 3 (defaults are given there).
- [ ] The user subscribes, in the Steam client on the Steam Deck, to exactly these Workshop items (IDs verified
  through the Steam Web API on 2026-11-21, `notes/29 §1.1`):

  | Item | Workshop ID | Needed for |
  | --- | --- | --- |
  | MW Base ("Modern Wokefare Base") | 2459720887 | everything |
  | Modern Warfare 2019 SWEPS - Assault Rifles | 2528829149 | `ar` weapons, tests |
  | Modern Warfare 2019 SWEPS - Submachine Guns | 2802430252 | `smg` weapons, measurement |
  | Modern Warfare 2019 SWEPS - Pistols | 2459723892 | secondary weapons |

  About 3.15 GB. Shotguns (2751323984), Marksman Rifles (2864559679), Light machine guns (2960120610) and Sniper
  Rifles (2918635913) are optional and not needed for any case below. Do not subscribe to compressed re-uploads or
  to "Modern Warfare: LITE" (incompatible base).
- [ ] The user restarts GMod on the Deck after subscribing: GMod mounts addons only at startup
  (`scripts/deck/deploy.sh` comment). The new integration folder `addons/privatewar-mwbase/` is deployed by the
  existing loop in `scripts/deck/deploy.sh` and also needs one game start (`[deploy] new addon ...` line).
- [ ] Any Deck access needs fresh explicit permission and confirmation that the Deck is free (`AGENTS.md` rule 7);
  only the locked `scripts/deck/*.sh` are used, through `nix develop --command`.
- [ ] Test runner: `make test` runs GLuaTest in the real game on the Deck (`scripts/check/test.sh` →
  `scripts/deck/test.sh`), so the Workshop items above are mounted there by the subscription. No Docker or
  collection runner exists in this repository. Do not add one in this change: a dedicated server would also hit
  MW Base's server-side read of the client ConVar `mgbase_tacsprint` (`notes/29 §3`).
- [ ] Step 0 (source verification) is done against the installed GMA before any code is written.

## 4. Files to create or modify

Paths are relative to the repository root. Each was checked against the current tree: the deploy loop
(`scripts/deck/deploy.sh`), packaging (`scripts/package/build.sh`), the rules gate (`scripts/check/rules.sh`) and
the lint and type gates (`scripts/check/lib.sh`) already pick up every `addons/<name>/` folder, so no script,
`Makefile`, `flake.nix` or `.luarc.json` change is needed.

| Path | Action | Content |
| --- | --- | --- |
| `addons/privatewar-mwbase/addon.json` | create | copy of `addons/privatewar-arc9/addon.json` with `"title": "Private War: MW Base integration"` |
| `addons/privatewar-mwbase/logo.png` | create | only if the user supplies one (§10 question 5); otherwise omit and confirm `scripts/package/verify.sh` accepts that |
| `addons/privatewar-mwbase/lua/privatewar/weapon_adapters/mwbase/shared.lua` | create | adapter, shared methods (§5) |
| `addons/privatewar-mwbase/lua/privatewar/weapon_adapters/mwbase/init.lua` | create | adapter, server methods (§5) |
| `addons/privatewar-mwbase/lua/privatewar/modules/mwbase/shared.lua` | create | `MODULE`, setting `perf`, `PW.MwBase` pure helpers, includes `sh_perf.lua` |
| `addons/privatewar-mwbase/lua/privatewar/modules/mwbase/sh_perf.lua` | create | profile tables and per-weapon cut functions (§6), pure |
| `addons/privatewar-mwbase/lua/privatewar/modules/mwbase/init.lua` | create | server glue: lock, server profile, `OnBuildCustomizedGun` listener, `ShutDown` |
| `addons/privatewar-mwbase/lua/privatewar/modules/mwbase/cl_init.lua` | create | client glue: HUD set, client profile, `ShutDown` |
| `addons/privatewar/lua/privatewar/modules/weapons_core/sh_convars.lua` | create | `PW.WeaponConVars` (§2 item 3) |
| `addons/privatewar/lua/privatewar/modules/weapons_core/shared.lua` | modify | `AddCSLuaFile` and `include` of `sh_convars.lua` at the end, the same way `modules/arc9/shared.lua` includes `sh_perf.lua` |
| `addons/privatewar/lua/privatewar/types/mwbase.lua` | create | `---@meta` types: `MwAttachment`, `PW.MwBaseWeapon`, `PW.MwBaseLib`, `PW.MwBaseStore`, and the `MW_ATTS` global, following `types/arc9.lua` |
| `addons/privatewar/lua/privatewar/types/weapon_convars.lua` | create | `---@meta` types of `PW.WeaponConVars` (`PW.ConVarSwap`, `PW.ConVarIO`, `PW.ConVarBackup`, `PW.PerfAction`) |
| `addons/privatewar/lua/tests/privatewar/weapons_convars.lua` | create | pure tests of the helper (§8.3) |
| `addons/privatewar/lua/tests/privatewar/mwbase_perf.lua` | create | profile tests (§8.2) |
| `addons/privatewar/lua/tests/privatewar/integration_mwbase.lua` | create | T-3.8 mandatory and adapter tests (§8.1) |
| `docs/agent-test-map.md` | modify | rows for T-3.8 pointing to `integration_mwbase.lua` with the exact case names of §8.1 (keep the ARC9 rows) |
| `docs/perf-report.md` | modify | new section "MW Base (T-3.8)" with the numbers of §9 |
| `THIRD_PARTY_NOTICES.md` | none | nothing is vendored |

Not created in this change: a generated MW bot loadout module (`bots_mwbase_loadouts`, §10 question 4) and the
ARC9 migration to `PW.WeaponConVars`.

Names fixed for the code: adapter id `mwbase` (`ADAPTER.ClassName` from the folder), module id `mwbase`, setting
`mwbase.perf`, library `PW.MwBase`, session store `PW._MwBase = { lock, hud, perf, memo }` (same shape as
`PW._Arc9`), backup files `data/privatewar/mwbase_perf_server.json` and `data/privatewar/mwbase_perf_client.json`,
listener names `PW.MwBase.Perf` and `PW.MwBase.StatMods` on `OnBuildCustomizedGun`, log prefix `[PW] mwbase:`.

## 5. Adapter contract mapping

Every method of `docs/api/adapter.md`. `wep` is a live weapon based on `mg_base`; field names are from the mirror
(`notes/29 §2`) and must be re-verified in step 0. "Memo" means `PW.MwBase._Memo(PW._MwBase.memo, revision, key,
compute)` with the same semantics as `PW.Arc9._Memo`; the revision is
`tostring(MW_ATTS) .. ":" .. table.Count(MW_ATTS) .. ":" .. #weapons.GetList()`.

| Method | Realm | MW Base mapping | Fallback |
| --- | --- | --- | --- |
| `Priority` | field | `100` (same as ARC9) | n/a |
| `IsAvailable()` | shared | `rawget(_G, "MW_ATTS") ~= nil and weapons.GetStored("mg_base") ~= nil` | `false` |
| `Claims(class, swep)` | shared | `swep ~= nil and class ~= "mg_base" and weapons.IsBasedOn(class, "mg_base")` | `false` |
| `ListWeapons()` | shared | every `weapons.GetList()` entry with `ClassName ~= "mg_base"`, based on `mg_base`, `Spawnable == true`, `AdminOnly ~= true`, `istable(Customization)`; info from `PW.MwBase._InfoFrom(swep)`; sorted by class | `{}` |
| `GetBaseStats(class)` | shared | `PW.MwBase._StatsFrom(weapons.Get(class))`, memo per class | `{}` |
| `GetLiveStats(wep)` | shared | `PW.MwBase._StatsFrom(wep:GetTable())` (after the build) | base stats |
| `PreviewBuildStats` | shared | not implemented (no consumer in the tree) | default `nil` |
| `GetIcon(class)` | client | not implemented | default `entities/<class>.png` |
| `GetSlots(class, build)` | shared | integer keys of `weapons.GetStored(class).Customization`, ascending, skipping `SLOT_CONVERSIONS` (-999) and non-number keys; `id = tostring(slot)`; `name` = `MW_ATTS[options[1]].Category` or `"Slot " .. slot`; `default = options[1]`; `cosmetic` = every option of the slot has `CosmeticChange == true`; `parent = nil`; `build` ignored (flat slots); memo per class; return caller-owned copies like ARC9's `copyList` | `{}` |
| `GetOptions(class, slotId)` | shared | `Customization[tonumber(slotId)]` indices 2..n (index 1 is the default, selected with `false`); `id` = class name, `name` = `MW_ATTS[id].Name` or the id, `cosmetic = MW_ATTS[id].CosmeticChange == true`, `icon` = `MW_ATTS[id].Icon` on the client only when it is an `IMaterial`; unknown `MW_ATTS` entries skipped; memo; copies | `{}` |
| `IsSelectionCosmetic(class, slotId, option)` | shared | `nil` when unavailable or the class has no `Customization`; else `true` only when `option` is in `Customization[slot]` and `MW_ATTS[option].CosmeticChange == true`; `false` otherwise | `nil` |
| `Validate(class, build)` | server | per entry: slot missing → `"unknown_slot"`; `false` → kept; option not in `MW_ATTS` → `"unknown_option"`; option not at index ≥ 2 of that slot → `"wrong_slot"`; else kept | identity |
| `Apply(wep, build)` | server | §5.1 | `{}` |
| `SetCustomizationLocked(locked)` | server | `PW.MwBase.SetLocked(locked == true)`: swaps `LockConVars` (§6.1) through `PW.WeaponConVars.Swap` | no-op |
| `GetOptionStats(class, slot, option)` | shared | `PW.MwBase._OptionStats(base, changed)` where `base` = memo copy of `weapons.Get(class)` and `changed` = `table.Copy(base)` after `MW_ATTS[option]:Stats(changed)` inside `pcall`; `nil` on error or no numeric change; memo per class and option | `nil` |
| `GetOptionSetKey()` | shared | `#names .. ":" .. util.CRC(table.concat(sorted MW_ATTS keys, "\n"))`, memo | n/a |
| `SuppressDefaultAmmo(wep)` | server | not implemented: `Primary.DefaultClip = 0` already (`notes/29 §2.2`) | default no-op |
| `GetAmmoType(wep)` | shared | not implemented | `wep:GetPrimaryAmmoType()` |
| `IsReloading(wep)` | shared | `wep:HasFlag("Reloading")` | `false` |
| `IsAiming(wep)` | shared | `wep:HasFlag("Aiming")` | default |
| `GetClip(wep)` | shared | `wep:Clip1(), wep:GetMaxClip1()` (MW fills `ClipSize`, not the chambered round, at spawn) | default |
| `CanFireNow(wep)` | shared | `wep:Clip1() ~= 0 and CurTime() > wep:GetNextPrimaryFire() and wep:HasFlag("Rechambered") and not wep:HasFlag("Lowered")` | default |
| `PrepareForBot(ply, wep)` | server | no-op body that returns when `wep` is not MW (presets are client-only, ammo is already 0); exists so the case "runs without errors" exercises the adapter | default |
| `GetFireInfo(wep)` | server | `kind`: `"safe"` if `HasFlag("Lowered")`, `"burst"` if `Primary.BurstRounds > 1`, `"auto"` if `Primary.Automatic`, else `"semi"`; `burst = max(1, BurstRounds or 1)`; `rpm = Primary.RPM` or 600; `adsKey = IN_ATTACK` when `UseLauncherLogic == true`, else `IN_ATTACK2`; `projectileSpeed = Projectile.Speed` and `projectileGravity = Projectile.Gravity` when `istable(Projectile)` and numbers, else `nil` (units verified in step 0) | default |
| `GetRecoil(wep)` | server | `pitch` = mean of `Recoil.Vertical[1..2]` × `mgbase_sv_recoil`; `yaw` = max of `abs(Recoil.Horizontal[1..2])` × `mgbase_sv_recoil`; `affectsBotAim = true` | default |
| `GetInputRules(wep)` | server | `releaseBetweenShots = not Primary.Automatic or BurstRounds > 1`; `reloadTap = false`; `reloadTapMax = 0.3`; `forbidWithAttack = IN_USE`; `forbidWithReload = IN_USE`; `noSprintWhileFiring = true`; `sprintToFire` = static length of animation `Sprint_Out` (`PW.MwBase._AnimLength`) or 0.25; `reselectEveryTick = true` | default |
| `BotAction(ply, wep, action, arg)` | server | §5.2 | `false` |
| `IsHeadshot(dmginfo)` | server | `dmginfo:GetDamageCustom() == 1 or nil` (MW's head marker; `nil` lets the core decide) | `nil` |
| `GetDisplayName(wep)` | shared | not implemented | default |
| `SupportedStatMods()` | shared | all six keys `true` | `{}` |
| `InstallStatMods(wep)` | shared | no-op (the global listener `PW.MwBase.StatMods` does the work) | no-op |
| `RefreshStatMods(wep)` | shared | `wep:BuildCustomizedGun()` unless `wep:HasFlag("Reloading")`; when reloading, set `wep.pwMwStatModsPending = true` and the module's `Think` retries once the flag clears | no-op |

Pure helpers in `modules/mwbase/shared.lua` (all testable without MW Base):

- `PW.MwBase.Categories`: lower-case `SubCategory` → category: `"assault rifles"` → `"ar"`, `"submachine guns"` →
  `"smg"`, `"shotguns"` → `"shotgun"`, `"sniper rifles"` → `"sniper"`, `"marksman rifles"` → `"sniper"`,
  `"light machine guns"` and `"lightmachine guns"` → `"lmg"`, `"pistols"` → `"pistol"`, `"launchers"` →
  `"special"`. Step 0 lists the installed packs' `SubCategory` strings; a string not in this table is reported, not
  guessed.
- `PW.MwBase._InfoFrom(swep)`: `kind = "launcher"` when `UseLauncherLogic == true` or `istable(Explosive)`;
  `"melee"` when the lower-case `SubCategory` is `"melee"`; else `"gun"`. `slot` 2 for category `"pistol"`, 3 for
  melee, else 1. `name` = `PrintName` or the class.
- `PW.MwBase._AnimLength(animations, name)`: case-insensitive lookup; merges a `Base` animation like MW
  (`notes/29 §2.2`); returns `Length / (Fps / 30)` or `nil`.
- `PW.MwBase._StatsFrom(t)`: `damageNear = Bullet.Damage[1]`, `damageFar = Bullet.Damage[2]` (already per trigger
  pull, **not** multiplied by pellets), `rangeNear = Bullet.DropOffStartRange or 0`, `rangeFar = rangeNear +
  Bullet.EffectiveRange` (metres), `rpm = Primary.RPM`, `magazine = floor(Primary.ClipSize)`, `adsTime =
  _AnimLength(Animations, "Ads_In")`, `pellets = Bullet.NumBullets`, `recoil` = mean of `Recoil.Vertical`,
  `spread = Cone.Hip`, `sprintToFire = _AnimLength(Animations, "Sprint_Out")`, `moveMult = nil`. Any non-number
  input gives `nil` for that field.
- `PW.MwBase._OptionStats(base, changed)`: ratios `changed / base` for `damage` (mean of both damage values),
  `range` (`DropOffStartRange + EffectiveRange`), `rpm`, `recoil` (mean vertical), `spread` (`Cone.Hip` share 1,
  `Cone.Ads` share 0.5, product as in ARC9), `adsTime`, `sprintToFire`, `reloadTime` (`_AnimLength` of `Reload`);
  `magazineAdd = changed ClipSize - base ClipSize` when not 0; omit ratios equal to 1; `nil` when empty.
- `PW.MwBase._BotRules(swep)`, `PW.MwBase._FireKind(flags, primary)`: the pure parts of `GetInputRules` and
  `GetFireInfo`.

### 5.1 `Apply(wep, build)`

1. Return `{}` when `wep` is invalid, not MW, or `build` is not a table.
2. `full = wep:Clip1() >= wep:GetMaxClip1()`.
3. For each slot id of `build` in ascending numeric order: `slot = tonumber(id)`; skip when
   `wep.Customization[slot] == nil`. Wanted index: `1` for `false`; for a string, its index in
   `wep.Customization[slot]` (skip when absent). Skip when `wep:GetAttachmentInUseForSlot(slot).Index` already
   equals it. Otherwise spawn one `mg_attachment` exactly as MW's own `CreateAttachmentEntity` does, but with the
   explicit slot and index (MW's helper picks the first slot containing the class, `notes/29 §2.3`): `ents.Create`,
   `SetOwner(wep)`, `SetSlot(slot)`, `SetIndex(index)`, `Spawn()`, `SetPos(wep:GetPos())`, `SetParent(wep)`,
   `wep:DeleteOnRemove(att)`. Each spawn runs MW's own `Attach` and build synchronously on the server.
4. If `full`, `wep:SetClip1(wep:GetMaxClip1())` (a larger magazine is full at spawn, as MW does for a first draw).
5. Read back every slot of `build`: class of `GetAttachmentInUseForSlot(slot)`; `false` when its index is 1 or the
   slot is missing. MW silently reverts disallowed picks to index 1 (`notes/29 §2.3`), so the read-back is the
   answer.

### 5.2 `BotAction`

- `"firemode"`: `n = #wep.Firemodes`; return `false` when `n < 2`; index `arg` when it is an integer in 1..n,
  `nil` → `(wep:GetFiremode() % n) + 1`; then `wep:ApplyFiremode(index)`; return `wep:GetFiremode() == index`.
- `"melee"`: return `false` unless `ply` owns `wep`, `wep:GetAnimation("Melee")` and `wep:GetAnimation("Melee_Hit")`
  exist, and a hull trace (`util.TraceHull`, `MASK_SHOT`, filter `ply`, half-size `Melee.Size` or 2) from
  `ply:EyePos()` along `ply:GetAimVector()` over `Melee.Range` hits a player, NPC or nextbot (same no-whiff rule as
  ARC9); then `wep:TrySetTask("Melee")`; return `wep:HasFlag("Meleeing")`.
- `"safety_off"`: return `true` when `not wep:HasFlag("Lowered")`; else `wep:TrySetTask("Raise")` and return
  `not wep:HasFlag("Lowered")`.
- Anything else: `false`.

## 6. Deck performance profile

### 6.1 Session ConVar sets (all restored on `ShutDown` unless noted)

| Set | Realm | ConVar | Value | Why |
| --- | --- | --- | --- | --- |
| Lock (`LockConVars`, always) | server | `mgbase_sv_customization` | `0` | closes the native menu and the `mgbase_customize_att` receiver (04 d.2) |
| Lock (`LockConVars`, always) | server | `mgbase_sv_customization_limit` | `0` | a host limit above 0 would silently revert gamemode builds |
| HUD (`ClientHudConVars`, always) | client | `mgbase_hud_firemode` | `0` | 09 d.1: the base's HUD is hidden, the crosshair stays |
| HUD (`ClientHudConVars`, always) | client | `mgbase_hud_controls` | `0` | 09 d.1 |

Not set: `mgbase_hud_xhair` (crosshair stays), damage, recoil, range and accuracy multipliers (gameplay; the host's
values stay), `mgbase_sv_aimassist` (§10 question 2), `mgbase_debug_vmrender` and `mgbase_debug_wmrender` (they hide
models, they are not quality options).

### 6.2 `deck` ConVars (`PerfConVars`)

| Realm | ConVar | `deck` value | Default | Class | Estimated impact |
| --- | --- | --- | --- | --- | --- |
| client | `mgbase_fx_blur` | `0` | 0 | must-cut | extra blurred model passes while reloading or scoped; medium when on |
| client | `mgbase_fx_debris` | `0` | 1 | must-cut | debris effects on every explosion; medium during explosions |
| server (replicated) | `mgbase_sv_full_penetration` | `0` | 0 | must-cut (default enforced) | halves penetration traces on magazines over 10 rounds when a host enabled it |
| server (replicated) | `mgbase_debug_range` | `0` | 0 | must-cut | per-hit overlay, console command and timer when on |
| server (replicated) | `mgbase_debug_reverb` | `0` | 0 | must-cut | per-trace overlay when on |
| server (replicated) | `mgbase_debug_projectiles` | `0` | 0 | must-cut | projectile overlay when on |

`off` = empty table for both realms: restore the saved values and delete the backup, then leave MW Base alone.

### 6.3 `deck` per-weapon cuts (`PerfWeaponCuts.deck`)

Applied by the listener `PW.MwBase.Perf` on `OnBuildCustomizedGun` (runs on both realms after every build), through
the pure function `PW.MwBase._PerfCuts(profile, facts)` that returns the list of cuts for one weapon, and a thin
applier. They are re-applied on every build because MW's build copies every class field and function back onto the
instance (`notes/29 §2.3`). They are not ConVars, so nothing is saved or restored: with `off` the next build leaves
the class behaviour.

| Cut id | Realm | Weapons | Change on the instance | `deck` default | Class |
| --- | --- | --- | --- | --- | --- |
| `reverb` | both | all MW weapons | `CreateAndResumeReverbJob` = a no-op function; `LastReverbState = true` | on | must-cut: about 3 long hull traces per tick per armed player, audio only |
| `ricochet` | both | all | `Bullet.Ricochet = false` (when `istable(Bullet)`) and `Secondary.Bullet.Ricochet = false` (when present) | on | must-cut: `ents.FindInSphere` of 1024 units plus an extra bullet per ricochet; follows the `arc9_ricochet 0` precedent |
| `tp_shells` | client | weapons where `not wep:IsCarriedByLocalPlayer()` | `HandleEjection` = a function returning `true` | on | must-cut: other players' shell effects |
| `penetration` | both | all | `Bullet.Penetration.MaxCount = 0` | off until measured (§9.3) | measure-then-decide: gameplay (wall-bangs) |
| `bot_tracers` | server | weapons whose owner `IsBot()` | `FireTracer` = a no-op function | off until measured (§9.3) | measure-then-decide: one reliable net message per pellet to every client; visual check |

Deferred, not implemented in this change: cutting the `mgbase_viewmodelanim` broadcast of bot viewmodels (it may
remove bots' third-person muzzle flashes, `notes/29 §2.4`); decide after the checkpoint answers §9.4 item 4.

Precache: `mgbase_precacheatts` is **not** set in this change. It is measured in §9.2; if adopted later it joins a
`PrecacheConVars` set that is set and never restored, like ARC9's precache pair.

### 6.4 Apply, restore and crash safety

Identical rules to `arc9.perf` (`design/04-weapons.md` d.7, `docs/api/adapter.md` "ARC9 session ConVars"), through
`PW.WeaponConVars`:

- Each realm checks `mwbase.perf` once a second (`RealTime`) and applies only the ConVars of its own realm; nothing
  happens while `MW_ATTS` is missing.
- `deck` first apply: save the current values in the swap and write them to the realm's backup file; set the
  values.
- `off`: restore the saved values, delete the backup, then leave MW Base alone (later player changes stay).
- `ShutDown`: restore lock, HUD and profile; delete the backup.
- First apply of a session with a backup file present (no clean `ShutDown`): restore the file's values first, log
  `[PW] mwbase: restored N MW Base <realm> settings left by a session without ShutDown`, delete the file, then apply.
- A second apply never overwrites the saved originals with profile values.
- A ConVar that does not exist is skipped without error.

### 6.5 `PW.WeaponConVars` (shared helper)

API, all pure over injected `io` and `backup` objects so tests use fakes (same semantics as the ARC9 functions they
generalize):

| Function | Semantics (ARC9 counterpart) |
| --- | --- |
| `Swap(swap, values, on, io)` | `PW.Arc9._SwapConVars` |
| `PerfAction(profile)` | `"apply"` for `"deck"`, `"restore"` for `"off"`, else `"none"` (`_PerfAction`) |
| `PerfValues(profile, values)` | copy of `values` for `"deck"`, else `{}` (`_PerfValues`) |
| `ApplyPerf(swap, profile, values, io, backup)` | `_ApplyPerf` with the realm's table passed in |
| `RestorePerf(swap, values, io, backup)` | `_RestorePerf` |
| `RecoverPerf(swap, values, io, backup)` | `_RecoverPerf`, returns the count restored |
| `FileBackup(path)` | `PerfFileBackup`, with the path passed in (`file.CreateDir("privatewar")`) |
| `InstallPerf(module, opts)` | `_InstallPerf` with `opts = { available = fn, store = swap, values = tbl, setting = "mwbase.perf", backupPath = path, io = io, label = "MW Base", prefix = "mwbase", realm = realm }` |

## 7. Implementation steps (tests first; one commit per step)

Commit messages follow `CLAUDE.md` (`git commit --signoff`, semantic message, trailer `Assisted-by: LLM`). Every
commit passes `nix develop --command make check` before it is made.

0. [ ] **Verify the installed source (no commit).** With Deck permission, read the installed GMA of 2459720887
   (or the extracted `lua/` under the Deck's addons folder) and compare with `notes/29`: every ConVar of
   `notes/29 §4`, `OnBuildCustomizedGun` placement, `CreateAttachmentEntity`, `mg_attachment:Attach`,
   `CreateAndResumeReverbJob`, `FireTracer`, `HandleEjection` lookup, `Bullet.Ricochet`, `Bullet.Penetration`,
   flag names, `GetMaxClip1WithChamber`, `ApplyFiremode`, `Projectile.Speed` units, and the `SubCategory` strings of
   the three packs. Record differences in `notes/29` (new section "Installed version check") and stop if a name in
   §5 or §6 changed.
1. [ ] **Helper tests (red).** `weapons_convars.lua` with the cases of §8.3. Commit
   `test(weapons): cover the shared ConVar swap helper`.
2. [ ] **Helper (green).** `weapons_core/sh_convars.lua`, `types/weapon_convars.lua`, include from
   `weapons_core/shared.lua`. Commit `feat(weapons): add shared ConVar swap and crash-safe backup helper`.
3. [ ] **Addon skeleton and pure MW helpers (red, then green).** Add the pure cases of §8.1 (helpers) to
   `integration_mwbase.lua`; then `addon.json`, `modules/mwbase/shared.lua` (no `sh_perf.lua` yet),
   `types/mwbase.lua`. Two commits: `test(mwbase): cover pure MW Base helpers` and
   `feat(mwbase): add MW Base integration module skeleton`.
4. [ ] **Adapter discovery and stats.** Tests: availability, claims, catalogue. Code: `weapon_adapters/mwbase/shared.lua`
   discovery, stats, slots, options, option stats, state, fire info, input rules. Commit
   `feat(mwbase): add MW Base adapter discovery, stats and slots`.
5. [ ] **Server adapter.** Tests: Apply, conflicting build, two bots, `PrepareForBot`, `BotAction`, lock. Code:
   `weapon_adapters/mwbase/init.lua`, lock in `modules/mwbase/init.lua`. Commit
   `feat(mwbase): apply builds, lock customization and add bot actions`.
6. [ ] **Stat mods.** Test: reload time. Code: listener `PW.MwBase.StatMods` (fields of `notes/12 §3.3`, guarded per
   field) and `RefreshStatMods` with the reloading retry. Commit `feat(mwbase): wire player stat modifiers`.
7. [ ] **HUD set.** Test: client HUD ConVars table and swap (pure). Code: `cl_init.lua` HUD part. Commit
   `feat(mwbase): hide MW Base HUD parts while the gamemode runs`.
8. [ ] **Perf profile (red, then green).** `mwbase_perf.lua` with §8.2; then `sh_perf.lua`, the setting in
   `modules/mwbase/shared.lua`, glue in `init.lua` and `cl_init.lua`, listener `PW.MwBase.Perf`. Two commits:
   `test(mwbase): cover the MW Base deck performance profile` and
   `feat(mwbase): add the MW Base deck performance profile`.
9. [ ] **Docs.** `docs/agent-test-map.md` rows; `notes/29` follow-ups found during implementation. Commit
   `docs(mwbase): map T-3.8 cases and record integration notes`.
10. [ ] **Gates and Deck run** (needs permission): §11, then §9 measurement. Commit the numbers:
    `docs(perf): record MW Base measurements`. Apply measurement decisions (§9.3) as their own commit
    `perf(mwbase): <cut> in the deck profile after measurement`, updating the defaults table test in the same
    commit.
11. [ ] **Hand-off.** Draft the `docs/api/adapter.md` "MW Base session ConVars" subsection text in the final report
    for the orchestrator (do not edit the frozen contract), list pending checkpoint items, and leave
    `changes/` moves to the orchestrator.

## 8. Mandatory test cases

In-game cases need MW Base and at least the Assault Rifles pack; without MW Base they are skipped with one log line,
never passed silently (same rule as `integration_arc9.lua`). Bots are created in `beforeAll` and kicked in
`afterAll` (slot budget, `TASKS.md` "Testing"). Every case that changes a ConVar restores it.

### 8.1 `integration_mwbase.lua` (T-3.8, from `TASKS.md` "T-3.6–T-3.8 Integrations")

| Mandatory clause (`TASKS.md`) | Exact case name |
| --- | --- |
| catalogue lists the pack's weapons with categories | `Catalogue: the pack's weapons are listed with categories and reach the weapons registry` |
| `Apply` on a bot's weapon returns the applied build | `Apply on a bot's weapon returns the applied build` |
| a conflicting build returns what stuck | `Apply with a conflicting build returns what stuck` |
| customization lock is active (the base's own customization path refuses) | `Customization lock: MW Base's own customization paths refuse` |
| stat mods change the server-side value of at least reload time | `Stat mods change the server-side reload time and removal restores it` |
| `PrepareForBot` runs without errors; two bots with different builds of the same class keep different builds | `PrepareForBot runs without errors; two bots keep different builds of the same class` |

Required content of these cases:

- Catalogue: at least one `ar` weapon from 2528829149 is listed with `kind = "gun"`, `slot = 1`, and is in
  `PW.Weapons` after `PW_WeaponsLoaded`.
- Apply: the returned value of a one-slot build equals the requested option, and `GetAttachmentInUseForSlot`
  agrees; `false` returns the slot to index 1.
- Conflict: a build whose second pick is blocked by the first (find a pair through MW's blocker rule at runtime;
  skip with a log line when the pack has none) returns the reverted slot as `false`.
- Lock: `mgbase_sv_customization` is `0` and `mgbase_sv_customization_limit` is `0`; the `Customize` task's
  `CanBeSet(wep)` is `false`; calling the `mgbase_customize_att` receiver from `net.Receivers` with a bot leaves the
  installed attachments unchanged.
- Stat mods: with `reload_time = 0.5` the server value of `wep:GetAnimLength("Reload")` (or the first reload
  animation the weapon has) is half of the base within 1e-6 after the refresh; `{}` restores it.
- Two bots: different options in the same slot of the same class stay different 0.5 s later, and the stored class
  table is unchanged.

Additional cases (same file):

- `Adapter: claims MW Base classes above the fallback; absent MW Base makes it unavailable`
- `Helpers: SubCategory maps to categories; launchers and melee get their kinds and slots`
- `Helpers: animation length is case-insensitive and merges Base animations`
- `Helpers: stats read damage per trigger pull, ranges in metres and timings from animations`
- `Helpers: option stats are ratios of the changed copy and omit unchanged fields`
- `Helpers: fire kind and input rules follow Automatic, BurstRounds, Lowered and UseLauncherLogic`
- `Validate: unknown slot, unknown option and wrong slot are rejected; false is kept`
- `Apply: a larger magazine is full after Apply when the magazine was full before`
- `BotAction: firemode switches to the given index and to the next one; a single-mode weapon refuses`
- `BotAction: melee is refused without a target in reach`
- `HUD: MW Base firemode HUD and control tips are off while the gamemode runs; the crosshair stays`
- `IsHeadshot: the MW head marker answers true, anything else nil`

### 8.2 `mwbase_perf.lua` (modeled on T-11.8)

- `Perf: deck maps exactly to the client and server values of the profile table; off is empty` (client
  `mgbase_fx_blur 0`, `mgbase_fx_debris 0`; server `mgbase_sv_full_penetration 0`, `mgbase_debug_range 0`,
  `mgbase_debug_reverb 0`, `mgbase_debug_projectiles 0`; nothing else)
- `Perf: deck per-weapon cuts are reverb, ricochet and third-person shells; penetration and bot tracers stay off`
- `Perf: mwbase.perf is a host setting in the schema, deck by default, with a description`
- `Perf: deck sets the values of its realm and backs up the originals; off restores, drops the backup`
- `Perf: applying deck twice keeps the player's originals in the swap and the backup`
- `Perf: a missing ConVar (MW Base not installed or another version) is skipped without error`
- `Perf: off leaves MW Base alone after the restore; the player's later changes stay`
- `Perf: ShutDown restores the originals, the lock and the HUD values and deletes the backup`
- `Perf: a backup left without ShutDown restores the originals first, then deck applies again`
- `Perf: the live server ConVars follow the profile, the backup file exists while deck is on` (in-game, MW Base)
- `Perf: per-weapon cuts survive a rebuild and off leaves the class behaviour at the next build` (in-game: after
  `wep:BuildCustomizedGun()` the reverb function is still the no-op and `Bullet.Ricochet` is still `false` under
  `deck`; after switching to `off` and rebuilding, both equal the class values)
- `Perf: third-person shell cut applies only to weapons not carried by the local player` (pure, `_PerfCuts` facts)
- `Perf: bot tracer cut applies only to bot-owned weapons when enabled` (pure)

### 8.3 `weapons_convars.lua`

- `ConVars: Swap saves and sets, then restores, and skips missing ConVars`
- `ConVars: PerfAction maps deck to apply, off to restore and anything else to none`
- `ConVars: ApplyPerf writes the backup once; a second apply keeps the originals`
- `ConVars: RestorePerf restores and removes the backup`
- `ConVars: RecoverPerf restores only known ConVars from the backup and removes it`
- `ConVars: FileBackup reads nothing when the file is missing and an empty table for broken JSON`

## 9. Deck measurement and checkpoint

All Deck steps need fresh permission and a free Deck. Commands run from the repository root.

### 9.1 Install and smoke

```bash
nix develop --command bash scripts/deck/deploy.sh
nix develop --command bash scripts/deck/test.sh
nix develop --command bash scripts/deck/logs.sh --once
```

The first `test.sh` after adding `addons/privatewar-mwbase/` restarts the game when needed (its own rule); the
log must show the adapter line for `mwbase` as available and no `mgbase`/`mwbase` Lua errors.

### 9.2 Baseline and micro-benchmarks

Scenario: `gm_construct`, TDM, `bots.fill` so that there are 9 bots and the idle host, score limit 1000, no time
limit, `deck` profile on, bots holding MW AR or SMG weapons through a dev-bridge timer (as in the ARC9 penetration
run of `docs/perf-report.md`) that gives each living bot an MW AR or SMG with `PW.WeaponAmmo.Give` whenever it holds
anything else.

```bash
nix develop --command bash scripts/deck/cmd.sh "pw_dev_profile start mw_base"
# play or idle for 180 s, then:
nix develop --command bash scripts/deck/cmd.sh "pw_dev_profile stop"
nix develop --command bash scripts/deck/logs.sh --once | grep "profile mw_base"
```

The HL2 comparison run uses the tag `hl2_base` with the preset classes. Each 120 s run of §9.3 uses the same three
commands with its own tag.

Record in `docs/perf-report.md`, section "MW Base (T-3.8)":

1. Server interval avg / p99 / max, server Lua hooks avg / p95 / p99 / max, client frame avg / p99 / max, for the
   MW run and an HL2 run of the same scenario (the ARC9 table layout).
2. Net bytes per second of `mgbase_fire_tracer`, `mgbase_viewmodelanim`, `mgbase_tpanim` (the profiler's net
   table).
3. Micro-benchmarks through `scripts/deck/cmd.sh "lua ..."` with `SysTime()`: first `Give` of each of 6 MW AR
   classes and the next `Give` of the same class; `Apply` of a build with 1, 3 and 5 attachments on a bot's weapon;
   one `wep:BuildCustomizedGun()`.
4. Map load time and the console's model precache warnings with `mgbase_precacheatts 0` and `1` (two map loads),
   restoring the host's value afterwards. Adopting it is a separate decision (§10 question 3).

### 9.3 Measure-then-decide protocol

For each of `penetration` and `bot_tracers`: four 120 s profiles in one match, alternating the cut on, off, on, off
(toggle through `scripts/deck/cmd.sh "lua PW.MwBase.PerfWeaponCuts.deck.<cut> = true|false"` followed by a rebuild
of the bots' MW weapons), tags `mw_<cut>_on1`, `mw_<cut>_off1`, `mw_<cut>_on2`, `mw_<cut>_off2`.

- Cut it in `deck` when, in both pairs, the run without the cut has an average server Lua time at least 0.5 ms
  higher, or a p99 at least 1.0 ms higher, than the run with it (the T-11.8 threshold, with "noticeably" fixed at
  1.0 ms).
- `bot_tracers` additionally needs the human visual check of §9.4 item 5; if bots' fire becomes hard to read, keep
  tracers even above the threshold and record why.
- Write all four rows per cut and the decision into `docs/perf-report.md` in the T-11.8 table format.

### 9.4 Human checkpoint (`CP` items for the local manual checklist)

The user checks on the Deck with `mwbase.perf = deck` unless stated:

1. Firing an MW AR and SMG: sound, recoil, muzzle flash, tracers, shells in first person.
2. Reload, empty reload, ADS in and out, sprint to fire, weapon switch to and from an MW pistol.
3. Gunsmith: MW attachments appear in the loadout UI with names; a saved class spawns with them; the native MW
   customize key does nothing.
4. Bots using MW guns (a player class with MW weapons and `bots.classes` including `players`): bots shoot, reload,
   switch; their muzzle flashes and shells are visible or not (answers `notes/29 §7` question 1).
5. With `bot_tracers` cut on (dev toggle): bots' fire is still readable.
6. Frame rate: TDM with 9 bots for 5 minutes; no hitch when a bot spawns or comes into view; compare `deck` and
   `off` once.
7. Headshot and limb damage feel right (TTK against bots).
8. MW key binds (`mgbase_binds_*` default to the `+grenade1`, `+grenade2`, `+use`, `+reload` keys) do not fight the
   gamemode's lethal (G), tactical (4) and streak keys.
9. Switching `mwbase.perf` to `off` in SETTINGS restores the host's own MW settings; after quitting GMod without a
   clean shutdown (task kill), the next start restores them (log line of §6.4).

## 10. Open questions for the user

1. **Approve the design extension and the per-weapon technique (§2 items 1 and 2)?** Recommended: yes for both.
2. **MW aim assist** (`mgbase_sv_aimassist`, default 1): bots also get MW's hull-trace aim assist while aiming.
   Recommended: leave the host's value alone (not a performance item); revisit after the checkpoint's TTK check.
3. **`mgbase_precacheatts 1`** (moves first-attach model loads to map load, raises precache pressure).
   Recommended: decide after §9.2 item 4; default not set.
4. **Generated MW bot loadouts** (an MW counterpart of `bots_arc9_loadouts`). Recommended: a separate change after
   this one; until then bots use MW guns only through player classes.
5. **Logo** for `addons/privatewar-mwbase/logo.png`. Recommended: reuse the ARC9 integration's logo style; the user
   supplies or approves the image.
6. **Bot build simplification for the Deck** (cap bots' MW builds at 3 non-cosmetic attachments and skip the
   `Lasers` category, to cut client models, draw calls and laser traces). Recommended: decide after §9.2; it belongs
   to the generated-loadout change of question 4, not to this one.

## 11. Gates

- [ ] `nix develop --command make check` passes (lint, types, markdown, rules, agent guides) before every commit and
  before review.
- [ ] `bash -o pipefail -c 'nix develop --command make test 2>&1 | tail -n 80'` passes on the Deck with MW Base and
  the three packs mounted, with every case of §8 present and passing, and the existing suites unchanged and green.
  Without Deck permission, report the test gate and the measurement as skipped and the merge gate incomplete.
- [ ] Deck access only with fresh explicit permission and a free Deck, through the locked scripts.
- [ ] No upstream MW Base code in the tree; `THIRD_PARTY_NOTICES.md` unchanged.
- [ ] PR as draft only after the user approves title and body; merge only with separate approval
  (`gh pr merge --squash --delete-branch`).
