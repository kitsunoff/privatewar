# Weapon adapter API: `ADAPTER`, stat mods, ammo, catalogue curation, bot input rules

Status: frozen on 2026-11-07, changes only through the orchestrator.

Extended on 2026-11-07 after T-3.1 to T-3.5: the items of "Open in design" that the lane agents decided in code
(items 1, 2, 3, 5, 6, 7 and 8) are now in the main text; the code wins over any description here. Items 9 to 11 are
still open, as are T-3.6 to T-3.8 (the integrations). Values marked "lane agent" are gameplay or API details the
orchestrator recorded after the merge.

Contract for the `weapons` lane (T-3.1 to T-3.8). It sits on top of `core.md` (kind `weapons`, weapon registration
phase, registry, `soft` registration) and does not repeat it. Sources: `design/04-weapons.md` d.1 to d.6 (cited as
`04 d.N`), the adapter research `notes/08-weapon-adapters.md` §5 (cited as `notes/08 §5`; "taken as written" by
`04 d.1`), `notes/12-weapon-stat-modifiers.md` §6. Where the design and the research differ, the design wins; the
differences are listed in "Differences from `notes/08` §5". What the design leaves open is in "Open in design".

## Ownership

| Item | Lane | Where |
| --- | --- | --- |
| Kind `weapon_adapters` (the declaration) | core files, see "Core changes needed" | `lua/privatewar/kinds/weapon_adapters.lua` |
| Adapters | weapons | `lua/privatewar/weapon_adapters/<id>.lua` |
| Catalogue entries (declarative) | weapons | `lua/privatewar/weapons/<class>.lua` |
| Fallback adapter `sweps` | weapons (T-3.2) | `lua/privatewar/weapon_adapters/sweps.lua` |
| Modules `weapons_core` (adapter lookup), `weapons_catalog`, `weapons_ammo`, `weapons_statmods` | weapons | `lua/privatewar/modules/weapons_*` |
| Integrations (ARC9, TFA, MW Base) | weapons | separate addons `privatewar-arc9`, `privatewar-tfa`, `privatewar-mwbase` |

The core knows nothing about any weapon base. It provides the registration phase, the `soft` rule, `PW_PreRegister`
and per-entry ConVars (`04 d.4`; `core.md`).

## Kind `weapon_adapters` and registration

A weapon adapter is an ordinary entity of the kind `weapon_adapters`, registered SWEP-style (`04` "Registration";
`01-extensibility.md` d.8, d.16). Class table `ADAPTER`; the id is the file or folder name
(`ADAPTER.ClassName`); the accessor is `PW.WeaponAdapters` (`core.md` "Namespace").

```lua
-- lua/privatewar/weapon_adapters/arc9.lua (in the integration addon)
if not PW or PW.API ~= 1 then return end

ADAPTER.Priority = 100          -- higher wins when several adapters claim a class
function ADAPTER:IsAvailable() return ARC9 ~= nil end
function ADAPTER:Claims(class) ... end
```

- Methods are written as `ADAPTER:Method(...)`; `Priority` is a field (`04 d.1`).
- No `apiVersion` field and no `id` field: an adapter guards itself with `PW.API` (`04 d.1`;
  `01-extensibility.md` d.14); the id is the file name.
- The guard in `04` "Registration" reads `if not COD or PW.API ~= 1 then return end`. `COD` is a leftover of the
  research naming (`notes/08` §5 uses `COD.*`); the global of the gamemode is `PW`. The example above uses `PW`.
- Adapters are not auto-subscribed: their methods are not `PW_*` hooks. `KIND.Subscribe` stays omitted (`"never"`).
- Enable ConVar `pw_adapter_<id>_enabled` follows from `Global = "ADAPTER"` (`01-extensibility.md` d.11).
- The core skips adapters whose `IsAvailable()` returns `false` and logs a single clear line per adapter at startup.
  Failures are not silent (`04` "Registration").
- Disabled adapters (ConVar or error) are not candidates: lookup should use `PW.WeaponAdapters.GetEnabledList()`
  (`core.md` "Registry": for anything picked in a match).
- Every adapter method is called through `PW.Call` (`00-core.md` d.6; `core.md` "Entity calls"): `pcall`, and an
  error disables that adapter until the map changes.

### Lookup (`T-3.1`)

- Several adapters may claim one class; the highest `Priority` wins (`04` "Registration"; mandatory case T-3.1).
- Adapters with `IsAvailable() == false` are skipped (T-3.1).
- `Priority` default is `0` (`notes/08` §5, `Adapter.priority`: "default 0"; the field is kept by `04 d.1`); a
  non-number `Priority` counts as `0`.
- Every optional method has a working default in the core (`04 d.1`; T-3.1). Defaults: "Defaults".

Module `weapons_core` (T-3.1), namespace `PW.Adapters` (shared; types `lua/privatewar/types/adapter.lua`). Lane agent
decisions:

| Function | Contract |
| --- | --- |
| `PW.Adapters.For(weaponOrClass) -> ADAPTER?` | The adapter of a weapon entity or a class string: among the **enabled** adapters of `PW.WeaponAdapters` (`GetEnabledList`), the one that is available and claims the class, with the highest `Priority`. `nil` for an invalid weapon, without the registry, or when nothing claims the class |
| `PW.Adapters.Call(adapter, method, ...) -> any` | Calls `adapter:method(...)` through `PW.Call` (`pcall`, an error disables the adapter). When the adapter lacks the method, or the call failed and the adapter is no longer valid, the answer is `PW.Adapters.Defaults[method](adapter, ...)`; a method with no default (`IsAvailable`, `Claims`, `ListWeapons`) answers `nil` |
| `PW.Adapters.CallFor(weaponOrClass, method, ...) -> any` | `For`, then `Call`; when no adapter is found the defaults answer (with a stand-in adapter whose `ClassName` is `"none"`) |
| `PW.Adapters.Defaults` | The table of default implementations, `Defaults.<Method>(adapter, ...)`: see "Defaults" |
| `PW.Adapters.Invalidate()` | Drops the lookup cache |

- `Claims` is called as `adapter:Claims(class, swep)`: the second argument is `weapons.GetStored(class)`, `nil` for an
  engine weapon. An adapter without `IsAvailable` counts as available.
- Tie rule: the same `Priority` is decided by the lowest adapter id (`ClassName`), independent of load order.
- `IsAvailable()` is evaluated lazily, at the first lookup of a class, and again after every cache flush. A lookup
  walks the adapters, asking `IsAvailable` and `Claims` only of those that can still beat the best so far.
