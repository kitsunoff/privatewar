-- Gunsmith, pure part (T-4.8; 05-loadout.md d.15, d.12). A weapon build is part of a class (loadout.builds). Plain
-- data in, plain data out; the adapter, progression and engine calls are injected (context fields, an api table).
-- Loaded by shared.lua through include; the server glue is sv_gunsmith.lua.
--
-- On save (every class repair, sh_classes_repair.lua) each build is checked in this order and each offending option is
-- removed with its reason, the rest is kept (05 d.12: repair, not reject):
--   1. "not available": the adapter does not offer the option in that build slot (unknown, gone from the catalogue, or
--      a weapon without a gunsmith: the HL2 fallback offers nothing);
--   2. "locked": progression (ctx.lockedOptions), asked per option so only the curated Unlock decides here;
--   3. "conflict: <code>": the adapter's static ADAPTER:Validate rejects the build slot;
--   4. "over the limit": the progression count limit (ctx.attachmentLimit, the weapon level): uncurated, non-cosmetic
--      options past it in build slot order.
-- The match cap (loadout.maxattachments, raised by wildcards through _EffectiveSlots) is not trimmed here: over it the
-- class is marked unavailable (sh_budget.lua, 05 d.12). So the limit a build meets is min(progression, match cap).
--
-- On spawn the build is applied to the live weapon (ADAPTER:Apply); options that did not stick are reported once and
-- dropped from the picked class with the reason "not installed" (05 d.15 item 4).

local lib = PW.Loadout --[[@as PW.LoadoutLib]]

---@param tbl table<any, any>
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

