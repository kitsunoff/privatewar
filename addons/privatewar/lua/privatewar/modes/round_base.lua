-- Abstract round mode (T-2.3; 00-core.md d.4; 02-modes.md d.6). Round-based modes (S&D and the like) set
-- MODE.Base = "round_base" and only parameters: RoundsToWin (rounds a team needs, default 6) and SwapSidesEvery
-- (swap the sides after every N completed rounds, 0 = never; the match's last round is never followed by a swap).
-- The loop: round 1 starts on the first tick of LIVE (the match start already spawned everyone); a round ends when
-- MODE:RoundWinner(timedOut) names a team (an integer 1..Teams) or a draw (false), or when the round time is up (a
-- draw unless RoundWinner answered); an intermission follows, then the sides swap when due, everyone respawns and
-- the next round starts. A team that reaches RoundsToWin ends the match with the shape of TDM's result (reason
-- "roundlimit"; standings are rounds won by team index, so after a swap the wins move with the players).
-- Notifications (fired here only, via PW.Notify; a listener must not return a value):
--   PW_RoundStart(round: integer, swapped: boolean) after the swap and respawn; swapped: sides swapped just before.
--   PW_RoundEnd(round: integer, winner: integer|false, wins: table<integer, integer>) before any swap; false: draw.
-- Everything decisive is a pure function over plain data (_NewState, _Step, ...); Think and _Run are thin glue.
-- Dead players stay dead during a round (PW_CanRespawn = false). Published for HUDs: NW2 globals pw_round,
-- pw_round_wins_<team> and the round end time in MatchRules._EndsKey (-1 in the intermission).

MODE.Abstract = true
MODE.Name = "Round-based mode"
MODE.Teams = 2
MODE.Description = "Abstract base of round-based modes."
MODE.RoundsToWin = 6
MODE.SwapSidesEvery = 0
MODE.Settings = {
    roundtime = { type = "int", default = 120, min = 0, max = 600, label = "Round time (s, 0 = none)" },
    intermission = { type = "float", default = 5, min = 1, max = 30, label = "Time between rounds (s)" }
}

-- MODE is a loader global that points at the next entity once this file is loaded: keep this table.
local base = MODE --[[@as PW.RoundBase]]
local roundKey, winsKey = "pw_round", "pw_round_wins_"

---@param value any
---@param n integer
---@return integer|false|nil
function MODE._Verdict(value, n)
    if value == nil then return nil end
    if isnumber(value) and value >= 1 and value <= n and value == math.floor(value) then return value end
    return false
end

---@param n integer
---@param toWin integer
---@param swapEvery integer
---@param roundTime number
---@param intermission number
---@return PW.RoundState
function MODE._NewState(n, toWin, swapEvery, roundTime, intermission)
    ---@type table<integer, integer>
    local wins = {}
    for i = 1, n do wins[i] = 0 end
    return {
        n = n, toWin = toWin, swapEvery = swapEvery, roundTime = roundTime, intermission = intermission,
        round = 0, wins = wins, phase = "starting", at = 0, swapPending = false
    }
end

---@param state PW.RoundState
---@param now number
---@return boolean
function MODE._TimedOut(state, now)
    return state.roundTime > 0 and now - state.at >= state.roundTime
end

---The last team alive: a team index when exactly one team (of those that had players) has players alive, false
---when none has, nil while two or more still fight (or fewer than two teams had players).
---@param alive table<integer, integer>
---@param present table<integer, integer>
---@param n integer
---@return integer|false|nil
function MODE._LastAlive(alive, present, n)
    local teamsIn, standing, last = 0, 0, nil
    for i = 1, n do
        if (present[i] or 0) > 0 then
            teamsIn = teamsIn + 1
            if (alive[i] or 0) > 0 then standing, last = standing + 1, i end
        end
    end
    if teamsIn < 2 then return nil end
    if standing == 0 then return false end
    if standing == 1 then return last end
    return nil
end

---The match result when a team has the rounds needed, else nil (same shape as the TDM result).
---@param state PW.RoundState
---@return PW.MatchResult?
function MODE._Result(state)
    ---@type PW.Standing[]
    local standings = {}
    for i = 1, state.n do standings[i] = { id = i, score = state.wins[i] or 0 } end
    local result = assert(PW.MatchRules)._Evaluate({
        standings = standings, teams = true, scorelimit = state.toWin, timelimit = 0, elapsed = 0
    })
    if result ~= nil then result.reason = "roundlimit" end
    return result
end

---@param state PW.RoundState
---@param now number
---@param winner integer|false
---@return PW.RoundAction[]
local function endRound(state, now, winner)
    if winner ~= false then state.wins[winner] = (state.wins[winner] or 0) + 1 end
    ---@type table<integer, integer>
    local wins = {}
    for i = 1, state.n do wins[i] = state.wins[i] or 0 end
    ---@type PW.RoundAction[]
    local actions = { { kind = "end", round = state.round, winner = winner, wins = wins } }
    local result = base._Result(state)
    if result ~= nil then
        state.phase = "over"
        actions[2] = { kind = "finish", result = result }
        return actions
    end
    state.phase, state.at = "intermission", now + state.intermission
    state.swapPending = state.swapEvery > 0 and state.round % state.swapEvery == 0
    return actions
