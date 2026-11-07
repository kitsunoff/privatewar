-- LOADOUT tab editors, pure part 2 (T-7.4; 05-loadout.md d.1-d.5): the class editor model. The rows are the
-- positions of the effective slot set (PW.Loadout._EffectiveSlots: the wildcards of the class change it), the
-- choices of a row are the enabled items of the slot's kind that fit its filter and, for a perk slot with a group,
-- the group; costs and the budget use PW.Loadout._Cost and _Validate, so the editor and the server agree. The
-- catalogue, the settings and the unlock checks come in through the input (PW.LoadoutUIEditorInput).

local lib = PW.LoadoutUI --[[@as PW.LoadoutUILib]]

local buildsKey = "builds"

---@return PW.LoadoutLib
local function loadout()
    return PW.Loadout --[[@as PW.LoadoutLib]]
end

---"perk1" -> "PERK 1", "close_quarters" -> "CLOSE QUARTERS".
---@param id string
---@return string
local function spell(id)
    local text = string.gsub(string.gsub(id, "_", " "), "(%a)(%d+)$", "%1 %2")
    return string.upper(text)
end

function lib.SlotLabel(slot, index)
    local label = slot.label
    local usable = isstring(label) and label ~= "" and string.sub(label --[[@as string]], 1, 1) ~= "#"
    local text = usable and string.upper(label --[[@as string]]) or spell(slot.id)
    if (slot.count or 1) > 1 then text = text .. " #" .. index end
    return text
end

---The level an Unlock field asks for: an integer, { level = N } or nothing (0).
---@param unlock any
---@return number
local function required(unlock)
    if isnumber(unlock) then return unlock --[[@as number]] end
    if istable(unlock) and isnumber((unlock --[[@as table<string, any>]]).level) then
        return (unlock --[[@as table<string, any>]]).level
    end
    return 0
end
lib._Required = required

function lib.LockText(entity)
    local level = required(entity.Unlock)
    if level > 0 then return "LV " .. level, "Unlocks at level " .. level end
    local price = entity.Price
    if isnumber(price) and price > 0 then return "STORE", "Buy it in the store" end
    return "LOCKED", "Locked"
end

---@param entity table<string, any>
---@param id string
---@return string
local function nameOf(entity, id)
    return isstring(entity.Name) and entity.Name or id
end

-- Display order of the slot kinds (the brief of T-7.4: weapons, equipment, perks by group, wildcards, streaks);
-- other kinds follow; within a kind perk groups ascend, then the declaration order holds.
local kindRank = { weapons = 1, equipment = 2, perks = 3, wildcards = 4, streaks = 5 }

---@param order string[]
---@param slots table<string, PW.LoadoutSlot>
---@return string[]
local function slotOrder(order, slots)
    ---@type table<string, integer>
    local position = {}
    for index, id in ipairs(order) do position[id] = position[id] or index end
    ---@type string[]
    local ids = {}
    for id in pairs(slots) do
        if isstring(id) and id ~= buildsKey then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local rankA, rankB = kindRank[slots[a].kind] or 9, kindRank[slots[b].kind] or 9
        if rankA ~= rankB then return rankA < rankB end
        local groupA, groupB = slots[a].group, slots[b].group
        if isnumber(groupA) and isnumber(groupB) and groupA ~= groupB then return groupA < groupB end
        local posA, posB = position[a] or math.huge, position[b] or math.huge
        if posA ~= posB then return posA < posB end
        return a < b
    end)
    return ids
end

---The Pick X cost of one pick, through the same arithmetic as the server.
---@param slots table<string, PW.LoadoutSlot>
---@param slot PW.LoadoutSlot
---@param id string
---@param ctx PW.LoadoutContext
---@return number
local function itemCost(slots, slot, id, ctx)
    return loadout()._Cost(slots, { [slot.id] = id }, ctx)
end

---@param slot PW.LoadoutSlot
---@param entity table<string, any>
---@param cost number
---@return string
local function costText(slot, entity, cost)
    if slot.kind == "streaks" then
        return isnumber(entity.Kills) and (entity.Kills .. " KILLS") or "FREE"
    end
    return tostring(cost)
end

