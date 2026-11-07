-- T-1.13 phase networking (TASKS.md, "Mandatory test cases" T-1.13; 00-core.md d.10, d.11). Every case swaps in a
-- fresh machine store whose NW2 writer only records the writes (the real NW2 globals are never touched), a fresh
-- PW.Call store, a fresh instance store and fresh settings and enable stores, and restores them, PW.ActiveMode and
-- pw_aftermatch afterwards, so the real machine stays in LOBBY and the real stores keep no match snapshot. The
-- client side is covered through its pure parts (PW.Phase._Remaining, PW.Phase._EndsInstances, PW.Phase._Apply);
-- the proxy itself is a checkpoint item (CP-1 items 2 and 6).

local keys = { "pw_phase_end", "pw_phase", "pw_phase_seq" }

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
---@param networked boolean
local function installStore(state, networked)
    local writes = state.writes --[[@as table[] ]]
    PW._Match = match()._NewStore({
        log = function() end,
        clock = function() return state.now end,
        players = function() return {} end,
        settings = function()
            return { prematch = 60, countdown = 10, postmatch = 15, vote = 15, afterMatch = "lobby" }
        end,
        write = function(key, value) writes[#writes + 1] = { key = key, value = value } end
    })
    if networked then
        match()._Publish()
        for index = #writes, 1, -1 do writes[index] = nil end
    end
end

---Moves the fake clock to the end of the current phase and runs one machine step.
---@param state table<string, any>
local function expire(state)
    state.now = PW._Match.endsAt
    match()._Tick()
end

---Runs a full match and an aborted one: LOBBY -> PREMATCH -> PREMATCH (countdown) -> LIVE -> POSTMATCH -> LOBBY,
---then LOBBY -> PREMATCH -> LOBBY (abort). Returns the number of transitions.
---@param state table<string, any>
---@return integer
local function runCycle(state)
    assert(match().Start(state.mode), "Start failed")
    expire(state)
    expire(state)
    assert(match().GetPhase() == "LIVE", "expected LIVE")
    assert(match().Finish({ winner = 1 }), "Finish failed")
    expire(state)
    assert(match().GetPhase() == "LOBBY", "expected LOBBY")
    assert(match().Start(state.mode), "second Start failed")
    assert(match().Abort("test"), "Abort failed")
    return 7
end

---Groups the recorded writes into transitions of three writes each.
---@param writes table[]
---@return table[][]
local function triples(writes)
    ---@type table[][]
    local groups = {}
    for index, write in ipairs(writes) do
        local group = math.floor((index - 1) / 3) + 1
        groups[group] = groups[group] or {}
        table.insert(groups[group], write)
    end
    return groups
end

return {
    groupName = "PW phase networking",
    beforeEach = function(state)
        state.previousStore = PW._Match
        state.previousSettings = PW._Settings
        state.previousEnable = PW._Enable
        -- Matches started here take their snapshots in fresh stores, never in the real ones.
        PW._Settings = must(PW.Settings)._NewStore()
        PW._Enable = must(PW.Enable)._NewStore({ registries = function() return {} end })
        state.previousCall = PW._Call
        state.previousInstances = PW._Instances
        state.previousMode = PW.ActiveMode
        state.previousAfterMatch = afterMatchVar():GetString()
        state.now = 1000
        state.writes = {}
        state.mode = { ClassName = "test_phase_net" }
        PW.ActiveMode = nil
        afterMatchVar():SetString("lobby")
        PW._Call = { log = function() end, failed = setmetatable({}, { __mode = "k" }), profile = {} }
        PW._Instances = { live = {}, count = 0 }
    end,
    afterEach = function(state)
        PW._Match = state.previousStore
        PW._Settings = state.previousSettings
        PW._Enable = state.previousEnable
        PW._Call = state.previousCall
        PW._Instances = state.previousInstances
        PW.ActiveMode = state.previousMode
        afterMatchVar():SetString(state.previousAfterMatch)
    end,
    cases = {
        {
            name = "NW2 values are written in the order end -> phase -> seq on every transition",
            func = function(state)
                installStore(state, true)
                local transitions = runCycle(state)
                local writes = state.writes --[[@as table[] ]]
                expect(#writes).to.equal(transitions * 3)
                local expectedPhases = { "PREMATCH", "PREMATCH", "LIVE", "POSTMATCH", "LOBBY", "PREMATCH", "LOBBY" }
                local expectedEnds = { 1060, 1070, -1, 1085, -1, 1145, -1 }
                for index, group in ipairs(triples(writes)) do
                    for position, key in ipairs(keys) do expect(group[position].key).to.equal(key) end
                    expect(group[1].value).to.equal(expectedEnds[index])
                    expect(group[2].value).to.equal(expectedPhases[index])
                end
            end
        },
        {
            name = "seq increases by exactly one per transition",
            func = function(state)
                installStore(state, true)
                local transitions = runCycle(state)
                for index, group in ipairs(triples(state.writes --[[@as table[] ]])) do
                    expect(group[3].value).to.equal(index)
                end
                expect(PW._Match.seq).to.equal(transitions)
            end
        },
        {
            name = "A rejected transition writes nothing and keeps seq",
            func = function(state)
                installStore(state, true)
                expect(match()._SetPhase("LIVE")).to.beFalse()
                expect(#state.writes).to.equal(0)
                expect(PW._Match.seq).to.equal(0)
            end
        },
        {
            name = "Before server InitPostEntity transitions only count; publishing writes the current state once",
            func = function(state)
                installStore(state, false)
                expect(PW._Match.networked).to.beFalse()
                assert(match().Start(state.mode), "Start failed")
                expect(#state.writes).to.equal(0)
                expect(PW._Match.seq).to.equal(1)
                match()._Publish()
                local writes = state.writes --[[@as table[] ]]
                expect(#writes).to.equal(3)
                for position, key in ipairs(keys) do expect(writes[position].key).to.equal(key) end
                expect(writes[1].value).to.equal(1060)
                expect(writes[2].value).to.equal("PREMATCH")
                expect(writes[3].value).to.equal(1)
                expect(PW._Match.networked).to.beTrue()
            end
        },
        {
            name = "A store that never transitioned publishes LOBBY, no end time, seq 0",
            func = function(state)
                installStore(state, false)
                match()._Publish()
                local writes = state.writes --[[@as table[] ]]
                expect(writes[1].value).to.equal(-1)
                expect(writes[2].value).to.equal("LOBBY")
                expect(writes[3].value).to.equal(0)
            end
        },
        {
            name = "Remaining time: end minus now, never below zero, nil without an end",
            func = function()
                expect(PW.Phase._Remaining(1010, 1004)).to.equal(6)
                expect(PW.Phase._Remaining(1010, 1010)).to.equal(0)
                expect(PW.Phase._Remaining(1010, 1012)).to.equal(0)
                expect(PW.Phase._Remaining(-1, 1000)).to.beNil()
            end
        },
        {
            name = "Client cleanup: leaving LIVE ends instances, every other transition does not",
            func = function()
                for _, from in ipairs(PW.Phase.Names) do
                    for _, to in ipairs(PW.Phase.Names) do
                        local expected = from == "LIVE" and to ~= "LIVE"
                        expect(PW.Phase._EndsInstances(from, to)).to.equal(expected)
                    end
                end
                expect(PW.Phase._EndsInstances(nil, "LIVE")).to.beFalse()
                expect(PW.Phase._EndsInstances(nil, "LOBBY")).to.beFalse()
            end
        },
        {
            name = "Client view: the first sync and every new seq change it; a repeated seq (full update) does not",
            func = function()
                ---@type PW.PhaseView
                local view = {}
                local changed, endInstances = PW.Phase._Apply(view, "LIVE", 3)
                expect(changed).to.beTrue()
                expect(endInstances).to.beFalse()
                expect(view.phase).to.equal("LIVE")
                expect(view.seq).to.equal(3)
                changed, endInstances = PW.Phase._Apply(view, "LIVE", 3)
                expect(changed).to.beFalse()
                expect(endInstances).to.beFalse()
                changed, endInstances = PW.Phase._Apply(view, "POSTMATCH", 4)
                expect(changed).to.beTrue()
                expect(endInstances).to.beTrue()
                changed, endInstances = PW.Phase._Apply(view, "POSTMATCH", 4)
                expect(changed).to.beFalse()
                expect(endInstances).to.beFalse()
                changed, endInstances = PW.Phase._Apply(view, "VOTE", 5)
                expect(changed).to.beTrue()
                expect(endInstances).to.beFalse()
            end
        },
        {
            name = "PW._EndInstances removes every live instance once",
            func = function()
                local unequipped = 0
                local def = { OnUnequip = function() unequipped = unequipped + 1 end }
                local first = PW.Instance(def, "a")
                local second = PW.Instance(def, "b")
                PW._EndInstances()
                expect(first:IsValid()).to.beFalse()
                expect(second:IsValid()).to.beFalse()
                expect(next(PW._Instances.live)).to.beNil()
                expect(unequipped).to.equal(2)
                PW._EndInstances()
                expect(unequipped).to.equal(2)
            end
        }
    }
}
