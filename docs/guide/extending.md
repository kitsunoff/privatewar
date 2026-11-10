# Extending Private War

Content is added as small files in a folder per kind, with no manifest. Each file defines one global table
(`MODE`, `PERK`, ...) that the loader creates for it. The file name is the id: lowercase letters, digits and `_`.

This guide gives, for each kind, the folder, the table, the required fields and a minimal example. The full
contracts are in `docs/api/`. Read current code/types alongside them; decided design takes precedence and actual
conflicts must be reported. Coding agents start at [AGENTS.md](../../AGENTS.md), use the matching mode/adapter/perk/
wildcard skill, and follow [tests-first verification](../agent-workflow.md) with the [mandatory case map](../agent-test-map.md).
Examples below are authoring patterns, not evidence that they were executed or authorization to add duplicate content.

## Where files go

Built-in content lives in `lua/privatewar/<folder>/`. Your own content goes in a separate addon with the same
layout:

```text
addons/my_private_war_pack/
  lua/privatewar/modes/quick_tdm.lua
  lua/privatewar/perks/second_wind.lua
```

Rules that hold for every kind (see [core.md](../api/core.md), "Entity files", "Required fields", "Enable ConVars"):

- A file is one entity. A folder `<id>/` with `shared.lua`, `init.lua` (server) and `cl_init.lua` (client) is the
  other form; if both exist, the folder wins.
- A syntax or runtime error skips the entity with one log line; the rest keeps loading.
- A missing or mistyped required field removes the entity from every list with one log line.
- Every entity gets an enable ConVar `pw_<table>_<id>_enabled`, where `<table>` is the global table name in
  lowercase (for example `pw_perk_second_wind_enabled`). The host can switch it off; the flag is read when a new
  match starts.
- `Base = "<id>"` inherits fields and methods from another entity of the same kind. Required fields are validated
  after inheritance; a child need not repeat them. Use unique paths/ids, never mount-order shadowing to replace built-ins.
- After editing, `pw_reload` rescans the server, but changed client datapack files require a map reload/reconnect.
  Agents use authorized locked scripts only; use `snap.sh` after client-visible edits, not a stale-client screenshot.
- An entity is never subscribed to engine hooks automatically. Perks, streaks and equipment get a per-player
  instance with `self:Hook(name, fn)` and `self:Timer(delay, reps, fn)`; both end with the instance
  ([core.md](../api/core.md), "Instances").
- Core/entity callers use `PW.Call`: ordinary definition errors disable that entity, active-mode errors abort to
  LOBBY, and instance errors end only that instance with cleanup. Bare third-party hook listeners retain ordinary
  GMod error propagation. Notifications return nothing; a value stops later listeners and the mode's default.

## A mode

| | |
| --- | --- |
| Folder | `lua/privatewar/modes/` |
| Global table | `MODE` |
| Required | `Name` (string), `Teams` (number; `0` is free-for-all) |
| Enable ConVar | `pw_mode_<id>_enabled` |
| Contract | [modes.md](../api/modes.md), "`MODE` class table" |

The simplest mode inherits a built-in one and changes its data. `Start`, `Think`, `Cleanup` and the `PW_*` answers
come from the base.

```lua
-- lua/privatewar/modes/quick_tdm.lua
MODE.Base = "tdm"
MODE.Name = "Quick Team Deathmatch"
MODE.Short = "QTDM"
MODE.Teams = 2
MODE.Description = "Two teams. First to 25 kills wins; the match lasts at most four minutes."
MODE.Settings = {
    scorelimit = { default = 25 },
    timelimit = { default = 240 }
}
```

Settings of a mode have the scope `match`; a child may re-declare an inherited key partially, as above. Read one with
`self:Setting("scorelimit")`.

A mode with its own rules defines the methods the core calls: `MODE:Start()` on entering LIVE, `MODE:Think()` every
tick of LIVE, `MODE:Cleanup()` on leaving it, and `MODE:PW_<Hook>(...)` answers. A mode finishes the match with
`PW.Match.Finish(result)`. For rounds, inherit `round_base`; for flags or tags see `dom` and `kc`. Bots follow a
mode's objectives through `MODE:BotObjectives(team)`.
Objective modes declare all required handlers/modules through `MODE.Dependencies`; missing/disabled dependencies
abort before play, even without bots. For round roles use `PrepareRound(round, swapped)` before playable spawns,
not the later `PW_RoundStart`. See [modes API](../api/modes.md) for pinned dependencies, life/role and privacy rules.

## A perk

