-- Dev-only profiler glue (T-10.4; DESIGN.md performance rule 4). Never shipped (T-10.2). Shared.
-- Zero cost while stopped: nothing is wrapped and no sampler hook exists. While running it
--   * wraps every hook.Add callback (re-scanned each second, so hooks added later are caught) with a SysTime timer
--     keyed "<owner>@<event>"; inclusive times (a hook that dispatches another hook includes it);
--   * wraps the tick functions of the bot scheduler (PW._BotSchedulerState) and its FIFO jobs, keyed "sched:<id kind>";
--   * wraps net.Start and the send functions and counts bytes per message (bytes x human recipients);
--   * samples every frame: engine.ServerFrameTime (server), RealFrameTime (client), the interval between frames, the
--     top-level Lua hook time of the frame, Lua memory growth, and the scheduler's last tick (server);
--   * turns pw_profile on (PW.Call timings per entity, 00-core.md d.6) and reports PW.Profile too.
-- Commands (server console, the dev bridge or the listen host):
--   pw_dev_profile start [tag]   start on the server and on the host's client
--   pw_dev_profile stop          stop both and print the reports ("[PW] profile <tag> <realm> ...", logs.sh --once)
-- The client side alone: pw_dev_profile_cl start|stop [tag].

AddCSLuaFile()
AddCSLuaFile("privatewar_dev/profile_stats.lua")

local stats = include("privatewar_dev/profile_stats.lua") --[[@as PWDev.ProfileStats]]

-- Engine functions that may be missing (a listen server has no engine.ServerFrameTime): resolved once, here.
local serverFrameProbe = SERVER and stats.ResolveProbe(engine, "ServerFrameTime") or nil
local clientFrameProbe = CLIENT and stats.ResolveProbe(_G, "RealFrameTime") or nil

local selfPrefix = "PWDev.Profile"
local capacity = 40000
local topHooks, topOwners, topNet = 25, 15, 20

---@class PWDev.ProfileRun
---@field tag string
---@field started number SysTime at start
---@field frames integer
---@field depth integer nesting of wrapped hooks
---@field frameLua number seconds of top-level hook time in the current frame
---@field lastFrame number SysTime of the previous frame sample
---@field lastMem number KB from collectgarbage("count")
---@field allocKB number growth of the Lua heap, summed over frames
---@field hooks table<string, PWDev.ProfileEntry>
---@field net table<string, PWDev.NetEntry>
---@field series table<string, PWDev.ProfileSeries>
---@field schedTicks integer
---@field schedStart table<string, number>

---@type PWDev.ProfileRun?
local run

-- wrapper -> what it replaced; used to skip our own wrappers and to restore the originals
---@type table<function, { event: string, id: any, fn: function }>
local hookWrappers = {}
---@type table<function, { entry: PW.BotSchedulerEntry, fn: fun(id: any, now: number) }>
local schedWrappers = {}
---@type table<string, function>
local netOriginals = {}
---@type function?
local enqueueOriginal
---@type string?
local netCurrent

---@param key string
---@param started number
---@param mem number collectgarbage("count") before the call
---@param depth integer
---@param ... any
---@return any ...
local function finishHook(key, started, mem, depth, ...)
    local elapsed = SysTime() - started
    local current = run
    if current ~= nil then
        current.depth = depth
        stats.AddTime(current.hooks, key, elapsed, collectgarbage("count") - mem)
        if depth == 0 then current.frameLua = current.frameLua + elapsed end
    end
    return ...
end

---@param key string
---@param fn function
---@return function
local function makeHookWrapper(key, fn)
    return function(...)
        local current = run
        local depth = current ~= nil and current.depth or 0
        if current ~= nil then current.depth = depth + 1 end
        return finishHook(key, SysTime(), collectgarbage("count"), depth, fn(...))
    end
end

