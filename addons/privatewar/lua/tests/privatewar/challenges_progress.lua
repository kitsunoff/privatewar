---@return PW.ChallengesLib
local function challenges()
    local lib = PW.Challenges
    assert(lib ~= nil)
    return lib
end

---@param fields table<string, any>[]
---@param needed? integer
---@param rounds? boolean
---@return PW.ChallengeProgressPlan?
local function weekly(fields, needed, rounds)
    local lib = challenges()
    if lib._ProgressPlan == nil then return nil end
    ---@type PW.ChallengeInstance[]
    local items = {}
    ---@type table<string, PW.ChallengeTemplate>
    local templates = {}
    for i, def in ipairs(fields) do
        def.Name, def.Description = "Test", "Test challenge"
        local id = "test_" .. i
        local template = lib._Compile(id, def)
        assert(template ~= nil)
        ---@type integer[]
        local targets = {}
        for n, obj in ipairs(template.objectives) do targets[n] = obj.targets.easy end
        templates[id] = template
        items[i] = { id = id, template = id, tier = "easy", params = {}, targets = targets, reward = {} }
    end
    local startsAt, endsAt = lib.WeekBounds(2967)
    return lib._ProgressPlan({ index = 2967, label = "2026-W47", items = items,
        startsAt = startsAt, endsAt = endsAt, seed = 0,
        bonus = { needed = needed or 0, reward = {} } }, templates, rounds == true)
end

---@param plan PW.ChallengeProgressPlan
---@param state PW.ChallengeProgressState
---@param kind string
---@param facts? { time?: number, value?: number, headshot?: boolean }
---@return PW.ChallengeAdvance
local function advance(plan, state, kind, facts)
    local input = facts or {}
    ---@type PW.ChallengeEvent
    local ev = { type = kind, value = input.value or 1, time = input.time or 0, headshot = input.headshot,
        player = NULL --[[@as Player]], mode = "tdm", modeBase = {}, playlist = "", match = 1, week = plan.index }
    return challenges()._AdvanceProgress(plan, state, ev)
end

---@param plan PW.ChallengeProgressPlan
---@param state PW.ChallengeProgressState
---@param slot? integer
---@return PW.ChallengeProgress, PW.ChallengeFileItem
local function counts(plan, state, slot)
    local id = "test_" .. (slot or 1)
    local lib = challenges()
    local progress = lib._ReadProgress(plan, state, id)
    assert(progress ~= nil)
    return progress, lib._SaveProgress(plan, state).items[id]
end

