-- Economy, pure part 1 (T-4.12; 06-progression.md d.6): the date-seeded store rotation. "Featured" changes daily,
-- "Weekly" weekly, with no backend: the selection is a pure function of (date, catalogue, slots), so the server and
-- every client compute the same shop. Plain data in, plain data out; no engine, no clock, no global random state.
--
-- A date is "YYYY-MM-DD" (UTC; lib.Today in shared.lua reads the clock). The day number counts days since 1970-01-01;
-- a week starts on Monday. The seed mixes the period (day or week number) with a salt per channel, then a small
-- integer generator (MINSTD: 48271 * state mod 2^31 - 1, exact in doubles) drives a partial Fisher-Yates over the
-- catalogue ids in sorted order, so the result does not depend on the order the catalogue was listed in.
-- Loaded by shared.lua.

local lib = PW.Economy --[[@as PW.EconomyLib]]

local modulus = 2147483647
local multiplier = 48271
local spread = 2654435761
local epochMonday = 4 -- 1970-01-05 is the first Monday, day number 4

---@param year integer
---@param month integer
---@return integer
local function daysInMonth(year, month)
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    local leap = (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
    if month == 2 and leap then return 29 end
    return days[month]
end

function lib._DayNumber(date)
    if not isstring(date) then return nil end
    local text = date --[[@as string]]
    local y, m, d = string.match(text, "^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if y == nil or m == nil or d == nil then return nil end
    local year, month, day = tonumber(y) --[[@as integer]], tonumber(m) --[[@as integer]], tonumber(d) --[[@as integer]]
    if month < 1 or month > 12 or day < 1 or day > daysInMonth(year, month) then return nil end
    if month <= 2 then year = year - 1 end
    local era = math.floor(year / 400)
    local yearOfEra = year - era * 400
    local monthIndex = (month + 9) % 12
    local dayOfYear = math.floor((153 * monthIndex + 2) / 5) + day - 1
    local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
    return era * 146097 + dayOfEra - 719468
end

function lib._WeekNumber(day)
    return math.floor((day - epochMonday) / 7)
end

---@param text string
---@return integer
local function hashOf(text)
    local hash = 5381
    for index = 1, #text do hash = (hash * 33 + string.byte(text, index)) % modulus end
    return hash
end

---A seed in 1..modulus-1 for a channel and a period; adjacent periods land far apart.
---@param salt string
---@param period integer
---@return integer
local function seedOf(salt, period)
    local seed = ((period + 1) * spread + hashOf(salt)) % modulus
    if seed == 0 then return 1 end
    return seed
end

function lib._Rotate(seed, ids, slots)
    ---@type string[]
    local pool = {}
    for index, id in ipairs(ids) do pool[index] = id end
    table.sort(pool)
    local state = math.floor(seed) % modulus
    if state == 0 then state = 1 end
    local function nextFraction()
        state = (state * multiplier) % modulus
        return state / modulus
    end
    for _ = 1, 3 do nextFraction() end
    local count = math.min(math.max(math.floor(slots), 0), #pool)
    for index = 1, count do
        local pick = index + math.floor(nextFraction() * (#pool - index + 1))
        pool[index], pool[pick] = pool[pick], pool[index]
    end
    ---@type string[]
    local chosen = {}
    for index = 1, count do chosen[index] = pool[index] end
    return chosen
end

function lib._Featured(date, ids, slots)
    local day = lib._DayNumber(date)
    if day == nil then return {} end
    return lib._Rotate(seedOf("daily", day), ids, slots)
end

function lib._Weekly(date, ids, slots)
    local day = lib._DayNumber(date)
    if day == nil then return {} end
    return lib._Rotate(seedOf("weekly", lib._WeekNumber(day)), ids, slots)
end
