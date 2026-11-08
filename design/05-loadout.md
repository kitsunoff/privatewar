# 05 — Loadout

Status: decided (in-game checks: `../notes/12-weapon-stat-modifiers.md` §8).

## Goal and scope

Classes, gunsmith, server-side validation and application of builds.

## Decisions

Inherited from `04-weapons.md`:

- The gamemode owns attachments; no in-match customization (decision 2).
- Weapon catalogue = kind `weapons/`, filled declaratively and programmatically; ready after `PW_WeaponsLoaded` (decision 3).
- Bases mix freely; restrictions are `match` settings of the loadout module: `weapons.bases` (allowed bases, type `set`, default all), a banned-weapons list and `loadout.bannedatts` (type `set`), usable in Game Setup and playlists (decision 5; `06-progression.md` decision 2).

### Structure

1. **Slots are declared by modules; the loadout module knows nothing about perks or streaks.**

   ```lua
   -- modules/perks/shared.lua
   PW.Loadout.DeclareSlot("perk1", { kind = "perks", group = 1, label = "#pw.slot.perk1" })
   PW.Loadout.DeclareSlot("perk2", { kind = "perks", group = 2, label = "#pw.slot.perk2" })
   PW.Loadout.DeclareSlot("perk3", { kind = "perks", group = 3, label = "#pw.slot.perk3" })

   -- modules/weapons_loadout/shared.lua
   PW.Loadout.DeclareSlot("primary",   { kind = "weapons", filter = { "ar", "smg", "lmg", "sniper", "shotgun" } })
   PW.Loadout.DeclareSlot("secondary", { kind = "weapons", filter = { "pistol", "launcher" } })
   ```

   - A loadout (class) is `{ [slotId] = entityId }` plus an attachment build (`PW.Build`, `04-weapons.md`) for weapon slots.
   - A slot declares which kind it holds (`weapons`, `perks`, `equipment`, `streaks`, `wildcards`), a filter, and optionally `count`, `group`, `maxattachments`.
   - The loadout module stores, validates against slot declarations and gives the contents at spawn.
   - Default slot set (declared by built-in modules): primary, secondary, lethal, tactical, perk 1–3 (one group each), 3 killstreaks, wildcards.
   - A mode can replace the loadout: question hook `PW_PlayerLoadout(ply)` (Gun Game, Gunfight). If the mode returns a loadout, it is used instead of the player's class.

### Pick X

2. **Pick X is the base system: one budget per class.**
   - `match` setting `loadout.budget`, default 10; `0` = no budget (classic).
   - Everything picked costs points: weapons, attachments, perks, equipment, wildcards. Default `Cost = 1`; an author may set another value (for example a sniper rifle 2).
   - Cosmetic attachments (skins, stickers; `cosmetic` flag from the adapter) are free.
   - Killstreaks are outside the budget (BO2 style); their cost is in-match score.
   - Why per-item cost 1 works even with thousands of attachments: Pick X limits the **number** of items, not their power; power is balanced by the attachments' own pros and cons, which the bases already provide (as in BO2, where every attachment cost 1).

3. **Deep gunsmith with a per-weapon cap.** `match` setting `loadout.maxattachments`, default 5; the budget limits the build as well (5 attachments = half of 10 points).

4. **Perk groups.** A perk slot accepts only perks of its group; this prevents stacking similar perks. Wildcards may break the rule on purpose.

5. **Wildcards are a kind `wildcards/`.** A wildcard costs points and changes slot rules:

   ```lua
   -- wildcards/perk_greed.lua
   WILDCARD.Name = "Perk Greed"
   function WILDCARD:ModifySlots(slots)
       slots.perk1.count = 2                 -- two perks from group 1
   end

   -- wildcards/gunfighter.lua
   function WILDCARD:ModifySlots(slots)
       slots.primary.maxattachments = slots.primary.maxattachments + 1
   end
   ```

6. **Extension points.**
   - `PW_LoadoutCost(item)` (question hook): change the cost of any item, for example a pack makes every sniper rifle cost 2.
   - `PW_ValidateLoadout(ply, loadout)` (question hook): final check; the budget sum plus any module's own rules. Weight systems or stat caps can be added later as modules through this hook, without changing the base.

7. **Playlist examples** (all through settings, `02-modes.md` decision 2):

   | Playlist | Settings |
   | --- | --- |
   | Pick 10 (BO2) | `loadout.budget = 10`, `loadout.maxattachments = 3` |
   | Pick 15 Gunsmith | `loadout.budget = 15`, `loadout.maxattachments = 8` |
   | Classic | `loadout.budget = 0`, `loadout.maxattachments = 5`, wildcards disabled |

