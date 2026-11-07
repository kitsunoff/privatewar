# 12 - Per-player weapon stat modifiers (perks and wildcards)

Read-only research into whether perks such as Sleight of Hand, Fast Hands, Quickdraw or Steady Aim can scale
weapon stats per player on ARC9, MW Base and TFA Base, plus plain SWEPs. It also covers how these
multipliers reach the owner's client so prediction does not desync. Nothing was run in game.

Evidence labels:

- **[src]** read in the source at the cited `file:line`;
- **[wiki]** GMod wiki;
- **[inference]** follows from the cited code, but the runtime behaviour was not observed;
- **[unverified]** not found, or depends on engine behaviour outside these repos.

Path prefixes are the same as in `08-weapon-adapters.md` §0: `A/` = ARC9 `lua/weapons/arc9_base/` (commit `f9bbe034`),
`M/` = MW `lua/weapons/mg_base/`, `mw:` = MW Base addon root, `T/` = TFA `lua/weapons/tfa_gun_base/`, `tfa:` = TFA Base addon root.

Multiplier convention used below: `mods.x = 0.8` means **"the time or amount becomes 80 %"**. For example, a
reload that takes 80 % of its normal time, or 85 % of the recoil.

## 1. TL;DR

| Stat (`mods` key) | ARC9 | MW Base | TFA | Plain SWEP / HL2 |
| --- | --- | --- | --- | --- |
| `reload_time` | **Yes**: stat `ReloadTime` (time multiplier). Anim rate and timers scale together. Low risk | **Yes**: `Animations.Reload*.Fps /= m` in `OnBuildCustomizedGun`. Length and rate both derive from `Fps`. Low risk | **Yes**: `TFA_AnimationRate` for reload ACTs, plus `TFA_GetStat("ProceduralReloadTime")`. Medium risk (anim classification) | No (needs per-class override of `Reload`). Exclude |
| `draw_time` / `holster_time` | **Yes**: stat `DeployTime`, used for draw, ready and holster. Low risk | **Yes**: `Draw`, `Equip`, `Holster` `Fps`. Low risk | **Yes**: `TFA_AnimationRate` for draw and holster ACTs. Medium risk | Partial: `Weapon:SetDeploySpeed` [wiki]. Must match on both realms. Draw only |
| `ads_time` | **Yes**: stat `AimDownSightsTime`. Low risk | **Yes**: `Ads_In` and `Ads_Out` `Fps`. Low risk | **Yes**: `TFA_GetStat("IronSightTime")`. Low risk | No |
| `sprint_to_fire` | **Yes**: stat `SprintToFireTime`. Low risk | **Yes**: `Sprint_Out` and `Super_Sprint_Out` `Fps`. Low risk | **No**: the sprint-out speed is the hardcoded constant `7.5`. Exclude | No |
| `recoil` | **Yes**: stat `Recoil`. View recoil is **client-only**, so the owner's client must know the multiplier. Medium risk | **Yes**: `Recoil.Vertical` and `Recoil.Horizontal` {min,max}. Low risk | Partial: `Primary.KickUp`, `KickDown`, `KickHorizontal` through `TFA_GetStat`. `RecoilLUT` weapons need more keys. Medium risk | No |
| `spread` | **Yes**: stat `Spread`. Low risk | **Yes**: `Cone.Hip`, `Cone.Ads`, `Cone.Increase`. Low risk | **Yes**: `Primary.Spread` / `Primary.Accuracy` / `Primary.IronAccuracy`. Low risk | No |
| `mag_size` | Technically possible (`ClipSizeHook`). The ammo flow through `PostModify` is risky. Exclude | Technically possible (`Primary.ClipSize`). The build clamps the clip. Medium risk. Exclude | Risky: the engine-side max clip versus `GetStatL`. Exclude | No |
| `damage` | Possible (`DamageMax`/`DamageMin`), but **the core should do it** in its damage hook, the same way for every base | same | same | **Core only** |

Main findings:

