-- Host abort against a racing Finish (00-core.md d.5: the host abort returns to LOBBY from any phase; a Finish that
-- arrives after an Abort never wins). Guards the candidates checked for the cp1.sh 5.2 failure: a Finish queued
-- during a transition, a Finish in the same tick as the abort, an abort while a transition is in progress. Every case
-- runs an isolated machine store (fake clock, capturing logger) with fresh PW.Call, settings and enable stores, and
-- restores them, PW.ActiveMode, pw_aftermatch and the test listeners afterwards; the real machine stays untouched.

local listenerId = "PW_Test_AbortRace"
local watched = { "PW_PhaseChange", "PW_MatchEnd" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
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

---@return ConVar
local function afterMatchVar()
    return must(GetConVar("pw_aftermatch"))
end

---@param state table<string, any>
local function installStore(state)
    PW._Match = match()._NewStore({
        log = function(message)
            local logged = state.logged --[[@as string[] ]]
            logged[#logged + 1] = message
        end,
        clock = function() return state.now end,
        players = function() return {} end,
        settings = function()
            local settings = match()._ReadSettings()
            settings.prematch = 60
            settings.countdown = 10
            settings.postmatch = 15
            settings.vote = 15
            return settings
        end
    })
end

---Registers a mode in an isolated registry; extra methods are its own.
---@param state table<string, any>
---@param extra? table<string, function>
---@return table
local function newMode(state, extra)
    local registry = PW.Registry.New("test_abort_race", { log = function() end, preRegister = function() end })
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    ---@type table<string, any>
    local def = { Name = "Test", Teams = 0 }
    for key, fn in pairs(extra or {}) do def[key] = fn end
    registry.Register(def, "testmode")
    registry.ResolveAll()
    return must(registry.Get("testmode"))
end

---Moves the fake clock to the end of the current phase and runs one machine step.
---@param state table<string, any>
local function expire(state)
    state.now = PW._Match.endsAt
    match()._Tick()
end

---Drives the machine from LOBBY to target through the public flow.
---@param state table<string, any>
---@param mode table
---@param target PW.PhaseName
local function driveTo(state, mode, target)
    assert(match().Start(mode), "Start failed")
    if target == "PREMATCH" then return end
    expire(state)
    expire(state)
    if target == "LIVE" then return end
    assert(match().Finish({ winner = 1 }), "Finish failed")
    if target == "POSTMATCH" then return end
    afterMatchVar():SetString("rotation")
    expire(state)
end

---@param state table<string, any>
---@return string[]
local function phaseChanges(state)
    return state.changes --[[@as string[] ]]
end

return {
    groupName = "PW abort race",
    beforeEach = function(state)
        state.previousStore = PW._Match
        state.previousSettings = PW._Settings
        state.previousEnable = PW._Enable
        state.previousCall = PW._Call
        state.previousMode = PW.ActiveMode
        state.previousAfterMatch = afterMatchVar():GetString()
        PW._Settings = must(PW.Settings)._NewStore()
        PW._Enable = must(PW.Enable)._NewStore({ registries = function() return {} end })
        PW._Call = { log = function() end, failed = setmetatable({}, { __mode = "k" }), profile = {} }
        PW.ActiveMode = nil
        afterMatchVar():SetString("lobby")
        state.now = 1000
        state.logged = {}
        state.registries = {}
        state.changes = {}
        state.ended = 0
        installStore(state)
        local changes = state.changes --[[@as string[] ]]
        hook.Add("PW_PhaseChange", listenerId, function(to, from) changes[#changes + 1] = from .. ">" .. to end)
        hook.Add("PW_MatchEnd", listenerId, function() state.ended = state.ended + 1 end)
    end,
    afterEach = function(state)
        for _, name in ipairs(watched) do hook.Remove(name, listenerId) end
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        PW._Match = state.previousStore
        PW._Settings = state.previousSettings
        PW._Enable = state.previousEnable
        PW._Call = state.previousCall
        PW.ActiveMode = state.previousMode
        afterMatchVar():SetString(state.previousAfterMatch)
    end,
    cases = {
        {
            name = "Abort from every phase returns to LOBBY with the reason",
            func = function(state)
                local mode = newMode(state)
                for _, target in ipairs({ "PREMATCH", "LIVE", "POSTMATCH", "VOTE" }) do
                    driveTo(state, mode, target --[[@as PW.PhaseName]])
                    expect(match().GetPhase()).to.equal(target)
                    expect(match().Abort("abort in " .. target)).to.beTrue()
                    expect(match().GetPhase()).to.equal("LOBBY")
                    expect(match().GetAbortReason()).to.equal("abort in " .. target)
                    afterMatchVar():SetString("lobby")
                end
            end
        },
        {
            name = "A Finish in the same tick after the Abort does not win: the machine stays in LOBBY",
            func = function(state)
                local thinks = 0
                local mode = newMode(state, { Think = function() thinks = thinks + 1 end })
                driveTo(state, mode, "LIVE")
                local liveThinks = thinks
                match().Abort("host abort")
                expect(match().Finish({ winner = 1 })).to.beFalse()
                match()._Tick()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(match().GetAbortReason()).to.equal("host abort")
                expect(thinks).to.equal(liveThinks)
                expect(state.ended).to.equal(1)
                expect(table.HasValue(phaseChanges(state), "LOBBY>POSTMATCH")).to.beFalse()
            end
        },
        {
            name = "Abort then Finish, both queued during a transition (MODE:Start): LOBBY wins",
            func = function(state)
                local mode = newMode(state, {
                    Start = function()
                        match().Abort("abort during start")
                        match().Finish({ winner = 1 })
                    end
                })
                driveTo(state, mode, "LIVE")
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(match().GetAbortReason()).to.equal("abort during start")
                expect(state.ended).to.equal(1)
            end
        },
        {
            name = "Finish then Abort, both queued during a transition (MODE:Start): LOBBY wins",
            func = function(state)
                local mode = newMode(state, {
                    Start = function()
                        match().Finish({ winner = 1 })
                        match().Abort("abort after finish")
                    end
                })
                driveTo(state, mode, "LIVE")
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(match().GetAbortReason()).to.equal("abort after finish")
                expect(state.ended).to.equal(1)
            end
        },
        {
            name = "A Finish from a PW_MatchEnd listener while the Abort leaves LIVE does not win",
            func = function(state)
                local mode = newMode(state)
                driveTo(state, mode, "LIVE")
                local ended = 0
                hook.Add("PW_MatchEnd", listenerId, function()
                    ended = ended + 1
                    match().Finish({ winner = 2 })
                end)
                match().Abort("abort with a late finish")
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(match().GetAbortReason()).to.equal("abort with a late finish")
                expect(ended).to.equal(1)
                expect(table.HasValue(phaseChanges(state), "LOBBY>POSTMATCH")).to.beFalse()
            end
        },
        {
            name = "Abort while the transition into PREMATCH is in progress returns to LOBBY right after it",
            func = function(state)
                local mode = newMode(state)
                local changes = phaseChanges(state)
                ---@param to string
                ---@param from string
                hook.Add("PW_PhaseChange", listenerId, function(to, from)
                    changes[#changes + 1] = from .. ">" .. to
                    if to == "PREMATCH" then match().Abort("abort during prematch entry") end
                end)
                expect(match().Start(mode)).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(changes).to.deepEqual({ "LOBBY>PREMATCH", "PREMATCH>LOBBY" })
                expect(match().GetAbortReason()).to.equal("abort during prematch entry")
            end
        }
    }
}
