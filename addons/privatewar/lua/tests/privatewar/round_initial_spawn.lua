-- Real phase-machine regressions with isolated stores and a recording notification boundary. No real spawns.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@param state table<string, any>
---@param failure? string
---@return table<string, any>
local function modeOf(state, failure)
    local mode = setmetatable({ ClassName = "test_round_preparation", Teams = 2,
        Setting = function(_, key) return ({ roundtime = 120, intermission = 5 })[key] end,
        PrepareRound = function()
            if failure == "error" then error("expected initial preparation failure") end
            if failure == "abort" then match().Abort("expected initial preparation abort") end
            state.rolesReady = true
        end
    }, { __index = must(PW.Modes.GetStored("round_base")) })
    return mode
end

return {
    groupName = "PW round initial spawn",
    beforeEach = function(state)
        state.match, state.mode, state.call = PW._Match, PW.ActiveMode, PW._Call
        state.settings, state.enable, state.notify = PW._Settings, PW._Enable, PW.Notify
        state.events = {}
        PW._Call = { log = function() end, failed = setmetatable({}, { __mode = "k" }), profile = {} }
        PW._Settings = PW.Settings._NewStore()
        PW._Enable = PW.Enable._NewStore({ registries = function() return {} end })
        PW._Match = match()._NewStore({ clock = function() return 0 end, players = function() return {} end,
            log = function() end })
        PW.ActiveMode = nil
        rawset(PW, "Notify", function(name)
            local events = state.events --[[@as string[] ]]
            events[#events + 1] = name
             if name == "PW_MatchStart" then state.rolesAtSpawn = state.rolesReady == true end
             if name == "PW_RoundPreparing" and state.abortBeforePrepare then match().Abort("preparing aborted") end
        end)
    end,
    afterEach = function(state)
        PW._Match, PW.ActiveMode, PW._Call = state.match, state.mode, state.call
        PW._Settings, PW._Enable = state.settings, state.enable
        rawset(PW, "Notify", state.notify)
    end,
    cases = {
        {
            name = "Initial round: Prepared and role facts precede MatchStart spawn without an early RoundStart",
            func = function(state)
                match().Start(modeOf(state))
                match()._SetPhase("LIVE")
                expect(state.events).to.deepEqual({
                    "PW_PhaseChange", "PW_PhaseChange", "PW_RoundPreparing", "PW_RoundPrepared", "PW_MatchStart"
                })
                expect(state.rolesAtSpawn).to.beTrue()
                match().Abort("initial ordering test complete")
            end
        },
        {
            name = "Initial round: queued active-mode preparation error or abort emits no Prepared MatchStart or spawn",
            func = function(state)
                for _, failure in ipairs({ "error", "abort" }) do
                    state.events = {}
                    match().Start(modeOf(state, failure))
                    match()._SetPhase("LIVE")
                    local events = state.events --[[@as string[] ]]
                    for _, name in ipairs(events) do
                        expect(name == "PW_RoundPrepared").to.beFalse()
                        expect(name == "PW_MatchStart").to.beFalse()
                        expect(name == "PW_RoundStart").to.beFalse()
                    end
                    expect(match().GetPhase()).to.equal("LOBBY")
                    expect(PW._Match.matchStarted).to.beFalse()
                end
            end
        },
        {
            name = "Initial round: abort from Preparing notification prevents child role mutation",
            func = function(state)
                state.abortBeforePrepare = true
                match().Start(modeOf(state))
                match()._SetPhase("LIVE")
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(state.rolesReady).to.beNil()
                for _, name in ipairs(state.events --[[@as string[] ]]) do
                    expect(name == "PW_RoundPrepared" or name == "PW_MatchStart").to.beFalse()
                end
            end
        },
        {
            name = "Spawn wrapper: exactly one post-spawn signal follows synchronous base and loadout initialization",
            func = function()
                 ---@type string[]
                 local events = {}
                local notify = PW.Notify
                rawset(PW, "Notify", function(name, ply)
                    events[#events + 1] = name
                    expect(ply.initialized).to.beTrue()
                end)
                 local fake = { initialized = false,
                     ---@param self { initialized: boolean }
                     Spawn = function(self)
                    events[#events + 1] = "base-and-loadout"
                    self.initialized = true
                end }
                local ok, err = pcall(function() must(must(PW.MatchRules).Spawn)(fake --[[@as Player]]) end)
                rawset(PW, "Notify", notify)
                if not ok then error(err) end
                expect(events).to.deepEqual({ "base-and-loadout", "PW_PlayerSpawned" })
            end
        }
    }
}
