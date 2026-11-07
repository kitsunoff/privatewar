-- Postmatch summary (T-7.7; 08-lobby.md d.4, d.5; 10-frontend.md d.1 POSTMATCH "result + scoreboard, XP / unlocks
-- summary"). Pure and shared, so the server-side test runner covers it: the result banner from the match_rules result
-- and the local player, the final scoreboard order, the level bar segments and their animation, the medal and weapon
-- lists, the currency earned and when the client opens or closes the screen. The client glue is cl_postmatch.lua, the
-- screen screens/postmatch.lua. Everything here is plain data in, plain data out.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

local pm = (rawget(lib, "Postmatch") or {}) --[[@as PW.UIPostmatchLib]]
lib.Postmatch = pm

pm.RootId = "postmatch"
pm.Tab = "summary"
pm.Titles = { victory = "VICTORY", defeat = "DEFEAT", draw = "DRAW", over = "MATCH OVER" }
pm.Tokens = { victory = "positive", defeat = "negative", draw = "text", over = "text" }

local suffixes = { "ST", "ND", "RD" }

function pm.Ordinal(n)
    local teen = n % 100 >= 11 and n % 100 <= 13
    local suffix = not teen and suffixes[n % 10] or "TH"
    return tostring(n) .. suffix
end

function pm.Number(n)
    local value = math.floor(n)
    local sign = value < 0 and "-" or ""
    local text = tostring(math.abs(value))
    local out = ""
    while #text > 3 do
        out = "," .. string.sub(text, -3) .. out
        text = string.sub(text, 1, -4)
    end
    return sign .. text .. out
end

---@param rows PW.UIBoardRow[]
---@return PW.UIBoardRow[]
local function listed(rows)
    ---@type PW.UIBoardRow[]
    local out = {}
    for _, entry in ipairs(rows) do
        if not entry.spectator then out[#out + 1] = entry end
    end
    return out
end

function pm.Placement(rows, ownId)
    local players = listed(rows)
    ---@type PW.UIBoardRow?
    local own = nil
    for _, entry in ipairs(players) do
        if entry.id == ownId then own = entry end
    end
    if own == nil then return nil, #players end
    local place = 1
    for _, entry in ipairs(players) do
        if entry.kills > own.kills then place = place + 1 end
    end
    return place, #players
end

---@param facts PW.UIPostmatchFacts
---@return PW.UIPostmatchKind
local function kindOf(facts)
    if facts.draw then return "draw" end
    if facts.winner <= 0 then return "over" end
    if facts.teams > 0 then
        if facts.ownTeam < 1 or facts.ownTeam > facts.teams then return "over" end
        return facts.winner == facts.ownTeam and "victory" or "defeat"
    end
    return facts.winner == facts.ownId and "victory" or "defeat"
end

---"own : best other" of a team match; "" without scores or outside the teams.
---@param facts PW.UIPostmatchFacts
---@return string
local function teamLine(facts)
    local scores = facts.teamScores
    if scores == nil or facts.ownTeam < 1 or facts.ownTeam > facts.teams then return "" end
    ---@type integer?
    local other = nil
    for index = 1, facts.teams do
        local value = scores[index] or 0
        if index ~= facts.ownTeam and (other == nil or value > other) then other = value end
    end
    return tostring(scores[facts.ownTeam] or 0) .. " : " .. tostring(other or 0)
end

function pm.Result(facts)
    local kind = kindOf(facts)
    ---@type PW.UIPostmatchResult
    local result = { kind = kind, title = pm.Titles[kind], token = pm.Tokens[kind], subtitle = "" }
    if facts.teams > 0 then
        result.subtitle = teamLine(facts)
    elseif facts.rows ~= nil then
        local place, count = pm.Placement(facts.rows, facts.ownId)
        if place ~= nil then
            result.placement = place
            result.subtitle = pm.Ordinal(place) .. " OF " .. count
        end
    end
    return result
end

---Best first: the primary key, then the others, then the name (case-insensitive), then the id.
---@param primary "score"|"kills"
---@return fun(a: PW.UIBoardRow, b: PW.UIBoardRow): boolean
local function rowOrder(primary)
    local secondary = primary == "score" and "kills" or "score"
    return function(a, b)
        if a[primary] ~= b[primary] then return a[primary] > b[primary] end
        if a[secondary] ~= b[secondary] then return a[secondary] > b[secondary] end
        if a.deaths ~= b.deaths then return a.deaths < b.deaths end
        local an, bn = string.lower(a.name), string.lower(b.name)
        if an ~= bn then return an < bn end
        return a.id < b.id
    end
end

---Sorts the rows and gives each its place (tied on the primary key: the same place).
---@param rows PW.UIBoardRow[]
---@param primary "score"|"kills"
---@return PW.UIBoardRow[]
local function ranked(rows, primary)
    table.sort(rows, rowOrder(primary))
    for index, entry in ipairs(rows) do
        local previous = rows[index - 1]
        local tied = previous ~= nil and previous[primary] == entry[primary]
        entry.place = tied and previous.place or index
    end
    return rows
end

---@param rows PW.UIBoardRow[]
---@param opts PW.UIBoardOpts
---@param index integer
---@return PW.UIBoardSection
local function teamSection(rows, opts, index)
    ---@type PW.UIBoardRow[]
    local members = {}
    for _, entry in ipairs(rows) do
        if entry.team == index then members[#members + 1] = entry end
    end
    local inTeams = opts.ownTeam >= 1 and opts.ownTeam <= opts.teams
    ---@type PW.UIBoardRelation
    local relation = not inTeams and "neutral" or (index == opts.ownTeam and "friendly" or "enemy")
    local name = opts.teamNames ~= nil and opts.teamNames[index] or nil
    return {
        id = index, title = string.upper(name or ("Team " .. index)), relation = relation,
        score = opts.teamScores ~= nil and opts.teamScores[index] or 0, rows = ranked(members, "score")
    }
end

function pm.Board(rows, opts)
    local players = listed(rows)
    if opts.teams <= 0 then
        return { { id = 0, title = "PLAYERS", relation = "neutral", rows = ranked(players, "kills") } }
    end
    ---@type PW.UIBoardSection[]
    local sections = {}
    for index = 1, opts.teams do sections[index] = teamSection(players, opts, index) end
    ---@param a PW.UIBoardSection
    ---@param b PW.UIBoardSection
    table.sort(sections, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.id < b.id
    end)
    return sections
end

---@param into number
---@param need number
---@return number
local function fraction(into, need)
    if need <= 0 then return 1 end
    return math.min(1, math.max(0, into / need))
end

function pm.LevelSteps(input, needOf)
    local before, after = input.levelBefore, input.levelAfter
    local last = fraction(input.into, input.need)
    if after <= before then
        local start = input.need > 0 and fraction(input.into - input.xp, input.need) or 1
        return { { level = after, from = math.min(start, last), to = last, levelUp = false } }
    end
    local startInto = input.into - input.xp
    for level = before, after - 1 do startInto = startInto + needOf(level) end
    ---@type PW.UILevelStep[]
    local steps = { { level = before, from = fraction(startInto, needOf(before)), to = 1, levelUp = true } }
    for level = before + 1, after - 1 do steps[#steps + 1] = { level = level, from = 0, to = 1, levelUp = true } end
    steps[#steps + 1] = { level = after, from = 0, to = last, levelUp = false }
    return steps
end

function pm.BarAt(steps, elapsed, timing)
    local count = #steps
    if count == 0 then return { level = 1, fraction = 0, levelUps = 0, done = true } end
    local per = math.min(timing.stepTime, timing.maxTime / count)
    local t = elapsed - (timing.delay or 0)
    local first, final = steps[1], steps[count]
    if t <= 0 then return { level = first.level, fraction = first.from, levelUps = 0, done = false } end
    local index = math.floor(t / per) + 1
    if index > count then
        return { level = final.level, fraction = final.to, levelUps = count - 1, done = true }
    end
    local step = steps[index]
    local progress = (t - (index - 1) * per) / per
    return {
        level = step.level, fraction = step.from + (step.to - step.from) * progress, levelUps = index - 1,
        done = false
    }
end

---@param id string
---@return string
local function same(id) return id end

function pm.Medals(list, order, nameOf)
    ---@type table<string, integer>
    local rank = {}
    for index, id in ipairs(order or {}) do rank[id] = index end
    local name = nameOf or same
    ---@type PW.UIPostmatchMedal[]
    local out = {}
    for _, medal in ipairs(list) do
        out[#out + 1] = { id = medal.id, count = medal.count, name = name(medal.id), text = "x" .. medal.count }
    end
    local unknown = math.huge
    ---@param a PW.UIPostmatchMedal
    ---@param b PW.UIPostmatchMedal
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        local ra, rb = rank[a.id] or unknown, rank[b.id] or unknown
        if ra ~= rb then return ra < rb end
        return a.id < b.id
    end)
    return out
end

function pm.Weapons(list, nameOf)
    local name = nameOf or same
    ---@type PW.UIPostmatchWeapon[]
    local out = {}
    for _, gain in ipairs(list) do
        out[#out + 1] = {
            class = gain.class, name = name(gain.class), before = gain.before, after = gain.after,
            text = "LVL " .. gain.after .. "  (+" .. (gain.after - gain.before) .. ")"
        }
    end
    ---@param a PW.UIPostmatchWeapon
    ---@param b PW.UIPostmatchWeapon
    table.sort(out, function(a, b)
        local ga, gb = a.after - a.before, b.after - b.before
        if ga ~= gb then return ga > gb end
        if a.name ~= b.name then return a.name < b.name end
        return a.class < b.class
    end)
    return out
end

function pm.Earned(start, now)
    if start == nil then return nil end
    return math.max(0, math.floor(now - start))
end

function pm.Decide(event, facts)
    if facts.phase ~= "POSTMATCH" or not facts.enabled then
        return facts.open and "close" or nil
    end
    if facts.open then return event == "summary" and "refresh" or nil end
    if event == "phase" then return "open" end
    if facts.dismissed or facts.otherRoot then return nil end
    return "open"
end