- Cache: the result per class, including "nothing claims it", is cached. A cached adapter is dropped when it is no
  longer valid (an error, or the enable snapshot disabled it); the whole cache is dropped when the registry object
  changes, on `Invalidate()`, and on the hooks `PW_RegistriesLoaded`, `PW_WeaponsLoaded`, `PW_PhaseChange` and
  `PW_PhaseChanged`. After `InitPostEntity` every base is mounted, so the first lookup after the weapon phase sees
  the right `IsAvailable()`.

### Fallback adapter (T-3.2)

The core ships one fallback adapter for plain SWEPs and HL2 weapons, so the game works with no weapon base installed
(`04` "Goal and scope"). Mandatory case (T-3.2): it claims a plain SWEP, and its stat defaults come from `Primary.*`
(`notes/08` §5, `GetBaseStats` default: `Primary.Damage/RPM/ClipSize`). Decided (`04`, clarified with the
user on 2026-11-07; `01-extensibility.md` d.5, d.8, d.16): the fallback is an ordinary entity of the kind
`weapon_adapters` in `lua/privatewar/weapon_adapters/`, not a gamemode folder: `sweps.lua`.

Decisions of the lane agent (T-3.2):

- `Priority = -100`: below the default `0` of an adapter that sets none, so any adapter that claims a class wins.
- `IsAvailable()` is always `true`.
- `Claims(class, swep)`: `true` for a class that has a SWEP table (`swep ~= nil`) and for the fixed HL2 classes below
  (engine weapons are not Lua SWEPs: `weapons.GetStored` returns `nil` for them).
- `ListWeapons()`: first the Lua SWEPs of `weapons.GetList()` that are `Spawnable == true`, not `AdminOnly`, and not a
  base: not named `weapon_base` or `*_base`, and not the `Base` of another SWEP in the list; then the HL2 list, sorted
  by class. Each entry is `{ class, name = PrintName or class, kind, slot }`; `category` is `nil` for a Lua SWEP.
- Kind of a SWEP, by `HoldType`: `melee`, `melee2`, `knife`, `fist` give `melee`; `grenade` gives `throwable`; `rpg`
  gives `launcher`; otherwise `gun` when `Primary.Damage` or `Primary.ClipSize` is a number, else `other`.
- Slot of a SWEP (`1` primary, `2` secondary, `3` equipment): `melee`, `throwable` and `other` give `3`; a SWEP with
  the GMod `Slot == 1` (pistols; GMod slots are 0-based) gives `2`; every other gives `1`.
- `GetBaseStats(class)`: for a SWEP the values of `Primary.*` (see `GetBaseStats` in "Defaults"); for an HL2 weapon
  the fixed values below (gameplay values, to be confirmed by the user). Every other method uses the defaults.

| HL2 class | Kind | Category | Slot | Stats |
| --- | --- | --- | --- | --- |
| `weapon_crowbar` | melee | none | 3 | damage 25, rpm 120 |
| `weapon_stunstick` | melee | none | 3 | damage 40, rpm 90 |
| `weapon_pistol` | gun | pistol | 2 | damage 8, rpm 400, magazine 18 |
| `weapon_357` | gun | pistol | 2 | damage 75, rpm 70, magazine 6 |
| `weapon_smg1` | gun | smg | 1 | damage 8, rpm 800, magazine 45 |
| `weapon_ar2` | gun | ar | 1 | damage 12, rpm 600, magazine 30 |
| `weapon_shotgun` | gun | shotgun | 1 | damage 8, rpm 70, magazine 6, pellets 7 |
| `weapon_crossbow` | gun | special | 1 | damage 100, rpm 40, magazine 1 |
| `weapon_rpg` | launcher | special | 1 | damage 150, rpm 30, magazine 1 |
| `weapon_frag` | throwable | none | 3 | damage 125 |
| `weapon_slam` | throwable | none | 3 | damage 150 |

Damage is given as `damageNear` and `damageFar` with the same value.

## Types

Types are taken as written in `notes/08` §5 (`04 d.1`); the `COD.` prefix of the research is `PW.` here. Slot and
option ids are opaque strings: ARC9 slots are nested addresses, MW slots are integers, TFA slots are categories
(`notes/08` §5, item 2). A build is `{ [slotId] = optionId }`.

```lua
---@alias PW.Realm "shared"|"server"|"client"
---@alias PW.WeaponKind "gun"|"melee"|"throwable"|"launcher"|"other"
---@alias PW.SlotId string          -- opaque; ARC9 "3" or "3.1", MW "2", TFA "1"
---@alias PW.OptionId string        -- attachment id; MW: class name (resolved to an index server-side)
---@alias PW.Build table<PW.SlotId, PW.OptionId|false>  -- false = clear (MW: index 1, the slot default)

---@class PW.WeaponInfo
---@field class string
---@field name string                -- PrintName (may be a language token)
---@field kind PW.WeaponKind
---@field category string|nil        -- "ar","smg","sniper","shotgun","pistol","lmg","special"; nil = unknown
---@field slot integer               -- 1 primary, 2 secondary, 3 equipment

---@class PW.Stats                   -- all fields optional; the core shows "-" for nil
---@field damageNear number|nil      -- per trigger pull (per-pellet x pellets)
---@field damageFar number|nil
---@field rangeNear number|nil       -- metres, end of max damage
---@field rangeFar number|nil        -- metres, start of min damage
---@field rpm number|nil
---@field magazine integer|nil       -- without the chambered round
---@field adsTime number|nil         -- seconds
---@field moveMult number|nil        -- 1.0 = no penalty
---@field pellets integer|nil
---@field recoil number|nil         -- T-11.7: base recoil in the base's own unit (compared within one category only)
---@field spread number|nil         -- T-11.7: base spread in the base's own unit
---@field sprintToFire number|nil   -- T-11.7: seconds

---@class PW.OptionStats             -- T-11.7: what an option changes; multipliers, 1 or absent = no change
---@field damage number|nil
---@field range number|nil
---@field rpm number|nil
---@field recoil number|nil
---@field spread number|nil
---@field adsTime number|nil
---@field sprintToFire number|nil
---@field moveSpeed number|nil
---@field reloadTime number|nil
---@field magazineAdd number|nil     -- rounds added to the magazine

---@class PW.Slot
---@field id PW.SlotId
---@field name string
---@field parent PW.SlotId|nil      -- nested slots (ARC9 only)
---@field cosmetic boolean           -- does not count toward the pick cap
---@field default PW.OptionId|nil

---@class PW.Option
---@field id PW.OptionId
---@field name string
---@field icon IMaterial|nil         -- client only
---@field cosmetic boolean

---@class PW.FireInfo
---@field kind "auto"|"semi"|"burst"|"safe"
---@field burst integer              -- rounds per burst; 1 for semi
---@field rpm number
---@field adsKey integer             -- IN_ATTACK2 (MW launchers: IN_ATTACK)
---@field projectileSpeed number|nil -- HU/s; nil = hitscan
---@field projectileGravity number|nil -- HU/s^2

---@class PW.Recoil
---@field pitch number               -- degrees per shot, average
---@field yaw number                 -- degrees per shot, +- range
---@field affectsBotAim boolean      -- true when the server-side shot direction is deflected

---@class PW.InputRules              -- consumed by the bot input writer
---@field releaseBetweenShots boolean -- semi/burst need >=1 tick with IN_ATTACK up
---@field reloadTap boolean          -- TFA: press then release within the window
---@field reloadTapMax number        -- seconds (TFA 0.3)
---@field forbidWithAttack integer   -- button mask never sent together with IN_ATTACK (TFA: IN_USE)
---@field forbidWithReload integer   -- ARC9: IN_USE|IN_WALK, TFA: IN_USE
---@field noSprintWhileFiring boolean -- MW, ARC9: drop IN_SPEED before firing
---@field sprintToFire number        -- seconds to wait after sprint
---@field reselectEveryTick boolean  -- MW: repeat cmd:SelectWeapon until active
```