| | |
| --- | --- |
| Folder | `lua/privatewar/perks/` |
| Global table | `PERK` |
| Required | `Name` (string), `Group` (number 1 to 3: the perk slot it fits) |
| Optional | `Description`, `Cost` (Pick X, default 1), `Stats`, event methods |
| Enable ConVar | `pw_perk_<id>_enabled` |
| Contract | [perks.md](../api/perks.md) |

Event methods get the owner first: `OnEquip`, `OnUnequip`, `OnKill(owner, victim, dmg)`, `OnDeath`, `OnDamaged`,
`OnDealDamage`. For any other hook use `self:Hook` inside `OnEquip`. `Stats` are multipliers by stat id.

```lua
-- lua/privatewar/perks/second_wind.lua
PERK.Name = "Second Wind"
PERK.Description = "Each kill restores 10 armor."
PERK.Group = 3
PERK.Cost = 1

---@param owner Player
function PERK:OnKill(owner)
    owner:SetArmor(math.min(owner:GetMaxArmor(), owner:Armor() + 10))
end
```

A stat perk needs no code: `PERK.Stats = { reload_time = 0.8 }`. Weapon stat mods only act on weapon bases whose
adapter lists them; the HL2 fallback adapter supports none ([perks.md](../api/perks.md), "Stats").
Do not call partial `PW.SetStatMods` from a perk; the owner composes the complete table. Timer/hook callbacks use
the instance argument, never the temporary global `PERK`. Cleanup must also cover revoke/disable and partial
constructor failure. Movement composes through the player-overrides owner without refresh healing or speed compounding.

## A killstreak

| | |
| --- | --- |
| Folder | `lua/privatewar/streaks/` |
| Global table | `STREAK` |
| Required | `Name` (string), `Kills` (number: the cost when earned by kills), `OnEquip` (function: the activation) |
| Optional | `Score` (cost by score, default `Kills` x 100), `Duration` (seconds, default 10), `OnUnequip`, `BotShouldUse(bot)` |
| Enable ConVar | `pw_streak_<id>_enabled` |
| Contract | [streaks.md](../api/streaks.md) |

Using a streak creates an instance and runs `OnEquip(owner)`; the module ends it after `Duration` seconds, which also
stops its hooks and timers.

```lua
-- lua/privatewar/streaks/field_medic.lua
STREAK.Name = "Field Medic"
STREAK.Kills = 4
STREAK.Duration = 10

function STREAK:OnEquip(owner)
    if not SERVER then return end
    self:Timer(1, 10, function()
        if not IsValid(owner) or not owner:Alive() then return end
        owner:SetHealth(math.min(owner:GetMaxHealth(), owner:Health() + 8))
    end)
end

---@param bot Player
function STREAK:BotShouldUse(bot)
    return bot:Health() < bot:GetMaxHealth() * 0.6
end
```

A streak is selected in a class's streak slots (`streak1` to `streak3`) in the class editor. The player uses it with
key 5 (`pw_streak`). Without `BotShouldUse` a bot uses the streak whenever it has it.

## A wildcard

| | |
| --- | --- |
| Folder | `lua/privatewar/wildcards/` |
| Global table | `WILDCARD` |
| Required | `Name` (string), `ModifySlots(slots)` (function) |
| Optional | `Description`, `Cost` (Pick X, default 1), `Stats` |
| Enable ConVar | `pw_wildcard_<id>_enabled` |
| Contract | [loadout.md](../api/loadout.md), "Wildcards" |

`ModifySlots` changes a copy of the slot set; validation, the Pick X budget and class repair all use the changed
copy. A class can carry up to two wildcards.
The callback is pure and deterministic; a local `pcall` drops a failing transform's scratch edits rather than
permanently disabling it through `PW.Call`. Duplicate ids and self-expansion of the wildcard slot are rejected.
An added effective slot passing validation is not proof it is given: the current Give path iterates declared slot
order, so new runtime slots need corresponding owned consumers/tests. Changing existing slot counts/filters/caps
does not need a parallel validator.

```lua
-- lua/privatewar/wildcards/perk_two_greed.lua
WILDCARD.Name = "Perk 2 Greed"
WILDCARD.Description = "Take two perks from the second perk group."

---@param slots table<string, PW.LoadoutSlot>
function WILDCARD:ModifySlots(slots)
    local slot = slots.perk2
    if slot == nil then return end
    slot.count = (slot.count or 1) + 1
end
```

## An equipment item

| | |
| --- | --- |
| Folder | `lua/privatewar/equipment/` |
| Global table | `EQUIPMENT` |
| Required | `Name` (string), `Count` (number: uses per life), `OnUse(owner)` (function) |
| Optional | `Category` (`"lethal"` or `"tactical"`: the slot it fits), `Cost` (Pick X, default 1) |
| Enable ConVar | `pw_equipment_<id>_enabled` |
| Contract | [equipment.md](../api/equipment.md) |

