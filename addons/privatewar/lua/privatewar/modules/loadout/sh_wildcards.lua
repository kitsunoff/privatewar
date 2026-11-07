-- Wildcards (T-4.3; 05-loadout.md d.2, d.5). A wildcard is an item of the kind wildcards picked in the slot
-- "wildcard"; its ModifySlots(slots) changes the slot set that the validation, the budget and the class repair judge
-- the loadout by. Pure functions over plain data; the equipped store and the stat source are in init.lua. Loaded by
-- shared.lua through include.
--
-- Decisions of the lane agent:
--   1. The slot "wildcard" (kind wildcards) holds up to 2 wildcards: "one or more" in the design; two lets a player
--      combine Overkill with another one without a third slot.
--   2. ModifySlots runs on a copy; the declared slots are never changed. A wildcard that errors is skipped whole
--      (its half-done changes are dropped). A wildcard may add a slot (the id is the key) but not change the
--      wildcard slot itself: it cannot grant more wildcards.
--   3. The same wildcard picked twice is rejected, so one effect never stacks.
--   4. Weapon slots without their own maxattachments get the setting's value before ModifySlots runs, so a wildcard
--      can write "maxattachments + 1" without knowing the setting.
--   5. A wildcard costs like any item: its Cost, else 1, through the normal Pick X sum (slot kind is not streaks).

local lib = PW.Loadout --[[@as PW.LoadoutLib]]

local wildcardSlot = "wildcard"
lib.WildcardSlot = wildcardSlot

---@param slots table<string, PW.LoadoutSlot>
---@param defaultCap number?
local function fillCaps(slots, defaultCap)
    if defaultCap == nil then return end
    for _, slot in pairs(slots) do
        if slot.kind == "weapons" and slot.maxattachments == nil then slot.maxattachments = defaultCap end
    end
end

---Does the wildcard's ModifySlots run cleanly on a scratch copy? Returns the changed copy, or nil.
---@param slots table<string, PW.LoadoutSlot>
---@param def table<string, any>
---@return table<string, PW.LoadoutSlot>?
local function applyOne(slots, def)
    if not isfunction(def.ModifySlots) then return nil end
    local work = table.Copy(slots)
    local ok = pcall(def.ModifySlots, def, work)
    if not ok then return nil end
    return work
end

function lib._EffectiveSlots(slots, loadout, lookup, defaultCap)
    local declared = slots[wildcardSlot]
    local ids = declared ~= nil and lib._Items(loadout[wildcardSlot]) or nil
    if ids == nil then return slots end
    local effective = table.Copy(slots)
    fillCaps(effective, defaultCap)
    ---@type table<string, boolean>
    local seen = {}
    for _, id in ipairs(ids) do
        local def = not seen[id] and lookup("wildcards", id) or nil
        seen[id] = true
        local changed = def ~= nil and applyOne(effective, def) or nil
        if changed ~= nil then effective = changed end
    end
    effective[wildcardSlot] = table.Copy(declared)
    for key, slot in pairs(effective) do
        if istable(slot) then slot.id = key else effective[key] = nil end
    end
    return effective
end

function lib._WildcardError(slots, loadout)
    if slots[wildcardSlot] == nil then return nil end
    ---@type table<string, boolean>
    local seen = {}
    for _, id in ipairs(lib._Items(loadout[wildcardSlot]) or {}) do
        if seen[id] then return "wildcard " .. id .. " is picked twice" end
        seen[id] = true
    end
    return nil
end

function lib._WildcardStats(ids, lookup)
    ---@type table<string, number>[]
    local lists = {}
    for _, id in ipairs(ids) do
        local def = lookup("wildcards", id)
        if def ~= nil and istable(def.Stats) then lists[#lists + 1] = def.Stats --[[@as table<string, number>]] end
    end
    return lists
end
