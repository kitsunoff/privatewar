-- LOADOUT tab editors, pure part 3 (T-7.4; 05-loadout.md d.3, d.15; 06-progression.md d.2): the gunsmith model of
-- one weapon. The adapter's build slots and options come in through the input (ADAPTER:GetSlots and GetOptions are
-- shared, so the client asks them); curation (Attachments, Camos) comes from the catalogue entry. Two limits:
--   the match cap (loadout.maxattachments, raised by wildcards): non-cosmetic options;
--   the weapon level (06 d.2, progression): uncurated, non-cosmetic options; none with unlockall.
-- An option that would break either is locked "FULL"; a curated option above the weapon level is locked "LV <n>".
-- The preview runs the loadout module's own save-time check (PW.Loadout._ValidateBuild) without the adapter's
-- Validate, which is server-only: conflicts show only in the server's answer to a save.

local lib = PW.LoadoutUI --[[@as PW.LoadoutUILib]]

local noGunsmith = "This weapon has no gunsmith: its adapter offers no attachments (HL2 weapons and plain SWEPs). " ..
    "A weapon base such as ARC9, TFA or MW Base adds them."
local serverNote = "Conflicts between attachments are checked by the server when you save."

---@class PW.LoadoutUIOptionFacts
---@field hidden boolean
---@field cosmetic boolean
---@field unlock number the weapon level of a curated option, 0 when uncurated
---@field levelCounted boolean counted toward the weapon level limit
---@field cost number

---@param input PW.LoadoutUIGunsmithInput
---@param slotCosmetic boolean
---@param id string
---@param optionCosmetic boolean
---@return PW.LoadoutUIOptionFacts
local function factsOf(input, slotCosmetic, id, optionCosmetic)
    local weapon = input.weapon
    local entries = istable(weapon.Attachments) and weapon.Attachments or {}
    local camos = istable(weapon.Camos) and weapon.Camos or {}
    local entry = istable(entries[id]) and entries[id] or {}
    local camo = istable(camos[id]) and camos[id] or nil
    local cosmetic = slotCosmetic or optionCosmetic or entry.Cosmetic == true or camo ~= nil
    local unlock = lib._Required(entry.Unlock)
    if camo ~= nil then unlock = lib._Required(camo.Unlock) end
    return {
        hidden = entry.Hidden == true, cosmetic = cosmetic, unlock = unlock,
        levelCounted = not cosmetic and entry.Unlock == nil,
        cost = cosmetic and 0 or (isnumber(entry.Cost) and entry.Cost or 1)
    }
end

---@class PW.LoadoutUISlotInfo
---@field slot PW.Slot
---@field options PW.Option[]
---@field byId table<string, PW.Option>

---@param input PW.LoadoutUIGunsmithInput
---@return table<string, PW.LoadoutUISlotInfo>
local function slotInfo(input)
    ---@type table<string, PW.LoadoutUISlotInfo>
    local info = {}
    for _, slot in ipairs(input.slots) do
        local options = input.options(slot.id) or {}
        ---@type table<string, PW.Option>
        local byId = {}
        for _, option in ipairs(options) do byId[option.id] = option end
        info[slot.id] = { slot = slot, options = options, byId = byId }
    end
    return info
end

---The facts of the option a build slot holds.
---@param input PW.LoadoutUIGunsmithInput
---@param info table<string, PW.LoadoutUISlotInfo>
---@param slotId string
---@param id string
---@return PW.LoadoutUIOptionFacts
local function pickedFacts(input, info, slotId, id)
    local slot = info[slotId]
    local option = slot ~= nil and slot.byId[id] or nil
    return factsOf(input, slot ~= nil and slot.slot.cosmetic == true, id, option ~= nil and option.cosmetic == true)
end

---@class PW.LoadoutUIGunsmithCounts
---@field count integer
---@field levelCount integer
---@field levelLimit? integer

---@param option PW.LoadoutUIGunsmithOption
---@param facts PW.LoadoutUIOptionFacts
---@param current? PW.LoadoutUIOptionFacts
---@param input PW.LoadoutUIGunsmithInput
---@param counts PW.LoadoutUIGunsmithCounts
local function lockOption(option, facts, current, input, counts)
    if input.banned[option.id] then
        option.locked, option.lockText, option.reason = true, "BANNED", "Banned in this match"
    elseif facts.unlock > 0 and not input.unlockAll and input.weaponLevel < facts.unlock then
        option.locked, option.lockText = true, "LV " .. facts.unlock
        option.reason = "Unlocks at weapon level " .. facts.unlock
    elseif not option.selected and not facts.cosmetic then
        local newCount = counts.count - ((current ~= nil and not current.cosmetic) and 1 or 0) + 1
        local newLevel = counts.levelCount - ((current ~= nil and current.levelCounted) and 1 or 0) + 1
        local limit = counts.levelLimit
        if newCount > input.cap then
            option.locked, option.lockText = true, "FULL"
            option.reason = "At most " .. input.cap .. " attachments on this weapon in this match"
        elseif limit ~= nil and facts.levelCounted and newLevel > limit then
            option.locked, option.lockText = true, "FULL"
            option.reason = "Weapon level " .. input.weaponLevel .. " allows " .. limit .. " attachment(s): level it up"
        end
    end
end

