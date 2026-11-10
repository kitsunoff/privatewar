# Loadout API: slots, validation, resolution, giving on spawn

Status: added after T-4.1 (2026-11-07); extended after T-4.2 (Pick X: budget, costs, attachment cap, bans), T-4.4 (perk slots, `PW_LoadoutGiven`), T-4.5 (the equipment slots), T-4.6 (streak slots) and T-4.7
(classes) and T-4.8 (the gunsmith flow). Read current code/types alongside this contract; decided design takes
precedence and actual conflicts must be reported.

Module `loadout` (`lua/privatewar/modules/loadout/`: `shared.lua` slots, pure rules, questions and resolution;
`sh_budget.lua` Pick X arithmetic and rules, `sh_classes.lua` and `sh_classes_repair.lua` the pure part of classes,
`sh_class_visibility.lua` human picker policy,
`sv_classes.lua` and `cl_init.lua` the class glue, `init.lua` giving weapons on spawn, server). Types: `lua/privatewar/types/loadout.lua`. Source decisions:
`design/05-loadout.md` d.1 to d.3, d.6, d.7, `design/01-extensibility.md` d.9. It sits on top of `core.md` (`PW.Ask`, registries,
`PW.HookFor`) and `adapter.md` (`PW.WeaponAmmo.Give`, ammo) and does not repeat them.

The module knows nothing about perks, streaks or equipment (it does own the wildcard slot, see "Wildcards"): other modules declare their own slots
(the equipment module declares `lethal` and `tactical`, see "Slots"; perks and streaks are T-4.4 and T-4.6). The Pick X
rules are in "Pick X", classes in "Classes". The class editor/gunsmith are implemented in
`screens/loadout_editor.lua`, `screens/loadout_gunsmith.lua` and `modules/loadout_ui/`.

## Concepts

- **Slot**: what a loadout holds at one place, declared by a module (`PW.LoadoutSlotDecl`).
- **Loadout** (`PW.Loadout`): a table from slot id to an entity id, or to a list of ids for a slot with `count > 1`.
  Example: `{ primary = "weapon_smg1", secondary = "weapon_pistol", melee = "weapon_crowbar" }`. The reserved key
  `builds` is not a slot: it holds the attachment builds of the weapon slots (see "Pick X").
- **Class**: the loadout a player chose, stored per player (`SetClass`); a pick through the LOADOUT tab sets it (see "Classes").

## Slots

```lua
PW.Loadout.DeclareSlot("primary", { kind = "weapons", filter = { "ar", "smg", "lmg", "sniper", "shotgun" } })
```

| Field | Type | Meaning |
| --- | --- | --- |
| `kind` | string | Required, non-empty: the kind the items come from (`"weapons"`, `"perks"`, `"equipment"`, ...) |
| `filter` | `string[]?` | Allowed values; `nil` allows any item |
| `count` | integer? | Positive integer, how many items the slot holds; default 1 |
| `maxattachments` | integer? | The attachment cap of a weapon slot; wins over the setting `loadout.maxattachments` (see "Pick X") |
| `group`, `label`, `key` | various | Carried for other modules (perk group, display name, action key); the loadout module does not read them |

A filter entry matches the `Category` of the item or, when the item has no `Category`, its `Kind` (the filter of the
secondary slot names `"launcher"`, which is a `Kind` of the adapter, next to categories; the crowbar has a `Kind`
only).

Built-in slots, declared in this order (the order of giving):

| Slot | Kind | Filter |
| --- | --- | --- |
| `primary` | `weapons` | `ar`, `smg`, `lmg`, `sniper`, `shotgun` |
| `secondary` | `weapons` | `pistol`, `launcher` |
| `melee` | `weapons` | `melee` |

`melee` is added by the lane agent and is not in the design: the HL2 fallback loadout needs a place for the crowbar.

The equipment module (T-4.5, `equipment.md`) declares two more slots after these, on `PW_RegistriesLoaded` (it loads
before this module, so it declares again once every registry is loaded):

| Slot | Kind | Filter | Key | Label |
| --- | --- | --- | --- | --- |
| `lethal` | `equipment` | `lethal` | `pw_lethal` | `#pw.slot.lethal` |
| `tactical` | `equipment` | `tactical` | `pw_tactical` | `#pw.slot.tactical` |

