-- Teams module, server glue (T-1.16). Thin wrappers around the pure rules in shared.lua:
--   PW_PhaseChange PREMATCH -> LIVE: balanced assignment of every player (before MODE:Start, so the mode and the
--     spawns see the teams); the team count is published to clients. Entering LOBBY clears it.
--   PlayerSpawn during LIVE: a player without a team of the active mode (a late joiner, a bot added by the bots
--     lane) goes to the smallest team (08-lobby.md d.4). Runs before GM:PlayerSpawn, which would otherwise spawn a
--     teamless player as a spectator (GM.TeamBased); GM:PlayerInitialSpawn resets the team, so it is not used.
--   Swap: moves the players one team along (side swap of round modes, T-2.3); the pure rule is in shared.lua.
--   PW_PendingTeams (question, asked by the core when it writes pending_match.json): team by SteamID64 of the
--     humans; PW_PendingMatchApplied restores it as preferences for the next assignment (00-core.md d.9).
-- PW_* methods are auto-subscribed (01-extensibility.md d.18); the engine hook goes through PW.HookFor, so it runs
-- only while the module is enabled (d.16).

local lib = PW.Teams --[[@as PW.TeamsLib]]

---Every player in join order (UserID), so the assignment is deterministic.
---@return Player[]
local function sortedPlayers()
    local list = player.GetAll()
    table.sort(list, function(a, b) return a:UserID() < b:UserID() end)
    return list
end

---@param ply Player
---@return integer
local function preference(ply)
    if not ply:IsBot() then
        local restored = PW._Teams.pending[ply:SteamID64()]
        if restored ~= nil then return restored end
    end
    return ply:Team()
end

---@param players Player[]
function lib._AssignPlayers(players)
    local n = #lib.GetActive()
    if n > 0 then
        ---@type PW.TeamEntry[]
        local entries = {}
        for i, ply in ipairs(players) do entries[i] = { id = ply, pref = preference(ply) } end
        for ply, team in pairs(lib._Assign(n, entries)) do
            (ply --[[@as Player]]):SetTeam(team)
        end
    end
    PW._Teams.pending = {}
end

---@param ply Player
---@param players Player[]
---@return integer?
function lib._PlaceLate(ply, players)
    local n = #lib.GetActive()
    if n == 0 then return nil end
    -- a join-in-progress spectator (lobby module) stays out of the teams until the next match
    if ply:Team() == TEAM_SPECTATOR or ply:GetNW2Bool("pw_spectating", false) then return nil end
    ---@type integer[]
    local current = {}
    for _, other in ipairs(players) do
        if other ~= ply and IsValid(other) then current[#current + 1] = other:Team() end
    end
    local team = lib._Smallest(lib._Counts(n, current), n) --[[@as integer]]
    ply:SetTeam(team)
    return team
end

---@param n integer
---@param players Player[]
---@return integer moved
function lib._SwapPlayers(n, players)
    ---@type table<any, integer>
    local before = {}
    for _, ply in ipairs(players) do before[ply] = ply:Team() end
    local moved = 0
    for ply, team in pairs(lib._SwapAssignment(n, before)) do
        if team ~= before[ply] then
            (ply --[[@as Player]]):SetTeam(team)
            moved = moved + 1
        end
    end
    return moved
end

function lib.Swap(players)
    return lib._SwapPlayers(#lib.GetActive(), players or sortedPlayers())
end

---@return integer?
function lib.Smallest()
    local n = #lib.GetActive()
    ---@type integer[]
    local current = {}
    for _, ply in ipairs(player.GetAll()) do current[#current + 1] = ply:Team() end
    return lib._Smallest(lib._Counts(n, current), n)
end

---@param phase PW.PhaseName
---@param oldPhase PW.PhaseName
function MODULE:PW_PhaseChange(phase, oldPhase)
    if phase == "LIVE" and oldPhase == "PREMATCH" then
        lib._AssignPlayers(sortedPlayers())
        SetGlobal2Int(lib._CountKey, #lib.GetActive())
    elseif phase == "LOBBY" then
        PW._Teams.pending = {}
        SetGlobal2Int(lib._CountKey, 0)
    end
end

---@param pending PW.PendingMatch
function MODULE:PW_PendingMatchApplied(pending)
    PW._Teams.pending = lib._FromFile(pending.teams)
end

---@param mode table
---@return table<string, integer>?
function MODULE:PW_PendingTeams(mode)
    ---@type PW.TeamFileRow[]
    local rows = {}
    for _, ply in ipairs(player.GetHumans()) do rows[#rows + 1] = { sid = ply:SteamID64(), team = ply:Team() } end
    local teams = lib._ForFile(lib._TeamCount(mode), rows)
    if next(teams) == nil then return nil end
    return teams
end

---@param ply Player
PW.HookFor(MODULE, "PlayerSpawn", function(_, ply)
    local match = PW.Match
    if match == nil or match.GetPhase() ~= "LIVE" then return end
    local current = ply:Team()
    local n = #lib.GetActive()
    if n == 0 or (current >= 1 and current <= n) then return end
    lib._PlaceLate(ply, player.GetAll())
end)
