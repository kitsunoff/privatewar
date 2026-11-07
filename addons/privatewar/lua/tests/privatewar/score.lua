-- T-2.1 score module (TASKS.md, "Mandatory test cases" T-2.1; 06-progression.md d.3). Pure cases over plain
-- player stand-ins (a table with IsValid, Team and SetNW2Int) and an isolated score_events registry; no bots and no
-- real players. Every case swaps in a fresh store, restores PW.ActiveMode, removes its hooks and zeroes the team
-- globals it touched.

local listenerId = "PW_Test_Score"
local hookNames = { "PW_ScoreValue", "PW_ScoreEvent", "PW_ScoreChanged" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.ScoreLib
local function score()
    return must(PW.Score)
end

---A player stand-in: the score module reads IsValid and Team and publishes through SetNW2Int.
---@param team? integer
---@return Player
local function fakePlayer(team)
    ---@type table<string, integer>
    local published = {}
    ---@type table<string, any>
    local fake = { published = published }
    fake.IsValid = function() return true end
    fake.Team = function() return team or 0 end
    ---@param _ any
    ---@param key string
    ---@param value integer
    fake.SetNW2Int = function(_, key, value) published[key] = value end
    return fake --[[@as Player]]
end

---An isolated score_events registry with the given events (id -> EVENT table), released by afterEach.
---@param state table<string, any>
---@param events table<string, table>
---@return PW.Registry
local function registryWith(state, events)
    local registry = PW.Registry.New("score_events", { log = function() end, preRegister = function() end })
    for id, event in pairs(events) do registry.Register(event, id) end
    registry.ResolveAll()
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    return registry
end

---Records every call of a notification hook.
---@param name string
---@param calls table[]
local function record(name, calls)
    hook.Add(name, listenerId, function(...)
        calls[#calls + 1] = { ... }
    end)
end

return {
    groupName = "PW score",
    beforeEach = function(state)
        state.registries = {}
        state.previousStore = PW._Score
        state.previousMode = PW.ActiveMode
        PW.ActiveMode = nil
        PW._Score = score()._NewStore()
    end,
    afterEach = function(state)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        for _, name in ipairs(hookNames) do hook.Remove(name, listenerId) end
        score()._Reset(PW._Score)
        PW._Score = state.previousStore
        PW.ActiveMode = state.previousMode
    end,
    cases = {
        {
            name = "Award adds points and fires PW_ScoreEvent with points, XP and weapon",
            func = function(state)
                local registry = registryWith(state, { kill = { Name = "Kill", Points = 100, XP = 120 } })
                local ply = fakePlayer()
                local weapon = { class = "weapon_smg1" } --[[@as Weapon]]
                ---@type table[]
                local calls = {}
                record("PW_ScoreEvent", calls)

                local ok, points, xp = score()._Award(PW._Score, registry, ply, "kill", { weapon = weapon })

                expect(ok).to.beTrue()
                expect(points).to.equal(100)
                expect(xp).to.equal(120)
                expect(score().Get(ply)).to.equal(100)
                expect(#calls).to.equal(1)
                expect(calls[1][1]).to.equal(ply)
                expect(calls[1][2]).to.equal("kill")
                expect(calls[1][3]).to.equal(100)
                expect(calls[1][4]).to.equal(120)
                expect(calls[1][5]).to.equal(weapon)
                score()._Award(PW._Score, registry, ply, "kill")
                expect(score().Get(ply)).to.equal(200)
                expect(#calls).to.equal(2)
                expect(calls[2][5]).to.beNil()
            end
        },
        {
            name = "PW_ScoreValue overrides the value; XP follows it only when the event has no XP of its own",
            func = function(state)
                local registry = registryWith(state, {
                    plain = { Name = "Plain", Points = 100 },
                    custom = { Name = "Custom", Points = 100, XP = 30 }
                })
                local ply = fakePlayer()
                ---@type table[]
                local asked = {}
                hook.Add("PW_ScoreValue", listenerId, function(who, id, points)
                    asked[#asked + 1] = { who, id, points }
                    return points * 2
                end)
                ---@type table[]
                local events = {}
                record("PW_ScoreEvent", events)

                local _, points, xp = score()._Award(PW._Score, registry, ply, "plain")
                expect(points).to.equal(200)
                expect(xp).to.equal(200)
                expect(score().Get(ply)).to.equal(200)
                expect(asked[1][1]).to.equal(ply)
                expect(asked[1][2]).to.equal("plain")
                expect(asked[1][3]).to.equal(100)
                expect(events[1][3]).to.equal(200)
                expect(events[1][4]).to.equal(200)

                local _, customPoints, customXp = score()._Award(PW._Score, registry, ply, "custom")
                expect(customPoints).to.equal(200)
                expect(customXp).to.equal(30)
                expect(score().Get(ply)).to.equal(400)
            end
        },
        {
            name = "A PW_ScoreValue answer that is not a number keeps the event's points",
            func = function(state)
                local registry = registryWith(state, { kill = { Name = "Kill", Points = 100 } })
                hook.Add("PW_ScoreValue", listenerId, function() return "lots" end)
                local ok, points = score()._Award(PW._Score, registry, fakePlayer(), "kill")
                expect(ok).to.beTrue()
                expect(points).to.equal(100)
            end
        },
        {
            name = "An unknown event id is rejected: false, one log line, no score, no hook",
            func = function(state)
                local registry = registryWith(state, { kill = { Name = "Kill", Points = 100 } })
                local ply = fakePlayer()
                ---@type table[]
                local calls = {}
                record("PW_ScoreEvent", calls)
                record("PW_ScoreChanged", calls)
                ---@type string[]
                local logged = {}
                PW._Score = score()._NewStore(function(message) logged[#logged + 1] = message end)
                local ok = score()._Award(PW._Score, registry, ply, "nonexistent")

                expect(ok).to.beFalse()
                expect(#logged).to.equal(1)
                expect(string.find(logged[1], "nonexistent", 1, true)).to.exist()
                expect(score().Get(ply)).to.equal(0)
                expect(#calls).to.equal(0)
                expect(score()._Award(PW._Score, nil, ply, "kill")).to.beFalse()
                ---@type any
                local notAnId = 5
                expect(score()._Award(PW._Score, registry, ply, notAnId)).to.beFalse()
            end
        },
        {
            name = "A disabled event is rejected",
            func = function(state)
                local registry = registryWith(state, { kill = { Name = "Kill", Points = 100 } })
                registry._Disable("kill", "test")
                local ply = fakePlayer()
                expect(score()._Award(PW._Score, registry, ply, "kill")).to.beFalse()
                expect(score().Get(ply)).to.equal(0)
            end
        },
        {
            name = "Order: the score is added, then PW_ScoreEvent, then PW_ScoreChanged with the final scores",
            func = function(state)
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2 }
                local registry = registryWith(state, { kill = { Name = "Kill", Points = 100 } })
                local ply = fakePlayer(2)
                ---@type string[]
                local order = {}
                ---@type table[]
                local changed = {}
                hook.Add("PW_ScoreEvent", listenerId, function(who)
                    order[#order + 1] = "event:" .. score().Get(who)
                end)
                hook.Add("PW_ScoreChanged", listenerId, function(...)
                    order[#order + 1] = "changed"
                    changed[#changed + 1] = { ... }
                end)

                score()._Award(PW._Score, registry, ply, "kill")
                score()._Award(PW._Score, registry, ply, "kill")

                expect(order).to.deepEqual({ "event:100", "changed", "event:200", "changed" })
                expect(changed[2][1]).to.equal(ply)
                expect(changed[2][2]).to.equal(200)
                expect(changed[2][3]).to.equal(100)
                expect(changed[2][4]).to.equal(2)
                expect(changed[2][5]).to.equal(200)
            end
        },
        {
            name = "Team modes add the points to the player's team; FFA keeps team scores empty",
            func = function(state)
                local registry = registryWith(state, { kill = { Name = "Kill", Points = 100 } })
                local one, two, mate = fakePlayer(1), fakePlayer(2), fakePlayer(1)
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2 }
                score()._Award(PW._Score, registry, one, "kill")
                score()._Award(PW._Score, registry, mate, "kill")
                score()._Award(PW._Score, registry, two, "kill")
                expect(score().GetTeam(1)).to.equal(200)
                expect(score().GetTeam(2)).to.equal(100)
                expect(score().Get(one)).to.equal(100)
                expect(score().GetTeam(3)).to.equal(0)

                PW._Score = score()._NewStore()
                PW.ActiveMode = { ClassName = "test_ffa", Teams = 0 }
                score()._Award(PW._Score, registry, one, "kill")
                expect(score().Get(one)).to.equal(100)
                expect(score().GetTeam(1)).to.equal(0)
                -- A team outside 1..N (a spectator) scores for itself only.
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2 }
                score()._Award(PW._Score, registry, fakePlayer(1001), "kill")
                expect(score().GetTeam(1)).to.equal(0)
            end
        },
        {
            name = "Pure helpers: _Resolve and _Add over plain data",
            func = function()
                local lib = score()
                local plain = { Name = "a", Points = 10 } --[[@as any]]
                local withXp = { Name = "a", Points = 10, XP = 4 } --[[@as any]]
                expect({ lib._Resolve(plain, nil) }).to.deepEqual({ 10, 10 })
                expect({ lib._Resolve(withXp, 50) }).to.deepEqual({ 50, 4 })
                expect({ lib._Resolve(plain, true) }).to.deepEqual({ 10, 10 })
                local store = lib._NewStore()
                local ply = fakePlayer()
                expect({ lib._Add(store, ply, nil, 30) }).to.deepEqual({ 30 })
                expect({ lib._Add(store, ply, 2, -10) }).to.deepEqual({ 20, -10 })
                expect(store.teams[2]).to.equal(-10)
            end
        },
        {
            name = "Scores are published for HUD reading: NW2 on the player, a global per team",
            func = function(state)
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2 }
                local registry = registryWith(state, { kill = { Name = "Kill", Points = 100 } })
                local ply = fakePlayer(2)
                score()._Award(PW._Score, registry, ply, "kill")
                expect((ply --[[@as table]]).published[score()._PlayerKey]).to.equal(100)
                expect(GetGlobal2Int(score()._TeamKey .. 2, 0)).to.equal(100)
            end
        },
        {
            name = "Reset zeroes player and team scores and their published values",
            func = function(state)
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2 }
                local registry = registryWith(state, { kill = { Name = "Kill", Points = 100 } })
                local ply = fakePlayer(1)
                score()._Award(PW._Score, registry, ply, "kill")
                score()._Reset(PW._Score)
                expect(score().Get(ply)).to.equal(0)
                expect(score().GetTeam(1)).to.equal(0)
                expect((ply --[[@as table]]).published[score()._PlayerKey]).to.equal(0)
                expect(GetGlobal2Int(score()._TeamKey .. 1, 0)).to.equal(0)
            end
        },
        {
            name = "The module resets scores when PREMATCH turns into LIVE and when the lobby returns",
            func = function(state)
                local module = must(must(PW.Modules).Get("score"))
                local registry = registryWith(state, { kill = { Name = "Kill", Points = 100 } })
                local ply = fakePlayer()
                score()._Award(PW._Score, registry, ply, "kill")
                module.PW_PhaseChange(module, "PREMATCH", "LOBBY", 0)
                expect(score().Get(ply)).to.equal(100)
                module.PW_PhaseChange(module, "POSTMATCH", "LIVE", 0)
                expect(score().Get(ply)).to.equal(100)
                module.PW_PhaseChange(module, "LIVE", "PREMATCH", 0)
                expect(score().Get(ply)).to.equal(0)
                score()._Award(PW._Score, registry, ply, "kill")
                module.PW_PhaseChange(module, "LOBBY", "POSTMATCH", 0)
                expect(score().Get(ply)).to.equal(0)
            end
        },
        {
            name = "Built-in events: kill is 100 points, headshot is a 50 point medal; both are required-complete",
            func = function()
                local events = must(PW.Registries.score_events)
                local kill = must(events.Get("kill"))
                expect(kill.Points).to.equal(100)
                expect(kill.Medal).to.beFalse()
                local headshot = must(events.Get("headshot"))
                expect(headshot.Points).to.equal(50)
                expect(headshot.Medal).to.beTrue()
                expect(PW.Score.Award).to.beA("function")
            end
        }
    }
}
