# Stim equipment: healing stim and speed stim

Status: `in-progress`

Recorded: 2026-11-21

Implementation started 2026-11-22 on `feat/stim-equipment` from `226330a`. Scope is the approved three stims,
equipment input, bot and HUD support, and optional animation integration. Gates and human acceptance are pending.

Approval (2026-11-22): the user approved every design change proposed in this record and the recommended
default of every open question, except where an answer below says otherwise. This approves the design
direction for implementation; push, PR, merge to `main` and publication still need separate approval.

Related: the items' `Unlock` field must stay valid under [programmatic unlocks](unlock-entitlements.md); stim usage
  may later become a [weekly challenge](weekly-challenges.md) event (not in this scope).

Research: [Arctic's Combat Stims research](../../notes/30-arctic-stims-research.md). This record is tracking, not
authorization: it does not authorize implementation, design or contract changes, Steam Deck access, redistribution or
publication. Every number below is a **proposed default, user to confirm**. Paths are relative to the repository root;
`P = addons/privatewar/lua/privatewar/`, `T = addons/privatewar/lua/tests/privatewar/`. Paths were checked against
the tree at `cf7c4ed`.

## 1. User request

- [ ] Record the request (translated from the maintainer's message): integrate the GMod addon "Arctic stims" and add
  to Private War equipment a **healing stim shot** and a **stim shot that increases movement speed**. Like other
  equipment, it is bound to a key (the existing equipment slot keys). "Shots for movement speed can be two."
- [ ] Record the interpretation used by this plan: the speed stim has **two charges per life** (`Count = 2`). The
  other reading (two different speed stim variants) is open question 1.
- [ ] Record the follow-up request (2026-11-21): "several medshots, not only heal and move speed; maybe an armor
  heal too." The system is therefore **effect-driven** (section 3.6): a new stim is one item file plus, only when it
  needs a new kind of effect, one effect entry. This slice ships three items: `stim_heal`, `stim_speed`,
  `stim_armor`.
- [ ] Record the identified addon: "[GCAL] Arctic's Combat Stims", Workshop `2370028261`, by Arctic; it requires GCAL
  (`3727245204`); it has no licence and no public source (research section 2).

## 2. Prerequisites

- [ ] Obtain explicit user authorization to implement, plus approval of every item in section 14 (design changes)
  and section 15 (contract changes) before writing code.
- [ ] Work on a feature branch from current `main` (for example `feat/stim-equipment`), never on `main`.
- [ ] Core stims need **no** third-party content. Nothing from Arctic's addon or GCAL is vendored (research section 2:
  no licence; Valve and Turtle Rock assets). `THIRD_PARTY_NOTICES.md` does not change.
- [ ] For the optional integration only: the user installs on the Deck GCAL (`3727245204`) and Arctic's Combat Stims
  (`2370028261`). GMod mounts addons only at startup, so a first install needs a game restart.
- [x] Animation facts verified from the downloaded source on 2026-11-21 (research section 11): one animation
  `arc_vm_medshot_inject` (`VManip:PlayAnim`), variants differ only by gesture skin (heal 0, speed 1), effect timing
  1 s after start, `arc_medshot_replacevial` exists (archived, replicated, default 1). Re-check after a Workshop
  update: the addon was last updated in 2021.
- [ ] GLuaTest runner: core cases need no Workshop mounting. Integration cases that need GCAL and Arctic's addon are
  skipped with one log line when absent, never passed silently (the `T/integration_arc9.lua` pattern). No new
  Workshop collection entry is required.
- [ ] Lane assignment by the orchestrator (`TASKS.md`, "Lanes and ownership"): `loadout` owns `P/equipment/`,
  `P/modules/equipment/` and the new `P/modules/stims/`; the `player_overrides` change, `docs/api/*` and `TASKS.md`
  go through the orchestrator; `bots` owns `P/modules/bots_tactics/` and `P/bot_behaviors/`; `ui` owns `P/hud/`.
  The integration addon `addons/privatewar-stims/` is not a weapon-base integration; the orchestrator assigns it
  (proposal: `loadout`). At most three lane agents at once.

## 3. Item specs

Both items are ordinary weapon-less equipment items (`docs/api/equipment.md`: an item without `Weapon` is used through
`PW.Equipment.Use`). They are thin: `OnUse` calls the stims module; the effect rules live in `P/modules/stims/`.

### 3.1 Slot and category

- [ ] Both items use `Category = "tactical"` and therefore the existing `tactical` slot, key `4`, console command
  `pw_tactical`, gamepad d-pad left. Justification: no new slot, key, HUD row or loadout layout; matches CoD (the
  stim is a tactical); `design/05-loadout.md` d.11 slot declarations stay unchanged; Stockpile (+1 tactical,
  d.16) applies automatically. Cost: a player chooses flash **or** a stim. Alternative (a new slot) is open
  question 2.
- [ ] The default loadout (`P/modules/loadout/shared.lua:203`, `tactical = "flash"`) and the class presets in
  `P/classes/` keep `flash`. Open question 13.

### 3.2 `stim_heal`

- [ ] File `P/equipment/stim_heal.lua`, id `stim_heal`, enable ConVar `pw_equipment_stim_heal_enabled` (automatic).

| Field | Proposed value | Notes |
| --- | --- | --- |
| `Name` | `"Heal Stim"` | HUD shows `[4] HEAL STIM x1` |
| `Description` | `"Restores 60 health over 1.5 seconds. Cannot be used at full health."` | Shown by the loadout UI (`P/modules/loadout_ui/sh_editor.lua:210`); keep it in sync with the settings defaults |
| `Category` | `"tactical"` | Section 3.1 |
| `Count` | `1` | Uses per life, refilled on spawn |
| `Cost` | `1` | Pick X |
| `Unlock` | `1` | Open question 8 |
| `Weapon` | not set | Weapon-less: the key uses it directly (section 5) |
| `Amount`, `Time` | not set | Optional item overrides of `stims.heal_amount` / `stims.heal_time` (section 3.6) |
| `Sound` | `"items/smallmedkit1.wav"` | Stock HL2 sound; existence is a mandatory test |
| `OnUse(self, owner)` | the item's own logic (section 3.6); `false` when `PW.Stims` is absent | `false` keeps the count and does not start the cooldown |

- [ ] Gameplay (proposed defaults, user to confirm):

| Rule | Proposed default |
| --- | --- |
| Use time (injection delay before the effect starts) | 0.4 s (`stims.use_time`) |
| Heal | 60 health total (`stims.heal_amount`) over 1.5 s (`stims.heal_time`), in ticks of 0.25 s: 6 ticks of 10. `heal_time = 0` heals at once |
| Cap | Never above `owner:GetMaxHealth()` (respects role overrides such as Infection's 400) |
| Refusal (count kept) | Health already at or above max; a heal of this player already pending or running; module disabled; not `LIVE`; dead |
| Damage while healing | Does not interrupt |
| Death, disconnect, round end, match end, item or module disabled | Pending injection and remaining ticks are cancelled; health already given stays |
| Cooldown | The equipment module's per-slot `Cooldown` (0.75 s); no extra cooldown |
| Sprint, reload, ADS | Allowed; no weapon switch and no weapon lock in this slice (open question 5) |

### 3.3 `stim_speed`

- [ ] File `P/equipment/stim_speed.lua`, id `stim_speed`, enable ConVar `pw_equipment_stim_speed_enabled`.

| Field | Proposed value | Notes |
| --- | --- | --- |
| `Name` | `"Speed Stim"` | HUD shows `[4] SPEED STIM x2` |
| `Description` | `"Walk and run speed +20% for 6 seconds. Two per life."` | Keep in sync with settings defaults |
| `Category` | `"tactical"` | Section 3.1 |
| `Count` | `2` | Open question 1 |
| `Cost` | `1` | Pick X |
| `Unlock` | `1` | Open question 8 |
| `Weapon` | not set | Weapon-less |
| `Mult`, `Time` | not set | Optional item overrides of `stims.speed_mult` / `stims.speed_time` (section 3.6) |
| `Sound` | `"items/battery_pickup.wav"` | Stock HL2 sound; existence is a mandatory test |
| `OnUse(self, owner)` | the item's own logic (section 3.6); `OnUnequip` removes the move source | |

- [ ] Gameplay (proposed defaults, user to confirm):

| Rule | Proposed default |
| --- | --- |
| Use time | 0.4 s (`stims.use_time`) |
| Effect | Walk and run speed multiplied by 1.20 (`stims.speed_mult`) for 6 s (`stims.speed_time`), counted from the end of the use time |
| Composition | Multiplies with perks (Fleet Foot 1.10), wildcards, mode stats, role overrides (Infection 1.15) and the weapon base's own speed (section 4); Fleet Foot plus stim gives 1.32 of the ordinary baseline |
| Stacking | **Refuse** while a speed effect is active or pending (`OnUse` returns `false`, the charge is kept). Alternatives `refresh` and `extend` are open question 4 |
| Not affected | Jump power, crouch speed, slide, ladder speed (same boundary as Fleet Foot, `design/05-loadout.md` d.16) |
| Expiry | The multiplier is removed and speeds are refreshed relative to the ordinary baseline, never compounded |
| Death, disconnect, round end, match end, item or module disabled | Effect removed at once, speeds refreshed |
| Cooldown, sprint, reload, ADS | As the heal stim |

### 3.3a `stim_armor`

- [ ] File `P/equipment/stim_armor.lua`, id `stim_armor`, enable ConVar `pw_equipment_stim_armor_enabled`.
- [ ] Fact check (2026-11-21): armor is displayed (`design/09-hud.md`: three 50-point segments, 150 total;
  `P/hud/vitals.lua`) but **no code grants armor today** (`SetArmor` is not called outside tests). This stim is the
  first armor source, so it changes balance: the user confirms it (open question 14). Verify how damage is absorbed by
  armor in the current damage path (engine default or a PW `EntityTakeDamage`/`ScalePlayerDamage` rule) and record it
  in the step 1 test notes before choosing numbers.

| Field | Proposed value | Notes |
| --- | --- | --- |
| `Name` | `"Armor Stim"` | HUD shows `[4] ARMOR STIM x1` |
| `Description` | `"Adds one armor plate (50)."` | Keep in sync with settings |
| `Category` | `"tactical"` | Section 3.1 |
| `Count` | `1` | |
| `Cost` | `1` | |
| `Unlock` | `1` | Open question 8 |
| `Amount`, `Time`, `Max` | not set | Optional item overrides of `stims.armor_*` (section 3.6) |
| `Sound` | `"items/battery_pickup.wav"` | Stock HL2; existence is a mandatory test |
| `OnUse(self, owner)` | the item's own logic (section 3.6) | |

| Rule | Proposed default |
| --- | --- |
| Amount | **One plate**: 50 armor (`stims.armor_amount`, one HUD segment) over 1 s (`stims.armor_time`) in 0.25 s ticks; `0` time = instant (user answer 2026-11-22) |
| Cap | `stims.armor_max` = 150 (matches the HUD segments; `owner:SetMaxArmor` is not changed) |
| Refusal (count kept) | Armor already at or above the cap; an armor effect of this player pending or running |
| Death and other end paths | As the heal stim |

### 3.4 Presentation without Arctic's addon (built-in fallback)

- [ ] On a successful use the server plays the item's `Sound` on the owner (`EmitSound`, audible to others) and a
  small view punch (`ViewPunch`, about 2 degrees pitch). No first-person animation, no new model, no client effect
  besides the HUD (section 8).
- [ ] Both are done by one helper, `PW.Stims.Played(owner, item)` (section 3.6), which also sends the owner a one-byte
  message `pw_stim_used` (item index) so the client can fire the client notification `PW_StimInjected(itemId)`; the
  optional integration listens to it.

### 3.6 Item-owned logic (how to add more)

Decision taken with the user on 2026-11-21: **no effect registry and no `PW.Stims.Inject`.** Each stim item writes its
own behaviour in `OnUse`, because the equipment instance already provides everything a registry would duplicate
(verified at `cf7c4ed`):

| Need | Already provided by | Reference |
| --- | --- | --- |
| Per-player, per-life state | `self` is a `PW.Instance(def, ply)`; reads fall through to the item table (`__index`) | `gamemodes/privatewar/gamemode/core/sh_instance.lua:100-108` |
| Delays and ticks | `self:Timer(delay, reps, fn)`, any number per instance; `fn` receives the instance | `sh_instance.lua:68-77` |
| Cleanup on death, disconnect, match end, respawn, item disable | instance `Remove` runs `OnUnequip` and removes every timer and hook | `sh_instance.lua:80-94`; `P/modules/equipment/init.lua:72-80`, `:114`, `:201`, `:231-237` |
| Refusal keeps the charge | `OnUse` returning `false` keeps the count and the cooldown | `P/modules/equipment/init.lua:175` |

- [ ] Pattern every stim follows (schema; the exact code is the implementer's, tests in section 11 are binding):

```lua
function EQUIPMENT:OnUse(owner)
    if <refusal: at cap / self.busy / module missing> then return false end   -- charge kept
    self.busy = true
    PW.Stims.Played(owner, self)                       -- sound, view punch, pw_stim_used, HUD mark
    self:Timer(PW.Stims.Param(self, "UseTime", "stims.use_time"), 1, function(inst)
        -- effect: SetHealth / SetArmor ticks via inst:Timer, or PW.PlayerOverrides.MoveSource
    end)
    return true
end

function EQUIPMENT:OnUnequip(owner)                    -- every end path; must be idempotent
    -- undo anything not owned by a timer: MoveSource(owner, self.ClassName, nil), HUD mark cleared
end
```

- [ ] Shared helpers in `P/modules/stims/` (the whole module is settings plus these; no store, no registry):

```text
PW.Stims.Param(item, field: string, settingId: string) -> any
  item[field] when not nil (item override, inherited through Base), else PW.Setting(settingId).
PW.Stims._Ticks(amount: number, time: number, step: number) -> number[]   (pure, shared)
  Splits amount into ceil(time / step) ticks whose sum equals amount exactly; time <= 0 gives { amount }.
PW.Stims._Step(current: number, add: number, cap: number) -> number       (pure, shared)
  min(current + add, cap), never lowers a value already above cap.
PW.Stims.Played(owner, item) -> nil                                       (server)
  EmitSound(item.Sound) on the owner, ViewPunch about 2 degrees, net pw_stim_used (item index) to the owner.
PW.Stims.Mark(owner, key: "heal"|"armor"|"speed", untilTime: number) -> nil   (server)
  Writes NW2 float pw_stim_<key>_until on change only (0 = none); read by the HUD (section 8).
```

- [ ] Variants are new item files using `Base` (registry copies the base's fields, including `OnUse`; own fields win):

```lua
-- P/equipment/stim_speed_combat.lua (example only, not shipped in this slice)
EQUIPMENT.Base = "stim_speed"
EQUIPMENT.Name = "Combat Stim"
EQUIPMENT.Mult, EQUIPMENT.Time = 1.35, 4
```

- [ ] Speed source id is the item id (`self.ClassName`), so two different speed items would compose instead of
  overwriting; the same item refuses while `self.active` (open question 4).
- [ ] Candidate future stims (**not in this slice**): regeneration over time, damage resistance (needs a damage hook
  owner), faster reload or ADS (needs `PW.Stat` mid-life recomputation, which `design/05-loadout.md` d.8 currently
  forbids), anti-flash. Each is a new item file and needs its own approval.

### 3.5 Tuning surface

- [ ] Tuning is a `match`-scope `MODULE.Settings` table of the new module `stims` (`design/01-extensibility.md`
  d.17: settings are declared as data; Game Setup generates the UI; playlists may override). Full ids and defaults:

| Full id | Type | Default | Min | Max | Label |
| --- | --- | --- | --- | --- | --- |
| `stims.use_time` | float | 0.4 | 0 | 2 | `Stim injection time (s)` |
| `stims.heal_amount` | int | 60 | 10 | 200 | `Heal stim health` |
| `stims.heal_time` | float | 1.5 | 0 | 5 | `Heal stim duration (s)` |
| `stims.speed_mult` | float | 1.2 | 1 | 2 | `Speed stim multiplier` |
| `stims.speed_time` | float | 6 | 1 | 30 | `Speed stim duration (s)` |
| `stims.armor_amount` | int | 50 | 10 | 150 | `Armor stim armor` |
| `stims.armor_time` | float | 1 | 0 | 5 | `Armor stim duration (s)` |
| `stims.armor_max` | int | 150 | 50 | 255 | `Armor stim cap` |

- [ ] Do **not** create ad-hoc `pw_equipment_<id>_*` ConVars: they would bypass the d.17 settings schema. Item
  counts stay item data (`Count`), changed per life through `PW_EquipmentCount` / count sources as today. Open
  question 9 covers a user preference for host (`server`) scope instead.

## 4. Movement speed composition

Current owner (verified): `P/modules/player_overrides/init.lua:48-62` sets
`walk = baseline.walk * profile.walkSpeedMult * PW.Stat(ply, "move_speed", 1)` and the same for run, relative to an
ordinary baseline captured once per life; `PW_PlayerStatsChanged` triggers `Refresh` (`:68-71`). `PW.Stat` is
cached and recomputed only on spawn and loadout change (`design/05-loadout.md` d.8). The ARC9 base multiplies its
weapon `Speed` on top in a shared `SetupMove` hook (research section 7).

- [ ] Do **not** route the stim through `PW.Stat` / `PW.Perks.StatSource`: it would need a mid-life perk stat
  recompute, which contradicts d.8 ("recomputed on spawn and loadout change") and the T-4.4 mandatory case
  "recomputed on spawn and loadout change only".
- [ ] Instead extend the public movement owner named by d.16 ("Movement composes multiplicatively through the public
  player-overrides owner"): add owner-local **temporary movement sources** to `PW.PlayerOverrides` (contract change,
  section 15). Resulting formula, applied on every `Refresh`:

```text
walk = baseline.walk * (profile.walkSpeedMult or 1) * PW.Stat(ply, "move_speed", 1) * SpeedFactor(sources[ply])
run  = baseline.run  * (profile.runSpeedMult  or 1) * PW.Stat(ply, "move_speed", 1) * SpeedFactor(sources[ply])
```

- [ ] Pure function (shared, `P/modules/player_overrides/shared.lua`):

```text
PW.PlayerOverrides._SpeedFactor(sources: table<string, number>?) -> number
  Product of every value that is a finite number > 0, iterated in sorted id order; 1 for nil or empty.
  Non-number, nonfinite, zero and negative values are ignored.
```

- [ ] Thin engine wrapper (server, `P/modules/player_overrides/init.lua`):

```text
PW.PlayerOverrides.MoveSource(ply: Player, id: string, mult: number?) -> nil
  Sets (mult) or removes (nil) the owner-local temporary multiplier `id` of `ply`, then calls Refresh(ply).
  Weak-keyed by player. Never heals, never re-applies spawnHealth, never compounds current speeds.
```

- [ ] Change the early release condition in `apply` from `profile == nil and speed == 1` to
  `profile == nil and speed == 1 and factor == 1`, so the end of the last source restores the ordinary baseline.
- [ ] Lifecycle safety net in the owner: `PlayerSpawn` (where it already calls `Release`), `PlayerDisconnected` and
  `PW_MatchEnd` drop every move source of the player. The stims module still removes its own source on every end path.
- [ ] `stim_speed`'s `OnUse` calls `PW.PlayerOverrides.MoveSource(owner, self.ClassName, mult)` when the effect starts
  (after the use time); its expiry timer and its `OnUnequip` call `MoveSource(owner, self.ClassName, nil)`. Without
  the `player_overrides` module the speed stim refuses (`OnUse` returns `false`; the charge is kept).

## 5. Weapon-less use path (key to `OnUse`)

Verified gap: the client slot keys only select a grenade SWEP (`P/modules/equipment/cl_init.lua:63-73`) and the T-4.5
use message was removed (`docs/api/equipment.md`, "Keys"). A weapon-less item can currently be used only by bots.

- [ ] Pure helper (shared, `P/modules/equipment/shared.lua`):

```text
PW.Equipment._KeyAction(itemId: string?, weaponClass: string?, count: integer) -> "select" | "use" | nil
  nil when itemId is nil or count < 1; "select" when the item has a grenade SWEP; "use" otherwise.
```

- [ ] Client (`P/modules/equipment/cl_init.lua`): in both the `pw_<slot>` concommand and the `PlayerButtonDown`
  handler, keep the grenade path for `"select"`; for `"use"` send `pw_equipment_use` with the slot index as
  `net.WriteUInt(index, 2)` (`lib.Slots` order). `PlayerBindPress` swallowing stays as is.
- [ ] Server (`P/modules/equipment/init.lua`): register
  `PW.Net.Receive("pw_equipment_use", { who = "any", phases = { "LIVE" }, rate = 4, maxLen = 1, owner = MODULE }, ...)`;
  the handler reads the index, maps it to a slot (unknown index: ignore) and calls `lib._ClientUse(ply, slot)`.
- [ ] `lib._ClientUse(ply, slot) -> boolean`: uses `lib._UsableEntry`; returns `false` when the entry is missing or
  has a `weapon` (grenades are used only by releasing attack, the d.11 revision is unchanged); otherwise returns
  `lib._Spend(ply, slot, entry, nil)`.
- [ ] `docs/api/equipment.md` currently says "No net message"; this is contract change C1 (section 15).

## 6. Arctic integration (optional addon)

### 6.1 What is used and what is not

- [ ] Used: only the first-person injection animation that Arctic's addon registers with GCAL/VManip, played
  through the public GCAL native API (`GCAL.Anims[name]`, `GCAL:Play(name, track)`, `GCAL:IsTrackActive(track)`)
  or, when GCAL is absent, the legacy VManip API (`VManip:GetAnim(name)`, `VManip:PlayAnim(name)`). Client only,
  local player only.
- [ ] Not used, ever: the `+arc_vm_medshot` command, the `vm_arc_medshot_use` message, `ply.ArcticMedShots_Inv`,
  `ArcticMedShots_SyncPlayer`, `ArcticMedShots_ActiveEffects`, Arctic's entities, models or sounds by path. These are
  undocumented internals (research section 4); calling them would apply Arctic's own effects on top of PW's.

### 6.2 Structure (mirrors `addons/privatewar-arc9/`)

- [ ] `addons/privatewar-stims/addon.json`: title `Private War: Arctic's Combat Stims integration`, type
  `"tool"` (or `"weapon"` to match the ARC9 integration; the user chooses at publication time), tags `["fun"]`, the
  same `ignore` list as `addons/privatewar-arc9/addon.json`.
- [ ] `addons/privatewar-stims/lua/privatewar/modules/stims_arctic/shared.lua`: first line guard
  `if not PW or PW.API ~= 1 then return end`, `MODULE.Name = "Arctic stims integration"`, library `PW.StimsArctic`,
  the animation table `lib.Anims = { stim_heal = { anim = "arc_vm_medshot_inject", skin = 0 }, stim_speed =
  { anim = "arc_vm_medshot_inject", skin = 1 } }` (verified, research section 11), and the pure helpers below. The
  client sets the skin on `VManip:GetVMGesture()` after a successful `PlayAnim`. Never call
  `ArcticMedShots_ApplyEffect` or send `vm_arc_medshot_use` (research section 11, consequences).
- [ ] `.../stims_arctic/init.lua` (server): at `InitPostEntity`, when `GetConVar("arc_medshot_replacevial")` exists,
  remember its value and set it to `"0"`; restore the remembered value on `ShutDown`. Nothing else on the server.
- [ ] `.../stims_arctic/cl_init.lua` (client): on `PW_StimInjected(itemId)` call `lib._PickBackend` and play the
  animation; with `pw_debug 1` log once per map when the backend or the animation is missing.
- [ ] Pure helpers (shared, tested without the addon):

```text
PW.StimsArctic._PickBackend(hasGcal: boolean, hasVManip: boolean, gcalHas: boolean, vmanipHas: boolean)
  -> "gcal" | "vmanip" | nil
  "gcal" when GCAL exists and has the animation; else "vmanip" when VManip exists and has it; else nil.
PW.StimsArctic._AnimFor(itemId: string, anims: table<string, string>) -> string?
PW.StimsArctic._ShouldSwap(current: string?) -> boolean
  true only when the ConVar exists (current ~= nil) and is not already "0".
```

### 6.3 Detection, fallback, realms

- [ ] Detection is per realm and capability based, never by Workshop ID: server checks the ConVar; client checks the
  `GCAL` / `VManip` globals and that the animation name is registered.
- [ ] Missing addon, missing GCAL/VManip or unregistered animation: the integration does nothing; the core fallback
  (section 3.4) is unchanged. Core never depends on the integration.
- [ ] Server timing never changes with the integration installed: `stims.use_time` stays authoritative for humans and
  bots alike. If the verified animation is much longer than the use time, raise open question 5 with the measured
  length instead of changing server timing silently.
- [ ] Double application check (checkpoint): after an integrated injection, `LocalPlayer().ArcticMedShots_ActiveEffects`
  stays empty and health/speed change only by PW values. If Arctic's animation data plays its own syringe sound,
  the owner may hear two sounds; record it at the checkpoint (open question 11).

## 7. Bots

- [ ] Facts (`P/modules/bots_tactics/init.lua:115-127`, types `P/types/bots_tactics.lua`): add `tactical` (uses left
  in the tactical slot, 0 without the equipment module) and `tacticalItem` (item id or `nil`), filled like `lethal`.
  Add both to `emptyFacts` in `P/modules/bots_tactics/shared.lua:100`.
- [ ] New behaviour `P/bot_behaviors/use_stim.lua` (bots lane):

| Field | Proposed value |
| --- | --- |
| `Interval`, `MinRun`, `Cooldown` | 0.5, 0.3, 6 |
| `Rank` | `"survival"` when `tacticalItem == "stim_heal"`, `tactical > 0`, `PW.BotTactics.HealthFrac(f) <= 0.5` and `PW.BotTactics.Visible(ctx) == nil`; else `false` |
| `Weight` | 1 |
| `Update` | `PW.BotTactics.UseEquipment(ctx, "tactical")`, then `Done` with `"stim used"` or `"no stim"` |

- [ ] Pure rank seam in the behaviour file or `bots_tactics/shared.lua`:
  `_StimWanted(facts, visible: boolean) -> boolean` (tested without a bot).
- [ ] The speed stim is **explicitly deferred** for bots (no behaviour uses it in this slice). A later proposal: use it
  when the current goal priority is `objective`, the goal is farther than 1500 units and no enemy is visible.
- [ ] Bots go through the same server path (`PW.Equipment.Use` → the item's `OnUse`); effects, refusals and
  numbers are identical for humans and bots. Bots never see animations.
- [ ] `07-bots.md` d.13 lists behaviours; adding `use_stim` needs approval (section 14, item 4).

## 8. UI

- [ ] HUD equipment line: no code change. `P/hud/equipment.lua` already draws weapon-less items from the NW2 count
  (`[4] HEAL STIM x1`, dimmed at 0). Verify at the checkpoint, including the gamepad glyph `[D-LEFT]`.
- [ ] Active-effect indicator: new HUD element `P/hud/stims.lua` (ui lane), `HUDELEMENT.Order = 31`, phases `LIVE`,
  bottom right above the equipment lines (design units: right 1880, baseline 830). Lines: `SPEED 4.2` while the speed
  effect runs (one decimal), `HEALING` / `ARMOR` while heal or armor ticks run. Text is rebuilt only when it changes; no allocation per
  frame; colour token `text`, font `PW.UI.FontName("small")` as in `P/hud/equipment.lua`.
- [ ] State reaches the client as NW2 floats on the player, written only on change through `PW.Stims.Mark`:
  `pw_stim_speed_until`, `pw_stim_heal_until`, `pw_stim_armor_until` (`CurTime` values, 0 = none).
- [ ] Pure formatter (shared, `P/modules/stims/shared.lua`):

```text
PW.Stims._EffectLines(now: number, marks: { speed: number, heal: number, armor: number }) -> string[]
  "SPEED <seconds, one decimal, rounded up to 0.1>" when marks.speed > now; "HEALING" when marks.heal > now;
  "ARMOR" when marks.armor > now; in that order; empty table when none.
```

- [ ] Loadout UI: no code change; both items appear in the tactical slot list with `Name`, `Cost`, lock state and
  `Description` through the generic option builder (`P/modules/loadout_ui/sh_editor.lua:185-216`). Verify at the
  checkpoint.
- [ ] Game Setup: the `stims.*` match settings appear automatically (d.17). Verify at the checkpoint.
- [ ] Icons: none in this slice (frag and flash have none either). Open question 12.

## 9. Files to create or modify

| Path | Action | Owner |
| --- | --- | --- |
| `docs/api/stims.md` | Create: module contract (sections 3–8) | orchestrator |
| `docs/api/README.md` | Modify: index entry for `stims.md` | orchestrator |
| `docs/api/equipment.md` | Modify: weapon-less key path, `pw_equipment_use`, `_KeyAction`, `_ClientUse`, built-in items table | orchestrator |
| `docs/api/player-overrides.md` | Modify: move sources, `_SpeedFactor`, release condition, lifecycle | orchestrator |
| `docs/api/bots-blackboard.md` | Modify: facts `tactical`, `tacticalItem`; behaviour `use_stim` | orchestrator |
| `docs/agent-test-map.md` | Modify: rows for the new mandatory cases | orchestrator |
| `TASKS.md` | Modify: new Phase 11 task row and "Mandatory test cases" entry (section 11) | orchestrator |
| `P/modules/player_overrides/shared.lua` | Modify: `_SpeedFactor` | orchestrator-assigned lane |
| `P/modules/player_overrides/init.lua` | Modify: `MoveSource`, factor in `apply`, release condition, lifecycle drops | orchestrator-assigned lane |
| `P/types/player_overrides.lua` | Modify: annotations | same |
| `P/modules/stims/shared.lua` | Create: `MODULE.Name`, `MODULE.Settings`, `PW.Stims` pure rules | loadout |
| `P/modules/stims/init.lua` | Create: `Played`, `Mark`, `pw_stim_used` network string | loadout |
| `P/modules/stims/cl_init.lua` | Create: receive `pw_stim_used`, fire `PW_StimInjected` | loadout |
| `P/types/stims.lua` | Create: `PW.StimsLib`, item fields `Sound`, `Amount`, `Time`, `Mult`, `Max`, `UseTime` | loadout |
| `P/equipment/stim_heal.lua` | Create | loadout |
| `P/equipment/stim_speed.lua` | Create | loadout |
| `P/equipment/stim_armor.lua` | Create | loadout |
| `P/modules/equipment/shared.lua` | Modify: `_KeyAction` | loadout |
| `P/modules/equipment/cl_init.lua` | Modify: `"use"` branch sends `pw_equipment_use` | loadout |
| `P/modules/equipment/init.lua` | Modify: `PW.Net.Receive`, `_ClientUse` | loadout |
| `P/types/equipment.lua` | Modify: `_KeyAction`, `_ClientUse` | loadout |
| `P/hud/stims.lua` | Create: effect indicator | ui |
| `P/modules/bots_tactics/init.lua`, `shared.lua`, `P/types/bots_tactics.lua` | Modify: facts | bots |
| `P/bot_behaviors/use_stim.lua` | Create | bots |
| `addons/privatewar-stims/addon.json` | Create | orchestrator-assigned |
| `addons/privatewar-stims/lua/privatewar/modules/stims_arctic/shared.lua`, `init.lua`, `cl_init.lua` | Create | orchestrator-assigned |
| `T/player_overrides_move_sources.lua` | Create | with the owner change |
| `T/stims.lua` | Create | loadout |
| `T/stims_items.lua` | Create | loadout |
| `T/stims_equipment.lua` | Create | loadout |
| `T/hud_stims.lua` | Create | ui |
| `T/stims_bots.lua` | Create | bots |
| `T/integration_stims.lua` | Create | integration owner |

- [ ] Every new or changed Lua file stays within the rules gate: at most 500 lines per file and 60 lines per function;
  no `net.WriteTable` / `net.ReadTable`.
- [ ] Packaging and deploy pick up `addons/privatewar-stims/` automatically (`docs/packaging.md` line 35;
  `scripts/deck/deploy.sh` iterates `addons/*/`). Run the packaging self-test; publishing the new addon is a separate
  user decision (`docs/publishing.md`).

## 10. Implementation steps (TDD; one commit per step)

Each step: write the cases first, run them and observe RED, implement, run GREEN, run
`nix develop --command make check`, commit with `git commit --signoff` and a semantic message ending with the
`Assisted-by: LLM` trailer. Do not push without authorization.

- [ ] Step 1 (orchestrator): contracts. Write `docs/api/stims.md`, update `equipment.md`, `player-overrides.md`,
  `bots-blackboard.md`, `README.md`, `TASKS.md` (task row and mandatory cases), `docs/agent-test-map.md`.
  Commit `docs(api): freeze stim equipment contracts`.
- [ ] Step 2: move sources. `T/player_overrides_move_sources.lua` (section 11.1), then `_SpeedFactor`, `MoveSource`,
  the release condition and lifecycle drops. Existing `T/player_overrides.lua` and `T/perk_*` cases stay green.
  Commit `feat(player-overrides): add temporary movement sources`.
- [ ] Step 3: stims pure rules. `T/stims.lua` pure group, then `P/modules/stims/shared.lua` and `P/types/stims.lua`:
  `Param`, `_Ticks`, `_Step`, `_EffectLines`, settings table.
  Commit `feat(stims): add pure stim rules and settings`.
- [ ] Step 4: stims server helpers. `T/stims.lua` helper group, then `P/modules/stims/init.lua`: `Played` and `Mark`
  (engine calls behind small injectable fields so the cases run with fakes). Commit
  `feat(stims): add stim presentation helpers`.
- [ ] Step 5: weapon-less key path. `T/stims_equipment.lua` key group, then `_KeyAction`, the client branch, the
  `pw_equipment_use` receiver and `_ClientUse`. Existing `T/equipment.lua` and `T/grenades_inventory.lua` stay green.
  Commit `feat(equipment): let the slot key use weapon-less items`.
- [ ] Step 6: items. `T/stims_equipment.lua` item group, then `P/equipment/stim_heal.lua`, `stim_speed.lua`, `stim_armor.lua`, each with its own `OnUse`
  and, where needed, `OnUnequip` (section 3.6). Commit `feat(equipment): add heal, speed and armor stims`.
- [ ] Step 7: client notification. `P/modules/stims/cl_init.lua` (receive `pw_stim_used`, `PW.Notify("PW_StimInjected",
  itemId)`); covered by a server-side case that the owner-only message is sent with the right index.
  Commit `feat(stims): notify the client of an injection`.
- [ ] Step 8: HUD. `T/hud_stims.lua`, then `P/hud/stims.lua`. Commit `feat(hud): show active stim effects`.
- [ ] Step 9: bots. `T/stims_bots.lua`, then facts and `P/bot_behaviors/use_stim.lua`.
  Commit `feat(bots): use the heal stim when hurt and out of sight`.
- [ ] Step 10: integration. `T/integration_stims.lua`, then `addons/privatewar-stims/`. Commit
  `feat(stims): add optional Arctic's Combat Stims animation integration`.
- [ ] Step 11: gates (section 13), then the human checkpoint (section 12). Record results in this file; move it to
  `changes/in-progress/` when work starts and update `changes/INDEX.md` in that change (not before).

## 11. Mandatory test cases

GLuaTest files under `T/`. Case names are exact; a task is not done without them. Pure cases need no bot; module
cases use injectable stores; in-game cases reuse shared bots (`beforeAll`/`afterAll`, `maxplayers 12` budget).

### 11.1 `T/player_overrides_move_sources.lua`

- [ ] `SpeedFactor: empty or nil sources give 1`
- [ ] `SpeedFactor: multiplies valid sources in sorted id order`
- [ ] `SpeedFactor: ignores non-number, nonfinite, zero and negative values`
- [ ] `MoveSource composes with role multiplier and move_speed stat relative to the ordinary baseline`
- [ ] `MoveSource removal restores the previous product without compounding`
- [ ] `Removing the last source without profile or stat releases to the ordinary baseline`
- [ ] `MoveSource refresh never heals or reapplies spawn health`
- [ ] `PlayerSpawn drops move sources of the previous life`

### 11.2 `T/stims.lua` (pure)

- [ ] `Ticks: 60 over 1.5 s at 0.25 s gives six ticks of 10`
- [ ] `Ticks: remainder is spread so the sum equals the amount`
- [ ] `Ticks: zero duration gives one immediate tick`
- [ ] `Step: clamps to the cap`
- [ ] `Step: never lowers a value above the cap`
- [ ] `Param: item field wins, nil falls back to the setting, Base-inherited field is used`
- [ ] `EffectLines: speed seconds rounded up to one decimal, then healing, then armor`
- [ ] `Settings: defaults and bounds match the record`

### 11.3 `T/stims_items.lua` (items on fake owners and instances)

- [ ] `stim_heal: refused at or above max health, charge kept`
- [ ] `stim_heal: heals after the use time in ticks and stops at max health`
- [ ] `stim_heal: refused while its heal is pending or running`
- [ ] `stim_armor: refused at or above stims.armor_max, charge kept`
- [ ] `stim_armor: adds armor in ticks up to the cap`
- [ ] `stim_speed: sets the move source after the use time and marks the end time`
- [ ] `stim_speed: expiry removes the move source and clears the mark`
- [ ] `stim_speed: refused while active, charge kept`
- [ ] `stim_speed: OnUnequip removes the move source (death, match end, disable)`
- [ ] `Instance removal stops pending heal and armor ticks` (timers end with the instance)
- [ ] `Missing player_overrides module refuses the speed stim`
- [ ] `A Base variant inherits OnUse and uses its own Mult and Time`
- [ ] `Played sends pw_stim_used to the owner only with the item index`

### 11.4 `T/stims_equipment.lua`

- [ ] `KeyAction: select for grenade items, use for weapon-less items, nil when empty`
- [ ] `ClientUse: weapon-less item spends one use and runs OnUse`
- [ ] `ClientUse: refuses grenade items`
- [ ] `pw_equipment_use from a bot sender with a valid index uses the tactical slot`
- [ ] `pw_equipment_use outside LIVE or with an unknown index does nothing`
- [ ] `Refusal returns false and keeps the count and the cooldown`
- [ ] `Speed stim has two uses and refuses the second while active`
- [ ] `Counts refill on spawn`
- [ ] `Stockpile adds one use to a stim in the tactical slot`
- [ ] `Item sounds exist in the mounted game content`
- [ ] `Loadout accepts each stim in the tactical slot and rejects it in the lethal slot`

### 11.5 `T/hud_stims.lua`

- [ ] `Stims HUD lines are cached until the effect state changes`
- [ ] `Stims HUD draws nothing without active effects`

### 11.6 `T/stims_bots.lua`

- [ ] `StimWanted: hurt bot with a heal stim and no visible enemy wants it`
- [ ] `StimWanted: healthy, enemy visible, empty or speed stim does not`
- [ ] `Bot heal stim smoke: a hurt shared bot uses the stim and its health rises` (in-game, generous timeout)

### 11.7 `T/integration_stims.lua`

- [ ] `PickBackend prefers GCAL, falls back to VManip, nil when the animation is missing`
- [ ] `AnimFor returns the table entry or nil`
- [ ] `ShouldSwap only when the ConVar exists and is not 0`
- [ ] `Missing Arctic addon: integration does nothing and core stims still heal and boost`
- [ ] `With Arctic installed: vial replacement is off during the session and restored on shutdown` (skipped with one
  log line when the addon is absent)

## 12. Human checkpoint (user, in game on the Deck)

- [ ] Loadout UI: Heal Stim and Speed Stim appear in the tactical slot with name, cost, description, lock state;
  selecting one replaces Flash; Pick X budget counts them.
- [ ] Keyboard: key `4` uses the selected stim at once (no weapon switch); weapon slot 4 is not selected.
- [ ] Controller: d-pad left uses the stim; HUD shows `[D-LEFT] HEAL STIM x1` with gamepad button hints.
- [ ] Heal: at 40 HP one stim brings health to 100 over about 1.5 s; at full health the key does nothing and the
  count stays; others hear the sound.
- [ ] Speed: two charges; the second press during the boost does nothing and keeps the charge; HUD shows the countdown;
  sprint, walk and ARC9 weapons all feel faster; **no rubber-banding** at boost start and end.
- [ ] Composition: with Fleet Foot the boost still feels additive; speed returns to normal (not slower, not faster)
  after expiry, after death and at round change.
- [ ] Death during the injection: no effect after respawn; counts refilled.
- [ ] Use while reloading, sprinting and aiming works; nothing breaks the held weapon.
- [ ] Bots: a hurt bot out of sight uses a heal stim (watch `pw_bot_debug` or health).
- [ ] With GCAL and Arctic's addon installed: the injection animation plays for the heal and the speed stim with ARC9
  and HL2 weapons; health and speed change only by PW values (`ArcticMedShots_ActiveEffects` stays empty); map
  health vials are not replaced by random stims; note doubled sounds if any.
- [ ] Without Arctic's addon: everything above except the animation works.
- [ ] Game Setup shows the five `stims.*` settings and a changed value applies in the next match.
- [ ] Steam Deck frame time shows no visible hitch on injection.

## 13. Gates

- [ ] `nix develop --command make check` (lint, types, markdown, rules) is clean before every commit.
- [ ] `set -o pipefail; nix develop --command make test 2>&1 | tee <log in the scratchpad>` is green before merge,
  with the exact pass/fail/skip counts recorded here; integration skips are listed with their reason.
- [ ] The test run needs the Steam Deck: obtain fresh explicit user permission and confirmation that the Deck is free
  before any `scripts/deck/*` use; without it, report the gate incomplete. Never record private Deck paths or hosts.
- [ ] The human checkpoint (section 12) is a separate acceptance; automated results do not replace it.
- [ ] PR to `main` is draft by default, its title and body shown to the user and approved before creation; merge only
  with separate explicit approval (`gh pr merge --squash --delete-branch`).

## 14. Design changes requiring approval

- [ ] 1. `design/05-loadout.md` d.11: record that the base rule "pressing the slot key calls `OnUse`" applies to
  weapon-less items, while the 2026-11-07 revision ("the only way to throw is releasing attack") stays for grenade
  items. This reintroduces a client use message limited to weapon-less items.
- [ ] 2. `design/05-loadout.md` d.11 "the concrete MVP equipment set is content": approve `stim_heal` and `stim_speed`
  as built-in tactical content with the confirmed numbers.
- [ ] 3. `design/09-hud.md` d.2 (overlay elements): approve the stim effect indicator as a new overlay element.
- [ ] 4. `design/07-bots.md` d.13: approve the `use_stim` behaviour (survival bucket) and the deferral of speed stim use.
- [ ] 5. Not a change, confirm only: `design/05-loadout.md` d.8 stays as is because the stim does not use `PW.Stat`;
  d.16's movement rule is satisfied through the player-overrides owner.

## 15. Contract changes requiring the orchestrator

- [ ] C1 `docs/api/equipment.md`: `pw_equipment_use` (client to server, weapon-less items only), `_KeyAction`,
  `_ClientUse`, built-in items table rows for the stims.
- [ ] C2 `docs/api/player-overrides.md`: `MoveSource`, `_SpeedFactor`, the new release condition and lifecycle drops.
- [ ] C3 `docs/api/stims.md` (new): `PW.Stims` functions, settings, NW2 keys `pw_stim_speed_until` and
  `pw_stim_heal_until`, `pw_stim_armor_until`, server-to-owner message `pw_stim_used`, client notification `PW_StimInjected(itemId)`.
- [ ] C4 `docs/api/bots-blackboard.md`: facts `tactical`, `tacticalItem`; behaviour `use_stim`.

## 16. Open questions (recommended defaults in bold)

User answers (2026-11-22): question 1 — the speed stim has **two charges** (`Count = 2`), no second variant;
question 14 — the armor stim ships and adds **one plate (50 armor)** per use, cap 150; every other question takes
its recommended default. Integration option A (own items on the equipment key plus Arctic's animation) is the
recommended default and therefore approved.

- [ ] 1. "Shots for movement speed can be two": **two charges of one speed stim (`Count = 2`)**, or two speed stim
  variants (for example short strong and long weak)?
- [ ] 2. Slot: **existing tactical slot (stim replaces flash)**, or a new equipment slot (for example `field`, key
  `5`, a free gamepad button) so a player can carry flash and a stim? A new slot changes d.11 slot declarations,
  HUD layout and gamepad mapping.
- [ ] 3. Heal: **60 HP over 1.5 s**, instant 60 HP, or a full heal?
- [ ] 4. Speed: **×1.20 for 6 s, refuse while active**; or refresh (restart 6 s) or extend (+6 s)?
- [ ] 5. Use time **0.4 s without a weapon lock**; or lock firing during the injection (needs per-weapon-base work)?
  Note: Arctic's animation reaches the needle at about 1 s (research section 11 item 6), so with the integration the
  effect would start before the visible injection. Options: keep 0.4 s and accept it; raise `stims.use_time` to 1.0;
  or play the animation from a later cycle. Recommended: keep 0.4 s for the core and decide at the checkpoint.
- [ ] 6. Death during the injection: **charge spent, no effect**, or refund?
- [ ] 7. Heal at full health: **refused, charge kept**, or allowed?
- [ ] 8. Unlock levels and cost: **`Unlock = 1`, `Cost = 1` for both**, or later levels (for example 4 and 10)?
- [ ] 9. Tuning: **`match`-scope settings `stims.*`**, host-only `server` scope, or item fields only?
- [ ] 10. Bots: **heal stim behaviour now, speed stim deferred**?
- [ ] 11. Integration: **turn Arctic's vial replacement off during PW sessions** (yes recommended); clear Arctic's own
  inventory (**no**, internals); what to do about doubled sounds if observed?
- [ ] 12. Icons for equipment in HUD and loadout UI: **defer** (no icon system exists for equipment today)?
- [ ] 13. Default class presets: **keep Flash**, or give one preset a stim?
- [ ] 14. Armor stim: approve **the first armor source in the game** (50 over 1 s, cap 150), or a different amount or
  cap, or drop the armor stim? Armor changes time-to-kill for humans; bots do not use it in this slice.
- [ ] 15. Which further stims (section 3.6 candidates) are wanted later? **None now**; each needs its own approval.