1. **All three bases have a shared (predicted) per-instance path.** ARC9 uses per-instance affector functions,
   MW uses the global hook `OnBuildCustomizedGun`, and TFA uses the global hooks `TFA_GetStat` and `TFA_AnimationRate`.
   None of them needs edits to the base for reload, draw/holster, ADS, recoil or spread.
2. **The ARC9 global hook `ARC9_<Stat>Hook` alone is not reliable.** `getValue` caches
   "this stat has no affectors" and then **returns early without running hooks** [src] (details in §2.2). Use
   per-instance `<Stat>Hook` fields instead.
3. **Replication pattern:** NW2 floats on the **player** (perks belong to the player), read by shared code
   through `wep:GetOwner()`. Add a revision counter so each realm knows when to refresh base caches.
   ARC9 needs `InvalidateCache`, MW needs `BuildCustomizedGun`, TFA needs nothing.

## 2. ARC9

### 2.1 Relevant stats and how they are used

| Our key | ARC9 stat | Semantics | Read at |
| --- | --- | --- | --- |
| `reload_time` | `ReloadTime` (base field `= 1`, `A/shared.lua:607`) | time multiplier passed to `PlayAnimation` | `A/sh_reload.lua:119,423,465` [src] |
| `draw_time` | `DeployTime` (`= 1`, `A/shared.lua:608`) | time multiplier for `draw`, `ready` and `holster` | `A/sh_deploy.lua:245,248,299,308,310` (`isstatic = true`) [src] |
| `ads_time` | `AimDownSightsTime` (`= 0.25`, `A/shared.lua:600`) | seconds; also used as an anim multiplier ("legacy") | `A/sh_sights.lua:38,70,303` [src] |
| `sprint_to_fire` | `SprintToFireTime` (`= 0.25`, `A/shared.lua:601`) | seconds | `A/sh_sprint.lua:4` (`isstatic = true`), `:8`, `:144` [src] |
| `recoil` | `Recoil` (`= 1`, `A/shared.lua:445`) | multiplier on `RecoilUp`/`RecoilSide` per shot | `A/sh_recoil.lua:88-92` [src] |
| `spread` | `Spread` (`A/shared.lua:571`) | radians-ish cone | `GetProcessedValue("Spread")` [src] |

- `PlayAnimation(anim, mult)` sets the viewmodel playback rate to `duration / time / mult` and scales the
  `EjectAt`, `DropMagAt` and `DumpAmmo` timers by the same `mult` [src `A/sh_anim.lua:88-125`].
- The reload refill is scheduled at `t * minprogress`, where `t` is the scaled length that `PlayAnimation` returns
  [src `A/sh_reload.lua:121-128`].
- **So anim speed and gameplay timing cannot drift apart in ARC9.** This is the safest base for these perks.

### 2.2 Mechanism (question 1)

Modifier layers in `getValue` (`A/sh_0_stats.lua:303-450`) [src]:

1. `X` from each affector (by priority);
2. `XOverride`;
3. `XAdd`;
4. `XMult`;
5. `XHook`: the functions `elem[X.."Hook"](wep, value)` from every affector, then `hook.Run("ARC9_"..X.."Hook", wep, value)` (`runHook`, `:245-299`).

**Affector 1 is `self:GetTable()`**, the weapon instance's own Lua table (`:162`) [src]. Fields set on the
instance therefore act as an attachment. The other affectors are attachments, the global `arc9_modifiers` convar
(`:190`), the firemode table and elements.

Options, from best to worst:

1. **Per-instance hook field (recommended).** Set `wep.ReloadTimeHook = function(w, v) return v * mult(w, "reload_time") end`
   on the instance, and likewise for `DeployTimeHook`, `AimDownSightsTimeHook`, `SprintToFireTimeHook`, `RecoilHook` and `SpreadHook`.
   - The function is found as an affector, so `runHook` returns `any = true` and the stat is never marked "no affectors".
   - The hook also runs on cache hits (`:336`), because the cache stores the pre-hook value (`:447`). So a change in the
     multiplier is seen without invalidation by every **non-static** read.
   - **Static reads** (`isstatic = true`: `DeployTime`, `SprintToFireTime` at `A/sh_sprint.lua:4`) go through
     `PV_CacheLong` (`:468`, `:668`). Those need `InvalidateCache()` after a change.
   - Collision risk: a weapon pack that itself defines `SWEP.ReloadTimeHook` would be shadowed. Wrap the class value:
     `local orig = weapons.GetStored(class).ReloadTimeHook`, then call it first [inference].
2. **Per-instance `XMult` field** (`wep.ReloadTimeMult = m`).
   - This also works, because it is read from affector 1 (`:413`).
   - But packs do define `XMult` fields on the SWEP, so we would need to multiply by the class value.
   - It is also cached in `StatCache`, so every change needs `InvalidateCache`.
3. **Global hook `ARC9_ReloadTimeHook(wep, value)` only. Not reliable** [src]:
   - `runHook` sets `any = true` only for affector **functions**, not for the global `hook.Run` (`:283-296`).
   - If no attachment touches the stat, `HasNoAffectors["ReloadTime"] = true` is cached (`:431`).
   - The next `getValue` returns at `:316` **before any hook runs**. The global hook applies only on the first read
     after each invalidation, or when some attachment happens to modify the stat.
   - Nothing in ARC9 itself registers `hook.Add("ARC9_<X>Hook")` (grep is empty), so this path is untested upstream.
4. `arc9_mod_*` convars (`quickmodifiers`, `:34-49`) are global and `replicated`. They cannot be per player.
   They only cover damage, spread, recoil, ADS time, sprint time, RPM and a few others.

Realm: `getValue`, `GetProcessedValue` and `runHook` are in shared files and run in the owner's prediction
(reload, deploy, sights and sprint are all shared). The hook function must exist on **both** realms [inference].

### 2.3 Caching to invalidate (question 2)

- `wep:InvalidateCache()` only sets a flag. `DoInvalidateCache()` runs on that realm's next `Think`
  (`A/sh_0_stats.lua:80-110`, `A/sh_think.lua:191`) [src]. It clears `StatCache`, `PV_Cache`, `PV_CacheLong`, `HookCache` and `HasNoAffectors`.
- It must run on **both** realms. ARC9 forwards it to the client only in singleplayer (`:80-86`).
  In multiplayer the client must call it itself, for example when it sees a new modifier revision.
- ARC9 already invalidates on `Deploy` (`A/sh_deploy.lua:12`) and `Initialize` (`A/sh_init.lua:3,219`) [src].
  A multiplier that is in place before the weapon is drawn is therefore picked up automatically.
- `HookCache[val]` caches the **list of hook functions**. Install the instance fields **before** the first stat read,
  or call `DoInvalidateCache()` after installing them [src `:247-280`, inference].

### 2.4 Risks

- **Recoil is client-side for view kick** (`AS/sh_move.lua:262-345`, see 08 §2.5). If the client lacks the
  multiplier, the owner sees full recoil while the server's `RecoilAmount`-driven spread uses the reduced value. Prediction does not
  break (the NW vars are server-authoritative), but the perk "feels" absent [inference]. Bots get no view recoil at all, so for them the
  perk only affects spread through `RecoilAmount`.
- `PlayAnimation` clamps the playback rate to 12 (`A/sh_anim.lua:96`). Irrelevant for multipliers of 0.5 or more.
- **Instance install on the client:** the server's instance fields are not networked. The client must install the same functions
  when it creates the weapon entity [inference]. See §6.

## 3. MW Base (`mg_base`)

### 3.1 How stats are built