The perks module (T-4.4, `perks.md`) declares `perk1`, `perk2`, `perk3` (kind `perks`, `group` 1 to 3, no filter) and the
streaks module (T-4.6, `streaks.md`) declares `streak1`, `streak2`, `streak3` (kind `streaks`, no filter), both again on
`PW_RegistriesLoaded`. The wildcard slot is declared by this module.

| Function | Contract |
| --- | --- |
| `PW.Loadout.DeclareSlot(id, decl) -> boolean, string?` | Declares a slot, or re-declares it keeping its position. `false` and a reason when the id is not a non-empty string, `kind` is missing, `filter` is not a list of strings or `count` is not a positive integer |
| `PW.Loadout.GetSlot(id) -> PW.LoadoutSlot?` | A copy of the slot (with `id`), or `nil` |
| `PW.Loadout.GetSlotIds() -> string[]` | Slot ids in declaration order |
| `PW.Loadout.RemoveSlot(id) -> boolean` | Removes a slot (tests, a module that goes away); `true` when it existed |

The slot store survives a reload, so slots declared by other modules are not lost.

## Validation

`PW.Loadout.Validate(ply, loadout, lookup?) -> boolean, string?`: the checks run in this order and the first failure
wins. Returns `true`, or `false` and a reason.

1. The slot rules, per key in sorted order (the key `builds` is skipped here).
2. The Pick X rules (`PW.Loadout._Extras`), in this order: the structure of `builds`, the bans (including Hidden
   attachments), the attachment cap, the budget. Each failure has its own reason string.
3. The question `PW_ValidateLoadout` (only when 1 and 2 passed).

Slot rules (each gives a reason string):

1. The slot id must be declared (`unknown slot <id>`).
2. The value must be a string or a non-empty list of strings.
3. The list must not be longer than the slot's `count`.
4. Every item must exist in the slot's `kind` (`lookup(kind, id)` returns an entity; the default reads
   `PW.Registries[kind].Get(id)` and requires a valid entity) and fit the filter.

`lookup` is injected in tests (`PW.LoadoutLookup`).

## Pick X

Source: `design/05-loadout.md` d.2, d.3, d.6, d.7 and `design/04-weapons.md` d.5; code `modules/loadout/sh_budget.lua`.

**The `builds` key.** `loadout.builds = { [weaponSlotId] = { [buildSlot] = optionId | false } }`: for each weapon slot the
chosen option per attachment slot of its weapon (`false` = cleared). Structure rules: `builds` is a table; every key is a
declared slot of kind `weapons` that holds a weapon in the loadout; each build is a table; every option is a string or
`false`. A build of a slot with `count > 1` belongs to the first weapon of the slot.

**Settings** of the module (declared in `shared.lua`; names follow the task, the design draft says `bannedatts`):

| Full id | Type | Default | Range | Meaning |
| --- | --- | --- | --- | --- |
| `loadout.budget` | int | 10 | 0..100 | Total cost allowed; `0` = unlimited |
| `loadout.maxattachments` | int | 5 | 0..20 | Attachments per weapon slot, when the slot declares no `maxattachments` |
| `loadout.bannedweapons` | set | empty | | Banned weapon classes |
| `loadout.bannedattachments` | set | empty | | Banned attachment option ids |

**Costs.**

- An item costs its `Cost` field, else `1`. For an attachment the `Cost` of its `Attachments` entry (`adapter.md`).
- Free, and not counted toward the cap: an attachment whose entry has `Cosmetic = true`, an option listed in `Camos`,
  and an option or build slot the adapter reports as cosmetic (`cosmetic = true`). A cleared option (`false`) is neither.
- Killstreaks (kind `streaks`) are outside the budget and cost nothing. Picks that are not in the catalogue are
  skipped by the cost (the slot rules reject them).

