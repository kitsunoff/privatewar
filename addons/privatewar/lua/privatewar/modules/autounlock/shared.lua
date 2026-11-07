-- Stat-based unlock levels (T-11.7; 06-progression.md d.2 revision 2026-11-07; docs/api/progression.md "Automatic
-- unlock levels"). Shared: both realms build the same levels, because the unlock checks answer on the client too.
-- Generic: works on any weapon adapter that gives stats (GetBaseStats) and, for attachments, GetSlots, GetOptions
-- and the optional GetOptionStats; an adapter with few stats (HL2 weapons) still gets levels, missing stats count as
-- the middle of their category. The pure rules are sh_rules.lua; this file is the thin glue.
--
-- Decisions of the lane agent:
--   1. Runs on PW_WeaponsLoaded, not in PW_RegisterWeapons: the listener order of a hook is undefined, and only after
--      the phase are the catalogue fills and every hand curation (declarative files, programmatic registrations) in
--      the registry, so the soft registration fills exactly the gaps.
--   2. Candidates: the weapons registry entries with a Category whose Kind is not melee, throwable or other.
--      Cosmetic slots and options get no level (they keep the old rule); a weapon with a Price stays shop-only.
--      Weapons of the preset classes (kind classes) are starters: open at level 1, so the presets stay usable for a
--      new player; they count toward the 1-2 open weapons of their category.
--   3. Cache: data/privatewar/unlocks_cache.json holds one result and its key: a hash of the weapon set (class and
--      category), the option set key of each adapter (GetOptionSetKey), the weights, the level caps and Version.
--   4. The host setting progression.autounlock (declared by the progression module) is read once per run: a change
--      takes effect at the next map or pw_reload.

MODULE.Name = "Automatic unlock levels"

local lib = (rawget(PW, "AutoUnlock") or {}) --[[@as PW.AutoUnlockLib]]
PW.AutoUnlock = lib

---@type PW.AutoUnlockStore
PW._AutoUnlock = PW._AutoUnlock or {}

lib.CachePath = "privatewar/unlocks_cache.json"
lib.Version = 1

if SERVER then AddCSLuaFile("privatewar/modules/autounlock/sh_rules.lua") end
include("privatewar/modules/autounlock/sh_rules.lua")

local skipKinds = { melee = true, throwable = true, other = true }

function lib._DefaultEnv()
    return {
        setting = function(id) return PW.Setting(id) end,
        adapterFor = function(class) return PW.Adapters.For(class) end,
        call = function(adapter, method, ...) return PW.Adapters.Call(adapter, method, ...) end,
        read = function(path) return file.Read(path, "DATA") end,
        write = function(path, text)
            file.CreateDir(string.GetPathFromFilename(path))
            file.Write(path, text)
        end,
        hash = function(text) return util.SHA256(text) end,
        clock = SysTime,
        log = function(message) print("[PW] " .. message) end,
        starters = function() return lib._PresetWeapons(rawget(PW, "Classes") --[[@as PW.Registry?]]) end
    }
end

function lib._PresetWeapons(classes)
    ---@type table<string, boolean>
    local set = {}
    if classes == nil then return set end
    for _, preset in ipairs(classes.GetList()) do
        local loadout = istable(preset.Loadout) and preset.Loadout or {}
        for _, value in pairs(loadout --[[@as table<string, any>]]) do
            if isstring(value) then set[value] = true end
        end
    end
    return set
end

---@class PW.AutoUnlockCandidate
---@field class string
---@field category string
---@field adapter? PW.Adapter
---@field starter boolean

---The weapons that get a level: an entry with a Category that is not melee, a throwable or other; sorted by class.
---@param reg PW.Registry
---@param env PW.AutoUnlockEnv
---@return PW.AutoUnlockCandidate[]
local function candidates(reg, env)
    ---@type PW.AutoUnlockCandidate[]
    local list = {}
    local starters = env.starters ~= nil and env.starters() or {}
    for _, entity in ipairs(reg.GetList()) do
        local category, kind = entity.Category, entity.Kind
        if isstring(category) and not skipKinds[kind or ""] then
            local class = entity.ClassName
            list[#list + 1] = { class = class, category = category, adapter = env.adapterFor(class),
                starter = starters[class] == true }
        end
    end
    return list
end

---@param env PW.AutoUnlockEnv
---@return PW.AutoUnlockCaps
local function capsOf(env)
    local maxLevel, maxWeaponLevel = env.setting("progression.maxlevel"), env.setting("progression.maxweaponlevel")
    return {
        maxLevel = isnumber(maxLevel) and math.floor(maxLevel) or 55,
        maxWeaponLevel = isnumber(maxWeaponLevel) and math.floor(maxWeaponLevel) or 30
    }
end

---What the cache key covers.
---@param list PW.AutoUnlockCandidate[]
---@param env PW.AutoUnlockEnv
---@param caps PW.AutoUnlockCaps
---@return table
local function keyParts(list, env, caps)
    ---@type string[]
    local weaponSet = {}
    ---@type string[]
    local optionSets = {}
    ---@type table<PW.Adapter, boolean>
    local seen = {}
    for _, item in ipairs(list) do
        weaponSet[#weaponSet + 1] = item.class .. "|" .. item.category .. (item.starter and "|starter" or "")
        local adapter = item.adapter
        if adapter ~= nil and not seen[adapter] then
            seen[adapter] = true
            local setKey = env.call(adapter, "GetOptionSetKey")
            local setText = isstring(setKey) and tostring(setKey) or ""
            optionSets[#optionSets + 1] = tostring(adapter.ClassName) .. ":" .. setText
        end
    end
    table.sort(optionSets)
    return { version = lib.Version, weights = lib.Weights, caps = caps, weapons = weaponSet, options = optionSets }
end

---The non-cosmetic options of a slot, with the stats of each.
---@param adapter PW.Adapter
---@param class string
---@param slotId PW.SlotId
---@param env PW.AutoUnlockEnv
---@return PW.AutoUnlockOption[]
local function optionsOf(adapter, class, slotId, env)
    ---@type PW.AutoUnlockOption[]
    local options = {}
    local list = env.call(adapter, "GetOptions", class, slotId) --[[@as PW.Option[]? ]]
    for _, option in ipairs(list or {}) do
        if not option.cosmetic then
            local stats = env.call(adapter, "GetOptionStats", class, slotId, option.id)
            options[#options + 1] = { id = option.id, stats = istable(stats) and stats or nil }
        end
    end
    return options
end

---The non-cosmetic slots of a class.
---@param adapter PW.Adapter
---@param class string
---@param env PW.AutoUnlockEnv
---@return PW.AutoUnlockSlot[]
local function slotsOf(adapter, class, env)
    ---@type PW.AutoUnlockSlot[]
    local slots = {}
    local list = env.call(adapter, "GetSlots", class, nil) --[[@as PW.Slot[]? ]]
    for _, slot in ipairs(list or {}) do
        if not slot.cosmetic then
            slots[#slots + 1] = { id = slot.id, options = optionsOf(adapter, class, slot.id, env) }
        end
    end
    return slots
end

---@param list PW.AutoUnlockCandidate[]
---@param env PW.AutoUnlockEnv
---@return PW.AutoUnlockWeapon[]
local function gather(list, env)
    ---@type PW.AutoUnlockWeapon[]
    local out = {}
    for _, item in ipairs(list) do
        local stats, slots = {}, {}
        if item.adapter ~= nil then
            local value = env.call(item.adapter, "GetBaseStats", item.class)
            stats = istable(value) and value or {}
            slots = slotsOf(item.adapter, item.class, env)
        end
        out[#out + 1] = { class = item.class, category = item.category, stats = stats, slots = slots,
            starter = item.starter }
    end
    return out
end

---The cached result when the file holds the same key.
---@param env PW.AutoUnlockEnv
---@param key string
---@return PW.AutoUnlockResult?
local function readCache(env, key)
    local text = env.read(lib.CachePath)
    if not isstring(text) then return nil end
    local data = util.JSONToTable(text --[[@as string]], false, true) --[[@as table<string, any>?]]
    if data == nil or data.key ~= key then return nil end
    local result = data.result --[[@as table<string, any>?]]
    if result == nil or not istable(result) or not istable(result.weapons) or not istable(result.attachments)
        or not istable(result.report) then return nil end
    return result --[[@as PW.AutoUnlockResult]]
end

---Soft registration of every computed weapon; returns how many entries got fields.
---@param reg PW.Registry
---@param result PW.AutoUnlockResult
---@return integer
local function register(reg, result)
    ---@type table<string, boolean>
    local classes = {}
    for class in pairs(result.weapons) do classes[class] = true end
    for class in pairs(result.attachments) do classes[class] = true end
    local sorted = table.GetKeys(classes) --[[@as string[] ]]
    table.sort(sorted)
    local count = 0
    for _, class in ipairs(sorted) do
        local existing = reg.Get(class) or reg.GetStored(class)
        local entry = existing ~= nil and lib._EntryFor(existing, result.weapons[class], result.attachments[class])
        if entry then
            reg.Register(entry, class, { soft = true })
            count = count + 1
        end
    end
    return count
end

---@param run PW.AutoUnlockRun
---@param env PW.AutoUnlockEnv
local function report(run, env)
    local r = (run.result --[[@as PW.AutoUnlockResult]]).report
    env.log(string.format("autounlock: %d weapons in %d categories, %d options (%d without numeric stats: middle " ..
        "level of their slot), %d entries registered softly; cache %s, %.1f ms", r.weapons, r.categories, r.options,
        r.noStats, run.registered, run.cacheHit and "hit" or "miss", run.ms))
end

function lib.Run(reg, env)
    env = env or lib._DefaultEnv()
    local start = env.clock()
    ---@type PW.AutoUnlockRun
    local run = { enabled = false, cacheHit = false, registered = 0, ms = 0 }
    if env.setting("progression.autounlock") == false then
        env.log("autounlock: off (progression.autounlock); attachments unlock by count")
        return run
    end
    run.enabled = true
    local caps = capsOf(env)
    local list = candidates(reg, env)
    local key = lib._CacheKey(keyParts(list, env, caps), env.hash)
    local result = readCache(env, key)
    run.cacheHit = result ~= nil
    if result == nil then
        result = lib._Compute(gather(list, env), lib.Weights, caps)
        env.write(lib.CachePath, util.TableToJSON({ key = key, version = lib.Version, result = result }))
    end
    run.result = result
    run.registered = register(reg, result)
    run.ms = (env.clock() - start) * 1000
    PW._AutoUnlock.last = run
    report(run, env)
    return run
end

function MODULE:PW_WeaponsLoaded()
    local reg = rawget(PW, "Weapons") --[[@as PW.Registry?]]
    if reg ~= nil then lib.Run(reg) end
end