- `BuildCustomizedGun()` (`M/modules/shared/sh_customization.lua:233-512`) [src]:
  - It resets the instance to class defaults: `DeepObjectCopy(weapons.Get(class), self)` (`:235`) and `Animations = table.Copy(stored.Animations)` (`:257`).
  - It runs `attachment:Stats(stats)` for every attachment (`:343`).
  - It copies the result back, runs `PostProcess`, clamps the clip (`:422-432`) and re-applies the firemode (`:500`).
  - Finally it calls **`hook.Call("OnBuildCustomizedGun", nil, self)`** (`:508`). The author's comment: "this hook passes the swep
    object after stats are built, allowing for custom 3rd party stat scaling".
- It is **shared** and runs on both realms:
  - in `Initialize` (`M/shared.lua:482`);
  - on every `Attach` (`sh_customization.lua:46`), which runs on the client when the `mg_attachment` entity arrives;
  - on `ApplyFiremode` (`sh_firemode_behaviour.lua:23`, under `IsFirstTimePredicted`);
  - on `OnReloaded` (`M/shared.lua:738`) [src].
- **It is idempotent:** each build starts from class defaults, so applying, removing and re-applying is just a rebuild with
  different multipliers [src `:235,257`]. This answers the "removable / re-appliable" requirement.

### 3.2 Animation timing is consistent

- Gameplay length = `Length / (Fps / 30)` (`M/shared.lua:679-691`).
- The viewmodel playback rate = `Fps / 30` (`mw:lua/entities/mg_viewmodel/shared.lua:152`) [src].
- Reload, deploy, holster, sprint-out and ADS all derive their timers from `GetAnimLength`:
  - `task_reload.lua` sets `NextPrimaryFire` and `NextSecondaryFire` (mag insert) from it;
  - `task_deploy.lua:27`, `task_holster.lua:14` and `task_sprint_out.lua:20,23` use it;
  - ADS speed is `1 / GetAnimLength("Ads_In")` (`sh_aim_behaviour.lua:38,45`) [src].
- So `Fps /= m` scales anim and timing together.

### 3.3 Fields to scale in `OnBuildCustomizedGun`

| Key | Fields (guard every one with `if anim then`) |
| --- | --- |
| `reload_time` | `Animations[k].Fps /= m` for every key matching `^reload` (case-insensitive): `Reload`, `Reload_Empty`, `Reload_Start`, `Reload_Loop`, `Reload_Loop_Empty`, `Reload_End`… |
| `draw_time` | `Draw`, `Equip` (first draw, `task_deploy.lua:16-18`), `Holster` |
| `ads_time` | `Ads_In`, `Ads_Out` |
| `sprint_to_fire` | `Sprint_Out`, `Super_Sprint_Out` |
| `recoil` | `Recoil.Vertical[1..2]`, `Recoil.Horizontal[1..2]` `*= m` |
| `spread` | `Cone.Hip`, `Cone.Ads`, `Cone.TacStance`, `Cone.Increase` `*= m` |

The key names come from `SWEP.StatDefinitions` (`M/modules/shared/sh_stats.lua`) [src]. Packs may name extra
animations (for example `Reload_Fast`). Matching by prefix covers them [inference].

### 3.4 Replication and risks

- The hook runs on both realms, but **each realm reads the multipliers at its own build time**. If the client built the gun
  before it knew the owner's multipliers, client and server `Fps` differ. Reload or deploy then mispredicts: the client predicts a longer reload and is
  corrected by the server's `NextPrimaryFire` [inference].
- Client `Initialize` can run before `GetOwner()` is valid [unverified]. Mitigation: the hook marks
  `wep.codModsRev`. A client-side check (§6) calls `wep:BuildCustomizedGun()` again when the owner's revision differs.
- Side effects of a rebuild [src `:235-505`]:
  - it resets `AimMode` and `TacStance`;
  - it sets the hold type to `camera` for one tick;
  - it clamps `Clip1` (server returns the excess to reserve).
  - Rebuild only at spawn or loadout change, never mid-reload [inference].
- Bots: the server rebuild is enough, because there is no client.
- `hook.Call(name, nil, self)` passes `nil` as the gamemode table, so **only `hook.Add` hooks run**, not a `GM:OnBuildCustomizedGun` method [src `:508`].