## Interface

Required methods: `IsAvailable`, `Claims`, `ListWeapons`. Everything else is optional with a safe default in the core
(`04 d.1`). The realm and the default of each method are as in `notes/08` §5; the colon call style is `04 d.1`.

### Discovery (required)

| Method | Realm | Returns |
| --- | --- | --- |
| `ADAPTER:IsAvailable()` | shared | `boolean`: the base is installed |
| `ADAPTER:Claims(class)` | shared | `boolean`: this adapter handles the SWEP class |
| `ADAPTER:ListWeapons()` | shared | `PW.WeaponInfo[]` |

`ListWeapons` is called by the `weapons_catalog` module in `PW_RegisterWeapons` (see "Weapon catalogue"); an
integration module still registers its own curation with `soft` registrations.

### Stats (optional)

| Method | Realm | Default | Returns |
| --- | --- | --- | --- |
| `ADAPTER:GetBaseStats(class)` | shared | `Primary.Damage/RPM/ClipSize/NumShots`, see "Defaults" | `PW.Stats`. Static values of a class |
| `ADAPTER:GetLiveStats(wep)` | shared | `GetBaseStats(wep:GetClass())` | `PW.Stats`. Values of a live weapon (after the build) |
| `ADAPTER:PreviewBuildStats(class, build)` | shared | `nil` (the UI shows base stats only) | `PW.Stats?`. Only MW can implement it statically |
| `ADAPTER:GetIcon(class)` | client | `Material("entities/<class>.png")` | `IMaterial?` |

`GetStats` is split into a static and a live method because ARC9 and TFA apply attachments only on a live entity
(`notes/08` §5, item 1).

### Attachments (optional; absent = the weapon has no gunsmith)

| Method | Realm | Default | Contract |
| --- | --- | --- | --- |
| `ADAPTER:GetSlots(class, build)` | shared | none: no gunsmith | `PW.Slot[]`; `build` may be `nil`; nested slots depend on the build (ARC9) |
| `ADAPTER:GetOptions(class, slot)` | shared | none | `PW.Option[]` for a slot |
| `ADAPTER:Validate(class, build)` | server | identity | `clean: PW.Build, rejected: table<PW.SlotId, string>` (reason codes). A cheap static check: the slot exists, the option belongs to the slot. Runs when a class is saved, not at every spawn (`05-loadout.md` d.15) |
| `ADAPTER:Apply(wep, build)` | server | none | `PW.Build`: what actually stuck. Applies, syncs to clients, blocks client presets. Runs at spawn after `Give` (`05-loadout.md` d.15) |
| `ADAPTER:SetCustomizationLocked(locked)` | server | no-op, logged once | Idempotent. `04 d.2`: applied with `true` for the whole session by every adapter |

- The gamemode owns attachments; there is no in-match customization and no "free customization" toggle. Native
  customization menus of ARC9, TFA and MW Base are always blocked (`04 d.2`).
- `Validate` and `Apply` move to the live weapon because every base validates against instance state
  (`notes/08` §5, item 3).
