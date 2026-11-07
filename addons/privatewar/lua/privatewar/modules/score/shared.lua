-- Score module (T-2.1; 06-progression.md d.3). One source for match score, XP and streak progress: score events
-- (the score_events kind). Shared: the API, the pure rules (plain data in, plain data out) and reading. The server
-- side (Award, reset) is in init.lua. Scores reach clients through NW2: an Int on each player and a global Int per
-- team, so a HUD reads them with PW.Score.Get / PW.Score.GetTeam on either realm.

MODULE.Name = "Score"

local lib = (rawget(PW, "Score") or {}) --[[@as PW.ScoreLib]]
PW.Score = lib

lib._PlayerKey = "pw_score"
lib._TeamKey = "pw_score_team_"

---@param log? PW.LogFn
---@return PW.ScoreStore
function lib._NewStore(log)
    return {
        players = {},
        teams = {},
        log = log or function(message) print("[PW] " .. message) end
    }
end

PW._Score = PW._Score or lib._NewStore()

---@param event PW.ScoreEvent
---@param answer any
---@return number points, number xp
function lib._Resolve(event, answer)
    local points = isnumber(answer) and answer --[[@as number]] or event.Points
    local xp = event.XP
    if xp == nil then xp = points end
    return points, xp
end

---@param store PW.ScoreStore
---@param ply Player
---@param team integer?
---@param points number
---@return integer score, integer? teamScore
function lib._Add(store, ply, team, points)
    local score = (store.players[ply] or 0) + points
    store.players[ply] = score
    if team == nil then return score, nil end
    local teamScore = (store.teams[team] or 0) + points
    store.teams[team] = teamScore
    return score, teamScore
end

---Server: the store. Client: the value the server published.
---@param ply Player
---@return integer
function lib.Get(ply)
    if SERVER then return PW._Score.players[ply] or 0 end
    return ply:GetNW2Int(lib._PlayerKey, 0)
end

---@param index integer
---@return integer
function lib.GetTeam(index)
    if SERVER then return PW._Score.teams[index] or 0 end
    return GetGlobal2Int(lib._TeamKey .. index, 0)
end
