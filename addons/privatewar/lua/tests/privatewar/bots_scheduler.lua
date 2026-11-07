-- T-5.3 bot scheduler (07-bots.md d.3): per-tick ms budget, random phase, global FIFO, perf counters. Pure cases over
-- plain data with an injected fake clock; no real bots. A fake bot's tick function advances the fake clock by its cost.

local epsilon = 1e-9

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotSchedulerLib
local function lib()
    return must(PW.BotScheduler)
end

---A fake clock in seconds.
---@return { t: number }
local function newClock()
    return { t = 0 }
end

---A deterministic random generator: a repeating sequence in [0, 1).
---@param values number[]
---@return fun(): number
local function sequence(values)
    local index = 0
    return function()
        index = index % #values + 1
        return values[index]
    end
end

---A scheduler with a fake clock, the given budget in ms and a deterministic spread of phases.
---@param clock { t: number }
---@param budget number
---@return PW.BotScheduler
local function newScheduler(clock, budget)
    ---@type number[]
    local values = {}
    for i = 0, 23 do values[#values + 1] = ((i * 7) % 24) / 24 end
    return lib().New({ clock = function() return clock.t end, budget = budget, random = sequence(values) })
end

---Registers count fake bots; the tick of bot i costs costs[i] ms of fake time. Returns the run log per bot.
---@param sched PW.BotScheduler
---@param clock { t: number }
---@param count integer
---@param costMs fun(i: integer): number
---@param period? number
---@return table<integer, number[]>
local function addBots(sched, clock, count, costMs, period)
    ---@type table<integer, number[]>
    local runs = {}
    for i = 1, count do
        runs[i] = {}
        sched.Register(i, function()
            runs[i][#runs[i] + 1] = clock.t
            clock.t = clock.t + costMs(i) / 1000
        end, { period = period })
    end
    return runs
end

---Advances the fake clock by dt and runs one scheduler tick, ticks times.
---@param sched PW.BotScheduler
---@param clock { t: number }
---@param ticks integer
---@param dt number
local function simulate(sched, clock, ticks, dt)
    for _ = 1, ticks do
        clock.t = clock.t + dt
        sched.Tick()
    end
end

return {
    groupName = "PW bots scheduler",
    cases = {
        {
            name = "Budget: it never exceeds the per-tick budget with 24 fake bots",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                addBots(sched, clock, 24, function(i) return 0.2 + (i % 5) * 0.1 end)
                simulate(sched, clock, 300, 0.015)
                local counters = sched.GetCounters()
                expect(counters.ticks).to.equal(300)
                expect(counters.brainRuns > 0).to.beTrue()
                expect(counters.maxTickMs <= 2 + epsilon).to.beTrue()
                expect(counters.overBudgetTicks).to.equal(0)
            end
        },
        {
            name = "Budget: a heavy load runs fewer bots per tick, extends the period and reports it",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                local runs = addBots(sched, clock, 24, function() return 1 end)
                simulate(sched, clock, 300, 0.015)
                local counters = sched.GetCounters()
                expect(counters.maxTickMs <= 2 + epsilon).to.beTrue()
                expect(counters.deferred > 0).to.beTrue()
                expect(counters.maxLateness > 0.1).to.beTrue()
                expect(counters.stretchedTicks > 0).to.beTrue()
                for i = 1, 24 do expect(#runs[i] > 0).to.beTrue() end
            end
        },
        {
            name = "Budget: one bot above the budget still runs (progress) and the tick is reported over budget",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                local runs = addBots(sched, clock, 1, function() return 5 end)
                simulate(sched, clock, 20, 0.015)
                expect(#runs[1] > 0).to.beTrue()
                expect(sched.GetCounters().overBudgetTicks > 0).to.beTrue()
            end
        },
        {
            name = "Period: every bot gets its brain tick within the expected period",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                local runs = addBots(sched, clock, 24, function() return 0.05 end)
                local period, dt = 0.1, 0.015
                simulate(sched, clock, 400, dt)
                for i = 1, 24 do
                    local log = runs[i]
                    expect(#log >= 50).to.beTrue()
                    expect(log[1] <= period + dt + epsilon).to.beTrue()
                    for k = 2, #log do
                        expect(log[k] - log[k - 1] <= period + dt + epsilon).to.beTrue()
                        expect(log[k] - log[k - 1] >= period - dt - epsilon).to.beTrue()
                    end
                end
                expect(sched.GetCounters().stretchedTicks).to.equal(0)
            end
        },
        {
            name = "Period: a bot with its own period runs at that rate",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                local count = 0
                sched.Register("fast", function() count = count + 1 end, { period = 0.02 })
                simulate(sched, clock, 100, 0.01)
                expect(count >= 45 and count <= 55).to.beTrue()
            end
        },
        {
            name = "Phase: each bot gets a random offset inside its period, so the ticks spread out",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                addBots(sched, clock, 24, function() return 0 end)
                ---@type table<integer, boolean>
                local seen = {}
                local distinct = 0
                for i = 1, 24 do
                    local phase = must(sched.GetPhase(i))
                    expect(phase >= 0 and phase < 0.1).to.beTrue()
                    local key = math.floor(phase * 1000 + 0.5)
                    if not seen[key] then seen[key] = true distinct = distinct + 1 end
                end
                expect(distinct).to.equal(24)
            end
        },
        {
            name = "Phase: the default random generator stays inside the period",
            func = function()
                local sched = lib().New({ budget = 2 })
                for i = 1, 50 do
                    sched.Register(i, function() end, { period = 0.1 })
                    local phase = must(sched.GetPhase(i))
                    expect(phase >= 0 and phase < 0.1).to.beTrue()
                end
            end
        },
        {
            name = "FIFO: the queue runs one expensive job per tick, in the order they were enqueued",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                ---@type integer[]
                local order = {}
                for i = 1, 5 do sched.Enqueue(function() order[#order + 1] = i end) end
                expect(sched.GetCounters().queued).to.equal(5)
                for tick = 1, 5 do
                    simulate(sched, clock, 1, 0.015)
                    expect(#order).to.equal(tick)
                    expect(order[tick]).to.equal(tick)
                end
                simulate(sched, clock, 3, 0.015)
                expect(#order).to.equal(5)
                local counters = sched.GetCounters()
                expect(counters.jobsRun).to.equal(5)
                expect(counters.queued).to.equal(0)
            end
        },
        {
            name = "FIFO: a job enqueued by a job waits for the next tick",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                ---@type string[]
                local ran = {}
                sched.Enqueue(function()
                    ran[#ran + 1] = "outer"
                    sched.Enqueue(function() ran[#ran + 1] = "inner" end)
                end)
                simulate(sched, clock, 1, 0.015)
                expect(#ran).to.equal(1)
                simulate(sched, clock, 1, 0.015)
                expect(table.concat(ran, ",")).to.equal("outer,inner")
            end
        },
        {
            name = "FIFO: jobs do not starve the bots and the budget holds with a job per tick",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                local runs = addBots(sched, clock, 24, function() return 0.05 end)
                for _ = 1, 100 do
                    sched.Enqueue(function() clock.t = clock.t + 0.0005 end)
                end
                simulate(sched, clock, 200, 0.015)
                local counters = sched.GetCounters()
                expect(counters.jobsRun).to.equal(100)
                expect(counters.maxTickMs <= 2 + epsilon).to.beTrue()
                for i = 1, 24 do expect(#runs[i] >= 25).to.beTrue() end
            end
        },
        {
            name = "Counters: time per tick, jobs run and the maximum lateness are reported and reset",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                addBots(sched, clock, 4, function() return 0.25 end)
                sched.Enqueue(function() clock.t = clock.t + 0.0003 end)
                simulate(sched, clock, 20, 0.015)
                local counters = sched.GetCounters()
                expect(counters.bots).to.equal(4)
                expect(counters.ticks).to.equal(20)
                expect(counters.jobsRun).to.equal(1)
                expect(counters.brainRuns > 0).to.beTrue()
                expect(counters.lastTickMs >= 0).to.beTrue()
                expect(counters.maxTickMs >= counters.lastTickMs).to.beTrue()
                expect(counters.maxLateness >= 0).to.beTrue()
                sched.ResetCounters()
                local reset = sched.GetCounters()
                expect(reset.ticks).to.equal(0)
                expect(reset.brainRuns).to.equal(0)
                expect(reset.jobsRun).to.equal(0)
                expect(reset.bots).to.equal(4)
            end
        },
        {
            name = "Register: an unregistered bot stops running, a re-registered id replaces its function",
            func = function()
                local clock = newClock()
                local sched = newScheduler(clock, 2)
                local first, second = 0, 0
                sched.Register("a", function() first = first + 1 end)
                simulate(sched, clock, 20, 0.015)
                expect(first > 0).to.beTrue()
                sched.Register("a", function() second = second + 1 end)
                local before = first
                simulate(sched, clock, 20, 0.015)
                expect(first).to.equal(before)
                expect(second > 0).to.beTrue()
                expect(sched.Unregister("a")).to.beTrue()
                expect(sched.Unregister("a")).to.beFalse()
                local frozen = second
                simulate(sched, clock, 20, 0.015)
                expect(second).to.equal(frozen)
                expect(sched.GetCounters().bots).to.equal(0)
            end
        },
        {
            name = "Errors: a failing bot or job is counted and does not stop the others",
            func = function()
                local clock = newClock()
                local sched = lib().New({ clock = function() return clock.t end, budget = 2,
                    onError = function() end })
                local good = 0
                sched.Register("bad", function() error("boom") end)
                sched.Register("good", function() good = good + 1 end)
                sched.Enqueue(function() error("boom") end)
                simulate(sched, clock, 30, 0.015)
                expect(good > 0).to.beTrue()
                expect(sched.GetCounters().errors > 0).to.beTrue()
                expect(sched.GetCounters().jobsRun).to.equal(1)
            end
        },
        {
            name = "Budget: a function budget is read every tick",
            func = function()
                local clock = newClock()
                local budget = 2
                local sched = lib().New({ clock = function() return clock.t end,
                    budget = function() return budget end })
                addBots(sched, clock, 24, function() return 0.5 end)
                simulate(sched, clock, 100, 0.015)
                expect(sched.GetCounters().maxTickMs <= 2 + epsilon).to.beTrue()
                budget = 0.6
                sched.ResetCounters()
                simulate(sched, clock, 100, 0.015)
                expect(sched.GetCounters().maxTickMs <= 0.6 + epsilon).to.beTrue()
            end
        },
        {
            name = "Setting: bots.tickbudget is a server float, default 2",
            func = function()
                expect(PW.Setting("bots.tickbudget")).to.equal(2)
                local group = must(PW.Settings.GetGroups("server")[1])
                ---@type PW.SettingDef?
                local found
                for _, g in ipairs(PW.Settings.GetGroups("server")) do
                    if g.owner == "bots" then group = g end
                end
                for _, field in ipairs(group.fields) do
                    if field.def.key == "tickbudget" then found = field.def end
                end
                expect(found).to.exist()
                expect(must(found).type).to.equal("float")
                expect(must(found).min).to.equal(0.5)
                expect(must(found).max).to.equal(10)
            end
        },
        {
            name = "Module: the default scheduler is on PW.BotScheduler and the Think hook ticks it",
            func = function()
                local sched = must(lib().Default)
                local module = must(must(PW.Modules).Get("bots_scheduler")) --[[@as PW.Module]]
                local think = (hook.GetTable() --[[@as table<string, table<any, function>>]])["Think"][module]
                expect(think).to.exist()
                local before = sched.GetCounters().ticks
                think(module)
                expect(sched.GetCounters().ticks).to.equal(before + 1)
            end
        }
    }
}
