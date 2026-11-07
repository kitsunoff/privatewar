---@meta
-- Types of the weapon stat modifiers module (T-3.5; 04-weapons.md d.6; docs/api/adapter.md "Stat modifiers").
-- Code: lua/privatewar/modules/weapons_statmods/.

---@alias PW.StatModKey "reload_time"|"draw_time"|"ads_time"|"sprint_to_fire"|"recoil"|"spread"

---What the refresh loop remembers about one weapon: the owner and the revision its adapter last refreshed for.
---@class PW.StatModSeen
---@field owner any
---@field revision integer
---@field installed? boolean InstallStatMods already ran for this weapon

---One weapon the loop has to touch.
---@class PW.StatModWork
---@field weapon any the weapon entity
---@field install boolean the first refresh of this weapon: InstallStatMods runs before RefreshStatMods

---@class PW.StatModsLib
---Writes the multipliers of a player (server). Keys absent from mods (and every key of nil or {}) become 1.0; a value
---that is not a positive finite number counts as 1.0; unknown keys are ignored. The revision counter is bumped
---once per call, written last.
---@field SetStatMods fun(ply: Player, mods: table<string, number>?)
---The player's multiplier of key (shared); 1 for an invalid entity, a non-player or an unknown key.
---@field GetStatMod fun(ply: Player?, key: string): number
---Internal, pure: the known keys in a stable order.
---@field _Keys string[]
---Internal: the NW2 name of a stat key.
---@field _Key fun(stat: string): string
---Internal: the NW2 name of the revision counter.
---@field _RevisionKey string
---Internal, pure: a full table key to value (absent = 1.0) from the caller's mods.
---@field _Normalize fun(mods: table<string, number>?): table<string, number>
---Internal, pure: the revision after rev (wraps well below the 32-bit limit of NW2 ints).
---@field _NextRevision fun(rev: integer): integer
---Internal, pure: which of weapons need work for this owner and revision; updates seen. Nil when none.
---@field _Sweep fun(seen: table<any, PW.StatModSeen>, owner: any, revision: integer, weapons: any[]): PW.StatModWork[]?
---Internal: one pass of the refresh loop over the owners of this realm (the Think hook).
---@field _Tick fun()

---@class PW
---@field StatMods PW.StatModsLib
---@field SetStatMods fun(ply: Player, mods: table<string, number>?)
---@field GetStatMod fun(ply: Player?, key: string): number
