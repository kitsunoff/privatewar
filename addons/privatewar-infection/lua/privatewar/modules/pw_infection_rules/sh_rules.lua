-- Pure roster/role/outcome rules. The only round loop remains round_base.
local lib = (rawget(PW, "InfectionRules") or {}) --[[@as PW.InfectionRulesLib]]
PW.InfectionRules = lib

---@param players PW.InfectionParticipant[]
---@param previous string?
---@param rng fun(): number
---@return string?
function lib.PickSeed(players, previous, rng)
    ---@type string[]
    local ids = {}
    for _, entry in ipairs(players) do
        if #players == 1 or entry.id ~= previous then ids[#ids + 1] = entry.id end
    end
    if #ids == 0 then return nil end
    local roll = rng()
    if not isnumber(roll) or roll ~= roll then roll = 0 end
    return ids[math.Clamp(math.floor(roll * #ids) + 1, 1, #ids)]
end

function lib.NewRound(players, seed, deadline)
    if not isnumber(deadline) or deadline ~= deadline or deadline <= 0 or deadline == math.huge then
        return nil, "Infection requires a finite positive deadline"
    end
    if #players < 2 then return nil, "Infection needs at least two participants (humans or bots)" end
    ---@type table<string, PW.InfectionLife>
    local roster = {}
    for _, entry in ipairs(players) do
        if not isstring(entry.id) or entry.id == "" or roster[entry.id] ~= nil or not isbool(entry.bot)
            or not isnumber(entry.life) or entry.life < 1 or entry.life == math.huge
            or entry.life ~= math.floor(entry.life) then
            return nil, "Infection received an invalid or duplicate participant"
        end
        roster[entry.id] = { id = entry.id, bot = entry.bot, life = entry.life,
            role = entry.id == seed and "infected" or "survivor", initial = entry.id == seed,
            present = true, converted = false, alive = true }
    end
    if roster[seed] == nil then return nil, "Infection seed is not a participant" end
    return { players = roster, deadline = deadline }
end

---@param round PW.InfectionRound
---@param role PW.InfectionRole
local function seal(round, role)
    round.winner = role
    for _, entry in pairs(round.players) do
        entry.won = (role == "infected" and entry.initial)
            or (role == "survivor" and entry.present and entry.role == "survivor" and entry.alive)
    end
end

function lib.Winner(round, now)
    if round.winner ~= nil then return round.winner end
    local survivors, infected = 0, 0
    for _, entry in pairs(round.players) do
        if entry.present then
            if entry.role == "survivor" then survivors = survivors + 1 else infected = infected + 1 end
        end
    end
    if now >= round.deadline then
        seal(round, survivors > 0 and "survivor" or "infected")
    elseif survivors == 0 then
        seal(round, "infected")
    elseif infected == 0 then
        seal(round, "survivor")
    end
    return round.winner
end

function lib.Death(round, id, life, now)
    if lib.Winner(round, now) ~= nil then return false end
    local entry = round.players[id]
    if entry == nil or not entry.present or entry.life ~= life or entry.deadLife == life then return false end
    entry.deadLife, entry.alive = life, false
    local converted = entry.role == "survivor"
    if converted then entry.role, entry.converted = "infected", true end
    lib.Winner(round, now)
    return converted
end

function lib.Disconnect(round, id, now)
    if lib.Winner(round, now) ~= nil then return end
    local entry = round.players[id]
    if entry ~= nil then entry.present, entry.alive = false, false end
    lib.Winner(round, now)
end

function lib.Admit()
    return false -- admission is a new-round operation; reconnect cannot buy another current-round life
end

function lib.Summary(rounds)
    ---@type table<string, integer>
    local wins = {}
    for _, round in ipairs(rounds) do
        for id, entry in pairs(round.players) do wins[id] = (wins[id] or 0) + (entry.won and 1 or 0) end
    end
    ---@type PW.InfectionStanding[]
    local standings = {}
    for id, count in pairs(wins) do standings[#standings + 1] = { id = id, score = count } end
    table.sort(standings, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.id < b.id
    end)
    local top = standings[1]
    local draw = top == nil or (standings[2] ~= nil and top.score == standings[2].score)
    return { reason = "roundlimit", teams = false, draw = draw,
        winner = not draw and top ~= nil and top.id or nil, standings = standings }
end
