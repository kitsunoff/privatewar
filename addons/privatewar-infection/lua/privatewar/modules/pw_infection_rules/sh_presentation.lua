-- An allowlisted snapshot reducer, shared so the server-only suite covers all HUD decisions.
local lib = (rawget(PW, "InfectionPresentation") or {}) --[[@as PW.InfectionPresentationLib]]
PW.InfectionPresentation = lib

---@param n any
---@param max number
---@return boolean
local function integer(n, max)
    return isnumber(n) and n >= 0 and n <= max and n == math.floor(n)
end

function lib.Accept(current, incoming)
    if not integer(incoming.revision, 4294967295)
        or (incoming.active ~= nil and not isbool(incoming.active))
        or (incoming.intermission ~= nil and not isbool(incoming.intermission))
        or (current ~= nil and incoming.revision <= current.revision) then return nil end
    if incoming.active == false then
        return { revision = incoming.revision, active = false, round = 0, survivors = 0, infected = 0,
            deadline = 0, role = "waiting", personalWins = 0 }
    end
    if not integer(incoming.round, 255) or not integer(incoming.survivors, 255)
        or not integer(incoming.infected, 255) or not integer(incoming.personalWins, 255)
        or not isnumber(incoming.deadline) or incoming.deadline ~= incoming.deadline
        or math.abs(incoming.deadline) == math.huge
        or (incoming.role ~= "survivor" and incoming.role ~= "infected" and incoming.role ~= "waiting") then
        return nil
    end
    local clean = { revision = incoming.revision, round = incoming.round, survivors = incoming.survivors,
        infected = incoming.infected, deadline = incoming.deadline, role = incoming.role,
        personalWins = incoming.personalWins } --[[@as PW.InfectionSnapshot]]
    if incoming.active ~= nil then clean.active = incoming.active == true end
    if incoming.intermission ~= nil then clean.intermission = incoming.intermission == true end
    if integer(incoming.infections, 65535) then clean.infections = incoming.infections end
    return clean
end

function lib.Model(snapshot, now)
    local role = snapshot.role == "waiting" and "WAITING FOR NEXT ROUND"
        or (snapshot.role == "infected" and "INFECTED" or "SURVIVOR")
    local remaining = math.max(0, math.ceil(snapshot.deadline - now))
    return { visible = snapshot.active ~= false, role = role, remaining = remaining,
        timer = string.format("%d:%02d", math.floor(remaining / 60), remaining % 60),
        round = snapshot.round, survivors = snapshot.survivors, infected = snapshot.infected,
        personalWins = snapshot.personalWins, intermission = snapshot.intermission == true }
end

local roleIds = { waiting = 0, survivor = 1, infected = 2 }
local roles = { [0] = "waiting", [1] = "survivor", [2] = "infected" }

function lib.Encode(writer, incoming)
    local clean = lib.Accept(nil, incoming)
    if clean == nil then return false end
    writer.uint(clean.revision, 32)
    writer.bool(clean.active ~= false)
    if clean.active == false then return true end
    writer.uint(clean.round, 8)
    writer.uint(clean.survivors, 8)
    writer.uint(clean.infected, 8)
    writer.float(clean.deadline)
    writer.uint(roleIds[clean.role], 2)
    writer.uint(clean.personalWins, 8)
    writer.bool(clean.intermission == true)
    writer.uint(clean.infections or 0, 16)
    return true
end

function lib.Decode(reader)
    ---@type table<string, any>
    local incoming = { revision = reader.uint(32), active = reader.bool() }
    if incoming.active then
        incoming.round = reader.uint(8)
        incoming.survivors, incoming.infected = reader.uint(8), reader.uint(8)
        incoming.deadline, incoming.role = reader.float(), roles[reader.uint(2)]
        incoming.personalWins, incoming.intermission = reader.uint(8), reader.bool()
        incoming.infections = reader.uint(16)
    end
    return incoming
end

-- Final presentation is intentionally independent of ordinary score/kills, XP and money.
function lib.Results(rows, ownId)
    ---@type PW.InfectionResultRow[]
    local clean = {}
    ---@type table<integer, boolean>
    local seen = {}
    for _, row in ipairs(rows) do
        if not integer(row.id, 4294967295) or row.id < 1 or seen[row.id] or not isstring(row.name) or #row.name > 256
            or not integer(row.wins, 255) or not integer(row.infections or 0, 65535)
            or not integer(row.kills or 0, 65535) or not integer(row.deaths or 0, 65535)
            or (row.bot ~= nil and not isbool(row.bot)) then return nil end
        seen[row.id] = true
        clean[#clean + 1] = { id = row.id, name = row.name, wins = row.wins, infections = row.infections or 0,
            bot = row.bot == true, kills = row.kills or 0, deaths = row.deaths or 0 }
    end
    table.sort(clean, function(a, b)
        if a.wins ~= b.wins then return a.wins > b.wins end
        local an, bn = string.lower(a.name), string.lower(b.name)
        if an ~= bn then return an < bn end
        return a.id < b.id
    end)
    local ownWins = 0
    ---@type integer?
    local ownPlace
    for index, row in ipairs(clean) do
        local previous = clean[index - 1]
        row.place = previous ~= nil and previous.wins == row.wins and previous.place or index
        if row.id == ownId then ownWins, ownPlace = row.wins, row.place end
    end
    local top = clean[1]
    local draw = top == nil or (clean[2] ~= nil and clean[2].wins == top.wins)
    return { rows = clean, personalWins = ownWins, place = ownPlace, draw = draw,
        winner = not draw and top ~= nil and top.id or nil }
end