---@param input PW.LoadoutUIGunsmithInput
---@param info PW.LoadoutUISlotInfo
---@param counts PW.LoadoutUIGunsmithCounts
---@return PW.LoadoutUIGunsmithSlot
local function makeSlot(input, info, counts)
    local slot = info.slot
    local picked = input.build[slot.id]
    local current = isstring(picked) and picked --[[@as string]] or nil
    local currentFacts = current ~= nil and pickedFacts(input, { [slot.id] = info }, slot.id, current) or nil
    ---@type PW.LoadoutUIGunsmithOption[]
    local options = { {
        id = "", name = "DEFAULT", cosmetic = false, cost = 0, costText = "", selected = current == nil, locked = false
    } }
    for _, entry in ipairs(info.options) do
        local facts = factsOf(input, slot.cosmetic == true, entry.id, entry.cosmetic == true)
        if not facts.hidden then
            ---@type PW.LoadoutUIGunsmithOption
            local option = {
                id = entry.id, name = isstring(entry.name) and entry.name or entry.id, cosmetic = facts.cosmetic,
                cost = facts.cost, costText = facts.cosmetic and "FREE" or tostring(facts.cost),
                selected = current == entry.id, locked = false, unlock = facts.unlock > 0 and facts.unlock or nil
            }
            lockOption(option, facts, currentFacts, input, counts)
            options[#options + 1] = option
        end
    end
    local shown = current ~= nil and info.byId[current] or nil
    return {
        id = slot.id, name = isstring(slot.name) and slot.name or slot.id, cosmetic = slot.cosmetic == true,
        current = current, options = options,
        currentName = current == nil and "DEFAULT" or (shown ~= nil and shown.name or current --[[@as string]])
    }
end

---The curated options of a build above the weapon level (the lockedOptions check of the preview).
---@param input PW.LoadoutUIGunsmithInput
---@param info table<string, PW.LoadoutUISlotInfo>
---@param build table<string, string|false>
---@return table<string, boolean>
local function lockedIn(input, info, build)
    ---@type table<string, boolean>
    local locked = {}
    for slotId, value in pairs(build) do
        local unlock = isstring(value) and pickedFacts(input, info, slotId, value --[[@as string]]).unlock or 0
        if unlock > 0 and not input.unlockAll and input.weaponLevel < unlock then
            locked[value --[[@as string]]] = true
        end
    end
    return locked
end

---@param input PW.LoadoutUIGunsmithInput
---@param info table<string, PW.LoadoutUISlotInfo>
---@param counts PW.LoadoutUIGunsmithCounts
---@return string[]
local function preview(input, info, counts)
    ---@type table<string, table<string, boolean>>
    local offered = {}
    ---@type table<string, string>
    local names = {}
    for slotId, slot in pairs(info) do
        offered[slotId] = {}
        for _, option in ipairs(slot.options) do
            offered[slotId][option.id] = true
            names[option.id] = isstring(option.name) and option.name or option.id
        end
    end
    ---@type PW.LoadoutContext
    local ctx = {
        lookup = function() return nil end, budget = 0, maxattachments = input.cap,
        adapterOptions = function() return offered end,
        isCosmetic = function(_, slotId, id) return pickedFacts(input, info, slotId, id).cosmetic end,
        lockedOptions = function(_, single) return lockedIn(input, info, single) end,
        attachmentLimit = function() return counts.levelLimit end
    }
    local _, problems = (PW.Loadout --[[@as PW.LoadoutLib]])._ValidateBuild(input.weaponId, input.weapon,
        input.build, ctx)
    ---@type string[]
    local lines = {}
    for _, problem in ipairs(problems) do
        lines[#lines + 1] = (names[problem.option] or problem.option) .. " (" .. problem.why .. ")"
    end
    local slotIds = table.GetKeys(input.build) --[[@as string[] ]]
    table.sort(slotIds)
    for _, slotId in ipairs(slotIds) do
        local id = input.build[slotId]
        if isstring(id) and input.banned[id] then lines[#lines + 1] = (names[id] or id) .. " (banned)" end
    end
    if counts.count > input.cap then
        lines[#lines + 1] = counts.count .. " attachments, at most " .. input.cap .. " in this match"
    end
    return lines
end

function lib.Gunsmith(input)
    local levelLimit = (not input.unlockAll) and input.weaponLevel or nil
    ---@type PW.LoadoutUIGunsmithCounts
    local counts = { count = 0, levelCount = 0, levelLimit = levelLimit }
    ---@type PW.LoadoutUIGunsmith
    local model = {
        gunsmith = #input.slots > 0, title = input.weaponName, slots = {}, count = 0, cap = input.cap,
        levelCount = 0, levelLimit = levelLimit, countText = "0 / " .. input.cap, over = false, problems = {},
        note = #input.slots > 0 and serverNote or noGunsmith
    }
    if not model.gunsmith then return model end
    local info = slotInfo(input)
    for slotId, id in pairs(input.build) do
        if isstring(id) then
            local facts = pickedFacts(input, info, slotId, id --[[@as string]])
            if not facts.cosmetic then counts.count = counts.count + 1 end
            if facts.levelCounted then counts.levelCount = counts.levelCount + 1 end
        end
    end
    for index, slot in ipairs(input.slots) do model.slots[index] = makeSlot(input, info[slot.id], counts) end
    model.count, model.levelCount = counts.count, counts.levelCount
    model.countText = counts.count .. " / " .. input.cap
    model.over = counts.count > input.cap or (levelLimit ~= nil and counts.levelCount > levelLimit)
    model.problems = preview(input, info, counts)
    return model
end

function lib.SetOption(build, slotId, option)
    local copy = table.Copy(build) --[[@as table<string, string|false>]]
    if option == nil or option == "" then copy[slotId] = nil else copy[slotId] = option end
    return copy
end
