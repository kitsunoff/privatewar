---@meta
-- Types of player classes and preset classes (T-4.7; 05-loadout.md d.12, d.13). Code:
-- lua/privatewar/modules/loadout/sh_classes.lua (pure: wire, file, repair, availability, cards),
-- sv_classes.lua (server: upload, pick, state), cl_init.lua (client: classes.json, upload on join, state),
-- lua/privatewar/kinds/classes.lua and lua/privatewar/classes/ (presets), lua/privatewar/screens/loadout_classes.lua.

---A preset class in lua/privatewar/classes/ (class table CLASS).
---@class PW.ClassPreset : PW.Entity
---@field Name string display name
---@field Loadout PW.Loadout the loadout, repaired against the match settings like a player's class
---@field Description? string
---@field Hidden? boolean human picker/id permission only; nil/false is visible, not bot eligibility or Abstract

---Where a class comes from: the classes kind or the player's own list.
---@alias PW.LoadoutClassSource "preset"|"custom"

---A player's custom class: as stored in classes.json and as uploaded.
---@class PW.LoadoutClass
---@field name string
---@field loadout PW.Loadout

---Writes values to a wire (net.Write* on the real path; a list in tests).
---@class PW.LoadoutWriter
---@field uint fun(value: integer, bits: integer)
---@field string fun(value: string)
---@field bool fun(value: boolean)

---Reads values from a wire (net.Read* on the real path; a list in tests).
---@class PW.LoadoutReader
---@field uint fun(bits: integer): integer
---@field string fun(): string
---@field bool fun(): boolean

---The result of repairing a class against the match settings and the catalogue.
---@class PW.LoadoutClassStatus
---@field loadout PW.Loadout what is left after the repair
---@field removed string[] what the repair removed, "<id> (<why>)"
---@field available boolean the repaired class can be used in this match
---@field reason? string why it cannot (budget, attachment cap, empty, PW_ValidateLoadout)

---One class in the state the server sends a player: a preset ("preset:<id>") or a custom class ("custom:<n>").
---@class PW.LoadoutClassEntry : PW.LoadoutClassStatus
---@field ref string
---@field name string

---What the server sends a player after an upload, a pick or a phase change.
---@class PW.LoadoutClassState
---@field selected string the ref of the class in use, "" for none (the default loadout)
---@field entries PW.LoadoutClassEntry[] custom classes first, then visible presets; stable within each category

---Internal: server state and injectable engine calls of the classes part.
---@class PW.LoadoutClassStore
---@field uploads table<any, PW.LoadoutClass[]> weak-keyed: the last upload of a player, kept as sent (repaired on use)
---@field picks table<any, string> weak-keyed: the ref a player picked
---@field read fun(): PW.LoadoutClass[] reads an upload (net on the real path)
---@field readPick fun(): string reads a pick (net on the real path)
---@field send fun(ply: Player, state: PW.LoadoutClassState) sends the state (net on the real path)
---@field context fun(): PW.LoadoutContext the Pick X context of the match (live settings on the real path)
---@field notInstalled table<any, table<string, table<string, table<string, boolean>>>> weak-keyed (T-4.8): per player,
---class ref -> loadout slot -> options that did not stick on the live weapon; dropped from that class ("not installed")

---@class PW.LoadoutClassStoreOptions
---@field read? fun(): PW.LoadoutClass[]
---@field readPick? fun(): string
---@field send? fun(ply: Player, state: PW.LoadoutClassState)
---@field context? fun(): PW.LoadoutContext