## 4. TFA Base

### 4.1 Mechanism

- **`TFA_GetStat(wep, statPath, value)`** (shared, documented in `tfa:lua/tfa/documentation/tfa_hooks_custom.lua:117-126`):
  - It is called by `GetStatL`/`GetStat` on every read: after the cache hit (`T/common/stat.lua:341`), with no valid owner (`:355`),
    and on a fresh compute (`:382`) [src].
  - **The result is never cached**, so no invalidation is needed. TFA itself uses it the same way
    (`tfa:lua/tfa/modules/tfa_commands.lua:306`).
  - Stat keys: `IronSightTime` (ADS; `T/common/calc.lua:112`, `T/shared.lua:1184`), `Primary.KickUp`, `Primary.KickDown`, `Primary.KickHorizontal`
    (`T/common/bullet.lua:376-377`), `Primary.Spread`/`Primary.Accuracy` (`calc.lua:204`), `Primary.IronAccuracy` (`:226,229`),
    `ProceduralReloadTime` (`T/shared.lua:1967,2067`), `ProceduralHolsterTime` (`:947`).
- **`TFA_AnimationRate(wep, ani, rate)`** (shared, `T/common/anims.lua:375`, docs `:579-588`) [src]:
  - `GetAnimationRate` multiplies the viewmodel playback rate in `SendViewModelAnim` (`:394-396`) and `SendViewModelSeq` (`:501-503`).
  - It also **divides** `GetActivityLength` (`T/common/utils.lua:193`), which drives `SetStatusEnd` for reload, draw, holster and pump
    (`T/shared.lua:876,947,1959-1969,2059-2069,2097,2108-2112`).
  - So timing and anim scale together, provided the hook returns the same factor for the same `ani` in both calls.

### 4.2 Risks

- **`ani` is ambiguous.** `GetActivityLength(tanim, status, ttype)` calls `GetAnimationRate(tanim)` **without** the type
  (`utils.lua:193`), while `SendViewModelSeq` passes `ANIMATION_SEQ` (`anims.lua:501`) [src].
  - For sequence-type animations the hook receives a sequence index in both calls, so the value is the same. But the hook cannot
    tell from the argument alone whether it is an `ACT_*` or a sequence index.
  - Classification: first check a set of ACTs (`ACT_VM_RELOAD`, `ACT_VM_RELOAD_EMPTY`, `ACT_VM_RELOAD_SILENCED`,
    `ACT_SHOTGUN_RELOAD_START`, `ACT_SHOTGUN_RELOAD_FINISH`, `ACT_VM_DRAW*`, `ACT_VM_HOLSTER*`). Then fall back to
    `wep.OwnerViewModel:GetSequenceActivity(ani)` and the sequence name (`reload`, `draw`, `holster`).
  - A collision between a sequence index and an ACT number is possible in theory [inference]. Verify in game.
- Do **not** classify by `wep:GetStatus()`. The reload anim is sent in `ChooseReloadAnim` **before**
  `SetStatus(STATUS_RELOADING)` (`T/shared.lua:1962-1964`), so anim and length would get different factors [src].
- Procedural-reload weapons (`IsProceduralReloadBased`) ignore the anim rate. Scale `ProceduralReloadTime` through `TFA_GetStat` as well.
- `LoopedReloadInsertTime` is divided by `GetAnimationRate(ACT_VM_RELOAD)` (`T/shared.lua:2111`), so it stays consistent [src].
- `GetAnimationRate` returns 1 without a valid viewmodel (`anims.lua:348`). Bots need a server viewmodel (08 §4.6, [unverified]).
- **Sprint-to-fire is not feasible.** Sprint progress uses the constant `7.5` (`T/common/calc.lua:76-78`), and fire is blocked
  while the progress is at least `0.1` (`T/shared.lua:1528,1799`) [src]. There is no stat or hook.
