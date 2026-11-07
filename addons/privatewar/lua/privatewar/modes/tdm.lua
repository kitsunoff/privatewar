-- Team Deathmatch (T-2.2; 02-modes.md d.5, d.7; 00-core.md d.3, d.5). Two teams; an enemy kill is one point toward
-- the score limit (the score module keeps the points of score events). The match ends at the score limit or at the
-- time limit; a shared top score is a draw. The kill, respawn and spawn glue is the match_rules module; this file
-- holds the mode's answers and its limits. FFA (ffa.lua) inherits everything here with Teams = 0.
-- Match state: self._StartedAt is the CurTime() at which LIVE began, nil outside a match.

MODE.Name = "Team Deathmatch"
MODE.Short = "TDM"
MODE.Teams = 2
MODE.Description = "Two teams. First to the kill limit wins; when time runs out the team with more kills wins."
MODE.Settings = {
    scorelimit = { type = "int", default = 75, min = 10, max = 1000, label = "Score limit (kills)" },
    timelimit = { type = "int", default = 600, min = 0, max = 3600, label = "Time limit (s, 0 = none)" },
    respawndelay = { type = "float", default = 3, min = 0, max = 30, label = "Respawn delay (s)" }
}

function MODE:Start()
    local now = CurTime()
    self._StartedAt = now
    local limit = tonumber(self:Setting("timelimit")) or 0
    SetGlobal2Float(assert(PW.MatchRules)._EndsKey, limit > 0 and now + limit or -1)
end

function MODE:Think()
    local result = assert(PW.MatchRules).Check(self, CurTime())
    if result ~= nil then assert(PW.Match).Finish(result) end
end

function MODE:Cleanup()
    self._StartedAt = nil
    SetGlobal2Float(assert(PW.MatchRules)._EndsKey, -1)
end

---@param victim Player
---@param attacker Entity
---@param dmg CTakeDamageInfo
function MODE:PW_PlayerKilled(victim, attacker, dmg)
    assert(PW.MatchRules).ScoreKill(victim, attacker, dmg)
end

function MODE:PW_CanRespawn()
    return true
end

function MODE:PW_RespawnDelay()
    return self:Setting("respawndelay")
end