local function wrapHooks()
    ---@type { event: string, id: any, fn: function }[]
    local pending = {}
    for event, list in pairs(hook.GetTable() --[[@as table<string, table<any, function>>]]) do
        for id, fn in pairs(list) do
            local own = isstring(id) and string.sub(id, 1, #selfPrefix) == selfPrefix
            local usable = isstring(id) or (istable(id) and IsValid(id)) or (isentity(id) and IsValid(id))
            if usable and not own and hookWrappers[fn] == nil and isfunction(fn) then
                pending[#pending + 1] = { event = event, id = id, fn = fn }
            end
        end
    end
    for _, item in ipairs(pending) do
        local wrapper = makeHookWrapper(stats.Key(stats.Owner(item.id), item.event), item.fn)
        hookWrappers[wrapper] = item
        hook.Add(item.event, item.id, wrapper)
    end
end

local function unwrapHooks()
    local hookTable = hook.GetTable() --[[@as table<string, table<any, function>>]]
    for wrapper, item in pairs(hookWrappers) do
        local list = hookTable[item.event]
        if list ~= nil and list[item.id] == wrapper then hook.Add(item.event, item.id, item.fn) end
    end
    hookWrappers = {}
end

---@param key string
---@param fn function
---@return function
local function makeTimed(key, fn)
    return function(...)
        return finishHook(key, SysTime(), collectgarbage("count"), 1, fn(...))
    end
end

---@return PW.BotSchedulerState?
local function schedulerState()
    return PW ~= nil and rawget(PW, "_BotSchedulerState") --[[@as PW.BotSchedulerState?]] or nil
end

local function wrapScheduler()
    local state = schedulerState()
    if state == nil then return end
    for id, entry in pairs(state.entries) do
        if schedWrappers[entry.fn] == nil then
            local wrapper = makeTimed(stats.SchedulerKey(id), entry.fn)
            schedWrappers[wrapper] = { entry = entry, fn = entry.fn }
            entry.fn = wrapper
        end
    end
    local lib = PW.BotScheduler
    if lib ~= nil and lib.Default ~= nil and enqueueOriginal == nil then
        local original = lib.Default.Enqueue
        enqueueOriginal = original
        lib.Default.Enqueue = function(job) original(makeTimed("sched:job", job)) end
    end
end

local function unwrapScheduler()
    for wrapper, item in pairs(schedWrappers) do
        if item.entry.fn == wrapper then item.entry.fn = item.fn end
    end
    schedWrappers = {}
    local lib = PW ~= nil and PW.BotScheduler or nil
    if enqueueOriginal ~= nil and lib ~= nil and lib.Default ~= nil then lib.Default.Enqueue = enqueueOriginal end
    enqueueOriginal = nil
end

---Human recipients of a send target (bots receive no net messages).
---@param target any
---@return integer
local function humans(target)
    if isentity(target) then return (IsValid(target) and target:IsPlayer() and not target:IsBot()) and 1 or 0 end
    ---@type Player[]?
    local list = istable(target) and target --[[@as Player[] ]] or nil
    if not istable(target) and target ~= nil and target.GetPlayers ~= nil then
        list = (target --[[@as CRecipientFilter]]):GetPlayers()
    end
    local count = 0
    if list ~= nil then
        for _, ply in ipairs(list) do
            if IsValid(ply) and not ply:IsBot() then count = count + 1 end
        end
    end
    return count
end

---@param recipients integer
local function account(recipients)
    local current = run
    if current == nil then return end
    local bytes = net.BytesWritten() or 0
    stats.AddNet(current.net, netCurrent or "?", bytes, recipients)
end

local function wrapNet()
    if next(netOriginals) ~= nil then return end
    local o = netOriginals
    o.Start = net.Start
    rawset(net, "Start", function(name, unreliable)
        netCurrent = name
        return o.Start(name, unreliable)
    end)
    if SERVER then
        o.Send, o.Broadcast, o.SendOmit = net.Send, net.Broadcast, net.SendOmit
        o.SendPVS, o.SendPAS = net.SendPVS, net.SendPAS
        rawset(net, "Send", function(target) account(humans(target)); return o.Send(target) end)
        rawset(net, "Broadcast", function() account(#player.GetHumans()); return o.Broadcast() end)
        rawset(net, "SendOmit", function(target)
            account(math.max(0, #player.GetHumans() - humans(target)))
            return o.SendOmit(target)
        end)
        -- PVS/PAS recipients are unknown to Lua: counted as every human (an upper bound).
        rawset(net, "SendPVS", function(pos) account(#player.GetHumans()); return o.SendPVS(pos) end)
        rawset(net, "SendPAS", function(pos) account(#player.GetHumans()); return o.SendPAS(pos) end)
    else
        o.SendToServer = net.SendToServer
        rawset(net, "SendToServer", function() account(1); return o.SendToServer() end)
    end
end

local function unwrapNet()
    for name, fn in pairs(netOriginals) do rawset(net, name, fn) end
    netOriginals = {}
end

---@param current PWDev.ProfileRun
---@param name string
---@param value number
local function sample(current, name, value)
    local series = current.series[name]
    if series == nil then
        series = stats.NewSeries(capacity)
        current.series[name] = series
    end
    stats.Add(series, value)
end

local function onFrame()
    local current = run
    if current == nil then return end
    local now = SysTime()
    current.frames = current.frames + 1
    sample(current, "interval_ms", (now - current.lastFrame) * 1000)
    sample(current, "lua_hooks_ms", current.frameLua * 1000)
    current.lastFrame, current.frameLua, current.depth = now, 0, 0
    local mem = collectgarbage("count")
    if mem > current.lastMem then current.allocKB = current.allocKB + (mem - current.lastMem) end
    current.lastMem = mem
    if SERVER then
        local frameMs = stats.ProbeMs(serverFrameProbe)
        if frameMs ~= nil then sample(current, "server_frame_ms", frameMs) end
        local state = schedulerState()
        if state ~= nil and state.counters.ticks ~= current.schedTicks and state.count > 0 then
            current.schedTicks = state.counters.ticks
            sample(current, "sched_tick_ms", state.counters.lastTickMs)
        end
    else
        local frameMs = stats.ProbeMs(clientFrameProbe)
        if frameMs ~= nil then sample(current, "client_frame_ms", frameMs) end
    end
end

-- A sampler error must never break the Think chain (an erroring hook stops the hooks after it): stop instead.
local function guardedFrame()
    local ok, err = pcall(onFrame)
    if not ok then
        print("[PW] profile: sampler failed, stopping the sampler: " .. tostring(err))
        hook.Remove("Think", selfPrefix .. ".Frame")
    end
end

local function rescan()
    if run == nil then return end
    wrapHooks()
    if SERVER then wrapScheduler() end
end

---@return table<string, number>
local function schedulerCounters()
    local state = schedulerState()
    if state == nil then return {} end
    ---@type table<string, number>
    local copy = {}
    for key, value in pairs(state.counters --[[@as table<string, number>]]) do copy[key] = value end
    copy.bots = state.count
    return copy
end

---@param tag string?
local function start(tag)
    if run ~= nil then
        print("[PW] profile: already running (" .. run.tag .. ")")
        return
    end
    local now = SysTime()
    run = { tag = (tag ~= nil and tag ~= "") and tag or "run", started = now, frames = 0, depth = 0, frameLua = 0,
        lastFrame = now, lastMem = collectgarbage("count"), allocKB = 0, hooks = {}, net = {}, series = {},
        schedTicks = -1, schedStart = schedulerCounters() }
    if PW ~= nil and PW.Profile ~= nil then PW.Profile.Reset() end
    if SERVER then RunConsoleCommand("pw_profile", "1") end
    wrapNet()
    rescan()
    hook.Add("Think", selfPrefix .. ".Frame", guardedFrame)
    timer.Create(selfPrefix .. ".Rescan", 1, 0, rescan)
    print(string.format("[PW] profile %s %s started", run.tag, SERVER and "server" or "client"))
end

---@param current PWDev.ProfileRun
---@return string[]
local function extraLines(current, duration)
    local lines = { string.format("lua_alloc_KB_s=%.1f lua_heap_KB=%.0f", current.allocKB / duration,
        collectgarbage("count")) }
    if SERVER then
        local before, after = current.schedStart, schedulerCounters()
        local function delta(key) return (after[key] or 0) - (before[key] or 0) end
        lines[#lines + 1] = string.format("sched bots=%d budget_ms=%s ticks=%d over_budget=%d stretched=%d runs=%d"
            .. " jobs=%d errors=%d max_tick_ms=%.3f",
            after.bots or 0, tostring(PW.Setting ~= nil and PW.Setting("bots.tickbudget") or "?"), delta("ticks"),
            delta("overBudgetTicks"), delta("stretchedTicks"), delta("brainRuns"), delta("jobsRun"), delta("errors"),
            after.maxTickMs or 0)
        lines[#lines + 1] = string.format("players=%d bots=%d humans=%d", player.GetCount(), #player.GetBots(),
            #player.GetHumans())
    end
    return lines
end

---@param current PWDev.ProfileRun
---@param duration number
local function report(current, duration)
    ---@type PWDev.ReportSeries[]
    local series = {}
    ---@type string[]
    local names = {}
    for name in pairs(current.series) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do series[#series + 1] = { name = name, series = current.series[name] } end
    ---@type table<string, PWDev.ProfileEntry>
    local calls = {}
    if PW ~= nil and PW.Profile ~= nil then
        for key, entry in pairs(PW.Profile.Get()) do
            calls[key] = { time = entry.time, calls = entry.calls, max = 0, alloc = 0 }
        end
    end
    local lines = stats.ReportLines({
        tag = current.tag, realm = SERVER and "server" or "client", duration = duration, frames = current.frames,
        series = series,
        tables = {
            { name = "hook", entries = current.hooks, limit = topHooks },
            { name = "owner", entries = stats.GroupBy(current.hooks), limit = topOwners },
            { name = "alloc", entries = current.hooks, limit = topOwners, by = "alloc" },
            { name = "pwcall", entries = calls, limit = topOwners },
            { name = "net", entries = current.net, limit = topNet, net = true }
        },
        extra = extraLines(current, duration)
    })
    for _, line in ipairs(lines) do print(line) end
end

local function stop()
    local current = run
    if current == nil then
        print("[PW] profile: not running")
        return
    end
    hook.Remove("Think", selfPrefix .. ".Frame")
    timer.Remove(selfPrefix .. ".Rescan")
    unwrapHooks()
    if SERVER then unwrapScheduler() end
    unwrapNet()
    run = nil
    if SERVER then RunConsoleCommand("pw_profile", "0") end
    report(current, SysTime() - current.started)
end

---@param action string?
---@param tag string?
local function command(action, tag)
    if action == "start" then
        start(tag)
    elseif action == "stop" then
        stop()
    else
        print("[PW] profile: usage start [tag] | stop")
    end
end

if SERVER then
    concommand.Add("pw_dev_profile", function(ply, _, args)
        if IsValid(ply) and not ply:IsListenServerHost() then return end
        command(args[1], args[2])
        local host = Entity(1)
        if IsValid(host) and host:IsPlayer() and not (host --[[@as Player]]):IsBot() then
            ---@cast host Player
            host:ConCommand("pw_dev_profile_cl " .. tostring(args[1]) .. " " .. tostring(args[2] or "run"))
        end
    end, nil, "Private War dev: profile hooks, scheduler and net (start [tag] | stop)")
else
    concommand.Add("pw_dev_profile_cl", function(_, _, args) command(args[1], args[2]) end, nil,
        "Private War dev: profile the client (start [tag] | stop)")
end
