-- Dev-only dummy mode and pw_dev_start for checkpoint CP-1 item 2 (TASKS.md, CP-1). Both live in the dev addon
-- dev/privatewar_dev/, which the test runner always deploys; neither is shipped (T-10.2). PW.Match.Start and
-- PW.Match.Finish are swapped for recorders, so no case starts or ends a real match.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.Mode
local function dummy()
    return must(PW.Modes.Get("pw_dummy")) --[[@as PW.Mode]]
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---Arguments of every recorded call, in order.
---@param state table<string, any>
---@return table[]
local function calls(state)
    return state.calls --[[@as table[] ]]
end

return {
    groupName = "PW dev dummy mode",
    beforeEach = function(state)
        state.calls = {}
        state.start = match().Start
        state.finish = match().Finish
        state.can = PW.Can
        local recorded = calls(state)
        match().Start = function(...)
            recorded[#recorded + 1] = { "Start", ... }
            return true
        end
        match().Finish = function(...)
            recorded[#recorded + 1] = { "Finish", ... }
            return true
        end
    end,
    afterEach = function(state)
        match().Start = state.start --[[@as fun(mode: table, map?: string): boolean]]
        match().Finish = state.finish --[[@as fun(result?: any): boolean]]
        rawset(PW, "Can", state.can)
        local mode = PW.Modes.Get("pw_dummy")
        if mode ~= nil then must(mode.Cleanup)(mode) end
    end,
    cases = {
        {
            name = "The dummy mode is a valid two-team mode with a short time limit setting",
            func = function()
                local mode = dummy()
                expect(mode.Teams).to.equal(2)
                expect(PW.Loader.ValidateRequired(mode, must(PW.Kinds.Get("modes")).Required)).to.beTrue()
                local timelimit = must(must(mode.Settings).timelimit)
                expect(timelimit.type).to.equal("int")
                expect(timelimit.default).to.equal(30)
            end
        },
        {
            name = "Think finishes the match once, only after the time limit has passed",
            func = function(state)
                local mode = dummy()
                must(mode.Start)(mode)
                must(mode.Think)(mode)
                expect(#calls(state)).to.equal(0)
                mode._EndsAt = CurTime() - 1
                must(mode.Think)(mode)
                must(mode.Think)(mode)
                expect(#calls(state)).to.equal(1)
                local call = must(calls(state)[1])
                expect(call[1]).to.equal("Finish")
                expect(must(call[2]).reason).to.equal("timelimit")
            end
        },
        {
            name = "pw_dev_start from the server console starts the dummy mode on the given map",
            func = function(state)
                concommand.Run(NULL, "pw_dev_start", { "gm_flatgrass" }, "gm_flatgrass")
                expect(#calls(state)).to.equal(1)
                local call = must(calls(state)[1])
                expect(call[1]).to.equal("Start")
                expect(call[2]).to.equal(dummy())
                expect(call[3]).to.equal("gm_flatgrass")
            end
        },
        {
            name = "pw_dev_start without a map starts on the current map",
            func = function(state)
                concommand.Run(NULL, "pw_dev_start", {}, "")
                local call = must(calls(state)[1])
                expect(call[2]).to.equal(dummy())
                expect(call[3]).to.beNil()
            end
        },
        {
            name = "pw_dev_start from a player without the privilege does nothing",
            func = function(state)
                rawset(PW, "Can", function() return false end)
                local fake = {
                    IsValid = function() return true end,
                    Nick = function() return "pw_test_user" end
                }
                concommand.Run(fake --[[@as Player]], "pw_dev_start", {}, "")
                expect(#calls(state)).to.equal(0)
            end
        }
    }
}
