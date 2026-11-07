# 08 - Weapon base adapters: ARC9, MW Base, TFA Base

Read-only verification of the adapter interface v1 (`DESIGN.md`, "Weapon base integrations") against
the real source of three weapon bases. Nothing was executed in game. Labels:

- **VERIFIED**: read in the source at the cited line.
- **INFERENCE**: follows from the cited code, but the runtime behaviour was not observed.
- **UNVERIFIED**: depends on engine or GMod-module behaviour outside these repos, or was not found.

## 0. Sources

| Base | Source | Version read | Path prefix used below |
| --- | --- | --- | --- |
| ARC9 | <https://github.com/necoarctic/ARC-9> (`HaodongMo/ARC-9` redirects here) | commit `f9bbe034`, 2026-11-01 | `arc9:` = repo root |
| MW Base (`mg_base`, Viper) | Workshop [2459720887](https://steamcommunity.com/sharedfiles/filedetails/?id=2459720887), current title "Modern Wokefare Base", 1.13 M subs | updated 2026-09-27 | `mw:` = root of the Workshop addon (contains its `lua/` folder) |
| TFA Base (YuRaNnNzZZ) | Workshop [2840031720](https://steamcommunity.com/sharedfiles/filedetails/?id=2840031720), docs: <https://github.com/YuRaNnNzZZ/TFA-SWEP-Base-Documentation> | updated 2026-08-22 | `tfa:` = root of the Workshop addon (contains its `lua/` folder) |

MW Base has no official GitHub repo. GitHub has only unofficial mirrors (`Casualez/mwbase`,
`1yling/Modern-Warfare-Base`), so the Workshop item is the canonical source. The MW Base GMA ships the
base only, with no guns. Anything that depends on a weapon pack is **UNVERIFIED**.

Abbreviations used below:

- `A/` = `arc9:lua/weapons/arc9_base/`, `AS/` = `arc9:lua/arc9/shared/`, `AC/` = `arc9:lua/arc9/common/`,
  `ASV/` = `arc9:lua/arc9/server/`
- `M/` = `mw:lua/weapons/mg_base/`
- `T/` = `tfa:lua/weapons/tfa_gun_base/`, `TM/` = `tfa:lua/tfa/modules/`

## 1. Summary table (function × base)

| v1 function | ARC9 | MW Base | TFA Base | v1 change |
| --- | --- | --- | --- | --- |
| `Claims(class)` | `weapons.IsBasedOn(c,"arc9_base")` or `SWEP.ARC9` | `weapons.IsBasedOn(c,"mg_base")` | `SWEP.IsTFAWeapon` / `IsBasedOn(c,"tfa_gun_base")` | keep |
| `ListWeapons()` | `ARC9.SpawnableWeapons` (registry, with weapon type) | filter `weapons.GetList()` + `Customization ~= nil` | filter `weapons.GetList()`; drop melee, nade, bow, knife | add `kind` (`gun`, `melee`, `throwable`, `launcher`) |
| `GetStats(class)` static | raw SWEP fields only; attachments need a live entity | static build possible: `MW_ATTS[c]:Stats(copy)` | raw fields only; `GetStatL` needs an entity | split: `GetBaseStats(class)` + `GetLiveStats(wep)` |
| units | HU, `ARC9.HUToM = 0.0254` | metres | LUT in metres or HU | core normalizes to metres and seconds |
| `GetIcon(class)` | dynamic killicon override (client) | none for guns | none | the core falls back to `entities/<class>.png` |
| `GetSlots` / `GetOptions` | nested tree, address-based | flat `Customization[slot] = {classes}`, index 1 = default | flat `Attachments[cat].atts`, ids | slots become opaque string ids |
| `Validate(class, build)` | inventory and blocking only; no ownership check in net receiver | silently reverts disallowed picks during the build | `CanAttach` (hooks, exclusions, dependencies) | needs a live entity for ARC9 and TFA: validate on the live weapon |
| `Apply(wep, build)` | `BuildSubAttachments` + `DoInvalidateCache` + `PruneAttachments` + `FillIntegralSlots` + `SendWeapon` + `PostModify` | `CreateAttachmentEntity(class)` per slot | `SetTFAAttachment(cat, id, true, true)` | keep; return the applied build |
| lock customization | `arc9_atts_nocustomize 1` + `ARC9_Hook_BlockAttachment` | `mgbase_sv_customization 0` (+ `MW19_AllowAttachment`) | `TFA_PreCanAttach` / `TFA_PreCanDetach` → false | **new**: `SetCustomizationLocked(bool)` |
| block client presets | `wep:SetNoPresets(true)` | convar above blocks the client preset sends | the `TFA_PreCanAttach` lock blocks client restore | part of `Apply` |
| `GiveDefaultAmmo` | `ForceDefaultAmmo` (0 is truthy) + delayed give | `DefaultClip = 0`, gives nothing | `DefaultClip`, `sv_tfa_default_clip` | change to `GetAmmoType(wep)` + `SuppressDefaultAmmo(wep)`; the core gives ammo |
| fire mode | `GetCurrentFiremode()`: -1 auto, 0 safe, 1 semi, N burst | `Primary.Automatic` / `BurstRounds` after `OnSet` | `GetFireMode()` + `FireModes` strings | normalize to `{kind, burst}` |
| ADS key | `IN_ATTACK2` (hold for bots) | `IN_ATTACK2` (`IN_ATTACK` for launchers) | `IN_ATTACK2` (hold for bots) | keep `adsKey` |
| `IsReloading` | NW `Reloading` | flag `Reloading` | `TFA.Enum.ReloadStatus[GetStatus()]` | keep |
| reload input | `IN_RELOAD` press; not with `IN_USE`/`IN_WALK` | `IN_RELOAD` press | **release** of `IN_RELOAD` within 0.3 s; hold = inspect | **new**: input rules |
| recoil data | degrees; view recoil is **client-only** | degrees; `ViewPunch` deflects bullets on the server | degrees; NW `ViewPunchP/Y` deflects bullets on the server | add `affectsBotAim` |
| projectile / hitscan | hybrid: hitscan 750 HU, then phys bullet at 150000 HU/s | hitscan; optional `Projectile` entity (HU/s) | hitscan; optional ballistics (off by default) or projectile | `projectileSpeed` in HU/s or nil |
| headshot | no marker; `arc9_mod_bodydamagecancel` divides by sandbox multipliers | `dmginfo:SetDamageCustom(1)` | none: core hitgroup | core owns hitgroup scaling |
| bot shims | ARC9 needs the most | weapon switch, server actions, `math.randomseed` | input rules (reload tap, `IN_USE` combos, bash) | **new**: `PrepareForBot`, `BotAction`, `GetInputRules` |

## 2. ARC9

### 2.1 Detection and catalogue

- Base class `arc9_base`, flag `SWEP.ARC9 = true` (`A/shared.lua:1460`). ARC9 itself uses
  `weapons.IsBasedOn(class, "arc9_base")` (`AS/sh_npc.lua:175`).
- Registry: `ARC9.SpawnableWeapons[class] = weptype` and `ARC9.WeaponClasses[weptype]`, built by
  `ARC9.PopulateWeaponClasses` (`AS/sh_npc.lua:168-194`). It skips `NotAWeapon`, `!Spawnable` and `AdminOnly` (`:178`).
  Weapon types: `ARC9.WEAPON_PISTOL=1 … SPECIAL=9, MISC=0` (`AC/sh_common.lua:294-303`).
- **Bug:** a weapon with an explicit `ARC9WeaponCategory` lands in `WeaponClasses[0]` (`AS/sh_npc.lua:180-189`).
  Read the type from `ARC9.SpawnableWeapons`.
- Throwables: `arc9:lua/weapons/arc9_base_nade.lua` (`Throwable=true`, `ShootEnt`). `PrimaryAttack` returns
  early for `Throwable`/`PrimaryBash` (`A/sh_shoot.lua:259-265`). Classify by these fields.

### 2.2 Stats

- Fields: `DamageMax`/`DamageMin` (`A/shared.lua:171-172`), `RangeMin`/`RangeMax` in HU (`:178-179`), `Num`
  (`:211`), `RPM` (`:391`), `ClipSize`/`ChamberSize` (`:336-337`), `Spread` (`:571`),
  `AimDownSightsTime`/`SprintToFireTime` (`:600-601`), `SpeedMult*` (`:620-622`).
- `ARC9.HUToM = 0.0254` (`AC/sh_common.lua:265`).
- Falloff is a cosine between `RangeMin` and `RangeMax` (`A/sh_shoot.lua:929-948`); `DamageLookupTable` overrides it (`:982-1036`).
- Effective value: `wep:GetProcessedValue(name, isstatic)`, shared (`A/sh_0_stats.lua:457`).
  - It depends on live state (sights, sprint, crouch, recoil, heat… `:497-660`).
  - It applies `arc9_mod_*` multipliers (`:34-49`).
  - **It needs a live entity** (`self.dt`, `GetOwner()`, `Clip1()`, `:160-235`). A static build preview
    without spawning a weapon is not possible through ARC9's API.
- `InvalidateCache()` only sets a flag; the cache is cleared in the next `Think` (`A/sh_0_stats.lua:80-86`, `A/sh_think.lua:191`).
  Call `DoInvalidateCache()` (`A/sh_0_stats.lua:89`) before reading stats right after `Apply`.

### 2.3 Attachments

- **Slot model:** `SWEP.Attachments[i]` = `{Category, Installed, SubAttachments, Integral, ExcludeElements, RequireElements, RejectAttachments, MergeSlots…}` (`A/shared.lua:1242-1325`).
  - Sub-slots come from the installed attachment's own `Attachments` (`A/sh_subatts.lua:101-215`). The tree is recursive, so a slot id must be an **address path** (for example `"3"` or `"3.1"`).
- **Registry:**
  - `ARC9.Attachments[name]`, `ARC9.Attachments_Index[id]`, `ARC9.GetAttTable(name|id)` (`AS/sh_atts.lua:1-2,115-116,231`).
  - `ARC9.GetAttsForCats(cats)` lists the options for a slot (`AS/sh_atts.lua:246`).
  - **Bug:** its blacklist check indexes `ARC9.Blacklist` by the attachment table, not by its name (`:253`), so the blacklist does not filter here.
- **Validation on a live weapon:**
  - `CanAttach(addr, att, slottbl)` (`A/sh_attach.lua:580`) checks blacklist, inventory, `Hook_BlockAttachment`, slot and attachment blocking, `Max`, `AdminOnly` and category.
  - `SlotInvalid` (`A/sh_attach.lua:306-360`) re-checks elements, `arc9_atts_max`, `Hook_BlockAttachment`, `RejectAttachments` and category. `PruneAttachments` (`A/sh_subatts.lua:272`) calls it.
- **Apply on the server.** Mirror the server branch of `ReceiveWeapon` (`A/sh_net.lua:74-146`):

  ```lua
  wep:SetNoPresets(true)            -- NW var (A/shared.lua:1573); stops the client pushing its default/autosave preset (A/sh_think.lua:206-219)
  wep:BuildSubAttachments(tree)     -- tree[i] = {Installed=, ToggleNum=, SubAttachments={...}} (A/sh_subatts.lua:217-245)
  wep:DoInvalidateCache()
  wep:PruneAttachments()            -- drops anything SlotInvalid() rejects
  wep:FillIntegralSlots()
  wep:SendWeapon()                  -- broadcast (A/sh_net.lua:1-19)
  wep:PostModify()                  -- on the server PostModify does not send (A/sh_attach.lua:135-138)
  ```

  If `Ammo` or `ClipSize` changes, `PostModify` unloads the clip into reserve and sets `RequestReload` (`A/sh_attach.lua:158-168`). Apply **before** filling the clip.
- **Sync:**
  - `SendWeapon(rec)` writes `ARC9_networkweapon` and recursive attachment ids. It goes to `rec`, or to everyone (`A/sh_net.lua:1-19`).
  - Every `Deploy` broadcasts again after 0.25 s (`A/sh_deploy.lua:70`).
- **Security finding (VERIFIED):** the server receiver `arc9_networkweapon` (`ASV/sv_net.lua:37-45`) checks only `wpn.ARC9` and `arc9_atts_nocustomize`. It does **not** check that the sender owns the weapon.
  - `ReceiveWeapon` checks only the inventory (`ValidateInventoryForNewTree`, `A/sh_subatts.lua:247-268`), then prunes.
  - With `arc9_free_atts 1` (the default, `AC/sh_0_convar.lua:240`) the inventory check always passes (`AS/sh_attinv.lua:5-8`).
  - Result: **any client can rebuild any ARC9 weapon on the server, including other players' weapons**, limited only by `Hook_BlockAttachment` and category in `SlotInvalid`.
  - The gamemode must set `arc9_atts_nocustomize 1` while it owns builds. The adapter's own server-side path above does not go through the receiver, so it keeps working.
- **Hooks and convars:**
  - Every `wep:RunHook(X)` also calls `hook.Run("ARC9_"..X, wep, data)` (`A/sh_0_stats.lua:260,290`).
  - Lock hooks: `ARC9_Hook_BlockAttachment(wep, {att, slottbl})` returns `false` (`A/sh_attach.lua:349,601`); `ARC9_Hook_CanDetachAttachment` returns `false` (`:657`).
  - `ARC9_PlayerGetAtts(ply, att, wep)` is reached **only when `arc9_free_atts` is 0** and the attachment is not `Free` (`AS/sh_attinv.lua:5-25`). Any approach that relies on this hook needs `arc9_free_atts 0`.
  - Convars: `arc9_atts_nocustomize` (`AC/sh_0_convar.lua:230`), `arc9_atts_lock` (`:249`), `arc9_atts_max` (`:245`), `arc9_atts_loseondie` (`:254`).
- **Presets:**
  - String format `"[Name]" .. base64(compress(json))` (`A/cl_presets.lua:449-540`).
  - Loading and importing are **client-only** (`A/cl_presets.lua`).
  - The server has only `ARC9.GetAttsFromPreset(str)`, which returns a flat list without slot addresses (`ASV/sv_preset_stuff.lua:105`).
  - `ARC9.SendPreset` / `arc9_giveswep_preset` (`ASV/sv_preset_stuff.lua:41-88,165`) need a client: **useless for bots**.
  - Store builds in the gamemode's own format.
- `CustomizeFullLoadout` does **not exist** in current ARC9 (grep is empty): **UNVERIFIED** whether older versions had it. Use `SetNoPresets(true)`.

### 2.4 Ammo, fire modes, ADS, reload

- **Ammo:**
  - `InitialDefaultClip` gives reserve 0.4 s after init, server only (`A/sh_init.lua:83-89`, `A/sh_deploy.lua:117-131`).
  - `if self.ForceDefaultAmmo then GiveAmmo(self.ForceDefaultAmmo …) else GiveAmmo(ClipSize * arc9_mult_defaultammo …)` (`A/sh_deploy.lua:126-129`). The default for `arc9_mult_defaultammo` is 2 (`AC/sh_0_convar.lua:808`).
  - `ForceDefaultAmmo = 0` is truthy in Lua, so ARC9 gives 0 reserve (**VERIFIED**).
  - The ammo type comes from `wep:GetValue("Ammo")`; attachments can change it.
- **Fire modes:**
  - `Firemodes = {{Mode = -1|0|1|N}}`: -1 auto, 0 safe, 1 semi, N = N-round burst (`A/shared.lua:400-413`).
  - Read with `GetCurrentFiremode()` / `GetCurrentFiremodeTable()` (`A/sh_firemodes.lua:98-140`). Set with `SetFiremode(i)` (NW var, `A/shared.lua:1608`).
  - Switch input: `IN_ZOOM`; `IN_ZOOM+IN_USE` toggles safety (`A/sh_firemodes.lua:176-182`).
  - Semi sets `NeedTriggerPress` (`A/sh_shoot.lua:542-544`), which clears only when `IN_ATTACK` is up (`A/sh_think.lua:92`). **The bot must release `IN_ATTACK` for at least one tick.**
- **ADS:**
  - Decided on the server in `ThinkSights` from `IN_ATTACK2` (`A/sh_sights.lua:291-330`).
  - Toggle mode comes from `GetInfoNum("arc9_toggleads", 0)` (`:84`). A bot gets the default, so it holds to aim (default return for bots: **UNVERIFIED**, per GMod wiki semantics).
  - State: `GetInSights()`, `GetSightAmount()` (NW, `A/shared.lua:1514,1555`).
  - `IN_ATTACK2` while standing still can deploy a bipod (`A/sh_bipod.lua:10`). `IN_USE+IN_ATTACK2` toggles the UBGL (`A/sh_ubgl.lua:16`).
- **Reload:**
  - `SWEP:Reload` runs on `IN_RELOAD` (`A/sh_reload.lua:12`). It is blocked by `IN_WALK` (`:39,175`), by sprint, and while customizing (`:174-192`).
  - `IN_USE+IN_RELOAD` inspects instead (`A/sh_inspect.lua:13`).
  - State: NW `Reloading`, `ReloadFinishTime` (`A/shared.lua:1546-1554`). Capacity: `GetCapacity() = ClipSize + ChamberSize` (`A/sh_reload.lua:282-292`).
  - **Auto-reload is client-only** (`arc9:lua/arc9/client/cl_move.lua:20`). The bot must press `IN_RELOAD` itself.

### 2.5 Recoil, projectiles, kill info

- **Recoil:**
  - Fields `Recoil`, `RecoilUp`, `RecoilSide`, `RecoilRandom*`, `RecoilPatternDrift`, `RecoilMax`, `RecoilDissipationRate`, `RecoilAutoControl`, `VisualRecoil*`, in degrees (`A/shared.lua:434-562`).
  - `ApplyRecoil` only writes NW vars `RecoilUp/RecoilSide/RecoilAmount` (`A/sh_recoil.lua:54-126`). The move into view angles happens **only in the `if CLIENT then` branch** of `ARC9.StartCommand` (`AS/sh_move.lua:262-345`).
  - So **bots get no view recoil from ARC9 at all**. This holds whether or not the gamemode overwrites view angles.
  - `RecoilAmount` still widens spread through the "Recoil" condition (`A/sh_0_stats.lua:609-612`).
  - Visual recoil moves the shot only with `UseVisualRecoil` + `PhysicalVisualRecoil` / `arc9_realrecoil` (`A/sh_recoil.lua:492-505`).
- **`GetFOV`:**
  - The only server-reachable call is `owner:SetFOV(owner:GetFOV() * (1 - 0.01 * RecoilKickRoll), 0)` under `arc9_recoilshake` (default 1, `AC/sh_0_convar.lua:795`), followed by `SetFOV(0, …)` (`A/sh_recoil.lua:122-124`).
  - It returns a number and restores the FOV, so in this version it cannot break firing.
  - "GetFOV error spam" with bots may come from an older ARC9, or from a 0 FOV on bots: **UNVERIFIED** for the current version. If a guard is needed, keep it narrow and bot-scoped. Do not use a global `Player` metatable override.
- **Bullet direction:** `GetShootDir` = `EyeAngles` + `ShootAngOffset` + free-aim (`arc9_mod_freeaim`, default 0) + sway (`arc9_mod_sway`, default 1) (`A/sh_shoot.lua:1078-1097`). Spread up to `spread·45·√2` degrees (`:594-604`).
- **Projectiles:**
  - `ShootEnt` spawns an entity with `ShootEntForce` (`A/sh_shoot.lua:1099-1171`).
  - Physical bullets are on by default (`arc9_bullet_physics 1`, `AC/sh_0_convar.lua:390`). Shotguns are excluded unless `arc9_bullet_physics_shotguns` is set (`A/sh_shoot.lua:660`).
  - A shot is a 750 HU hitscan; past that, a phys bullet starts at `PhysBulletMuzzleVelocity` (default 150000 HU/s, `A/shared.lua:301`) × `arc9_mod_muzzlevelocity` (`A/sh_shoot.lua:609,686,747-751`).
  - Gravity: `600 · PhysBulletGravity · arc9_bullet_gravity` HU/s² (`AS/sh_physbullet.lua:311`). Lead is negligible at map ranges.
  - Server-fired phys bullets skip `SendBullet` (`A/sh_shoot.lua:628`, `AS/sh_physbullet.lua:139`). Whether other clients see bot tracers is **UNVERIFIED**.
- **Headshots:**
  - `BodyDamageMults` (head 2.5, `A/shared.lua:241-249`) × `HeadshotDamage` (`A/sh_shoot.lua:794-813`).
  - With `arc9_mod_bodydamagecancel 1` the damage is then **divided** by sandbox's multipliers (head 2, limbs 0.25), on the assumption that the gamemode's `ScalePlayerDamage` re-applies them (`AC/sh_common.lua:238-249`, `A/sh_shoot.lua:857-858`).
  - The core and the adapter must agree on this. See §6.
- **Kill info:**
  - ARC9 replaces `killicon.Render`/`Draw` on the client with a dynamic weapon icon (`arc9:lua/arc9/client/cl_killicons.lua:1-120`); `NoDynamicKillIcon` (`A/shared.lua:142`) opts out.
  - Hooks: `ARC9_Hook_OnKill(wep, victim)` (`AS/sh_gunutils.lua:1-26`), `ARC9_Hook_BulletImpact` (`A/sh_shoot.lua:777`).
  - `PrintName` can change with attachments (`A/sh_attach.lua:116-131`).

### 2.6 Bot audit

| Path | Bot effect | Shim |
| --- | --- | --- |
| View recoil (`AS/sh_move.lua:262`, CLIENT) | none | core simulates or ignores |
| Auto-reload (`arc9:lua/arc9/client/cl_move.lua:20`) | never fires | bot presses `IN_RELOAD` |
| Presets (`A/sh_think.lua:206-219`, `A/cl_presets.lua`) | never load | server-side `Apply` |
| `GetInfoNum("arc9_toggleads")` (`A/sh_sights.lua:84`), `arc9_manualbolt` (`A/sh_cycle.lua:18,52`) | defaults: hold-ADS, auto-bolt | none |
| `GetFOV` (`A/sh_recoil.lua:123`) | numeric, harmless (INFERENCE) | optional bot-only guard |
| Net to owner: `ARC9_sendattinv` (`AS/sh_attinv.lua:154`), `arc9_sendpreset` (`ASV/sv_preset_stuff.lua:180,193`) | sent to a client-less player; effect **UNVERIFIED** (no error expected) | skip for bots |
| `SendWeapon` broadcast | other clients need it to see bot attachments | **do not** mute it permanently (muting it breaks pickups, INFERENCE) |
| Sprint (`A/sh_sprint.lua:42-75`) | needs `IN_SPEED` + a movement **button bit** | set `IN_FORWARD` etc., not only `SetForwardMove` |
| `SprintLock` (`A/sh_shoot.lua:22-29,291`) | no fire until `SprintAmount = 0` | wait `SprintToFireTime` |
| Weapon switch (`A/sh_deploy.lua:233-291`) | ARC9's own `StartCommand` hook re-selects | none |
| `IsBot` (`AS/sh_move.lua:131`) | writes a dead variable | none |
| `StartCommand` order | ARC9 hooks run before `GM:StartCommand`; sway and bipod clamps are overwritten | none |

## 3. MW Base (`mg_base`)

### 3.1 Detection and catalogue

- `SWEP.Base = "weapon_base"`, `Category = "MG"`, `Spawnable = false` (`M/shared.lua:43-47`). Packs are identified with `weapons.IsBasedOn(class, "mg_base")` (`M/init.lua:64`).
- `PreRegisterSWEP` (`mw:lua/autorun/mw_loader.lua:44-86`):
  - acts only on SWEPs with `Customization`;
  - refuses old-format SWEPs;
  - strips classes missing from `MW_ATTS`;
  - sets tracers by `SubCategory` ("Pistols", "Shotguns"…).
- `SubCategory` is the natural class hint.
- No grenade or melee sub-base in the GMA. Kind flags: `UseLauncherLogic`, `Explosive`, `Projectile`, `Primary.ClipSize < 0` (`M/modules/shared/sh_aim_behaviour.lua:20-23`, task `task_primaryfire.lua:32-48,129`).

### 3.2 Stats

- **Damage:** `Bullet.Damage = {near, far}`, lerped by `(dist - DropOffStartRange) / EffectiveRange`, divided by `NumBullets` (`M/modules/shared/sh_primaryattack_behaviour.lua:108-115`).
- **Ranges** in **metres** (`MetersToHU = m*100/2.54`, `:56-58`). `Bullet.Range` × `mgbase_sv_range` (`:381`).
- **RPM:** `Primary.RPM` (`M/shared.lua:650-652`). **Clip:** `Primary.ClipSize` (+1 chamber, `sh_reload_behaviour.lua:3-9`).
- **ADS time:** from `Animations.Ads_In.Length / (Fps/30)` (`M/shared.lua:679-691`).
- **No movement-speed stat** in the base (INFERENCE from grep). Mobility must default.
- **Static build stats are possible.** `BuildCustomizedGun` (`sh_customization.lua:233-513`) copies `weapons.Get(class)` and calls `att:Stats(t)` per attachment. The base itself does this on a plain table (`:519-522`).
  - `PostProcess` and `Firemodes[1].OnSet` expect a weapon, so a static preview should skip them.
  - Pack `Stats` functions that call entity methods: **UNVERIFIED**.

### 3.3 Attachments

- **Slot model:** `SWEP.Customization[slotInt] = {"att_class", …}`.
  - **Index 1 is the slot default**: a real attachment, not "none" (`M/shared.lua:478-480`).
  - Conversions use slot -999 (`mw_loader.lua:34`).
- **Registry:** `MW_ATTS[class]`, loaded from `M/modules/attachmentss/**` with inheritance (`mw:lua/autorun/mw_assets/attachments.lua:3-105`). Fields: `Name`, `Icon`, `Category`, `Stats`, `CosmeticChange`, `Excluded*`.
- **Server apply: `SWEP:CreateAttachmentEntity(class)`** (`M/shared.lua:337-360`, VERIFIED):
  - It is server-only.
  - It spawns an `mg_attachment` entity with `Slot` and `Index` found by searching `Customization`. An unknown class gives slot 0, which is silently ignored.
  - `mg_attachment` replaces the existing attachment in that slot and calls `weapon:Attach(slot, idx)` (`mw:lua/entities/mg_attachment.lua:46-54`). The client copy re-attaches when the entity arrives (`:57-70`). **Client sync goes through these entities only.**
- **Validation:**
  - `IsAttachmentAllowed` checks `mgbase_sv_customization_limit` (non-cosmetic), `hook.Run("MW19_AllowAttachment", wep, att) == false` and exclusions (`sh_customization.lua:837-864`).
  - Disallowed picks are **silently reverted** to index 1 during the build (`:294-298`). `Apply` must read back `GetAttachmentInUseForSlot(s)` to report what stuck.
- **Receiver `mgbase_customize_att`** (`M/init.lua:46-78`, VERIFIED):
  - It checks the convar, owner, class base and slot existence.
  - It does **not** bounds-check `attIndex`, so a nil class is ignored downstream.
  - Re-picking the installed class toggles back to index 1 (`:72-74`).
  - So "(slot, index) pairs mirror the base" (**VERIFIED**).
- **Lock:**
  - `mgbase_sv_customization 0` disables the receiver and the Customize task only (`M/init.lua:51`, `task_customize.lua:10`). Server-side `CreateAttachmentEntity` ignores it. This is the main switch.
  - `MW19_AllowAttachment` runs inside every build on both realms. It would also block the adapter's own picks unless it whitelists them, so it is not needed when the convar is off.
- **Presets:**
  - Lua presets go into `MW_PRESETS` (`mw_assets/presets.lua:6-29`). User presets are client JSON.
  - `mw_utils.LoadPreset(weapon, preset)` on the server calls `CreateAttachmentEntity` directly (`mw:lua/includes/modules/mw_utils.lua:230-248`).
  - The spawn preset is client-only (`M/shared.lua:500-557`).

### 3.4 Ammo, fire modes, ADS, reload

- **Ammo:**
  - `Primary.DefaultClip = 0` (`M/shared.lua:67`), so `Give` adds no reserve. `Primary.Ammo` is per pack (**UNVERIFIED**).
  - Infinite reserve only when `game.GetAmmoMax(type) == -2` (`task_reload.lua:61-63`).
  - Attachments added right after `Give` fill the magazine (`sh_customization.lua:417-433`, `task_deploy.lua:67-71`).
- **Fire modes:**
  - `Firemodes = {{Name, OnSet(w)}}`, where `OnSet` sets `Primary.Automatic` / `BurstRounds` (`attachmentss/perks/att_perk_mw_burst.lua:9-15`).
  - Kind = auto if `Automatic`, burst if `BurstRounds > 1`, else semi (`task_primaryfire.lua:18-32`). The index is NW `GetFiremode()`.
  - Switch on the server with `wep:ApplyFiremode(i)` (`sh_firemode_behaviour.lua:11-34`).
  - Semi and burst clear `AutoFire` after each shot (`task_primaryfire.lua:61-63`): **release `IN_ATTACK` between shots.**
- **ADS:**
  - `KeyDown(IN_ATTACK2)`, or `IN_ATTACK` for launchers (`sh_aim_behaviour.lua:20`). Toggle comes from `GetInfoNum("mgbase_toggleaim", 0)` (`:15`).
  - State: `HasFlag("Aiming")`, `GetAimDelta()` (`sh_datatables.lua:50-53`).
- **Reload:**
  - `Reload()` runs `TrySetTask("Reload")` (`M/shared.lua:596-602`). State: flag `Reloading` (`task_reload.lua:41-47`).
  - Timing is table-driven (`SWEP.Animations`), **not** viewmodel-driven (`M/shared.lua:679-691`).
  - Auto-reload: `GetInfoNum("mgbase_autoreload", 1)`, so it is on for bots (`sh_think.lua:23-27`).

### 3.5 Recoil, projectiles, kill info

- **Recoil:**
  - `Recoil = {Vertical{min,max}, Horizontal{min,max}, AdsMultiplier, Punch, …}` in degrees, × `mgbase_sv_recoil` (`sh_primaryattack_behaviour.lua:39-54`).
  - Applied in the shared PrimaryFire task (`task_primaryfire.lua:136-149`): always `owner:ViewPunch`, and `SetEyeAngles` under `IsFirstTimePredicted()`.
  - The overwrite cancels the `SetEyeAngles` part. **`ViewPunch` still deflects server bullets**: the shot dir is `EyeAngles() + GetViewPunchAngles() + breathing sway` (`sh_primaryattack_behaviour.lua:362`). Bots do feel MW recoil.
- **Global RNG side effect (VERIFIED):** `math.randomseed(Seed + SprayRounds)` on every shot and `math.randomseed(Clip1 + Ammo1)` on every hit (`sh_primaryattack_behaviour.lua:42,194`). On the server this **reseeds `math.random` for all Lua**, including the bot AI. The core must use its own PRNG.
- **Projectiles:** hitscan `FireBullets` by default (`:372-390`).
  - `SWEP.Projectile` spawns `Projectile.Class` (`:510-546`). `mg_bullet` speed defaults to 4000 HU/s, with gravity (`mw:lua/entities/mg_bullet/init.lua:7-11,32,43`).
- **Headshot:** `dmgInfo:SetDamageCustom(1)` on head hits (`sh_primaryattack_behaviour.lua:150-165`). That is a usable marker. Damage scales with `HeadshotMultiplier`.
- **No gun killicons**; only arrows (`mw:lua/entities/mg_arrow/cl_init.lua:3`). No kill hooks; build hook `OnBuildCustomizedGun` (`sh_customization.lua:508`).

### 3.6 Bot audit

| Path | Bot effect | Shim |
| --- | --- | --- |
| `Holster` → task sets `CanSwitch`, but only the **client** re-selects (`M/shared.lua:608-622`, `task_holster.lua:18-31`) | one `cmd:SelectWeapon` leaves the bot stuck in `Holstering` (priority 999: no fire, no reload) (INFERENCE) | repeat `cmd:SelectWeapon` every tick until active |
| Binds via `GetInfoNum("mgbase_binds_*")` (`mw:lua/includes/modules/mw_input.lua:29,105`) | firemode, melee, safety, tac stance, underbarrel unreachable | `BotAction`: `ApplyFiremode`, `TrySetTask("Melee")`… |
| Sprint needs `IN_SPEED` + movement bits (`sh_sprint_behaviour.lua:3-8`); sprint priority above fire (`sh_tasks.lua:58`) | `IN_SPEED` while moving blocks firing | drop `IN_SPEED` before shooting |
| Bipod auto-deploys with no movement bits (`sh_bipod_behavior.lua:23-36`) | bot moved only by `SetForwardMove` counts as standing | set movement bits |
| `mgbase_viewmodelanim` broadcast per anim (`mw:lua/entities/mg_viewmodel/shared.lua:159-166`) | bandwidth per bot shot | none (budget) |
| `math.randomseed` | AI randomness reseeded | core PRNG |
| `SendLua` to owner for tracking weapons (`sh_aim_behaviour.lua:187,211`) | **UNVERIFIED** for bots | avoid those weapons for bots |

## 4. TFA Base

### 4.1 Detection and catalogue

- `SWEP.IsTFAWeapon = true` (`T/shared.lua:12`). The authors say to check this flag directly (`TM/tfa_meta.lua:4-5`). For a class: `weapons.IsBasedOn(class, "tfa_gun_base")` (`TM/tfa_hooks.lua:571`).
- Kinds: `tfa_melee_base`, `tfa_knife_base` (`IsMelee`), `tfa_nade_base` (`IsGrenade`), `tfa_bow_base` (`IsBow`), `tfa_bash_base`, `tfa_sword_advanced_base`, plus `tfa_3dscoped_base`, `tfa_3dbash_base` (`TM/tfa_small_entities.lua:55,90`).

### 4.2 Stats

- **Fields** (`tfa:lua/tfa/documentation/tfa_base_template.lua`): `Primary.Damage` (`:49`), `RPM` (+ `RPM_Semi/Burst`, `:43,65-66`), `NumShots` (`:44`), `ClipSize` (`:178`), `Spread` / `IronAccuracy` (`:195-196`).
- **Range:** `Primary.RangeFalloffLUT` with `units = "meters"|"hammer"` (`:206-240`). Legacy `Range`/`RangeFalloff` are converted (`T/common/autodetection.lua:97-117`).
- **Mobility:** `RegularMoveSpeedMultiplier` / `AimingDownSightsSpeedMultiplier` (`TM/tfa_data.lua:39-46`). **ADS time:** `IronSightTime` (default 0.3 s, `T/shared.lua:154`).
- **Effective value:** `wep:GetStatL(path, default)` (`T/common/stat.lua:314`), cached; `ClearStatCache()` (`:79`).
  - **It needs a live entity.** It returns un-attached values without a valid owner (`:347-359`).
  - Hook `TFA_GetStat` can override any stat (`:341,382`).
- `SWEP:MetersToUnits` uses ×52.49 (`T/common/utils.lua:18-20`), while the LUT and ballistics use 39.37. Do not mix them.

### 4.3 Attachments

- **Slot model:** `SWEP.Attachments[cat] = {atts = {ids}, sel, default, hidden, order}` (`tfa_base_template.lua:902-917`). Plus `AttachmentDependencies`, `AttachmentExclusions` (`:919-929`).
- **Registry:** `TFA.Attachments.Atts[id]`, from `lua/tfa/att/*.lua` and `attbatch` (`TM/tfa_attachments.lua:2,290,312-427`).
- **Apply:** `wep:SetTFAAttachment(cat, id, nw, force)` (`T/common/attachments.lua:387`).
  - Without `force`, the server runs `CanAttach` (`:408-409`): `TFA_PreCanAttach`/`PreCanDetach` → `sv_tfa_attachments_enabled` → exclusions and dependencies → `att:CanAttach` → `TFA_CanAttach` (`:238-319`).
  - With `nw = true` it syncs via `net.SendPVS` (`TM/tfa_attachments.lua:39-55`). Clients re-request on PVS entry (`:168-195`).
- **Client restore trap:** the client restores saved attachments (`cl_tfa_attachments_persist_enabled`, `T/common/attachments.lua:580-586`) and sends `TFA_Attachment_Request`. The server applies it **without force**, and does not check customizing (`TM/tfa_attachments.lua:89-115`).
  - Lock with `TFA_PreCanAttach`/`TFA_PreCanDetach` returning `false` on the server.
  - Adapter applies use `force = true`.
- **Default-selection desync risk:** default `sel` is applied on both realms with `nw = false`, but the server-only `CanAttach` check can reject it on the server and not on the client (`T/common/attachments.lua:408,554-557`) (INFERENCE).
- **No preset system.** `sv_tfa_cmenu 0` only hides the menu key (`TM/tfa_hooks.lua:195,228`).

### 4.4 Ammo, fire modes, ADS, reload

- **Ammo:**
  - `Primary.Ammo`, `DefaultClip`. `sv_tfa_default_clip` rewrites `DefaultClip` for every TFA weapon (`TM/tfa_commands.lua:107-158`).
  - Grenades strip themselves when empty (`tfa:lua/weapons/tfa_nade_base.lua:67-81`).
- **Fire modes:**
  - `FireModes` strings `"Automatic"`, `"Single"`, `"<N>Burst"`, `"Safe"`, auto-built if absent (`T/common/autodetection.lua:413-466`).
  - Read: `GetFireMode()`, `IsFireModeAutomatic()`, `GetMaxBurst()`, `IsSafety()` (`T/common/utils.lua:570,799,1251`).
  - Server switch: `CycleFireMode()` (`:834`), or cmd impulse 150 (`TM/tfa_hooks.lua:6-7,258-261`).
- **ADS:**
  - Decided in `FinishMove` from `IN_ATTACK2` edges (`TM/tfa_hooks.lua:284-317`, VERIFIED).
  - Toggle and resight come from `GetInfoNum(…, 0)`, so bots hold to aim and do not re-ADS after reload. Humans default to toggle (`TM/cl_tfa_commands.lua:70,74`).
  - State: `GetIronSights()`, `GetIronSightsProgress()` (`T/shared.lua:478,526`).
  - Sprint = speed > 0.6·run **and** `IN_SPEED` **and** on ground (`T/common/calc.lua:56-57`). It blocks fire while progress ≥ 0.1 (`T/shared.lua:1528`).
- **Reload (VERIFIED, `TM/tfa_hooks.lua:319-332`):**
  - With `sv_tfa_reloads_legacy 0` (the default), reload starts on **release** of `IN_RELOAD` within 0.3 s of the press, and only without `IN_USE`.
  - Holding longer runs `CheckAmmo` (inspect).
  - The bot must tap: press for 1 to 10 ticks, then release.
  - State: `TFA.Enum.ReloadStatus[wep:GetStatus()]` (`tfa:lua/tfa/enums/statusnew.lua:96-103`). Capacity: `GetPrimaryClipSize()` (+1 chamber, `T/common/utils.lua:300-328`).
  - Reload length comes from the server viewmodel's `SequenceDuration` (`T/common/utils.lua:149-195`). That bots have a valid server viewmodel is **UNVERIFIED**; Garry's Mod normally creates one per player.

### 4.5 Recoil, projectiles, kill info

- **Recoil:**
  - `Primary.KickUp/KickDown/KickHorizontal`, `StaticRecoilFactor`, `RecoilLUT`, in degrees (`tfa_base_template.lua:189-192,277-350`).
  - `SWEP:Recoil` (`T/common/bullet.lua:410-437`, VERIFIED) does three things:
    1. calls `owner:ViewPunch` on the server;
    2. accumulates NW `ViewPunchP/Y` on the weapon;
    3. calls `SetEyeAngles` only in singleplayer, or on the predicting client.
  - Bullet aim = `GetAimVector()` + weapon `ViewPunchP/Y` (or the LUT) (`T/common/utils.lua:1174-1191`). This server-side kick **does** affect bots; the eye-angle part never does.
- **Projectiles:**
  - Hitscan by default (`T/common/bullet.lua:18-35`). `Primary.Projectile` uses `ProjectileVelocity` in HU/s (`:132-176`).
  - Ballistics only if `UseBallistics` or `sv_tfa_ballistics_enabled` (default 0). Velocity = `Primary.Velocity` m/s × 39.37, with drag and gravity (`TM/tfa_ballistics.lua:61,189-235`, `tfa:lua/tfa/ballistics/bullet.lua:140-150`).
- **Kill info:**
  - There is no headshot scaling (only TTT `GetHeadshotMultiplier`, `T/common/ttt.lua:72-74`), no killicons (grep is empty) and no kill hook.
  - Penetration hook: `TFA_Bullet_Penetrate` (`T/common/bullet.lua:641`).
  - The hitmarker is sent with `net.Send` to the owner (`T/common/utils.lua:967-981`).

### 4.6 Bot audit

| Path | Bot effect | Shim |
| --- | --- | --- |
| Reload on release within 0.3 s (`TM/tfa_hooks.lua:319-332`) | holding `IN_RELOAD` inspects instead | tap rule |
| `GetInfoNum("cl_tfa_keys_*")` = 0 → combos (`T/common/utils.lua:918`, `T/shared.lua:1651`) | `IN_USE`+fire toggles a silencer; `IN_USE`+R changes firemode | never send `IN_USE` with attack or reload |
| `TFABashZoom` is a `StartCommand` hook (`TM/tfa_hooks.lua:343-366`) | hooks run before `GM:StartCommand`, so a gamemode `IN_ZOOM` is never converted (INFERENCE from `hook.Call` order) | `cmd:SetImpulse(149)` for bash |
| `SetEyeAngles` recoil (`T/common/bullet.lua:427`) | absent | none; server kick is still real |
| Viewmodel checks in `PrimaryAttack`/`Reload`/`Deploy` (`T/shared.lua:856-861,1744,1910`) | need `owner:GetViewModel()` (**UNVERIFIED** for bots) | test in game |
| `Holster` waits for the animation, then `SelectWeapon` on the server (`T/shared.lua:916-990`) | works | none |
| Grenade strips itself (`tfa_nade_base.lua:67-81`) | active weapon disappears | core re-selects |

## 5. Refined adapter interface v1

Changes from the v1 table, with reasons:

1. **`GetStats` split** into a static `GetBaseStats(class)` and a live `GetLiveStats(wep)`. ARC9 and TFA can apply attachments only on a live entity (§2.2, §4.2). A static `PreviewBuildStats` is optional, and only MW can implement it today.
2. **Slot and option ids are opaque strings.** ARC9 slots are nested addresses, MW slots are integers with index 1 as the default, and TFA slots are categories. A build is `{[slotId] = optionId}`.
3. **`Validate` moves to the live weapon.** Every base validates against instance state (elements, exclusions, limits). The static `Validate(class, build)` stays optional and cheap (existence and slot membership only).
4. **New `SetCustomizationLocked(locked)`.** Each base needs a different global switch, and two of them have exploitable client paths (§2.3 ARC9 receiver, §4.3 TFA request).
5. **Ammo is owned by the core.** `SuppressDefaultAmmo` + `GetAmmoType`, because the default-ammo behaviour differs (ARC9 delayed 0.4 s, MW zero, TFA convar).
6. **New bot functions:** `GetInputRules`, `BotAction`, and `affectsBotAim` in recoil. Each base has input quirks a plain `IN_*` writer gets wrong (§2.6, §3.6, §4.6).
7. **Headshots and hitgroups are owned by the core.** See §6.

```lua
---@meta cod_weapon_adapter

---@alias COD.Realm "shared"|"server"|"client"
---@alias COD.WeaponKind "gun"|"melee"|"throwable"|"launcher"|"other"
---@alias COD.SlotId string          -- opaque; ARC9 "3" or "3.1", MW "2", TFA "1"
---@alias COD.OptionId string        -- attachment id; MW: class name (resolved to an index server-side)
---@alias COD.Build table<COD.SlotId, COD.OptionId|false>  -- false = clear (MW: index 1, the slot default)

---@class COD.WeaponInfo
---@field class string
---@field name string                -- PrintName (may be a language token)
---@field kind COD.WeaponKind
---@field category string|nil        -- "ar","smg","sniper","shotgun","pistol","lmg","special"; nil = unknown
---@field slot integer               -- 1 primary, 2 secondary, 3 equipment

---@class COD.Stats                  -- all fields optional; core shows "-" for nil
---@field damageNear number|nil      -- per trigger pull (per-pellet × pellets)
---@field damageFar number|nil
---@field rangeNear number|nil       -- metres, end of max damage
---@field rangeFar number|nil        -- metres, start of min damage
---@field rpm number|nil
---@field magazine integer|nil       -- without the chambered round
---@field adsTime number|nil         -- seconds
---@field moveMult number|nil        -- 1.0 = no penalty
---@field pellets integer|nil

---@class COD.Slot
---@field id COD.SlotId
---@field name string
---@field parent COD.SlotId|nil      -- nested slots (ARC9 only)
---@field cosmetic boolean           -- does not count toward the pick cap
---@field default COD.OptionId|nil

---@class COD.Option
---@field id COD.OptionId
---@field name string
---@field icon IMaterial|nil         -- client only
---@field cosmetic boolean

---@class COD.FireInfo
---@field kind "auto"|"semi"|"burst"|"safe"
---@field burst integer              -- rounds per burst; 1 for semi
---@field rpm number
---@field adsKey integer             -- IN_ATTACK2 (MW launchers: IN_ATTACK)
---@field projectileSpeed number|nil -- HU/s; nil = hitscan
---@field projectileGravity number|nil -- HU/s^2

---@class COD.Recoil
---@field pitch number               -- degrees per shot, average
---@field yaw number                 -- degrees per shot, +- range
---@field affectsBotAim boolean      -- true when the server-side shot direction is deflected

---@class COD.InputRules             -- consumed by the bot input writer
---@field releaseBetweenShots boolean -- semi/burst need >=1 tick with IN_ATTACK up
---@field reloadTap boolean          -- TFA: press then release within the window
---@field reloadTapMax number        -- seconds (TFA 0.3)
---@field forbidWithAttack integer   -- button mask never sent together with IN_ATTACK (TFA: IN_USE)
---@field forbidWithReload integer   -- ARC9: IN_USE|IN_WALK, TFA: IN_USE
---@field noSprintWhileFiring boolean -- MW, ARC9: drop IN_SPEED before firing
---@field sprintToFire number        -- seconds to wait after sprint
---@field reselectEveryTick boolean  -- MW: repeat cmd:SelectWeapon until active

---@class COD.Adapter
---@field id string                  -- required
---@field apiVersion 1               -- required
---@field priority integer           -- default 0
local Adapter = {}

-- Discovery (required) ---------------------------------------------------------
---@realm shared
---@return boolean
function Adapter.IsAvailable() end
---@realm shared
---@param class string
---@return boolean
function Adapter.Claims(class) end
---@realm shared
---@return COD.WeaponInfo[]
function Adapter.ListWeapons() end

-- Stats (optional) -------------------------------------------------------------
---@realm shared  default: Primary.Damage/RPM/ClipSize
---@param class string
---@return COD.Stats
function Adapter.GetBaseStats(class) end
---@realm shared  default: GetBaseStats(wep:GetClass())
---@param wep Weapon
---@return COD.Stats
function Adapter.GetLiveStats(wep) end
---@realm shared  default: nil (UI shows base stats only); MW can implement statically
---@param class string
---@param build COD.Build
---@return COD.Stats|nil
function Adapter.PreviewBuildStats(class, build) end
---@realm client  default: Material("entities/<class>.png")
---@param class string
---@return IMaterial|nil
function Adapter.GetIcon(class) end

-- Attachments (optional; absent = weapon has no gunsmith) -----------------------
---@realm shared
---@param class string
---@param build COD.Build|nil        -- nested slots depend on the build (ARC9)
---@return COD.Slot[]
function Adapter.GetSlots(class, build) end
---@realm shared
---@param class string
---@param slot COD.SlotId
---@return COD.Option[]
function Adapter.GetOptions(class, slot) end
---@realm server  cheap static check: slot exists, option belongs to slot; default: identity
---@param class string
---@param build COD.Build
---@return COD.Build clean, table<COD.SlotId,string> rejected  -- reason codes
function Adapter.Validate(class, build) end
---@realm server  applies, syncs to clients, blocks client presets; returns what actually stuck
---@param wep Weapon
---@param build COD.Build
---@return COD.Build applied
function Adapter.Apply(wep, build) end
---@realm server  idempotent; default: no-op (logged once)
---@param locked boolean
function Adapter.SetCustomizationLocked(locked) end

-- Ammo (optional) --------------------------------------------------------------
---@realm server  called right after ply:Give; default: no-op
---@param wep Weapon
function Adapter.SuppressDefaultAmmo(wep) end
---@realm shared  default: wep:GetPrimaryAmmoType()
---@param wep Weapon
---@return integer ammoType
function Adapter.GetAmmoType(wep) end

-- State (optional) -------------------------------------------------------------
---@realm shared  default: false
function Adapter.IsReloading(wep) end
---@realm shared  default: owner:KeyDown(IN_ATTACK2)
function Adapter.IsAiming(wep) end
---@realm shared  default: wep:Clip1(), wep:GetMaxClip1()
---@return integer clip, integer capacity
function Adapter.GetClip(wep) end
---@realm shared  default: wep:GetNextPrimaryFire() <= CurTime() and clip > 0
function Adapter.CanFireNow(wep) end

-- Bot support (optional) -------------------------------------------------------
---@realm server  once per Give for a bot-owned weapon; default: no-op
function Adapter.PrepareForBot(ply, wep) end
---@realm server  default: {kind = Primary.Automatic and "auto" or "semi", burst = 1, rpm, adsKey = IN_ATTACK2}
---@return COD.FireInfo
function Adapter.GetFireInfo(wep) end
---@realm server  default: {pitch = 0, yaw = 0, affectsBotAim = false}
---@return COD.Recoil
function Adapter.GetRecoil(wep) end
---@realm server  default: conservative rules (release between shots, plain IN_RELOAD)
---@return COD.InputRules
function Adapter.GetInputRules(wep) end
---@realm server  actions a bot cannot express through CUserCmd; default: false
---@param action "firemode"|"melee"|"safety_off"
---@param arg any
---@return boolean done
function Adapter.BotAction(ply, wep, action, arg) end

-- Kill info (optional) ---------------------------------------------------------
---@realm server  called after the core's hitgroup check; default: nil (core decides)
---@param dmginfo CTakeDamageInfo
---@return boolean|nil
function Adapter.IsHeadshot(dmginfo) end
---@realm shared  default: language.GetPhrase(wep.PrintName)
function Adapter.GetDisplayName(wep) end
```

### 5.1 Per-base implementation notes

| Function | ARC9 | MW Base | TFA |
| --- | --- | --- | --- |
| `ListWeapons` | `ARC9.SpawnableWeapons`; kind from `Throwable`/`PrimaryBash`; category from `ARC9.WEAPON_*` | `weapons.GetList()` + `IsBasedOn mg_base` + `Customization`; category from `SubCategory` | `weapons.GetList()` + `IsTFAWeapon`; kind from `IsMelee`/`IsGrenade`/`IsBow` |
| `GetBaseStats` | raw fields, HU × 0.0254 | `Bullet.*` (metres), `Primary.RPM`, ADS from `Animations.Ads_In` | `Primary.*`; range from `RangeFalloffLUT` (units field) |
| `GetLiveStats` | `GetProcessedValue(x, true)` after `DoInvalidateCache()` | live SWEP table fields after the build | `GetStatL(path)` |
| `PreviewBuildStats` | nil | copy `weapons.Get` + `MW_ATTS[c]:Stats(t)` (no `PostProcess`) | nil |
| `GetSlots` | walk `Attachments`/`SubAttachments`, address ids | `Customization` keys (skip -999 unless conversions are wanted) | `Attachments` keys, sorted by `order`, skip `hidden` |
| `GetOptions` | `ARC9.GetAttsForCats(slot.Category)` (filter blacklist yourself) | `Customization[s]`, metadata from `MW_ATTS` | `Attachments[c].atts`, `TFA.Attachments.Atts` |
| `Apply` | sequence in §2.3 with `SetNoPresets(true)` | per slot: index lookup → `CreateAttachmentEntity`; read back `GetAttachmentInUseForSlot` | `SetTFAAttachment(c, id, true, true)` per slot |
| `SetCustomizationLocked` | `arc9_atts_nocustomize` (always 1 while builds are owned by the core) + `ARC9_Hook_BlockAttachment` | `mgbase_sv_customization 0` | `TFA_PreCanAttach`/`TFA_PreCanDetach` → false unless the adapter flag is set |
| `SuppressDefaultAmmo` | `wep.ForceDefaultAmmo = 0` before the 0.4 s timer | none (already 0) | strip excess or set `DefaultClip`; `sv_tfa_default_clip -1` |
| `GetFireInfo` | `GetCurrentFiremode()` | `Primary.Automatic` / `BurstRounds` | `FireModes[GetFireMode()]` |
| `IsReloading` | `GetReloading()` | `HasFlag("Reloading")` | `TFA.Enum.ReloadStatus[GetStatus()]` |
| `IsAiming` | `GetInSights()` | `HasFlag("Aiming")` | `GetIronSights()` |
| `GetClip` | `Clip1()`, `GetCapacity()` | `Clip1()`, `ClipSize` (+1 when chambered) | `Clip1()`, `GetPrimaryClipSize()` |
| `GetRecoil.affectsBotAim` | false (only spread grows) | true (`ViewPunch`) | true (`ViewPunchP/Y`) |
| `projectileSpeed` | `PhysBulletMuzzleVelocity` × mod (beyond 750 HU) or nil | `Projectile.Speed` or nil | `ProjectileVelocity`, ballistics v0, or nil |
| `IsHeadshot` | nil | `dmginfo:GetDamageCustom() == 1` | nil |
| `BotAction("firemode")` | `SetFiremode(i)` | `ApplyFiremode(i)` | `CycleFireMode()` or impulse 150 |

## 6. Bot shims per adapter

### 6.1 Core rules for all bases

1. Write **button bits**, not only `SetForwardMove`: MW and ARC9 decide sprint and bipod from `IN_FORWARD`/`IN_MOVELEFT`/… (§2.6, §3.6).
2. Release `IN_ATTACK` for at least one tick between semi and burst shots (§2.4, §3.4).
3. Never send `IN_USE` together with `IN_ATTACK`, `IN_ATTACK2` or `IN_RELOAD` (ARC9 inspect and UBGL; TFA silencer and firemode).
4. Use the core's own PRNG for the AI. MW reseeds `math.random` (§3.5).
5. Own the hitgroup multipliers in one place:
   - set `arc9_mod_bodydamagecancel` consistently with the core's `ScalePlayerDamage`;
   - TFA has no hitgroup scaling;
   - MW scales the head itself.

   Prefer the core applying one table, and the adapters turning their base's own scaling off where possible. For MW: **UNVERIFIED** whether it can be turned off without editing.
6. Keep `cmd:SelectWeapon(target)` every tick until `GetActiveWeapon()` matches.

### 6.2 ARC9 `PrepareForBot` and adapter settings

1. Run `wep:SetNoPresets(true)`, then build server-side. Do not mute `SendWeapon`: other clients need the broadcast to render bot attachments, and a muted weapon dropped by a bot stays broken.
2. Set `ForceDefaultAmmo = 0` immediately after `Give`. The core gives magazines.
3. Bot presses `IN_RELOAD` itself; auto-reload is client-only.
4. View recoil is absent. Simulate it in the aim controller if difficulty needs it. Spread growth from `RecoilAmount` is still real.
5. `GetFOV`: no shim needed in `f9bbe034` (INFERENCE). If kept, scope it to `ply:IsBot()` instead of wrapping every player.
6. Global settings while the gamemode owns builds: `arc9_atts_nocustomize 1` (closes the unowned receiver), `arc9_atts_loseondie 0`. Set `arc9_free_atts` as wanted; the `ARC9_PlayerGetAtts` hook only runs at 0.

### 6.3 MW Base `PrepareForBot`

1. Firemode, melee, tac stance and underbarrel go through `BotAction` (server task calls), because the binds are read with `GetInfoNum`.
2. Use `GetInputRules().reloadTap = false` and `reselectEveryTick = true`.
3. Drop `IN_SPEED` before firing.
4. `mgbase_sv_customization 0` during the match.

### 6.4 TFA `PrepareForBot`

1. Reload tap rule: press `IN_RELOAD` for less than 0.3 s, then release. No `IN_USE`.
2. Bash with `cmd:SetImpulse(149)`, firemode with impulse 150 or `CycleFireMode()`.
3. ADS is hold-to-aim and has no resight. The bot must re-press `IN_ATTACK2` after reload or sprint.
4. Re-select the weapon when a grenade strips itself.
5. Lock with `TFA_PreCanAttach`/`TFA_PreCanDetach`.

## 7. Risks and open questions

1. **ARC9 receiver without an owner check** (§2.3). This is a real exploit on any server running ARC9 with customization on. Mitigation: `arc9_atts_nocustomize 1` whenever the core owns builds. Consider reporting it upstream (needs the user's approval).
2. **TFA client restore applies without force** (§4.3). Without the lock hook, a human's saved TFA attachments override the class build on every PVS re-entry or deploy.
3. **ARC9 instance tables:** whether each weapon instance gets its own deep copy of `SWEP.Attachments` depends on GMod's `weapons` module (**UNVERIFIED**). ARC9 sometimes assigns class tables directly (`A/cl_presets.lua:86`). Test two bots with different builds of the same class.
4. **Bot viewmodels (TFA):** reload and deploy need `owner:GetViewModel()` on the server (**UNVERIFIED** for `CreateNextBot` players). Test first.
5. **`GetInfoNum` on bots** returns the default argument (GMod wiki semantics, **UNVERIFIED** in game). All three bases read toggle and bind convars this way.
6. **Hook order:** ARC9 (`ARC9_StartCommand`) and TFA (`TFABashZoom`) run their `StartCommand` hooks before `GM:StartCommand`. The core writes the cmd in `GM:StartCommand`, so it sees their edits and overwrites them. If the core instead writes in a `hook.Add("StartCommand")`, order versus the bases' hooks is undefined.
7. **Stat parity:** ARC9 `GetProcessedValue` is state-dependent (sights, sprint, recoil). Read live stats with `isstatic = true` for UI and bot range choice.
8. **MW `math.randomseed`:** any server-side randomness in the gamemode that uses `math.random` becomes predictable while MW weapons fire.
9. **Packs:** MW Base ships no guns, and TFA and ARC9 packs vary. The `category`, `Primary.Ammo` and stats paths need a test against at least one real pack per base.
10. **Common assumptions that do not hold:**
    - `CustomizeFullLoadout` does not exist in current ARC9.
    - ARC9 recoil for bots is lost because it is client-only, not only because a gamemode overwrites view angles.
    - The `ARC9_PlayerGetAtts` hook needs `arc9_free_atts 0`.