### Perks

8. **Perks: stat multipliers as data, events and free hooks through instances.**

   ```lua
   -- perks/lightweight.lua
   PERK.Group = 1
   PERK.Stats = { move_speed = 1.10, fall_damage = 0.5 }     -- multipliers

   -- perks/scavenger.lua
   function PERK:OnKill(owner, victim) end                   -- refill ammo
   ```

   - Perks are `KIND.Subscribe = "never"`; each equipped perk is an instance (`00-core.md` decision 11) living from spawn to death, loadout change or match end.
   - Passive numbers: `PW.Stat(ply, name, base)` multiplies the multipliers of the player's perks, wildcards and mode. Recomputed on spawn and loadout change, cached; nothing per tick. No caps in MVP (a module may add them through the same function later).
   - Convenience events called by the perks module only for the relevant owner: `OnEquip`, `OnUnequip`, `OnKill`, `OnDeath`, `OnDamaged`, `OnDealDamage`.
   - Unusual effects use `self:Hook` / `self:Timer` on the instance; cleanup is automatic.
   - Player stats (speed, health, fall damage, damage taken, damage dealt) are applied by the core and modules directly; damage is scaled once in the core damage hook. Weapon stats (`reload_time`, `draw_time`, `ads_time`, `sprint_to_fire`, `recoil`, `spread`) go through `PW.SetStatMods` and the adapter methods of `04-weapons.md` decision 6. A perk's description shows when a key is not supported by the base of the held weapon (`SupportedStatMods`).

### Killstreaks

9. **Killstreaks are a kind `streaks/`; activation is an instance.**

   ```lua
   -- streaks/uav.lua
   STREAK.Name     = "UAV"
   STREAK.Kills    = 4          -- cost when earned by kills
   STREAK.Score    = 500        -- cost when earned by score; default Kills × 100
   STREAK.Duration = 30

   function STREAK:OnEquip(owner)               -- activation (core decision 11)
       PW.Reveal.Team(owner, 3)
       self:Timer(self.Duration, 1, function() self:Remove() end)
   end

   function STREAK:BotShouldUse(bot) return true end
   ```

   - Earning: `match` setting `streaks.earn` = `kills` (CoD4) or `score` (MW2019; objective play is rewarded).
   - On death the streak counter resets; earned but unused streaks are kept. `match` setting `streaks.persist` (default off) keeps the counter; a perk may enable it for its owner (Hardline-like).
   - Kills made by streaks do not extend the streak (MW2019 rule); `match` setting `streaks.chain`, default off.
   - Earned streaks wait in an inventory; the player selects one with a dedicated key and activates it. Activation creates an instance; a streak that needs a held item (airstrike designator, laptop) gives a SWEP and removes it in `OnUnequip`.
   - Bots decide through `STREAK:BotShouldUse(bot)` (details in `07-bots.md`).
   - Killstreaks are outside the Pick X budget (decision 2).

10. **MVP killstreaks: UAV, Counter-UAV, precision airstrike** — three different effect types (radar reveal, radar jamming, area damage). AI-driven streaks (helicopters and similar) come after MVP.

### Equipment

