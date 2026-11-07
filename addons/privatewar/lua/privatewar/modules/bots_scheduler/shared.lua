-- Bots scheduler (T-5.3; 07-bots.md d.3; DESIGN.md performance rule 1). A pure core over plain data with an
-- injectable clock: every tick runs at most one expensive job from a global FIFO, then the bot tick functions that
-- are due (the most overdue first) until the per-tick millisecond budget is spent. Each bot gets a random phase in
-- its period, so the ticks of many bots spread over the frames instead of landing on one.
--
-- Decisions of the lane agent:
--   1. The budget is the server setting bots.tickbudget (ms, float, default 2, 0.5..10), declared in modules/bots.
--      The default scheduler reads it at most once a second.
--   2. A bot tick is never started when its predicted cost (its own last cost; for a bot not yet measured, the
--      longest cost seen) no longer fits the remaining budget, so a tick stays within the budget unless one bot or job
--      alone is longer. The first due bot of a tick always runs, so a bot longer than the budget still makes progress;
--      the tick is then counted in overBudgetTicks.
--   3. When more bots are due than fit, the rest wait for the next tick, most overdue first. Their period is
--      extended, not their cost: stretchedTicks and maxLateness report it. A bot that is more than one period behind
--      is not "caught up" with a burst: its next due time restarts from now.
--   4. The expensive job runs first and counts in the budget; its time is not predicted. A job that is itself long is
--      expected to slice itself (A* does) and re-enqueue the rest, which then waits one tick.
--   5. A failing bot tick or job is caught with pcall, counted in errors and reported; the others keep running.
--   6. The default scheduler keeps its state in PW._BotSchedulerState, so a reload does not drop the registered bots.

MODULE.Name = "Bots scheduler"

local lib = (rawget(PW, "BotScheduler") or {}) --[[@as PW.BotSchedulerLib]]
PW.BotScheduler = lib

local defaultBudgetMs = 2
local defaultPeriod = 0.1
local clockTolerance = 1e-9 -- seconds: float rounding of a clock difference is not an overrun

---@return PW.BotSchedulerCounters
local function newCounters()
    return { ticks = 0, lastTickMs = 0, maxTickMs = 0, brainRuns = 0, jobsRun = 0, errors = 0, maxLateness = 0,
        deferred = 0, stretchedTicks = 0, overBudgetTicks = 0, bots = 0, queued = 0 }
end

---@return PW.BotSchedulerState
local function newState()
    return { entries = {}, count = 0, seq = 0, jobs = {}, jobHead = 1, jobTail = 0, maxCost = 0,
        counters = newCounters() }
end

---@param opts PW.BotSchedulerOpts
---@return number budget in seconds for this tick
local function budgetSeconds(opts)
    local budget = opts.budget
    if isfunction(budget) then budget = (budget --[[@as fun(): number]])() end
    if not isnumber(budget) or budget ~= budget or budget <= 0 then budget = defaultBudgetMs end
    local ms = budget --[[@as number]]
    return ms / 1000
end

---Runs fn under pcall; on an error counts it and reports it. Returns the seconds it took.
---@param state PW.BotSchedulerState
---@param opts PW.BotSchedulerOpts
---@param clock fun(): number
---@param fn function
---@param ... any
---@return number
local function timed(state, opts, clock, fn, ...)
    local started = clock()
    local ok, err = pcall(fn, ...)
    if not ok then
        state.counters.errors = state.counters.errors + 1
        local onError = opts.onError or ErrorNoHalt
        onError(tostring(err) .. "\n")
    end
    return clock() - started
end

---Runs the head of the FIFO, if any.
---@param state PW.BotSchedulerState
---@param opts PW.BotSchedulerOpts
---@param clock fun(): number
local function runJob(state, opts, clock)
    local job = state.jobs[state.jobHead]
    if job == nil then return end
    state.jobs[state.jobHead] = nil
    state.jobHead = state.jobHead + 1
    state.counters.jobsRun = state.counters.jobsRun + 1
    timed(state, opts, clock, job)
end