- **Recoil LUT weapons** (`HasRecoilLUT`, `bullet.lua:397-415`) also read `Primary.RecoilLUT_ViewPunchMult` and `Primary.RecoilLUT_AnglePunchMult`.
  Scale those too [src]. The LUT angles themselves are not scaled [inference].
- Performance: `TFA_GetStat` fires on every `GetStatL` (hundreds per frame). The hook must return early with a table lookup on `statPath`.

## 5. Plain SWEPs and HL2 weapons

- `Weapon:SetDeploySpeed(speed)` [wiki]: "Sets the weapon deploy speed. This value needs to match on client and server."
  The minimum is 0.1. This is the only generic per-instance knob, and it covers the **draw** speed only. The client side must be set from replicated
  state [inference].
- Reload in `weapon_base` uses `DefaultReload(ACT_VM_RELOAD)`. The engine derives completion from `NextPrimaryFire` and the sequence
  duration [unverified, Source SDK behaviour].
  - Scaling it would need a per-class override of `SWEP:Reload`: call `vm:SetPlaybackRate(1/m)` and `SetNextPrimaryFire(CurTime() + dur*m)`.
  - Engine HL2 weapons (`weapon_smg1` and similar) are C++ and cannot be changed this way.
- Recoil and spread are arbitrary per-SWEP Lua fields (`Primary.Recoil`, `Primary.Cone`, or none). There is no common contract.
- Verdict: the default adapter implements **only** `draw_time` through `SetDeploySpeed`, and ignores the rest.

## 6. Proposed adapter method

### 6.1 Contract

```lua
---@class COD.StatMods                -- multipliers; absent key = 1.0
---@field reload_time number|nil      -- time multiplier (0.8 = 20 % faster)
---@field draw_time number|nil        -- draw and holster time multiplier
---@field ads_time number|nil
---@field sprint_to_fire number|nil
---@field recoil number|nil
---@field spread number|nil

---@realm shared  install once per weapon instance on BOTH realms; idempotent; default: no-op
---@param wep Weapon
function Adapter.InstallStatMods(wep) end

---@realm shared  called after the owner's modifier revision changed; default: no-op
---@param wep Weapon
function Adapter.RefreshStatMods(wep) end

---@realm shared  which keys this base honours, for UI and perk descriptions; default: {}
---@return table<string, boolean>
function Adapter.SupportedStatMods() end
```

This differs from the planned `ApplyStatMods(wep, mods)`. A server-only "apply" call cannot reach the client's
predicted code on any of the three bases. The **values** must live in replicated state, and the adapter only wires the
base so that it reads them on both realms.

### 6.2 Replication: one core helper, one source of truth

```lua
-- shared core
COD.STAT_KEYS = { "reload_time", "draw_time", "ads_time", "sprint_to_fire", "recoil", "spread" }

function COD.GetStatMod(ply, key)            -- the only reader used by every adapter
    if not IsValid(ply) or not ply:IsPlayer() then return 1 end
    return ply:GetNW2Float("cod_sm_" .. key, 1)
end

if SERVER then
    function COD.SetStatMods(ply, mods)      -- at spawn and on loadout change
        for _, k in ipairs(COD.STAT_KEYS) do
            ply:SetNW2Float("cod_sm_" .. k, mods[k] or 1)
        end
        ply:SetNW2Int("cod_sm_rev", ply:GetNW2Int("cod_sm_rev", 0) + 1)  -- written last
    end
end

-- shared: refresh weapons whose owner's revision moved (both realms, cheap check)
hook.Add("Think", "COD_StatModsRefresh", function()
    local plys = CLIENT and { LocalPlayer() } or player.GetAll()
    for _, ply in ipairs(plys) do
        if not IsValid(ply) then continue end
        local rev = ply:GetNW2Int("cod_sm_rev", 0)
        for _, wep in ipairs(ply:GetWeapons()) do
            if wep.codSmRev ~= rev then
                local a = COD.AdapterFor(wep)
                a.InstallStatMods(wep)
                a.RefreshStatMods(wep)
                wep.codSmRev = rev
            end
        end
    end
end)
```

