# 33 - TFA Base integration research (T-3.7)

Date: 2026-11-21. Scope: what Private War needs to integrate TFA Base weapons on par with the ARC9 integration
(catalogue, stats, full attachment support, customization lock, unlock levels, bots, Steam Deck performance profile).
Research explains *why*; it is not a decision. Where it disagrees with `design/`, `design/` wins. The change record is
`changes/planned/tfa-integration.md`.

## 0. Sources, versions and evidence labels

| Item | Value | Evidence |
| --- | --- | --- |
| Base | "TFA Base", Workshop [2840031720](https://steamcommunity.com/sharedfiles/filedetails/?id=2840031720), author YuRaNnNzZZ, about 1.45 M subscribers, last update 2026-08-22 (Steam `GetPublishedFileDetails`, `time_updated` 1787376454) | documented |
| Version | `4.7.9.8` (`lua/autorun/tfa_base_autorun.lua:6`); the newest entry of the official changelog is also 4.7.9.8 | verified-in-source |
| Official documentation | <https://github.com/YuRaNnNzZZ/TFA-SWEP-Base-Documentation>, commit `1290ac0` (2026-08-22). Its `lua/tfa/documentation/*.lua` files are byte-identical (md5) to the ones in the source copy below | documented |
| Base source | There is **no official public source repository**. The Workshop item is the canonical distribution; the old `YuRaNnNzZZ/TFA-Base` GitHub URL does not exist (HTTP "Repository not found"). Inspected copy: community mirror `LeRatEmperor/tfa_base_2840031720`, commit `95a5595` (2026-10-19), 147 Lua files | verified-in-source (mirror; see the caveat) |
| Attachment pack (recommended test content) | "TFA Insurgency: Shared Parts", Workshop [2840032487](https://steamcommunity.com/sharedfiles/filedetails/?id=2840032487), same author, about 594 k subscribers, updated 2026-08-20: 9 sights, laser, suppressor, 4 extended magazines, 2 underbarrel launchers, laser and flashlight | documented (Steam API description) |
| Weapon packs (recommended) | `[TFA][AT] MK18` [1243623141](https://steamcommunity.com/sharedfiles/filedetails/?id=1243623141), `[TFA][AT] H&K UMP .45` [1232089571](https://steamcommunity.com/sharedfiles/filedetails/?id=1232089571), `[TFA][AT] Beretta M9` [1304932254](https://steamcommunity.com/sharedfiles/filedetails/?id=1304932254); all "featuring standard INS2 attachments support", by the base author | documented (Steam API descriptions); source not inspected |

Caveat for the mirror: the version string and the documentation match the official release, but the mirror is not
published by the author. Before implementation, the user (or an agent with Deck permission) compares the Deck's
Workshop copy (`garrysmod/addons/` or the Workshop cache, `.gma`) with the file paths cited here; the change record
has that step.

Evidence labels used below: **[src]** verified in the inspected source (path and line), **[doc]** stated by official
documentation or the Workshop page, **[community]** third-party claim, **[assumption]** not verified, with a
verification step. Paths: `T/` = `lua/weapons/tfa_gun_base/`, `TM/` = `lua/tfa/modules/`, `TD/` =
`lua/tfa/documentation/`, `TE/` = `lua/effects/`.

## 1. Architecture

1. Loader `lua/autorun/tfa_base_autorun.lua` loads, in order, `lua/tfa/enums/`, the official modules (a fixed list),
   unofficial modules, `lua/tfa/external/`, then attachments from `lua/tfa/att/` (files with `base` in the name
   first) and `lua/tfa/attbatch/` [src] [doc] (`README.md` of the documentation repository).
2. Global `TFA` (namespace), `TFA_BASE_VERSION`, `TFA_BASE_VERSION_STRING` [src] (`tfa_base_autorun.lua:78-79`).
3. Weapon bases: `tfa_gun_base` (folder, `shared.lua` 2539 lines plus `common/` and `client/`), `tfa_bash_base`,
   `tfa_melee_base` (`IsMelee`), `tfa_knife_base` (`IsMelee`, `IsKnife`), `tfa_sword_advanced_base` (`IsMelee`),
   `tfa_nade_base` (`IsGrenade`), `tfa_bow_base` (`IsBow`) [src] (`lua/weapons/*.lua`).
4. Detection: `SWEP.IsTFAWeapon = true` on the base (`T/shared.lua:12`) [src]; the authors ask to check that flag on an
   instance (`TM/tfa_meta.lua:4-5`) [src]. For a class string use `weapons.IsBasedOn(class, "tfa_gun_base")` (TFA
   itself does, `TM/tfa_hooks.lua:588`) [src]. A stored table of a derived class does not carry the inherited flag.
5. Data versions: `SWEP.TFADataVersion` (template `1`), `TFA.LatestDataVersion = 1` (`TM/tfa_data.lua:4`). Old (M9K
   style) stat paths are remapped to new ones (`TFA.DataVersionMapping`), for example `MoveSpeed` to
   `RegularMoveSpeedMultiplier`, `IronSightsMoveSpeed` to `AimingDownSightsSpeedMultiplier`, `data.ironsights` to
   `Secondary.IronSightsEnabled` [src].
6. Stat pipeline: `wep:GetStatL(path, default)` (`T/common/stat.lua:313-386`) [src]:
   - merges the weapon value with `AttachmentTableCache` (built from the attached attachments' `WeaponTable`);
   - caches per path (`StatCache`, `StatCache2`); `ClearStatCache()` drops it (`stat.lua:79-80`), and
     `BuildAttachmentCache` calls it after every attachment change (`T/common/attachments.lua:220`);
   - **without a valid owner it returns the weapon's own value, without attachments** (`stat.lua:353-364`);
   - calls hook `TFA_GetStat(wep, path, value)` on every read, cached or not; a non-nil return replaces the value
     (`stat.lua:341, 360, 382`). The path passed is the latest-version path.
7. `Initialize` (`T/shared.lua:676`) copies `Primary` into `Primary_TFA`, runs autodetection (damage from
   `Primary.Round`, RPM from `Primary.Delay`, range LUT, spread growth, type, fire modes), then `InitAttachments`
   (`:748`) [src]. Static reads of `weapons.Get(class)` therefore miss autodetected values.

## 2. Stats

| PW field | TFA source (latest path) | Template line (`TD/tfa_base_template.lua`) | Notes |
| --- | --- | --- | --- |
| damage | `Primary.Damage` (per pellet) | 49 | Base default `-1` means autodetect (`T/shared.lua:28`; `T/common/autodetection.lua:225-274`) |
| pellets | `Primary.NumShots` | 44 | |
| rpm | `Primary.RPM`; `Primary.RPM_Semi`, `Primary.RPM_Burst` | 43, 65-66 | Effective delay: `SWEP:GetFireDelay()` (`T/common/utils.lua:515`) |
| magazine | `Primary.ClipSize` | 178 | Capacity with chamber: `GetPrimaryClipSize()` adds 1 (`utils.lua:310-318`); PW `magazine` excludes the chamber |
| ammo | `Primary.Ammo`, `Primary.DefaultClip` | 180-181 | `sv_tfa_default_clip` rewrites stored `DefaultClip` (`TM/tfa_commands.lua:107-159`). **TFA overrides `SWEP:GetPrimaryAmmoType()` to return the ammo name string** (`GetStatL("Primary.Ammo") or ""`, `T/shared.lua:2251-2253`, `T/common/utils.lua:338-344`), not the engine's integer id |
| spread (hip) | `Primary.Spread` | 195 | Less is better |
| spread (ADS) | `Primary.IronAccuracy` | 196 | |
| recoil | `Primary.KickUp`, `Primary.KickDown`, `Primary.KickHorizontal` (degrees), `Primary.StaticRecoilFactor` | 189-192 | `Primary.RecoilLUT*` for LUT weapons (279-350) |
| ADS time | `IronSightTime` | base `0.3` (`T/shared.lua:154`) | Used as `12.5 / (IronSightTime / 0.3)` (`T/common/calc.lua:112`) |
| move speed | `RegularMoveSpeedMultiplier`, `AimingDownSightsSpeedMultiplier` | 391, 398 | ADS default `Regular * 0.8` (`T/shared.lua:753-755`) |
| range | `Primary.RangeFalloffLUT` (`units` meters or hammer) or legacy `Primary.Range`, `Primary.RangeFalloff`, or metric `FalloffByMeter`, `MinRangeStartFalloff`, `MaxFalloff` | 205-240 | Converted at `Initialize` (`autodetection.lua:75-117`); legacy end damage is `1 - sv_tfa_range_modifier` (default 0.5) |
| sprint to fire | none | | Sprint progress approaches its target at a constant rate 7.5 (`calc.lua:76-78`); fire is blocked while `SprintProgress >= 0.1` (`T/shared.lua:1528`). Exponential approach: about `ln(10) / 7.5 = 0.31` s for every weapon [src, arithmetic] |
| reload time | animation length (`GetActivityLength`, `utils.lua:149-195`) or `ProceduralReloadTime` | 671-672 | Not a static number for animated weapons |

- `SWEP:MetersToUnits(x)` is `x * 39.3701 * 4 / 3` (`utils.lua:18-20`) [src], unlike the LUT `units = "meters"` path
  (39.37); never mix the two.
- Weapon type: `SWEP.Type` (template 38) or `SWEP:GetType()` autodetection (`autodetection.lua:543-666`) [src]: in
  order projectile (Launcher or Grenade), `buckshot` ammo (Shotgun), Pistol, Sub-Machine Gun, Revolver, scoped and
  under 600 RPM or `SniperPenetratedRound` (Designated Marksman Rifle or Sniper Rifle), holdtype `pistol` (Machine
  Pistol or Pistol), `duel` (Dual ...), `ar2` ammo (Light Machine Gun at 60+ rounds, Carbine, Rifle), SMG, Melee, Bow,
  else `Weapon`. `GetType` is an instance method; a static catalogue needs its own pure mirror of these rules.

## 3. Attachments

### 3.1 Data model

- Per weapon: `SWEP.Attachments[category] = { atts = { ids }, sel = index-or-id, default = id, hidden = bool,
  order = n }` (`TD/tfa_base_template.lua:902-916`; base default `{}` at `T/common/attachments.lua:5`) [src] [doc].
  A category has **no name**: it is a number (or, in CW2-style packs, a model attachment name, see 3.3).
  - `sel`: pre-selected index or id; `default`: id equipped when the category is cleared (`attachments.lua:402-404`);
    `hidden`: hidden from the selector, "does not prevent attachments to be selected through other means" [doc].
- `SWEP.AttachmentDependencies = { [id] = "other" | { ids..., type = "OR"|"AND" } }`,
  `SWEP.AttachmentExclusions = { [id] = { ids } }` (made symmetric on first `CanAttach`, `attachments.lua:247-263`),
  `SWEP.AttachmentTableOverride = { [id] = WeaponTable }` (per-weapon override of an attachment's stats) [src].
- Registry: `TFA.Attachments.Atts[id] = ATTACHMENT` (`TM/tfa_attachments.lua:2, 290`) [src].
  - Files `lua/tfa/att/<id>.lua` (id = lower-case file name) and batches `lua/tfa/attbatch/*.lua` calling
    `TFA.Attachments.RegisterFromTable(id, tbl)` (`:293-309`) [src] [doc].
  - Inheritance through `ATTACHMENT.Base` (default `"base"`), resolved by `patchInheritance` after loading
    (`:319-354, 418-424`) [src].
  - `TFAUpdateAttachments()` **replaces** the `Atts` table (`:363`); it runs on load and on
    `sv_tfa_attachments_reload` (`:439-443`), which also broadcasts `TFA_Attachment_Reload` [src]. A cache keyed by
    `tostring(TFA.Attachments.Atts)` plus its count changes when attachments reload.
  - Hooks around loading: `TFABase_ShouldLoadAttachment` (return false to skip), `TFABase_PreBuildAttachment`,
    `TFABase_BuildAttachment`, `TFABase_RegisterAttachment`, `TFAAttachmentsLoaded`, `TFAAttachmentsInitialized`
    [src] [doc] (`TD/tfa_hooks_custom.lua:57-107`).
- Attachment fields (`TD/tfa_attachment_template.lua`) [doc]: `Name`, `ShortName`, `Description` (colour and text
  pairs), `Icon` (png path), `WeaponTable` (stat replacements), `TFADataVersion`, optional `CanAttach(wep)`,
  `CanDetach(wep)`, `Attach(wep)`, `Detach(wep)`, `RTCode`, `CustomBulletCallback`, stencil sight hooks.
- **Stat effects are not deltas.** A `WeaponTable` leaf is either an absolute value that replaces the stat, or a
  function `fn(wep, stat) -> value` that receives the weapon's current value (`attachments.lua:122-187`;
  `TD/tfa_attachment_template.lua` `ClipSize` example) [src] [doc]. The bundled suppressor uses
  `function(wep, stat) return stat * 0.95 end` for damage and `* 0.9` for kicks and spread
  (`lua/tfa/attbatch/0_base_attachments.lua:135-140`) [src]. Functions may read `wep.Primary_TFA` (the original
  values) [doc]. A static stat estimate must evaluate these functions against the class's own base value, protected
  by `pcall`, and treat anything that is not a finite number as unknown.
- Visual-only changes live in the same `WeaponTable`: `ViewModelElements`, `WorldModelElements`, `Skin`,
  `MaterialTable`, `MaterialTable_V`, `MaterialTable_W`, `ViewModelBodygroups`, `WorldModelBodygroups` (bundled
  suppressor, `0_base_attachments.lua:125-134`) [src]. TFA has **no cosmetic flag** and no camo system; reskins are
  ordinary attachments (the UMP .45 and M9 pages credit "reskin attachments Lua code") [doc].
- Bundled attachments in the base: `am_gib`, `am_magnum`, `am_match`, `sg_frag`, `sg_slug`, `br_supp`, `si_acog`,
  `si_aimpoint`, `si_eotech` (batch) and `si_rt_base` (RT scope base) [src]. Pack prefixes such as `ins2_si_*`
  are **[assumption]**; list the installed ids on the Deck before writing role heuristics.

### 3.2 Applying and removing attachments

- `wep:SetTFAAttachment(cat, id, nw, force)` (`T/common/attachments.lua:387-457`) [src]:
  - `id` is an index into `atts`, an id string (resolved with `table.KeyFromValue`), `""` or `<= 0` to clear;
  - clearing a category with a `default` equips the default instead (`:402-404`);
  - **on the server only**, without `force`, it calls `CanAttach` for an attach and `CanAttach(old, true)` for a
    detach (`:408-409`); the client never checks;
  - detaches the old attachment (`ATTACHMENT:Detach`, hook `TFA_Attachment_Detached`), attaches the new one
    (`ATTACHMENT:Attach`, hook `TFA_Attachment_Attached`), stores `sel`, rebuilds the cache (`BuildAttachmentCache`,
    which also clears the stat and material caches) and runs `ForceAttachmentReqs`, which **force-detaches**
    attachments whose dependencies or exclusions no longer hold (`:325-374, 445-446`);
  - with `nw` on the server it sends `TFA_Attachment_Set` to the PVS (`TFA.Attachments.NetworkAttachmentToPVS`;
    a Player passed as `nw` is left out) (`:448-454`; `TM/tfa_attachments.lua:39-56`);
  - returns `true` when the call completed, `false` for an unknown category or option or a refused check.
- `wep:Attach(id, force)` and `wep:Detach(id, force)` find the category and call `SetTFAAttachment(..., true, force)`
  (`attachments.lua:460-481`) [src].
- `CanAttach(id, detaching)` order (`attachments.lua:234-321`) [src]:
  1. hook `TFA_PreCanAttach(wep, id)` or `TFA_PreCanDetach(wep, id)`: **any non-nil return is the answer**;
  2. `sv_tfa_attachments_enabled 0` refuses everything;
  3. exclusions (attach only), dependencies (attach only, `OR` default or `AND`);
  4. `ATTACHMENT:CanAttach(wep)` or `ATTACHMENT.CanDetach(wep)`;
  5. hook `TFA_CanAttach` or `TFA_CanDetach`: a non-nil return overrides.
- `force = true` skips **all** of the above, including exclusions and dependencies.
- Lifecycle (`InitAttachments`, `attachments.lua:502-570`) [src], called from `Initialize` and again from `Think2`
  (guarded by `HasInitAttachments`):
  1. hook `TFA_PreInitAttachments`;
  2. a **string** category key is looked up as a model attachment (viewmodel when valid, else world model); found:
     moved to that numeric index; not found: the category is deleted (`:507-515`);
  3. each pre-selected `sel` is cleared and re-applied in `timer.Simple(0)` with `SetTFAAttachment(k, sel, false)`:
     no `force`, so on the server it goes through `CanAttach`, and no network message (`:543-562`);
  4. hooks `TFA_PostInitAttachments`, `RemoveUnusedAttachments` (drops ids missing from the registry and empty
     categories, `:15-35`), `BuildAttachmentCache`, `TFA_FinalInitAttachments`;
  5. on the client, `RestoreAttachments` applies the player's saved choices (see 3.4).
- The alphabetical-order branch at `:516` reads `(not cvar) and cvar:GetBool()`, so it never runs while the ConVar
  exists [src]: option order is the pack's `atts` order.

### 3.3 Category ids on a live weapon versus the class

- Numeric category keys survive unchanged; string keys are remapped to a model attachment index per realm and per
  model (viewmodel on the owning client, world model on the server when no viewmodel is valid) [src]. The network
  messages carry the numeric category (`categoryBits = 8`, `TM/tfa_attachments.lua:20-22`), so a string-keyed
  category can resolve to different numbers on server and client. Recommendation: offer only numeric categories,
  count and log skipped string categories. Index `0` is not a valid model attachment, so numeric keys start at 1.
- The 8-bit category field caps category numbers at 255 [src].

### 3.4 Networking and client persistence

- Server to clients: `TFA_Attachment_Set` (entity, category, id) to the PVS on every networked change; clients that
  enter the PVS later send `TFA_Attachment_Request` (on `NotifyShouldTransmit`, `NetworkEntityCreated`,
  `OnEntityCreated`, once per entity) and the server answers with every numeric category of that weapon
  (`TM/tfa_attachments.lua:58-87, 169-195`) [src]. A message for an entity the client does not know yet reads a NULL
  entity and is ignored (`:138-147`); the request after creation repairs it [src, inference from the code paths].
- Client to server: `TFA_Attachment_Set` carrying the **class name**, category and id; the server resolves the weapon
  with `ply:GetWeapon(class)` (only the sender's own weapon) and calls `SetTFAAttachment(cat, id, ply)`: no `force`,
  so `CanAttach` runs, and no check of the customization state or of `sv_tfa_cmenu`; it answers
  `TFA_Attachment_SetStatus`, and on refusal the client reverts and plays `buttons/button2.wav`
  (`TM/tfa_attachments.lua:89-115, 153-167`) [src]. No rate limit on this message [src].
- Persistence: with `cl_tfa_attachments_persist_enabled 1` (default) the client stores its choice per class in SQLite
  table `tfa_savedattachments` and, in `InitAttachments`, re-applies it locally with `force = true, nw = true`, which
  sends one `TFA_Attachment_Set` per saved category (`attachments.lua:572-586`; `TM/tfa_attachments.lua:130-136,
  197-220`) [src].

### 3.5 Customization menu

- The menu is the inspection screen, opened by `ToggleInspect` (`T/shared.lua:2255-2275`, alias `ToggleCustomize`)
  through impulse `148` (`TFA.INSPECTION_IMPULSE`, `TM/tfa_hooks.lua:3, 256-257`) [src]. Paths that send the
  impulse: the context-menu key when `sv_tfa_cmenu 1` (`TM/tfa_hooks.lua:194, 223-225`), the `customize` key bind
  (`TM/tfa_keybinds.lua:178-185`, **not** gated by `sv_tfa_cmenu`), or a manual `impulse 148` [src].
- The panel is built in `SWEP:GenerateInspectionDerma` (`T/client/hud.lua:858`); hook
  `TFA_InspectVGUI_Start(wep)` returning `false` prevents creation (`:859`), and `TFA_InspectVGUI_AttachmentsStart`
  returning `false` hides only the attachment picker (`:632`, which also requires `sv_tfa_attachments_enabled`)
  [src] [doc].
- Conclusion: `sv_tfa_cmenu 0` alone does not close the menu, and the menu is cosmetic anyway: the authority is the
  server-side `CanAttach`. A complete lock is (a) server `TFA_PreCanAttach` and `TFA_PreCanDetach` returning `false`
  outside the adapter's own apply, (b) client `TFA_InspectVGUI_Start` returning `false`, (c) `sv_tfa_cmenu 0` for the
  key path and `cl_tfa_attachments_persist_enabled 0` so restored choices do not produce refused requests.
- Trap for (a): a blanket `false` also refuses the class's own pre-selected `sel` on the server (3.2 step 3) while the
  client applies it, so client and server disagree unless the server applies every category itself. The change record
  resolves this with a short "defaults pending" window per weapon plus an explicit full build in `Apply`.

## 4. Hooks relevant to the integration

All shared unless noted [doc] (`TD/tfa_hooks_custom.lua`, lines in brackets) and [src] where cited above.

| Hook | Use |
| --- | --- |
| `TFA_PreCanAttach`, `TFA_PreCanDetach` (480-522) | customization lock (server) |
| `TFA_CanAttach`, `TFA_CanDetach` | not needed |
| `TFA_Attachment_Attached`, `TFA_Attachment_Detached` (500, 532) | optional diagnostics |
| `TFA_PreInitAttachments`, `TFA_PostInitAttachments`, `TFA_FinalInitAttachments` (459-473) | "defaults pending" marker |
| `TFA_GetStat` (117) | stat modifiers (`ads_time`, `recoil`, `spread`, procedural reload and holster times) |
| `TFA_AnimationRate` (580; called at `T/common/anims.lua:375`) | stat modifiers (`reload_time`, `draw_time`) |
| `TFA_InspectVGUI_Start`, `TFA_InspectVGUI_AttachmentsStart` (client, 819, 875) | menu lock |
| `TFA_MakeShell`, `TFA_EjectionSmoke`, `TFA_MuzzleSmoke`, `TFA_MuzzleFlash` (599-626) | optional perf trims; a non-nil return skips the effect (`T/common/effects.lua:101-105, 188-192, 232-236, 253-257`) [src] |
| `TFA_Bullet_Penetrate` (350; `T/common/bullet.lua:642`) | returning `false` stops penetration of that bullet |
| `TFA_DrawCrosshair`, `TFA_DrawHUDAmmo` (client) | optional |
| `HUDShouldDraw` with names `TFA_HUDAmmo`, `TFA_HUDFallback` (client) | hide TFA's ammo HUD without a ConVar (`T/client/hud.lua:1081, 1106`) [src] |
| `TFA_PreCanPrimaryAttack` (268) | not needed |

Notes on `TFA_GetStat`: hook results are first-non-nil, so another addon's handler for the same path may win; TFA
itself registers `TFA_IronsightsConVarToggle` for `data.ironsights` and `Secondary.IronSightsEnabled`
(`TM/tfa_commands.lua:306-312`) [src]. The hook fires on every stat read (hundreds per frame): a handler must return
early on a table lookup of the path (`notes/12` §4.2).

## 5. Bullets, recoil and damage

- Hitscan by default; `Primary.Projectile` spawns an entity; TFA ballistics (simulated bullets) only with
  `sv_tfa_ballistics_enabled 1` (default `0`) or a weapon's `UseBallistics` (`T/common/bullet.lua:125-176`;
  `TM/tfa_ballistics.lua:61-69`) [src].
- Penetration: `MainBullet:Penetrate` (`bullet.lua:641-...`) runs per hit: door handling, hitmarker net message,
  ricochet roll, then up to `min(sv_tfa_penetration_hardlimit (100), Primary.MaxSurfacePenetrationCount)` extra
  surfaces, each with one to three `util.TraceLine` calls (`:732-815`) and a new bullet (`:900-940`) [src]. Off with
  `sv_tfa_bullet_penetration 0` (`:731`) or per bullet with `TFA_Bullet_Penetrate` returning `false`.
- Ricochet: `sv_tfa_bullet_ricochet` (default `0`) (`bullet.lua:989-...`) [src].
- Doors: bullets and melee can shoot doors off their hinges (`sv_tfa_bullet_doordestruction 1`,
  `sv_tfa_melee_doordestruction 1`, respawn never by default), creating physics props [src].
- Damage randomisation: `sv_tfa_damage_mult_min 0.95`, `sv_tfa_damage_mult_max 1.05` (`bullet.lua:48-49`) [src];
  this varies time to kill by up to 10 %.
- Recoil (`bullet.lua:360-437`) [src]: random kick between `KickDown` and `KickUp`, horizontal within
  `KickHorizontal`, scaled by `sv_tfa_recoil_mul_p/_y`; on the server `owner:ViewPunch` plus the weapon's NW
  `ViewPunchP/Y`; `SetEyeAngles` only in singleplayer or on the predicting client. The server bullet direction adds
  the weapon's `ViewPunchP/Y` or the recoil LUT angle (`T/common/utils.lua:1178-1192`) [src], so recoil does deflect
  bot shots.
- Jamming: on by default (`sv_tfa_jamming 1`, `SWEP.CanJam = true` in the template, `JamChance 0.04`,
  `JamFactor 0.06`); a jammed weapon refuses to fire and a reload clears it even with a full magazine
  (`T/shared.lua:77-78, 1558, 1912-1929, 2305-2350`) [src].
- No headshot multiplier outside TTT, no kill icons, hitmarker sent with `net.Send` to the shooter (`notes/08` §4.5;
  `SendHitMarker`, `utils.lua:967`) [src].

## 6. Effects and rendering

| Effect | Mechanism | Control |
| --- | --- | --- |
| Shell casings | Lua effect `tfa_shell` with `PhysicsInitBox`, alive `cl_tfa_fx_ejectionlife` seconds (default 15); `LifeTime <= 0` removes it at once (`TE/tfa_shell/init.lua:31, 55-59, 82-86, 114`) [src] | `cl_tfa_fx_ejectionlife`, `cl_tfa_legacy_shells`, hook `TFA_MakeShell` |
| Ejection smoke | `tfa_shelleject_smoke` | `cl_tfa_fx_ejectionsmoke` |
| Muzzle flash | Server sends unreliable `tfa_base_muzzle_mp` to everyone except the shooter for **every shot** (`T/common/effects.lua:284-294`; `TM/tfa_netcode.lua:115-121`); the client creates the flash effect, which uses a `DynamicLight` (`lua/tfa/muzzleflash_base.lua:11, 58-67`) [src] | no ConVar; hook `TFA_MuzzleFlash` (skipping it hides shooters, a gameplay change) |
| Muzzle smoke | `tfa_muzzlesmoke`, smoke trail | `cl_tfa_fx_muzzlesmoke`, `_limited`, `cl_tfa_fx_muzzleflashsmoke` |
| Impacts | custom impact effects, ricochet sparks (`T/client/effects.lua:129`; `TE/tfa_ricochet`) | `cl_tfa_fx_impact_enabled`, `cl_tfa_fx_impact_ricochet_*` |
| RT scopes | `PreRender` hook `TFASCREENS` pushes a render target of `ScrH() / 2^quality` pixels every frame while the active weapon has `RTDrawEnabled` or `RTCode` (`TM/cl_tfa_rendertarget.lua:30-140`); the base RT sight re-renders the scene with `render.RenderView` only while ADS progress is above 0.005 (`lua/tfa/att/si_rt_base.lua:80-82`) [src]. Pack RT sights may differ [assumption] | `cl_tfa_3dscope_quality` (0 full to 3 eighth); `cl_tfa_3dscope` is marked "[IGNORED]" |
| RT scope background blur | `PostDrawTranslucentRenderables`: mode 1 runs `cl_tfa_fx_rtscopeblur_passes` (3) full-screen `UpdateScreenEffectTexture` blur passes, mode 2 a bokeh pass with the depth texture (`TM/cl_tfa_rtbgblur.lua:7-60`) [src] | `cl_tfa_fx_rtscopeblur_mode` (0 = none), `_passes`, `_intensity` |
| Stencil sights | `PostDrawViewModel`, `PostDrawPlayerHands` (`TM/cl_tfa_stencilsights.lua:362-367`) | none (cheap) |
| ADS depth of field, gas blur | `cl_tfa_vm_blur.lua`; `TFA_AllowDoFDraw` | `cl_tfa_fx_ads_dof`, `_hd`, `cl_tfa_fx_gasblur` (all default 0) |
| Inspection bokeh | `NeedsDepthPass` while inspecting (`TM/cl_tfa_inspection.lua:58-62`) | `cl_tfa_inspection_bokeh` (default 0) |
| View and gun bob | `cl_tfa_viewbob_*`, `cl_tfa_gunbob_*` | cosmetic, small cost |
| Laser trails | | `cl_tfa_laser_trails` |
| World models | `SWEP:DrawWorldModel` calls `ply:SetupBones()` and invalidates bone caches **on every draw** (the code comments "this tanks FPS"), then draws world elements (`T/client/mods.lua:613-667`) [src] | none |
| World model culling | `sv_tfa_worldmodel_culldistance` is created but **never read** (`TM/tfa_commands.lua:255-257`; repository-wide grep) [src] | none (setting it does nothing) |

## 7. Sounds

- Weapon sounds are soundscripts (`TM/tfa_soundscripts.lua`); the default sound character is `)` (spatial stereo)
  (`TM/tfa_functions.lua:51`) [src].
- `sv_tfa_soundscale` scales pitch with the timescale; `sv_tfa_nearlyempty` plays low-ammo sounds; dry fire with
  `sv_tfa_allow_dryfire` [src]. None of them is a performance lever.

## 8. Bots (Player bots driven through `CUserCmd`)

| Path | Effect on a bot | Shim (PW) |
| --- | --- | --- |
| ADS from `IN_ATTACK2` edges in `FinishMove` (`TM/tfa_hooks.lua:246-316`) [src] | `GetInfoNum("cl_tfa_ironsights_toggle", 0)` and `_resight` read 0 for a bot (no client ConVars), so a bot holds to aim and does not re-aim after reload or sprint; humans default to toggle (`TM/cl_tfa_commands.lua:70, 74`) [src] [assumption: `GetInfoNum` on bots returns the default] | hold `IN_ATTACK2`; re-press after reload |
| Reload on **release** of `IN_RELOAD` within 0.3 s, only without `IN_USE`; holding longer runs `CheckAmmo` (`TM/tfa_hooks.lua:320-332`) [src] | a held key never reloads | `reloadTap = true`, `reloadTapMax = 0.3` (already implemented by the bot input writer, `modules/bots_input/shared.lua:13-14, 103`) |
| `sv_tfa_reloads_legacy 1` switches to the press rule (`:321-323`) [src] | tap rule then wrong | read the ConVar in `GetInputRules` |
| `IN_USE` + attack or reload combos via key binds (`notes/08` §4.6) | silencer toggle, fire mode | `forbidWithAttack = forbidWithReload = IN_USE` |
| Sprint blocks fire while `SprintProgress >= 0.1` (`T/shared.lua:1528`) [src] | | `noSprintWhileFiring = true`, `sprintToFire = 0.31` |
| Fire modes: `FireModes` strings, `GetFireMode()` NW int, `IsFireModeAutomatic()`, `GetMaxBurst()`, `IsSafety()`, `CycleFireMode()` (`utils.lua:570-581, 799-859, 1251-1262`); the impulse path also needs `SelectiveFire`; `CycleFireMode` never selects the last mode (safe) [src] | | `BotAction("firemode")` calls `CycleFireMode` on the server |
| Bash: impulse 149 or `IN_ZOOM` converted by the `StartCommand` hook `TFABashZoom` (`TM/tfa_hooks.lua:343-366`), `AltAttack` [src] | a gamemode writing the cmd in `GM:StartCommand` runs after the hook (`notes/08` §7.6) | `BotAction("melee")` deferred (open question) |
| `PrimaryAttack` returns early for a player without a valid viewmodel (`T/shared.lua:1744`); reload and deploy also use `VMIV` (`:857, 1908`) [src] | a bot without a server viewmodel cannot fire or reload | [assumption] bots have one (engine creates a viewmodel per player); first in-game case |
| Jamming (section 5) | a jammed bot "fires" nothing | `CanFireNow` false while jammed so the bot reloads, or disable jamming (open question) |
| Recoil deflects the server shot (section 5) | | `GetRecoil().affectsBotAim = true` |
| `Holster` waits for its animation, then `SelectWeapon` (`notes/08` §4.6) | | `reselectEveryTick = true` |
| NPC attachment randomisation only for NPC owners (`T/init.lua:103-113`) [src] | not for bots | none |

## 9. Known performance issues

1. Per-shot muzzle net message and dynamic light for every other shooter (section 6) [src].
2. Shell physics effects live 15 s each by default (section 6) [src].
3. RT scope background blur: three full-screen passes per frame while an RT scope is aimed (section 6) [src].
4. `DrawWorldModel` forces `SetupBones` on every TFA world model draw (section 6) [src].
5. `TFA_GetStat` fires on every stat read; slow handlers multiply (`notes/12` §4.2) [src].
6. Penetration can chain up to 100 surfaces per bullet with up to three traces each (section 5) [src].
7. Community forks claim excess hook work, allocations, network operations and a heavy startup precache in older
   builds ([TFA-Base-Optimized](https://github.com/Etherinus/TFA-Base-Optimized),
   [KenTFA](https://github.com/kentovka/KenTFA)) [community]. Not used by Private War (the user installs the official
   base); listed only as a pointer for measurement.
8. First `Give` of a class: unmeasured. ARC9 stalled 0.3 to 0.6 s per class (`docs/perf-report.md`, "ARC9"); TFA
   has no precache ConVar [src]. Measure before deciding on a precache step [assumption].

## 10. ConVar inventory

Realm: **S** = `CreateConVar` on both realms with `FCVAR_REPLICATED`, archived on the server (TFA's
`CreateReplConVar`, `TM/tfa_commands.lua:1-3`, `TM/tfa_ballistics.lua:57-59`); set on the server. **C** = client
ConVar (`CreateClientConVar`; archived unless noted). Impact: perf impact on the Steam Deck (H high, M medium, L low,
none) and whether gameplay changes (G). Recommendation keys: **deck** = part of the `deck` profile; **lock**,
**hud** = session sets; **ask** = gameplay question for the user; blank = leave alone.

### 10.1 Server (replicated) ConVars

| ConVar | Default | Meaning | Impact | PW |
| --- | --- | --- | --- | --- |
| `sv_tfa_soundscale` | 1 | pitch follows timescale | none | |
| `sv_tfa_weapon_strip` | 0 | remove empty weapons | G | |
| `sv_tfa_spread_legacy` | 0 | legacy spread | G | |
| `sv_tfa_cmenu` | 1 | allow the context-menu key for the inspection menu | none | lock: 0 |
| `sv_tfa_cmenu_key` | -1 | override the menu key | none | |
| `sv_tfa_range_modifier` | 0.5 | max damage loss of the legacy range | G | |
| `sv_tfa_allow_dryfire` | 1 | dry fire | none | |
| `sv_tfa_penetration_hardlimit` | 100 | max surfaces a bullet penetrates | M, G | measure (candidate 2) |
| `sv_tfa_bullet_penetration_power_mul` | 1 | penetration power | L, G | |
| `sv_tfa_penetration_hitmarker` | 1 | hitmarker for penetrating hits | L | |
| `sv_tfa_damage_multiplier`, `sv_tfa_damage_multiplier_npc` | 1, 1 | damage multipliers | G | |
| `sv_tfa_damage_mult_min`, `sv_tfa_damage_mult_max` | 0.95, 1.05 | random damage factor | G | ask: 1, 1 |
| `sv_tfa_melee_damage_npc`, `sv_tfa_melee_damage_ply` | 1, 0.65 | melee multipliers | G | |
| `sv_tfa_melee_blocking_timed`, `_anglemult`, `_deflection`, `_stun_enabled`, `_stun_time` | 1, 1, 1, 1, 0.65 | melee blocking | G | |
| `sv_tfa_melee_doordestruction` | 1 | bash doors open | L, G | ask: 0 |
| `sv_tfa_door_respawn` | -1 | door respawn time | G | |
| `sv_tfa_npc_randomize_atts` | 1 | NPC attachment randomisation | none (NPCs only) | |
| `sv_tfa_default_clip` | -1 | rewrites stored `DefaultClip` | none (PW gives ammo) | |
| `sv_tfa_unique_slots` | 1 | unique selection slots | none | |
| `sv_tfa_spread_multiplier` | 1 | spread | G | |
| `sv_tfa_force_multiplier`, `sv_tfa_knockback_multiplier` | 1, 1 | arrow force, knockback | G | |
| `sv_tfa_recoil_multiplier` | 1 | recoil | G | |
| `sv_tfa_dynamicaccuracy` | 1 | crouch and jump accuracy | G | |
| `sv_tfa_ammo_detonation`, `_mode`, `_chain` | 1, 2, 1 | shootable ammo boxes | L | |
| `sv_tfa_scope_gun_speed_scale` | 0 | sensitivity by speed | none | |
| `sv_tfa_bullet_penetration` | 1 | penetration | M, G | measure |
| `sv_tfa_bullet_doordestruction`, `_keep` | 1, 0 | shoot doors off | L, G | ask: 0 |
| `sv_tfa_npc_burst` | 0 | NPC bursts | none | |
| `sv_tfa_bullet_ricochet` | 0 | ricochet | M, G | deck: 0 (pin) |
| `sv_tfa_bullet_randomseed` | 0 | extra server seed | G | |
| `sv_tfa_debug` | 0 | debug | L | |
| `sv_tfa_holdtype_dynamic` | 1 | dynamic hold types | none | |
| `sv_tfa_arrow_lifetime` | 30 | arrow lifetime | L | |
| `sv_tfa_worldmodel_culldistance` | -1 | never read | none | do not set |
| `sv_tfa_reloads_legacy` | 0 | press-to-reload | G (bot input) | read by the adapter |
| `sv_tfa_recoil_legacy` | 0 | legacy recoil | G | |
| `sv_tfa_recoil_mul_p`, `_y`, `_p_npc`, `_y_npc` | 1 | kick multipliers | G | |
| `sv_tfa_recoil_viewpunch_mul`, `sv_tfa_recoil_eyeangles_mul` | 1, 1 | recoil split | G | |
| `sv_tfa_fx_penetration_decal` | 1 | exit decals | L (client decals) | deck: 0 |
| `sv_tfa_ironsights_enabled` | 1 | iron sights | G | |
| `sv_tfa_sprint_enabled` | 1 | sprint blocks fire | G | |
| `sv_tfa_reloads_enabled` | 1 | reloading | G | |
| `sv_tfa_attachments_enabled` | 1 | attachment picker and `CanAttach` | G | lock: 1 (the apply path needs it) |
| `sv_tfa_attachments_alphabetical` | 0 | dead code path (3.2) | none | |
| `sv_tfa_jamming`, `_mult`, `_factor`, `_factor_inc` | 1, 1, 1, 1 | jamming | G | ask: 0 |
| `sv_tfa_nearlyempty` | 1 | low-ammo sounds | none | |
| `sv_tfa_fixed_crosshair` | 0 | centred crosshair | none | |
| `sv_tfa_crosshair_showplayer`, `_showplayerteam` | 1, 1 | crosshair colour shows aimed players and teams | G | ask (keep) |
| `sv_tfa_weapon_weight` | 1 | move speed multipliers | G | |
| `sv_tfa_fov_sprintmod` | 1 | sprint FOV | none | |
| `sv_tfa_first_draw_anim_enabled` | 1 | first draw animation | G (time) | |
| `sv_tfa_backcompat_patchswepthink` | 1 | patch old `Think` overrides (`TM/tfa_hooks.lua:579`) | none | |
| `sv_tfa_envcheck` | 1 | environment warnings (`TM/tfa_envcheck.lua:5`) | none | |
| `sv_tfa_ttt_patch_weapons` | 1 | TTT only (`TM/tfa_tttpatch.lua:3`) | none | |
| `sv_tfa_nz_melee_scaling`, `_multiplier`, `_immunity` | 1, 0.65, 0.67 | nZombies only (`TM/tfa_nzombies.lua:15-17`) | none | |
| `sv_tfa_ballistics_enabled` | 0 | simulated bullets | H, G | deck: 0 (pin) |
| `sv_tfa_ballistics_bullet_life`, `_damping_air`, `_damping_water`, `_velocity`, `_substeps`, `_custom_gravity`, `_custom_gravity_value`, `_mindist` | 10, 1, 3, 1, 1, 0, 0, -1 | ballistics tuning (`TM/tfa_ballistics.lua:61-69`) | only with ballistics | |

### 10.2 Client ConVars (`TM/cl_tfa_commands.lua` unless noted)

| ConVar | Default | Meaning | Impact | PW |
| --- | --- | --- | --- | --- |
| `cl_tfa_inspection_bokeh`, `_radius` | 0, 0.1 | inspection DOF | M when on | deck: 0 (pin) |
| `cl_tfa_inspect_hide_in_screenshots`, `cl_tfa_inspect_hide` (not archived), `cl_tfa_inspect_hide_hud`, `cl_tfa_inspect_newbars`, `cl_tfa_inspect_spreadinmoa` | 0 | inspection panel options | none | |
| `cl_tfa_viewbob_intensity`, `cl_tfa_gunbob_intensity`, `cl_tfa_gunbob_custom`, `cl_tfa_gunbob_invertsway`, `cl_tfa_viewbob_animated` | 1, 1, 1, 0, 1 | bob | L | |
| `cl_tfa_3dscope_quality` | 0 | RT size `ScrH / 2^q` | H with RT sights | deck: 1 (measure 2) |
| `cl_tfa_3dscope` | 1 | "[IGNORED]" except the blur gate | none | |
| `cl_tfa_scope_sensitivity_3d`, `_autoscale`, `cl_tfa_scope_sensitivity` | 2, 1, 100 | scope sensitivity | none | |
| `cl_tfa_3dscope_overlay` | 0 | 3D scope shadows | L | deck: 0 (pin) |
| `cl_tfa_ironsights_toggle`, `_resight`, `_responsive`, `_responsive_timer` | 1, 1, 0, 0.175 | ADS input (userinfo) | none | |
| `cl_tfa_laser_trails` | 1 | laser dot trails | L | deck: 0 |
| `cl_tfa_hud_crosshair_*`: `length`, `length_use_pixels`, `width`, `enable_custom`, `gap_scale`, `dot`, `color_r/g/b/a`, `color_team`, `color_friendly_r/g/b`, `color_enemy_r/g/b`, `outline_color_r/g/b/a`, `outline_width`, `outline_enabled`, `triangular`, `pump` | various | crosshair look | none | |
| `cl_tfa_hud_hitmarker_enabled` | 1 | TFA hitmarker | L | hud: 0 (PW has its own) |
| `cl_tfa_hud_hitmarker_fadetime`, `_solidtime`, `_scale`, `_color_r/g/b/a`, `_3d_all`, `_3d_shotguns` | various | hitmarker look | none | |
| `cl_tfa_hud_ammodata_fadein`, `cl_tfa_hud_hangtime`, `cl_tfa_hud_scale` | 0.2, 1, 1 | HUD look | none | |
| `cl_tfa_hud_enabled`, `cl_tfa_hud_fallback_enabled` | 1, 1 | 3D2D ammo HUD, fallback | L | hidden through `HUDShouldDraw` instead |
| `cl_tfa_fx_gasblur` | 0 | muzzle gas blur | M when on | deck: 0 (pin) |
| `cl_tfa_fx_muzzlesmoke`, `_limited` | 1, 1 | muzzle smoke trail | M | deck: 0 |
| `cl_tfa_fx_muzzleflashsmoke` | 1 | smoke with the flash | M | deck: 0 |
| `cl_tfa_legacy_shells` | 0 | legacy shell effect | unknown | |
| `cl_tfa_fx_ejectionsmoke` | 1 | ejection smoke | L-M | deck: 0 |
| `cl_tfa_fx_ejectionlife` | 15 | shell lifetime, s | M-H | deck: 2 |
| `cl_tfa_fx_impact_enabled` | 1 | custom impact effects | M | measure |
| `cl_tfa_fx_impact_ricochet_enabled`, `_sparks`, `_sparklife` | 1, 6, 2 | ricochet visuals | L (no ricochets with the server off) | deck: 0 (first) |
| `cl_tfa_fx_ads_dof`, `_hd` | 0, 0 | ADS DOF | H when on | deck: 0 (pin both) |
| `cl_tfa_viewmodel_offset_x/_y/_z/_fov`, `_multiplier_fov`, `_flip`, `_centered`, `_nearwall`, `_vp_enabled`, `_vp_pitch`, `_vp_pitch_is`, `_vp_vertical`, `_vp_vertical_is`, `_vp_max_vertical`, `_vp_max_vertical_is`, `_vp_yaw`, `_vp_yaw_is` | various | viewmodel placement | none | |
| `cl_tfa_debug_crosshair`, `_animations`, `_rt`, `_cache` (not archived) | 0 | debug; `_cache 1` disables stat caching | H when on | |
| `cl_tfa_reticule_color_r/g/b`, `cl_tfa_laser_color_r/g/b` | 255/100/0, 255/0/0 | colours | none | |
| `cl_tfa_attachments_persist_enabled` | 1 | save and restore choices per class | none | lock: 0 |
| `cl_tfa_hud_keybindhints_enabled`, `_solidtime`, `_fadeintime`, `_fadeouttime` | 1, 3, 1, 4 | key hints | L | hud: 0 |
| `cl_tfa_hud_firemode_notify` | 0 | fire mode notifier | none | |
| `cl_tfa_fx_rtscopeblur_mode`, `_passes`, `_intensity` (`TM/cl_tfa_rtbgblur.lua:7-11`) | 1, 3, 4 | RT scope background blur | H with RT sights | deck: mode 0 |
| `cl_tfa_subcategories_enabled`, `_auto` (`TM/cl_tfa_subcategories.lua:1-2`) | 1, 0 | spawn menu | none | |
| `cl_tfa_fix_pmhands_hook`, `cl_tfa_fix_siminov_scopes` (`TM/tfa_hooks.lua:415, 445`) | 1, 1 | compatibility patches | none | |
| `cl_tfa_ballistics_mp`, `_fx_bullet`, `_fx_tracers_style`, `_fx_tracers_mp`, `_fx_tracers_adv` (`TM/tfa_ballistics.lua:104-108`) | 1 | ballistics visuals | only with ballistics | |
| `cl_tfa_keys_bash`, `_customize`, `_inspect`, `_firemode`, `_silencer` (`TM/tfa_keybinds.lua:72-73, 160-224`; userinfo) | 0 | key binds | none | |

## 11. Corrections to existing repository documents

1. `notes/08` §4.3 says the client restore "sends `TFA_Attachment_Request`" and the server applies that without
   force. The client actually sends **`TFA_Attachment_Set`** (class, category, id; `TM/tfa_attachments.lua:117-128`),
   applied at `:89-115`; `TFA_Attachment_Request` only asks the server for its current state (`:66-87`). The
   conclusion (no force, no customizing check) stands.
2. `notes/08` §4.3 lock advice ("`TFA_PreCanAttach`/`TFA_PreCanDetach` → false") is incomplete: it also refuses the
   class's pre-selected `sel` on the server, which the client still applies (3.2 step 3, 3.5), and `sv_tfa_cmenu 0`
   does not stop the `customize` key bind or a manual `impulse 148` (3.5).
3. `notes/08` §4.3 "Adapter applies use `force = true`": `force` bypasses exclusions, dependencies and the
   attachment's own `CanAttach`, so "what stuck" would include illegal combinations. Applying without force while the
   lock lets the adapter through keeps TFA's own validation (change record, "Apply").
4. `docs/api/adapter.md` "Ammo" says TFA default ammo is suppressed through a ConVar. With
   `PW.WeaponAmmo.Give` calling `ply:Give(class, true)`, TFA adds no ammo of its own (no default-ammo timer in the
   base; `sv_tfa_default_clip` only rewrites stored `DefaultClip`, `TM/tfa_commands.lua:114-147`), so
   `SuppressDefaultAmmo` can stay the default no-op [src; confirm with the T-3.4 analogue in game].
5. `notes/08` line references shifted slightly in 4.7.9.8 (for example the menu key checks are at
   `TM/tfa_hooks.lua:194, 223`, not `:195, 228`); the facts stand.
6. `notes/08` §4.1 says "check `SWEP.IsTFAWeapon` directly" for a class: that only works on an instance or on
   `weapons.Get(class)` (merged copy); `weapons.GetStored(class)` of a pack weapon does not carry it. Use
   `weapons.IsBasedOn`.
7. Not in any repository document yet: the core default `GetAmmoType` (`wep:GetPrimaryAmmoType()`,
   `modules/weapons_core/shared.lua:233`) returns a **string** for TFA weapons (section 2). `PW.WeaponAmmo.Give`
   (`modules/weapons_ammo/init.lua:18-19`), the resupply (`sv_resupply.lua:33-35`) and the HUD reserve readout
   (`modules/hud/cl_init.lua:112-116`) accept only a number, so without a TFA `GetAmmoType` a TFA weapon gets no
   reserve ammo, no resupply and no reserve on the HUD. The TFA adapter must convert with `game.GetAmmoID`.

## 12. Unverified items and how to verify them

| Item | Verification |
| --- | --- |
| Mirror equals the Workshop 4.7.9.8 copy | Compare file list and hashes of the Deck's mounted TFA Base with the mirror paths cited here |
| Bots have a server viewmodel (`VMIV`) | In-game case: a bot fires and reloads a TFA rifle |
| `GetInfoNum` on bots returns the default | Same case: the bot holds ADS and does not toggle |
| Per-instance `Attachments` tables | In-game case: two bots with different builds of one class keep them |
| Pack attachment ids, `WeaponTable` shapes, RT sights in the INS2 Shared Parts | On the Deck: `lua` print of `table.GetKeys(TFA.Attachments.Atts)` and of one pack weapon's `Attachments` |
| Static stat estimates match live values | Case: `GetBaseStats(class)` versus `GetLiveStats` on a weapon without a build |
| Default-selection race on remote clients | Checkpoint: a second client (or the host) sees a bot's attachments correctly |
| First `Give` stall per class | Micro-benchmark, as for ARC9 |
| `TFA_GetStat` path names for the stat keys | Debug print of the paths seen once per weapon |
