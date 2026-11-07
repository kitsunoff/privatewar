# Equipment API: items, slots, grenade SWEPs, throwing, blinding

Status: added after T-4.5 (2026-11-07); grenades became inventory SWEPs in T-11.4 (2026-11-07). The code wins over any
description here.

Modules `equipment` (`lua/privatewar/modules/equipment/`: `shared.lua` slots, keys, pure rules; `sh_grenades.lua` pure
grenade rules and the grenade ammo types; `init.lua` per-player state and use, server; `sv_grenades.lua` the grenade
SWEPs' server glue; `cl_init.lua` slot keys, client) and `throwables` (`lua/privatewar/modules/throwables/`:
`shared.lua` pure throw and flash rules and the `pw_grenade` entity; `init.lua` `PW.Throw` and blinding, server;
`cl_init.lua` the white screen, client). Kind `equipment` (`kinds/equipment.lua`), items in
`lua/privatewar/equipment/`, grenade SWEPs in `gamemodes/privatewar/entities/weapons/` (`weapon_pw_grenade` base,
`weapon_pw_frag`, `weapon_pw_flash`), HUD element `lua/privatewar/hud/equipment.lua`. Types:
`lua/privatewar/types/equipment.lua`, `types/throwables.lua`. Source decisions: `design/05-loadout.md` d.11 (equipment is
an item in a slot, its behaviour belongs to the item; revision 2026-11-07: grenades are inventory SWEPs, the count is
the SWEP's ammo, bots switch to the grenade and throw it), `design/01-extensibility.md` d.12, d.16, d.18. It sits on top
of `core.md` (kinds, instances, `PW.Call`) and `loadout.md` (slots, Pick X) and does not repeat them.

## Kind `equipment` and `EQUIPMENT`

One file per item in `lua/privatewar/equipment/` with an `EQUIPMENT` table. Folder `equipment`, global `EQUIPMENT`,
`Subscribe = "never"` (d.18: the module makes an instance of the item per player), enable ConVar
`pw_equipment_<id>_enabled`. `Required = { Name = "string", Count = "number", OnUse = "function" }`.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `Name` | string | yes | Display name (the HUD upper-cases it) |
| `Count` | number | yes | Uses per life, refilled on spawn; rounded down, negative counts as 0 |
| `OnUse` | `function(self, owner, use?) -> boolean?` | yes | Runs on the item's instance (`PW.Call`) when the slot is used: the release of the item's grenade SWEP, or `PW.Equipment.Use`. `use` is `PW.EquipmentUse` (below). Returning `false` refuses the use: the count is kept and the cooldown does not start |
| `Weapon` | string | no | The grenade SWEP class the item gives; the count is that SWEP's ammo. Without it the item has no weapon and is used only through `PW.Equipment.Use` |
| `Cook` | boolean | no | Whether holding attack cooks the grenade (its fuse runs in hand) |
| `Category` | string | no | The slot filter value: `"lethal"` or `"tactical"`; the built-in slots accept only their own category |
| `Cost` | number | no | Pick X cost (`loadout.md`), default 1 |

`PW.EquipmentUse`: `cooked` (seconds cooked in hand, 0 for an item that does not cook), `drop` (the cook reached the cap:
the grenade goes off in hand), `death` (the owner died while cooking: the live grenade drops at the body), `weapon` (the
SWEP that threw it).

On spawn the item becomes a per-player instance (`PW.Instance(def, ply)`, `core.md`), so `OnUse` may keep state on `self`
and use `self:Hook` and `self:Timer`, which end with the life. Other fields are free data of the item (the samples use
`Fuse`, `Damage`, `Radius`, `Model`).

### Built-in items

| Item | Category | Count | SWEP | Behaviour |
| --- | --- | --- | --- | --- |
| `frag` ("Frag") | `lethal` | 1 | `weapon_pw_frag`, ammo `pw_frag` | Cooks. `PW.Throw` with fuse 3 s less the time cooked; at the end `util.BlastDamage` of 150 damage, radius 350 (linear falloff), stock explosion effect, scorch decal and screen shake. The thrower is the attacker and the grenade SWEP the inflictor, so kills count for the thrower and weapon XP goes to `weapon_pw_frag`; the grenade still goes off when the thrower died meanwhile. Dying while cooking drops it live at the body with the remaining fuse (3 s less the time cooked, at least `DeathMinFuse`) |
| `flash` ("Flash") | `tactical` | 1 | `weapon_pw_flash`, ammo `pw_flash` | Does not cook: the fuse starts on release. `PW.Throw` with fuse 1.5 s, tinted pale blue; at the end a bang and a flare, then `PW.Throwables.FlashAt` blinds the players it reaches. No damage |

Both use the stock HL2 grenade models, animations and effects; nothing is vendored.

## Grenade SWEPs

`weapon_pw_grenade` is the base (not spawnable, never given); `weapon_pw_frag` and `weapon_pw_flash` derive from it and
set `PWSlot` and `Primary.Ammo`. All are `Spawnable = false`, so the weapon catalogue never lists them. Fields:
`PWGrenade = true` (marks a grenade SWEP), `PWSlot` (the equipment slot), GMod `Slot = 4` (the fifth weapon bucket),
`HoldType = "grenade"`, `Primary.ClipSize = -1` (the ammo is the count; the HL2 ammo panel shows it), `AutoSwitchTo =
false`. The ammo types `pw_frag` and `pw_flash` (`PW.Equipment.AmmoTypes`) are added once at load (`game.AddAmmoType`,
max 9), so an empty grenade is skipped by the weapon wheel and the bumpers.

| Input | Behaviour |
| --- | --- |
| Hold primary attack | Pulls the pin. For an item that cooks, the fuse runs in hand; at `CookCap` (3 s) the grenade goes off in hand (thrown with no speed and the minimum fuse) |
| Release primary attack | Throws: on the server `PW.Equipment._Release` calls the item's `OnUse` with the cooked time, takes one ammo and starts the cooldown |
| Last grenade thrown | After `SwitchDelay` (0.5 s) the player returns to the weapon held before the grenade (else another non-grenade weapon) |
| Holster while cooking | Cancels the cook; nothing is thrown and no ammo is used |
| Death while cooking | Drops the live grenade at the body (`DoPlayerDeath`, `_DropOnDeath`): the item's `OnUse` runs with `death = true`; it goes off after the remaining fuse with the dead thrower as the attacker (user decision 2026-11-07) |

The cook state lives in the SWEP's data table float 0 (`CurTime` when the pin was pulled, 0 when idle), predicted on the
owner's client. Bots never cook through the SWEP: they throw through `PW.Equipment.Use`.

## Slots and the module library

The slots `lethal` and `tactical` (kind `equipment`, filter `{ slot }`) are declared in the loadout module
(`loadout.md`). The default loadout and the class presets carry `frag` and `flash`.

`PW.Equipment` (the module library; the registry is `PW.Registries.equipment`):

| Field or function | Contract |
| --- | --- |
| `Slots` | `{ "lethal", "tactical" }` |
| `Keys` | Per slot `{ command, convar, default }`: `lethal` is `pw_lethal`, `pw_key_lethal`, `g`; `tactical` is `pw_tactical`, `pw_key_tactical`, `4` |
| `Cooldown` | 0.75 seconds between two uses of one slot |
| `CookCap`, `SwitchDelay`, `BotHold`, `DeathMinFuse`, `AmmoTypes` | 3 s; 0.5 s; 0.3 s; 0.1 s; `{ "pw_frag", "pw_flash" }` |
| `Count(ply, slot)` | Uses left (integer). Server: the server state, mirrored into the grenade SWEP's ammo. Client: the ammo of the slot's grenade SWEP when the player holds it, else the networked value; 0 when the slot is empty |
| `Item(ply, slot)` | The item id in the slot, `nil` when empty |
| `Use(ply, slot, use?)` | Server. In `LIVE`, for a living player with uses left and the cooldown passed, uses the slot; equips the player first when they have no state yet. For an item with a grenade SWEP: selects the SWEP (giving it when missing), calls `OnUse` with `use` and the SWEP, and returns to the previous weapon after `BotHold`. For an item without one: calls `OnUse` directly. On success the count drops, the cooldown starts and the count is published. Returns whether the item was used. **Bots use this function directly** (`bot_behaviors/throw_equipment.lua`) |
| `_Release(ply, wep, use?)` | Server. The grenade SWEP's release: uses the SWEP's slot (only when the slot's item names this SWEP class) with `use` and the SWEP; then the store's `afterThrow` (after the last grenade: switch back after `SwitchDelay`). Returns whether a grenade was thrown |
| `_GiveWeapons(ply)` | Server. Gives every equipped slot's grenade SWEP (when missing) and sets its ammo to the count. On the first give of a life the count is the answer of `PW_EquipmentCount` |
| `_ReturnTo(ply)` | Server. Selects the weapon held before the grenade (remembered on `PlayerSwitchWeapon`, then `GetPreviousWeapon`), else the first non-grenade weapon; returns the class |
| `_Equip`, `_Clear`, `_OnSpawn`, `_NewStore`, `_UsableEntry`, `_Spend`, `_BotThrow`, `_AfterThrow`, `_Remember`, `_Inflictor` | Server internals for tests: equip the resolved loadout with full counts, end the instances and empty the slots, the spawn hook body (equips in `LIVE` only), a store over injectable engine calls (`lookup`, `resolve`, `publish`, `clock`, `phase`, `alive`, `afterThrow`), the entry a player may use now, one use of an entry, the bot path, the default `afterThrow`, the `PlayerSwitchWeapon` body, the inflictor of a grenade's damage |
| `_Refill`, `_CanUse`, `_KeySlot`, `_ItemKey`, `_CountKey`, `_DeclareSlots` | Pure helpers: uses per life; whether an entry can be used (`false` and `"empty"`, `"invalid"` or `"cooldown"`); the slot of a pressed key; the NW2 keys; the slot declaration |
| `_DropOnDeath(ply)` | Server. The `DoPlayerDeath` body: when the dying player's active grenade SWEP is being cooked by an item that cooks, calls its `OnUse` with `{ cooked, death = true, weapon }`; returns whether a grenade was dropped |
| `_RemainingFuse`, `_DeathDrop` | Pure death-drop rules: the fuse less the cook, never below a minimum; the seconds cooked when the pin is pulled on an item that cooks, else `nil` (nothing drops) |
| `_CookState`, `_CookedFuse`, `_ShouldSwitchBack`, `_ReturnWeapon`, `_SlotWeapon`, `_KeyWeapon`, `_CountFor`, `_WeaponOf`, `_ThrowOptions` | Pure grenade rules: `"idle"`, `"hold"`, `"throw"` or `"overcook"` and the seconds cooked; the fuse less the cook; whether a count means switching back; the weapon to return to; the grenade SWEP of a slot or a pressed key when it has ammo; the count after a `PW_EquipmentCount` answer; the SWEP class of an item; the `PW.ThrowOptions` of a use |
| `_AmmoOf`, `_Lookup`, `_ItemWeapon` | Shared: the ammo type of a SWEP class; the valid definition of an item id; the SWEP class of an item id |

Life cycle (server): the spawn hook equips in `LIVE` only, resolving the loadout through `PW.Loadout.Resolve` (so a mode's
`PW_PlayerLoadout` and a picked class count) and refilling every count. After the loadout's weapons are given
(`PW_LoadoutGiven`, one tick later so perks and wildcards are equipped) the grenade SWEPs are given with ammo = count; a
new loadout in the same life gives them again with the count left. Death (`PostPlayerDeath`), disconnect and the end of
the match (`PW_MatchEnd`) end the instances and empty the slots. Equipment is spent on death and refilled on spawn.

State reaches the client as NW2 values of the player, written only when they change: `pw_eq_<slot>` (item id string,
empty when none) and `pw_eqn_<slot>` (count); the count is also the grenade SWEP's ammo.

## Hook `PW_EquipmentCount`

`PW_EquipmentCount(ply, slot, itemId, count) -> number?`: question (`PW.Ask`), server. Asked once per life when the
grenade SWEPs are first given, after the perks and wildcards of the loadout are equipped. A number replaces the count
(rounded down, at least 0) and becomes the SWEP's ammo; `nil` keeps it. The first listener that answers wins (GMod hook
order). A perk answers it from its instance: `self:Hook("PW_EquipmentCount", function(perk, ply, slot, id, count) ...
end)`.

### Deterministic additive count sources

Approved by `design/05-loadout.md` d.16; implemented after observed test-first RED.
The legacy question above retains its first-answer meaning. It is not converted into a chain.

- `PW.Equipment.CountSource(ply, id, fn?)`: register/replace an owner-local additive source;
  nil removes it. `fn(ply, slot, itemId)` returns an additional count, not a replacement.
  Sources run in sorted id order, after the single legacy answer has been resolved.
- Ignore failed, negative, non-number and nonfinite source answers; floor finite nonnegative
  additions. `_ComposeCount(base, legacyAnswer, sources, ply, slot, itemId)` is the pure seam.
- Resolve exactly once on the first grant of each life after perks/wildcards equip. Stockpile
  contributes +1 to lethal and tactical only. Repeated grants, weapon switches or selecting a
  different class midlife do not refill spent counts. Cached count and grenade ammo remain
  authoritative. Removing a source does not take back already-granted uses or grant more.
- A perk unregisters its source on unequip. Source ownership is separate from equipment
  instance lifetime, so spawn hook order cannot accidentally discard an equipped source.

Tests: `equipment_count_sources.lua`; the existing grenade inventory/cooking cases are unchanged.

## Keys

No net message: the use message `pw_equipment_use` of T-4.5 is gone, so the release of the grenade SWEP is the only way
a player throws.

Keys (client): the default physical keys are the client ConVars `pw_key_lethal` (default `g`) and `pw_key_tactical`
(default `4`), saved with the player's settings; a key name is anything `input.GetKeyCode` takes. The console commands
`pw_lethal` and `pw_tactical` do the same for players who bind keys themselves (`bind x pw_tactical`); the gamepad
d-pad down and left run them (`ui.md`, "Gamepad buttons in a match"). A press in `LIVE` selects the slot's grenade SWEP
(`input.SelectWeapon`) when the player holds it with ammo; it never throws. The weapon wheel and the bumpers
(`invnext`, `invprev`) reach the grenades too. While the player holds an item in a slot during `LIVE`, the engine bind
of that key is swallowed (`PlayerBindPress`), so the tactical key `4` does not also switch to weapon slot 4. `F` stays
the flashlight.

HUD element `equipment` (`hud/equipment.lua`, order 30, phase `LIVE`): one line per held slot at the bottom right, above
the HL2 ammo panel: the key hint in brackets, the item name and the uses left (`[G] FRAG x1`, the grenade SWEP's ammo);
an empty slot is not drawn, a spent one is dimmed.

## `PW.Throw` and `PW.Throwables`

`PW.Throw(ply, entClass, opts?)` (server; the same function as `PW.Throwables.Throw`) spawns `entClass` from the eye along
the aim with physics and runs the fuse. It returns the entity, or `nil` when `ply` is not a living player (a dead one only with `opts.drop`) or the entity
could not be made. The start point is pulled back when a wall is in the way. When the fuse ends, `opts.detonate(ent,
owner)` runs and the entity is removed.

| `PW.ThrowOptions` field | Meaning |
| --- | --- |
| `cook` | Seconds from the throw to detonation (the design's name; a bot's quick throw has no hold) |
| `fuse` | The same, used when `cook` is nil |
| `speed`, `lift`, `forward` | Throw speed along the aim, extra upward speed, spawn distance in front of the eye |
| `model`, `color` | World model and tint of the projectile |
| `detonate` | `function(ent, owner)`, run at the end of the fuse |
| `drop` | Drop at the owner's body (waist height, the body's velocity) instead of throwing from the eye; allowed for a dead owner |

Defaults (`PW.Throwables.Defaults`): speed 900 units per second along the aim plus 180 up, spawned 18 units in front of
the eye, the thrower's velocity added; fuse 3 s, clamped to 0.05 to 10 s. The generic projectile is the entity
`pw_grenade` (`PW.Throwables.EntityClass`): a physics model with an owner that does not collide with it, bounce sounds
only. Live projectiles are removed without detonating at the end of the match (`PW.Throwables._RemoveAll`).

| `PW.Throwables` | Contract |
| --- | --- |
| `Flash` | `{ radius = 1500, near = 300, behind = 0.2, maxTime = 4, minStrength = 0.05 }` |
| `Blind(ply, strength)` | Server. Returns whether it blinded; does nothing below `minStrength`. For a human it sends `pw_blind` and, at strength 0.5 or more, sets the ringing DSP; for everyone (bots too) it notifies `PW_Blinded` |
| `Impairment(ply, now?)` | Server. Current ordinary blind alpha from the authoritative resolved strength/start time; 0 without active status. Bot sight and firing use the same status and expiry, without changing difficulty or erasing memory |
| `ClearBlind(ply)`, `ClearBlinds()` | Server. Release one/all owned flash statuses, expiry timers, DSP and human overlays. Death, disconnect, match end and throwables disable clean up owned state; round lifecycle owners may call `ClearBlinds` |
| `FlashAt(pos, inflictor?)` | Server. Blinds every living player within `radius` of `pos` by line of sight, angle and distance; returns how many were blinded |
| `Blinded` | Client. `{ strength, at }`: the blind being shown (strength 0 = none) and its start time |
| `_Launch`, `_Fuse`, `_FlashStrength`, `_BlindTime`, `_BlindAlpha`, `_EncodeStrength`, `_DecodeStrength` | Pure helpers (tests) |

Flash strength (`_FlashStrength(dist, dot, visible)`): 0 without line of sight (an opaque-mask trace from the flash to the
eye) or at `radius` and beyond; the distance factor is 1 inside 300 units and falls linearly to 0 at 1500; the angle
factor is 1 when the player faces the flash within 60 degrees, down to 0.2 when facing directly away. A full blind lasts
4 s (`_BlindTime` is `maxTime` times the strength); the white screen is held for the first 30 percent and then fades.

| Message | Direction | Content |
| --- | --- | --- |
| `pw_blind` | server to client | `uint(8)`: the strength times 255. The white screen is drawn in `RenderScreenspaceEffects`, not as a HUD element, so `pw_hud 0` does not remove it |

## Hook `PW_Blinded`

`PW_Blinded(ply, strength, seconds)`: notification (`PW.Notify`), server. Fired by `PW.Throwables.Blind` for every
blinded player, bots included, so the bot perception may listen. `strength` is 0..1, `seconds` is the blind duration.
Flash resistance scales strength before this notification. The resolved 8-bit strength and
its derived duration are identical for human packets and bot status. A weaker simultaneous
flash cannot shorten a stronger remaining status. Ordinary bots suppress new visual
recognition and weapon firing while impairment exceeds 0.05; legitimate old memory and
nonvisual awareness are not deleted. Difficulty parameters and recoil compensation are unchanged.

## Bots

The behaviour `throw_equipment` (`bots-blackboard.md`) calls `PW.Equipment.Use(bot, "lethal")` after looking at the last
known position of an enemy that was lost behind cover 300 to 1800 units away.
