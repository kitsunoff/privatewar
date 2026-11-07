---@meta
-- Types of wildcards (T-4.3; 05-loadout.md d.5). Source: lua/privatewar/kinds/wildcards.lua (the kind),
-- lua/privatewar/modules/loadout/sh_wildcards.lua (effective slot set, duplicate rule, stat lists), init.lua of the
-- loadout module (equipped store, PW.Perks.StatSource) and lua/privatewar/wildcards/ (overkill, perk_greed,
-- gunfighter).

---One wildcard, a file in lua/privatewar/wildcards/ with a WILDCARD table. Never auto-subscribed. Picked in the
---loadout slot "wildcard"; its ModifySlots changes the slot set the loadout is validated, costed and repaired by.
---@class PW.Wildcard : PW.Entity
---Required. Display name.
---@field Name string
---Required. Changes the slot set: `slots` is a scratch copy (slot id to PW.LoadoutSlot) that the method may edit in
---place (counts, filters, maxattachments, groups) or extend with a new slot (the key is the id). The wildcard slot
---itself cannot be changed. An error drops the wildcard's changes.
---@field ModifySlots fun(self: PW.Wildcard, slots: table<string, PW.LoadoutSlot>)
---Short text for the class screen.
---@field Description? string
---Pick X cost (05-loadout.md d.2); default 1.
---@field Cost? number
---Multipliers by stat id, read through PW.Stat (the loadout module registers them with PW.Perks.StatSource).
---@field Stats? table<string, number>

---Class table inside a wildcards/ file.
---@type PW.Wildcard
WILDCARD = nil

---@class PW
---Internal: the wildcard ids each player has equipped (server, weak-keyed).
---@field _Wildcards? table<any, string[]>
