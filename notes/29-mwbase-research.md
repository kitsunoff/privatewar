# 29 - MW Base (`mg_base`): identity, architecture, bot behaviour and Steam Deck cost

Research for integrating MW Base into Private War and for a `deck` performance profile that cuts its frame-time
cost hard. Research explains why; it is not a decision. The plan is
[`changes/planned/mwbase-integration.md`](../changes/planned/mwbase-integration.md). Earlier adapter research:
[`08-weapon-adapters.md`](08-weapon-adapters.md) §3 and §6.3, stat modifiers:
[`12-weapon-stat-modifiers.md`](12-weapon-stat-modifiers.md) §3. Nothing here was run in game; no device was
accessed.

Evidence labels used below:

- **[src]**: read in the upstream Lua at the cited path and line (source snapshot in §1.3).
- **[api]**: returned by the public Steam Web API (`ISteamRemoteStorage/GetPublishedFileDetails/v1`) on 2026-11-21.
- **[doc]**: stated on a public page (Workshop description, GMod wiki semantics).
- **[community]**: a user claim in comments or forums; not verified.
- **[inference]**: follows from the cited code; runtime behaviour not observed.
- **[assumption]**: not verified; needs a check in game.

No upstream code is copied into this repository. File references describe behaviour only.

## 1. Identity, versions and source

### 1.1 Workshop items