end

---Moves the wins with the players after a swap.
---@param state PW.RoundState
local function swapWins(state)
    local map = assert(PW.Teams)._SwapMap(state.n)
    ---@type table<integer, integer>
    local moved = {}
    for i = 1, state.n do moved[map[i]] = state.wins[i] or 0 end
    state.wins = moved
end

---One step of the state machine at time now; verdict is the answer of RoundWinner (nil: undecided). Returns the
---actions in order: "swap", "start" { round, swapped, respawn }, "end" { round, winner, wins }, "finish" { result }.
---@param state PW.RoundState
---@param now number
---@param verdict any
---@return PW.RoundAction[]
function MODE._Step(state, now, verdict)
    local phase = state.phase
    if phase == "starting" or (phase == "intermission" and now >= state.at) then
        ---@type PW.RoundAction[]
        local actions = {}
        local swapped = state.swapPending
        if swapped then
            actions[1] = { kind = "swap" }
            swapWins(state)
            state.swapPending = false
        end
        state.round, state.phase, state.at = state.round + 1, "round", now
        actions[#actions + 1] = {
            kind = "start", round = state.round, swapped = swapped, respawn = phase ~= "starting"
        }
        return actions
    end
    if phase ~= "round" then return {} end
    local winner = base._Verdict(verdict, state.n)
    if winner == nil and base._TimedOut(state, now) then winner = false end
    if winner == nil then return {} end
    return endRound(state, now, winner)
end

---@param state PW.RoundState
local function publish(state)
    SetGlobal2Int(roundKey, state.round)
    for i = 1, state.n do SetGlobal2Int(winsKey .. i, state.wins[i] or 0) end
    local ends = state.phase == "round" and state.roundTime > 0 and state.at + state.roundTime or -1
    SetGlobal2Float(assert(PW.MatchRules)._EndsKey, ends)
end

---Every player spawns again (a new round).
function MODE:_RespawnAll()
    local list = player.GetAll()
    table.sort(list, function(a, b) return a:UserID() < b:UserID() end)
    for _, ply in ipairs(list) do ply:Spawn() end
end

---Executes the actions of _Step.
---@param actions PW.RoundAction[]
function MODE:_Run(actions)
    for _, action in ipairs(actions) do
        if action.kind == "swap" then
            assert(PW.Teams).Swap()
        elseif action.kind == "start" then
            if action.respawn then self:_RespawnAll() end
            PW.Notify("PW_RoundStart", action.round, action.swapped)
        elseif action.kind == "end" then
            PW.Notify("PW_RoundEnd", action.round, action.winner, action.wins)
        elseif action.kind == "finish" then
            assert(PW.Match).Finish(action.result)
        end
    end
    if self._Rounds ~= nil then publish(self._Rounds) end
end

---The round's verdict (the child's hook): an integer 1..Teams for the winner, false for a draw, nil while the
---round goes on. timedOut: the round time is up (nil is then a draw). Default: the last team alive.
---@param timedOut boolean
---@return integer|false|nil
function MODE:RoundWinner(timedOut)
    local n = assert(PW.Teams)._TeamCount(self)
    ---@type table<integer, integer>, table<integer, integer>
    local alive, present = {}, {}
    for _, ply in ipairs(player.GetAll()) do
        local index = ply:Team()
        if index >= 1 and index <= n then
            present[index] = (present[index] or 0) + 1
            if ply:Alive() then alive[index] = (alive[index] or 0) + 1 end
        end
    end
    local last = base._LastAlive(alive, present, n)
    if last == nil and timedOut then return false end
    return last
end

function MODE:Start()
    local n = assert(PW.Teams)._TeamCount(self)
    local toWin = math.max(1, math.floor(tonumber(self.RoundsToWin) or 6))
    local swapEvery = math.max(0, math.floor(tonumber(self.SwapSidesEvery) or 0))
    self._Rounds = base._NewState(n, toWin, swapEvery, tonumber(self:Setting("roundtime")) or 0,
        tonumber(self:Setting("intermission")) or 5)
end

function MODE:Think()
    local state = self._Rounds --[[@as PW.RoundState?]]
    if state == nil then return end
    local now = CurTime()
    ---@type integer|false|nil
    local verdict = nil
    if state.phase == "round" then
        verdict = self:RoundWinner(base._TimedOut(state, now)) --[[@as integer|false|nil]]
    end
    local actions = base._Step(state, now, verdict)
    if #actions > 0 then self:_Run(actions) end
end

function MODE:Cleanup()
    local state = self._Rounds
    self._Rounds = nil
    SetGlobal2Float(assert(PW.MatchRules)._EndsKey, -1)
    SetGlobal2Int(roundKey, 0)
    if state ~= nil then
        for i = 1, state.n do SetGlobal2Int(winsKey .. i, 0) end
    end
end

---@param victim Player
---@param attacker Entity
---@param dmg CTakeDamageInfo
function MODE:PW_PlayerKilled(victim, attacker, dmg)
    assert(PW.MatchRules).ScoreKill(victim, attacker, dmg)
end

function MODE:PW_CanRespawn()
    return false
end
