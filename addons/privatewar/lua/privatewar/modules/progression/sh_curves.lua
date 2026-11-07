-- Progression, pure part 1 (T-4.9; 06-progression.md d.4): the level curves and the settings that tune them. Plain
-- numbers in, plain numbers out; the live settings are read by a thin wrapper at the bottom. Loaded by shared.lua.
--
-- Both layers start at level 1 with 0 XP. XP to next level L is floor(base * L ^ exponent); the player reaches level
-- N after the sum of XP to next over levels 1..N-1. At the maximum level the bar is full and the XP keeps counting.

local lib = PW.Progression --[[@as PW.ProgressionLib]]

lib.Defaults = {
    maxLevel = 55, xpBase = 1000, xpExp = 1.2, maxWeaponLevel = 30, weaponBase = 500, weaponExp = 1.1,
    xpScale = 1, unlockAll = false
}

---@param value any
---@param fallback number
---@return number
local function number(value, fallback)
    if isnumber(value) and value == value and math.abs(value --[[@as number]]) ~= math.huge then
        return value --[[@as number]]
    end
    return fallback
end

function lib._Params(read)
    local d = lib.Defaults
    ---@type PW.ProgressionParams
    local params = {
        maxLevel = math.max(1, math.floor(number(read("progression.maxlevel"), d.maxLevel))),
        xpBase = number(read("progression.xpbase"), d.xpBase),
        xpExp = number(read("progression.xpexp"), d.xpExp),
        maxWeaponLevel = math.max(1, math.floor(number(read("progression.maxweaponlevel"), d.maxWeaponLevel))),
        weaponBase = number(read("progression.weaponxpbase"), d.weaponBase),
        weaponExp = number(read("progression.weaponxpexp"), d.weaponExp),
        xpScale = math.max(0, number(read("progression.xpscale"), d.xpScale)),
        unlockAll = read("progression.unlockall") == true
    }
    return params
end

function lib._XpToNext(level, base, exponent)
    return math.floor(base * level ^ exponent)
end

function lib._XpForLevel(level, base, exponent)
    local total = 0
    for step = 1, level - 1 do total = total + lib._XpToNext(step, base, exponent) end
    return total
end

function lib._LevelOf(xp, base, exponent, maxLevel)
    local level, spent = 1, 0
    while level < maxLevel do
        local step = lib._XpToNext(level, base, exponent)
        if xp < spent + step then return level, xp - spent, step end
        spent = spent + step
        level = level + 1
    end
    return level, 0, 0
end

function lib._PlayerLevel(params, xp)
    return lib._LevelOf(xp, params.xpBase, params.xpExp, params.maxLevel)
end

function lib._WeaponLevel(params, xp)
    return lib._LevelOf(xp, params.weaponBase, params.weaponExp, params.maxWeaponLevel)
end

function lib._Fraction(into, need)
    if need <= 0 then return 1 end
    return math.Clamp(into / need, 0, 1)
end
