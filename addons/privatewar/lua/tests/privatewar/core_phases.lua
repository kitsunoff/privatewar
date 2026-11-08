-- T-1.12 phase machine (TASKS.md, "Mandatory test cases" T-1.12 and the real-machine T-1.8 case; 00-core.md
-- d.1-d.5; 02-modes.md d.7). Every case swaps in a fresh machine store (fake clock, injected players and
-- durations, capturing logger), a fresh PW.Call store and fresh settings and enable stores (a started match takes
-- its snapshots there), and restores them, PW.ActiveMode, pw_aftermatch and the test listeners afterwards, so the
-- real machine stays in LOBBY and the real stores keep no match snapshot.

local listenerId = "PW_Test_Phases"
local watched = { "PW_PhaseChange", "PW_MatchStart", "PW_MatchEnd" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return ConVar
local function afterMatchVar()
    return must(GetConVar("pw_aftermatch"))
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@return PW.MatchStore
local function store()
    return PW._Match
end

---@param state table<string, any>
local function installStore(state)
    PW._Match = match()._NewStore({
        log = function(message)
            local logged = state.logged --[[@as string[] ]]
            logged[#logged + 1] = message
        end,
        clock = function() return state.now end,
        players = function() return state.players end,
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

---Registers a counting mode in an isolated registry; extra methods override the counting ones.
---@param state table<string, any>
---@param extra? table<string, function>
---@return table
local function newMode(state, extra)
    local registry = PW.Registry.New("test_phases", { log = function() end, preRegister = function() end })
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    local counts = state.counts --[[@as table<string, integer>]]
    ---@type table<string, any>
    local def = { Name = "Test", Teams = 0 }
    for _, method in ipairs({ "Start", "Cleanup", "Think" }) do
        def[method] = function() counts[method] = counts[method] + 1 end
    end
    for key, fn in pairs(extra or {}) do def[key] = fn end
    registry.Register(def, "testmode")
    registry.ResolveAll()
    state.registry = registry
    return must(registry.Get("testmode"))
end

---Moves the fake clock to the end of the current phase and runs one machine step.
---@param state table<string, any>
local function expire(state)
    state.now = store().endsAt
    match()._Tick()
end

---Drives the machine from LOBBY to target through the public flow.
---@param state table<string, any>
---@param target PW.PhaseName
local function driveTo(state, target)
    if target == "LOBBY" then return end
    assert(match().Start(state.mode), "Start failed")
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
---@param name string
---@return integer
local function eventCount(state, name)
    local count = 0
    for _, event in ipairs(state.events --[[@as string[] ]]) do
        if string.sub(event, 1, #name) == name then count = count + 1 end
    end
    return count
end

return {
    groupName = "PW phase machine",
    -- afterEach has restored every real store before yielding. A zero-delay group timer can run in this same tick;
    -- phase listeners have queued real spawns/net updates even though the phase machine's players are injected.
    afterAll = function() include("privatewar_fixtures/resource_lifecycle.lua").Yield(timer.Simple) end,
    beforeEach = function(state)
        state.previousStore = PW._Match
        state.previousSettings = PW._Settings
        state.previousEnable = PW._Enable
        -- Matches started here take their snapshots in fresh stores, never in the real ones.
        PW._Settings = must(PW.Settings)._NewStore()
        PW._Enable = must(PW.Enable)._NewStore({ registries = function() return {} end })
        state.previousCall = PW._Call
        state.previousMode = PW.ActiveMode
        state.previousAfterMatch = afterMatchVar():GetString()
        state.now = 1000
        state.players = {}
        state.logged = {}
        state.events = {}
        state.registries = {}
        state.counts = { Start = 0, Cleanup = 0, Think = 0 }
        PW.ActiveMode = nil
        afterMatchVar():SetString("lobby")
        PW._Call = { log = function() end, failed = setmetatable({}, { __mode = "k" }), profile = {} }
        installStore(state)
        local events = state.events --[[@as string[] ]]
        for _, name in ipairs(watched) do
            hook.Add(name, listenerId, function(a, b)
                events[#events + 1] = name .. ":" .. tostring(a) .. ":" .. tostring(b)
            end)
        end
        state.mode = newMode(state)
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
            name = "The transition table is exactly the one of 00-core.md d.5 (plus the PREMATCH countdown)",
            func = function()
                local expected = {
                    "LOBBY>PREMATCH", "PREMATCH>PREMATCH", "PREMATCH>LIVE", "PREMATCH>LOBBY", "LIVE>POSTMATCH",
                    "LIVE>LOBBY", "POSTMATCH>VOTE", "POSTMATCH>LOBBY", "VOTE>PREMATCH", "VOTE>LOBBY"
                }
                ---@type table<string, true>
                local listed = {}
                for from, targets in pairs(PW.Phase.Transitions) do
                    for to in pairs(targets) do listed[from .. ">" .. to] = true end
                end
                for _, pair in ipairs(expected) do
                    expect(listed[pair]).to.beTrue()
                    listed[pair] = nil
                end
                expect(next(listed)).to.beNil()
            end
        },
        {
            name = "Every transition in the table fires and no other transition is possible",
            func = function(state)
                for _, from in ipairs(PW.Phase.Names) do
                    for _, to in ipairs(PW.Phase.Names) do
                        installStore(state)
                        store().phase = from
                        state.events = {}
                        state.logged = {}
                        local events = state.events --[[@as string[] ]]
                        hook.Add("PW_PhaseChange", listenerId, function(a, b)
                            events[#events + 1] = "PW_PhaseChange:" .. tostring(a) .. ":" .. tostring(b)
                        end)
                        local allowed = PW.Phase.CanTransition(from, to)
                        expect(match()._SetPhase(to)).to.equal(allowed)
                        if allowed then
                            expect(store().phase).to.equal(to)
                            expect(#events).to.equal(1)
                            expect(events[1]).to.equal("PW_PhaseChange:" .. to .. ":" .. from)
                            expect(#state.logged).to.equal(0)
                        else
                            expect(store().phase).to.equal(from)
                            expect(#events).to.equal(0)
                            expect(#state.logged).to.equal(1)
                        end
                    end
                end
                expect(match()._SetPhase("NOPE")).to.beFalse()
            end
        },
        {
            name = "The phase end time is CurTime-based, -1 when the phase has none",
            func = function(state)
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(match().GetPhaseEnd()).to.equal(-1)
                match().Start(state.mode)
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(match().GetPhaseEnd()).to.equal(1060)
                expect(PW.ActiveMode).to.equal(state.mode)
            end
        },
        {
            name = "PREMATCH -> LIVE on all ready (bots count as ready), then a countdown",
            func = function(state)
                local human = { name = "human" }
                state.players = { { key = human, bot = false }, { key = { name = "bot" }, bot = true } }
                driveTo(state, "PREMATCH")
                match()._Tick()
                expect(store().countdown).to.beFalse()
                match().SetReady(human)
                state.now = 1001
                match()._Tick()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(store().countdown).to.beTrue()
                expect(match().GetPhaseEnd()).to.equal(1011)
                state.now = 1010.9
                match()._Tick()
                expect(match().GetPhase()).to.equal("PREMATCH")
                state.now = 1011
                match()._Tick()
                expect(match().GetPhase()).to.equal("LIVE")
                expect(match().GetPhaseEnd()).to.equal(-1)
            end
        },
        {
            name = "PREMATCH -> LIVE on timeout when a human is not ready",
            func = function(state)
                state.players = { { key = { name = "human" }, bot = false } }
                driveTo(state, "PREMATCH")
                state.now = 1059.9
                match()._Tick()
                expect(store().countdown).to.beFalse()
                state.now = 1060
                match()._Tick()
                expect(store().countdown).to.beTrue()
                state.now = 1070
                match()._Tick()
                expect(match().GetPhase()).to.equal("LIVE")
            end
        },
        {
            name = "Ready flags are cleared when a match begins",
            func = function(state)
                local human = { name = "human" }
                state.players = { { key = human, bot = false } }
                match().SetReady(human)
                driveTo(state, "PREMATCH")
                match()._Tick()
                expect(store().countdown).to.beFalse()
            end
        },
        {
            name = "PW.Match.Finish moves LIVE to POSTMATCH and passes the result to PW_MatchEnd",
            func = function(state)
                driveTo(state, "PREMATCH")
                expect(match().Finish({})).to.beFalse()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(#state.logged).to.equal(1)
                expire(state)
                expire(state)
                expect(match().GetPhase()).to.equal("LIVE")
                local result = { winner = 2 }
                expect(match().Finish(result)).to.beTrue()
                expect(match().GetPhase()).to.equal("POSTMATCH")
                expect(match().GetPhaseEnd()).to.equal(state.now + 15)
                local events = state.events --[[@as string[] ]]
                -- Leaving LIVE ends the match first, then the phase change is announced.
                expect(events[#events - 1]).to.equal("PW_MatchEnd:" .. tostring(result) .. ":nil")
                expect(events[#events]).to.equal("PW_PhaseChange:POSTMATCH:LIVE")
                expect(PW.ActiveMode).to.equal(state.mode)
            end
        },
        {
            name = "Host abort returns to LOBBY from any phase and keeps the reason",
            func = function(state)
                for _, phase in ipairs(PW.Phase.Names) do
                    installStore(state)
                    afterMatchVar():SetString("lobby")
                    driveTo(state, phase)
                    expect(match().GetPhase()).to.equal(phase)
                    match().Abort("host abort from " .. phase)
                    expect(match().GetPhase()).to.equal("LOBBY")
                    expect(match().GetPhaseEnd()).to.equal(-1)
                    expect(match().GetAbortReason()).to.equal("host abort from " .. phase)
                    expect(PW.ActiveMode).to.beNil()
                end
                match().Start(state.mode)
                expect(match().GetAbortReason()).to.beNil()
            end
        },
        {
            name = "The abort command needs the pw.match.abort privilege",
            func = function(state)
                local user = { IsValid = function() return true end, Nick = function() return "user" end,
                    IsAdmin = function() return false end, IsSuperAdmin = function() return false end }
                local host = { IsValid = function() return true end, Nick = function() return "host" end,
                    IsAdmin = function() return true end, IsSuperAdmin = function() return true end }
                driveTo(state, "LIVE")
                expect(match()._AbortCommand(user, {})).to.beFalse()
                expect(match().GetPhase()).to.equal("LIVE")
                expect(match()._AbortCommand(host, { "too", "slow" })).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(match().GetAbortReason()).to.equal("too slow")
                driveTo(state, "PREMATCH")
                expect(match()._AbortCommand(nil, {})).to.beTrue()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(string.find(must(match().GetAbortReason()), "server console", 1, true)).to.exist()
            end
        },
        {
            name = "After-match setting lobby: POSTMATCH -> LOBBY after the timer, VOTE skipped",
            func = function(state)
                driveTo(state, "POSTMATCH")
                afterMatchVar():SetString("lobby")
                state.now = store().endsAt - 0.1
                match()._Tick()
                expect(match().GetPhase()).to.equal("POSTMATCH")
                expire(state)
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(PW.ActiveMode).to.beNil()
                expect(eventCount(state, "PW_PhaseChange:VOTE")).to.equal(0)
            end
        },
        {
            name = "After-match setting rotation: POSTMATCH -> VOTE -> PREMATCH with the next match",
            func = function(state)
                driveTo(state, "POSTMATCH")
                afterMatchVar():SetString("rotation")
                expire(state)
                expect(match().GetPhase()).to.equal("VOTE")
                expect(match().GetPhaseEnd()).to.equal(state.now + 15)
                expire(state)
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(match().GetPhaseEnd()).to.equal(state.now + 60)
                expect(store().countdown).to.beFalse()
                expect(PW.ActiveMode).to.equal(state.mode)
                expire(state)
                expire(state)
                expect(match().GetPhase()).to.equal("LIVE")
            end
        },
        {
            name = "MODE:Start and MODE:Cleanup are called exactly once per match; MODE:Think only in LIVE",
            func = function(state)
                local counts = state.counts --[[@as table<string, integer>]]
                -- A human who never readies: PREMATCH runs to its timeout, so ticks there do not start LIVE.
                state.players = { { key = { name = "human" }, bot = false } }
                match()._Tick()
                driveTo(state, "PREMATCH")
                match()._Tick()
                expect(counts.Think).to.equal(0)
                expect(counts.Start).to.equal(0)
                expire(state)
                expire(state)
                expect(match().GetPhase()).to.equal("LIVE")
                expect(counts.Start).to.equal(1)
                expect(counts.Cleanup).to.equal(0)
                local before = counts.Think
                match()._Tick()
                match()._Tick()
                expect(counts.Think).to.equal(before + 2)
                match().Finish({})
                match().Finish({})
                expect(counts.Cleanup).to.equal(1)
                local afterLive = counts.Think
                match()._Tick()
                afterMatchVar():SetString("rotation")
                expire(state)
                match()._Tick()
                expect(match().GetPhase()).to.equal("VOTE")
                expect(counts.Think).to.equal(afterLive)
                expect(counts.Start).to.equal(1)
                expect(counts.Cleanup).to.equal(1)
                expect(eventCount(state, "PW_MatchStart")).to.equal(1)
                expect(eventCount(state, "PW_MatchEnd")).to.equal(1)

                -- Second match, aborted in LIVE: once more each.
                expire(state)
                expire(state)
                expire(state)
                expect(match().GetPhase()).to.equal("LIVE")
                match().Abort("stop")
                expect(counts.Start).to.equal(2)
                expect(counts.Cleanup).to.equal(2)
                expect(eventCount(state, "PW_MatchEnd")).to.equal(2)

                -- Third match, aborted in PREMATCH: the mode never started, so no Cleanup and no PW_MatchEnd.
                driveTo(state, "PREMATCH")
                match().Abort("stop")
                expect(counts.Start).to.equal(2)
                expect(counts.Cleanup).to.equal(2)
                expect(eventCount(state, "PW_MatchStart")).to.equal(2)
                expect(eventCount(state, "PW_MatchEnd")).to.equal(2)
            end
        },
        {
            name = "The active mode erroring ends the match and returns to LOBBY with the error message (real machine)",
            func = function(state)
                local counts = state.counts --[[@as table<string, integer>]]
                state.mode = newMode(state, { Think = function() error("think boom") end })
                driveTo(state, "LIVE")
                match()._Tick()
                expect(match().GetPhase()).to.equal("LOBBY")
                local reason = must(match().GetAbortReason())
                expect(string.find(reason, "mode testmode failed: ", 1, true)).to.equal(1)
                expect(string.find(reason, "think boom", 1, true)).to.exist()
                expect(counts.Cleanup).to.equal(1)
                expect(PW.ActiveMode).to.beNil()
            end
        },
        {
            name = "MODE:Start erroring aborts the match after it entered LIVE; Cleanup still runs once",
            func = function(state)
                local counts = state.counts --[[@as table<string, integer>]]
                state.mode = newMode(state, { Start = function() error("start boom") end })
                driveTo(state, "LIVE")
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(string.find(must(match().GetAbortReason()), "start boom", 1, true)).to.exist()
                expect(counts.Cleanup).to.equal(1)
                expect(eventCount(state, "PW_MatchStart")).to.equal(eventCount(state, "PW_MatchEnd"))
            end
        },
        {
            name = "PW.Match.Finish called from MODE:Start runs right after the phase change",
            func = function(state)
                state.mode = newMode(state, { Start = function() match().Finish({ instant = true }) end })
                driveTo(state, "LIVE")
                expect(match().GetPhase()).to.equal("POSTMATCH")
                expect(eventCount(state, "PW_MatchStart")).to.equal(1)
                expect(eventCount(state, "PW_MatchEnd")).to.equal(1)
            end
        },
        {
            name = "Start is rejected outside LOBBY and for a non-entity",
            func = function(state)
                expect(match().Start({})).to.beFalse()
                expect(match().GetPhase()).to.equal("LOBBY")
                driveTo(state, "LIVE")
                expect(match().Start(state.mode)).to.beFalse()
                expect(match().GetPhase()).to.equal("LIVE")
                expect(#state.logged).to.equal(2)
            end
        },
        {
            name = "A late registration in the mode's registry does not stop the active mode",
            func = function(state)
                local counts = state.counts --[[@as table<string, integer>]]
                driveTo(state, "LIVE")
                local registry = state.registry --[[@as PW.Registry]]
                registry.Register({ Name = "Other", Teams = 2 }, "othermode")
                local before = counts.Think
                match()._Tick()
                expect(counts.Think).to.equal(before + 1)
                expect(registry.Get("testmode")).to.equal(state.mode)
            end
        },
        {
            name = "Durations and the after-match setting come from ConVars",
            func = function()
                local settings = match()._ReadSettings()
                expect(settings.prematch).to.equal(must(GetConVar("pw_prematch_timeout")):GetFloat())
                expect(settings.countdown).to.equal(must(GetConVar("pw_countdown")):GetFloat())
                expect(settings.postmatch).to.equal(must(GetConVar("pw_postmatch_time")):GetFloat())
                expect(settings.vote).to.equal(must(GetConVar("pw_vote_time")):GetFloat())
                afterMatchVar():SetString("rotation")
                expect(match()._ReadSettings().afterMatch).to.equal("rotation")
                afterMatchVar():SetString("something")
                expect(match()._ReadSettings().afterMatch).to.equal("lobby")
            end
        },
        {
            name = "Pure rules: all ready ignores bots; the next step follows the timers",
            coroutine = true,
            func = function()
                local human = {}
                expect(PW.Phase._AllReady({}, {})).to.beTrue()
                expect(PW.Phase._AllReady({ { key = human, bot = false } }, {})).to.beFalse()
                expect(PW.Phase._AllReady({ { key = human, bot = false }, { key = {}, bot = true } },
                    { [human] = true })).to.beTrue()
                ---@type PW.PhaseSettings
                local settings = { prematch = 60, countdown = 10, postmatch = 15, vote = 15, afterMatch = "lobby" }
                local live = PW.Phase._Next({ phase = "LIVE", endsAt = -1, countdown = false }, 5, true, settings)
                local lobby = PW.Phase._Next({ phase = "LOBBY", endsAt = -1, countdown = false }, 5, true, settings)
                expect(live).to.beNil()
                expect(lobby).to.beNil()
                local step = must(PW.Phase._Next({ phase = "VOTE", endsAt = 5, countdown = false }, 5, false, settings))
                expect(step.phase).to.equal("PREMATCH")
                expect(step.begin).to.beTrue()
            end
        }
    }
}
