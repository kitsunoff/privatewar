-- Teams module (T-1.16; 02-modes.md d.6, 08-lobby.md d.4, 00-core.md d.9). A mode declares MODE.Teams = N
-- (0 = FFA); this module owns everything about teams: the list of active teams, the enemy check, the balanced
-- assignment when LIVE starts, late join placement and the team part of pending_match.json. Shared: the API and
-- the pure rules (plain data in, plain data out). Server glue: init.lua. Team indices are 1..N; team names and
-- colours are cosmetic defaults ("Team <i>").

MODULE.Name = "Teams"

local lib = (rawget(PW, "Teams") or {}) --[[@as PW.TeamsLib]]
PW.Teams = lib

lib._CountKey = "pw_teams"

local palette = {
    Color(70, 130, 220), Color(220, 70, 60), Color(80, 180, 90), Color(230, 180, 40),
    Color(160, 90, 200), Color(60, 190, 190), Color(230, 120, 40), Color(200, 200, 200)
}

---@type table<integer, integer[]>
local lists = {}

---@return PW.TeamsStore
function lib._NewStore()
    return { pending = {} }
end

PW._Teams = PW._Teams or lib._NewStore()

---@param mode table?
---@return integer
function lib._TeamCount(mode)
    if mode == nil then return 0 end
    local count = (mode --[[@as table<string, any>]]).Teams --[[@as any]]
    if not isnumber(count) then return 0 end
    local n = math.floor(count --[[@as number]])
    if n < 0 then return 0 end
    return n
end

---@param team any
---@param n integer
---@return boolean
local function inRange(team, n)
    return isnumber(team) and team >= 1 and team <= n and team == math.floor(team)
end

---@param counts table<integer, integer>
---@param n integer
---@return integer?
function lib._Smallest(counts, n)
    ---@type integer?
    local best = nil
    local bestCount = math.huge
    for i = 1, n do
        local count = counts[i] or 0
        if count < bestCount then
            best, bestCount = i, count
        end
    end
    return best
end

---@param n integer
---@param list integer[]
---@return integer[]
function lib._Counts(n, list)
    ---@type integer[]
    local counts = {}
    for i = 1, n do counts[i] = 0 end
    for _, team in ipairs(list) do
        if inRange(team, n) then counts[team] = counts[team] + 1 end
    end
    return counts
end

---@param n integer
---@param entries PW.TeamEntry[]
---@return table<any, integer>
function lib._Assign(n, entries)
    ---@type table<any, integer>
    local result = {}
    if n <= 0 then return result end
    local base, extra = math.floor(#entries / n), #entries % n
    local counts = lib._Counts(n, {})
    local big = 0
    ---@type PW.TeamEntry[]
    local rest = {}
    -- A preference is kept while every team can still end with base or base + 1 players, at most extra of them
    -- with base + 1; the smallest-first fill below then always ends balanced.
    for _, entry in ipairs(entries) do
        local pref = entry.pref
        if pref ~= nil and inRange(pref, n) and (counts[pref] < base or (counts[pref] == base and big < extra)) then
            if counts[pref] == base then big = big + 1 end
            counts[pref] = counts[pref] + 1
            result[entry.id] = pref
        else
            rest[#rest + 1] = entry
        end
    end
    for _, entry in ipairs(rest) do
        local team = lib._Smallest(counts, n) --[[@as integer]]
        counts[team] = counts[team] + 1
        result[entry.id] = team
    end
    return result
end

---@param n integer
---@param same boolean
---@param teamA integer
---@param teamB integer
---@return boolean
function lib._IsEnemyRule(n, same, teamA, teamB)
    if same then return false end
    if n <= 0 then return true end
    return teamA ~= teamB
end

---@param n integer
---@param rows PW.TeamFileRow[]
---@return table<string, integer>
function lib._ForFile(n, rows)
    ---@type table<string, integer>
    local teams = {}
    for _, row in ipairs(rows) do
        if inRange(row.team, n) then teams[row.sid] = row.team end
    end
    return teams
end

---@param raw table<any, any>
---@return table<string, integer>
function lib._FromFile(raw)
    ---@type table<string, integer>
    local teams = {}
    if not istable(raw) then return teams end
    for sid, team in pairs(raw) do
        if isstring(sid) and string.match(sid, "^%d+$") ~= nil and isnumber(team) and team >= 1
            and team == math.floor(team) then
            teams[sid] = team
        end
    end
    return teams
end

---Where each team goes when the sides swap: team i moves to i + 1, the last team to 1 (n = 2: a plain swap).
---@param n integer
---@return table<integer, integer>
function lib._SwapMap(n)
    ---@type table<integer, integer>
    local map = {}
    for i = 1, n do map[i] = i % n + 1 end
    return map
end

---The assignment after a side swap; entries outside 1..n keep their team.
---@param n integer
---@param assignment table<any, integer>
---@return table<any, integer>
function lib._SwapAssignment(n, assignment)
    local map = lib._SwapMap(math.max(n, 0))
    ---@type table<any, integer>
    local result = {}
    for id, team in pairs(assignment) do result[id] = map[team] or team end
    return result
end

---The list { 1, ..., n }, cached; the engine team table gets the default name and colour of each index.
---@param n integer
---@return integer[]
local function listFor(n)
    local list = lists[n]
    if list ~= nil then return list end
    list = {}
    for i = 1, n do
        list[i] = i
        if not team.Valid(i) then
            team.SetUp(i, "Team " .. i, palette[(i - 1) % #palette + 1], false)
        end
    end
    lists[n] = list
    return list
end

---@return integer
local function activeCount()
    if SERVER then return lib._TeamCount(PW.ActiveMode) end
    return GetGlobal2Int(lib._CountKey, 0)
end

---@return integer[]
function lib.GetActive()
    return listFor(activeCount())
end

---@param a Player
---@param b Player
---@return boolean
function PW.IsEnemy(a, b)
    local answer = PW.Ask("PW_IsEnemy", a, b)
    if answer == true or answer == false then return answer end
    return lib._IsEnemyRule(activeCount(), a == b, a:Team(), b:Team())
end