Notes:

1. The values sit on the **player**, not on the weapon. A weapon picked up by another player reads its new owner's perks
   automatically. ARC9 invalidates on `Deploy` anyway (§2.3).
2. NW2 on the player reaches the local client before or with its weapons in normal play [inference]. The revision check
   covers the "client built the gun first" race on MW (§3.4).
3. Other clients need only `recoil`/`spread`/`ads_time` for visuals, which are irrelevant. The client loop therefore checks only `LocalPlayer()`.
4. Removal = `COD.SetStatMods(ply, {})`. The revision bump triggers a refresh, so no per-base "undo" is needed.

### 6.3 Per-base sketches

ARC9 (instance hook fields; §2.2 option 1):

```lua
local MAP = { ReloadTime = "reload_time", DeployTime = "draw_time", AimDownSightsTime = "ads_time",
              SprintToFireTime = "sprint_to_fire", Recoil = "recoil", Spread = "spread" }

function ARC9Adapter.InstallStatMods(wep)
    if wep.codSmInstalled then return end
    local stored = weapons.GetStored(wep:GetClass()) or {}
    for stat, key in pairs(MAP) do
        local orig = stored[stat .. "Hook"]              -- keep a pack-defined hook working
        wep[stat .. "Hook"] = function(w, v)
            if orig then v = orig(w, v) or v end
            if not isnumber(v) then return v end
            return v * COD.GetStatMod(w:GetOwner(), key)
        end
    end
    wep.codSmInstalled = true
end

function ARC9Adapter.RefreshStatMods(wep)
    wep:DoInvalidateCache()                              -- clears PV_CacheLong, HookCache, HasNoAffectors
end
```

MW Base (one global hook; the install is a no-op):

```lua
hook.Add("OnBuildCustomizedGun", "COD_StatMods", function(wep)
    local ply = wep:GetOwner()
    local function fps(pattern, key)
        local m = COD.GetStatMod(ply, key)
        if m == 1 then return end
        for name, a in pairs(wep.Animations or {}) do
            if istable(a) and a.Fps and string.find(string.lower(name), pattern) then a.Fps = a.Fps / m end
        end
    end
    fps("^reload", "reload_time")
    fps("^draw$", "draw_time"); fps("^equip$", "draw_time"); fps("^holster$", "draw_time")
    fps("^ads_", "ads_time")
    fps("sprint_out$", "sprint_to_fire")
    -- recoil: Recoil.Vertical/Horizontal {min,max}; spread: Cone.Hip/Ads/TacStance/Increase
end)

function MWAdapter.RefreshStatMods(wep)
    if not wep:HasFlag("Reloading") then wep:BuildCustomizedGun() end   -- else retry next tick
end
```

TFA (two global hooks; nothing to refresh):

```lua
local STAT = { ["IronSightTime"] = "ads_time", ["ProceduralReloadTime"] = "reload_time",
               ["ProceduralHolsterTime"] = "draw_time",
               ["Primary.KickUp"] = "recoil", ["Primary.KickDown"] = "recoil", ["Primary.KickHorizontal"] = "recoil",
               ["Primary.RecoilLUT_ViewPunchMult"] = "recoil", ["Primary.RecoilLUT_AnglePunchMult"] = "recoil",
               ["Primary.Spread"] = "spread", ["Primary.Accuracy"] = "spread", ["Primary.IronAccuracy"] = "spread" }

hook.Add("TFA_GetStat", "COD_StatMods", function(wep, stat, v)
    local key = STAT[stat]
    if not key or not isnumber(v) then return end
    local m = COD.GetStatMod(wep:GetOwner(), key)
    if m ~= 1 then return v * m end
end)

hook.Add("TFA_AnimationRate", "COD_StatMods", function(wep, ani, rate)
    local key = COD.TFAClassifyAnim(wep, ani)            -- ACT set first, then sequence activity/name
    if not key then return end
    local m = COD.GetStatMod(wep:GetOwner(), key)
    if m ~= 1 then return rate / m end                    -- time x m  =>  rate / m
end)
```

