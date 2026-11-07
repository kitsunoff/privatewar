-- Match rules module (T-2.2; 02-modes.md d.6, d.7; 00-core.md d.3, d.5). The glue between the engine and the
-- mode for kills, respawns and spawning, and the win rules of kill-limit modes (TDM, FFA and their children).
-- Shared: the API, the pure rules (plain data in, plain data out) and reading. Server glue: init.lua.
-- Kills toward the score limit are counted here (an enemy kill is 1, CoD style); the points of score events stay in
-- the score module (PW.Score). Counts reach clients through NW2, so a HUD reads them on either realm.

MODULE.Name = "Match rules"

local lib = (rawget(PW, "MatchRules") or {}) --[[@as PW.MatchRulesLib]]
PW.MatchRules = lib

-- FFA players need a real team: with GM.TeamBased the base GM:PlayerSpawn makes a player of TEAM_UNASSIGNED or
-- TEAM_SPECTATOR a spectator. 1000 is below the engine's TEAM_UNASSIGNED (1001) and far above any match team.
lib.FreeTeam = 1000
team.SetUp(lib.FreeTeam, "Free for all", Color(220, 220, 220), false)

lib._KillsKey = "pw_kills"
lib._TeamKillsKey = "pw_kills_team_"
lib._EndsKey = "pw_mode_ends"
lib._DefaultDelay = 3

-- HUD (U-8): a client has no active mode, so the server publishes which NW2 prefix holds the per-team score of the
-- running mode and, at the end, the result as plain numbers.
lib._ScoreKeyKey = "pw_hud_score"
lib._ResultWinnerKey = "pw_result_winner"
lib._ResultDrawKey = "pw_result_draw"
lib._ResultTeamsKey = "pw_result_teams"
-- The score limit of the running mode for the score bars (T-11.5); 0 means none.
lib._LimitKey = "pw_hud_limit"

-- Score prefixes of the built-in modes that do not score by kills; a mode may say it itself (MODE.HudScoreKey).
---@type table<string, string>
local scoreKeys = { dom = "pw_dom_score_", kc = "pw_kc_confirms_", round_base = "pw_round_wins_" }

function lib._HudScoreKey(mode)
    if mode == nil then return lib._TeamKillsKey end
    local own = mode.HudScoreKey
    if isstring(own) then return own --[[@as string]] end
    return scoreKeys[tostring(mode.ClassName)] or scoreKeys[tostring(mode.Base)] or lib._TeamKillsKey
end

function lib._HudScoreLimit(mode)
    if mode == nil then return 0 end
    local value = mode.HudScoreLimit
    if not isnumber(value) then value = mode.RoundsToWin end
    if not isnumber(value) and isfunction(mode.Setting) then value = tonumber(mode:Setting("scorelimit")) end
    if not isnumber(value) then return 0 end
    return math.max(0, math.floor(value --[[@as number]]))
end

function lib._ResultFields(result)
    local winner = result.winner
    ---@type integer
    local id = 0
    if isnumber(winner) then
        id = winner --[[@as integer]]
    elseif winner ~= nil then
        id = (winner --[[@as Player]]):UserID()
    end
    return id, result.draw == true, result.teams and #result.standings or 0
end

---@return PW.MatchRulesStore
function lib._NewStore()
    return { kills = {}, teamKills = {}, respawnAt = {}, points = {} }
end

PW._MatchRules = PW._MatchRules or lib._NewStore()

---@param info PW.KillInfo
---@return string[]
function lib._KillEvents(info)
    if info.suicide or not info.player or not info.enemy then return {} end
    if info.headshot then return { "kill", "headshot" } end
    return { "kill" }
end

---@param store PW.MatchRulesStore
---@param ply any
---@param index integer?
---@return integer kills, integer? teamKills
function lib._Tally(store, ply, index)
    local kills = (store.kills[ply] or 0) + 1
    store.kills[ply] = kills
    if index == nil then return kills, nil end
    local teamKills = (store.teamKills[index] or 0) + 1
    store.teamKills[index] = teamKills
    return kills, teamKills
end

---@param standings PW.Standing[]
---@return PW.Standing[]
function lib._Sort(standings)
    ---@type { entry: PW.Standing, index: integer }[]
    local rows = {}
    for i, entry in ipairs(standings) do rows[i] = { entry = entry, index = i } end
    table.sort(rows, function(a, b)
        if a.entry.score ~= b.entry.score then return a.entry.score > b.entry.score end
        return a.index < b.index
    end)
    ---@type PW.Standing[]
    local sorted = {}
    for i, row in ipairs(rows) do sorted[i] = { id = row.entry.id, score = row.entry.score } end
    return sorted
end

---@param input PW.LimitInput
---@return PW.MatchResult?
function lib._Evaluate(input)
    local sorted = lib._Sort(input.standings)
    local top, second = sorted[1], sorted[2]
    ---@type string?
    local reason = nil
    if input.scorelimit > 0 and top ~= nil and top.score >= input.scorelimit then
        reason = "scorelimit"
    elseif input.timelimit > 0 and input.elapsed >= input.timelimit then
        reason = "timelimit"
    end
    if reason == nil then return nil end
    local draw = top == nil or (second ~= nil and second.score == top.score)
    return {
        reason = reason,
        teams = input.teams,
        draw = draw,
        winner = not draw and top.id or nil,
        standings = sorted
    }
end

---@param teamCount integer
---@param store PW.MatchRulesStore
---@param players any[]
---@return PW.Standing[]
function lib._Standings(teamCount, store, players)
    ---@type PW.Standing[]
    local standings = {}
    if teamCount > 0 then
        for i = 1, teamCount do standings[i] = { id = i, score = store.teamKills[i] or 0 } end
        return standings
    end
    for i, ply in ipairs(players) do standings[i] = { id = ply, score = store.kills[ply] or 0 } end
    return standings
end

---@param now number
---@param at number?
---@return boolean
function lib._RespawnDue(now, at)
    return at ~= nil and now >= at
end

---@param answer any
---@return string?
function lib._SpawnTarget(answer)
    if isentity(answer) then
        if IsValid(answer) then return "entity" end
        return nil
    end
    if istable(answer) and isvector((answer --[[@as table<string, any>]]).pos) then return "point" end
    return nil
end

---@param ply Player
---@return integer
function lib.GetKills(ply)
    if SERVER then return PW._MatchRules.kills[ply] or 0 end
    return ply:GetNW2Int(lib._KillsKey, 0)
end

---@param index integer
---@return integer
function lib.GetTeamKills(index)
    if SERVER then return PW._MatchRules.teamKills[index] or 0 end
    return GetGlobal2Int(lib._TeamKillsKey .. index, 0)
end