---The bots whose tick is due at now, the most overdue first, with their ids.
---@param state PW.BotSchedulerState
---@param now number
---@return PW.BotSchedulerEntry[] due
---@return any[] ids
local function dueList(state, now)
    ---@type PW.BotSchedulerEntry[]
    local due = {}
    ---@type table<PW.BotSchedulerEntry, any>
    local idOf = {}
    for id, entry in pairs(state.entries) do
        if entry.due <= now then
            due[#due + 1] = entry
            idOf[entry] = id
        end
    end
    table.sort(due, function(a, b)
        if a.due ~= b.due then return a.due < b.due end
        return a.seq < b.seq
    end)
    ---@type any[]
    local ids = {}
    for i, entry in ipairs(due) do ids[i] = idOf[entry] end
    return due, ids
end

---Runs one due bot and moves its due time to the next period (decision 3).
---@param state PW.BotSchedulerState
---@param opts PW.BotSchedulerOpts
---@param clock fun(): number
---@param entry PW.BotSchedulerEntry
---@param id any
---@param start number
local function runBot(state, opts, clock, entry, id, start)
    local counters = state.counters
    local lateness = start - entry.due
    if lateness > counters.maxLateness then counters.maxLateness = lateness end
    entry.due = entry.due + entry.period
    if entry.due < start then entry.due = start end
    local cost = timed(state, opts, clock, entry.fn, id, start)
    entry.cost = cost
    if cost > state.maxCost then state.maxCost = cost end
    counters.brainRuns = counters.brainRuns + 1
end

---Runs the due bots while their predicted cost fits the budget; returns how many were left for later.
---@param state PW.BotSchedulerState
---@param opts PW.BotSchedulerOpts
---@param clock fun(): number
---@param start number
---@param budget number seconds
---@return integer deferred
local function runDue(state, opts, clock, start, budget)
    local due, ids = dueList(state, start)
    for i, entry in ipairs(due) do
        local predicted = entry.cost or state.maxCost
        if i > 1 and clock() - start + predicted > budget then return #due - i + 1 end
        runBot(state, opts, clock, entry, ids[i], start)
    end
    return 0
end

---@param state PW.BotSchedulerState
---@param opts PW.BotSchedulerOpts
---@param clock fun(): number
local function tick(state, opts, clock)
    local counters = state.counters
    local start = clock()
    local budget = budgetSeconds(opts)
    runJob(state, opts, clock)
    local deferred = runDue(state, opts, clock, start, budget)
    local elapsed = clock() - start
    counters.ticks = counters.ticks + 1
    counters.lastTickMs = elapsed * 1000
    if counters.lastTickMs > counters.maxTickMs then counters.maxTickMs = counters.lastTickMs end
    counters.deferred = deferred
    if deferred > 0 then counters.stretchedTicks = counters.stretchedTicks + 1 end
    if elapsed > budget + clockTolerance then counters.overBudgetTicks = counters.overBudgetTicks + 1 end
end

---Zeroes the counters except bots and queued, which are computed.
---@param counters PW.BotSchedulerCounters
local function resetCounters(counters)
    counters.ticks, counters.lastTickMs, counters.maxTickMs, counters.brainRuns = 0, 0, 0, 0
    counters.jobsRun, counters.errors, counters.maxLateness, counters.deferred = 0, 0, 0, 0
    counters.stretchedTicks, counters.overBudgetTicks = 0, 0
end

---Creates an independent scheduler.
---@param opts? PW.BotSchedulerOpts
---@return PW.BotScheduler
function lib.New(opts)
    local options = opts or {}
    local clock = options.clock or SysTime
    local random = options.random or math.random
    local state = options.state or newState()
    local entries = state.entries
    local counters = state.counters
    local function register(id, fn, regOpts)
        assert(id ~= nil, "bots_scheduler: Register needs an id")
        assert(isfunction(fn), "bots_scheduler: Register needs a function")
        local period = regOpts ~= nil and regOpts.period or defaultPeriod
        assert(isnumber(period) and period > 0, "bots_scheduler: period must be a positive number")
        local entry = entries[id]
        if entry ~= nil then
            entry.fn, entry.period = fn, period
            return
        end
        local phase = random() * period
        state.seq = state.seq + 1
        state.count = state.count + 1
        entries[id] = { fn = fn, period = period, phase = phase, due = clock() + phase, seq = state.seq }
    end

    local function unregister(id)
        if entries[id] == nil then return false end
        entries[id] = nil
        state.count = state.count - 1
        return true
    end

    local function enqueue(job)
        assert(isfunction(job), "bots_scheduler: Enqueue needs a function")
        state.jobTail = state.jobTail + 1
        state.jobs[state.jobTail] = job
    end

    local function getCounters()
        local copy = table.Copy(counters)
        copy.bots = state.count
        copy.queued = state.jobTail - state.jobHead + 1
        return copy
    end

    local function getPhase(id)
        local entry = entries[id]
        return entry ~= nil and entry.phase or nil
    end

    return {
        Register = register,
        Unregister = unregister,
        Enqueue = enqueue,
        Tick = function() tick(state, options, clock) end,
        GetCounters = getCounters,
        ResetCounters = function() resetCounters(counters) end,
        GetPhase = getPhase
    }
end

local settingRefreshed = -math.huge
local settingMs = defaultBudgetMs

---The budget of the default scheduler: bots.tickbudget, read at most once a second.
---@return number
local function settingBudget()
    local now = SysTime()
    if now - settingRefreshed >= 1 then
        settingRefreshed = now
        local value = PW.Setting("bots.tickbudget")
        settingMs = isnumber(value) and value or defaultBudgetMs
    end
    return settingMs
end

PW._BotSchedulerState = PW._BotSchedulerState or newState()
lib.Default = lib.New({ budget = settingBudget, state = PW._BotSchedulerState })

function lib.Register(id, fn, opts) lib.Default.Register(id, fn, opts) end
function lib.Unregister(id) return lib.Default.Unregister(id) end
function lib.Enqueue(job) lib.Default.Enqueue(job) end
function lib.GetCounters() return lib.Default.GetCounters() end
function lib.ResetCounters() lib.Default.ResetCounters() end
function lib.GetPhase(id) return lib.Default.GetPhase(id) end
