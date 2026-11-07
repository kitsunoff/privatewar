-- Frozen objective lifecycle contract: tests precede implementation.
-- No real players, clock changes, swaps, spawns or match finishes. Existing round_base cases remain unchanged.

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

---@param state table<string, any>
---@return table<string, any>
local function child(state)
    local log = state.log --[[@as string[] ]]
    return setmetatable({
        Teams = 2, RoundsToWin = 9, SwapSidesEvery = 1,
        Setting = function(_, key) return ({ roundtime = 30, intermission = 5 })[key] end,
        PrepareRound = function(_, round, swapped)
            log[#log + 1] = "prepare:" .. round .. ":" .. tostring(swapped)
        end,
        _RespawnAll = function() log[#log + 1] = "spawn" end,
        RoundWinner = function() return nil end
    }, { __index = base() })
end

---@param actions PW.RoundAction[]
---@return string[]
local function kinds(actions)
    ---@type string[]
    local out = {}
    for i, action in ipairs(actions) do out[i] = action.kind end
    return out
end

return {
    groupName = "PW round objective lifecycle",
    beforeEach = function(state)
        state.log = {}
        local log = state.log --[[@as string[] ]]
        state.finish = must(PW.Match).Finish
        state.abort = must(PW.Match).Abort
        state.swap = must(PW.Teams).Swap
        rawset(must(PW.Match), "Finish", function()
            log[#log + 1] = "finish"
            return true
        end)
        rawset(must(PW.Match), "Abort", function()
            log[#log + 1] = "abort"
            return true
        end)
        must(PW.Teams).Swap = function()
            log[#log + 1] = "swap"
            return 0
        end
        hook.Add("PW_RoundStart", "PW_Test_RoundObjective", function(round)
            log[#log + 1] = "start:" .. round
        end)
        hook.Add("PW_RoundEnd", "PW_Test_RoundObjective", function(round)
            log[#log + 1] = "end:" .. round
        end)
        hook.Add("PW_RoundPreparing", "PW_Test_RoundObjective", function(round)
            log[#log + 1] = "preparing:" .. round
        end)
        hook.Add("PW_RoundPrepared", "PW_Test_RoundObjective", function(round)
            log[#log + 1] = "prepared:" .. round
        end)
    end,
    afterEach = function(state)
        must(PW.Match).Finish = state.finish
        must(PW.Match).Abort = state.abort
        must(PW.Teams).Swap = state.swap
        hook.Remove("PW_RoundStart", "PW_Test_RoundObjective")
        hook.Remove("PW_RoundEnd", "PW_Test_RoundObjective")
        hook.Remove("PW_RoundPreparing", "PW_Test_RoundObjective")
        hook.Remove("PW_RoundPrepared", "PW_Test_RoundObjective")
    end,
    cases = {
        {
            name = "Round objective: planted overtime survives the base deadline",
            func = function()
                local s = base()._NewState(2, 9, 1, 120, 5)
                base()._Step(s, 0, nil)
                expect(base()._Step(s, 120, nil, true)).to.deepEqual({})
                expect(base()._Step(s, 164, nil, true)).to.deepEqual({})
                expect(s.phase).to.equal("round")
                expect(s.wins).to.deepEqual({ 0, 0 })
                local actions = base()._Step(s, 165, 2, true)
                expect(kinds(actions)).to.deepEqual({ "end" })
                expect(must(actions[1]).winner).to.equal(2)
                expect(s.wins).to.deepEqual({ 0, 1 })
            end
        },
        {
            name = "Round objective: ordinary children still draw and timeout deferral is not sticky",
            func = function()
                for _, defer in ipairs({ false, true }) do
                    local s = base()._NewState(2, 9, 0, 30, 5)
                    base()._Step(s, 0, nil)
                    if defer then expect(base()._Step(s, 30, nil, true)).to.deepEqual({}) end
                    local actions = base()._Step(s, 31, nil)
                    expect(kinds(actions)).to.deepEqual({ "end" })
                    expect(must(actions[1]).winner).to.equal(false)
                end
            end
        },
        {
            name = "Round objective: Think forwards only explicit child timeout deferral",
            func = function(state)
                local mode = child(state)
                mode:Start()
                local s = must(mode._Rounds --[[@as PW.RoundState?]])
                mode:_Run(base()._Step(s, CurTime() - 31, nil))
                rawset(mode, "RoundWinner", function(_, timedOut)
                    expect(timedOut).to.beTrue()
                    return nil, true
                end)
                mode:Think()
                expect(s.phase).to.equal("round")
                rawset(mode, "RoundWinner", function() return nil end)
                mode:Think()
                expect(s.phase).to.equal("intermission")
                mode:Cleanup()
            end
        },
        {
            name = "Round objective: prepare follows swap and precedes every playable respawn",
            func = function(state)
                local mode = child(state)
                mode:Start()
                -- The core's PW_MatchStart spawn happens after Start; simulate that external spawn, not a base respawn.
                local log = state.log --[[@as string[] ]]
                log[#log + 1] = "initial-spawn"
                local s = must(mode._Rounds --[[@as PW.RoundState?]])
                mode:_Run(base()._Step(s, 0, nil))
                mode:_Run(base()._Step(s, 1, 1))
                mode:_Run(base()._Step(s, 6, nil))
                mode:_Run(base()._Step(s, 7, 2))
                mode:_Run(base()._Step(s, 12, nil))
                expect(state.log).to.deepEqual({
                    "preparing:1", "prepare:1:false", "prepared:1", "initial-spawn", "start:1", "end:1", "swap",
                    "preparing:2", "prepare:2:true", "prepared:2", "spawn", "start:2", "end:2", "swap",
                    "preparing:3", "prepare:3:true", "prepared:3", "spawn", "start:3"
                })
                mode:Cleanup()
            end
        },
        {
            name = "Round objective: terminal verdict prevents another swap spawn or award",
            func = function(state)
                local mode = child(state)
                mode.RoundsToWin = 1
                mode:Start()
                local s = must(mode._Rounds --[[@as PW.RoundState?]])
                mode:_Run(base()._Step(s, 0, nil))
                mode:_Run(base()._Step(s, 1, 1))
                local final = table.Copy(s.wins)
                for i = 1, 3 do mode:_Run(base()._Step(s, i * 100, 1)) end
                expect(state.log).to.deepEqual({
                    "preparing:1", "prepare:1:false", "prepared:1", "start:1", "end:1", "finish"
                })
                expect(s.wins).to.deepEqual(final)
                expect(s.phase).to.equal("over")
                mode:Cleanup()
            end
        },
        {
            name = "Fixed total: limits 1 and 3 finish once with no extra respawn despite RoundsToWin 1",
            func = function()
                for _, limit in ipairs({ 1, 3 }) do
                    local s = base()._NewState(2, 1, 1, 30, 5, limit)
                    base()._Step(s, 0, nil)
                    local finishes, starts, swaps = 0, 1, 0
                    for round = 1, limit do
                        local endActions = base()._Step(s, round * 10, 1)
                        expect(must(endActions[1]).kind).to.equal("end")
                        if round < limit then
                            expect(kinds(endActions)).to.deepEqual({ "end" })
                        else
                            expect(kinds(endActions)).to.deepEqual({ "end", "finish" })
                            finishes = finishes + 1
                            expect(must(must(endActions[2]).result).reason).to.equal("roundlimit")
                        end
                        for _, action in ipairs(base()._Step(s, round * 10 + 5, nil)) do
                            if action.kind == "start" then starts = starts + 1 end
                            if action.kind == "swap" then swaps = swaps + 1 end
                        end
                    end
                    expect({ finishes, starts, swaps }).to.deepEqual({ 1, limit, limit - 1 })
                    expect(s.round).to.equal(limit)
                    expect(base()._Step(s, 1e6, 1)).to.deepEqual({})
                end
            end
        },
        {
            name = "Fixed total: Start snapshots the child RoundLimit before the initial spawn",
            func = function(state)
                local mode = child(state)
                mode.RoundLimit = 3
                mode:Start()
                local s = must(mode._Rounds --[[@as PW.RoundState?]])
                expect(s.roundLimit).to.equal(3)
                mode.RoundLimit = 1
                expect(s.roundLimit).to.equal(3)
                mode:Cleanup()
            end
        },
        {
            name = "Fixed total: drawn rounds count and tied wins produce a match draw",
            func = function()
                local s = base()._NewState(2, 1, 0, 30, 5, 3)
                base()._Step(s, 0, nil)
                base()._Step(s, 1, 1)
                base()._Step(s, 6, nil)
                base()._Step(s, 7, 2)
                base()._Step(s, 12, nil)
                local actions = base()._Step(s, 13, false)
                expect(kinds(actions)).to.deepEqual({ "end", "finish" })
                local result = must(must(actions[2]).result)
                expect(result.draw).to.beTrue()
                expect(result.winner).to.beNil()
                expect(result.standings).to.deepEqual({ { id = 1, score = 1 }, { id = 2, score = 1 } })
            end
        },
        {
            name = "Round objective: failed preparation emits no Prepared or later spawn/start",
            func = function(state)
                local mode = child(state)
                mode:Start()
                local s = must(mode._Rounds --[[@as PW.RoundState?]])
                mode:_Run(base()._Step(s, 0, nil))
                mode:_Run(base()._Step(s, 1, 1))
                rawset(mode, "PrepareRound", function() error("expected preparation failure") end)
                state.log = {}
                -- The recorders retain their original list; compare its tail after the attempted next start.
                 ---@type string[]
                 local original = {}
                mode._RespawnAll = function() original[#original + 1] = "spawn" end
                local prepared = 0
                hook.Add("PW_RoundPrepared", "PW_Test_FailedPrepare", function() prepared = prepared + 1 end)
                mode:_Run(base()._Step(s, 6, nil))
                hook.Remove("PW_RoundPrepared", "PW_Test_FailedPrepare")
                expect(prepared).to.equal(0)
                expect(original).to.deepEqual({})
                mode:Cleanup()
            end
        },
        {
            name = "Round objective: terminal transform runs once and nil preserves the legacy result",
            func = function(state)
                local mode = child(state)
                mode.RoundsToWin = 1
                local calls, captured = 0, nil
                mode.FinalizeRounds = function(_, result)
                    calls, captured = calls + 1, result
                    return nil
                end
                mode:Start()
                local s = must(mode._Rounds --[[@as PW.RoundState?]])
                mode:_Run(base()._Step(s, 0, nil))
                mode:_Run(base()._Step(s, 1, 2))
                mode:_Run(base()._Step(s, 100, 2))
                expect(calls).to.equal(1)
                expect(must(captured).winner).to.equal(2)
                expect(state.log[#state.log]).to.equal("finish")
                mode:Cleanup()
            end
        },
        {
            name = "Round objective: personal transformed tied standings reach Finish once",
            func = function(state)
                local mode = child(state)
                mode.RoundsToWin = 1
                local result = { reason = "roundlimit", teams = false, draw = true,
                    standings = { { id = "participant_one", score = 1 }, { id = "participant_two", score = 1 } } }
                mode.FinalizeRounds = function() return result end
                local received, finishes = nil, 0
                rawset(must(PW.Match), "Finish", function(value)
                    received, finishes = value, finishes + 1
                    return true
                end)
                mode:Start()
                local s = must(mode._Rounds --[[@as PW.RoundState?]])
                mode:_Run(base()._Step(s, 0, nil))
                mode:_Run(base()._Step(s, 1, 1))
                mode:_Run(base()._Step(s, 100, 1))
                expect(received).to.equal(result)
                expect(finishes).to.equal(1)
                mode:Cleanup()
            end
        },
        {
            name = "Round objective: invalid or erroring terminal transform aborts without Finish or another round",
            func = function(state)
                for _, throws in ipairs({ false, true }) do
                    local mode = child(state)
                    mode.RoundsToWin = 1
                    mode.FinalizeRounds = function()
                        if throws then error("expected terminal transform failure") end
                        return { draw = false }
                    end
                    local finishes, aborts = 0, 0
                    rawset(must(PW.Match), "Finish", function() finishes = finishes + 1 return true end)
                    rawset(must(PW.Match), "Abort", function() aborts = aborts + 1 return true end)
                    mode:Start()
                    local s = must(mode._Rounds --[[@as PW.RoundState?]])
                    mode:_Run(base()._Step(s, 0, nil))
                    mode:_Run(base()._Step(s, 1, 1))
                    mode:_Run(base()._Step(s, 100, 1))
                    expect({ finishes, aborts }).to.deepEqual({ 0, 1 })
                    expect(s.phase).to.equal("over")
                    mode:Cleanup()
                end
            end
        },
        {
            name = "Fixed total: absent or zero limit preserves ordinary RoundsToWin",
            func = function()
                for _, zero in ipairs({ false, true }) do
                    local s = base()._NewState(2, 1, 0, 30, 5)
                    if zero then s = base()._NewState(2, 1, 0, 30, 5, 0) end
                    base()._Step(s, 0, nil)
                    expect(kinds(base()._Step(s, 1, 1))).to.deepEqual({ "end", "finish" })
                end
            end
        }
    }
}
