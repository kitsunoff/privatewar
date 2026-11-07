-- Operators, server glue (06-progression.md d.7; docs/api/operators.md). Thin wrappers around the pure rules:
--   pw_operator_model (PW.Net.Receive: any player, 2 per second, MaxChoiceBytes + 1 bytes, owner the module): a
--     human's choice. A malformed one is dropped; a well-formed one is kept and checked again at every spawn (an
--     item bought later becomes usable, a lost one falls back). Outside LIVE an alive player gets it at once, so the
--     lobby shows it; during LIVE from the next spawn.
--   PlayerSetModel: humans get their resolved choice, bots a random operator picked once (locks ignored); the player
--     colour is the team colour in team modes, else cl_playercolor (humans) or a colour picked once (bots).
-- The engine calls are injectable store fields, so the tests drive fake players through a fake store.

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.OperatorsModuleServer : PW.Module
local module = MODULE --[[@as PW.OperatorsModuleServer]]

local lib = PW.Operators --[[@as PW.OperatorsLib]]

---@param message string
local function defaultLog(message)
    print("[PW] operators: " .. message)
end

---@param ply Player
---@param id string
---@return boolean
local function engineUnlocked(ply, id)
    local progression = rawget(PW, "Progression") --[[@as PW.ProgressionLib?]]
    if progression == nil or progression.IsUnlocked == nil then return true end
    return progression.IsUnlocked(ply, "models", id)
end

---@return integer
local function engineTeams()
    local teams = rawget(PW, "Teams") --[[@as PW.TeamsLib?]]
    if teams == nil then return 0 end
    return #teams.GetActive()
end

---@param index integer
---@return Color?
local function engineTeamColour(index)
    if not team.Valid(index) then return nil end
    return team.GetColor(index)
end

---@return string
local function enginePhase()
    local match = PW.Match
    if match == nil then return "LOBBY" end
    return match.GetPhase()
end

---@return PW.OperatorEconomyInput[]
local function engineEconomy()
    return lib.LiveInput().economy or {}
end

---@return table<string, string>
local function engineStock()
    return lib.LiveInput().stock or {}
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        log = opts.log or defaultLog,
        stock = opts.stock or engineStock,
        economy = opts.economy or engineEconomy,
        unlocked = opts.unlocked or engineUnlocked,
        teams = opts.teams or engineTeams,
        teamColour = opts.teamColour or engineTeamColour,
        phase = opts.phase or enginePhase,
        roll = opts.roll or math.random,
        requested = setmetatable({}, { __mode = "k" }),
        bots = setmetatable({}, { __mode = "k" })
    }
end

PW._Operators = PW._Operators or lib._NewStore()

function lib._ListFor(store, ply)
    return lib.List({
        stock = store.stock(), economy = store.economy(),
        unlocked = function(id) return store.unlocked(ply, id) end
    })
end

---The bot's operator and colour, picked once.
---@param store PW.OperatorsStore
---@param ply Player
---@return { path: string, colour: number[] }
local function botLook(store, ply)
    local look = store.bots[ply]
    if look ~= nil then return look end
    local entries = lib.List({ stock = store.stock(), economy = store.economy() })
    local picked = lib.BotPick(entries, store.roll)
    local colour = HSVToColor(math.floor(store.roll() * 360), 0.65, 0.9)
    look = {
        path = picked ~= nil and picked.path or lib.FallbackPath,
        colour = { colour.r / 255, colour.g / 255, colour.b / 255 }
    }
    store.bots[ply] = look
    return look
end

---@param store PW.OperatorsStore
---@param ply Player
---@return string path
---@return number[]? own colour
local function lookOf(store, ply)
    if ply:IsBot() then
        local look = botLook(store, ply)
        return look.path, look.colour
    end
    local entry = lib.Resolve(lib._ListFor(store, ply), store.requested[ply] or lib.Auto, ply:GetInfo("cl_playermodel"))
    return entry ~= nil and entry.path or lib.FallbackPath, nil
end

function lib._OnSetModel(store, ply)
    local path, own = lookOf(store, ply)
    util.PrecacheModel(path)
    ply:SetModel(path)
    local index = ply:Team()
    local colour = lib.Colour({
        teams = store.teams(), team = index, teamColour = store.teamColour(index), own = own,
        info = not ply:IsBot() and ply:GetInfo("cl_playercolor") or nil
    })
    ply:SetPlayerColor(Vector(colour[1], colour[2], colour[3]))
    return path
end

function lib._OnRequest(store, ply, choice)
    if ply:IsBot() or not lib.CheckChoice(choice) then return false, nil end
    store.requested[ply] = choice --[[@as string]]
    local _, reason = lib.Resolve(lib._ListFor(store, ply), choice, ply:GetInfo("cl_playermodel"))
    if reason ~= nil then
        store.log(string.format("%s asked for %q (%s); using their fallback", ply:Nick(), choice, reason))
    end
    if store.phase() ~= "LIVE" and ply:Alive() then lib._OnSetModel(store, ply) end
    return true, reason
end

PW.Net.Receive(lib.NetName, { who = "any", rate = 2, maxLen = lib.MaxChoiceBytes + 1, owner = module },
    function(ply) lib._OnRequest(PW._Operators, ply, net.ReadString()) end)

---@param ply Player
PW.HookFor(module, "PlayerSetModel", function(_, ply)
    lib._OnSetModel(PW._Operators, ply)
end)