---@class PW.LoadoutLib
---Maximum size of a class upload in bytes (PW.Net.Receive maxLen of pw_loadout_classes).
---@field ClassesMaxBytes integer
---Longest class name kept, in characters.
---@field ClassNameMax integer
---The net.Write* functions as a writer.
---@field _NetWriter fun(): PW.LoadoutWriter
---The net.Read* functions as a reader.
---@field _NetReader fun(): PW.LoadoutReader
---Pure: writes classes (count, then name and loadout each) with explicit types and bit widths.
---@field _EncodeClasses fun(classes: PW.LoadoutClass[], writer: PW.LoadoutWriter)
---Pure: reads classes written by _EncodeClasses; keeps at most max; every count is bounded by its bit width.
---@field _DecodeClasses fun(reader: PW.LoadoutReader, max: integer): PW.LoadoutClass[]
---Pure: writes the state a server sends a player.
---@field _EncodeClassState fun(state: PW.LoadoutClassState, writer: PW.LoadoutWriter)
---Pure: reads a state written by _EncodeClassState.
---@field _DecodeClassState fun(reader: PW.LoadoutReader): PW.LoadoutClassState
---Pure: the classes of a decoded classes.json ({ version, classes = { { name, loadout } } }): shape-checked, names
---cut to ClassNameMax ("Class <n>" when missing), at most max classes, classes without any item dropped.
---@field _ClassesFromJson fun(data: any, max: integer): PW.LoadoutClass[]
---Pure: removes what is unavailable (unknown slot, unknown or disabled item, wrong filter, too many items, banned
---weapon, banned or hidden attachment, builds of a removed weapon) and keeps the rest. Returns the repaired loadout
---and what was removed.
---@field _RepairClass fun(slots: table<string, PW.LoadoutSlot>, loadout: PW.Loadout, ctx: PW.LoadoutContext):
---PW.Loadout, string[]
---Pure: repairs a class and decides whether it is available in the match (budget, attachment cap: the class is
---marked unavailable, not trimmed). check replaces the final check (the server adds PW_ValidateLoadout).
---@field _ClassStatus fun(slots: table<string, PW.LoadoutSlot>, loadout: PW.Loadout, ctx: PW.LoadoutContext,
---check?: fun(loadout: PW.Loadout): boolean, string?): PW.LoadoutClassStatus
---Pure: "preset:<id>" or "custom:<n>" to its source and key; nil for anything else.
---@field _ParseRef fun(ref: any): PW.LoadoutClassSource?, string|integer|nil
---Pure stable partition/filter; copies the list, not entry objects or loadouts.
---A missing preset keeps legacy visibility.
---@field _HumanClassEntries fun(entries: PW.LoadoutClassEntry[], customOnly: boolean,
---lookup: fun(id: string): PW.ClassPreset?): PW.LoadoutClassEntry[]
---Shared human view using public preset metadata; customOnly excludes all presets. Does not mutate state.
---Selected is empty when absent from the filtered entries; does not change the authoritative stored pick.
---@field HumanClassState fun(state: PW.LoadoutClassState, customOnly?: boolean): PW.LoadoutClassState
---Shared human-filtered cards (IN USE for the selected class, N/A with its reason when unavailable).
---@field _ClassCards fun(state: PW.LoadoutClassState, customOnly?: boolean): PW.UICard[]
---Pure: key and value rows of a class (slot, item name; attachments counted per weapon slot).
---@field _ClassRows fun(entry: PW.LoadoutClassEntry, nameOf?: fun(kind: string, id: string): string):
---{ [1]: string, [2]: string }[]
---Server: a fresh class store; every engine call can be replaced.
---@field _NewClassStore fun(opts?: PW.LoadoutClassStoreOptions): PW.LoadoutClassStore
---Server: registers pw_loadout_classes and pw_loadout_pick through PW.Net.Receive (owner: the module).
---@field _RegisterClassNet fun(owner?: table)
---Server: stores an upload, re-applies the pick and sends the state. Returns the state.
---@field _OnClasses fun(ply: Player, classes: PW.LoadoutClass[]): PW.LoadoutClassState
---Server: picks a class by ref. An available class becomes the player's class (next spawn, through Resolve); an
---unknown or unavailable one is refused. The state is sent either way. Returns whether the pick was taken.
---@field _OnPick fun(ply: Player, ref: string): boolean
---Server: the state of a player under the current match settings.
---@field ClassState fun(ply: Player): PW.LoadoutClassState
---Server: re-applies the pick of a player under the current settings and sends the state. Returns the state.
---@field RefreshClasses fun(ply: Player): PW.LoadoutClassState
---The question PW_ValidateLoadout(ply, loadout) alone: false or a string rejects (Validate asks it last).
---@field _AskValidate fun(ply: Player, loadout: PW.Loadout): boolean, string?
---Client: the last state the server sent, nil before the first.
---@field GetClassState? fun(): PW.LoadoutClassState?
---Client: reads classes.json and uploads the classes.
---@field UploadClasses? fun()
---Client: asks the server to use a class.
---@field SendPick? fun(ref: string)

---@class PW
---@field Classes? PW.Registry the classes kind registry (lua/privatewar/classes/)
---@field _LoadoutClasses PW.LoadoutClassStore internal

---Class table inside a classes/ file.
---@type PW.ClassPreset
CLASS = nil