| Item | Workshop ID | Title on 2026-11-21 | Size | Updated | Subscribers |
| --- | --- | --- | --- | --- | --- |
| MW Base (the base, no guns) | [2459720887](https://steamcommunity.com/sharedfiles/filedetails/?id=2459720887) | "Modern Wokefare Base" | 1078 MB | 2026-09-27 | 1 135 640 |
| Assault Rifles pack | [2528829149](https://steamcommunity.com/sharedfiles/filedetails/?id=2528829149) | "Modern Warfare 2019 SWEPS - Assault Rifles" | 671 MB | 2026-03-09 | 661 663 |
| Submachine Guns pack | [2802430252](https://steamcommunity.com/sharedfiles/filedetails/?id=2802430252) | "Modern Warfare 2019 SWEPS - Submachine Guns" | 584 MB | 2026-03-09 | 498 319 |
| Pistols pack | [2459723892](https://steamcommunity.com/sharedfiles/filedetails/?id=2459723892) | "Modern Warfare 2019 SWEPS - Pistols" | 819 MB | 2026-03-09 | 638 276 |
| Shotguns pack | [2751323984](https://steamcommunity.com/sharedfiles/filedetails/?id=2751323984) | "Modern Warfare 2019 SWEPs - Shotguns" | 653 MB | 2026-03-09 | 479 862 |
| Marksman Rifles pack | [2864559679](https://steamcommunity.com/sharedfiles/filedetails/?id=2864559679) | "Modern Warfare 2019 SWEPs - Marksman Rifles" | 368 MB | 2026-03-09 | 346 285 |
| Light machine guns pack | [2960120610](https://steamcommunity.com/sharedfiles/filedetails/?id=2960120610) | "Modern Warfare 2019 SWEPS - Lightmachine Guns" | 1132 MB | 2026-03-22 | 298 013 |
| Sniper Rifles pack | [2918635913](https://steamcommunity.com/sharedfiles/filedetails/?id=2918635913) | "Modern Warfare 2019 SWEPs - Sniper Rifles" | 575 MB | 2026-03-09 | 358 427 |
| Rigs (arms models) | [2802427264](https://steamcommunity.com/sharedfiles/filedetails/?id=2802427264) | "Modern Warfare 2019 SWEPS - Rigs" | 600 MB | 2023-12-16 | 287 209 |

- All rows are **[api]** (public, `banned 0`, `visibility 0`). The base creator SteamID is `76561198155440595`.
  The base was posted 2021-04-17.
- Credits in the base description **[doc]**: Mushroom Guy (code), Viper (models, animations, sounds), with
  Shadowdark listed as a contributor. "Modern Wokefare Base" is the uploader's current title of the same item that
  the community calls "Modern Warfare Base" or "MW Base"; class prefix `mg_`, base class `mg_base`.
- **False signal, corrected:** an anonymous fetch of the Workshop HTML shows the banner "This item has been removed
  from the community because it violates Steam Community & Content Guidelines" and "incompatible with Garry's Mod".
  The Steam API reports the item public and not banned, with 1.1 M subscribers, so the banner is page-template text
  served to anonymous clients, not the item's state **[api]**. The user should still confirm the subscription works
  in the Steam client.
- Pack IDs come from a Workshop search by title and were confirmed through the API. Pack-to-base "Required items"
  links were not fetched (Steam answered HTTP 429); confirm in the Steam client **[assumption]**.
- Not MW Base: "Modern Warfare: LITE" is a separate, incompatible base **[doc]**; compressed re-uploads of the packs
  exist and are not covered here.

### 1.2 Disk and memory budget (Steam Deck)

The base plus the Assault Rifles, Submachine Guns and Pistols packs is about 3.15 GB on disk **[api]**. Every
further pack adds 0.4 to 1.1 GB. Download size matters less than the model and material load at the first `Give`
of each class (see §5.4).

### 1.3 Where the source lives

- There is **no official repository**. The Workshop GMA is canonical.
- Lua-only mirror read for this note: <https://github.com/Casualez/mwbase>, commit
  `56890bd53361a0512d00a0b42b762c08941cca3b` ("first commit", 2026-03-30), 343 Lua files, no licence file.
  It was shallow-cloned into a scratch directory and only read.
- Other mirrors: `1yling/Modern-Warfare-Base` (with content, pushed 2025-04-04), `rlenhub/mgbase-fork` (2021).
- **Version drift:** the mirror predates the Workshop update of 2026-09-27. Every **[src]** claim below must be
  re-checked against the installed GMA (change record, step 0). The structure matches the one cited in
  `notes/08` §3, but line numbers differ (see §9).
- Licence: the mirror carries no licence and the base ships Activision-derived assets. Private War must not vendor
  any of it (`CLAUDE.md`, "Third-party code"); the integration uses only public tables, methods, hooks and ConVars.

Path prefixes below: `M/` = `lua/weapons/mg_base/`, `MS/` = `M/modules/shared/`, `MT/` = `MS/tasks/`,
`VM/` = `lua/entities/mg_viewmodel/`, `L/` = `lua/` (all relative to the mirror root).

## 2. Architecture relevant to Private War

### 2.1 SWEP base class and detection

- `mg_base` derives from `weapon_base`; `Category = "MG"`, `Spawnable = false`, `AdminOnly = false`
  (`M/shared.lua:56-60`) **[src]**. Packs are `weapons.IsBasedOn(class, "mg_base")` (`M/init.lua:64`) **[src]**.
- `PreRegisterSWEP` hook `MW19_PreRegisterSWEP` (`L/autorun/mw_loader.lua:44-89`) **[src]**: only SWEPs with
  `Customization`; refuses old-format SWEPs (string slot keys) by returning `false`; drops attachment classes missing
  from `MW_ATTS`; assigns `Bullet.TracerName` by `SubCategory` (`"Shotguns"`, `"Sniper Rifles"`, `"Pistols"`,
  `"Submachine Guns"`, else the default tracer).
- Globals: `MW_ATTS` (attachment registry, `L/autorun/mw_assets/attachments.lua:3`), `MW_PRESETS`, `MW_RIGS`,
  `MW_GLOVES`, `SLOT_CONVERSIONS = -999` (`mw_loader.lua:34`) **[src]**.
- The weapon is a **task state machine**: `SWEP.Tasks` with priorities (`MS/sh_tasks.lua:29-108`), a networked
  current task and a bit field of flags (`MS/sh_datatables.lua:50-93`). `HasFlag("Reloading")`, `"Aiming"`,
  `"Lowered"` (safety), `"Holstering"`, `"CanSwitch"`, `"Rechambered"`, `"Meleeing"` **[src]**.

### 2.2 Stat storage

| Stat | Field | Unit and rule | Source |
| --- | --- | --- | --- |
| Damage | `Bullet.Damage = {near, far}` | per trigger pull; each pellet gets `max(damage / NumBullets, 1)` | `MS/sh_primaryattack_behaviour.lua:112-115` |
| Fall-off | `Bullet.DropOffStartRange`, `Bullet.EffectiveRange` | metres; lerp over `(dist - start) / effective`, so far damage from `start + effective` | `:108-114` |
| Max range | `Bullet.Range` × `mgbase_sv_range` | metres → HU (`m * 100 / 2.54`) | `:56-58`, `:381` |
| Pellets | `Bullet.NumBullets` | count | `:377` |
| Hit groups | `Bullet.HeadshotMultiplier`, `LimbMultiplier`, `TorsoMultiplier` | see §2.7 | `:150-165` |
| Penetration | `Bullet.Penetration = {MaxCount, DamageMultiplier, Thickness}` | traces per hit, §5.2 | `:120-142`, `:291-347` |
| Ricochet | `Bullet.Ricochet` (boolean) | §5.2 | `:193-285` |
| RPM | `Primary.RPM` | delay `60 / RPM` | `M/shared.lua:670-672` |
| Magazine | `Primary.ClipSize`; `+1` when `CanChamberRound` and rechambered | rounds | `MS/sh_reload_behaviour.lua:3-9` |
| Fire mode | `Primary.Automatic`, `Primary.BurstRounds`, `Firemodes[i].OnSet` | | `MT/task_primaryfire.lua:17-33` |
| Spread | `Cone = {Hip, Ads, TacStance, Increase, Max, ...}` ÷ `mgbase_sv_accuracy` | | `:423-444` |
| Recoil | `Recoil = {Vertical{min,max}, Horizontal{min,max}, AdsMultiplier, Punch, Seed, ...}` × `mgbase_sv_recoil` | degrees | `:39-54` |
| Timings | `Animations[name] = {Fps, Length, Sequences, ...}`; length = `Length / (Fps / 30)`; lookup is case-insensitive and merges `Base` animations with `table.Copy` | seconds | `M/shared.lua:699-736` |
| Projectile | `Projectile = {Class, Speed, Gravity, Velocity, ...}` | entity per shot | `:514-550`, `MS/sh_stats.lua:35-39` |
| Movement | none in the base | | grep: no speed field |

All **[src]**. Ammo: `Primary.DefaultClip = 0` (`M/shared.lua:80`) and `Initialize` sets `Clip1 = ClipSize`
(`:498`), so `Give` adds a full magazine and no reserve **[src]**.

### 2.3 Attachments and customization

- Slot model: `SWEP.Customization[slot] = {"att_class", ...}`, integer slots, **index 1 is the slot default** (a
  real attachment, usually with a model) **[src]** (`M/shared.lua:487-496`).
- `Initialize` creates the index-1 attachment of every slot and runs `BuildCustomizedGun` (`M/shared.lua:487-496`)
  **[src]**.
- `BuildCustomizedGun` (`MS/sh_customization.lua:233-512`) **[src]**:
  1. resets the instance with `DeepObjectCopy(weapons.Get(class), self)` (`:235`): every class field and every
     class **function** is copied onto the instance again;
  2. re-copies `Customization` and `Animations` from the stored class (`:256-257`);
  3. reverts disallowed attachments to index 1 (`:294-298`);
  4. deep-copies the whole instance into a `stats` table, runs every attachment's `Stats(stats)`, copies back
     (`:308-387`), runs `PostProcess`, clamps the clip, recreates attachment models (client), re-applies the firemode;
  5. calls `hook.Call("OnBuildCustomizedGun", nil, self)` (`:508`), documented in the code as the extension point
     for third-party stat scaling. Only `hook.Add` listeners run (gamemode table is `nil`).
- `Attach(slot, index)` calls `BuildCustomizedGun` once per attachment (`:34-61`) **[src]**.
- Server apply: `SWEP:CreateAttachmentEntity(class)` (`M/shared.lua:350-373`) spawns one networked `mg_attachment`
  entity, finds slot and index by scanning `Customization` with `pairs` and the **first** match wins, parents it to
  the weapon and `DeleteOnRemove`. **[src]** If a class appears in two slots the slot is ambiguous **[inference]**.
- `mg_attachment` (`L/entities/mg_attachment.lua:43-70`) **[src]**: on the server it removes any other attachment
  entity of the same slot and calls `weapon:Attach(slot, index)`. On every client it starts a 0-interval timer that
  retries until the weapon is ready, then calls `Attach`, so **each attachment entity runs one full
  `BuildCustomizedGun` on every client that receives it**.
- Validation: `IsAttachmentAllowed` (`MS/sh_customization.lua:837-864`) checks `mgbase_sv_customization_limit`
  (non-cosmetic count), `hook.Run("MW19_AllowAttachment", wep, att) == false`, and blocker attachments **[src]**.
- Network receiver `mgbase_customize_att` (`M/init.lua:46-78`) **[src]**: returns at once when
  `mgbase_sv_customization` is 0; checks owner, a 1 s restore window, base class and slot; re-picking the installed
  class toggles back to index 1. `CreateAttachmentEntity` itself ignores the ConVar.
- Customize task: `CanBeSet` requires `mgbase_sv_customization` (`MT/task_customize.lua:8-12`) **[src]**.
- Presets: client-only spawn presets (`mgbase_presetspawnmethod`, `M/shared.lua:513-570`); `mw_utils.LoadPreset`
  sends `mgbase_customize_att` from a client or spawns entities on the server (`L/includes/modules/mw_utils.lua:229-247`)
  **[src]**.
- Attachment metadata in `MW_ATTS[class]`: `Name`, `Icon`, `Category`, `CosmeticChange`, `Model`, `Stats`
  (function), `Laser`, `Flashlight`, `Optic`, `Reticle`, `Bipod`, `Base` **[src]** (attachment base files under
  `M/modules/attachmentss/base/`).
- Option stats for T-11.7 are **functions**, not declarative tables: a stat delta needs `att:Stats(copy)` on a copy
  of the class table **[src]**.

### 2.4 Client and server effects

| Effect | Where it runs | Cost driver | Source |
| --- | --- | --- | --- |
| Viewmodel entity `mg_viewmodel` | created on the **server** per weapon in `Initialize`, networked, parented | one extra edict per MW weapon | `M/shared.lua:437-447` |
| Viewmodel rig models | every client creates 3 `ClientsideModel`s (rig, gloves, c_hands) per `mg_viewmodel` it receives, including other players' | client entities and memory per weapon | `VM/cl_init.lua:11-164` |
| Viewmodel animation sync | server `PlayAnimation` broadcasts `mgbase_viewmodelanim` (unreliable) to **all** clients on every anim (each shot, reload, ADS); `GetAnimID` sorts `Animations` with `SortedPairs` per call | server Lua and bandwidth per shot per bot | `VM/shared.lua:92-104`, `:138-167` |
| Client reconcile | every client's `mg_viewmodel:Think` runs `ReconcileServerAnims` **before** the local-player guard, so bots' hidden viewmodels play sequences too | client Lua per bot anim | `VM/client/cl_animation.lua:209-271` |
| Third-person gesture | `mgbase_tpanim` per shot and reload, `SendOmit(owner)` | bandwidth | `M/shared.lua:738-754` |
| Tracers | `mgbase_fire_tracer` **reliable**, `SendOmit(owner)`, once per bullet callback (per pellet), then `util.ParticleTracerEx` on each client | bandwidth, client particles | `MS/sh_primaryattack_behaviour.lua:383-390`, `:552-584` |
| Muzzle flash and shell ejection | animation events of `mg_viewmodel` (`CL_EVENT_DISPATCHEFFECT0`, `CL_EVENT_EJECTBRASS1`): first person on the viewmodel, otherwise particles on the world model and `mwb_shelleject_*` effects | client particles; shell effect traces at 10 Hz for 1 s | `VM/client/cl_events.lua:104-167`, `:224-310`, `L/effects/mwb_shelleject.lua:55-92` |
| Weapon-level shell override | `FireAnimationEvent` calls `weapon:HandleEjection(name)` when the weapon defines it | designed per-weapon hook | `VM/client/cl_events.lua:281-285` |
| World model | `RenderOverride` runs `SetupBones` and draws every attachment's third-person model separately (`m_TpModel`), each frame | draw calls per attachment | `M/modules/client/cl_worldmodel_render.lua:6-46` |
| Attachment models | client creates 2 `ClientsideModel`s per attachment with a model (viewmodel copy and `m_TpModel`), defaults included | client entities | `MS/sh_customization.lua:109-199` |
| Full-update reparent | client `PreRender` hook iterates every registered clientside model each frame with `GetInternalVariable` | client Lua per frame, linear in MW models | `L/includes/modules/mw_utils.lua:268-287` |
| Reverb | `SWEP:Think` resumes a coroutine on **both realms** for every active MW weapon: 36 `TraceHull`s of 32768 units over 4 ticks every ~0.1 s, only to pick an indoor or outdoor sound layer | server traces per armed bot | `MS/sh_think.lua:57-58`, `M/modules/reverb/mw_reverbimpl.lua:3-74`, `M/modules/reverb/mw_reverb.lua:133-191` |
| Dynamic lights | `MakeLight` for HE and Dragon's Breath ammo impacts; explosive entities | client | `MS/sh_primaryattack_behaviour.lua:64-83` |
| Lasers | per frame per weapon with a laser, third person included: one `TraceLine`, two beams, one quad | client | `M/modules/attachmentss/base/att_laser.lua:22-80`, `:124-144` |
| Flashlight | `ProjectedTexture` and a particle, viewmodel (local player) only | client GPU | `att_laser.lua:82-120` |
| Scopes | **no picture-in-picture**: stencil cut-out plus a 512 px render target filled with a 2D parallax pass, local player while aiming | small | `M/modules/attachmentss/base/att_optic.lua:8`, `:40-128` |
| Bipod | one `TraceHull` per `Think` while standing still with a bipod | server and client | `MS/sh_bipod_behavior.lua:23-39` |
| Empty server hook | `Think` hook `MW19_SafeToDeleteThinkHook` with a commented-out body | negligible | `M/init.lua:80-92` |

All **[src]**. Whether the engine dispatches animation events of a hidden other player's `mg_viewmodel` (and so
whether bots show third-person muzzle flashes and shells at all) is **[assumption]**; check in game (change
record, checkpoint).

### 2.5 Animations, gestures, sounds, inspect, TPIK

- Timing is table-driven (`Animations`), not engine-sequence driven; the viewmodel playback rate is `Fps / 30`
  (`VM/shared.lua:151-152`) **[src]**. A server-side `mg_viewmodel` exists per weapon, so the base does **not** need
  the engine viewmodel `ply:GetViewModel()`: the weapon uses its own networked `ViewModel` entity
  (`MS/sh_datatables.lua:67`) **[src]**. Bots have no client, which is fine for timing.
- Third-person: `PlayerGesture` (`M/shared.lua:738-754`) **[src]**. There is no TPIK (no hand IK on world models);
  the closest is bone manipulation of the world model per frame **[src]**.
- Sounds: fire sound and optional trailing sound per shot from the server (`MT/task_primaryfire.lua:119-124`),
  plus the reverb layer and reflection sounds (`mw_reverb.lua:147-173`), shell casing sounds on impact
  (`L/effects/mwb_shelleject.lua:35-49`) **[src]**.
- Inspect, melee, safety, firemode, tac stance and underbarrel are bound through `mw_input` client binds
  `mgbase_binds_*` (`L/includes/modules/mw_input.lua:12-25`), defaulting to the keys bound to `+grenade2` (melee),
  `+use` (switch sights, tac stance), `+menu_context` (customize), `+reload` (inspect), `+grenade1` (firemode)
  (`MS/sh_button_dispatcher.lua:18-26`) **[src]**, read through `PlayerButtonDown`. Bots press no buttons.

### 2.6 Hooks MW Base exposes or uses

| Hook | Kind | Use for Private War | Source |
| --- | --- | --- | --- |
| `OnBuildCustomizedGun(wep)` | `hook.Call`, both realms, after every build | stat modifiers (04 d.6) and per-weapon `deck` cuts that must survive rebuilds | `MS/sh_customization.lua:508` |
| `MW19_AllowAttachment(wep, att)` | `hook.Run`, return `false` to refuse | not needed while the ConVar lock is on | `:854` |
| `MW19_OnAssetsLoaded()` | `hook.Call` after the attachment and preset load | catalogue memo invalidation | `L/autorun/mw_loader.lua:42` |
| `PreRegisterSWEP` | engine hook, MW filters packs | none | `:44-89` |

All **[src]**. There is no kill hook and no killicon for guns.

### 2.7 Damage and hit groups

- Head: `damage * 0.5 * HeadshotMultiplier * 2` and `dmginfo:SetDamageCustom(1)`; a generic hit above eye height
  also counts as head without the marker. Arms × 4; legs × 4 × 0.75 × `LimbMultiplier`; torso × `TorsoMultiplier`
  (`MS/sh_primaryattack_behaviour.lua:150-165`) **[src]**.
- The × 4 limbs pre-compensate the base gamemode's `ScalePlayerDamage` (limbs × 0.25, head × 2). Private War does
  not override `ScalePlayerDamage` and derives from `base` (no `DeriveGamemode`, grep), so the result is MW's
  intended balance **[inference]**: head 2 × `HeadshotMultiplier`, limbs × 1 (legs × 0.75). This answers the open
  item of `notes/08` §6.1 rule 5: no change is needed; verify TTK in the checkpoint.
- `mgbase_sv_pvpdamage` and `mgbase_sv_pvedamage` multiply the damage (`:144-148`) **[src]**.

## 3. Bot compatibility

| Path | Effect on a Private War bot (a real `Player`) | Shim | Evidence |
| --- | --- | --- | --- |
| Fire: `PrimaryAttack` sets `AutoFire`; `Think` clears it when `IN_ATTACK` is up | automatic works with held `IN_ATTACK`; semi and burst need one tick released | `releaseBetweenShots` for non-automatic | `M/shared.lua:618-626`, `MS/sh_think.lua:60-64` **[src]** |
| Reload: `IN_RELOAD` → `SWEP:Reload` → task `Reload` | plain press works | `reloadTap = false` | `M/shared.lua:606-612` **[src]** |
| Auto-reload: `GetInfoNum("mgbase_autoreload", 1)` | bots get the default 1, so an empty magazine reloads by itself | none | `MS/sh_think.lua:23-27` **[src]**; default for bots **[doc]** (GMod wiki: no userinfo returns the default) |
| ADS: hold `IN_ATTACK2` (`IN_ATTACK` for `UseLauncherLogic`); `GetInfoNum("mgbase_toggleaim", 0)` | hold-to-aim for bots | `adsKey` per weapon | `MS/sh_aim_behaviour.lua:11-41` **[src]** |
| Weapon switch: `Holster` starts the holster task; only the client calls `input.SelectWeapon` | one `cmd:SelectWeapon` leaves the bot holstering; repeating it works because an equal-priority task is not re-set and `CanSwitch` stays | `reselectEveryTick = true` | `MT/task_holster.lua:12-28`, `MS/sh_tasks.lua:58-60` **[src]**, corrects the **[inference]** label of `notes/08` §3.6 |
| Sprint: needs `IN_SPEED` and a movement button bit; sprint priority 6 is above fire (3) | `IN_SPEED` while moving blocks fire | `noSprintWhileFiring`; movement bits | `MT/task_sprint_in.lua:8-14` **[src]** |
| Bipod: deploys when no movement bit is down | a bot moved only by `SetForwardMove` counts as standing | write movement bits | `MS/sh_bipod_behavior.lua:23-39` **[src]** |
| Firemode, melee, safety: `mw_input` binds | unreachable through `CUserCmd` | `BotAction`: `ApplyFiremode`, `TrySetTask("Melee")`, `TrySetTask("Raise")` | `MS/sh_button_dispatcher.lua` **[src]** |
| Recoil: `ViewPunch` always; `SetEyeAngles` when `Recoil.Punch` | the shot direction is `EyeAngles + ViewPunchAngles + breathing sway`, so recoil deflects bot bullets on the server | `affectsBotAim = true` | `MS/sh_primaryattack_behaviour.lua:361-362`, `MT/task_primaryfire.lua:136-149` **[src]** |
| Aim assist: hull trace size 1 when aiming, `GetInfoNum("mgbase_aimassist", 1)` and `mgbase_sv_aimassist` | bots get aim assist while aiming; shotguns always | user decision (§7) | `:369-379` **[src]** |
| Global RNG: `math.randomseed` on every shot and every hit | reseeds `math.random` for all server Lua | core PRNG (already a core rule) | `:42`, `:194` **[src]** |
| `GetConVar("mgbase_tacsprint")` in a shared task | a **client** ConVar read on the server: works on a listen server (shared engine ConVars), `nil` and a Lua error on a dedicated server when a player sprints | none on the Deck; blocks a dedicated Docker runner | `MT/task_sprint_in.lua:18,37,50`, `M/cl_init.lua:11` **[src]**, runtime **[inference]** |
| Tracking launchers: `SendLua` to the owner | sent to a bot | avoid tracking weapons for bots | `MS/sh_aim_behaviour.lua:184-212` **[src]** |
| `ply:GetViewModel()` | not used; the weapon owns an `mg_viewmodel` | none | grep **[src]** |

## 4. ConVar inventory

Every `CreateConVar` / `CreateClientConVar` in the mirror **[src]**. "Perf" is an estimate for a listen server with
about 9 bots: **none**, **low** (under 0.05 ms per frame or tick), **medium**, **high**.

### 4.1 Server (replicated, archived unless noted)

| ConVar | Default | Meaning | Perf | Source |
| --- | --- | --- | --- | --- |
| `mgbase_sv_pvpdamage` | 1 | PvP damage multiplier (0 to 10) | none | `M/shared.lua:303` |
| `mgbase_sv_pvedamage` | 1 | PvE damage multiplier | none | `:304` |
| `mgbase_sv_recoil` | 1 | recoil multiplier | none | `:305` |
| `mgbase_sv_range` | 1 | max range multiplier | none | `:306` |
| `mgbase_sv_accuracy` | 1 | divides the cone (0.01 to 10) | none | `:307` |
| `mgbase_sv_customization` | 1 | allows the native menu and the `mgbase_customize_att` receiver (notify flag) | none; **security lock** | `:308` |
| `mgbase_sv_customization_limit` | 0 | max non-cosmetic attachments, 0 = unlimited; above 0 silently reverts builds | none; must be 0 for gamemode builds | `:309` |
| `mgbase_sv_aimassist` | 1 | hull-trace aim assist while aiming | low (hull vs line trace) | `:310` |
| `mgbase_sv_breathing` | 1 | scope breathing sway (moves the shot) | none | `:311` |
| `mgbase_sv_full_penetration` | 0 | penetrate on every shot instead of every second round (magazines over 10) | medium when 1 | `:312`, used `MS/sh_primaryattack_behaviour.lua:126` |
| `mgbase_sv_firstdraws` | 1 | first-draw animations | none | `:313` |
| `mgbase_sv_tacstance` | 1 | tactical stance | none | `:314` |
| `mgbase_sv_sprintreloads` | 0 | reload while sprinting | none | `:315` |
| `mgbase_sv_sprintvmanip` | 1 | VManip while sprinting (only with the VManip addon) | none | `:316` |
| `mgbase_debug_reverb` | 0 (not archived) | reverb debug overlay | medium when 1 | `:317` |
| `mgbase_debug_range` | 0 (not archived) | range overlay; runs `clear_debug_overlays` and a timer per hit | medium when 1 | `:318`, `:122-124` |
| `mgbase_debug_projectiles` | 0 (not archived) | projectile overlay | low | `:319` |
| `mgbase_debug_mag` | 0 (not archived) | forces magazines to 1 (cheat) | none | `:320` |
| `mgbase_precacheatts` | 0 | precache every attachment model while the attachments load (autorun, so it applies from the next map load) | moves first-attach stalls to map load; raises the model precache count | `L/autorun/mw_loader.lua:1`, `L/autorun/mw_assets/attachments.lua:27-33` |

### 4.2 Client (archived; "userinfo" means the server can read it with `GetInfoNum`)

| ConVar | Default | Userinfo | Meaning | Perf | Source |
| --- | --- | --- | --- | --- | --- |
| `mgbase_rig` | `chands` | no | first-person arms rig | low | `M/cl_init.lua:7` |
| `mgbase_rig_skin` | 0 | no | rig skin | none | `:8` |
| `mgbase_gloves` | (empty) | no | gloves model | low | `:9` |
| `mgbase_gloves_skin` | 0 | no | gloves skin | none | `:10` |
| `mgbase_tacsprint` | 1 | yes | tac-sprint input type (0 to 2); also read on the server, §3 | none | `:11` |
| `mgbase_toggleaim` | 0 | yes | 0 hold, 1 toggle | none | `:12` |
| `mgbase_autoreload` | 1 | yes | auto-reload | none | `:13` |
| `mgbase_aimassist` | 1 | yes | personal aim assist | low | `:14` |
| `mgbase_manualrechamber` | 0 | yes | manual bolt | none | `:15` |
| `mgbase_underbarrelswitch` | 1 | yes | remember underbarrel | none | `:16` |
| `mgbase_fx_blur` | 0 | no | first-person blur (extra model passes) | medium when 1 | `:17`, `VM/client/cl_render.lua:188-230` |
| `mgbase_fx_laser_weaponcolor` | 0 | no | laser uses weapon colour | none | `:18` |
| `mgbase_fx_vmfov`, `mgbase_fx_vmfov_ads` | 1 | no | viewmodel FOV | none | `:19-20` |
| `mgbase_fx_vmposx`, `_vmposy`, `_vmposz` | 0 | no | viewmodel offset | none | `:21-23` |
| `mgbase_fx_debris` | 1 | no | debris effects from explosions | medium during explosions | `:24`, `L/effects/mwb_grenade_explosion.lua:91`, `L/effects/mwb_rpg_explosion.lua:84` |
| `mgbase_hud_xhaircolor` | `255 255 255` | no | crosshair colour | none | `:25` |
| `mgbase_hud_xhair` | 1 | no | crosshair (0 to 2) | low | `:26` |
| `mgbase_hud_xhairdot` | 1 | no | centre dot | none | `:27` |
| `mgbase_hud_firemode` | 1 | no | firemode HUD | low | `:28` |
| `mgbase_hud_controls` | 1 | no | control tips | low | `:29` |
| `mgbase_debug_freeview` | 0 (not archived) | no | debug | none | `:30` |
| `mgbase_debug_crosshair` | 0 | no | debug | none | `:31` |
| `mgbase_debug_vmrender` | 1 | no | draws the viewmodel; 0 hides it (not a perf option) | n/a | `:32` |
| `mgbase_debug_wmrender` | 1 | no | draws world models; 0 hides every MW gun (not a perf option) | n/a | `:33` |
| `mgbase_presetspawnmethod` | 0 | no | client spawn presets (0 none) | none | `:34` |
| `mgbase_sensitivity_ads`, `mgbase_sensitivity_tacstance` | 1 | yes | sensitivity | none | `:35-36` |
| `mgbase_binds_doubletap_delay` | 0.3 | yes | bind double-tap window | none | `MS/sh_button_dispatcher.lua:16` |
| `mgbase_binds_<name>` for `melee`, `switchsights`, `tacstance`, `customize`, `safety`, `inspect`, `firemode`, `holster`, `underbarrel` | key of the source bind or 0 | yes | packed key codes | none | `L/includes/modules/mw_input.lua:12-25`, `MS/sh_button_dispatcher.lua:18-26` |

**There is no ConVar for muzzle flashes, shell ejection, tracers, reverb, lasers, ricochet, penetration (other
than `full_penetration`), viewmodel animation sync or LOD.** Those costs can only be cut through public per-weapon
fields and the `OnBuildCustomizedGun` hook (§6), or by loadout choices.

## 5. Where the frame time goes (estimates)

Numbers are estimates from the code, not measurements. The Deck measurement in the change record decides.

### 5.1 Server, per armed bot

1. **Reverb job**: about 36 hull traces of 32768 units per ~0.16 s cycle, about 3 per tick per bot holding an MW
   gun, ending early only outdoors (`mw_reverbimpl.lua:25-65`). Ten bots: about 30 long hull traces per tick for an
   audio choice. Likely the largest steady server cost. **High.**
2. **Per shot**: `PlayAnimation` (`SortedPairs` over `Animations` and a broadcast), `GetAnimation` linear scans
   with `string.lower` and `table.Copy` for animations with `Base` (`M/shared.lua:713-736`), `PlayerGesture` net,
   `HandleReverb` sounds, `FireBullets` per pellet, `FireTracer` reliable net per pellet. **Medium**, scales with
   RPM × bots.
3. **Per hit**: hit-group maths, attachment `OnImpact` loop, `util.PointContents`; ricochet chance on world hits
   (when `Bullet.Ricochet`): `ents.FindInSphere(hitpos, 1024)` with line-of-sight checks and one more `FireBullets`;
   penetration (every second round or magazines ≤ 10): two `TraceLine`s and two `FireBullets`. **Medium.**
4. **Builds** (`BuildCustomizedGun`): several deep copies of the whole weapon table per attachment; N attachments
   applied one by one give N + 1 builds on the server and on every client. A stall at spawn, not a steady cost.
   **High at spawn**; measure (change record).
5. Edicts: 1 `mg_viewmodel` plus 1 `mg_attachment` per non-default slot per MW weapon **[src]**.

### 5.2 Client (the Deck host renders everything)

1. Entity load: per MW weapon received, 3 rig models plus 2 models per attachment with a model; the per-frame
   `PreRender` reparent loop walks all of them (`mw_utils.lua:268-287`). Inactive weapons of other players may also
   be transmitted **[assumption]**.
2. Per-shot effects from bots: `mgbase_fire_tracer` particles (per pellet), muzzle particles and shells (if the
   hidden viewmodel dispatches events, §2.4).
3. Every rebuild on the client (`mg_attachment` arrivals) repeats N full builds, also on re-entry into the PVS
   (entities are recreated) **[inference]**: a stutter source whenever bots appear.
4. World model draws: one draw per attachment model per gun plus `SetupBones` each frame.
5. Lasers on bots: a trace and three sprite draws per frame per bot.

### 5.3 Community reports

Searches found no MW Base specific performance thread. One ARC9 thread claims ARC9 costs more frame rate than
MW Base **[community]** ([ARC9 discussion](https://steamcommunity.com/workshop/filedetails/discussion/2910505837/3730701797624474013)).
Comments on compressed packs report Lua and particle errors after GMod updates **[community]**. Not a basis for
decisions.

### 5.4 First `Give` stalls

ARC9 showed 0.3 to 0.6 s per first `Give` of a class (`docs/perf-report.md`, "ARC9"). MW loads the server-side
`mg_viewmodel` model (`vm:SetModel(self.VModel)`, `M/shared.lua:444`) and the world model at `Give`, and every
client loads attachment models at the first build **[src]**; a similar stall is likely **[inference]**.
`mgbase_precacheatts 1` moves attachment model loads to the map load, at the price of precaching every attachment
model of every pack (precache table pressure; GMod's model precache table is limited) **[assumption]**: measure
before deciding.

## 6. What can be cut without editing MW Base

| Cut | Mechanism (public) | Realm | Gameplay effect | Class |
| --- | --- | --- | --- | --- |
| Customization lock | `mgbase_sv_customization 0`, `mgbase_sv_customization_limit 0` | server | none (04 d.2) | lock, always |
| Debug overlays | `mgbase_debug_range 0`, `mgbase_debug_reverb 0`, `mgbase_debug_projectiles 0` | server | none | must-cut |
| Full penetration | `mgbase_sv_full_penetration 0` (the default) | server | fewer penetrations | must-cut (default enforced) |
| Blur and debris | `mgbase_fx_blur 0`, `mgbase_fx_debris 0` | client | visual only | must-cut |
| MW HUD parts | `mgbase_hud_firemode 0`, `mgbase_hud_controls 0`; keep the crosshair (09 d.1) | client | none | HUD set, not perf |
| Reverb job | in `OnBuildCustomizedGun`: per-instance `CreateAndResumeReverbJob` no-op and `LastReverbState = true` (re-applied after every build, because the build copies class functions back) | both | always the outdoor sound layer | must-cut, needs approval of the technique |
| Ricochet | in `OnBuildCustomizedGun`: `wep.Bullet.Ricochet = false` | both | no ricochet bullets (MW's ricochets steer toward enemies) | must-cut (precedent: `arc9_ricochet 0` in 04 d.7) |
| Third-person shells | client, weapons not carried by the local player: per-instance `HandleEjection` returning `true` (the designed weapon-level override) | client | no shells from others | must-cut |
| Penetration | `wep.Bullet.Penetration.MaxCount = 0` in the hook | both | no wall-bangs | measure-then-decide |
| Bot tracers | server, bot-owned weapons: per-instance `FireTracer` no-op | server | no tracers from bots for other players | measure-then-decide; visual check |
| Viewmodel anim broadcast for bots | server, bot-owned weapons: per-instance `mg_viewmodel.PlayAnimation` that skips the broadcast | server | possibly no third-person muzzle flashes from bots | measure-then-decide; blocked on the §2.4 assumption |
| Attachment precache | `mgbase_precacheatts 1` (not restored, like the ARC9 precache pair) | server | none | measure-then-decide |
| Fewer attachment models | bot builds limited in count, no `Lasers` category | loadout | bots' builds are simpler | user decision |
| Aim assist | `mgbase_sv_aimassist 0` | server | humans and bots lose aim assist | user decision, not perf |

Not cuttable without detouring MW Base (out of scope): the client `PreRender` reparent loop, the empty server
`Think` hook, `GetAnimation` copies, `BuildCustomizedGun` deep copies, the `mg_viewmodel` and `mg_attachment`
edicts, `math.randomseed`.

## 7. Questions this research cannot answer

1. Does the hidden viewmodel of another player dispatch animation events on the client (third-person muzzle and
   shells)? In game.
2. Are inactive weapons of other players transmitted (client models per bot secondary)? In game (`ents.GetAll`
   count of `mg_viewmodel` on the client).
3. `BuildCustomizedGun` cost per attachment on the Deck, server and client. Micro-benchmark.
4. Precache count headroom with the chosen packs and `mgbase_precacheatts 1`. Map-load log.
5. `SubCategory` strings of the installed packs (only four are confirmed in the base, §2.1). Read in game.
6. `Projectile.Speed` units (`notes/08` says HU/s; the base's own projectile entity is not read here). Source of
   the installed GMA.

## 8. Recommendations for the integration (research view)

1. Mirror `privatewar-arc9`: adapter `mwbase`, module `mwbase`, host setting `mwbase.perf` (`deck` default, `off`),
   crash-safe save and restore.
2. Extract the ConVar swap and crash-safe backup of `modules/arc9/sh_perf.lua` into a small weapons-lane helper in
   `modules/weapons_core/` instead of copying it; leave ARC9 on its own copy until a separate migration.
3. Put every per-weapon cut in one `OnBuildCustomizedGun` listener, so it survives rebuilds and costs nothing
   between builds.
4. Measure before cutting penetration, bot tracers and the bot viewmodel broadcast (T-11.8 protocol).
5. Start with the base plus the Assault Rifles, Submachine Guns and Pistols packs.

## 9. Corrections to existing repository text

1. `notes/08` §3 line numbers do not match the mirror read here (for example `Category`/`Spawnable` at
   `M/shared.lua:56-57`, not `:43-47`; `DefaultClip` at `:80`, not `:67`; semi `AutoFire` removal at
   `MT/task_primaryfire.lua:83-85`, not `:61-63`; ADS length in `GetAnimLength` at `M/shared.lua:699-711`). `notes/08`
   records no source version for MW; the behaviour it describes matches.
2. `notes/08` §3.6 marks the holster deadlock as inference; the source confirms it and confirms that repeating
   `cmd:SelectWeapon` resolves it (§3).
3. `notes/08` §3.6 lists `mgbase_viewmodelanim` as the bandwidth item; there are two more per-shot messages,
   `mgbase_tpanim` and the reliable per-pellet `mgbase_fire_tracer` (§2.4).
4. `notes/08` §6.1 rule 5 leaves MW hit-group scaling unverified; MW pre-compensates the base gamemode scaling,
   which Private War keeps (§2.7).
5. The Workshop HTML "removed" banner is not the item state (§1.1).
6. `TASKS.md` "Coverage strategy" assumes a GLuaTest Workshop collection runner; the repository's `make test` runs
   on the Steam Deck (`scripts/check/test.sh` delegates to `scripts/deck/test.sh`), and a dedicated-server runner
   would also hit the `mgbase_tacsprint` server read (§3).

## Sources

- Steam Web API, `GetPublishedFileDetails` for the IDs in §1.1 (queried 2026-11-21).
- [MW Base Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=2459720887).
- [Workshop search "Modern Warfare 2019 SWEPS"](https://steamcommunity.com/workshop/browse/?appid=4000&searchtext=Modern+Warfare+2019+SWEPS).
- Mirror [Casualez/mwbase](https://github.com/Casualez/mwbase) at `56890bd`.
- [GMod wiki: Player:GetInfoNum](https://wiki.facepunch.com/gmod/Player:GetInfoNum).
