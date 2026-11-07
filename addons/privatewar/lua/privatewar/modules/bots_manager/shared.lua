-- Bots manager (T-5.1; 07-bots.md d.3, 00-core.md d.9, 02-modes.md d.4 and d.5a, 08-lobby.md d.4). A sub-module of
-- `bots` (docs/api/bots-blackboard.md): it keeps the number of bots at the bots.fill quota, creates them with
-- player.CreateNextBot and kicks them with Player:Kick, lets the teams module place them, reconciles the bots
-- after a changelevel and refuses to work in Singleplayer. Shared: the pure rules over plain data (the quota, the
-- gate, which bot to kick, the plan of one step); bot names: sh_names.lua over the pool in sh_name_pool.lua. Server
-- glue: init.lua.

MODULE.Name = "Bots manager"

local lib = (rawget(PW, "BotsManager") or {}) --[[@as PW.BotsManagerLib]]
PW.BotsManager = lib

if SERVER then
    AddCSLuaFile("privatewar/modules/bots_manager/sh_name_pool.lua")
    AddCSLuaFile("privatewar/modules/bots_manager/sh_names.lua")
end
include("privatewar/modules/bots_manager/sh_name_pool.lua")
include("privatewar/modules/bots_manager/sh_names.lua")

lib._FreeSlots = 1
lib._Interval = 1
lib._ActivePhases = { PREMATCH = true, LIVE = true, POSTMATCH = true, VOTE = true }

function lib._Quota(facts)
    if facts.maxPlayers <= 1 then return 0 end
    local free = facts.freeSlots or lib._FreeSlots
    local total = math.min(facts.fill, facts.maxPlayers - free)
    return math.max(0, total - facts.humans)
end

function lib._Gate(facts)
    if facts.singlePlayer then return "singleplayer" end
    if facts.paused then return "tests" end
    if facts.generating then return "navgen" end
    if not lib._ActivePhases[facts.phase] then return "phase" end
    return nil
end

---Players per team 1..n (humans and bots).
---@param entries PW.BotsEntry[]
---@param n integer
---@return table<integer, integer>
local function teamCounts(entries, n)
    ---@type table<integer, integer>
    local counts = {}
    for _, entry in ipairs(entries) do
        local team = entry.team
        if team >= 1 and team <= n then counts[team] = (counts[team] or 0) + 1 end
    end
    return counts
end

---The newest bot (highest id) of team (nil: any team).
---@param entries PW.BotsEntry[]
---@param team integer?
---@return integer?
local function newestBot(entries, team)
    ---@type integer?
    local best = nil
    for i, entry in ipairs(entries) do
        if entry.bot and (team == nil or entry.team == team) and (best == nil or entry.id > entries[best].id) then
            best = i
        end
    end
    return best
end

---The team to kick from without a preference: the largest that has a bot (ties: the lowest index); nil in FFA.
---@param entries PW.BotsEntry[]
---@param n integer
---@return integer?
local function largestTeam(entries, n)
    local counts = teamCounts(entries, n)
    ---@type integer?
    local best = nil
    for team = 1, n do
        if newestBot(entries, team) ~= nil and (best == nil or counts[team] > counts[best]) then best = team end
    end
    return best
end

function lib._PickKick(entries, n, prefer)
    if prefer ~= nil then
        local preferred = newestBot(entries, prefer)
        if preferred ~= nil then return preferred end
    end
    return newestBot(entries, largestTeam(entries, n))
end

function lib._Plan(target, entries, n, prefer)
    ---@type PW.BotsEntry[]
    local remaining = {}
    local bots = 0
    for i, entry in ipairs(entries) do
        remaining[i] = entry
        if entry.bot then bots = bots + 1 end
    end
    ---@type PW.BotsPlan
    local plan = { create = math.max(0, target - bots), kick = {} }
    while bots > target do
        local index = lib._PickKick(remaining, n, #plan.kick == 0 and prefer or nil)
        if index == nil then break end
        plan.kick[#plan.kick + 1] = remaining[index].ent
        table.remove(remaining, index)
        bots = bots - 1
    end
    return plan
end
