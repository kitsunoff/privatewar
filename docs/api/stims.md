# Stims API

The optional `stims` module supplies settings, presentation and pure helpers for weapon-less tactical
equipment. The built-in items are `stim_heal`, `stim_speed` and `stim_armor`. Each item owns its
effect and lifecycle in `OnUse` and `OnUnequip` through a `PW.Instance`, not an effect registry.
See [equipment](equipment.md) for the key, cooldown, counts and loadout rules and
[player overrides](player-overrides.md) for temporary movement composition.

## Settings and items

These `match`-scope settings appear in Game Setup and can be overridden by playlists.

| Setting | Type | Default | Range |
| --- | --- | --- | --- |
| `stims.use_time` | float | 0.4 s | 0 to 2 s |
| `stims.heal_amount` | int | 60 health | 10 to 200 |
| `stims.heal_time` | float | 1.5 s | 0 to 5 s |
| `stims.speed_mult` | float | 1.2 | 1 to 2 |
| `stims.speed_time` | float | 6 s | 1 to 30 s |
| `stims.armor_amount` | int | 50 armor | 10 to 150 |
| `stims.armor_time` | float | 1 s | 0 to 5 s |
| `stims.armor_max` | int | 150 armor | 50 to 255 |

The three items cost 1 and unlock at level 1. Heal and armor get one use per life; speed gets
two. Heal and armor add their amount over 0.25 s ticks, or immediately after injection when their
duration is zero. Health is capped by the player's actual maximum; armor is capped by
`stims.armor_max` without changing the player's maximum armor. Being at or above the corresponding
cap refuses the use. Damage does not interrupt recovery. Speed multiplies walk and run (not
jump, crouch, slide or ladder speed) from the end of the use delay until expiry. An already
pending or active effect refuses another use of the same item without spending a charge or
starting cooldown. No weapon switch or lock is introduced.

Items may override `UseTime`, `Amount`, `Time`, `Mult` or `Max`, as applicable. Ordinary registry
`Base` inheritance supplies defaults and behaviour for variants; the item id is also the movement
source id. Item timers end on instance removal. Cleanup cancels pending effects and removes
any temporary movement source and HUD mark; health and armor already given stay.

## Library

| Function | Realm | Contract |
| --- | --- | --- |
| `Param(item, field, settingId)` | shared | Read the requested item field including inherited values; fall back to the setting only for nil |
| `_Ticks(amount, time, step)` | shared | Split the amount into `ceil(time / step)` additions that sum exactly to it; nonpositive time produces one immediate addition |
| `_Step(current, add, cap)` | shared | Add up to the cap without lowering a value already above it |
| `_EffectLines(now, marks)` | shared | Ordered active lines: `SPEED <seconds>` rounded up to one decimal, `HEALING`, `ARMOR` |
| `Played(owner, item)` | server | Play the stock sound and a small view punch, then notify the owner about the injection |
| `Mark(owner, key, untilTime)` | server | Set the corresponding NW2 expiry on change; zero clears it |

`pw_stim_used` sends an 8-bit item index to the owner only. The client raises the notification
`PW_StimInjected(itemId)`. The `stims` HUD element (order 31, `LIVE`) reads player NW2 floats
`pw_stim_speed_until`, `pw_stim_heal_until` and `pw_stim_armor_until`, expressed in `CurTime()`
seconds, and displays only active effects above the equipment line.
The fixed right anchor is 1660 and the baseline is 830 in design units. This leaves the streak
column, bar and key hints clear without moving the indicator when streaks are toggled.

## Optional animation integration

`addons/privatewar-stims/` listens to `PW_StimInjected` on the local client. It prefers the
registered GCAL animation, then the VManip animation; no supported backend or animation means
no action. Without the integration, the item still has the stock sound, view punch and HUD.
The server temporarily sets the Arctic vial replacement ConVar to zero when present, then
restores the saved value on shutdown. The integration does not call Arctic's use path, change
inventory, apply effects or change Private War's effect timing.

The heal-stim bot behaviour uses the same server `PW.Equipment.Use` path. Speed and armor stim
usage by bots is not part of this feature.