- Attachments are not registry entities; they stay adapter data (`06-progression.md` d.2).
- Mandatory cases (T-3.6 to T-3.8): `Apply` on a bot's weapon returns the applied build; a conflicting build returns
  what stuck; the lock is active (the base's own customization path refuses).
- ARC9 requires `arc9_atts_nocustomize 1` for the whole session (`04` "Security").

### Option stats (optional; T-11.7)

Added on 2026-11-07 for the stat-based unlock levels (`06-progression.md` d.2 revision; `progression.md`, "Automatic
unlock levels"). Both have no default: an adapter without them gives every option the middle level of its slot, and
its cache key covers only the weapon set.

| Method | Realm | Contract |
| --- | --- | --- |
| `ADAPTER:GetOptionStats(class, slot, option)` | shared | `PW.OptionStats?`: what the option changes on that weapon, as multipliers (`magazineAdd` in rounds); `nil` when it changes no numeric stat. Must not error on odd data (an error disables the adapter) |
| `ADAPTER:GetOptionSetKey()` | shared | `string`: changes whenever the set of options the adapter can offer changes (packs added or removed) |

ARC9 (integration addon): `GetOptionStats` reads the attachment table through `PW.Arc9._OptionStats`. Each field is the
product of stat ratios `new / old` raised to a share (`PW.Arc9.OptionStatKeys`): `damage` from `DamageMax`,
`DamageMin` (0.5 each); `range` from `RangeMax`, `RangeMin` (0.5 each); `rpm` from `RPM`; `recoil` from `Recoil` (1)
and `RecoilUp`, `RecoilSide`, `RecoilKick` (1/3 each); `spread` from `Spread` (1) and its `HipFire` condition (0.5);
`adsTime` from `AimDownSightsTime`; `sprintToFire` from `SprintToFireTime`; `moveSpeed` from `Speed` (1) and its
`Sights` condition (0.5); `reloadTime` from `ReloadTime`; `magazineAdd` = `ClipSizeAdd`. A stat ratio comes from
`<stat>Override<cond>` (against the weapon's base value), else `<stat>Mult<cond>` and `<stat>Add<cond>` (an `Add`
needs the base value of the class, read once per memo revision). `GetOptionSetKey` is the count and a CRC of the
sorted attachment names. `GetBaseStats` also fills `recoil` (`Recoil`), `spread` (`Spread`) and `sprintToFire`
(`SprintToFireTime`).

### Ammo (optional)

| Method | Realm | Default | Contract |
| --- | --- | --- | --- |
| `ADAPTER:SuppressDefaultAmmo(wep)` | server | no-op | Called right after `ply:Give`; stops the base from giving its own default ammo (ARC9: delayed 0.4 s; MW: zero; TFA: ConVar) |
| `ADAPTER:GetAmmoType(wep)` | shared | `wep:GetPrimaryAmmoType()` | `integer`: the ammo type id |

- Ammo is owned by the core: after `SuppressDefaultAmmo` the core gives ammo (`04 d.1`; `05-loadout.md` d.15;
  `notes/08` §5, item 5; T-3.4: "default ammo suppressed; the core gives the configured magazines"). Who gives it and
  how many: "Ammo module".
- The default ammo suppression happens before the base's own timer (ARC9: `wep.ForceDefaultAmmo = 0` before the
  0.4 s timer; `notes/08` §5.1).

### State (optional)

| Method | Realm | Default |
| --- | --- | --- |
| `ADAPTER:IsReloading(wep)` | shared | `false` |
| `ADAPTER:IsAiming(wep)` | shared | `owner:KeyDown(IN_ATTACK2)` |
| `ADAPTER:GetClip(wep)` | shared | `wep:Clip1(), wep:GetMaxClip1()` (`clip, capacity`) |
| `ADAPTER:CanFireNow(wep)` | shared | `wep:GetNextPrimaryFire() <= CurTime() and clip ~= 0` (a weapon with no magazine, `Clip1 < 0`, is not blocked by the clip) |

### Bots (optional)

| Method | Realm | Default | Contract |
| --- | --- | --- | --- |
| `ADAPTER:PrepareForBot(ply, wep)` | server | no-op | Once per `Give` for a bot-owned weapon (`05-loadout.md` d.15, item 5) |
| `ADAPTER:GetFireInfo(wep)` | server | `{ kind = Primary.Automatic and "auto" or "semi", burst = 1, rpm, adsKey = IN_ATTACK2 }` | `PW.FireInfo` |
| `ADAPTER:GetRecoil(wep)` | server | `{ pitch = 0, yaw = 0, affectsBotAim = false }` | `PW.Recoil`; `07-bots.md` d.8 uses it for recoil compensation |
| `ADAPTER:GetInputRules(wep)` | server | conservative: release between shots, plain `IN_RELOAD` | `PW.InputRules` |
| `ADAPTER:BotAction(ply, wep, action, arg)` | server | `false` | `boolean done`; `action` is `"firemode"`, `"melee"` or `"safety_off"`: actions a bot cannot express through `CUserCmd` |

### Bot input rules (`GetInputRules`)

`PW.InputRules` (see "Types") is consumed by the bot input writer of the bots lane (`07-bots.md` d.2: bots act only
through `CUserCmd`). The writer follows these core rules for all bases (`notes/08` §6.1):

1. Write button bits, not only `SetForwardMove`: MW and ARC9 decide sprint and bipod from `IN_FORWARD`,
   `IN_MOVELEFT`, and so on.
2. Release `IN_ATTACK` for at least one tick between semi and burst shots (`releaseBetweenShots`).
3. Never send `IN_USE` together with `IN_ATTACK`, `IN_ATTACK2` or `IN_RELOAD` (`forbidWithAttack`,
   `forbidWithReload`).
4. Use the core's own PRNG for the AI (MW reseeds `math.random`).
5. Keep `cmd:SelectWeapon(target)` every tick until `GetActiveWeapon()` matches (`reselectEveryTick`).

Per-base values (`notes/08` §6.2 to §6.4, research): ARC9 `forbidWithReload = IN_USE|IN_WALK`,
`noSprintWhileFiring = true`; MW `reloadTap = false`, `reselectEveryTick = true`, `noSprintWhileFiring = true`;
TFA `reloadTap = true`, `reloadTapMax = 0.3`, `forbidWithAttack = IN_USE`, `forbidWithReload = IN_USE`. The values of
the default (a base that implements nothing): see "Defaults".

### Bot actions (`BotAction`)

`BotAction` answers `true` only when the action happened; the caller never branches on a weapon base. Per base:

- ARC9 `"firemode"`: `arg` is the firemode index, or `nil` for the next one (`SetFiremode`; ARC9 reads its firemode bind
  from the client).
- ARC9 `"melee"` (T-11.6 follow-up): ARC9's own bash. ARC9's melee key is `IN_BULLRUSH` read through `KeyPressed`,
  which the bot input writer does not send, so the adapter starts the swing on the server with the weapon's
  `MeleeAttack`; ARC9 then plays the bash, hits after `PreBashTime / BashSpeed` with `BashDamage` along `BashRange`,
  lunges at a target within `BashLungeRange` and waits `PostBashTime` before the next bash. `true` when the swing
  started. `false` (no swing) without a bash (`Bash` and `PrimaryBash` off, attachments included), and wherever ARC9's
  own key would refuse it, by `PW.Arc9._BashRefusal` (pure, in this order): safety on, in sights, a primed grenade,
  bipod, a swing under way, the bash cooldown, a reload (unless `BashCancelsReload`), an animation lock, primed attack
  or holster, sprinting or the barrel against a wall (unless `BashWhileSprint`), and no player, NPC or nextbot along
  the aim within the longer of `BashRange` and `BashLungeRange`, so a bot never whiffs into the cooldown. Unlike the
  key path, the gun's fire cadence (the next primary fire time) does not refuse it: a bot shoots until the bash.
- ARC9 reach and damage: `BashRange` 64 units from the eye (the base default; the MW2019 pack keeps 64, with
  `BashLungeRange` 0, `BashDamage` 55, `PreBashTime` and `PostBashTime` 0.2), against the bots' melee threshold of
  110 units between the feet (`bots-blackboard.md`, "Combat movement"): between about 80 and 110 units the adapter answers
  `false` and `fight` asks again 0.8 s later.

### Kill info (optional)

| Method | Realm | Default | Contract |
| --- | --- | --- | --- |
| `ADAPTER:IsHeadshot(dmginfo)` | server | `nil` (the core decides) | `boolean?`; called after the core's hitgroup check |
| `ADAPTER:GetDisplayName(wep)` | shared | `language.GetPhrase(wep.PrintName)` | `string` |

Headshots and hitgroups are owned by the core (`notes/08` §5, item 7; §6.1 rule 5). Damage scaling is applied once in
the core damage hook (`04 d.6`).

## Defaults

`PW.Adapters.Defaults.<Method>(adapter, ...)` answers a method an adapter does not implement (lane agent decision,
T-3.1; `PW.Adapters.Call`). Each is safe for a plain weapon: one without `Primary`, an owner or a clip.

| Method | Default |
| --- | --- |
| `GetBaseStats(class)` | From `weapons.GetStored(class).Primary` (a missing `Primary` gives `{}`): `damageNear` and `damageFar` = `Damage`; `rpm` = `RPM`; `magazine` = `floor(ClipSize)`; `pellets` = `NumShots`. A field exists only when the source is a number above 0 |
| `GetLiveStats(wep)` | `GetBaseStats(wep:GetClass())` through `PW.Adapters.Call` |
| `PreviewBuildStats()` | `nil` |
| `GetIcon(class)` | Client: `Material("entities/<class>.png")`; server: `nil` |
| `GetSlots()`, `GetOptions()` | `{}` |
| `Validate(class, build)` | `build, {}` (identity, nothing rejected) |
| `Apply(wep, build)` | `{}` (no gunsmith: nothing sticks) |
| `SetCustomizationLocked(locked)` | No-op; one log line per adapter id (`weapon adapter "<id>" has no SetCustomizationLocked; its customization stays as it is`) |
| `SuppressDefaultAmmo(wep)` | No-op |
| `GetAmmoType(wep)` | `wep:GetPrimaryAmmoType()` |
| `IsReloading(wep)` | `false` |
| `IsAiming(wep)` | `owner:KeyDown(IN_ATTACK2)`; `false` without a valid owner |
| `GetClip(wep)` | `wep:Clip1(), wep:GetMaxClip1()` |
| `CanFireNow(wep)` | `wep:GetNextPrimaryFire() <= CurTime()` and the clip from `GetClip` is not `0` |
| `PrepareForBot(ply, wep)` | No-op |
| `GetFireInfo(wep)` | `{ kind = Primary.Automatic and "auto" or "semi", burst = 1, rpm, adsKey = IN_ATTACK2 }`; `rpm` is `Primary.RPM`, else `60 / Primary.Delay`, else 600 |
| `GetRecoil(wep)` | `{ pitch = 0, yaw = 0, affectsBotAim = false }` |
| `GetInputRules(wep)` | The conservative rules below |
| `BotAction(ply, wep, action, arg)` | `false` |
| `IsHeadshot(dmginfo)` | `nil` |
| `GetDisplayName(wep)` | `PrintName` (else the class); on the client through `language.GetPhrase` |
| `InstallStatMods(wep)`, `RefreshStatMods(wep)` | No-op |
| `SupportedStatMods()` | `{}` |

Default `PW.InputRules` (lane agent decision, T-3.1; the core rules of "Bot input rules" included):

| Field | Value |
| --- | --- |
| `releaseBetweenShots` | `true` |
| `reloadTap` | `false` |
| `reloadTapMax` | `0.3` |
| `forbidWithAttack` | `IN_USE` |
| `forbidWithReload` | `IN_USE` |
| `noSprintWhileFiring` | `true` |
| `sprintToFire` | `0.25` |
| `reselectEveryTick` | `true` |

## Stat modifiers (`04 d.6`)

Per-player weapon stat modifiers: the values live in replicated player state; adapters only wire the base. A
server-only "apply" call cannot reach client-predicted code on any of the three bases (`notes/12` §6.1).

### Keys

Multipliers, absent = `1.0` (`04 d.6`):

| Key | Meaning |
| --- | --- |
| `reload_time` | Reload time multiplier (`0.8` = 20 % faster) |
| `draw_time` | Draw and holster time multiplier |
| `ads_time` | Aim-down-sights time multiplier |
| `sprint_to_fire` | Time from sprint to fire |
| `recoil` | Recoil multiplier |
| `spread` | Spread multiplier |

The multiplier semantics of each key follow `notes/12` §6.1 (research).

### Optional adapter methods (shared, default no-op)

| Method | Contract |
| --- | --- |
| `ADAPTER:InstallStatMods(wep)` | Once per weapon instance, on both realms; idempotent |
| `ADAPTER:RefreshStatMods(wep)` | Called after the owner's modifier revision changed |
| `ADAPTER:SupportedStatMods()` | The keys the base honours, `table<string, boolean>`, for the UI and perk descriptions. Default `{}` (`notes/12` §6.1) |

### `PW.SetStatMods(ply, mods)` and `PW.GetStatMod(ply, key)`

| Function | Realm | Contract |
| --- | --- | --- |
| `PW.SetStatMods(ply, mods)` | server | Writes the NW2 float of each of the six keys on the player (absent key = `1.0`), then a revision counter, written last. `PW.SetStatMods(ply, {})` (or `nil`) removes every modifier. Unknown keys are ignored; a value that is not a positive finite number is stored as `1.0`. A non-player or invalid entity is ignored. Each call bumps the revision once (it wraps to 1 at 2^30) |
| `PW.GetStatMod(ply, key) -> number` | shared | The player's value of `key`; `1` for a non-player or an invalid entity, and for an unknown key. The only reader every adapter uses |

Module `weapons_statmods` (T-3.5), namespace `PW.StatMods` (`SetStatMods`, `GetStatMod`; `PW.SetStatMods` and
`PW.GetStatMod` are the documented aliases, because `PW.Weapons` is the registry). The keys are the six of "Keys".
Types: `lua/privatewar/types/weapons_statmods.lua`.

- NW2 (internal; readers use `PW.GetStatMod`): Float `pw_sm_<key>` per key (default `1`) and Int `pw_sm_rev` (default
  `0`) on the player.
- The refresh loop is a `Think` hook through `PW.HookFor` (it stops while the module is disabled): on the server for
  every player, on the client for `LocalPlayer()` only. A player whose revision is `0` and who was never refreshed costs
  one NW2 read per tick.
- For a player with revision `r`, each weapon the player holds is refreshed when it has not been seen for this owner
  and this revision:
  - a weapon first seen while `r == 0` is only recorded: no refresh, no install;
  - otherwise the loop calls `InstallStatMods(wep)` (only the first time for that weapon instance) and then
    `RefreshStatMods(wep)`, once per revision per weapon;
  - a weapon whose owner changed is refreshed again, with the new owner's values; weapons picked up later are
    covered, because the loop reads the player's weapon list every tick once the player has been swept.
- Both adapter calls go through `PW.Adapters.CallFor` (the defaults are no-ops), so a weapon of a player with no
  modifiers is never touched.

- The values live on the player, so a weapon picked up by another player reads its new owner's values automatically
  (`04 d.6`).
- A shared check refreshes weapons whose owner's revision moved: on the server for all players, on the client for
  `LocalPlayer()` only (`04 d.6`).
- Mandatory case (T-3.5): `SetStatMods` writes the NW2 values and bumps the revision once; the refresh is called once
  per revision per weapon; removal resets to `1.0`.
- The names of the NW2 variables are internal; readers use `PW.GetStatMod` (`01-extensibility.md` d.14).
- Per-base mechanism (`04 d.6`): ARC9 uses per-instance `<Stat>Hook` functions plus `DoInvalidateCache` (a global
  `ARC9_<Stat>Hook` is unreliable); MW Base uses `OnBuildCustomizedGun` scaling `Animations.*.Fps` plus
  `BuildCustomizedGun`; TFA uses `TFA_GetStat` / `TFA_AnimationRate`.
- Excluded from MVP (`04 d.6`): `sprint_to_fire` on TFA, magazine size, damage (applied once in the core damage hook),
  reload, recoil and spread on plain SWEPs and HL2 weapons, RPM.
- Mandatory case (T-3.6 to T-3.8): stat mods change the server-side value of at least reload time.
- The module `weapons_statmods` hosts `PW.SetStatMods` and the refresh loop. The perks module of the loadout lane
  calls `PW.SetStatMods` (`05-loadout.md` d.8: weapon stats go through it).

## Ammo module

Module `weapons_ammo` (T-3.4), namespace `PW.WeaponAmmo` (`PW.Weapons` is the registry). Ammo is owned by the core:
the weapon base's default ammo is suppressed, then the module gives the configured number of magazines. Types:
`lua/privatewar/types/weapons_ammo.lua`. Lane agent decisions:

| Function | Realm | Contract |
| --- | --- | --- |
| `PW.WeaponAmmo.Give(ply, class, opts?) -> Weapon?` | server | Gives the weapon to the player: `ply:Give(class, true)` (no default ammo), then `ADAPTER:SuppressDefaultAmmo`, the clip is filled to the capacity of `ADAPTER:GetClip` (when above 0), and the reserve of `ADAPTER:GetAmmoType` is set (absolute, replacing what the base left) to `magazines * floor(clip size)`. A weapon without a clip gets one round per magazine. `opts.magazines` overrides the setting. Returns the weapon, or `nil` when nothing was given (an invalid player, a non-string class, the player already holds the weapon, or `Give` failed). The loadout lane calls it |

Setting (full id `weapons_ammo.magazines`, scope `match`, the default scope):

| Key | Type | Default | Range | Meaning |
| --- | --- | --- | --- | --- |
| `magazines` | int | 3 | 0 to 20 | Spare magazines per weapon (gameplay value, to be confirmed by the user) |

The setting is read when `Give` runs, as a non-negative integer (a non-number reads as 3). Internal: `_ReserveFor`,
`_Magazines`.

### Ordinary-reserve resupply extension

Approved consumer requirements: `design/05-loadout.md` d.16 and support-streak cache.
The following contract is implemented after observed GLuaTest RED; mounted verification is pending.
Spawn-only `Give` and delayed base-default-ammo suppression remain unchanged.

- `PW.WeaponAmmo.Resupply(ply, weapons, opts?) -> table<integer, integer>`: server-authoritative
  ordinary reserve only. `weapons` is an explicit list of the recipient's existing weapons;
  `opts.fraction` is the requested magazine fraction (default 1), `opts.maxMagazines` the
  reserve ceiling in magazines (default 3). Return only ammo types actually supplied, mapped
  to rounds added. The cache requests fraction 1; Scavenger requests fraction 0.5.
- A disabled `weapons_ammo` owner makes retained `Resupply` calls return `{}` without reserve
  mutation. Pure resupply math and `DamageWeapon` remain usable utilities, including weapon XP attribution.
- Read live capacity and primary ammo through the adapter. Reject invalid, foreign, clipless
  and grenade weapons, negative/unknown ammo types and the equipment ammo types. No `Give`,
  no clip mutation and no grenade-count mutation. Human and bot recipients follow one path.
- Deduplicate before mutation by ammo type. For shared ammo, use the largest eligible capacity
  in the explicit list, independent of list order. Requested rounds are
  `max(1, floor(capacity * fraction))`; add only up to `capacity * maxMagazines`. Existing
  excess reserve is never reduced. Invalid/nonfinite/nonpositive requests supply nothing.
- Pure test seams: `_ResupplyAmount(capacity, reserve, fraction, maxMagazines)` and
  `_ResupplyPlan(entries, fraction, maxMagazines)`, with entries `{ ammo, capacity, reserve }`.
  The plan maps ammo ids to positive additions, not new absolute totals.
- `PW.WeaponAmmo.DamageWeapon(owner, dmg) -> Weapon?, boolean`: proven scoring weapon and
  direct-weapon eligibility. A valid owned weapon inflictor may retain weapon attribution
  without qualifying for scavenging (for example grenade/delayed explosive damage). An
  unrelated held gun is never substituted for world/projectile/streak damage. The active
  weapon fallback is allowed only when the inflictor is the player and the damage is a
  direct weapon hit, not an autonomous or delayed nonweapon effect.
- `_DamageSource(facts)` is the pure provenance classifier used by the engine wrapper.
  Match kill scoring uses proven attribution without changing player score/XP rewards.

The support-streak owner owns receipt cooldowns, device charges and deployment; this service
owns only bounded ordinary-reserve mutation. Tests: `ammo_resupply.lua`, `perk_rewards.lua`.

## Weapon catalogue (kind `weapons`)

The kind exists (`core.md` "Built-in kind `weapons`"): folder `weapons/`, class table `WEAPON`, id = SWEP class, no
required fields, enable ConVar `pw_weapon_<class>_enabled` (`04 d.3`; `01-extensibility.md` d.11). This section adds
the curation fields (`04 d.3`; `06-progression.md` d.2) and the integration rules (`04 d.3`, `d.4`). The existing
fields `Category`, `Name` and `Unlock` are in `core.md`.

### Fields

| Field | Type | Meaning | Source |
| --- | --- | --- | --- |
| `Category` | string? | `"ar"`, `"smg"`, ... | `04 d.3`; `core.md` |
| `Name` | string? | Display name | `04 d.3`; `core.md` |
| `Unlock` | integer? | Player level that unlocks the weapon; empty: `06-progression.md` decides the default | `04 d.3`; `06-progression.md` d.1, d.2 |
| `Attachments` | `table<PW.OptionId, table>`? | Optional curation, keyed by option id | `06-progression.md` d.2 |
| `Camos` | `table<string, table>`? | Cosmetic options by id | `06-progression.md` d.2 |
| `Cost` | number? | Pick X cost; default 1 | `05-loadout.md` d.2 (an author may set another value, for example a sniper rifle 2) |
| `Price` | number? | Shop price; the weapon is unlocked if the level is reached or it was bought | `06-progression.md` d.6 |
| `Kind` | `PW.WeaponKind`? | Filled softly from `ListWeapons` (lane agent, T-3.3) | `04 d.3` |
| `Slot` | integer? | `1` primary, `2` secondary, `3` equipment; filled softly from `ListWeapons` | `04 d.3` |

Entries of `Attachments` (per option id):

| Field | Type | Meaning |
| --- | --- | --- |
| `Unlock` | integer | Weapon level that unlocks the option |
| `Cost` | number | Pick X cost of the option |
| `Hidden` | boolean | Never offered |

Entries of `Camos` (per camo id): `Unlock` (weapon level) (`06-progression.md` d.2).

```lua
function MODULE:PW_RegisterWeapons(reg)
    reg.Register({
        Category = "ar",
        Unlock   = 4,
        Attachments = {
            optic_acog  = { Unlock = 5 },
            muzzle_supp = { Unlock = 12, Cost = 2 },
            meme_scope  = { Hidden = true },
        },
        Camos = { gold = { Unlock = 30 } },
    }, "arc9_eft_ak74", { soft = true })
end
```

- Without curation, the weapon level unlocks the number of attachments that may be installed, any attachment allowed,
  capped by `loadout.maxattachments` (`06-progression.md` d.2).
- Camos are the bases' cosmetic attachment options (`cosmetic` flag); MVP unlocks them by weapon level only
  (`06-progression.md` d.2).
- Banning a single attachment for a match: the `set` setting `loadout.bannedatts` with `"<adapter>:<option id>"`
  strings (`06-progression.md` d.2).
- `PW_PreRegister` runs on weapon entries (also programmatic ones after the main load); another addon can patch the
  curation of someone else's weapon. `Base` of a late entry is resolved at registration time (`04 d.3`;
  `06-progression.md` d.2).