11. **Equipment is just an item in a slot; its behaviour belongs to the item.**

    ```lua
    PW.Loadout.DeclareSlot("lethal",   { kind = "equipment", key = "pw_lethal" })     -- default G
    PW.Loadout.DeclareSlot("tactical", { kind = "equipment", key = "pw_tactical" })   -- default 4

    -- equipment/frag.lua
    EQUIPMENT.Count = 1
    function EQUIPMENT:OnUse(owner) PW.Throw(owner, "pw_frag", { cook = 4 }) end
    ```

    - A slot may declare an action key. On spawn the item becomes an instance (`00-core.md` decision 11); pressing the slot key calls `OnUse` on it. Bots call the same server-side, without keys.
    - The item does whatever it wants: throw a projectile, give a SWEP, deploy something, toggle a shield.
    - ~~Quick throw is a helper of a `throwables` module (`PW.Throw`); items may use it or not; the loadout module knows nothing about throwing.~~ Superseded for grenades by the revision below (2026-11-07). `PW.Throw` stays as a helper that the grenade SWEPs and bots may use for the projectile itself.
    - The same "slot + key + `OnUse`" pattern covers field upgrades: just another slot.
    - The concrete MVP equipment set is content, decided when filling content.

    **Revision 2026-11-07 (user decision 2026-11-07, after the first playtest): grenades are inventory items.**

    - Lethal and tactical grenades are weapons (SWEPs) in the player's weapon inventory. They are no longer quick-throw: the earlier quick-throw text above is superseded, not deleted.
    - The slot still holds an equipment item whose behaviour belongs to the item (the rule above is unchanged). What changed is the behaviour of the built-in `frag` and `flash`: instead of throwing at once they give a grenade SWEP to the owner.
    - Count = ammo of the grenade SWEP. It refills on spawn as before.
    - Bots switch to the grenade SWEP and throw it (the `throw_equipment` behaviour, `07-bots.md` decision 13).
    - Decided (confirmed by the user on 2026-11-07; the local manual checklist (not published) section 7, items 64 and 66): the slot keys G and 4 (gamepad d-pad down and left) switch to the grenade and do not throw at once; holding attack cooks it, capped at about 3 s; when the grenade count is empty the player returns to the previous weapon.
    - Grenade details, decided on 2026-11-07 (item 66): only an item with `Cook = true` cooks (the frag); the flash's fuse starts on release. The cook cap equals the frag fuse (3 s); reaching it drops the grenade at the feet with the minimum fuse. Switching weapons while cooking cancels the cook: nothing is thrown and no grenade is spent. After the last grenade the player returns to the previous weapon after 0.5 s. Weapon XP of a grenade kill goes to the grenade SWEP; when the thrower is dead at detonation, no weapon gets it. Grenades sit in GMod weapon slot 4. The only way to throw is releasing attack with the grenade in hand; bots go through `PW.Equipment.Use`. A perk or wildcard changes the count through `PW_EquipmentCount`, once per life.
    - Death while cooking (user change of item 66.3, 2026-11-07): the live grenade drops at the body, CoD-style, and goes off when its remaining fuse ends (the fuse less the time cooked, at least 0.1 s). The thrower stays the attacker, so kills count for them as with a normal throw.

### Classes

12. **Player classes: stored on the client, repaired on the server.**
    - Number of custom classes: `server` setting `loadout.classes`, default 10.
    - Stored on the client in `data/privatewar/classes.json`, so classes travel between friends' servers (progression trust model: forgeable, accepted).
    - On join the client sends its classes in one message through `PW.Net.Receive` with a size limit. The server checks each class (entities exist, budget, unlocks) and **repairs** it instead of rejecting it: an unavailable item is removed and its slot left empty.
    - Edits in the lobby or while dead send the changed class; it applies at the next spawn.
    - If match settings make a class invalid (for example a playlist sets a lower budget), the class is marked unavailable for that match, not silently trimmed.

13. **Addons define ready-made classes: a kind `classes/` (data).** Packs ship presets (for example "Assault", "Sniper"). Players can copy a preset into a custom class.

14. **Bots can use players' classes.**
    - `match` setting `bots.classes` (type `set`): sources a bot picks from — `preset` (the `classes/` kind) and `players` (custom classes of humans who joined this session), default both.
    - The `players` pool collects every human's valid custom classes during the session and keeps them after the player leaves (until the map changes).
    - A player's class was already validated for that player (including unlocks); a bot using it is not checked against progression, only against the current match settings (budget, bans).
    - Rationale: bots play with real community builds, which makes them feel less generic.

### Gunsmith server flow

15. **Applying a weapon build at spawn.**
    1. `ply:Give(class)`, then `ADAPTER:SuppressDefaultAmmo(wep)`; the core gives ammo (`../notes/08-weapon-adapters.md` §5, item 5).
    2. The cheap static check `ADAPTER:Validate(class, build)` runs **when a class is saved**, not at every spawn, so the player sees errors in the gunsmith immediately.
    3. `ADAPTER:Apply(wep, build)` returns what actually stuck (ARC9 and TFA can validate exactly only on a live weapon, §5 item 3).
    4. If something did not stick (a conflict visible only on the live weapon), the player spawns with what stuck, gets one message ("attachment X not installed: conflicts with Y"), and the class is repaired (decision 12).
    5. Bots follow the same path plus `ADAPTER:PrepareForBot`.

### Approved expansion