`OnUse` runs on the item's per-player instance. Returning `false` refuses the use: the count is kept and the
cooldown does not start. Other fields are free data of the item.

```lua
-- lua/privatewar/equipment/stim.lua
EQUIPMENT.Name = "Stim"
EQUIPMENT.Category = "tactical"
EQUIPMENT.Count = 1
EQUIPMENT.Heal = 40

---@param owner Player
---@return boolean
function EQUIPMENT:OnUse(owner)
    if owner:Health() >= owner:GetMaxHealth() then return false end
    owner:SetHealth(math.min(owner:GetMaxHealth(), owner:Health() + self.Heal))
    return true
end
```

For a thrown item use `PW.Throw(owner, PW.Throwables.EntityClass, opts)` with `opts.detonate`; the built-in `frag`
and `flash` are the references. The player uses the slot with `G` (lethal) or `4` (tactical).

## A bot behaviour

| | |
| --- | --- |
| Folder | `lua/privatewar/bot_behaviors/` |
| Global table | `BEHAVIOR` |
| Required | `Rank(bot, ctx)`, `Weight(bot, ctx)`, `Update(bot, ctx)` |
| Optional | `Modes` (list of mode ids, default every mode), `Interval`, `MinRun`, `Cooldown`, `OnStart`, `OnEnd`, `OnSuspend`, `OnResume` |
| Enable ConVar | `pw_behavior_<id>_enabled` |
| Contract | [bots-blackboard.md](../api/bots-blackboard.md), "`bot_behaviors`" |

The brain picks a behaviour in two steps. `Rank` is a hard bucket (`"survival"` 40, `"combat"` 30, `"objective"` 20,
`"roam"` 10, or a number above 0); `nil` or `false` means "not a candidate now". `Weight` is the nuance inside the
bucket. `Update` returns a transition: `PW.BotBrain.Continue()`, `ChangeTo(id, reason?)`, `SuspendFor(id, reason?)`
or `Done(reason?)`. A bot acts only through its intent (`ctx:Intent()`), never by moving or damaging itself.

```lua
-- lua/privatewar/bot_behaviors/catch_breath.lua
-- A badly hurt bot that sees no enemy crouches until it has recovered a little.
BEHAVIOR.Interval = 0.5
BEHAVIOR.MinRun = 1
BEHAVIOR.Cooldown = 5

---@param bot Player
---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(bot, ctx)
    if bot:Health() >= 30 then return false end
    for _, contact in ipairs(ctx.contacts) do
        if contact.visible then return false end
    end
    return "survival"
end

---@return number
function BEHAVIOR:Weight()
    return 0.5
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnStart(_, ctx)
    ctx:ClearGoal()
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    ctx:Intent().stance = "stand"
end

---@param bot Player
---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(bot, ctx)
    if bot:Health() >= 50 then return PW.BotBrain.Done("recovered") end
    ctx:Intent().stance = "crouch"
    return PW.BotBrain.Continue()
end
```

Other bot kinds are data files with the same folder layout: `bot_personalities`, `bot_difficulties`. The built-in
behaviours in `lua/privatewar/bot_behaviors/` (`camp`, `idle`, `fight`) are the best references.

## A weapon-base adapter

One integration is one separate addon with a base-specific module and an `ADAPTER` definition. Current reference:
`addons/privatewar-arc9/lua/privatewar/weapon_adapters/arc9/{shared.lua,init.lua}` (repository-relative).
Read [adapter API](../api/adapter.md) and the [adapter skill](../../.opencode/skills/privatewar-weapon-adapter/SKILL.md)
for required signatures, catalogue timing, public-API-only integration, native customization lock, actual-stuck
build returns, shared stat prediction and human/bot native checks. TFA/MW Base remain future integrations.

## Checking your content

1. Write task-specific GLuaTest cases first in repository `addons/privatewar/lua/tests/privatewar/`; preserve all
   applicable mandatory assertions. Observe intended RED/GREEN only in an authorized real-game run, or report unobserved.
2. Set `set -o pipefail`; run `nix develop --command make check`. With permission and a confirmed-free Deck,
   run `nix develop --command make test`; never interrupt an occupied device. Both gates are needed for merge.
3. In that authorized workflow reload the server/map appropriately and inspect errors and new registry entries.
   Open the lobby: modes appear in Custom game, perks/streaks/wildcards/equipment in the class editor. Verify the
   actual build/effect and cleanup, not just the row's presence.
4. Leave human visual/controller/P2P/feel/performance checkpoints pending until actually checked and accepted.
   See [workflow](../agent-workflow.md) for failures, device scripts, reporting and separate publication approvals.