### Registration and `soft`

- Entries come from files in `lua/privatewar/weapons/` (declarative; loaded earlier) and from `PW_RegisterWeapons(reg)`
  listeners (programmatic) (`04 d.3`; `core.md` "Weapon registration phase").
- Phase: in `InitPostEntity` the core calls `PW_RegisterWeapons(reg)`, then fires `PW_WeaponsLoaded`. Consumers
  (loadout, bots, HUD) wait for `PW_WeaponsLoaded`; registering from a module's own `InitPostEntity` is not used
  because hook order is undefined (`04 d.3`).
- `{ soft = true }`: if an entry with that id exists, only missing fields are filled and nothing is overwritten.
  Declarative files and explicit `Register` calls win; automatic registration fills gaps. Without `soft`, a
  registration replaces the entry (`04 d.3`; `01-extensibility.md` d.12).
- `soft` merges nested tables per key: a curated file overrides automatic values option by option, not the whole
  `Attachments` table (`06-progression.md` d.2; `core.md` "Registry").
- Every entry gets the ConVar `pw_weapon_<class>_enabled`; the host can hide any weapon regardless of who registered
  it (`04 d.3`).
- Mandatory case (T-3.3): a declarative entry beats a programmatic `soft` entry per field; the per-weapon ConVar hides
  a weapon; curation fields (`Attachments`, `Camos`) survive the merge.