Plain SWEP: `InstallStatMods` = `wep:SetDeploySpeed(base / COD.GetStatMod(owner, "draw_time"))` on both realms
(the base value is `wep.m_WeaponDeploySpeed` or the `sv_defaultdeployspeed` convar [unverified]).

## 7. Stats to exclude from the MVP

1. **`sprint_to_fire` on TFA:** a hardcoded constant (§4.2). Advertise the perk as "not on TFA weapons", or drop it.
2. **`mag_size` everywhere:** ARC9 unloads and reloads through `PostModify` (08 §2.3), MW clamps in the build, and TFA's
   `GetStatL` value can disagree with the engine-side max clip. In CoD it is an attachment anyway, so leave it to `Apply`.
3. **`damage` in the adapters:** do it once in the core damage hook (`EntityTakeDamage`/`ScalePlayerDamage` with the attacker's
   perks). That makes it base-agnostic and avoids double scaling with ARC9 `arc9_mod_bodydamagecancel` (08 §6.1).
4. **Plain SWEP/HL2 reload, recoil and spread:** no common contract (§5).
5. **RPM** (Double Time style): possible on all three bases, but it changes the bot `releaseBetweenShots` timing and
   balance. Leave it for later.

## 8. To verify in game

1. ARC9: with only `hook.Add("ARC9_ReloadTimeHook")`, a second reload is **not** sped up (confirms §2.2 option 3).
   With the instance `ReloadTimeHook`, every reload is.
2. ARC9: the client-side instance fields survive the weapon leaving and re-entering PVS, and a weapon drop and pickup
   (`codSmRev` reset is expected).
3. ARC9: view recoil on the owner's screen shrinks with `recoil = 0.5`, and there is no prediction jitter on `RecoilAmount`.
4. MW: with `reload_time = 0.5` there is no reload rubber-banding on a 150 ms ping client (`net_fakelag 150`) immediately after spawn.
   This checks the client-rebuild race in §3.4.
5. MW: `BuildCustomizedGun` on the client mid-life does not reset visible attachments or camo.
6. TFA: the reload anim and the `StatusEnd` stay in sync for both ACT-based and `ANIMATION_SEQ`-based weapons (`TFA.Enum.ANIMATION_SEQ`).
   Log `ani` in the hook to confirm the classification.
7. TFA bots: `GetAnimationRate` gets a valid server viewmodel (otherwise the perk silently does nothing for bots).
8. `Weapon:SetDeploySpeed` on a plain SWEP: set on both realms, and check that it does not reset on `Deploy`.
9. Performance: `TFA_GetStat` hook cost with 16 players and 16 bots (`FrameTime` budget).

## 9. Sources

- ARC9 `f9bbe034`: `A/sh_0_stats.lua`, `A/sh_anim.lua`, `A/sh_reload.lua`, `A/sh_deploy.lua`, `A/sh_sights.lua`, `A/sh_sprint.lua`, `A/sh_recoil.lua`, `A/shared.lua`.
- MW Base (Workshop 2459720887): `M/modules/shared/sh_customization.lua`, `M/shared.lua`, `M/modules/shared/sh_stats.lua`, `M/modules/shared/tasks/*.lua`,
  `mw:lua/entities/mg_viewmodel/shared.lua`.
- TFA (Workshop 2840031720): `T/common/stat.lua`, `T/common/anims.lua`, `T/common/utils.lua`, `T/common/calc.lua`, `T/common/bullet.lua`, `T/shared.lua`,
  `tfa:lua/tfa/modules/tfa_commands.lua`, `tfa:lua/tfa/documentation/tfa_hooks_custom.lua`.
- GMod wiki: <https://wiki.facepunch.com/gmod/Weapon:SetDeploySpeed>.
