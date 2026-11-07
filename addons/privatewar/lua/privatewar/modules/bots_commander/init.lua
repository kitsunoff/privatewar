-- Bots commander, server glue (T-5.11). Every Config.interval seconds (1 Hz, 07 d.3) one pass over the managed bots:
--   per team: the objectives (MODE:BotObjectives through PW.Call, else PW.BotObjectives.Derive), PW.BotCommander.Assign
--   over the alive bots and their current orders, board.order written (nil for a bot without one and a dead bot);
--   then the hunt slots of every alive human (PW.BotCommander.Hunt) and board.hunt written for every managed bot.
-- Bots without a team (FFA) get no objectives (docs/api/modes.md open item 12: the commander does not ask the mode).

local lib = PW.BotCommander --[[@as PW.BotCommanderLib]]

PW._BotCommander = rawget(PW, "_BotCommander") or { nextRun = 0, hunt = lib.NewHuntState() }
local store = PW._BotCommander

---@class PW.CommanderMember
---@field ply Player
---@field board PW.BotBoard
---@field entry PW.CommanderBot

---@class PW.CommanderGroup
---@field team? integer
---@field size integer every managed bot of the team, dead ones included (the defender cap)
---@field alive PW.CommanderMember[]

---@type fun(): (fun(): integer?, Player?)
local players = player.Iterator

---CurTime() of the bot's last contact with each human, by the human's UserID.
---@param board PW.BotBoard
---@return table<integer, number>
local function seenOf(board)
    ---@type table<integer, number>
    local seen = {}
    for ent, contact in pairs(board.memory or {}) do
        if lib.IsHuman(ent) then seen[(ent --[[@as Player]]):UserID()] = contact.time end
    end
    return seen
end

---@param ply Player
---@param board PW.BotBoard
---@return PW.CommanderMember
local function memberOf(ply, board)
    local personality = (istable(board.personality) and board.personality or {}) --[[@as table<string, any>]]
    ---@type PW.CommanderBot
    local entry = { id = ply:UserID(), pos = ply:GetPos(), team = board.team,
        stationary = personality.type == "stationary", seen = seenOf(board) }
    return { ply = ply, board = board, entry = entry }
end

---@return table<integer, PW.CommanderGroup> groups, PW.CommanderMember[] alive, PW.BotBoard[] dead
local function gather()
    ---@type table<integer, PW.CommanderGroup>
    local groups = {}
    ---@type PW.CommanderMember[]
    local alive = {}
    ---@type PW.BotBoard[]
    local dead = {}
    local get = (PW.Bot --[[@as PW.BotLib]]).Get
    for _, entry in players() do
        local ply = entry --[[@as Player]]
        local board = ply:IsBot() and get(ply) or nil
        if board ~= nil then
            local key = board.team or 0
            local group = groups[key] or { team = board.team, size = 0, alive = {} }
            groups[key] = group
            group.size = group.size + 1
            if ply:Alive() then
                local member = memberOf(ply, board)
                group.alive[#group.alive + 1] = member
                alive[#alive + 1] = member
            else
                dead[#dead + 1] = board
            end
        end
    end
    return groups, alive, dead
end

---@param raw any
---@return PW.BotObjective[]
local function sanitize(raw)
    ---@type PW.BotObjective[]
    local out = {}
    if not istable(raw) then return out end
    for _, o in ipairs(raw --[[@as table[] ]]) do
        if istable(o) and isstring(o.id) and isvector(o.pos) and isstring(o.action) then
            out[#out + 1] = { id = o.id, pos = o.pos, action = o.action, radius = tonumber(o.radius) or 160,
                weight = tonumber(o.weight) or 0, want = math.floor(tonumber(o.want) or 1) }
        end
    end
    return out
end

---@param team integer
---@return PW.BotObjective[]
local function objectivesFor(team)
    local mode = rawget(PW, "ActiveMode") --[[@as table<string, any>?]]
    if mode == nil then return {} end
    ---@type PW.BotObjective[]?
    local own = nil
    if isfunction(mode.BotObjectives) then own = sanitize(PW.Call(mode, "BotObjectives", team)) end
    local derive = rawget(PW, "BotObjectives") --[[@as PW.BotObjectivesLib?]]
    if derive == nil then return own or {} end
    return sanitize(derive.Derive(mode.ClassName, own, {}, {}, team))
end

---@param group PW.CommanderGroup
---@param now number
local function assignTeam(group, now)
    local objectives = group.team ~= nil and objectivesFor(group.team) or {}
    ---@type PW.CommanderBot[]
    local bots = {}
    ---@type table<integer, PW.BotOrder>
    local orders = {}
    for i, member in ipairs(group.alive) do
        bots[i] = member.entry
        orders[member.entry.id] = member.board.order
    end
    local out = lib.Assign(bots, objectives, orders, now, { teamSize = group.size })
    for _, member in ipairs(group.alive) do
        member.board.order = out[member.entry.id]
        member.entry.busy = member.board.order ~= nil
    end
end

---@param alive PW.CommanderMember[]
---@param now number
local function huntPass(alive, now)
    ---@type PW.CommanderHuman[]
    local humans = {}
    ---@type table<integer, Player>
    local byId = {}
    for _, entry in players() do
        local ply = entry --[[@as Player]]
        if not ply:IsBot() and ply:Alive() then
            humans[#humans + 1] = { id = ply:UserID(), pos = ply:GetPos(), team = ply:Team() }
            byId[ply:UserID()] = ply
        end
    end
    ---@type PW.CommanderBot[]
    local bots = {}
    for i, member in ipairs(alive) do bots[i] = member.entry end
    local hunters = lib.Hunt(store.hunt, humans, bots, now)
    for _, member in ipairs(alive) do
        local humanId = hunters[member.entry.id]
        local hs = humanId ~= nil and store.hunt.humans[humanId] or nil
        local hunter = hs ~= nil and hs.hunters[member.entry.id] or nil
        member.board.hunt = { target = humanId ~= nil and byId[humanId] or nil,
            since = hunter ~= nil and hunter.since or now }
    end
end

function lib.Step(now)
    local botLib = rawget(PW, "Bot") --[[@as PW.BotLib?]]
    if botLib == nil or botLib.Get == nil then return end
    local groups, alive, dead = gather()
    for _, board in ipairs(dead) do
        board.order, board.hunt = nil, { since = now }
    end
    for _, group in pairs(groups) do assignTeam(group, now) end
    huntPass(alive, now)
end

PW.HookFor(MODULE, "Think", function()
    local now = CurTime()
    if now < store.nextRun then return end
    store.nextRun = now + lib.Config.interval
    lib.Step(now)
end)