- Weapon packs and bases mix freely; installed integrations are all active at once. Restrictions are `match` settings
  of the loadout module: `weapons.bases` (allowed bases, default all) and a banned-weapons list (`04 d.5`;
  `05-loadout.md`).

### Population from the adapters (T-3.3)

Module `weapons_catalog`, namespace `PW.WeaponsCatalog` (lane agent decisions; types
`lua/privatewar/types/weapons_catalog.lua`):

- `ListWeapons` has one generic caller: this module. In `PW_RegisterWeapons` it calls `ListWeapons` of every enabled
  and available (`IsAvailable()`) adapter, highest `Priority` first (ties: lowest id), through `PW.Call`, and registers
  each class with `reg.Register(entry, class, { soft = true })`. The fields taken from `PW.WeaponInfo`: `Name`,
  `Category`, `Kind`, `Slot`. When several adapters list the same class, the first list (highest `Priority`) wins each
  field, the others fill what is missing. An integration module still curates with its own soft registration
  (`Attachments`, `Camos`, `Unlock`, ...).
- Order independence. A soft registration only fills the missing fields of an existing entry, but a later plain
  registration of the same class replaces the entry (`01-extensibility.md` d.12) and the soft fields would be lost.
  So the module keeps what it filled during the phase and, on `PW_PreRegister` of a `weapons` entry, adds the missing
  fields to the incoming table. The fills live from `PW_RegisterWeapons` to `PW_WeaponsLoaded` (released on it); a
  registration after the phase replaces the entry, as `core.md` says.