---@param build table<string, string|false>
---@param problems PW.GunsmithProblem[]
---@param slot string
---@param why string
local function reject(build, problems, slot, why)
    problems[#problems + 1] = { slot = slot, option = build[slot] --[[@as string]], why = why }
    build[slot] = nil
end

---@param weaponId string
---@param build table<string, string|false>
---@param ctx PW.LoadoutContext
---@param problems PW.GunsmithProblem[]
local function checkOffered(weaponId, build, ctx, problems)
    if ctx.adapterOptions == nil then return end
    local offered = ctx.adapterOptions(weaponId, build) or {}
    for _, slot in ipairs(sortedKeys(build)) do
        local option, options = build[slot], offered[slot]
        if isstring(option) and (options == nil or not options[option --[[@as string]]]) then
            reject(build, problems, slot, "not available")
        end
    end
end

---@param weaponId string
---@param build table<string, string|false>
---@param ctx PW.LoadoutContext
---@param problems PW.GunsmithProblem[]
local function checkLocked(weaponId, build, ctx, problems)
    if ctx.lockedOptions == nil then return end
    for _, slot in ipairs(sortedKeys(build)) do
        local option = build[slot]
        -- One option at a time: the count limit of progression is judged by checkLimit with the wildcards in mind.
        if isstring(option) and (ctx.lockedOptions(weaponId, { [slot] = option }) or {})[option --[[@as string]]] then
            reject(build, problems, slot, "locked")
        end
    end
end

---@param weaponId string
---@param build table<string, string|false>
---@param ctx PW.LoadoutContext
---@param problems PW.GunsmithProblem[]
local function checkConflicts(weaponId, build, ctx, problems)
    if ctx.adapterValidate == nil or next(build) == nil then return end
    local rejected = ctx.adapterValidate(weaponId, table.Copy(build)) or {}
    for _, slot in ipairs(sortedKeys(rejected)) do
        if isstring(build[slot]) then
            local code = rejected[slot]
            reject(build, problems, slot, isstring(code) and code ~= "" and "conflict: " .. code or "conflict")
        end
    end
end

---Is an option counted toward the progression limit (no curated Unlock, not cosmetic)?
---@param weaponId string
---@param weapon table<string, any>
---@param slot string
---@param option string
---@param ctx PW.LoadoutContext
---@return boolean
local function counted(weaponId, weapon, slot, option, ctx)
    local entries = istable(weapon.Attachments) and weapon.Attachments or {}
    local camos = istable(weapon.Camos) and weapon.Camos or {}
    local entry = istable(entries[option]) and entries[option] or {}
    if entry.Unlock ~= nil or entry.Cosmetic == true or camos[option] ~= nil then return false end
    return not (ctx.isCosmetic ~= nil and ctx.isCosmetic(weaponId, slot, option) == true)
end

---@param weaponId string
---@param weapon table<string, any>
---@param build table<string, string|false>
---@param ctx PW.LoadoutContext
---@param problems PW.GunsmithProblem[]
local function checkLimit(weaponId, weapon, build, ctx, problems)
    local limit = ctx.attachmentLimit ~= nil and ctx.attachmentLimit(weaponId) or nil
    if limit == nil then return end
    local count = 0
    for _, slot in ipairs(sortedKeys(build)) do
        local option = build[slot]
        if isstring(option) and counted(weaponId, weapon, slot, option --[[@as string]], ctx) then
            count = count + 1
            if count > limit then reject(build, problems, slot, "over the limit") end
        end
    end
end

function lib._ValidateBuild(weaponId, weapon, build, ctx)
    ---@type table<string, string|false>
    local clean = {}
    for slot, option in pairs(build) do
        if isstring(slot) and (isstring(option) or option == false) then clean[slot] = option end
    end
    ---@type PW.GunsmithProblem[]
    local problems = {}
    checkOffered(weaponId, clean, ctx, problems)
    checkLocked(weaponId, clean, ctx, problems)
    checkConflicts(weaponId, clean, ctx, problems)
    checkLimit(weaponId, weapon, clean, ctx, problems)
    return clean, problems
end

-- Apply on spawn ----------------------------------------------------------------------------------------------------

function lib._NotStuck(build, stuck)
    local applied = istable(stuck) and stuck or {}
    ---@type string[]
    local missing = {}
    for _, slot in ipairs(sortedKeys(build)) do
        local option = build[slot]
        if isstring(option) and applied[slot] ~= option then missing[#missing + 1] = option end
    end
    return missing
end

---@param build any
---@return boolean
local function hasOptions(build)
    return istable(build) and next(build) ~= nil
end

---Applies one build; the options that did not stick, or nil.
---@param slotId string
---@param wep any
---@param build table<string, any>
---@param api PW.LoadoutGunsmithApi
---@return string[]?
local function applyOne(slotId, wep, build, api)
    if not api.gunsmith(wep) then
        api.debug("gunsmith: the weapon of slot " .. slotId .. " has no gunsmith; its build is not applied")
        return nil
    end
    local missing = lib._NotStuck(build, api.apply(wep, table.Copy(build)))
    return #missing > 0 and missing or nil
end

function lib._ApplyBuilds(loadout, weapons, api)
    local builds = istable(loadout.builds) and loadout.builds or {}
    ---@type PW.GunsmithFailure[]
    local failures = {}
    for _, slotId in ipairs(sortedKeys(builds --[[@as table<string, any>]])) do
        local build, wep = (builds --[[@as table<string, any>]])[slotId], weapons[slotId]
        local missing = wep ~= nil and hasOptions(build) and applyOne(slotId, wep, build, api) or nil
        if missing ~= nil then failures[#failures + 1] = { slot = slotId, weapon = wep, options = missing } end
    end
    return failures
end

function lib._NotInstalledText(failures, nameOf)
    ---@type string[]
    local parts = {}
    for _, failure in ipairs(failures) do
        parts[#parts + 1] = nameOf(failure.weapon) .. ": " .. table.concat(failure.options, ", ")
    end
    return "Attachments not installed (they conflict on the weapon): " .. table.concat(parts, "; ")
end

function lib._DropOptions(loadout, drops, why)
    local copy = table.Copy(loadout) --[[@as PW.Loadout]]
    ---@type string[]
    local removed = {}
    local builds = copy.builds
    if drops == nil or not istable(builds) then return copy, removed end
    for _, slotId in ipairs(sortedKeys(drops)) do
        local build = (builds --[[@as table<string, table<string, string|false>>]])[slotId]
        for _, slot in ipairs(istable(build) and sortedKeys(build) or {}) do
            local option = build[slot]
            if isstring(option) and drops[slotId][option] then
                build[slot] = nil
                removed[#removed + 1] = option .. " (" .. why .. ")"
            end
        end
        if istable(build) and next(build) == nil then (builds --[[@as table<string, any>]])[slotId] = nil end
    end
    if next(builds --[[@as table]]) == nil then copy.builds = nil end
    return copy, removed
end