**Question `PW_LoadoutCost(item)`** (through `PW.Ask`: a module listener first, the active mode's method as the default). A
number `>= 0` replaces the cost of the item; any other answer is ignored. Not asked for free cosmetic attachments.
`item` fields:

| Field | Meaning |
| --- | --- |
| `kind`, `id` | Kind of the slot and the entity id (for an attachment: kind `"attachment"`, `id` the option id) |
| `slot` | The loadout slot id |
| `entity` | The entity table (for an attachment: the weapon) |
| `cost` | The cost so far (`Cost` or `1`) |
| `attachment`, `weapon`, `cosmetic`, `hidden` | Attachments only: the option id, the weapon id, the cosmetic flag, the `Hidden` flag |

**Rules.**

- Bans use the bare id: the weapon class against `loadout.bannedweapons`, the option id against
  `loadout.bannedattachments`. A `Hidden` attachment is rejected like a banned one.
- The cap per weapon slot is the `maxattachments` of the slot declaration when it has one, else the setting.
- The budget is checked only when `loadout.budget > 0`.

| Function | Contract |
| --- | --- |
| `PW.Loadout.Cost(loadout, lookup?) -> number` | The total Pick X cost of a loadout under the live settings (slots in sorted order; streaks skipped; cosmetic attachments free; `PW_LoadoutCost` applied). `lookup` defaults to the registries |

## Questions

Both go through `PW.Ask`, so a module listener answers first and the active mode's method is the default
(`core.md` "Hook dispatch").

| Hook | Arguments | Answer |
| --- | --- | --- |
| `PW_PlayerLoadout` | `ply` | A table replaces the player's class (Gun Game, Gunfight). **The mode is trusted: the table is not validated.** Any other answer is ignored |
| `PW_ValidateLoadout` | `ply, loadout` | `false` rejects (reason `rejected by PW_ValidateLoadout`); a string rejects with that string as the reason; anything else accepts. Asked only after the slot rules and the Pick X rules passed |
| `PW_LoadoutCost` | `item` | A number `>= 0` replaces the cost of one pick; see "Pick X" |

## Resolution and class

| Function | Contract |
| --- | --- |
| `PW.Loadout.Resolve(ply) -> PW.Loadout, string` | The loadout for the player now and its source: `"mode"` (the table `PW_PlayerLoadout` answered), else `"class"` (`GetClass`), else `"default"` |
| `PW.Loadout.Default() -> PW.Loadout` | A fresh copy of the default loadout: `weapon_smg1` (primary), `weapon_pistol` (secondary), `weapon_crowbar` (melee) for everyone, a gameplay value. While the slots of other modules are declared it adds their defaults: `lethal = "frag"`, `tactical = "flash"`, `perk1 = "ready_up"`, `perk2 = "sleight_of_hand"`, `perk3 = "adrenaline"`, `streak1 = "uav"`, `streak2 = "counter_uav"`, `streak3 = "airstrike"` |
| `PW.Loadout.SetClass(ply, loadout?)` | Stores the player's class; `nil` clears it. **Not validated** here (the class glue repairs and checks before it calls this, see "Classes"). Weak-keyed by player |
| `PW.Loadout.GetClass(ply) -> PW.Loadout?` | The stored class |

## Giving on spawn (server)

`PW.Loadout.Give(ply, loadout) -> string[]`: strips the player's weapons and ammo, then, for every slot of kind
`weapons` in declaration order, gives each item through `PW.WeaponAmmo.Give(ply, class)` (`adapter.md`: default ammo
suppressed, the configured spare magazines added). Items that `Give` refuses are skipped. The first class given is
selected. After the weapons are given, the build of each weapon slot is applied to the first weapon of the slot (T-4.8, see
"Gunsmith (T-4.8)"), and a bot's weapons get `PrepareForBot`. Returns the classes given. Slots of other kinds are ignored here (their modules give them: the equipment module equips `lethal` and `tactical` on
spawn). At the end it notifies `PW_LoadoutGiven(ply, loadout)` (through `PW.Notify`) with the loadout that was given; the
perks module recomputes on it (`perks.md`), and it is the only trigger for that. It fires on the spawn in LIVE and when a mode gives a new loadout.

The engine hook `PlayerLoadout` (called by the base `GM:PlayerSpawn`) is answered by the module, through
`PW.HookFor`:

- In `LIVE` it resolves the loadout, gives it and returns `true`, so the base gamemode's own `PlayerLoadout` never runs
  (no extra base weapons on respawn).
- In any other phase (`LOBBY`, `PREMATCH`, `POSTMATCH`, `VOTE`), or without the match module, it answers nothing and the
  base behaviour stays.

## Classes

