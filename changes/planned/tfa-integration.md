# TFA Base integration with attachments and Steam Deck performance profile (T-3.7)

Status: `planned`

Recorded: 2026-11-21

Approval (2026-11-22): the user approved every design change proposed in this record and the recommended
default of every open question, except where an answer below says otherwise. This approves the design
direction for implementation; push, PR, merge to `main` and publication still need separate approval.

Related: [MW Base integration](mwbase-integration.md) defines the shared `PW.WeaponConVars` helper; whichever change
lands first creates it.

Research: [TFA Base research](../../notes/33-tfa-research.md) (cited below as `notes/33 §N`), with
[`notes/08`](../../notes/08-weapon-adapters.md) §4 and §6.4 (corrected by `notes/33 §11`) and
[`notes/12`](../../notes/12-weapon-stat-modifiers.md) §4. This record is tracking, not authorization: it does not
authorize implementation, design changes, installing Workshop items, Steam Deck access, pushing or publication. It
replaces the TFA half of [`changes/blocked/weapon-integrations.md`](../blocked/weapon-integrations.md) once the
orchestrator updates that record and [`changes/INDEX.md`](../INDEX.md); this record does not edit them.

Rails for the implementing agent: every name, path, value and order below is decided here or listed as an open
question (§10). Do not invent a different name, add a ConVar, or change a value. Where a step says "verify", stop and
report when the installed TFA differs from `notes/33`. Implementation must not start before the user approves §12
items 1 and 2. Paths without a prefix are relative to the repository root; `T/` and `TM/` are the TFA paths of
`notes/33 §0`. The structure mirrors `addons/privatewar-arc9/` and the parallel MW Base plan
([`changes/planned/mwbase-integration.md`](mwbase-integration.md)); the shared ConVar helper is the one specified
there (§6.5 of that record) and is reused, not duplicated.

## 1. User request

- [ ] Recorded (translated): "We also need TFA integration, with attachments supported, like with the ARC9 system."
  Scope taken from the request and the project rules: TFA weapon catalogue, stat reading and player stat modifiers,
  full attachment support (per-weapon catalogue, builds applied to player and bot weapons from the Private War
  loadout, TFA's own customization menu locked, curated and stat-based attachment unlock levels as in T-11.7),
  generated bot loadouts, and a Steam Deck performance profile that cuts TFA's visual costs ("optimisation first",
  `DESIGN.md` global rule 7).

## 2. Prerequisites

