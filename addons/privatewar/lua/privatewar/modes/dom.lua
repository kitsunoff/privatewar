-- Domination (T-2.4; 02-modes.md d.5, d.7; 03-mapdata.md d.2, d.4, d.6; README.md "worth stealing": capture math).
-- TDM with flags: the flags come from the map data (MAP.Modes.dom.flags = { A = Vector(...), ... }); the mode is
-- offered only on maps whose data passes ValidateMapData (PW.Map.ModeFits; 03-mapdata.md d.6).
--   Capture: one signed scalar per flag in [-100, 100] (+100 = team 1, -100 = team 2). Every StepEvery seconds the
--   presence pass (module dom_flags) counts the alive players of each team inside each flag, and the scalar moves by
--   capturerate x min(diff, 3) per second toward the side with more players. It stops at +-100 and does not move
--   while the counts are equal (contested, or nobody inside). The owner changes only when the scalar reaches the
--   other side's end, so a flag under capture keeps scoring for its owner until it is lost.
--   Capture award: score event dom_capture to every player of the new owner inside the flag.
--   Scoring: every tickinterval seconds each held flag adds TickPoints to its team. The score limit counts these
--   points; the time limit and the result shape are TDM's (match_rules _Evaluate). Kills score "kill" as in TDM.
-- Published for HUDs: NW2 globals pw_dom_score_<team> (GetScore) and the flag entities' network vars (letter, scalar,
-- owner, contested: both teams inside with equal counts; T-6.5).
-- Bots (T-5.11): BotObjectives answers the d.14 rules of PW.BotObjectives.DomObjectives over this match's flags.

MODE.Base = "tdm"
MODE.Name = "Domination"
MODE.Short = "DOM"
MODE.Teams = 2
MODE.Dependencies = { objective_actions = { "capture", "defend" }, modules = { "bots_objectives", "dom_flags" } }
MODE.MapData = true
MODE.Description = "Two teams. Capture and hold the flags: every held flag scores for your team. "
    .. "First to the score limit wins."
MODE.Settings = {
    scorelimit = { default = 200, label = "Score limit (points)" },
    capturerate = { type = "float", default = 10, min = 1, max = 100,
        label = "Capture speed (per second, per player ahead, up to 3)" },
    tickinterval = { type = "float", default = 5, min = 1, max = 30, label = "Seconds per point for each held flag" }
}

-- MODE is a loader global that points at the next entity once this file is loaded: keep this table.
local dom = MODE --[[@as PW.DomMode]]
dom._ScoreKey = "pw_dom_score_"
dom.StepEvery = 0.2
dom.TickPoints = 1

local limit, maxDiff = 100, 3

function dom._Step(value, plus, minus, rate, dt)
    local diff = plus - minus
    if diff == 0 then return value end
    local sign = diff > 0 and 1 or -1
    local moved = value + sign * rate * math.min(math.abs(diff), maxDiff) * dt
    return math.Clamp(moved, -limit, limit)
end

function dom._Contested(plus, minus)
    return plus > 0 and plus == minus
end

function dom._Owner(value, owner)
    if value >= limit then return 1 end
    if value <= -limit then return 2 end
    return owner
end

function dom._Hold(flags, scores, points)
    ---@type table<integer, true>
    local changed = {}
    for _, flag in ipairs(flags) do
        local owner = flag.owner
        if owner > 0 then
            scores[owner] = (scores[owner] or 0) + points
            changed[owner] = true
        end
    end
    return changed
end

