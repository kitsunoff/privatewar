-- Pick X (T-4.2; 05-loadout.md d.2, d.3, d.6, d.7 and 04-weapons.md d.5). Pure arithmetic and rules over plain data:
-- the cost of every pick, the budget, the attachment cap and the bans. Engine reads (settings, adapter) sit in thin
-- wrappers at the bottom. Loaded by shared.lua through include.
--
-- A loadout carries the attachment builds of its weapon slots under the reserved key "builds":
--   { primary = "arc9_ak74", builds = { primary = { muzzle = "suppressor", optic = false } } }
-- (slot id -> PW.Build: build slot -> option id, false = cleared). The key is not a slot.
--
-- Question PW_LoadoutCost(item): a number >= 0 replaces the cost of the item. item is { kind, id, entity, cost,
-- slot } for a pick, plus { attachment = optionId, weapon = weaponId, cosmetic } with kind "attachment" for an
-- attachment (entity is then the weapon).
--
-- Decisions of the lane agent:
--   1. Default cost 1; the Cost field of the entity, or of its Attachments entry, replaces it (adapter.md).
--   2. Free and not counted toward the cap: the Cosmetic flag of an Attachments entry, an option listed in Camos, and
--      what the adapter reports as a cosmetic slot or option. A cleared option (false) is neither.
--   3. Killstreaks are outside the budget (05 d.2): kind "streaks" costs nothing here.
--   4. The cap is the declared maxattachments of the slot (a wildcard changes it, T-4.3), else the setting.
--   5. Bans are by bare id: weapon class in loadout.bannedweapons, option id in loadout.bannedattachments. A Hidden
--      attachment is rejected like a banned one.
--   6. A build of a slot with count > 1 belongs to the first weapon of the slot.

local lib = PW.Loadout --[[@as PW.LoadoutLib]]

local buildsKey = "builds"
local defaultBudget = 10
local defaultMaxAttachments = 5

---@param value any
---@return table<string, boolean>
local function toSet(value)
    ---@type table<string, boolean>
    local set = {}
    if not istable(value) then return set end
    for key, member in pairs(value --[[@as table<any, any>]]) do
        if isstring(member) then
            set[member] = true
        elseif member == true and isstring(key) then
            set[key] = true
        end
    end
    return set
end

---@param read fun(id: string): any
---@param id string
---@param default number
---@return number
local function readNumber(read, id, default)
    local value = read(id)
    if not isnumber(value) then return default end
    return math.max(0, math.floor(value --[[@as number]]))
end

function lib._Context(read, lookup)
    ---@type PW.LoadoutContext
    local ctx = {
        lookup = lookup or lib._RegistryLookup,
        budget = readNumber(read, "loadout.budget", defaultBudget),
        maxattachments = readNumber(read, "loadout.maxattachments", defaultMaxAttachments),
        bannedWeapons = toSet(read("loadout.bannedweapons")),
        bannedAttachments = toSet(read("loadout.bannedattachments"))
    }
    return ctx
end

---The base cost of an entity: its Cost field, else 1.
---@param entity table<string, any>
---@return number
local function baseCost(entity)
    local cost = entity.Cost
    if isnumber(cost) and cost >= 0 then return cost --[[@as number]] end
    return 1
end

---@class PW.LoadoutItem
---@field kind string
---@field id string
---@field slot string
---@field entity table<string, any>
---@field cost number
---@field attachment? string
---@field weapon? string
---@field cosmetic? boolean
---@field hidden? boolean

---Applies the PW_LoadoutCost answer to an item (a number >= 0 replaces the cost; anything else is ignored).
---@param item PW.LoadoutItem
local function applyOverride(item)
    local answer = PW.Ask("PW_LoadoutCost", item)
    if isnumber(answer) and answer >= 0 then item.cost = answer --[[@as number]] end
end

---@param table_ table<string, any>
---@return string[]
local function sortedKeys(table_)
    local keys = table.GetKeys(table_) --[[@as string[] ]]
    table.sort(keys)
    return keys