Source: `design/05-loadout.md` d.12 and d.13; code `modules/loadout/sh_classes.lua`, `sh_classes_repair.lua`,
`sh_class_visibility.lua`,
`sv_classes.lua`, `cl_init.lua`, kind `classes` (`kinds/classes.lua`), screen `screens/loadout_classes.lua`. Types:
`lua/privatewar/types/loadout_classes.lua`.

**Where classes come from.** Presets are data files in `lua/privatewar/classes/` (kind `classes`: folder `classes`, class
table `CLASS`, never auto-subscribed, required `Name` string and `Loadout` table, optional `Description` and
`Hidden: boolean` (default false); enable ConVar
`pw_class_<id>_enabled`; registry `PW.Classes`). Custom classes are the player's own, in the client file
`data/privatewar/classes.json`, so they travel between servers. File format:

```json
{ "version": 1, "classes": [ { "name": "Mine", "loadout": { "primary": "weapon_ar2", "secondary": "weapon_pistol" } } ] }
```

**Human visibility (T-11.15).** The class editor/customization list contains custom classes only. Human selection
lists (lobby, pause and death/respawn) show custom classes first, then visible presets, retaining order within each
category without mutating the source tables. `Hidden = true` removes a code preset from every human picker and
server-side id selection. Hidden presets remain registered and accessible through `PW.Classes.Get(id)`;
trusted technical code may use their `Loadout`, including from `PW_PlayerLoadout`. `Abstract` and enable semantics
are unchanged. The existing bot pool still admits enabled presets only when `bots.classes` permits presets and
match validation passes, regardless of `Hidden`; hiding grants no additional bot permission.

The human upload/save wire carries raw custom loadouts, not preset ids or a trusted bot/technical flag. A hidden
preset ref cannot be selected by saving/uploading, forging a pick, or using a bot sender on the human net path.
An old selected ref that now names a hidden preset is cleared to the default loadout on refresh/upload/pick;
custom slot contents, builds and progression checks are unchanged. Equivalent custom contents are not prohibited:
visibility is id permission, not content DRM. No new messages or unbounded tables are introduced.

`_ClassesFromJson` reads only `classes` (`version` is not checked). Per class it keeps the structure the wire can carry
(slot id to an id or a list of ids, `builds` to slot to build slot to an id or `false`), drops a class whose loadout is
empty after that, names a nameless class `Class <n>` and cuts the name to `PW.Loadout.ClassNameMax` (32) characters. At
most `loadout.classes` classes are read.

**Setting.** `loadout.classes` (int, scope `server`, default 10, range 1 to 20): custom classes per player. The client
reads it for its own cut, the server cuts again.

**Built-in presets** (all with `lethal = "frag"`, `tactical = "flash"`, three perks and the streaks `uav`, `counter_uav`, `airstrike`; Pick X cost 8 at the default costs, budget 10: the budget change of T-4.4, the three perks cost 1 each and streaks are free, so presets and the default loadout now cost 8 of 10):

| Preset (id) | primary | secondary | melee | perk1 | perk2 | perk3 |
| --- | --- | --- | --- | --- | --- | --- |
| Assault (`assault`) | `weapon_ar2` | `weapon_pistol` | `weapon_crowbar` | `flak_jacket` | `sleight_of_hand` | `adrenaline` |
| Close quarters (`close_quarters`) | `weapon_shotgun` | `weapon_357` | `weapon_crowbar` | `ready_up` | `sleight_of_hand` | `adrenaline` |
| Run and gun (`run_and_gun`) | `weapon_smg1` | `weapon_pistol` | `weapon_crowbar` | `ready_up` | `sleight_of_hand` | `adrenaline` |

There is no Marksman preset: the HL2 crossbow has the category `special`, which no weapon slot accepts.

**Refs.** A class is addressed by a ref: `preset:<id>` (lowercase letters, digits, underscore) or `custom:<n>` (n 1 to 99,
the position in the uploaded list). `PW.Loadout._ParseRef(ref)` returns `"preset"` or `"custom"` and the id or the
number, or `nil, nil`.

**Wire.** Explicit encoding (never `net.WriteTable`); every count is bounded by its bit width, so a forged message cannot
make the reader loop. A loadout is: `uint(4)` slot count, per slot a string id, `uint(3)` item count and the item ids;
`uint(3)` build count, per build a string slot id, `uint(5)` option count, per option a string build slot, a bool "has
option" and the option id when it has one (`false` = cleared).

