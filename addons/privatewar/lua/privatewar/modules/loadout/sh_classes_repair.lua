-- Classes, pure part 2 (T-4.7; 05-loadout.md d.12): repair, availability, class refs and the card model of the
-- class list. Plain data in, plain data out; the context (catalogue lookup, budget, cap, bans) is injected.
-- Loaded by shared.lua through include; the decisions are listed in sh_classes.lua.

local lib = PW.Loadout --[[@as PW.LoadoutLib]]

local buildsKey = "builds"

---@param tbl table<string, any>
---@return string[]
local function sortedKeys(tbl)
    ---@type string[]
    local keys = {}
    for key in pairs(tbl) do
        if isstring(key) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

---@param list string[]
---@param id string
---@param why string
local function note(list, id, why)
    list[#list + 1] = id .. " (" .. why .. ")"
end

---Why an item cannot stay in a slot, or nil when it can.
---@param slot PW.LoadoutSlot
---@param id string
---@param keptCount integer
---@param ctx PW.LoadoutContext
---@return string?
local function itemProblem(slot, id, keptCount, ctx)
    if keptCount >= (slot.count or 1) then return "too many in " .. slot.id end
    local entity = ctx.lookup(slot.kind, id)
    if entity == nil then return "not available" end
    if not lib._Matches(slot, entity) then return "does not fit " .. slot.id end
    if slot.kind == "weapons" and (ctx.bannedWeapons or {})[id] then return "banned" end
    if ctx.isUnlocked ~= nil and not ctx.isUnlocked(slot.kind, id) then return "locked" end
    return nil
end

---@param slot PW.LoadoutSlot
---@param value any
---@param ctx PW.LoadoutContext
---@param removed string[]
---@return string[]
local function repairSlot(slot, value, ctx, removed)
    ---@type string[]
    local kept = {}
    local items = lib._Items(value)
    if items == nil then
        note(removed, slot.id, "not a list of ids")
        return kept
    end
    for _, id in ipairs(items) do
        local problem = itemProblem(slot, id, #kept, ctx)
        if problem ~= nil then note(removed, id, problem) else kept[#kept + 1] = id end
    end
    return kept
end

---@param weaponId string
---@param weapon table<string, any>
---@param build table<string, any>
---@param ctx PW.LoadoutContext
---@param removed string[]
---@return table<string, string|false>
local function repairBuild(weaponId, weapon, build, ctx, removed)
    local entries = istable(weapon.Attachments) and weapon.Attachments or {}
    local banned = ctx.bannedAttachments or {}
    ---@type table<string, string|false>
    local kept = {}
    for _, buildSlot in ipairs(sortedKeys(build)) do
        local option = build[buildSlot]
        if option == false then
            kept[buildSlot] = false
        elseif isstring(option) then
            local entry = entries[option] --[[@as any]]
            if banned[option] then
                note(removed, option, "banned")
            elseif istable(entry) and entry.Hidden == true then
                note(removed, option, "not available")
            else
                kept[buildSlot] = option --[[@as string]]
            end
        end
    end
    -- T-4.8: the adapter's options and static Validate, progression unlocks and its count limit (sh_gunsmith.lua).
    local clean, problems = lib._ValidateBuild(weaponId, weapon, kept, ctx)
    for _, problem in ipairs(problems) do note(removed, problem.option, problem.why) end
    return clean
end

---@param slots table<string, PW.LoadoutSlot>
---@param loadout PW.Loadout
---@param repaired PW.Loadout
---@param ctx PW.LoadoutContext
---@param removed string[]
local function repairBuilds(slots, loadout, repaired, ctx, removed)
    local builds = loadout[buildsKey]
    if not istable(builds) then return end
    ---@type table<string, table<string, string|false>>
    local kept = {}
    for _, slotId in ipairs(sortedKeys(builds --[[@as table<string, any>]])) do
        local slot, build = slots[slotId], (builds --[[@as table<string, any>]])[slotId]
        local items = repaired[slotId] ~= nil and lib._Items(repaired[slotId]) or nil
        if slot ~= nil and slot.kind == "weapons" and items ~= nil and istable(build) then
            local weapon = ctx.lookup("weapons", items[1]) or {}
            local clean = repairBuild(items[1], weapon, build --[[@as table<string, any>]], ctx, removed)
            if next(clean) ~= nil then kept[slotId] = clean end
        end
    end
    if next(kept) ~= nil then repaired[buildsKey] = kept end
end

function lib._RepairClass(declared, loadout, ctx)
    local slots = lib._EffectiveSlots(declared, loadout, ctx.lookup, ctx.maxattachments)
    ---@type PW.Loadout
    local repaired = {}
    ---@type string[]
    local removed = {}
    for _, slotId in ipairs(sortedKeys(loadout)) do
        local slot = slots[slotId]
        if slotId ~= buildsKey and slot == nil then
            note(removed, slotId, "unknown slot")
        elseif slotId ~= buildsKey then
            local kept = repairSlot(slot, loadout[slotId], ctx, removed)
            if #kept == 1 and (slot.count or 1) == 1 then
                repaired[slotId] = kept[1]
            elseif #kept > 0 then
                repaired[slotId] = kept
            end
        end
    end
    repairBuilds(slots, loadout, repaired, ctx, removed)
    return repaired, removed
end

function lib._ClassStatus(slots, loadout, ctx, check)
    local repaired, removed = lib._RepairClass(slots, loadout, ctx)
    ---@type PW.LoadoutClassStatus
    local status = { loadout = repaired, removed = removed, available = true }
    local items = false
    for key in pairs(repaired) do
        if key ~= buildsKey then items = true end
    end
    if not items then
        status.available, status.reason = false, "the class is empty"
        return status
    end
    local final = check or function(value) return lib._Validate(slots, value, ctx.lookup, ctx) end
    local ok, err = final(repaired)
    if not ok then status.available, status.reason = false, err or "not available" end
    return status
end

function lib._ParseRef(ref)
    if not isstring(ref) then return nil, nil end
    local preset = string.match(ref, "^preset:([%l%d_]+)$")
    if preset ~= nil then return "preset", preset end
    local custom = tonumber(string.match(ref, "^custom:(%d%d?)$") or "")
    if custom ~= nil and custom >= 1 then return "custom", math.floor(custom) end
    return nil, nil
end

-- Cards and rows ----------------------------------------------------------------------------------------------------

function lib._ClassCards(state)
    ---@type PW.UICard[]
    local cards = {}
    for index, entry in ipairs(state.entries) do
        local badge = (not entry.available and "N/A") or (entry.ref == state.selected and "IN USE") or nil
        local text = entry.reason
        if text == nil and #entry.removed > 0 then text = "Removed: " .. table.concat(entry.removed, ", ") end
        cards[index] = {
            id = entry.ref, title = entry.name, badge = badge, text = text,
            tags = lib._ParseRef(entry.ref) == "preset" and "Preset" or "Custom class"
        }
    end
    return cards
end

---@param kind string
---@param id string
---@return string
local function registryName(kind, id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries[kind] or nil
    local entity = registry ~= nil and registry.Get(id) or nil
    local name = entity ~= nil and entity.Name or nil
    return isstring(name) and name --[[@as string]] or id
end

---Slot ids of a loadout: declared slots in declaration order, then the rest sorted.
---@param loadout PW.Loadout
---@return string[]
local function slotOrder(loadout)
    ---@type string[]
    local ids = {}
    ---@type table<string, boolean>
    local seen = { [buildsKey] = true }
    for _, id in ipairs(PW._Loadout.order) do
        if loadout[id] ~= nil then ids[#ids + 1] = id end
        seen[id] = true
    end
    for _, id in ipairs(sortedKeys(loadout)) do
        if not seen[id] then ids[#ids + 1] = id end
    end
    return ids
end

function lib._ClassRows(entry, nameOf)
    local name = nameOf or registryName
    ---@type { [1]: string, [2]: string }[]
    local rows = {}
    local loadout = entry.loadout
    for _, slotId in ipairs(slotOrder(loadout)) do
        local slot = PW._Loadout.slots[slotId]
        ---@type string[]
        local names = {}
        for index, id in ipairs(lib._Items(loadout[slotId]) or {}) do
            names[index] = name(slot ~= nil and slot.kind or "", id)
        end
        rows[#rows + 1] = { string.upper(slotId), table.concat(names, ", ") }
    end
    local builds = loadout[buildsKey]
    for _, slotId in ipairs(istable(builds) and sortedKeys(builds --[[@as table<string, any>]]) or {}) do
        local count = 0
        for _, option in pairs((builds --[[@as table<string, table<string, any>>]])[slotId]) do
            if isstring(option) then count = count + 1 end
        end
        rows[#rows + 1] = { string.upper(slotId) .. " ATTACHMENTS", tostring(count) }
    end
    return rows
end