16. **Twelve additional perks** (user approval and delegated tuning, frozen by the coordinator,
    2026-11-08). These supplement, never replace or retune, Adrenaline, Ready Up, Sleight of Hand
    and Flak Jacket. The existing three groups and Pick X rules remain. Each new perk has
    `Cost = 1` and `Unlock = 1` for the initial release.

    | Group | Id / name | Frozen effect |
    | --- | --- | --- |
    | 1 | `stockpile` / Stockpile | One additional lethal and one additional tactical use, once per life |
    | 1 | `soft_landing` / Soft Landing | Ordinary fall damage multiplied by 0.5 once; no physics or routing changes |
    | 1 | `flash_guard` / Flash Guard | Ordinary flash strength and its derived duration multiplied by 0.5 |
    | 1 | `fleet_foot` / Fleet Foot | Ordinary walk/run baseline multiplied by 1.10; no jump, crouch, slide or special ADS-speed bonus |
    | 2 | `quick_draw` / Quick Draw | Weapon draw time multiplied by 0.75 where the adapter supports `draw_time` |
    | 2 | `sightline` / Sightline | ADS transition time multiplied by 0.8 where the adapter supports `ads_time` |
    | 2 | `recoil_control` / Recoil Control | Weapon recoil multiplied by 0.8 where the adapter supports `recoil` |
    | 2 | `scavenger` / Scavenger | Eligible direct enemy weapon kill restores half a magazine of that weapon's ordinary reserve |
    | 3 | `quiet_steps` / Quiet Steps | Mutes stock human footsteps and their matching bot-hearing stimulus |
    | 3 | `ghost` / Ghost | Conceals the owner from every deliberate `PW.Reveal` source |
    | 3 | `retaliation` / Retaliation | Eligible attacker with current LOS is revealed for 1.5 seconds, at most once per 5 seconds |
    | 3 | `continuity` / Continuity | Keeps existing earned streak progress through death; unused inventory is unchanged |

    - All effects, eligibility rules and lifecycle boundaries are identical for human and bot owners.
      Recoil changes the weapon property, never difficulty or an additional compensation multiplier.
      Draw/ADS/recoil use the composed cached weapon-mod table, not partial `SetStatMods` calls.
      Only ARC9 currently supports these keys; HL2 fallback supports none. TFA and MW Base are
      absent, not compatible by assertion. The class UI warns for the selected unsupported base.
    - Scavenging adds `max(1, floor(capacity / 2))`, capped at three ordinary reserve magazines per
      ammo type. Shared ammo is deduplicated. No clip refill, grenade supply, ally kill, suicide,
      world kill, autonomous streak kill or delayed nonweapon kill qualifies. Provenance must not
      attribute an unrelated held weapon merely because a player caused the damage. Existing
      player XP is unchanged; no unrelated held-weapon XP is awarded for a streak kill.
    - Equipment composition preserves the existing `PW_EquipmentCount` first-answer result, then
      applies new owner-local additive sources in sorted source-id order. It is resolved once per
      life; the cached count and grenade ammo are authoritative afterward. No midlife refill.
    - Quiet Steps does not hide gunfire, sight or remembered contacts. Unsupported custom weapon
      movement sounds are outside stock-footstep coverage; the description says so.
    - Ghost filters targets before both human position packets and bot stimuli, for UAV, retaliation,
      sensors and every other deliberate reveal. CUAV remains independent and unchanged. Visual,
      sound and damage awareness and already-existing contacts are not removed.
    - Retaliation requires a living enemy direct-player-weapon attacker and current LOS. It uses
      the owner's existing `PW.Streaks.Viewer` and `PW.Reveal`, respecting Ghost and CUAV; it is a
      bounded event-time pulse, never a continuous hidden-position stream.
    - Continuity snapshots persistence before perk cleanup under either death-listener order.
      It does not discount thresholds, loop earnings, chain streak kills or change unused inventory.
    - Movement composes multiplicatively through the public player-overrides owner, relative to
      the ordinary baseline. It preserves independent role health/speed overrides and never heals
      during refresh or compounds an already-modified speed. Flash resistance precedes the same
      ordinary human/bot impairment and derives duration from the resolved strength once.

    Implementation and mounted acceptance are tracked separately; this decision is not a pass claim.

## Interfaces

TBD.

## Performance budget

TBD.

## Security

TBD.

## Open questions

1. ~~Perk dispatch~~ Closed: decision 8; weapon stat modifiers: `04-weapons.md` decision 6.
2. ~~Equipment~~ Closed: decision 11.
3. ~~Killstreaks~~ Closed: decisions 9 and 10.
4. ~~Classes~~ Closed: decisions 12 and 13.
5. ~~Gunsmith server flow~~ Closed: decision 15.
6. ~~Bot loadouts~~ Closed: decision 14 (selection logic inside the bot brain: `07-bots.md`).
