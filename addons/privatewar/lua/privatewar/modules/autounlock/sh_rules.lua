-- Stat-based unlock levels, pure part (T-11.7; 06-progression.md d.2 revision 2026-11-07). Plain data in, plain data
-- out: the weapon power score, the ranking, the level spreading, the attachment stat gain, the cache key and the merge
-- with existing curation. Loaded by shared.lua.
--
-- Formula (the weights are lib.Weights, pending confirmation in the local checklist section 7):
--   1. Weapon features, higher is better: -TTK near, -TTK at the mid range (continuous shots to kill times the shot
--      interval), rate of fire, -recoil, -spread, -ADS time, -sprint-to-fire time, move speed.
--   2. Each feature is normalised within the category to 0..1 (min-max; a missing value or a category where all are
--      equal gives 0.5). The power score is the weighted sum.
--   3. Weapons are ranked weakest first (ties by class). The first 1 or 2 (openTwoFrom) open at level 1; the rest
--      are spread evenly over 2..maxLevel-1: level = 1 + round((cap - 1) * i / (rest + 1)).
--   4. An option's stat gain is the weighted sum of the logarithms of its multipliers, signed so that a better stat
--      is positive (magazineAdd as the ratio to the weapon's magazine). Options are ranked within their slot and
--      spread over weapon levels the same way with none open at level 1; an option without numeric stats gets the
--      middle of the levels of its slot (of 1..cap when no option of the slot has stats).

local lib = PW.AutoUnlock --[[@as PW.AutoUnlockLib]]

lib.Weights = {
    weapon = { ttkNear = 0.30, ttkMid = 0.25, rpm = 0.05, recoil = 0.15, spread = 0.05, adsTime = 0.10,
        sprintToFire = 0.05, moveSpeed = 0.05 },
    option = { damage = 1.0, range = 0.4, rpm = 0.6, recoil = 0.8, spread = 0.5, adsTime = 0.6, sprintToFire = 0.4,
        moveSpeed = 0.5, reloadTime = 0.3, magazine = 0.3 },
    health = 100,
    midRange = 20,
    defaultRpm = 600,
    defaultMagazine = 30,
    openTwoFrom = 4
}

-- Direction of each option stat: +1 when a larger value is better.
local optionSign = { damage = 1, range = 1, rpm = 1, recoil = -1, spread = -1, adsTime = -1, sprintToFire = -1,
    moveSpeed = 1, reloadTime = -1 }

---@param value any
---@return number?
local function positive(value)
    if isnumber(value) and value > 0 and value == value and value < math.huge then return value --[[@as number]] end
    return nil
end

---@param x number
---@return integer
local function round(x)
    return math.floor(x + 0.5)
end

---Damage at the mid range: interpolated between the near and far values when the ranges are known.
---@param s PW.Stats
---@param w PW.AutoUnlockWeights
---@return number?
local function midDamage(s, w)
    local near, far = positive(s.damageNear), positive(s.damageFar)
    if near == nil then return far end
    if far == nil then return near end
    local from, to = positive(s.rangeNear), positive(s.rangeFar)
    if from == nil or to == nil or to <= from then return (near + far) / 2 end
    local t = math.Clamp((w.midRange - from) / (to - from), 0, 1)
    return near + (far - near) * t
end

---Time to kill in seconds with continuous shots to kill (so that more damage always helps).
---@param damage number?
---@param rpm number?
---@param w PW.AutoUnlockWeights
---@return number?
local function ttk(damage, rpm, w)
    if damage == nil then return nil end
    local shots = math.max(1, w.health / damage)
    return (shots - 1) * 60 / (rpm or w.defaultRpm)
end

---@param value number?
---@return number?
local function negated(value)
    if value == nil then return nil end
    return -value
end

function lib._WeaponFeatures(stats, w)
    local s = istable(stats) and stats or {}
    local rpm = positive(s.rpm)
    return {
        ttkNear = negated(ttk(positive(s.damageNear) or positive(s.damageFar), rpm, w)),
        ttkMid = negated(ttk(midDamage(s, w), rpm, w)),
        rpm = rpm,
        recoil = negated(positive(s.recoil)),
        spread = negated(positive(s.spread)),
        adsTime = negated(positive(s.adsTime)),
        sprintToFire = negated(positive(s.sprintToFire)),
        moveSpeed = positive(s.moveMult)
    }
end

---Min and max of one feature over a category; nil when no weapon has it.
---@param features PW.AutoUnlockFeatures
---@param name string
---@return number?, number?
local function rangeOf(features, name)
    local low, high = nil, nil
    for _, values in pairs(features) do
        local value = values[name]
        if value ~= nil then
            low = (low == nil or value < low) and value or low
            high = (high == nil or value > high) and value or high
        end
    end
    return low, high
end

function lib._ScoreCategory(features, w)
    ---@type table<string, number>
    local scores = {}
    for class in pairs(features) do scores[class] = 0 end
    for name, weight in pairs(w.weapon) do
        local low, high = rangeOf(features, name)
        for class, values in pairs(features) do
            local value = values[name]
            local norm = 0.5
            if value ~= nil and low ~= nil and high ~= nil and high > low then norm = (value - low) / (high - low) end
            scores[class] = scores[class] + weight * norm
        end
    end
    return scores
end

function lib._Rank(scores)
    ---@type string[]
    local ids = table.GetKeys(scores) --[[@as string[] ]]
    table.sort(ids, function(a, b)
        if scores[a] ~= scores[b] then return scores[a] < scores[b] end
        return a < b
    end)
    return ids
end

function lib._Spread(n, open, cap)
    ---@type integer[]
    local levels = {}
    local first = math.min(n, math.max(0, open))
    local rest = n - first
    for i = 1, first do levels[i] = 1 end
    for i = 1, rest do
        levels[first + i] = math.Clamp(1 + round((cap - 1) * i / (rest + 1)), 1, math.max(1, cap))
    end
    return levels
end

function lib._OpenCount(n, w)
    if n >= w.openTwoFrom then return 2 end
    return 1
end

function lib._OptionGain(stats, base, w)
    local gain = 0
    for name, sign in pairs(optionSign) do
        local mult = positive(stats[name])
        local weight = w.option[name] or 0
        if mult ~= nil then gain = gain + weight * sign * math.log(mult) end
    end
    local add = stats.magazineAdd
    if isnumber(add) and add ~= 0 then
        local magazine = positive(base.magazine) or w.defaultMagazine
        local ratio = math.max(0.01, (magazine + add) / magazine)
        gain = gain + (w.option.magazine or 0) * math.log(ratio)
    end
    return gain
end

function lib._SlotLevels(slot, base, w, cap)
    ---@type table<string, number>
    local gains = {}
    ---@type string[]
    local plain = {}
    for _, option in ipairs(slot.options or {}) do
        if istable(option.stats) and next(option.stats) ~= nil then
            gains[option.id] = lib._OptionGain(option.stats, base, w)
        else
            plain[#plain + 1] = option.id
        end
    end
    ---@type table<string, integer>
    local levels = {}
    local ranked = lib._Rank(gains)
    local spread = lib._Spread(#ranked, 0, cap)
    for i, id in ipairs(ranked) do levels[id] = spread[i] end
    local middle = round((1 + cap) / 2)
    if #ranked > 0 then middle = round((spread[1] + spread[#ranked]) / 2) end
    for _, id in ipairs(plain) do levels[id] = middle end
    return { levels = levels, noStats = #plain }
end

---Weapon levels of one category into result.weapons.
---@param list PW.AutoUnlockWeapon[]
---@param w PW.AutoUnlockWeights
---@param cap integer
---@param out table<string, integer>
local function categoryLevels(list, w, cap, out)
    ---@type PW.AutoUnlockFeatures
    local features = {}
    local starters = 0
    for _, item in ipairs(list) do features[item.class] = lib._WeaponFeatures(item.stats, w) end
    -- Starters (weapons of the preset classes) open at level 1, are scored with the category but not ranked, and
    -- count toward the 1-2 weapons open at once.
    local scores = lib._ScoreCategory(features, w)
    for _, item in ipairs(list) do
        if item.starter then
            out[item.class] = 1
            scores[item.class] = nil
            starters = starters + 1
        end
    end
    local ranked = lib._Rank(scores)
    local levels = lib._Spread(#ranked, math.max(0, lib._OpenCount(#list, w) - starters), cap)
    for i, class in ipairs(ranked) do out[class] = levels[i] end
end

---Option levels of one weapon (the lowest level when an option sits in several slots).
---@param item PW.AutoUnlockWeapon
---@param w PW.AutoUnlockWeights
---@param cap integer
---@param report PW.AutoUnlockReport
---@return table<string, integer>?
local function weaponOptions(item, w, cap, report)
    ---@type table<string, integer>
    local levels = {}
    local any = false
    for _, slot in ipairs(item.slots or {}) do
        local res = lib._SlotLevels(slot, item.stats or {}, w, cap)
        report.noStats = report.noStats + res.noStats
        for id, level in pairs(res.levels) do
            if levels[id] == nil then report.options = report.options + 1 end
            levels[id] = math.min(levels[id] or level, level)
            any = true
        end
    end
    return any and levels or nil
end

function lib._Compute(list, w, caps)
    ---@type table<string, PW.AutoUnlockWeapon[]>
    local byCategory = {}
    ---@type PW.AutoUnlockResult
    local result = { weapons = {}, attachments = {},
        report = { weapons = 0, categories = 0, options = 0, noStats = 0 } }
    for _, item in ipairs(list) do
        local group = byCategory[item.category]
        if group == nil then
            group = {}
            byCategory[item.category] = group
            result.report.categories = result.report.categories + 1
        end
        group[#group + 1] = item
        result.report.weapons = result.report.weapons + 1
        result.attachments[item.class] = weaponOptions(item, w, caps.maxWeaponLevel, result.report)
    end
    for _, group in pairs(byCategory) do categoryLevels(group, w, caps.maxLevel, result.weapons) end
    return result
end

function lib._Canonical(value)
    if not istable(value) then
        if isnumber(value) then return string.format("%.6g", value) end
        return string.format("%q", tostring(value))
    end
    local tbl = value --[[@as table<any, any>]]
    ---@type { text: string, key: any }[]
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = { text = tostring(key), key = key } end
    table.sort(keys, function(a, b) return a.text < b.text end)
    ---@type string[]
    local parts = {}
    for _, entry in ipairs(keys) do
        parts[#parts + 1] = string.format("%q", entry.text) .. "=" .. lib._Canonical(tbl[entry.key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function lib._CacheKey(parts, hash)
    return hash(lib._Canonical(parts))
end

function lib._EntryFor(existing, level, options)
    local current = existing or {}
    if isnumber(current.Price) then return nil end
    ---@type table<string, any>
    local entry = {}
    if level ~= nil and current.Unlock == nil then entry.Unlock = level end
    if options ~= nil then
        ---@type table<string, table<string, integer>>
        local atts = {}
        for id, optionLevel in pairs(options) do atts[id] = { Unlock = optionLevel } end
        entry.Attachments = atts
    end
    if next(entry) == nil then return nil end
    return entry
end
