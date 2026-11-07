-- T-2.2 TDM and FFA (TASKS.md, "Mandatory test cases" T-2.2; 02-modes.md d.5, d.7; 00-core.md d.3, d.5). Pure
-- cases over plain standings, and mode cases that call MODE:Think with kill counts in a swapped match_rules store,
-- the mode's Setting stubbed and PW.Match.Finish replaced by a recorder, so no case ends a real match. Every case
-- restores the store, PW.Match.Finish, PW.ActiveMode and the stubbed Setting.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.MatchRulesLib
local function rules()
    return must(PW.MatchRules)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@param id string
---@return PW.Mode
local function mode(id)
    return must(PW.Modes.Get(id)) --[[@as PW.Mode]]
end

---Results given to the recorded PW.Match.Finish, in order.
---@param state table<string, any>
---@return PW.MatchResult[]
local function finished(state)
    return state.finished --[[@as PW.MatchResult[] ]]
end

---Replaces the mode's Setting with fixed values (restored by afterEach) and starts its clock at now - elapsed.
---@param state table<string, any>
---@param m PW.Mode
---@param values table<string, number>
---@param elapsed number
local function prepare(state, m, values, elapsed)
    local stubbed = state.stubbed --[[@as table[] ]]
    stubbed[#stubbed + 1] = { mode = m, setting = rawget(m, "Setting") }
    rawset(m, "Setting", function(_, key) return values[key] end)
    m._StartedAt = CurTime() - elapsed
end

---@param id any
---@param score integer
---@return PW.Standing
local function standing(id, score)
    return { id = id, score = score }
end

return {
    groupName = "PW modes TDM and FFA",
    beforeEach = function(state)
        state.finished = {}
        state.stubbed = {}
        state.store = PW._MatchRules
        state.finish = match().Finish
        state.activeMode = PW.ActiveMode
        PW._MatchRules = rules()._NewStore()
        local results = finished(state)
        match().Finish = function(result)
            results[#results + 1] = result
            return true
        end
    end,
    afterEach = function(state)
        for _, entry in ipairs(state.stubbed --[[@as table[] ]]) do
            local stubbedMode = entry.mode --[[@as PW.Mode]]
            rawset(stubbedMode, "Setting", entry.setting)
            stubbedMode._StartedAt = nil
        end
        match().Finish = state.finish --[[@as fun(result?: any): boolean]]
        PW._MatchRules = state.store
        PW.ActiveMode = state.activeMode
    end,
    cases = {
        {
            name = "TDM and FFA are registered with their teams and settings (FFA inherits TDM)",
            func = function()
                local tdm, ffa = mode("tdm"), mode("ffa")
                expect(tdm.Teams).to.equal(2)
                expect(ffa.Teams).to.equal(0)
                expect(ffa.Base).to.equal("tdm")
                local function schema(m)
                    return PW.Settings._Schema(m, "modes", function() end)
                end
                local tdmSettings, ffaSettings = schema(tdm), schema(ffa)
                expect(must(ffaSettings.scorelimit).id).to.equal("ffa.scorelimit")
                expect(must(ffaSettings.scorelimit).max).to.equal(1000)
                expect(must(tdmSettings.scorelimit).default).to.equal(75)
                expect(must(tdmSettings.timelimit).default).to.equal(600)
                expect(must(tdmSettings.respawndelay).default).to.equal(3)
                expect(must(ffaSettings.scorelimit).default).to.equal(30)
                expect(must(ffaSettings.timelimit).default).to.equal(600)
                expect(must(ffaSettings.respawndelay).default).to.equal(3)
            end
        },
        {
            name = "Win by score limit (pure): the first standing at the limit wins",
            func = function()
                local input = {
                    standings = { standing(1, 40), standing(2, 75) },
                    teams = true, scorelimit = 75, timelimit = 600, elapsed = 10
                }
                local result = must(rules()._Evaluate(input))
                expect(result.reason).to.equal("scorelimit")
                expect(result.draw).to.beFalse()
                expect(result.winner).to.equal(2)
                expect(result.teams).to.beTrue()
                expect(result.standings).to.deepEqual({ standing(2, 75), standing(1, 40) })
                input.standings = { standing(1, 74), standing(2, 10) }
                expect(rules()._Evaluate(input)).to.beNil()
            end
        },
        {
            name = "Win by score limit: TDM Think finishes the match with the team that reached it",
            func = function(state)
                local tdm = mode("tdm")
                prepare(state, tdm, { scorelimit = 75, timelimit = 600 }, 5)
                PW._MatchRules.teamKills = { [1] = 74, [2] = 30 }
                must(tdm.Think)(tdm)
                expect(#finished(state)).to.equal(0)
                PW._MatchRules.teamKills[1] = 75
                must(tdm.Think)(tdm)
                expect(#finished(state)).to.equal(1)
                local result = must(finished(state)[1])
                expect(result.reason).to.equal("scorelimit")
                expect(result.winner).to.equal(1)
                expect(result.draw).to.beFalse()
                expect(result.standings).to.deepEqual({ standing(1, 75), standing(2, 30) })
            end
        },
        {
            name = "Win by time limit (pure): the leader wins when the time is up; 0 means no time limit",
            func = function()
                local input = {
                    standings = { standing(1, 12), standing(2, 20) },
                    teams = true, scorelimit = 75, timelimit = 600, elapsed = 599
                }
                expect(rules()._Evaluate(input)).to.beNil()
                input.elapsed = 600
                local result = must(rules()._Evaluate(input))
                expect(result.reason).to.equal("timelimit")
                expect(result.winner).to.equal(2)
                expect(result.draw).to.beFalse()
                input.timelimit = 0
                input.elapsed = 100000
                expect(rules()._Evaluate(input)).to.beNil()
            end
        },
        {
            name = "Win by time limit: TDM Think finishes the match with the leading team",
            func = function(state)
                local tdm = mode("tdm")
                prepare(state, tdm, { scorelimit = 75, timelimit = 60 }, 59)
                PW._MatchRules.teamKills = { [1] = 3, [2] = 9 }
                must(tdm.Think)(tdm)
                expect(#finished(state)).to.equal(0)
                tdm._StartedAt = CurTime() - 61
                must(tdm.Think)(tdm)
                local result = must(finished(state)[1])
                expect(result.reason).to.equal("timelimit")
                expect(result.winner).to.equal(2)
            end
        },
        {
            name = "Tie handling: a shared top score at the time limit is a draw without a winner",
            func = function(state)
                local input = {
                    standings = { standing(1, 20), standing(2, 20) },
                    teams = true, scorelimit = 75, timelimit = 600, elapsed = 600
                }
                local result = must(rules()._Evaluate(input))
                expect(result.reason).to.equal("timelimit")
                expect(result.draw).to.beTrue()
                expect(result.winner).to.beNil()
                expect(result.standings).to.deepEqual({ standing(1, 20), standing(2, 20) })
                -- Both teams over the limit in the same tick with the same score: a draw too.
                input.standings = { standing(1, 75), standing(2, 75) }
                input.elapsed = 1
                local both = must(rules()._Evaluate(input))
                expect(both.reason).to.equal("scorelimit")
                expect(both.draw).to.beTrue()
                expect(both.winner).to.beNil()
                -- No kills at all when the time is up: a draw.
                input.standings = { standing(1, 0), standing(2, 0) }
                input.elapsed = 600
                expect(must(rules()._Evaluate(input)).draw).to.beTrue()
                -- The same through the TDM mode.
                local tdm = mode("tdm")
                prepare(state, tdm, { scorelimit = 75, timelimit = 60 }, 61)
                PW._MatchRules.teamKills = { [1] = 7, [2] = 7 }
                must(tdm.Think)(tdm)
                local viaMode = must(finished(state)[1])
                expect(viaMode.draw).to.beTrue()
                expect(viaMode.winner).to.beNil()
            end
        },
        {
            name = "Tie handling in FFA: players sharing the top score draw; a lower tie does not matter",
            func = function()
                local input = {
                    standings = { standing("a", 5), standing("b", 9), standing("c", 9) },
                    teams = false, scorelimit = 30, timelimit = 600, elapsed = 600
                }
                local result = must(rules()._Evaluate(input))
                expect(result.draw).to.beTrue()
                expect(result.winner).to.beNil()
                input.standings = { standing("a", 4), standing("b", 4), standing("c", 9) }
                local single = must(rules()._Evaluate(input))
                expect(single.draw).to.beFalse()
                expect(single.winner).to.equal("c")
            end
        },
        {
            name = "FFA winner is the top player (pure standings over players)",
            func = function()
                local store = rules()._NewStore()
                store.kills = { a = 3, b = 30, c = 12 }
                local standings = rules()._Standings(0, store, { "a", "b", "c", "d" })
                expect(standings).to.deepEqual({ standing("a", 3), standing("b", 30), standing("c", 12),
                    standing("d", 0) })
                local result = must(rules()._Evaluate({
                    standings = standings, teams = false, scorelimit = 30, timelimit = 600, elapsed = 1
                }))
                expect(result.reason).to.equal("scorelimit")
                expect(result.teams).to.beFalse()
                expect(result.winner).to.equal("b")
                expect(must(result.standings[1]).id).to.equal("b")
                expect(must(result.standings[2]).id).to.equal("c")
                -- At the time limit the top player wins without reaching the limit.
                local timed = must(rules()._Evaluate({
                    standings = standings, teams = false, scorelimit = 50, timelimit = 600, elapsed = 600
                }))
                expect(timed.winner).to.equal("b")
            end
        },
        {
            name = "FFA winner is the top player: FFA Think finishes with the player, not a team",
            func = function(state)
                local ffa = mode("ffa")
                local host = must(player.GetHumans()[1])
                prepare(state, ffa, { scorelimit = 30, timelimit = 600 }, 5)
                PW._MatchRules.kills = { [host] = 30 }
                PW._MatchRules.teamKills = { [1] = 100 }
                must(ffa.Think)(ffa)
                local result = must(finished(state)[1])
                expect(result.reason).to.equal("scorelimit")
                expect(result.teams).to.beFalse()
                expect(result.winner).to.equal(host)
            end
        },
        {
            name = "Team standings cover every team of the mode, missing counts are 0",
            func = function()
                local store = rules()._NewStore()
                store.teamKills = { [2] = 4 }
                expect(rules()._Standings(2, store, {})).to.deepEqual({ standing(1, 0), standing(2, 4) })
                expect(rules()._Sort({ standing("x", 1), standing("y", 3), standing("z", 1) }))
                    .to.deepEqual({ standing("y", 3), standing("x", 1), standing("z", 1) })
            end
        },
        {
            name = "Start records the start time and Cleanup clears it; a mode without a start never finishes",
            func = function(state)
                local tdm = mode("tdm")
                prepare(state, tdm, { scorelimit = 75, timelimit = 1 }, 0)
                tdm._StartedAt = nil
                must(tdm.Think)(tdm)
                expect(#finished(state)).to.equal(0)
                must(tdm.Start)(tdm)
                expect(tdm._StartedAt).to.equal(CurTime())
                must(tdm.Cleanup)(tdm)
                expect(tdm._StartedAt).to.beNil()
            end
        },
        {
            name = "Respawn answers: the mode allows respawning after its respawn delay setting",
            func = function(state)
                local tdm = mode("tdm")
                prepare(state, tdm, { respawndelay = 2.5 }, 0)
                expect(must(tdm.PW_CanRespawn)(tdm)).to.beTrue()
                expect(must(tdm.PW_RespawnDelay)(tdm)).to.equal(2.5)
            end
        }
    }
}