return {
    groupName = "PW challenges progress",
    cases = {
        {
            name = "Scope: cumulative counts across matches",
            func = function()
                local plan = weekly({ { Event = "kill", Target = 3 } })
                expect(type(plan)).to.equal("table")
                assert(plan ~= nil)
                local lib = challenges()
                local state = lib._NewProgress(plan)
                lib._ResetProgress(plan, state, "match_start")
                advance(plan, state, "kill")
                lib._ResetProgress(plan, state, "match_end")
                lib._ResetProgress(plan, state, "match_start")
                advance(plan, state, "kill")
                local run, saved = counts(plan, state)
                expect(run.values[1]).to.equal(2)
                expect(saved.p[1]).to.equal(2)
                expect(run.done).to.beFalse()
            end
        },
        {
            name = "Scope: match resets at match start and keeps the best run",
            func = function()
                local plan = weekly({ { Event = "kill", Scope = "match", Target = 3 } })
                expect(type(plan)).to.equal("table")
                assert(plan ~= nil)
                local lib = challenges()
                local state = lib._NewProgress(plan)
                lib._ResetProgress(plan, state, "match_start")
                advance(plan, state, "kill")
                advance(plan, state, "kill")
                lib._ResetProgress(plan, state, "match_end")
                local ended = counts(plan, state)
                expect(ended.values[1]).to.equal(2)
                lib._ResetProgress(plan, state, "match_start")
                advance(plan, state, "kill")
                local run, saved = counts(plan, state)
                expect(run.values[1]).to.equal(1)
                expect(saved.p[1]).to.equal(2)
                expect(run.done).to.beFalse()
            end
        },
        {
            name = "Scope: round resets at round start and acts as match without rounds",
            func = function()
                for _, rounds in ipairs({ true, false }) do
                    local plan = weekly({ { Event = "kill", Scope = "round", Target = 3 } }, 0, rounds)
                    expect(type(plan)).to.equal("table")
                    assert(plan ~= nil)
                    local lib = challenges()
                    local state = lib._NewProgress(plan)
                    lib._ResetProgress(plan, state, "match_start")
                    lib._ResetProgress(plan, state, "round_start")
                    advance(plan, state, "kill")
                    lib._ResetProgress(plan, state, "round_start")
                    local run, saved = counts(plan, state)
                    expect(run.values[1]).to.equal(rounds and 0 or 1)
                    expect(saved.p[1]).to.equal(1)
                    lib._ResetProgress(plan, state, "match_start")
                    local again = counts(plan, state)
                    expect(again.values[1]).to.equal(rounds and 1 or 0)
                end
            end
        },
        {
            name = "Scope: life resets on death and team change and keeps the best run",
            func = function()
                local plan = weekly({ { Event = "kill", Scope = "life", Target = 5 } })
                expect(type(plan)).to.equal("table")
                assert(plan ~= nil)
                local lib = challenges()
                local state = lib._NewProgress(plan)
                lib._ResetProgress(plan, state, "match_start")
                ---@type PW.ChallengeProgressBoundary[]
                local boundaries = { "death", "team_change", "spawn" }
                for _, reset in ipairs(boundaries) do
                    advance(plan, state, "kill")
                    advance(plan, state, "kill")
                    lib._ResetProgress(plan, state, reset)
                    local run, saved = counts(plan, state)
                    expect(run.values[1]).to.equal(0)
                    expect(saved.p[1]).to.equal(2)
                end
            end
        },
        {
            name = "Within: count events inside the window add one and the window clears",
            func = function()
                local plan = weekly({ { Event = "kill", Scope = "life", Target = 3,
                    Within = { count = 2, seconds = 5 } } })
                expect(type(plan)).to.equal("table")
                assert(plan ~= nil)
                local lib = challenges()
                local state = lib._NewProgress(plan)
                lib._ResetProgress(plan, state, "spawn")
                for _, t in ipairs({ 0, 6, 11, 12 }) do advance(plan, state, "kill", { time = t }) end
                local run = counts(plan, state)
                expect(run.values[1]).to.equal(1)
                lib._ResetProgress(plan, state, "death")
                advance(plan, state, "kill", { time = 13 })
                run = counts(plan, state)
                expect(run.values[1]).to.equal(0)
                advance(plan, state, "kill", { time = 14 })
                run = counts(plan, state)
                expect(run.values[1]).to.equal(1)
            end
        },
        {
            name = "ResetOn: a matching event resets the run; a completed challenge never regresses",
            func = function()
                local plan = weekly({ { Event = "kill", Target = 2,
                    ResetOn = { { Event = "kill", Filters = { headshot = false } }, { Event = "death" } } } })
                expect(type(plan)).to.equal("table")
                assert(plan ~= nil)
                local state = challenges()._NewProgress(plan)
                advance(plan, state, "kill", { headshot = true })
                advance(plan, state, "death")
                local run = counts(plan, state)
                expect(run.values[1]).to.equal(0)
                advance(plan, state, "kill", { headshot = true })
                advance(plan, state, "kill", { headshot = false })
                run = counts(plan, state)
                expect(run.values[1]).to.equal(1)
                advance(plan, state, "kill", { headshot = true })
                advance(plan, state, "death")
                run = counts(plan, state)
                expect(run.values[1]).to.equal(2)
                expect(run.done).to.beTrue()
            end
        },
        {
            name = "Objectives: all and any combinations complete correctly",
            func = function()
                local objectives = {
                    { Event = "kill", Target = 1, ResetOn = { { Event = "death" } } },
                    { Event = "objective", Target = 2 }
                }
                local plan = weekly({ { Objectives = objectives }, { Objectives = objectives, Mode = "any" } })
                expect(type(plan)).to.equal("table")
                assert(plan ~= nil)
                local state = challenges()._NewProgress(plan)
                advance(plan, state, "kill")
                advance(plan, state, "death")
                local all = counts(plan, state)
                local any = counts(plan, state, 2)
                expect(all.done).to.beFalse()
                expect(all.values[1]).to.equal(1)
                expect(any.done).to.beTrue()
                advance(plan, state, "objective")
                advance(plan, state, "objective")
                all = counts(plan, state)
                any = counts(plan, state, 2)
                expect(all.done).to.beTrue()
                expect(any.values[2]).to.equal(0)
            end
        },
        {
            name = "Count: value adds ev.value",
            func = function()
                local plan = weekly({ { Event = "time_played", Count = "value", Target = 5 } })
                expect(type(plan)).to.equal("table")
                assert(plan ~= nil)
                local state = challenges()._NewProgress(plan)
                advance(plan, state, "time_played", { value = 0.6 })
                advance(plan, state, "time_played", { value = 1.6 })
                local run = counts(plan, state)
                expect(run.values[1]).to.equal(2)
                advance(plan, state, "time_played", { value = -3 })
                advance(plan, state, "time_played", { value = math.huge })
                run = counts(plan, state)
                expect(run.values[1]).to.equal(2)
                advance(plan, state, "time_played", { value = 60 })
                run = counts(plan, state)
                expect(run.values[1]).to.equal(5)
                expect(run.done).to.beTrue()
            end
        },
        {
            name = "Completion fires once per player, instance and week",
            func = function()
                local plan = weekly({ { Event = "kill", Target = 1 }, { Event = "objective", Target = 1 } })
                expect(type(plan)).to.equal("table")
                assert(plan ~= nil)
                local lib = challenges()
                local first = lib._NewProgress(plan)
                local second = lib._NewProgress(plan)
                expect(advance(plan, first, "kill").completed[1]).to.equal("test_1")
                expect(#advance(plan, first, "kill").completed).to.equal(0)
                expect(advance(plan, first, "objective").completed[1]).to.equal("test_2")
                expect(advance(plan, second, "kill").completed[1]).to.equal("test_1")
                local saved = lib._SaveProgress(plan, first)
                local reloaded = lib._NewProgress(plan, saved)
                expect(#advance(plan, reloaded, "kill").completed).to.equal(0)
                local nextWeek = weekly({ { Event = "kill", Target = 1 } })
                assert(nextWeek ~= nil)
                nextWeek.index = plan.index + 1
                expect(advance(nextWeek, lib._NewProgress(nextWeek, saved), "kill").completed[1]).to.equal("test_1")
            end
        },
        {
            name = "Bonus: the weekly bonus completes after bonusneeded completions and only once",
            func = function()
                local plan = weekly({ { Event = "kill", Target = 1 }, { Event = "objective", Target = 1 } }, 2)
                expect(type(plan)).to.equal("table")
                assert(plan ~= nil)
                local lib = challenges()
                local state = lib._NewProgress(plan)
                expect(advance(plan, state, "kill").bonus).to.beFalse()
                expect(advance(plan, state, "objective").bonus).to.beTrue()
                expect(advance(plan, state, "objective").bonus).to.beFalse()
                expect(lib._SaveProgress(plan, state).bonus).to.beTrue()
                local disabled = weekly({ { Event = "kill", Target = 1 } }, 0)
                assert(disabled ~= nil)
                expect(advance(disabled, lib._NewProgress(disabled), "kill").bonus).to.beFalse()
            end
        }
    }
}
