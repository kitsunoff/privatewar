-- Kill Confirmed (T-2.5; 02-modes.md d.5, d.7; 01-extensibility.md d.17). TDM with tags: every death drops a tag
-- (module kc_tags) on the ground under the victim. An enemy of the victim who picks it up confirms the kill: the
-- score event kc_confirm and one confirm for the collector's team. A teammate (or the victim) who picks it up denies
-- it: kc_deny, no confirm. The score limit counts confirms (CoD style: kills alone do not win); the time limit and
-- the result shape are TDM's (match_rules _Evaluate). The kill itself still scores "kill" (match_rules ScoreKill).
-- Tags are removed after pickup, when their lifetime (setting taglifetime, 0 = none) ends and at match end.
-- Published for HUDs: NW2 globals pw_kc_confirms_<team> (GetConfirms).
-- Bots (T-5.11): BotObjectives answers the d.14 rules of PW.BotObjectives.KCObjectives over the tags on the ground.

MODE.Base = "tdm"
MODE.Name = "Kill Confirmed"
MODE.Short = "KC"
MODE.Teams = 2
MODE.Dependencies = { objective_actions = { "collect", "deny" }, modules = { "bots_objectives", "kc_tags" } }
MODE.Description = "Two teams. Pick up enemy tags to confirm kills, your team's tags to deny them. "
    .. "First to the confirm limit wins."
MODE.Settings = {
    scorelimit = { default = 65, label = "Score limit (confirms)" },
    taglifetime = { type = "int", default = 0, min = 0, max = 300, label = "Tag lifetime (s, 0 = until match end)" }
}

-- MODE is a loader global that points at the next entity once this file is loaded: keep this table.
local kc = MODE --[[@as PW.KCMode]]
kc._ConfirmsKey = "pw_kc_confirms_"

---@param confirms table<integer, integer>
---@param verdict PW.KCVerdict
---@param index integer?
---@return string
function kc._Apply(confirms, verdict, index)
    if verdict ~= "confirm" then return "kc_deny" end
    if index ~= nil then confirms[index] = (confirms[index] or 0) + 1 end
    return "kc_confirm"
end

---@param teamId integer
---@param n integer
---@return integer?
function kc._TeamIndex(teamId, n)
    if teamId >= 1 and teamId <= n and teamId == math.floor(teamId) then return teamId end
    return nil
end

---@param confirms table<integer, integer>
---@param n integer
---@return PW.Standing[]
function kc._Standings(confirms, n)
    ---@type PW.Standing[]
    local standings = {}
    for i = 1, n do standings[i] = { id = i, score = confirms[i] or 0 } end
    return standings
end

---@param index integer
---@return integer
function kc.GetConfirms(index)
    return GetGlobal2Int(kc._ConfirmsKey .. index, 0)
end

---@param self PW.KCMode
---@return integer
local function teamCount(self)
    local teams = PW.Teams
    if teams ~= nil then return teams._TeamCount(self) end
    return self.Teams
end

function kc:Start()
    local now = CurTime()
    self._StartedAt = now
    self._Confirms = {}
    local limit = tonumber(self:Setting("timelimit")) or 0
    SetGlobal2Float(assert(PW.MatchRules)._EndsKey, limit > 0 and now + limit or -1)
    for i = 1, teamCount(self) do SetGlobal2Int(kc._ConfirmsKey .. i, 0) end
end

function kc:Think()
    local started = self._StartedAt
    if not isnumber(started) then return end
    local result = assert(PW.MatchRules)._Evaluate({
        standings = kc._Standings(self._Confirms or {}, teamCount(self)),
        teams = true,
        scorelimit = tonumber(self:Setting("scorelimit")) or 0,
        timelimit = tonumber(self:Setting("timelimit")) or 0,
        elapsed = CurTime() - started
    })
    if result ~= nil then assert(PW.Match).Finish(result) end
end

function kc:BotObjectives(team)
    local bots, tags = PW.BotObjectives, PW.KCTags
    if bots == nil or tags == nil then return {} end
    ---@type PW.BotTagInfo[]
    local infos = {}
    for _, tag in ipairs(tags.GetAll()) do
        if IsValid(tag) then
            local victim = tag:GetVictim() --[[@as Player]]
            infos[#infos + 1] = { id = "tag_" .. tag:EntIndex(), pos = tag:GetPos(),
                team = IsValid(victim) and victim:Team() or nil }
        end
    end
    return bots.KCObjectives(infos, team)
end

function kc:Cleanup()
    local tags = PW.KCTags
    if tags ~= nil and tags.RemoveAll ~= nil then tags.RemoveAll() end
    self._StartedAt = nil
    self._Confirms = nil
    SetGlobal2Float(assert(PW.MatchRules)._EndsKey, -1)
    for i = 1, teamCount(self) do SetGlobal2Int(kc._ConfirmsKey .. i, 0) end
end

---@param victim Player
---@param attacker Entity
---@param dmg CTakeDamageInfo
function kc:PW_PlayerKilled(victim, attacker, dmg)
    assert(PW.MatchRules).ScoreKill(victim, attacker, dmg)
    local tags = PW.KCTags
    if tags == nil or tags.Drop == nil then return end
    tags.Drop(victim, tonumber(self:Setting("taglifetime")) or 0)
end

---@param collector Player
---@param _ any the victim
---@param verdict PW.KCVerdict
function kc:PW_KCTagCollected(collector, _, verdict)
    local confirms = self._Confirms
    if confirms == nil then
        confirms = {}
        self._Confirms = confirms
    end
    local index = kc._TeamIndex(collector:Team(), teamCount(self))
    local eventId = kc._Apply(confirms, verdict, index)
    if verdict == "confirm" and index ~= nil then SetGlobal2Int(kc._ConfirmsKey .. index, confirms[index]) end
    local score = PW.Score
    if score ~= nil then score.Award(collector, eventId) end
end
