-- UTC week math without the host clock, time zone or Economy module.
local lib = PW.Challenges --[[@as PW.ChallengesLib]]
local daySeconds = 86400
local epochMonday = 4 -- 1970-01-05

---The shop's March-based Gregorian day arithmetic, specialized to January 1.
---@param year integer
---@return integer
local function januaryFirst(year)
    local marchYear = year - 1
    local era = math.floor(marchYear / 400)
    local yearOfEra = marchYear - era * 400
    return era * 146097 + yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + 306 - 719468
end

---Inverse day arithmetic: only the year is needed, not the month or the day.
---@param day integer
---@return integer
local function yearOf(day)
    local shifted = day + 719468
    local era = math.floor(shifted / 146097)
    local dayOfEra = shifted - era * 146097
    local leaps = math.floor(dayOfEra / 1460) - math.floor(dayOfEra / 36524) + math.floor(dayOfEra / 146096)
    local yearOfEra = math.floor((dayOfEra - leaps) / 365)
    local marchDay = dayOfEra - (yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100))
    return era * 400 + yearOfEra + (marchDay >= 306 and 1 or 0)
end

function lib.WeekIndex(unixUtc)
    return math.floor((math.floor(unixUtc / daySeconds) - epochMonday) / 7)
end

function lib.WeekLabel(index)
    local thursday = index * 7 + epochMonday + 3
    local year = yearOf(thursday)
    local week = math.floor((thursday - januaryFirst(year)) / 7) + 1
    return string.format("%04d-W%02d", year, week)
end

function lib.WeekBounds(index)
    local startsAt = (index * 7 + epochMonday) * daySeconds
    return startsAt, startsAt + 7 * daySeconds
end
