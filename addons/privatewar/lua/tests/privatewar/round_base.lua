-- T-2.3 round_base (TASKS.md, "Mandatory test cases" T-2.3; 00-core.md d.4; 02-modes.md d.6). Pure cases drive the
-- state machine MODE._Step with plain data (no clock, no players). Glue cases run MODE:_Run and Think of a plain
-- stand-in child (a table whose __index is the stored round_base) with PW.Teams.Swap, PW.Match.Finish and
-- _RespawnAll replaced by recorders, so no case swaps real players or ends a real match. No bots are created.
-- Every case restores what it replaced.

local listener = "PW_Test_RoundBase"
local hooks = { "PW_RoundStart", "PW_RoundEnd" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.RoundBase
local function base()
    return must(PW.Modes.GetStored("round_base")) --[[@as PW.RoundBase]]
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@param values? table<string, any>
---@return PW.RoundState
local function newState(values)
    local o = values or {}
    return base()._NewState(o.n or 2, o.toWin or 3, o.swapEvery or 0, o.roundTime or 100, o.intermission or 5)
end

---Plays a list of verdicts through _Step: each round is decided, then the intermission is waited out. Returns every
---action in order.
---@param state PW.RoundState
---@param verdicts any[]
---@return PW.RoundAction[]
local function play(state, verdicts)
    ---@type PW.RoundAction[]
    local all = {}
    ---@param actions PW.RoundAction[]
    local function take(actions)
        for _, action in ipairs(actions) do all[#all + 1] = action end
    end
    take(base()._Step(state, 0, nil))
    for i, verdict in ipairs(verdicts) do
        if state.phase ~= "round" then break end
        take(base()._Step(state, i * 100, verdict))
        take(base()._Step(state, i * 100 + 50, nil))
    end
    return all
end

---@param actions PW.RoundAction[]
---@return string[]
local function kinds(actions)
    ---@type string[]
    local list = {}
    for i, action in ipairs(actions) do
        list[i] = action.kind .. (action.round ~= nil and (":" .. action.round) or "")
    end
    return list
end

---A stand-in round mode: plain data, Setting from a table, the engine glue replaced by recorders.
---@param state table<string, any>
---@param values table<string, any>
---@return table<string, any>
local function standIn(state, values)
    local log = state.log --[[@as string[] ]]
    local mode = setmetatable({
        Teams = 2, RoundsToWin = values.toWin or 2, SwapSidesEvery = values.swapEvery or 0,
        Setting = function(_, key) return ({ roundtime = 100, intermission = 5 })[key] end,
        _RespawnAll = function() log[#log + 1] = "respawn" end
    }, { __index = base() })
    return mode
end

return {
    groupName = "PW round_base",
    beforeEach = function(state)
        state.log = {}
        state.finish = match().Finish
        state.swap = must(PW.Teams).Swap
        local log = state.log --[[@as string[] ]]
        match().Finish = function(result)
            log[#log + 1] = "finish:" .. tostring((result --[[@as PW.MatchResult]]).winner)
            return true
        end
        must(PW.Teams).Swap = function()
            log[#log + 1] = "swap"
            return 0
        end
        hook.Add("PW_RoundStart", listener, function(round, swapped)
            log[#log + 1] = "start:" .. tostring(round) .. ":" .. tostring(swapped)
        end)
        hook.Add("PW_RoundEnd", listener, function(round, winner, wins)
            log[#log + 1] = "end:" .. tostring(round) .. ":" .. tostring(winner) .. ":" .. wins[1] .. "-" .. wins[2]
        end)
    end,
    afterEach = function(state)
        match().Finish = state.finish --[[@as fun(result?: any): boolean]]
        must(PW.Teams).Swap = state.swap --[[@as fun(players?: Player[]): integer]]
        for _, name in ipairs(hooks) do hook.Remove(name, listener) end
    end,
    cases = {
        {
            name = "round_base is abstract with defaults and settings; it is absent from the mode lists",
            func = function()
                local stored = base()
                expect(stored.Abstract).to.beTrue()
                expect(stored.Teams).to.equal(2)
                expect(isstring(stored.Name)).to.beTrue()
                ---@param list PW.Entity[]
                ---@return boolean
                local function listed(list)
                    for _, entry in ipairs(list) do
                        if entry.ClassName == "round_base" then return true end
                    end
                    return false
                end
                expect(listed(PW.Modes.GetList())).to.beFalse()
                expect(listed(PW.Modes.GetEnabledList())).to.beFalse()
                -- A child that only sets parameters is valid and listed; the abstract base is not.
                local reg = PW.Registry.New("modes", { log = function() end, preRegister = function() end,
                    required = { Name = "string", Teams = "number" } })
                reg.Register(table.Copy(stored), "round_base")
                reg.Register({ Base = "round_base", RoundsToWin = 4, SwapSidesEvery = 2 }, "test_rounds")
                reg.ResolveAll()
                local list = reg.GetList()
                expect(#list).to.equal(1)
                expect(must(list[1]).ClassName).to.equal("test_rounds")
                expect(must(list[1]).RoundsToWin).to.equal(4)
                expect(must(list[1]).Teams).to.equal(2)
                expect(must(list[1]).Abstract).to.beNil()
            end
        },
        {
            name = "Round loop runs until RoundsToWin: no finish before a team has the rounds, one finish at it",
            func = function()
                local state = newState({ toWin = 3 })
                local actions = play(state, { 1, 2, 1, 2, 1, 1, 1 })
                -- Team 1 gets its third win in round 5; nothing happens after the finish.
                expect(kinds(actions)).to.deepEqual({
                    "start:1", "end:1", "start:2", "end:2", "start:3", "end:3", "start:4", "end:4", "start:5",
                    "end:5", "finish"
                })
                local result = must(must(actions[#actions]).result)
                expect(result.winner).to.equal(1)
                expect(result.draw).to.beFalse()
                expect(result.teams).to.beTrue()
                expect(result.reason).to.equal("roundlimit")
                expect(result.standings).to.deepEqual({ { id = 1, score = 3 }, { id = 2, score = 2 } })
                expect(state.phase).to.equal("over")
                expect(base()._Step(state, 1000, 1)).to.deepEqual({})
            end
        },
        {
            name = "Round loop: a drawn round (false) scores nothing; an invalid verdict is a draw; undecided waits",
            func = function()
                local state = newState({ toWin = 2 })
                base()._Step(state, 0, nil)
                expect(base()._Step(state, 1, nil)).to.deepEqual({})
                expect(must(base()._Step(state, 2, false)[1]).winner).to.equal(false)
                expect(state.wins).to.deepEqual({ 0, 0 })
                base()._Step(state, 100, nil)
                expect(must(base()._Step(state, 101, 7)[1]).winner).to.equal(false)
                expect(state.wins).to.deepEqual({ 0, 0 })
                expect(state.round).to.equal(2)
            end
        },
        {
            name = "Round time: when it is up an undecided round is a draw; 0 means no round time",
            func = function()
                local state = newState({ roundTime = 30 })
                base()._Step(state, 0, nil)
                expect(base()._TimedOut(state, 29)).to.beFalse()
                expect(base()._Step(state, 29, nil)).to.deepEqual({})
                expect(base()._TimedOut(state, 30)).to.beTrue()
                local actions = base()._Step(state, 30, nil)
                expect(must(actions[1]).kind).to.equal("end")
                expect(must(actions[1]).winner).to.equal(false)
                local open = newState({ roundTime = 0 })
                base()._Step(open, 0, nil)
                expect(base()._TimedOut(open, 1e9)).to.beFalse()
                -- The child may name the winner at the time limit.
                local timed = newState({ roundTime = 30 })
                base()._Step(timed, 0, nil)
                expect(must(base()._Step(timed, 31, 2)[1]).winner).to.equal(2)
            end
        },
        {
            name = "Side swap every SwapSidesEvery rounds: after rounds 2 and 4, wins move with the players",
            func = function()
                local state = newState({ toWin = 9, swapEvery = 2 })
                local actions = play(state, { 1, 1, 2, 2, 1 })
                expect(kinds(actions)).to.deepEqual({
                    "start:1", "end:1", "start:2", "end:2", "swap", "start:3", "end:3", "start:4", "end:4",
                    "swap", "start:5", "end:5", "start:6"
                })
                expect(must(actions[6]).swapped).to.beTrue()
                expect(must(actions[3]).swapped).to.beFalse()
                -- Wins after round 2: 2-0; swapped: 0-2 (team 2 holds them); round 3 team 2 wins: 0-3; ...
                expect(must(actions[7]).wins).to.deepEqual({ 0, 3 })
                expect(must(actions[9]).wins).to.deepEqual({ 0, 4 })
                expect(must(actions[12]).wins).to.deepEqual({ 5, 0 })
            end
        },
        {
            name = "Side swap: never when SwapSidesEvery is 0, and none after the match-winning round",
            func = function()
                local never = play(newState({ toWin = 9, swapEvery = 0 }), { 1, 2, 1, 2, 1, 2 })
                for _, action in ipairs(never) do expect(action.kind == "swap").to.beFalse() end
                local last = play(newState({ toWin = 2, swapEvery = 2 }), { 1, 1 })
                expect(kinds(last)).to.deepEqual({ "start:1", "end:1", "start:2", "end:2", "finish" })
            end
        },
        {
            name = "Teams swap (pure): two teams trade places, N teams rotate, outside players stay",
            func = function()
                local teams = must(PW.Teams)
                expect(teams._SwapMap(2)).to.deepEqual({ 2, 1 })
                expect(teams._SwapMap(3)).to.deepEqual({ 2, 3, 1 })
                expect(teams._SwapAssignment(2, { a = 1, b = 2, c = 1, spec = 1001 })).to.deepEqual(
                    { a = 2, b = 1, c = 2, spec = 1001 })
                expect(teams._SwapAssignment(0, { a = 1 })).to.deepEqual({ a = 1 })
            end
        },
        {
            name = "Teams.Swap moves the given players (stand-ins) and reports how many",
            func = function(state)
                local teams = must(PW.Teams)
                local real = state.swap --[[@as fun(players?: Player[]): integer]]
                ---@param team integer
                local function standInPlayer(team)
                    local ply = { team = team }
                    function ply:Team() return self.team end
                    function ply:SetTeam(t) self.team = t end
                    return ply
                end
                local a, b, spec = standInPlayer(1), standInPlayer(2), standInPlayer(1001)
                local moved = must(teams._SwapPlayers)(2, { a, b, spec } --[[@as Player[] ]])
                expect(moved).to.equal(2)
                expect({ a.team, b.team, spec.team }).to.deepEqual({ 2, 1, 1001 })
                expect(isfunction(real)).to.beTrue()
            end
        },
        {
            name = "Last team alive (pure): one team left wins, none left is a draw, two or more go on",
            func = function()
                local last = base()._LastAlive
                expect(last({ 3, 0 }, { 3, 3 }, 2)).to.equal(1)
                expect(last({ 0, 1 }, { 3, 3 }, 2)).to.equal(2)
                expect(last({ 1, 2 }, { 3, 3 }, 2)).to.beNil()
                expect(last({ 0, 0 }, { 3, 3 }, 2)).to.equal(false)
                -- A team that had nobody does not count; one team alone never ends the round.
                expect(last({ 2, 0 }, { 2, 0 }, 2)).to.beNil()
                expect(last({ 0, 1, 0 }, { 2, 2, 0 }, 3)).to.equal(2)
            end
        },
        {
            name = "PW_RoundStart and PW_RoundEnd order: start, end, (swap, respawn), start ... end, then the finish",
            func = function(state)
                local mode = standIn(state, { toWin = 2, swapEvery = 1 })
                local s = base()._NewState(2, 2, 1, 100, 5)
                mode._Rounds = s
                local verdicts = { 1, 1 }
                mode:_Run(base()._Step(s, 0, nil))
                for i, verdict in ipairs(verdicts) do
                    mode:_Run(base()._Step(s, i * 100, verdict))
                    mode:_Run(base()._Step(s, i * 100 + 50, nil))
                end
                -- Round 1 won by team 1 (1-0); the swap moves that win to team 2 (0-1); team 1 wins round 2: 1-1.
                expect(state.log).to.deepEqual({
                    "start:1:false", "end:1:1:1-0", "swap", "respawn", "start:2:true", "end:2:1:1-1", "swap",
                    "respawn", "start:3:true"
                })
                mode._Rounds = nil
            end
        },
        {
            name = "PW_RoundStart/End order: the last round ends with PW_RoundEnd, then Finish, no more starts",
            func = function(state)
                local mode = standIn(state, { toWin = 2 })
                local s = base()._NewState(2, 2, 0, 100, 5)
                mode._Rounds = s
                mode:_Run(base()._Step(s, 0, nil))
                for i, verdict in ipairs({ 2, 2 }) do
                    mode:_Run(base()._Step(s, i * 100, verdict))
                    mode:_Run(base()._Step(s, i * 100 + 50, nil))
                end
                expect(state.log).to.deepEqual({
                    "start:1:false", "end:1:2:0-1", "respawn", "start:2:false", "end:2:2:0-2", "finish:2"
                })
                mode._Rounds = nil
            end
        },
        {
            name = "Think of a stand-in child: round 1 starts on the first tick; RoundWinner ends the round",
            func = function(state)
                local mode = standIn(state, { toWin = 1 })
                local verdict = nil
                mode.RoundWinner = function() return verdict end
                mode:Start()
                local started = must(mode._Rounds --[[@as PW.RoundState?]])
                expect(started.round).to.equal(0)
                mode:Think()
                expect(started.round).to.equal(1)
                expect(state.log).to.deepEqual({ "start:1:false" })
                mode:Think()
                expect(#state.log).to.equal(1)
                verdict = 1
                mode:Think()
                expect(state.log).to.deepEqual({ "start:1:false", "end:1:1:1-0", "finish:1" })
                mode:Cleanup()
                expect(mode._Rounds).to.beNil()
            end
        },
        {
            name = "round_base answers PW_CanRespawn with false (dead players wait for the next round)",
            func = function()
                expect(must(base().PW_CanRespawn)()).to.beFalse()
            end
        }
    }
}