- The table trap: `Register` stores a table passed for a new id as the entry itself (and stamps it). `Populate`
  therefore registers a `table.Copy` of each fill, and the fill helper copies nested tables, so a registry entry never
  aliases the stored fills (writing into one would change the other).

| Function | Contract |
| --- | --- |
| `PW.WeaponsCatalog.Populate(reg, adapters?, call?) -> integer` | Does the above for `reg`; `adapters` defaults to the enabled `weapon_adapters`, `call` to `PW.Call`. Returns the number of classes registered; replaces the stored fills. The module calls it itself in `PW_RegisterWeapons` |
| `PW.WeaponsCatalog.GetByCategory(category, registry?) -> PW.Weapon[]` | The enabled entries of the weapons registry (default `PW.Weapons`) whose `Category` equals `category`, sorted by class |

### One integration = one addon (`04 d.4`)

```text
privatewar-arc9/lua/privatewar/
  modules/arc9/shared.lua          MODULE: base ConVars (arc9_atts_nocustomize 1), bot shims, weapon registration
  weapon_adapters/arc9.lua         ADAPTER: Claims, Apply, GetFireInfo, ...
```

The module owns everything base-specific; the adapter stays a separate entity because loadout, bots and HUD look up
the adapter for a weapon class through `Claims` and `Priority` (`04 d.4`).

#### ARC9 session ConVars