end

---@param weaponId string
---@param weapon table<string, any>
---@param slotId string
---@param build table<string, any>
---@param ctx PW.LoadoutContext
---@return PW.LoadoutItem[]
local function attachmentItems(weaponId, weapon, slotId, build, ctx)
    ---@type PW.LoadoutItem[]
    local items = {}
    local entries = istable(weapon.Attachments) and weapon.Attachments or {}
    local camos = istable(weapon.Camos) and weapon.Camos or {}
    for _, buildSlot in ipairs(sortedKeys(build)) do
        local option = build[buildSlot]
        if isstring(option) then
            local entry = entries[option] or {}
            local cosmetic = entry.Cosmetic == true or camos[option] ~= nil
                or (ctx.isCosmetic ~= nil and ctx.isCosmetic(weaponId, buildSlot, option) == true)
            ---@type PW.LoadoutItem
            local item = {
                kind = "attachment", id = option, slot = slotId, entity = weapon, weapon = weaponId,
                attachment = option, cosmetic = cosmetic, hidden = entry.Hidden == true,
                cost = cosmetic and 0 or baseCost(entry)
            }
            if not cosmetic then applyOverride(item) end
            items[#items + 1] = item
        end
    end
    return items
end

---The picks of one slot (and, for the first weapon, its attachments) as items.
---@param slot PW.LoadoutSlot
---@param loadout PW.Loadout
---@param ctx PW.LoadoutContext
---@param list PW.LoadoutItem[]
local function slotItems(slot, loadout, ctx, list)
    local rawBuilds = loadout[buildsKey]
    local builds = (istable(rawBuilds) and rawBuilds or {}) --[[@as table<string, table<string, any>>]]
    for index, id in ipairs(lib._Items(loadout[slot.id]) or {}) do
        local entity = ctx.lookup(slot.kind, id)
        if entity ~= nil then
            ---@type PW.LoadoutItem
            local item = { kind = slot.kind, id = id, slot = slot.id, entity = entity, cost = baseCost(entity) }
            applyOverride(item)
            list[#list + 1] = item
            local build = builds[slot.id]
            if index == 1 and slot.kind == "weapons" and istable(build) then
                table.Add(list, attachmentItems(id, entity, slot.id, build, ctx))
            end
        end
    end
end

---Every pick of a loadout as a flat list, slots in sorted order: items of the slots and the attachments of weapons.
---Streaks are skipped (outside the budget); picks missing from the catalogue are skipped (the slot rules reject them).
---@param slots table<string, PW.LoadoutSlot>
---@param loadout PW.Loadout
---@param ctx PW.LoadoutContext
---@return PW.LoadoutItem[]
local function collect(slots, loadout, ctx)
    ---@type PW.LoadoutItem[]
    local list = {}
    for _, slotId in ipairs(sortedKeys(loadout)) do
        local slot = slots[slotId]
        if slot ~= nil and slot.kind ~= "streaks" then slotItems(slot, loadout, ctx, list) end
    end
    return list
end

function lib._Cost(declared, loadout, ctx)
    local slots = lib._EffectiveSlots(declared, loadout, ctx.lookup, ctx.maxattachments)
    local total = 0
    for _, item in ipairs(collect(slots, loadout, ctx)) do total = total + item.cost end
    return total
end

---Structure of the builds table: a table of declared weapon slots that hold a weapon, each a table of
---build slot -> option id or false.
---@param slots table<string, PW.LoadoutSlot>
---@param loadout PW.Loadout
---@return string?
local function buildsError(slots, loadout)
    local builds = loadout[buildsKey] --[[@as any]]
    if builds == nil then return nil end
    if not istable(builds) then return "builds is not a table" end
    for _, slotId in ipairs(sortedKeys(builds --[[@as table<string, any>]])) do
        local slot = slots[slotId]
        if slot == nil or slot.kind ~= "weapons" then
            return "builds names " .. slotId .. ", which is not a weapon slot"
        end
        if loadout[slotId] == nil then return "builds names " .. slotId .. ", which holds no weapon" end
        local build = builds[slotId] --[[@as table<string, any>]]
        if not istable(build) then return "the build of " .. slotId .. " is not a table" end
        for _, buildSlot in ipairs(sortedKeys(build)) do
            local option = build[buildSlot]
            if not (isstring(option) or option == false) then
                return "the build of " .. slotId .. " has a bad option in " .. tostring(buildSlot)
            end
        end
    end
    return nil
end

---@param items PW.LoadoutItem[]
---@param ctx PW.LoadoutContext
---@return string?
local function banError(items, ctx)
    local bannedWeapons, bannedAttachments = ctx.bannedWeapons or {}, ctx.bannedAttachments or {}
    for _, item in ipairs(items) do
        if item.kind == "weapons" and bannedWeapons[item.id] then return item.id .. " is banned" end
        if item.kind == "attachment" then
            if bannedAttachments[item.id] then return "attachment " .. item.id .. " is banned" end
            if item.hidden then return "attachment " .. item.id .. " is not available" end
        end
    end
    return nil
end

---@param slots table<string, PW.LoadoutSlot>
---@param items PW.LoadoutItem[]
---@param ctx PW.LoadoutContext
---@return string?
local function capError(slots, items, ctx)
    ---@type table<string, integer>
    local counts = {}
    for _, item in ipairs(items) do
        if item.kind == "attachment" and not item.cosmetic then counts[item.slot] = (counts[item.slot] or 0) + 1 end
    end
    for _, slotId in ipairs(sortedKeys(counts)) do
        local cap = slots[slotId].maxattachments or ctx.maxattachments
        if counts[slotId] > cap then
            return "slot " .. slotId .. " holds " .. counts[slotId] .. " attachments, at most " .. cap
        end
    end
    return nil
end

function lib._Extras(slots, loadout, ctx)
    local err = buildsError(slots, loadout)
    if err ~= nil then return false, err end
    local items = collect(slots, loadout, ctx)
    err = banError(items, ctx) or capError(slots, items, ctx)
    if err ~= nil then return false, err end
    if ctx.budget > 0 then
        local total = 0
        for _, item in ipairs(items) do total = total + item.cost end
        if total > ctx.budget then return false, "the loadout costs " .. total .. ", the budget is " .. ctx.budget end
    end
    return true
end

---Does the base adapter call an option cosmetic? Either its build slot or the option itself.
---@param weaponId string
---@param buildSlot string
---@param option string
---@return boolean
local function adapterCosmetic(weaponId, buildSlot, option)
    local adapters = rawget(PW, "Adapters") --[[@as PW.AdaptersLib?]]
    if adapters == nil then return false end
    local precise = adapters.CallFor(weaponId, "IsSelectionCosmetic", weaponId, buildSlot, option)
    if isbool(precise) then return precise --[[@as boolean]] end
    local listed = adapters.CallFor(weaponId, "GetSlots", weaponId, nil) --[[@as PW.Slot[]?]]
    for _, slot in ipairs(listed or {}) do
        if slot.id == buildSlot and slot.cosmetic == true then return true end
    end
    local options = adapters.CallFor(weaponId, "GetOptions", weaponId, buildSlot) --[[@as PW.Option[]?]]
    for _, entry in ipairs(options or {}) do
        if entry.id == option and entry.cosmetic == true then return true end
    end
    return false
end

function lib._LiveContext(lookup)
    local ctx = lib._Context(PW.Setting --[[@as fun(id: string): any]], lookup)
    ctx.isCosmetic = adapterCosmetic
    return ctx
end

function lib.Cost(loadout, lookup)
    local ctx = lib._LiveContext(lookup or lib._RegistryLookup)
    return lib._Cost(PW._Loadout.slots, loadout, ctx)
end