function dom._ParseFlags(data)
    ---@type PW.DomFlagSpot[]
    local list = {}
    local raw = istable(data) and (data --[[@as table<string, any>]]).flags or nil
    if not istable(raw) then return list end
    for letter, pos in pairs(raw --[[@as table<any, any>]]) do
        if isstring(letter) and isvector(pos) then list[#list + 1] = { letter = letter, pos = pos } end
    end
    table.sort(list, function(a, b) return a.letter < b.letter end)
    return list
end

function dom:ValidateMapData(data)
    local raw = istable(data) and data.flags or nil
    if not istable(raw) then return false, "Domination needs a flags table" end
    for letter, pos in pairs(raw --[[@as table<any, any>]]) do
        if not isstring(letter) or not isvector(pos) then
            return false, "flag " .. tostring(letter) .. " must be a letter and a Vector"
        end
    end
    if #dom._ParseFlags(data) < 2 then return false, "Domination needs at least 2 flags" end
    return true
end

function dom._Standings(scores, n)
    ---@type PW.Standing[]
    local standings = {}
    for i = 1, n do standings[i] = { id = i, score = scores[i] or 0 } end
    return standings
end

function dom.GetScore(index)
    return GetGlobal2Int(dom._ScoreKey .. index, 0)
end

function dom._Players()
    return player.GetAll()
end

---@param self PW.DomMode
---@return integer
local function teamCount(self)
    local teams = PW.Teams
    if teams ~= nil then return teams._TeamCount(self) end
    return self.Teams
end

---@param self PW.DomMode
local function publishScores(self)
    local scores = self._Scores or {}
    for i = 1, teamCount(self) do SetGlobal2Int(dom._ScoreKey .. i, scores[i] or 0) end
end

function dom:Start()
    local now = CurTime()
    self._StartedAt = now
    self._Scores = {}
    self._LastStep, self._NextStep = now, now + dom.StepEvery
    self._NextTick = now + (tonumber(self:Setting("tickinterval")) or 5)
    local timelimit = tonumber(self:Setting("timelimit")) or 0
    SetGlobal2Float(assert(PW.MatchRules)._EndsKey, timelimit > 0 and now + timelimit or -1)
    publishScores(self)
    ---@type PW.DomFlagState[]
    local list = {}
    local map = PW.Map
    local spots = dom._ParseFlags(map ~= nil and map.GetModeData(self.ClassName) or nil)
    local module = PW.DomFlags
    for _, spot in ipairs(spots) do
        local ent = module ~= nil and module.Spawn ~= nil and module.Spawn(spot.letter, spot.pos) or nil
        list[#list + 1] = { letter = spot.letter, pos = spot.pos, value = 0, owner = 0, ent = ent }
    end
    self._Flags = list
end

---@param members any[]?
local function awardCapture(members)
    local score = PW.Score
    if score == nil or members == nil then return end
    for _, ply in ipairs(members) do score.Award(ply, "dom_capture") end
end

---One capture step over every flag: presence, scalar, owner, awards, network vars.
---@param self PW.DomMode
---@param dt number
local function stepFlags(self, dt)
    local module = PW.DomFlags
    local list = self._Flags
    if module == nil or list == nil or #list == 0 then return end
    ---@type Vector[]
    local points = {}
    for i, flag in ipairs(list) do points[i] = flag.pos end
    local presence = module._Presence(points, module._Infos(self._Players()))
    local rate = tonumber(self:Setting("capturerate")) or 10
    for i, flag in ipairs(list) do
        local counts = presence[i].counts
        local value = dom._Step(flag.value, counts[1] or 0, counts[2] or 0, rate, dt)
        local owner = dom._Owner(value, flag.owner)
        flag.value = value
        if IsValid(flag.ent) then
            flag.ent:SetValue(value)
            flag.ent:SetContested(dom._Contested(counts[1] or 0, counts[2] or 0))
        end
        if owner ~= flag.owner then
            flag.owner = owner
            if IsValid(flag.ent) then flag.ent:SetOwnerTeam(owner) end
            awardCapture(presence[i].members[owner])
        end
    end
end

---@param self PW.DomMode
---@param now number
local function scoreTick(self, now)
    local interval = math.max(1, tonumber(self:Setting("tickinterval")) or 5)
    self._NextTick = now + interval
    local scores = self._Scores or {}
    self._Scores = scores
    if next(dom._Hold(self._Flags or {}, scores, dom.TickPoints)) ~= nil then publishScores(self) end
end

function dom:Think()
    local started = self._StartedAt
    if not isnumber(started) then return end
    local now = CurTime()
    if now >= (self._NextStep or 0) then
        stepFlags(self, math.max(0, now - (self._LastStep or now)))
        self._LastStep, self._NextStep = now, now + dom.StepEvery
    end
    if now >= (self._NextTick or 0) then scoreTick(self, now) end
    local result = assert(PW.MatchRules)._Evaluate({
        standings = dom._Standings(self._Scores or {}, teamCount(self)),
        teams = true,
        scorelimit = tonumber(self:Setting("scorelimit")) or 0,
        timelimit = tonumber(self:Setting("timelimit")) or 0,
        elapsed = now - started
    })
    if result ~= nil then assert(PW.Match).Finish(result) end
end

function dom:BotObjectives(team)
    local bots = PW.BotObjectives
    if bots == nil then return {} end
    ---@type PW.BotFlagInfo[]
    local infos = {}
    for i, flag in ipairs(self._Flags or {}) do
        infos[i] = { letter = flag.letter, pos = flag.pos, owner = flag.owner, value = flag.value }
    end
    return bots.DomObjectives(infos, team)
end

function dom:Cleanup()
    local module = PW.DomFlags
    if module ~= nil and module.RemoveAll ~= nil then module.RemoveAll() end
    self._StartedAt, self._Flags, self._Scores = nil, nil, nil
    self._LastStep, self._NextStep, self._NextTick = nil, nil, nil
    SetGlobal2Float(assert(PW.MatchRules)._EndsKey, -1)
    publishScores(self)
end