- [ ] **Approval** of §12 items 1 and 2 by the user, and implementation authorization.
- [ ] **Workshop items the user installs on the Deck** (subscribe with the Deck's Steam account; GMod mounts
  subscribed items at game start, so restart GMod afterwards):

  | Item | Workshop ID | Why |
  | --- | --- | --- |
  | TFA Base 4.7.9.8 | [2840031720](https://steamcommunity.com/sharedfiles/filedetails/?id=2840031720) | the base (`notes/33 §0`) |
  | TFA Insurgency: Shared Parts | [2840032487](https://steamcommunity.com/sharedfiles/filedetails/?id=2840032487) | standard TFA attachments used by the `[AT]` packs (sights incl. RT scopes, suppressor, extended magazines, laser, underbarrel launchers) |
  | `[TFA][AT] MK18` | [1243623141](https://steamcommunity.com/sharedfiles/filedetails/?id=1243623141) | rifle (`ar`) with standard INS2 attachments |
  | `[TFA][AT] H&K UMP .45` | [1232089571](https://steamcommunity.com/sharedfiles/filedetails/?id=1232089571) | SMG with standard INS2 attachments and reskins (cosmetic options) |
  | `[TFA][AT] Beretta M9` | [1304932254](https://steamcommunity.com/sharedfiles/filedetails/?id=1304932254) | pistol (secondary slot) with standard INS2 attachments |

  Do **not** also install the separate "TFA INS2 Shared Parts" addon: users report duplicate Lua files with item
  2840032487 (community claim). ARC9 and its packs stay installed: both integrations must work side by side.
- [ ] **GLuaTest runner mounting:** `make test` (`scripts/deck/test.sh`) runs GLuaTest inside the Deck's own GMod,
  which mounts the subscribed items above. No extra mount step exists or is needed. The TFA cases skip with one log
  line when `TFA` is missing (never pass silently), as the ARC9 cases do.
- [ ] **Source check (step 0 of §7):** with Deck permission, compare the installed TFA Base with `notes/33` (the
  research used a community mirror whose version string and documentation match 4.7.9.8).
- [ ] **Deck permission** for every Deck action (deploy, tests, measurements), fresh and explicit, through the
  locked scripts.

## 3. Files to create or modify

Checked against the current tree: the Deck deploy loop (`scripts/deck/deploy.sh:28-38`) and packaging
(`scripts/package/build.sh:69-90`, `scripts/package/selftest.sh:39-55`) already pick up every `addons/<name>/` folder
except the gamemode and the dev addon; the type gate matches entity folders of any addon
(`scripts/check/types.sh:19`); the size rules cover the integration addons and exempt tests
(`scripts/check/rules.sh:10`). No script, `Makefile`, `flake.nix`, `.luarc.json` or `.glualint.json` change is needed.

| Path | Action | Content |
| --- | --- | --- |
| `addons/privatewar-tfa/addon.json` | create | copy of `addons/privatewar-arc9/addon.json` with `"title": "Private War: TFA integration"` |
| `addons/privatewar-tfa/logo.png` | create only if the user supplies one (§10 question 6) | packaging does not require it (`scripts/package/verify.sh`) |
| `addons/privatewar-tfa/lua/privatewar/weapon_adapters/tfa/shared.lua` | create | adapter, shared methods (§4) |
| `addons/privatewar-tfa/lua/privatewar/weapon_adapters/tfa/init.lua` | create | adapter, server methods: `Validate`, `Apply`, `SetCustomizationLocked`, `PrepareForBot`, `BotAction` |
| `addons/privatewar-tfa/lua/privatewar/modules/tfa/shared.lua` | create | `MODULE` (name, setting `perf`), `PW.Tfa` tables (lock, HUD, stat keys), store `PW._Tfa`, includes `sh_rules.lua` and `sh_perf.lua`, stat-mod hooks `TFA_GetStat` and `TFA_AnimationRate` (shared) |
| `addons/privatewar-tfa/lua/privatewar/modules/tfa/sh_rules.lua` | create | pure rules of §5 (type to category, slots, option stats, effective build, validation, lock answer, fire info, input rules, clip, range) |
| `addons/privatewar-tfa/lua/privatewar/modules/tfa/sh_perf.lua` | create | profile tables of §6 (pure data) and the `PW.WeaponConVars.InstallPerf` options |
| `addons/privatewar-tfa/lua/privatewar/modules/tfa/init.lua` | create | server glue: lock hooks and defaults-pending marker (§5.5), lock ConVars, server profile, `ShutDown` |
| `addons/privatewar-tfa/lua/privatewar/modules/tfa/cl_init.lua` | create | client glue: menu hook, client lock and HUD ConVars, `HUDShouldDraw`, client profile, `ShutDown` |
| `addons/privatewar-tfa/lua/privatewar/modules/bots_tfa_loadouts/shared.lua` | create | mirror of `modules/bots_arc9_loadouts/shared.lua` for TFA (§5.8) |
| `addons/privatewar-tfa/lua/privatewar/modules/bots_tfa_loadouts/sh_generate.lua` | create | mirror of the ARC9 cooperative generator (§5.8) |
| `addons/privatewar-tfa/lua/privatewar/modules/bots_tfa_loadouts/init.lua` | create | mirror of the ARC9 provider glue (§5.8) |
| `addons/privatewar/lua/privatewar/modules/weapons_core/sh_convars.lua` | create **only if the MW Base change has not landed** | `PW.WeaponConVars` exactly as `mwbase-integration.md` §6.5 (same API, same tests) |
| `addons/privatewar/lua/privatewar/modules/weapons_core/shared.lua` | modify (same condition) | include `sh_convars.lua`, as specified by the MW Base record |
| `addons/privatewar/lua/privatewar/types/weapon_convars.lua` | create (same condition) | as specified by the MW Base record |
| `addons/privatewar/lua/privatewar/types/tfa.lua` | create | `---@meta`: the part of the `TFA` global used (`TFALib`: `Attachments.Atts`, `Enum.ReloadStatus`, `Enum.STATUS_IDLE`), `TFAAttachment`, `PW.TfaWeapon` (methods of §4), `PW.TfaLib`, `PW.TfaStore`; `TFA = nil` like `types/arc9.lua` |
| `addons/privatewar/lua/privatewar/types/bots_tfa_generated.lua` | create | types of `PW.TfaBotLoadouts`, mirroring `types/bots_arc9_generated.lua` |
| `addons/privatewar/lua/tests/privatewar/tfa_helpers.lua` | create | pure cases (§8.2) |
| `addons/privatewar/lua/tests/privatewar/integration_tfa.lua` | create | T-3.7 mandatory and in-game cases (§8.1) |
| `addons/privatewar/lua/tests/privatewar/tfa_unlocks.lua` | create | T-11.7 analogue (§8.3) |
| `addons/privatewar/lua/tests/privatewar/tfa_perf.lua` | create | T-11.8 analogue (§8.4) |
| `addons/privatewar/lua/tests/privatewar/bots_tfa_generated.lua` | create | generator cases (§8.5) |
| `addons/privatewar/lua/tests/privatewar/weapons_convars.lua` | create **only if absent** | as the MW Base record §8.3 |
| `docs/agent-test-map.md` | modify | rows `T-3.6–T-3.8` pointing to `integration_tfa.lua` with the exact names of §8.1 (keep the ARC9 rows; the agent-guides gate counts the rows that start with a T- id) |
| `docs/perf-report.md` | modify | section "TFA performance profile (T-3.7)" with the numbers of §9 |
| `docs/bot-generated-loadouts.md` | modify | add the TFA provider (setting, refs, roles) |
| `docs/packaging.md` | modify | integration list: `privatewar-tfa`; Workshop ID only after a first upload (not in this change) |
| `README.md` | modify | addons table row and install step for `addons/privatewar-tfa/` ("Only with TFA Base") |
| `THIRD_PARTY_NOTICES.md` | modify | a "TFA integration" paragraph like the ARC9 one: public API only, no TFA code or assets |
| `CLAUDE.md`, `TASKS.md` | none (orchestrator) | layout line and T-3.7 status are the orchestrator's; the final report drafts the text |
| `docs/api/adapter.md` | none (frozen) | the final report drafts a "TFA session ConVars" subsection and the `SuppressDefaultAmmo` correction for the orchestrator |

Names fixed for the code: adapter id `tfa` (folder name), module ids `tfa` and `bots_tfa_loadouts`, setting
`tfa.perf`, setting `bots_tfa_loadouts.generate`, library `PW.Tfa`, store `PW._Tfa = { lock, clientLock, hud, perf,
memo, applying, pending }` (`applying` and `pending` are weak-keyed tables `setmetatable({}, { __mode = "k" })`),
backup files `data/privatewar/tfa_perf_server.json` and `data/privatewar/tfa_perf_client.json`, ban strings
`"tfa:<option id>"` for `loadout.bannedatts`, generated refs `generated:tfa:<category>:<variant>`, log prefix
`[PW] tfa:`. All engine and TFA hooks are registered with `PW.HookFor(MODULE, <event>, fn)` (one function per event
per module; the perf helper owns `Think`).

## 4. Adapter contract mapping

Every method of `docs/api/adapter.md`. `wep` is a live TFA weapon; "stored" is `weapons.Get(class)` (merged copy,
read once per memo revision); revision = `tostring(TFA.Attachments.Atts) .. ":" .. table.Count(TFA.Attachments.Atts)`.

| PW method | TFA field or function (verified in `notes/33`) | Fallback / notes |
| --- | --- | --- |
| `Priority` | field `100` | claims are disjoint from ARC9 |
| `IsAvailable()` | `rawget(_G, "TFA") ~= nil and TFA.Attachments ~= nil` | |
| `Claims(class, swep)` | `swep ~= nil and weapons.IsBasedOn(class, "tfa_gun_base")` (`notes/33 §1` item 4) | not `IsTFAWeapon` on the stored table (`notes/33 §11` item 6) |
| `ListWeapons()` | `weapons.GetList()` filtered by `IsBasedOn`, `Spawnable == true`, `AdminOnly ~= true`, class not ending in `_base`; info by `PW.Tfa._InfoFrom(stored)` (§5.1) | sorted by class |
| `GetBaseStats(class)` | `PW.Tfa._StatsFrom(stored)` (§5.1): `Primary.Damage`, `NumShots`, `RPM`, `ClipSize`, `Spread`, kicks, `IronSightTime`, `RegularMoveSpeedMultiplier`, range | missing or `-1` damage gives `nil` (autodetected values are not static, `notes/33 §1` item 7) |
| `GetLiveStats(wep)` | same fields through `wep:GetStatL(path)` | without a valid owner TFA returns values without attachments (`notes/33 §1` item 6); documented, not worked around |
| `PreviewBuildStats(class, build)` | not implemented | default `nil` (TFA applies stats only on a live weapon) |
| `GetIcon(class)` | not implemented | default `entities/<class>.png` |
| `GetSlots(class, build)` | `PW.Tfa._SlotsOf(stored.Attachments, TFA.Attachments.Atts)` (§5.2); `build` ignored (no nested slots) | `{}` for a weapon without attachments |
| `GetOptions(class, slotId)` | options of that slot: registered ids of `atts`, `name = att.Name or id`, `cosmetic = PW.Tfa._IsCosmeticAtt(att)` | banned (`loadout.bannedatts`) filtering stays in the core |
| `IsSelectionCosmetic(class, slotId, optionId)` | not implemented | default `nil` |
| `Validate(class, build)` | `PW.Tfa._ValidateBuild(slots, build, stored.AttachmentDependencies, stored.AttachmentExclusions)` (§5.4) | reason codes `unknown_slot`, `unknown_option`, `excluded`, `missing_dependency` |
| `Apply(wep, build)` | §5.3: `wep:SetTFAAttachment(cat, id, true, false)` under the adapter's own lock bypass; read back `wep.Attachments[cat].sel` | never `force = true` (`notes/33 §11` item 3) |
| `SetCustomizationLocked(locked)` | §5.5: lock flag, `TFA_PreCanAttach` and `TFA_PreCanDetach`, server lock ConVars | idempotent |
| `GetOptionStats(class, slot, option)` | `PW.Tfa._OptionStats(att, base, stored.AttachmentTableOverride[option])` (§5.6) | `nil` when no numeric stat changes |
| `GetOptionSetKey()` | `#ids .. ":" .. util.CRC(table.concat(sorted ids, "\n"))` of `TFA.Attachments.Atts`, memoised per revision | |
| `SuppressDefaultAmmo(wep)` | not implemented | default no-op: `Give(class, true)` gives no TFA ammo (`notes/33 §11` item 4); covered by a case |
| `GetAmmoType(wep)` | `game.GetAmmoID(wep:GetPrimaryAmmoType())` when that is a string, else the number | **required**: TFA returns a string (`notes/33 §2`, `§11` item 7); `-1` for an unknown name |
| `IsReloading(wep)` | `TFA.Enum.ReloadStatus[wep:GetStatus()] == true` | |
| `IsAiming(wep)` | `wep:GetIronSights()` | |
| `GetClip(wep)` | `wep:Clip1(), math.floor(wep:GetStatL("Primary.ClipSize"))` | capacity without the chamber |
| `CanFireNow(wep)` | default rule plus `not wep:IsJammed()` and `not wep:IsSafety()` | a jammed bot reloads instead |
| `PrepareForBot(ply, wep)` | no-op body that returns after checking `wep.IsTFAWeapon` | bots read no client ConVars; nothing to prepare (`notes/33 §8`) |
| `GetFireInfo(wep)` | `PW.Tfa._FireInfo(wep:GetStatL("FireModes")[wep:GetFireMode()], wep:GetMaxBurst(), 60 / wep:GetFireDelay())` | `kind` `auto`, `semi`, `burst`, `safe`; `adsKey = IN_ATTACK2`; `projectileSpeed` from `Primary.ProjectileVelocity` only for projectile weapons, else `nil` |
| `GetRecoil(wep)` | `pitch = (KickUp + KickDown) / 2 * (1 - StaticRecoilFactor)`, `yaw = KickHorizontal * (1 - StaticRecoilFactor)`, both through `GetStatL`, `affectsBotAim = true` | `notes/33 §5` |
| `GetInputRules(wep)` | `releaseBetweenShots = not wep:IsFireModeAutomatic()`, `reloadTap = not sv_tfa_reloads_legacy`, `reloadTapMax = 0.3`, `forbidWithAttack = IN_USE`, `forbidWithReload = IN_USE`, `noSprintWhileFiring = true`, `sprintToFire = 0.31`, `reselectEveryTick = true` | `notes/33 §8` |
| `BotAction(ply, wep, action, arg)` | `"firemode"`: `wep:CycleFireMode()` when `#FireModes > 2` and status idle, returns `true`; `"melee"`: `false` (§10 question 4); others `false` | |
| `IsHeadshot(dmginfo)` | not implemented | core decides |
| `GetDisplayName(wep)` | not implemented | default `PrintName` |
| `InstallStatMods(wep)` | not implemented (global hooks need no per-instance install) | default no-op |
| `RefreshStatMods(wep)` | not implemented (`TFA_GetStat` runs after the cache, `notes/12 §4.1`) | default no-op |
| `SupportedStatMods()` | `{ reload_time = true, draw_time = true, ads_time = true, recoil = true, spread = true }` | `sprint_to_fire` excluded (`design/04-weapons.md` d.6) |

Stat-modifier hooks (module `tfa`, shared, as `design/04-weapons.md` d.6 and `notes/12 §4`):

- [ ] `TFA_GetStat(wep, path, value)`: one table lookup `PW.Tfa.StatPaths[path]` first, return `nil` when absent; else
  multiply a number by `PW.GetStatMod(wep:GetOwner(), key)`. Paths: `IronSightTime` to `ads_time`;
  `Primary.KickUp`, `Primary.KickDown`, `Primary.KickHorizontal`, `Primary.RecoilLUT_ViewPunchMult`,
  `Primary.RecoilLUT_AnglePunchMult` to `recoil`; `Primary.Spread`, `Primary.IronAccuracy` to `spread`;
  `ProceduralReloadTime` to `reload_time`; `ProceduralHolsterTime` to `draw_time`. Return `nil` (not the value) when
  the multiplier is exactly 1, so other addons' handlers still run.
- [ ] `TFA_AnimationRate(wep, ani, rate)`: classify `ani` by the ACT sets of `notes/12 §4.2` (reload and draw or
  holster), else by `wep.OwnerViewModel:GetSequenceActivity(ani)`, never by `GetStatus()`; return
  `rate / PW.GetStatMod(owner, key)`; `nil` when unclassified or the multiplier is 1.

## 5. Attachment support (core of the task)

### 5.1 Catalogue and static stats (`sh_rules.lua`)

- [ ] `PW.Tfa._TypeOf(swep)`: `swep.Type` when a string, else a pure mirror of TFA's autodetection order
  (`notes/33 §2`), reading only stored fields. Write it from the rule list, do not copy TFA code.
- [ ] `PW.Tfa.Categories`: Pistol, Machine Pistol, Revolver, Dual Pistols, Dual Revolvers, Dual Guns to `pistol`;
  Sub-Machine Gun, Dual Sub-Machine Guns to `smg`; Rifle, Carbine to `ar`; Light Machine Gun to `lmg`; Shotgun to
  `shotgun`; Designated Marksman Rifle, Sniper Rifle to `sniper`; Launcher, Bow to `special`; Grenade, Melee, Weapon to
  none. Match case-insensitively.
- [ ] `PW.Tfa._InfoFrom(swep)`: kind `throwable` for `IsGrenade`, `melee` for `IsMelee`, `launcher` for type
  Launcher, else `gun`; slot 3 for melee and throwable, 2 for category `pistol`, else 1; `name = PrintName or class`.
- [ ] `PW.Tfa._StatsFrom(swep, rangeModifier)`: `damageNear = Damage * pellets` (only when `Damage > 0.01`),
  `damageFar = damageNear * lowest LUT damage`; `rangeNear`/`rangeFar` in metres from `Primary.RangeFalloffLUT`
  (`units` `inches`, `inch`, `hammer`, `hu` times 0.0254, anything else metres): `rangeNear` = range of the last
  point with damage at least 0.99 (0 when the first point is below), `rangeFar` = range of the lowest-damage point;
  legacy `Primary.Range` (units) and `Primary.RangeFalloff` (fraction): near `Range * RangeFalloff * 0.0254`, far
  `Range * 0.0254`, far damage `1 - rangeModifier` (the live `sv_tfa_range_modifier`); metric fields: near
  `MinRangeStartFalloff`, far `MinRangeStartFalloff + MaxFalloff / FalloffByMeter`; none: `nil`. `rpm = RPM` (else
  `60 / Primary.Delay`), `magazine = floor(ClipSize)`, `adsTime = IronSightTime or 0.3`,
  `moveMult = RegularMoveSpeedMultiplier or 1`, `pellets = max(1, floor(NumShots or 1))`,
  `recoil = (KickUp + KickDown) / 2 + KickHorizontal / 2` (degrees; compared within a category only),
  `spread = Primary.Spread`, `sprintToFire = nil` (identical for every TFA weapon, `notes/33 §2`).

### 5.2 Slots and options

- [ ] `PW.Tfa._SlotsOf(attachments, registry)` returns `slots, skipped`:
  - only **numeric** category keys (integer, 1 to 255); a string key is counted in `skipped` and logged once per
    class at `PW_WeaponsLoaded` (`[PW] tfa: <class>: <n> attachment categories keyed by model attachment name are not offered`)
    (`notes/33 §3.3`);
  - options are the ids of `atts` that exist in `registry`, in pack order; a category with none is dropped (TFA does
    the same, `notes/33 §3.2`);
  - `hidden = true` categories are not offered as slots, but their class default is kept by `Apply` (§5.3);
  - slot record: `id = tostring(cat)`, `name` from §5.2 naming, `cosmetic` true when every option is cosmetic,
    `default` = the class pre-selection (`sel` as id, or as index into `atts`) else the `default` field, else `nil`.
- [ ] Slot naming `PW.Tfa._SlotName(ids, cat)`: the first option id that matches decides, by substring of the
  lower-case id: `si_`, `sight`, `scope`, `optic` to "Optic"; `br_`, `supp`, `muzzle`, `barrel` to "Muzzle";
  `fg_`, `grip` to "Grip"; `laser`, `flashlight`, `light` to "Laser"; `mag`, `drum` to "Magazine"; `am_`, `ammo`,
  `sg_` to "Ammo"; `ub_`, `gl`, `launcher` to "Underbarrel"; `skin`, `camo`, `reskin` to "Camo"; else
  `"Slot " .. cat`. Verify against the installed pack ids in step 0 and adjust the substrings in the same commit as
  their test (the list is data, `PW.Tfa.SlotNames`).
- [ ] `PW.Tfa._IsCosmeticAtt(att)`: `true` when its `WeaponTable` (after `Base` inheritance, which TFA has already
  patched in `TFA.Attachments.Atts`) is non-empty and every top-level key is in `PW.Tfa.VisualKeys` =
  `Skin`, `MaterialTable`, `MaterialTable_V`, `MaterialTable_W`, `ViewModelBodygroups`, `WorldModelBodygroups`,
  `Bodygroups_V`, `Bodygroups_W`; `ViewModelElements` and `WorldModelElements` are visual too, but only when no key
  outside the set appears (a sight also changes `IronSightsPosition`, so it stays functional). An empty
  `WeaponTable` is not cosmetic (behaviour may live in `Attach`).

### 5.3 Applying a build (`weapon_adapters/tfa/init.lua`)

Timing: the loadout calls `PW.WeaponAmmo.Give` for every weapon, then `ADAPTER:Apply` on the first weapon of each
slot with a build, then `PrepareForBot` (`modules/loadout/init.lua:29-49`, `sv_gunsmith.lua:102-118`), all in the
same tick; TFA's `Initialize` (with `InitAttachments`) has already run inside `Give`. No deploy wait is needed.

- [ ] Guard: return `{}` unless `IsValid(wep)`, `wep.IsTFAWeapon`, `wep.HasInitAttachments` and `istable(build)`.
- [ ] `effective = PW.Tfa._EffectiveBuild(slots, build)`: for each offered slot, `build[id]` when present (an id or
  `false`), else the slot's class default (or `false` when it has none); hidden categories keep their class default.
- [ ] Order: categories ascending by number. Mark `PW._Tfa.applying[wep] = true` and clear
  `PW._Tfa.pending[wep]` (sealing the weapon against TFA's delayed default selection, §5.5).
- [ ] Pass 1, detach: every category whose wanted value is `false` and whose `sel` is set:
  `wep:SetTFAAttachment(cat, "", true, false)` (a category with a `default` field re-equips that default, as TFA
  does).
- [ ] Passes 2 to `n + 1` (`n` = number of wanted ids): attach every wanted id not yet selected with
  `wep:SetTFAAttachment(cat, id, true, false)`; stop after a pass that attached nothing. This lets TFA's own
  `CanAttach` enforce exclusions, dependencies, the attachment's `CanAttach` and `TFA_CanAttach`, in dependency order.
- [ ] Clear `PW._Tfa.applying[wep]` in every path: run the passes inside `ProtectedCall`/`pcall`, clear, then
  re-raise the error so `PW.Call` still disables a broken adapter.
- [ ] Clip: `PW.Tfa._ClipAfterApply(clip, oldCapacity, newCapacity)`: when the clip equalled the old capacity (full
  after `Give`), set it to the new capacity; when it exceeds the new capacity, clamp; else keep. Capacities from
  `GetStatL("Primary.ClipSize")` before and after. Reserve ammo stays the core's (§10 question 7).
- [ ] Return `PW.Tfa._ReadBuild(wep.Attachments, build)`: for each slot id of `build`, the selected id
  (`atts[sel]`) or `false`.
- [ ] Network: `nw = true` sends to the PVS; clients outside it, and clients that did not have the entity yet,
  receive the state through TFA's own request on entity creation (`notes/33 §3.4`). Nothing else to send.

### 5.4 Static validation (`Validate`, at save time)

- [ ] `PW.Tfa._ValidateBuild(slots, build, deps, excl)`: `unknown_slot` (no offered slot with that id),
  `unknown_option` (not an option of that slot; `false` is always allowed), `excluded` (exclusions made symmetric, as
  TFA does on first use, `notes/33 §3.1`; the slot processed later in ascending order is rejected),
  `missing_dependency` (string, `OR` table or `AND` table; satisfied by the build itself or by a class default kept by
  §5.3). The attachment's own `CanAttach(wep)` needs a live weapon: only `Apply` reports it, as "what stuck".

### 5.5 Customization lock

- [ ] Server state: `PW._Tfa.lock` (a ConVar swap of `PW.Tfa.LockConVars = { sv_tfa_cmenu = "0",
  sv_tfa_attachments_enabled = "1" }`) plus the flag `PW._Tfa.lock.on`. `SetCustomizationLocked(true)` swaps on;
  `false` restores. `PW_WeaponsLoaded` calls it with `true` through `PW.Adapters.Call`, as the ARC9 module does;
  `ShutDown` restores.
- [ ] Server hooks `TFA_PreCanAttach(wep, id)` and `TFA_PreCanDetach(wep, id)` return
  `PW.Tfa._LockAnswer(PW._Tfa.lock.on, PW._Tfa.applying[wep], PW._Tfa.pending[wep])`: `false` when locked and neither
  applying nor pending, else `nil` (TFA's own checks continue). Registered only in `modules/tfa/init.lua` (server).
- [ ] Defaults-pending marker (server): hook `TFA_FinalInitAttachments(wep)` sets `PW._Tfa.pending[wep] = true` and
  creates `timer.Simple(0, ...)` that clears it. TFA created its default-selection timers earlier in the same
  `InitAttachments` call (`notes/33 §3.2` step 3), so a weapon that is never applied gets its class defaults on both
  realms; `Apply` clears the marker first, so TFA's later default timer is refused and the build stays. Timer order
  within one tick is an assumption covered by two cases (§8.1).
- [ ] Client: hook `TFA_InspectVGUI_Start` returns `false` (no customization screen at all, `notes/33 §3.5`);
  client lock swap `PW.Tfa.ClientLockConVars = { cl_tfa_attachments_persist_enabled = "0" }` (no restored choices,
  no refused requests or error sounds); both while the module runs and TFA exists, restored on `ShutDown`.
- [ ] What the lock covers: client `TFA_Attachment_Set` requests (refused through `CanAttach`), other addons' unforced
  `Attach`/`Detach`, TFA's default timer after `Apply`. Not covered: code calling `SetTFAAttachment` with
  `force = true` (same trust level as any server addon).

### 5.6 Option stats and unlock levels (T-11.7 analogue)

- [ ] `PW.Tfa._OptionStats(att, base, override)`: walk `PW.Tfa.OptionStatKeys` (data, like `PW.Arc9.OptionStatKeys`):
  `damage` from `Primary.Damage` (1) and `Primary.NumShots` (1); `range` from `Primary.Range` (1); `rpm` from
  `Primary.RPM` (1); `recoil` from `Primary.KickUp`, `Primary.KickDown`, `Primary.KickHorizontal` (1/3 each);
  `spread` from `Primary.Spread` (1) and `Primary.IronAccuracy` (0.5); `adsTime` from `IronSightTime` (1);
  `moveSpeed` from `RegularMoveSpeedMultiplier` (1) and `AimingDownSightsSpeedMultiplier` (0.5); `reloadTime` from
  `ProceduralReloadTime` (1); `magazineAdd` = new `Primary.ClipSize` minus base. Leaf value from `override` (the
  weapon's `AttachmentTableOverride[option]`) first, else `att.WeaponTable`.
  - number: ratio `new / base` (base must be a positive finite number);
  - function: `pcall(fn, stub, base)` with `stub = setmetatable({ Primary_TFA = base Primary copy }, { __index =
    stored })`; a finite positive number gives the ratio; an error or anything else gives "unknown" for that stat;
  - field multiplier = product of ratios raised to their shares; omitted when 1; `nil` when nothing numeric changed.
- [ ] Base values: `stored` fields with TFA defaults (`IronSightTime 0.3`, moves `1` and `0.8 * regular`); read once
  per memo revision per class (as `baseValues` in the ARC9 adapter).
- [ ] Unlock levels need no new code: `modules/autounlock` is generic (`docs/api/progression.md` "Automatic unlock
  levels") and reads `GetBaseStats`, `GetSlots`, `GetOptions`, `GetOptionStats`, `GetOptionSetKey`. Options without
  numeric stats (cosmetic, sights that only move the view) get the middle level of their slot and are counted in the
  report line. Cosmetic options unlock by weapon level as before (`design/06-progression.md` d.2).
- [ ] Curated levels: a declarative `lua/privatewar/weapons/<tfa class>.lua` or a `PW_RegisterWeapons` listener with
  `Attachments = { [option id] = { Unlock = n, Cost = c, Hidden = true } }`, registered `soft`, wins option by option
  over the automatic level. No TFA-specific curation file ships in this change (§10 question 3).
- [ ] Compatibility with the entitlement refactor (`changes/in-progress/unlock-entitlements.md`): it keeps the
  `Attachments[option].Unlock` field (accepting `{ level = n }` and `false` too) and soft registration; TFA option ids
  become keys `attachments:<class>:<option id>`, pattern `^%l[%l_]*:[%w_%-%.:]+$`. TFA ids are lower-case file names
  or batch ids; an id outside `[%w_%-%.:]` cannot be keyed: count such ids at `PW_WeaponsLoaded` and log them once
  (`[PW] tfa: <n> attachment ids cannot be used as unlock keys`). Nothing else changes when that refactor lands.

### 5.7 Loadout UI

- [ ] No UI code changes: the gunsmith screen (`screens/loadout_gunsmith.lua`) lists `slot.name` and `option.name`
  from `GetSlots`/`GetOptions` generically. TFA option names are `att.Name` (plain strings in the base batch). Icons
  are not used by the gunsmith (`PW.Option.icon` stays `nil`). Check the TFA slots and options visually at the
  checkpoint (§9.4).

### 5.8 Generated bot loadouts (`bots_tfa_loadouts`)

- [ ] Mirror `addons/privatewar-arc9/lua/privatewar/modules/bots_arc9_loadouts/` file by file, with: adapter id
  `tfa`, availability `rawget(_G, "TFA")`, setting `generate` (match, bool, default `true`, label
  "Generate TFA loadouts", description as the ARC9 one with "TFA"), refs `generated:tfa:<category>:<variant>`, names
  `"TFA <category> <variant>"`, the same archetypes, perks and version handling, the same time slice
  (`0.00075` s, 32 resumes) and atomic publication.
- [ ] `DescribeWeapon(class, category, kind, stored)`: gun or melee only; exclude projectile guns
  (`Primary.Projectile`), `IsGrenade`, `IsBow`; knife = `IsKnife` or holdtype `knife`.
- [ ] `OptionRole(att, slotName)`: `camo` for cosmetic options; `optic`, `muzzle`, `grip`, `laser` from the slot name
  of §5.2; `nil` for Magazine, Ammo, Underbarrel and "Slot N" (never ammo types or launchers on bots).
- [ ] Builds: at most one camo and two functional accessories per weapon, only in slots without a class default
  (as the ARC9 generator), then `Validate`; candidates pass `Legal` (adapter `Validate` clean) before they join
  `PW_BotLoadoutCandidates`.

### 5.9 Edge cases

| Case | Behaviour |
| --- | --- |
| Weapon with empty `Attachments` | `GetSlots` `{}`; gunsmith absent for it; `Apply` returns `{}` for an empty build |
| String-keyed (CW2-style) categories | not offered, counted and logged (§5.2) |
| Option id not registered (pack missing) | not offered (TFA drops it too); a saved build with it fails `Validate` (`unknown_option`) |
| Hidden category | not offered; class default kept by `Apply` |
| Category with `default` | clearing it re-equips the default; read-back reports the default id |
| Cosmetic-only option (reskin) | slot `cosmetic` when all options are; free in Pick X (`docs/api/loadout.md`); middle unlock level |
| Sight with RT scope (`RTDrawEnabled` or `RTCode`) | offered normally; client cost bounded by the deck profile (§6); measured (§9.3) |
| `sv_tfa_attachments_reload` at run time | the memo revision changes (new `Atts` table); live weapons keep their builds |
| Attachment whose `Attach` errors | TFA's `ProtectedCall` reports failure, `sel` unchanged; read-back shows it did not stick |
| Two adapters | ARC9 and TFA classes are disjoint (`IsBasedOn`) |

## 6. Deck performance profile

Setting `tfa.perf`: scope `server`, type `enum`, default `deck`, options `deck`, `off`, label
"TFA performance profile", description "deck (recommended) trades TFA's visual effects for frame time on the Steam
Deck: no scope background blur, half-resolution scope render targets, short-lived shell casings, no muzzle and
ejection smoke, hitscan bullets without ricochets. off restores your own TFA settings and leaves them alone."
`off` = empty table. Apply, restore and crash safety: identical to `arc9.perf` through `PW.WeaponConVars`
(`mwbase-integration.md` §6.4 and §6.5), with `available = function() return rawget(_G, "TFA") ~= nil end`,
`backupPath = "privatewar/tfa_perf_<realm>.json"`, `label = "TFA"`, `prefix = "tfa"`, log line
`[PW] tfa: restored N TFA <realm> settings left by a session without ShutDown`.

### 6.1 `deck` values (`PW.Tfa.PerfConVars`)

| ConVar | Side | `deck` | TFA default | Class | Justification (`notes/33`) | Expected impact |
| --- | --- | --- | --- | --- | --- | --- |
| `cl_tfa_fx_rtscopeblur_mode` | client | `0` | 1 | must-cut | three full-screen blur passes per frame while an RT scope is aimed (§6) | high, GPU, while scoped |
| `cl_tfa_3dscope_quality` | client | `1` | 0 | must-cut | RT is `ScrH / 2^q`: half resolution, a quarter of the pixels (§6) | medium to high with RT sights |
| `cl_tfa_fx_ejectionlife` | client | `2` | 15 | must-cut | each shell is a physics effect alive this many seconds (§6) | medium to high in fights |
| `cl_tfa_fx_ejectionsmoke` | client | `0` | 1 | must-cut | particle per shot | low to medium |
| `cl_tfa_fx_muzzlesmoke` | client | `0` | 1 | must-cut | smoke trail per shot | medium |
| `cl_tfa_fx_muzzleflashsmoke` | client | `0` | 1 | must-cut | smoke with every flash | medium |
| `cl_tfa_fx_impact_ricochet_enabled` | client | `0` | 1 | must-cut | ricochet sparks (no gameplay) | low |
| `cl_tfa_laser_trails` | client | `0` | 1 | must-cut | laser dot trails | low |
| `cl_tfa_fx_gasblur` | client | `0` | 0 | must-cut (pin) | screen blur if a player enabled it | high when on |
| `cl_tfa_fx_ads_dof` | client | `0` | 0 | must-cut (pin) | depth of field while aiming | high when on |
| `cl_tfa_fx_ads_dof_hd` | client | `0` | 0 | must-cut (pin) | | high when on |
| `cl_tfa_inspection_bokeh` | client | `0` | 0 | must-cut (pin) | depth pass while inspecting | medium when on |
| `cl_tfa_3dscope_overlay` | client | `0` | 0 | must-cut (pin) | scope shadows | low |
| `sv_tfa_ballistics_enabled` | server (replicated) | `0` | 0 | must-cut (pin); gameplay | simulated bullets, as `arc9_bullet_physics 0` | high when on |
| `sv_tfa_bullet_ricochet` | server (replicated) | `0` | 0 | must-cut (pin); gameplay | extra traces and bullets, as `arc9_ricochet 0` | medium when on |
| `sv_tfa_fx_penetration_decal` | server (replicated) | `0` | 1 | must-cut | exit-side decals on clients | low |

### 6.2 Measure, then decide (not in `deck` until measured, §9.3)

| Lever | Candidate value | Gameplay | Decision rule |
| --- | --- | --- | --- |
| `sv_tfa_bullet_penetration` | `0` | yes | as T-11.8: off only if it adds more than 0.5 ms to average server Lua hook time or raises p99/max noticeably |
| `sv_tfa_penetration_hardlimit` | `2` | yes | measured only when penetration fails the rule: prefer the limit over turning penetration off when it passes the same rule |
| `cl_tfa_fx_impact_enabled` | `0` | no | client A/B (§9.3): cut when the client frame average improves by at least 1 ms or p99 by at least 3 ms |
| `cl_tfa_3dscope_quality` | `2` | no | client A/B with an RT sight aimed: take 2 when it saves at least 1 ms and the reticle stays readable at the checkpoint |
| Shells and smoke of other players through `TFA_MakeShell` (return `true` for weapons not owned by `LocalPlayer()`) | hook | no | client A/B in a 9-bot fight; adopt only if `cl_tfa_fx_ejectionlife 2` leaves at least 1 ms to gain (needs §12 item 2 approval, it is a hook, not a ConVar) |
| Precache of TFA view and world models of catalogued classes at `PW_WeaponsLoaded` | `util.PrecacheModel` | no | only if the first-`Give` micro-benchmark shows a stall above 100 ms per class |

### 6.3 Keep (not touched)

- Muzzle flashes and their light (they reveal shooters; no ConVar), crosshair and colour (`09-hud.md` d.1),
  view and gun bob, viewmodel options, sounds, `sv_tfa_worldmodel_culldistance` (never read by TFA, `notes/33 §6`).

### 6.4 Session sets outside the profile (always while the mode runs, restored on `ShutDown`)

| Set | Side | Values | Why |
| --- | --- | --- | --- |
| `PW.Tfa.LockConVars` | server | `sv_tfa_cmenu 0`, `sv_tfa_attachments_enabled 1` | §5.5; `Apply` depends on the second |
| `PW.Tfa.ClientLockConVars` | client | `cl_tfa_attachments_persist_enabled 0` | §5.5 |
| `PW.Tfa.ClientHudConVars` | client | `cl_tfa_hud_hitmarker_enabled 0`, `cl_tfa_hud_keybindhints_enabled 0` | Private War draws its own hitmarker and hints (`09-hud.md` d.1) |
| `HUDShouldDraw` | client | `false` for `TFA_HUDAmmo` and `TFA_HUDFallback` | hides TFA's ammo HUD without changing the player's ConVars (`notes/33 §4`) |

### 6.5 Shared helper and lane ownership

- [ ] Use `PW.WeaponConVars` (`modules/weapons_core/sh_convars.lua`) for every swap and the profile. Reason: the
  same crash-safe save, restore and recovery logic is needed by ARC9, MW Base and TFA; one copy keeps one place for a
  crash-safety bug; `modules/weapons_*` belongs to the `weapons` lane, which also owns the integration addons
  (`TASKS.md`, "Lanes and ownership"); `weapons_core` is always loaded with any adapter. If the MW Base change has
  landed, only import; otherwise create it exactly as that record specifies (§7 steps 1 and 2) so the two changes do
  not diverge. ARC9 is not migrated here.

## 7. Implementation steps in order (tests first; one commit per step)

Commit messages follow `CLAUDE.md` (`git commit --signoff`, semantic message, trailer `Assisted-by: LLM`). Every
commit passes `nix develop --command make check` before it is made. Branch from `main` on a feature branch.

0. [ ] **Verify the installed source (no commit).** With Deck permission, list the mounted TFA Base files and compare
   with `notes/33`: version string, `SetTFAAttachment` signature and server check, `CanAttach` order, the
   `TFA_Attachment_Set` receiver, `InitAttachments` default timer, `TFA_PreCanAttach`, `TFA_FinalInitAttachments`,
   `TFA_InspectVGUI_Start`, `GetPrimaryAmmoType` override, every ConVar of §6, and print `table.GetKeys` of
   `TFA.Attachments.Atts` plus the `Attachments` table of one weapon of each pack. Record differences in `notes/33`
   (new section "Installed version check") and stop if a name in §4 to §6 changed.
1. [ ] **Shared helper (only if absent).** Tests `weapons_convars.lua`, then `sh_convars.lua` and its types, as the
   MW Base record steps 1 and 2 (same commit messages).
2. [ ] **Pure rules, red.** `tfa_helpers.lua` with every case of §8.2 and the pure cases of §8.3 in
   `tfa_unlocks.lua`. Commit `test(tfa): cover pure TFA integration rules`.
3. [ ] **Pure rules, green.** `addon.json`, `modules/tfa/shared.lua` (no hooks yet), `sh_rules.lua`, `types/tfa.lua`.
   Commit `feat(tfa): add TFA integration module and pure rules`.
4. [ ] **Adapter discovery, stats, slots, options, option stats, state, fire info, input rules.** In-game cases first
   (§8.1 adapter, catalogue, stats, ammo, unlock cases), then `weapon_adapters/tfa/shared.lua`. Commit
   `feat(tfa): add TFA adapter discovery, stats and attachment catalogue`.
5. [ ] **Server adapter and lock.** Cases: Apply, conflicting build, defaults, lock, two bots, `PrepareForBot`,
   `BotAction`, clip. Code: `weapon_adapters/tfa/init.lua`, `modules/tfa/init.lua` lock part, `cl_init.lua` menu and
   client lock part. Commit `feat(tfa): apply builds and lock TFA customization`.
6. [ ] **Stat mods.** Case: reload time. Code: the two hooks in `modules/tfa/shared.lua`. Commit
   `feat(tfa): wire player stat modifiers through TFA hooks`.
7. [ ] **HUD set.** Case: client HUD table and swap (pure) plus `HUDShouldDraw` names. Code: `cl_init.lua` HUD part.
   Commit `feat(tfa): hide TFA HUD parts while the gamemode runs`.
8. [ ] **Perf profile, red then green.** `tfa_perf.lua` (§8.4); then `sh_perf.lua`, the setting, the glue. Two
   commits: `test(tfa): cover the TFA deck performance profile` and `feat(tfa): add the TFA deck performance profile`.
9. [ ] **Generated bot loadouts, red then green.** `bots_tfa_generated.lua` (§8.5); then `modules/bots_tfa_loadouts/`
   and `types/bots_tfa_generated.lua`. Two commits: `test(tfa): cover generated TFA bot loadouts` and
   `feat(tfa): generate TFA bot loadouts`.
10. [ ] **Docs.** `docs/agent-test-map.md`, `docs/bot-generated-loadouts.md`, `docs/packaging.md`, `README.md`,
    `THIRD_PARTY_NOTICES.md`, and `notes/33` follow-ups. Commit `docs(tfa): document the TFA integration`.
11. [ ] **Gates and Deck run** (needs permission): §11, then §9. Commit the numbers:
    `docs(perf): record TFA measurements`. Each measured decision of §6.2 is its own commit
    `perf(tfa): <lever> in the deck profile after measurement`, updating the profile-table test in the same commit.
12. [ ] **Hand-off.** In the final report draft for the orchestrator: the `docs/api/adapter.md` "TFA session
    ConVars" subsection and the `SuppressDefaultAmmo` and TFA `GetAmmoType` notes, the `TASKS.md` T-3.7 status text,
    the `CLAUDE.md` layout line, and the pending checkpoint items. Leave `changes/` moves to the orchestrator.

## 8. Mandatory test cases

Every case name below is exact. In-game cases skip with one log line per file when `TFA` or the packs are missing
(never pass silently). Two bots live for the whole in-game group (`beforeAll` creates, `afterAll` kicks), as in
`integration_arc9.lua`.

### 8.1 `integration_tfa.lua` (T-3.7, from `TASKS.md` "T-3.6–T-3.8 Integrations", plus attachments)

- [ ] `Adapter: claims TFA classes above the fallback; absent TFA makes it unavailable`
- [ ] `Catalogue: the pack's weapons are listed with categories and reach the weapons registry` (mandatory)
- [ ] `Apply on a bot's weapon returns the applied build` (mandatory)
- [ ] `Apply with a conflicting build returns what stuck` (mandatory; an excluded pair or a missing dependency from
  the installed pack, found at run time; skip with a log line when the pack has neither)
- [ ] `Customization lock: TFA's own attachment request path refuses` (mandatory; calls the receiver's path
  `SetTFAAttachment(cat, id, ply)` without force and expects `false` and an unchanged `sel`)
- [ ] `Stat mods change the server-side reload time and removal restores it` (mandatory)
- [ ] `PrepareForBot runs without errors; two bots keep different builds of the same class` (mandatory)
- [ ] `Attachments: slots and options come from SWEP.Attachments and the TFA registry`
- [ ] `Attachments: Apply keeps TFA's own checks (a TFA_CanAttach refusal does not stick)`
- [ ] `Attachments: a weapon without a build gets its class defaults on the server`
- [ ] `Attachments: the delayed class default does not override an applied build`
- [ ] `Attachments: live stats follow the applied build`
- [ ] `Attachments: an extended magazine refills the clip to the new capacity`
- [ ] `Lock: a detach outside Apply is refused; unlocking allows it again`
- [ ] `Lock: sv_tfa_cmenu is 0 and sv_tfa_attachments_enabled is 1 while the mode runs; ShutDown restores them`
- [ ] `Ammo: GetAmmoType is the integer ammo id and the core gives reserve ammo`
- [ ] `Stats: GetBaseStats of a class matches GetLiveStats of a fresh weapon without a build`
- [ ] `Bots: a bot fires and reloads a TFA rifle` (smoke, generous timeout; proves the server viewmodel)
- [ ] `BotAction: firemode cycles a selective-fire TFA weapon; melee returns false`

### 8.2 `tfa_helpers.lua` (pure)

- [ ] `Helpers: TFA weapon types map to PW categories, kinds and slots`
- [ ] `Helpers: the type rules follow TFA autodetection order`
- [ ] `Helpers: only numeric categories with registered options become slots; string categories are counted`
- [ ] `Helpers: slot names come from option ids, else Slot N`
- [ ] `Helpers: an attachment that changes only visual keys is cosmetic; a sight is not`
- [ ] `Helpers: the effective build fills unnamed slots with class defaults and keeps false`
- [ ] `Helpers: Validate rejects unknown slots, unknown options, exclusions and missing dependencies`
- [ ] `Helpers: the lock answers false only when locked, not applying and not pending`
- [ ] `Helpers: fire info from TFA fire mode names (auto, semi, burst, safe)`
- [ ] `Helpers: input rules use the reload tap unless legacy reloads are on`
- [ ] `Helpers: the clip after Apply follows the new capacity only when it was full`
- [ ] `Helpers: range from a meters LUT, a hammer LUT, legacy Range and none`
- [ ] `Helpers: read-back reports the selected id or false per slot`

### 8.3 `tfa_unlocks.lua` (T-11.7 analogue)

- [ ] `Unlock: option stats from absolute values and from functions; an erroring function is unknown`
- [ ] `Unlock: lower kicks give a recoil multiplier below 1; a larger ClipSize gives a positive magazineAdd`
- [ ] `Unlock: an option without numeric stats returns nil and gets the middle level of its slot`
- [ ] `Unlock: AttachmentTableOverride of the weapon wins over the attachment's WeaponTable`
- [ ] `Unlock: GetOptionSetKey is the count and CRC of the sorted TFA attachment ids`
- [ ] `Unlock: TFA weapons reach the autounlock candidates; attachment levels spread over 1..30 within a slot` (in game)
- [ ] `Unlock: a hand-curated Attachments Unlock beats the automatic TFA level`
- [ ] `Unlock: ids that cannot be unlock keys are counted`

### 8.4 `tfa_perf.lua` (T-11.8 analogue)

- [ ] `Perf: the deck profile maps exactly the client and server values; off is empty`
- [ ] `Perf: tfa.perf is a host setting in the schema, deck by default, with a description`
- [ ] `Perf: deck sets the values of its realm and backs up the originals; off restores, drops the backup`
- [ ] `Perf: applying twice does not overwrite the saved originals`
- [ ] `Perf: a missing ConVar (TFA not installed or an older TFA) is skipped without error`
- [ ] `Perf: off leaves TFA alone after the restore; the player's later changes stay`
- [ ] `Perf: ShutDown restores the originals and deletes the backup`
- [ ] `Perf: a backup left without ShutDown restores the originals first, then deck applies again`
- [ ] `Perf: lock and HUD sets are not part of the profile and stay set under off`
- [ ] `Perf: the live server ConVars follow the profile, the backup file exists while deck is on` (in game)

### 8.5 `bots_tfa_generated.lua`

- [ ] `Generate: 18 additive candidates, three per archetype, coherent slots and pistol-only knife`
- [ ] `Unavailable: zero weapons, missing TFA and missing knife preserve an empty generated pool`
- [ ] `Roles: optics, muzzles, grips and lasers only; never ammo, magazines or underbarrel launchers`
- [ ] `Async: incomplete and failed jobs never publish a partial pool, errors remain isolated`
- [ ] `Cache: matches and settings reuse exact data; map change and reload invalidate safely`
- [ ] `Setting: default-on match bool is exposed through schema without changing bots.classes sources`

## 9. Deck measurement and human checkpoint

Needs Deck permission. All commands through the repository scripts (`CLAUDE.md`, "Platform facts").

### 9.1 Install and smoke

1. The user installs §2 items and restarts GMod.
2. `nix develop --command bash scripts/deck/dev.sh` (deploy, `pw_reload`, filtered logs); then
   `bash scripts/deck/logs.sh --once | grep "\[PW\] tfa"` shows no errors and the skipped-category and key lines.

### 9.2 Baseline and micro-benchmarks

Scenario of `docs/perf-report.md` "ARC9 performance profile (T-11.8)": Steam Deck, Proton, listen server,
`gm_construct`, TDM, 9 bots and the idle host, `tfa.perf = deck`. A dev-bridge timer gives each living bot a TFA rifle
or SMG from the installed packs with `PW.WeaponAmmo.Give` once a second whenever it holds something else (as the
ARC9 run; record the probe in the report).

```bash
bash scripts/deck/cmd.sh "pw_dev_profile start tfa_base"
# 120 s of LIVE
bash scripts/deck/cmd.sh "pw_dev_profile stop"
bash scripts/deck/logs.sh --once | grep "profile tfa_base"
```

Record: server interval avg, p99, max; server Lua hooks avg, p95, p99, max; client frame avg, p99; the top TFA hooks
(`TFAFinishMove`, `TFA_GetStat` handlers, `TFASCREENS`); first-`Give` time per class (micro-benchmark, 6 classes,
first and second copy, as the ARC9 section); `Apply` time per call.

### 9.3 Measure-then-decide protocol

- Penetration: four 120 s profiles in one match, alternating `sv_tfa_bullet_penetration` 1, 0, 1, 0
  (`bash scripts/deck/cmd.sh "sv_tfa_bullet_penetration 0"`), tags `tfa_pen_on_1`, `tfa_pen_off_1`, `tfa_pen_on_2`,
  `tfa_pen_off_2`. Off in `deck` only if the average server Lua hook time with penetration is more than 0.5 ms above
  the runs without, or p99 is higher in both "on" runs than in both "off" runs, or a max spike is attributed to the
  bullet path (not to `bots_loadouts@PostPlayerDeath`, which caused the ARC9 maxima). If it fails, repeat with
  `sv_tfa_penetration_hardlimit 2` against off and prefer the limit when it passes.
- Client levers (`cl_tfa_fx_impact_enabled 0`, `cl_tfa_3dscope_quality 2`, the `TFA_MakeShell` trim): the host stands
  at a fixed position facing the main fight with a fixed weapon, 60 s per run, alternating A, B, A, B, client frame avg
  and p99 from the profiler's client report; thresholds in §6.2.
- Write every run row and every decision into `docs/perf-report.md`, section "TFA performance profile (T-3.7)", in
  the T-11.8 table format.

### 9.4 Human checkpoint (items for the local manual checklist)

The user checks on the Deck with `tfa.perf = deck` unless stated:

1. A TFA rifle fires, reloads (tap R), aims (right mouse, toggle as in TFA), and switches fire mode with TFA's key.
2. Gunsmith: TFA weapons show slots named Optic, Muzzle and so on, options by name; locked options show their level.
3. A saved build is visible on spawn (sight, suppressor) and its stats apply (suppressed sound, extended magazine
   count).
4. TFA's own menu does not open (context key, the `customize` bind, `impulse 148` in the console); no button error
   sounds after spawning.
5. Bots spawn with TFA guns and visible attachments, shoot, reload and keep fighting; another client (or the host
   looking at a bot) sees the bot's attachments.
6. An RT scope works and the reticle is readable at quality 1 (and at 2 if §9.3 proposes it).
7. Frame rate in a 9-bot fight feels at least as smooth as with ARC9; shells disappear quickly; no smoke clouds.
8. TFA's ammo HUD and hitmarker are hidden; Private War's HUD shows clip and reserve for TFA weapons.
9. Switching `tfa.perf` to `off` in SETTINGS restores the host's own TFA settings; after quitting GMod without a
   clean shutdown, the next start restores them before applying `deck`.

## 10. Open questions for the user

1. **Approve the design changes of §12 items 1 and 2?** Recommended: yes for both.
2. **Gameplay ConVars of TFA** (not performance; `notes/33 §10.1`): jamming (`sv_tfa_jamming`, default 1), random
   damage (`sv_tfa_damage_mult_min 0.95`, `_max 1.05`), shootable doors (`sv_tfa_bullet_doordestruction`,
   `sv_tfa_melee_doordestruction`, default 1). Recommended: a session gameplay set while the mode runs, restored on
   `ShutDown`: jamming 0, random damage 1 and 1, door destruction 0 (CoD-like consistency, no props from doors).
   Not part of this change until approved; it would be a third session set beside lock and HUD.
3. **Curated TFA unlock files** for the recommended packs. Recommended: none now; automatic levels first, curate
   after the checkpoint if levels feel wrong.
4. **Bot bash with TFA** (`BotAction("melee")` through `AltAttack` or impulse 149). Recommended: not in this change
   (`false`); revisit with the generic melee work.
5. **Generalize the generated bot loadouts** (ARC9 and TFA providers share the generator). Recommended: duplicate for
   TFA now (keeps ARC9 untouched, matches the request for bot loadouts); extract one generic generator when MW Base
   gets its own (third copy), as a separate change.
6. **Logo** for `addons/privatewar-tfa/logo.png`. Recommended: the user supplies or approves an image in the ARC9
   integration's style; otherwise ship without.
7. **Reserve ammo after an extended magazine:** the core sets the reserve from the clip size before `Apply`.
   Recommended: accept for now (same behaviour class as ARC9); if it matters, a core change gives ammo after `Apply`.
8. **Crosshair player reveal** (`sv_tfa_crosshair_showplayer 1`: TFA's crosshair turns the team colour on the aimed
   player). Recommended: keep (similar to CoD's red crosshair on enemies).

## 11. Gates

- [ ] `nix develop --command make check` passes (lint, types, markdown, rules, agent guides, self-tests) before every
  commit and before review. Never `--no-verify`.
- [ ] `bash -o pipefail -c 'nix develop --command make test 2>&1 | tail -n 80'` passes on the Deck with TFA Base, the
  shared parts and the three packs mounted (ARC9 still installed), with every case of §8 present and passing, and
  the existing suites (including all ARC9 cases) unchanged and green. Without Deck permission, report the test gate
  and the measurements as skipped and the merge gate incomplete.
- [ ] Deck access only with fresh explicit permission and a free Deck, through the locked scripts; never SSH by hand.
- [ ] No TFA code or assets in the tree; `THIRD_PARTY_NOTICES.md` only gains the "public API only" paragraph.
- [ ] PR as draft only after the user approves title and body; merge only with separate approval
  (`gh pr merge --squash --delete-branch`).

## 12. Design changes requiring approval

Proposed wording; the orchestrator writes it into `design/` after approval. Nothing in `design/` is edited by this
record.

1. **Extend `design/04-weapons.md` d.7 to TFA:** a host setting `tfa.perf` with values `deck` (default) and `off`,
   the same apply, restore and crash-safe backup rules as `arc9.perf`, with the values of §6.1; measured levers of
   §6.2 join `deck` only after the §9.3 protocol. If MW Base's extension is approved first, phrase d.7 generically:
   "every weapon-base integration ships a `<id>.perf` profile (`deck` default, `off`) with crash-safe backup; its
   values are listed in that integration's section of `docs/api/adapter.md`".
2. **Customization lock technique for TFA** (`design/04-weapons.md` d.2 stays as is; this records the means):
   server `TFA_PreCanAttach`/`TFA_PreCanDetach` refusal with the adapter's own bypass during `Apply` and a one-tick
   defaults-pending window per weapon, client `TFA_InspectVGUI_Start` refusal, and the session lock ConVars of §6.4.
   Optional, only with the §6.2 measurement: a client `TFA_MakeShell` hook that skips other players' shells.
3. **Lane-internal (recorded for the reviewer):** reuse of `PW.WeaponConVars` in `modules/weapons_core/`
   (`mwbase-integration.md` §2 item 3); ARC9 is not migrated in this change.
4. `docs/api/adapter.md` is frozen; the orchestrator adds a "TFA session ConVars" subsection and corrects the
   `SuppressDefaultAmmo` row ("TFA: ConVar" is not needed, `notes/33 §11` item 4) after the merge. No contract method
   is added or changed.