| Set | Realm | ConVars | Restored on `ShutDown` |
| --- | --- | --- | --- |
| Customization lock (`PW.Arc9.LockConVars`) | server | `arc9_atts_nocustomize 1`, `arc9_atts_anarchy 0`, `arc9_free_atts 0`, `arc9_atts_loseondie 0` | yes |
| HUD (`HudConVars`, `ClientHudConVars`) | server, client | `arc9_hud_force_disable 1` (replicated); `arc9_hud_hints 0` | yes |
| Precache (`PrecacheConVars`) | server | `arc9_precache_wepmodels_onstartup 1`, `arc9_precache_attsmodels_onstartup 1` | no |
| Performance profile `deck` (`PerfConVars.client`) | client | `arc9_tpik_others 0`, `arc9_lod_distance 0.4`, `arc9_cheapscopes 1`, `arc9_fx_rtvm 0`, `arc9_muzzle_others 0`, `arc9_eject_fx 0` | yes |
| Performance profile `deck` (`PerfConVars.server`) | server | `arc9_bullet_physics 0`, `arc9_ricochet 0` | yes |

The performance profile (`04 d.7`) follows the host setting `arc9.perf` (`deck` default, `off`), shown in the Host
section of SETTINGS. Each realm's glue checks it once a second (`PW.Arc9.ApplyPerf`), so a change applies at once:
`deck` saves the current values and sets the profile, `off` restores the saved values and then leaves ARC9 alone.
Nothing happens while the global `ARC9` is missing. `arc9_cheapscopes` is an unreplicated ConVar of each realm, read
by the client's scope code, so the client sets its own.

Crash safety: when `deck` is first applied, the realm writes the values it replaced to
`data/privatewar/arc9_perf_<realm>.json` (`PW.Arc9.PerfBackupPath`; one file per realm because a listen host shares
`data/`). The first apply of a session finds a file left by a session without `ShutDown` and restores its values
before applying the profile again (`_RecoverPerf`; one log line `[PW] arc9: restored N ARC9 <realm> settings ...`).
`off` and a clean `ShutDown` restore and delete the file. The pure part is `modules/arc9/sh_perf.lua`
(`_PerfAction`, `_ApplyPerf`, `_RestorePerf`, `_RecoverPerf` over `PW.Arc9ConVarIO` and `PW.Arc9PerfBackup`).

## Differences from `notes/08` §5

The design wins (`04 d.1`):

| `notes/08` §5 | Design | Source |
| --- | --- | --- |
| Methods written `Adapter.Method(...)` | `ADAPTER:Method(...)`, SWEP style | `04 d.1` |
| Field `id` required | No `id` field; the id is the file name | `04 d.1`; `01-extensibility.md` d.8 |
| Field `apiVersion` required | No `apiVersion`; adapters guard with `PW.API` | `04 d.1`; `01-extensibility.md` d.14 |
| Field `priority` (default 0) | Field `Priority`, higher wins | `04 d.1` |
| Types `COD.*`, global `COD` | Types `PW.*`, global `PW` | namespace of the project (`core.md`) |
| Stat-mod methods not in §5 | Added: `InstallStatMods`, `RefreshStatMods`, `SupportedStatMods` | `04 d.6`; `notes/12` §6.1 |
| `notes/12` names `COD.SetStatMods`, `COD.GetStatMod`, NW2 prefix `cod_sm_` | `PW.SetStatMods`, `PW.GetStatMod`; NW2 names internal | `04 d.6` |
| Adapters registered in an adapter list | Ordinary entities of the kind `weapon_adapters` | `04` "Registration" |

## Core changes needed

1. **Kind declaration file** `lua/privatewar/kinds/weapon_adapters.lua`: `Folder = "weapon_adapters"`,
   `Global = "ADAPTER"`, `Subscribe = "never"`, `Required = { IsAvailable = "function", Claims = "function",
   ListWeapons = "function" }`, validated after `Base` resolution. The core lane's directory; the orchestrator added
   the file for T-3.1.
2. **`KIND.Required` is checked before `Base` resolution** (`sh_loader.lua`, `loadEntity`; see `modes.md`, "Core
   changes needed", item 2). If an adapter requires `function` fields (`IsAvailable`, `Claims`, `ListWeapons`), an
   adapter that inherits them through `Base` is rejected. Decided: `KIND.Required` will be validated after `Base`
   resolution (wave 0).
3. **Extension of `PW.Weapon`** with `Attachments`, `Camos`, `Cost`, `Price` is a non-breaking addition
   (`01-extensibility.md` d.14); the type file `lua/privatewar/types/weapons.lua` is core-owned and gets the fields.
4. No other core change: the registration phase, `soft` and `PW_PreRegister` exist (`core.md`).

## Open in design

Nothing here is invented. Each item says what is missing and which task it blocks.

- **Details are decided by the lane agent.** The API details and defaults listed here (names, return types, event
  points, thresholds, magazine counts) are decided by the lane agent of each task. The agent documents them and
  reports them; the orchestrator writes them into this contract after the merge. Only gameplay-changing choices go
  to the user.

1. ~~**Lookup API.**~~ Decided (lane agent, T-3.1): `PW.Adapters.For`, tie rule lowest id, see "Lookup".
2. ~~**When `IsAvailable()` is evaluated.**~~ Decided (lane agent, T-3.1): lazily at the first lookup of a class and
   again after every cache flush, see "Lookup".
3. ~~**`Priority` of the fallback adapter.**~~ Decided (lane agent, T-3.2): `-100`.
4. ~~Location of the fallback adapter~~ Closed: `lua/privatewar/weapon_adapters/` (see "Fallback adapter").
5. ~~**`ListWeapons` versus `PW_RegisterWeapons`.**~~ Decided (lane agent, T-3.3): the `weapons_catalog` module
   calls it, see "Population from the adapters".
6. ~~**Who gives ammo and how many.**~~ Decided (lane agent, T-3.4): `PW.WeaponAmmo.Give`, setting
   `weapons_ammo.magazines` (3), see "Ammo module".
7. ~~**Default `PW.InputRules`.**~~ Decided (lane agent, T-3.1), see "Defaults".
8. ~~**`Required` list of the kind `weapon_adapters`.**~~ Decided: `IsAvailable`, `Claims`, `ListWeapons` as
   `"function"`.
9. **Category set.** `04 d.3` shows `"ar"` and `"smg"`; the research lists `"ar"`, `"smg"`, `"sniper"`, `"shotgun"`,
   `"pistol"`, `"lmg"`, `"special"` (`notes/08` §5), not a decision. The closed list, and the mapping from each base's
   own categories. Blocks T-3.3 for category filtering in the loadout; does not block the registry. In code: the HL2
   list of `sweps` uses `pistol`, `smg`, `ar`, `shotgun` and `special`; `GetByCategory` compares the string as given.
10. **`PW_CanPickup`** (`01-extensibility.md` d.9): arguments, who fires it. Does not block P3.
11. **In-game risks** of `notes/08` §7 (ARC9 instance tables, TFA client restore, bot viewmodel on TFA, `GetInfoNum`
    on bots) are checkpoint items of CP-3, not design questions.