---@param slot PW.LoadoutSlot
---@param entity table<string, any>
---@return boolean
local function groupFits(slot, entity)
    return slot.kind ~= "perks" or slot.group == nil or entity.Group == slot.group
end

---Why a pick is not valid in a slot, or nil.
---@param slot PW.LoadoutSlot
---@param id string
---@param ctx PW.LoadoutContext
---@return string?
local function itemProblem(slot, id, ctx)
    local entity = ctx.lookup(slot.kind, id)
    if entity == nil then return "Not available" end
    if not loadout()._Matches(slot, entity) then return "Does not fit this slot" end
    if not groupFits(slot, entity) then return "A group " .. tostring(entity.Group or "?") .. " perk" end
    if slot.kind == "weapons" and (ctx.bannedWeapons or {})[id] then return "Banned in this match" end
    if ctx.isUnlocked ~= nil and not ctx.isUnlocked(slot.kind, id) then
        local _, reason = lib.LockText(entity)
        return "Locked: " .. string.lower(string.sub(reason, 1, 1)) .. string.sub(reason, 2)
    end
    return nil
end

---@param slots table<string, PW.LoadoutSlot>
---@param slot PW.LoadoutSlot
---@param index integer
---@param id? string
---@param ctx PW.LoadoutContext
---@return PW.LoadoutUIRow
local function makeRow(slots, slot, index, id, ctx)
    local entity = id ~= nil and ctx.lookup(slot.kind, id) or nil
    local cost = (id ~= nil and entity ~= nil) and itemCost(slots, slot, id --[[@as string]], ctx) or 0
    return {
        id = (slot.count or 1) > 1 and (slot.id .. "#" .. index) or slot.id,
        slot = slot.id, index = index, kind = slot.kind, label = lib.SlotLabel(slot, index), group = slot.group,
        item = id, itemName = id ~= nil and nameOf(entity or {}, id --[[@as string]]) or "EMPTY",
        cost = cost, costText = entity ~= nil and costText(slot, entity, cost) or "",
        gunsmith = slot.kind == "weapons" and index == 1 and id ~= nil,
        problem = id ~= nil and itemProblem(slot, id --[[@as string]], ctx) or nil
    }
end