| Message | Direction | Rules | Content |
| --- | --- | --- | --- |
| `pw_loadout_classes` | client to server | `PW.Net.Receive`, any player, 0.5 per second, at most `ClassesMaxBytes` (16384) | `uint(5)` class count, per class a string name and a loadout. Sent on `InitPostEntity` from `classes.json`; the client leaves out trailing classes until the payload fits and prints a line per class left out |
| `pw_loadout_pick` | client to server | any player, 4 per second, 64 bytes | one string, a class ref |
| `pw_loadout_class_state` | server to client | | the state: string `selected` ref (empty when none), `uint(6)` entry count, per entry: string ref, string name, bool available, string reason (empty when none), `uint(5)` removed count and the strings, a loadout (the repaired one) |

`PW.Loadout._EncodeClasses`, `_DecodeClasses(reader, max)`, `_EncodeClassState` and `_DecodeClassState` are the pure
codecs over a writer or reader of plain functions (`_NetWriter` and `_NetReader` are the net ones), so tests round-trip
them.

**Repair** (`PW.Loadout._RepairClass(slots, loadout, ctx) -> repaired, removed`; decisions of the lane agent, 05 d.12
leaves the split open). Repair removes whatever is wrong regardless of the budget and lists each removal as
`<id> (<why>)`:

- an unknown slot (`unknown slot`);
- an item that is not an id or a list of ids (`not a list of ids`), is unknown or disabled in its kind (`not available`),
  does not match the slot filter (`does not fit <slot>`), is a weapon in `loadout.bannedweapons` (`banned`), or exceeds
  the slot count (`too many in <slot>`);
- in `builds`: an attachment option that is banned (`banned`) or `Hidden` (`not available`); the build of a weapon that was
  removed goes with it. A `false` (cleared) option is kept.

Since T-4.8 the build of each weapon also goes through `PW.Loadout._ValidateBuild` (see "Gunsmith (T-4.8)"), which
removes options the adapter does not offer, locked options, conflicts and options over the progression limit. Over the
budget or over the match attachment cap does not repair: it only marks the class unavailable (05 d.12: "marked
unavailable, not silently trimmed").

**Availability** (`PW.Loadout._ClassStatus(slots, loadout, ctx, check?)` returns `{ loadout, removed, available, reason? }`):
the repaired class is available unless it has no item left (reason `the class is empty`) or the final check fails (the
reason is the check's). The final check on the server is `_Validate` (slot rules and Pick X) followed by `_AskValidate`.

| Function | Contract |
| --- | --- |
| `PW.Loadout.ClassState(ply)` | Server. Uploaded custom classes first, then enabled visible presets in registry order, each repaired and checked under the current settings: `{ selected, entries = { { ref, name, loadout, removed, available, reason? } } }` |
| `PW.Loadout.RefreshClasses(ply)` | Server. Recomputes the state; when the player has picked a class, sets it as the class when it is available and clears it (back to the default loadout) when it is not; sends the state; returns it |
| `PW.Loadout._OnClasses(ply, classes)` | Server. Stores the upload (cut to `loadout.classes`) and refreshes |
| `PW.Loadout._OnPick(ply, ref) -> boolean` | Server. An available class becomes the pick and the player's class (used from the next spawn through `Resolve`); an unavailable, unknown or malformed ref is refused and the previous pick stays. The state is sent either way. Returns whether the pick was taken |
| `PW.Loadout._AskValidate(ply, loadout) -> boolean, string?` | The `PW_ValidateLoadout` question on its own: `false` with a reason when a listener rejected, else `true` |
| `PW.Loadout.GetClassState()` | Client. The last state received, `nil` before the first answer |
| `PW.Loadout.UploadClasses()` | Client. Reads `classes.json` and sends `pw_loadout_classes` |
| `PW.Loadout.SendPick(ref)` | Client. Sends `pw_loadout_pick` |
| `PW.Loadout._HumanClassEntries(entries, customOnly, lookup)` | Pure. Fresh stable custom-first list; when `customOnly` is true, no presets. `lookup(id)` supplies preset metadata; `Hidden = true` is omitted. Entry objects and loadouts are never changed |
| `PW.Loadout.HumanClassState(state, customOnly?)` | Shared wrapper using public preset metadata. Fresh filtered state; selected is empty if absent from the filtered entries. Used by client state, preview/editor cards and in-match selectors |
| `PW.Loadout._ClassCards(state, customOnly?)`, `_ClassRows(entry)` | Human-filtered card model (editor passes `customOnly = true`; badge `N/A` when unavailable, else `IN USE` for the selected one; text is the reason, else `Removed: ...`; tag `Preset` or `Custom class`) and the pure content rows of a class (slot id upper-cased and the item names; one `<SLOT> ATTACHMENTS` row per build with the option count) |

A class that becomes unavailable because the match settings changed (for example a playlist lowers the budget) is kept
and shown `N/A`; the player gets the default loadout for that match. The state is sent again one frame after every
`PW_PhaseChange` to each player who uploaded, because the settings snapshot is taken on entering `PREMATCH` and dropped
in `LOBBY`. Unlock checks (T-4.9, `progression.md`): the server builds the `PW.LoadoutContext` of each player with two extra
fields, `isUnlocked(kind, id) -> boolean` (an item whose slot kind is not unlocked is removed) and
`lockedOptions(weaponId, build) -> table<string, boolean>` (attachments and camos of a weapon build the player has not
unlocked are dropped), and since T-4.8 `attachmentLimit(weaponId)`, see "Gunsmith (T-4.8)". The first two are absent (nothing is locked) when the progression module is missing. Repair marks every
removal with the reason `locked`, shown like the other "Removed by the server" reasons. A class is re-checked on every
`RefreshClasses`, so a new unlock or a level-up is applied the next time the classes are refreshed, not instantly. Not done
yet: partial upload (only the full list is sent). The class editor is implemented; see the paths above.

## Gunsmith (T-4.8)

Source: `design/05-loadout.md` d.12 and d.15; code `modules/loadout/sh_gunsmith.lua` (pure), `sv_gunsmith.lua` (server glue),
`sh_classes_repair.lua` and `sv_classes.lua` (where it plugs in), `init.lua` (`Give`). Types: `lua/privatewar/types/loadout.lua`.
A weapon build is `loadout.builds`, part of a class (see "Pick X"). The class editor UI is T-7.4; this is the server side.
There are **no new net messages**: the reasons travel in `pw_loadout_class_state` (the `removed` strings of an entry).

**Principle.** The server removes the offending option and keeps the class (05 d.12: repair, not reject); the class stays
available. It is the only place where the adapter's catalogue (`adapter.md`) meets a class.

### Validating a build on save

`PW.Loadout._ValidateBuild(weaponId, weapon, build, ctx) -> clean, problems` (pure). `_RepairClass` calls it for every build
after the old bans and Hidden checks. It returns the build without the offending options and a list of
`{ slot, option, why }`; each becomes a `<option> (<why>)` line in the entry's `removed`. The checks run in this order, and
an option removed by one is not seen by the next:

| Order | Reason | Source | Meaning |
| --- | --- | --- | --- |
| 1 | `not available` | `ctx.adapterOptions(weaponId, build)` | The adapter does not offer the option in that build slot (unknown, gone from the catalogue, or a weapon without a gunsmith: the HL2 fallback offers nothing) |
| 2 | `locked` | `ctx.lockedOptions`, one option at a time | The curated `Unlock` of the option is not reached. The count limit is not judged here |
| 3 | `conflict: <code>` | `ctx.adapterValidate(weaponId, build)` (`ADAPTER:Validate`) | The adapter's static check rejects the build slot; `<code>` is its reason code (just `conflict` when it gave none) |
| 4 | `over the limit` | `ctx.attachmentLimit(weaponId)` | More uncurated, non-cosmetic options than the progression limit, trimmed in build slot order |

A missing context field skips its check. A `false` (cleared) option is never touched. An option is "counted" toward the
limit unless its attachment entry has an `Unlock` or `Cosmetic = true`, it is a camo, or the adapter reports it cosmetic.

### Two limits

The attachment count a build meets is `min(progression, match cap)`, but the two are handled differently:

- **Progression** (`ctx.attachmentLimit`, the weapon level) **trims**: options past it are removed as `over the limit`.
  The limit is `nil` (no trimming) with `progression.unlockall` or for a weapon not in the catalogue.
- **Match cap** (`loadout.maxattachments` or the slot's `maxattachments`, plus what wildcards add through `_EffectiveSlots`,
  for example `gunfighter`) **marks the class N/A** (`Pick X` rules in `sh_budget.lua`); nothing is trimmed.

This changes the behaviour before T-4.8: `lockedOptions` used to cut the count by the match cap and ignored `gunfighter`.
Now it judges the curated `Unlock` only, and the count belongs to the two limits above.

### `PW.LoadoutContext` fields

| Field | Meaning |
| --- | --- |
| `adapterOptions(weaponId, build) -> table<buildSlot, table<optionId, true>>` | The options the weapon's adapter offers per build slot (`GetSlots` with the build, then `GetOptions` per slot). Absent: check 1 is skipped. Server: `PW.Loadout._AdapterOptions` |
| `adapterValidate(weaponId, build) -> table<buildSlot, code>` | The rejected build slots of `ADAPTER:Validate` with their codes (a copy of the build is passed). Absent: check 3 is skipped. Server: `PW.Loadout._AdapterValidate` |
| `attachmentLimit(weaponId) -> integer?` | The progression count limit; `nil` means none. Set in `sv_classes.lua` `contextFor` only when the progression module exists |

`PW.Loadout._GunsmithContext(ctx)` adds the first two to a live context. The context is built per player on every
`ClassState`.

### Applying on spawn: Give and "not installed"

`PW.Loadout.Give` calls `PW.Loadout._GunsmithOnGive(ply, loadout, firsts)` after the weapons are given, then
`PW.Loadout._PrepareForBot(ply, entities)`:

- **Apply.** For each weapon slot with a non-empty build, the build is applied to the first weapon of the slot through
  `ADAPTER:Apply(wep, build)` (`adapter.md`), which returns what stuck. `PW.Loadout._NotStuck(build, stuck)` lists the
  options that did not.
- **Has gunsmith.** `PW.Loadout._HasGunsmith(weaponOrClass)` is true when the weapon's adapter has `Apply`. A weapon
  without it (the HL2 fallback) is skipped: nothing is applied and a debug line is printed with `pw_debug 1`; spawning
  works.
- **PrepareForBot.** For a bot, `ADAPTER:PrepareForBot(ply, wep)` is called once per `Give` for each given weapon (before
  this task nothing called it).
- **notInstalled.** Options that did not stick (a conflict only a live weapon shows) are reported once to a human player in
  one chat line `[PW] Attachments not installed (they conflict on the weapon): <weapon>: <options>` (not to a bot), and
  are remembered per player and class ref in `PW._LoadoutClasses.notInstalled`. `statusOf` drops them with
  `PW.Loadout._DropOptions(loadout, drops, "not installed")`, so the class list shows `<option> (not installed)` and the
  next spawn does not try them again (no second message).
- **Which class.** Only the class the player picked is repaired after spawn (`store.picks[ply]` and the loadout equal to
  `GetClass`). A loadout from the mode or the default is reported but not changed.
- **Lifetime.** The marks live until the classes reload: a new class upload (`_OnClasses`, a reconnect) clears them; a
  `pw_reload` keeps them (the store is carried over).

| Function | Contract |
| --- | --- |
| `PW.Loadout._ApplyBuilds(loadout, weapons, api) -> PW.GunsmithFailure[]` | Pure over an injected `api` (`gunsmith`, `apply`, `debug`, `tell`, `name`): applies each slot's build, returns `{ slot, weapon, options }` per failure |
| `PW.Loadout._NotInstalledText(failures, nameOf) -> string` | The chat line |
| `PW.Loadout._DropOptions(loadout, drops, why) -> loadout, removed` | A copy without the dropped options (`drops[slotId][option] = true`), and `<option> (<why>)` lines; an emptied build or `builds` is removed |
| `PW.Loadout._GunsmithOnGive(ply, loadout, weapons, api?)` | Server. Apply, tell, remember |
| `PW.Loadout._PrepareForBot(ply, given)` | Server. `PrepareForBot` for each weapon of a bot |

Mandatory case (`TASKS.md` T-4.8): validation on save; partial application repairs the class and sends one message. The
manual checks need ARC9, TFA or MW enabled: the local manual checklist (not published), section 31.

## Wildcards

Source: `design/05-loadout.md` d.5; code `modules/loadout/sh_wildcards.lua` and `init.lua`, kind `wildcards`
(`kinds/wildcards.lua`, registry `PW.Registries.wildcards`, folder `lua/privatewar/wildcards/`, ConVar
`pw_wildcard_<id>_enabled`, never auto-subscribed). Types: `lua/privatewar/types/wildcards.lua`.

The loadout module declares the slot `wildcard` (kind `wildcards`, `count` 2, so up to two wildcards). A `WILDCARD` table
has `Name` and `ModifySlots(slots)` (required) and `Description`, `Cost` (Pick X, default 1), `Stats` (optional).

| Function | Contract |
| --- | --- |
| `PW.Loadout._EffectiveSlots(slots, loadout, lookup, defaultCap?)` | Pure. The declared slots when the loadout has no wildcard, else a copy changed by each wildcard's `ModifySlots` in pick order (each id once). An unknown wildcard is ignored here (the slot rules reject it); a `ModifySlots` that errors is skipped whole; the wildcard slot itself stays as declared; a wildcard may add a slot (key = id). `defaultCap` (the setting) fills `maxattachments` of weapon slots that declare none, so a wildcard can add to it |
| `PW.Loadout._WildcardError(slots, loadout)` | Pure. A reason when the same wildcard is picked twice |
| `PW.Loadout._WildcardStats(ids, lookup)` | Pure. The `Stats` tables of the wildcards among `ids` |

`_Validate`, `_Cost` and `_RepairClass` judge the loadout by the effective slot set, so validation, the budget (a wildcard
costs its `Cost`, and the extra picks it allows cost as usual) and the class repair agree. The perk group rule uses it too.
`ModifySlots` uses a local `pcall` on a scratch copy, not `PW.Call`: a thrown error discards that transform's edits,
but does not permanently disable the wildcard. It must be deterministic and side-effect-free.
An effective new slot being valid does not prove runtime support: `PW.Loadout.Give` currently iterates declared
slot order. A new runtime slot requires explicitly owned giving/UI/wire consumers and tests. Existing-slot count,
filter and cap changes should not be generalized into a claim that every new effective slot is equipped.
Stats: on `PW_LoadoutGiven` the module stores the player's wildcards and `PW.Perks.StatSource("wildcards", fn)` returns
their `Stats` (the perks module recomputes). Samples: `overkill` (secondary also takes primary categories), `perk_greed`
(`perk1` count +1) and `gunfighter` (`primary.maxattachments` +1, `Stats = { recoil = 0.95 }`), each costs 1. The perks module judges the group rule by the effective slots too, see `perks.md`.
Bots take classes through `PW.Loadout.SetClass`, see `bots-blackboard.md` item 13.

## Internal

`PW.Loadout._Validate(slots, loadout, lookup, ctx?)` (with a context it also runs the Pick X rules), `_Extras`, `_Cost`,
`_Context`, `_LiveContext`, `_Matches(slot, entity)`, `_Items(value)` and
`_OnPlayerLoadout(ply)` are pure helpers and the hook body, for tests. `PW._Loadout` is the store (`slots`, `order`,
`classes`); `PW._LoadoutClasses` is the server class store (`uploads`, `picks` and the injectable `read`, `readPick`,
`send`, `context`, built by `PW.Loadout._NewClassStore`); `PW.Loadout._ClientView` holds the client state.

## Mandatory cases

`TASKS.md` T-4.1: a module-declared slot appears; a wrong kind in a slot is rejected; the filter is respected;
`PW_PlayerLoadout` from the mode replaces the class.

`TASKS.md` T-4.2: the budget sum; budget 0 is unlimited; cosmetic attachments are free; the `PW_LoadoutCost` override;
`maxattachments`; a banned weapon or attachment is rejected.

`TASKS.md` T-4.3: `ModifySlots` changes validation; the budget counts wildcards; removing the wildcard restores the slots; an
invalid combination is rejected (`wildcards.lua`).

`TASKS.md` T-4.7: repair removes unavailable items and keeps the rest; an oversized upload is rejected before the handler;
a class is marked unavailable when a playlist lowers the budget; the presets pass `Validate` at the default budget and
each carries a lethal and a tactical.