function lib.Editor(input)
    local ctx = input.ctx
    local slots = loadout()._EffectiveSlots(input.declared, input.loadout, ctx.lookup, ctx.maxattachments)
    ---@type PW.LoadoutUIRow[]
    local rows = {}
    for _, slotId in ipairs(slotOrder(input.order, slots)) do
        local slot = slots[slotId]
        local items = loadout()._Items(input.loadout[slotId]) or {}
        for index = 1, slot.count or 1 do rows[#rows + 1] = makeRow(slots, slot, index, items[index], ctx) end
    end
    local cost = loadout()._Cost(input.declared, input.loadout, ctx)
    local ok, err = loadout()._Validate(input.declared, input.loadout, ctx.lookup, ctx)
    return {
        rows = rows, slots = slots, cost = cost, meter = lib.Budget(cost, ctx.budget), check = not ok and err or nil
    }
end

---@param slot PW.LoadoutSlot
---@param entity table<string, any>
---@param id string
---@param ctx PW.LoadoutContext
---@param taken table<string, boolean>
---@param option PW.LoadoutUIOption
local function lockOption(slot, entity, id, ctx, taken, option)
    if taken[id] then
        option.locked, option.reason, option.lockText = true, "Already picked", "PICKED"
    elseif slot.kind == "weapons" and (ctx.bannedWeapons or {})[id] then
        option.locked, option.reason, option.lockText = true, "Banned in this match", "BANNED"
    elseif ctx.isUnlocked ~= nil and not ctx.isUnlocked(slot.kind, id) then
        option.locked = true
        option.lockText, option.reason = lib.LockText(entity)
    end
end

function lib.Options(input, row, slots)
    local slot, ctx = slots[row.slot], input.ctx
    ---@type string[]
    local selectedWeapons = {}
    for _, id in ipairs({ "primary", "secondary" }) do
        local value = input.loadout[id]
        if isstring(value) then selectedWeapons[#selectedWeapons + 1] = value --[[@as string]] end
    end
    ---@type PW.LoadoutUIOption[]
    local options = { { id = "", name = "NONE", cost = 0, costText = "", selected = row.item == nil, locked = false } }
    if slot == nil then return options end
    ---@type table<string, boolean>
    local taken = {}
    for index, id in ipairs(loadout()._Items(input.loadout[row.slot]) or {}) do
        if index ~= row.index then taken[id] = true end
    end
    for _, entity in ipairs(input.list(slot.kind)) do
        local id = entity.ClassName
        if isstring(id) and loadout()._Matches(slot, entity) and groupFits(slot, entity) then
            local cost = itemCost(slots, slot, id, ctx)
            ---@type PW.LoadoutUIOption
            local option = {
                id = id, name = nameOf(entity, id), cost = cost, costText = costText(slot, entity, cost),
                selected = row.item == id, locked = false,
                description = isstring(entity.Description) and entity.Description or nil
            }
            lockOption(slot, entity, id, ctx, taken, option)
            if slot.kind == "perks" then option.description = lib.PerkDescription(entity, selectedWeapons) end
            options[#options + 1] = option
        end
    end
    return options
end

function lib.Budget(cost, budget)
    if budget <= 0 then
        return { cost = cost, budget = 0, state = "unlimited", text = cost .. " (no limit)", fraction = 0 }
    end
    local state = (cost > budget and "over") or (cost == budget and "full") or "ok"
    return { cost = cost, budget = budget, state = state, text = cost .. " / " .. budget,
        fraction = math.min(cost / budget, 1) }
end

---@param slot PW.LoadoutSlot
---@param items string[]
---@return string|string[]|nil
local function stored(slot, items)
    if #items == 0 then return nil end
    if (slot.count or 1) == 1 and #items == 1 then return items[1] end
    return items
end

function lib.Normalize(input, value)
    local ctx = input.ctx
    local slots = loadout()._EffectiveSlots(input.declared, value, ctx.lookup, ctx.maxattachments)
    ---@type PW.Loadout
    local out = {}
    for key, entry in pairs(value) do
        local slot = key ~= buildsKey and slots[key] or nil
        local items = slot ~= nil and loadout()._Items(entry) or nil
        if slot ~= nil and items ~= nil then
            ---@type string[]
            local kept = {}
            for index = 1, math.min(#items, slot.count or 1) do kept[index] = items[index] end
            out[key] = stored(slot, kept)
        end
    end
    local builds = value[buildsKey]
    ---@type table<string, any>
    local keptBuilds = {}
    for slotId, build in pairs(istable(builds) and builds --[[@as table<string, any>]] or {}) do
        local slot = slots[slotId]
        if slot ~= nil and slot.kind == "weapons" and out[slotId] ~= nil and istable(build) then
            keptBuilds[slotId] = table.Copy(build)
        end
    end
    if next(keptBuilds) ~= nil then out[buildsKey] = keptBuilds end
    return out
end

function lib.SetItem(input, rowId, id)
    local slotId, position = string.match(rowId, "^(.-)#(%d+)$")
    local index = tonumber(position) or 1
    slotId = slotId or rowId
    local copy = table.Copy(input.loadout) --[[@as PW.Loadout]]
    local ctx = input.ctx
    local slot = loadout()._EffectiveSlots(input.declared, copy, ctx.lookup, ctx.maxattachments)[slotId]
    if slot == nil then return lib.Normalize(input, copy) end
    local items = loadout()._Items(copy[slotId]) or {}
    local old = items[index]
    ---@type (string|false)[]
    local positions = {}
    for at = 1, math.max(slot.count or 1, #items, index) do positions[at] = items[at] or false end
    positions[index] = (id ~= nil and id ~= "") and id or false
    ---@type string[]
    local list = {}
    for _, item in ipairs(positions) do
        if item then list[#list + 1] = item --[[@as string]] end
    end
    copy[slotId] = stored(slot, list)
    local builds = copy[buildsKey]
    if slot.kind == "weapons" and index == 1 and old ~= positions[index] and istable(builds) then
        (builds --[[@as table<string, any>]])[slotId] = nil
        if next(builds --[[@as table]]) == nil then copy[buildsKey] = nil end
    end
    return lib.Normalize(input, copy)
end
