-- Dev-only profiler (T-10.4): the pure aggregation of dev/privatewar_dev/lua/privatewar_dev/profile_stats.lua. The
-- dev addon is always deployed with the tests and never shipped (T-10.2). Only plain data goes in and out: the
-- engine glue (hook and net wrappers, samplers) lives in autorun/pw_profile.lua and is checked by the load test.

---@return PWDev.ProfileStats
local function stats()
    return include("privatewar_dev/profile_stats.lua") --[[@as PWDev.ProfileStats]]
end

---@param list number[]
---@return PWDev.ProfileSeries
local function seriesOf(list)
    local lib = stats()
    local series = lib.NewSeries(#list + 10)
    for _, value in ipairs(list) do lib.Add(series, value) end
    return series
end

return {
    groupName = "PW dev profiler aggregation",
    cases = {
        {
            name = "Percentile uses the nearest rank of a sorted list and 0 for an empty list",
            func = function()
                local lib = stats()
                ---@type number[]
                local sorted = {}
                for i = 1, 100 do sorted[i] = i end
                expect(lib.Percentile(sorted, 50)).to.equal(50)
                expect(lib.Percentile(sorted, 95)).to.equal(95)
                expect(lib.Percentile(sorted, 99)).to.equal(99)
                expect(lib.Percentile(sorted, 100)).to.equal(100)
                expect(lib.Percentile(sorted, 0)).to.equal(1)
                expect(lib.Percentile({ 7 }, 99)).to.equal(7)
                expect(lib.Percentile({}, 95)).to.equal(0)
            end
        },
        {
            name = "Summarize gives count, average, percentiles and maximum without changing the samples",
            func = function()
                local lib = stats()
                local series = seriesOf({ 4, 1, 3, 2 })
                local summary = lib.Summarize(series)
                expect(summary.count).to.equal(4)
                expect(summary.avg).to.equal(2.5)
                expect(summary.p50).to.equal(2)
                expect(summary.p95).to.equal(4)
                expect(summary.max).to.equal(4)
                expect(series.values[1]).to.equal(4)
                local empty = lib.Summarize(lib.NewSeries(8))
                expect(empty.count).to.equal(0)
                expect(empty.avg).to.equal(0)
                expect(empty.max).to.equal(0)
            end
        },
        {
            name = "A full series keeps only the newest samples, and total counts every sample",
            func = function()
                local lib = stats()
                local series = lib.NewSeries(3)
                for value = 1, 5 do lib.Add(series, value) end
                expect(series.count).to.equal(3)
                expect(series.total).to.equal(5)
                local summary = lib.Summarize(series)
                expect(summary.count).to.equal(3)
                expect(summary.avg).to.equal(4)
                expect(summary.max).to.equal(5)
                expect(lib.Percentile({ 3, 4, 5 }, 0)).to.equal(3)
            end
        },
        {
            name = "AddTime accumulates time, calls and the longest call per key",
            func = function()
                local lib = stats()
                ---@type table<string, PWDev.ProfileEntry>
                local entries = {}
                lib.AddTime(entries, "a", 0.002, 1.5)
                lib.AddTime(entries, "a", 0.005, -40)
                lib.AddTime(entries, "b", 0.001)
                local a = entries["a"]
                expect(a.calls).to.equal(2)
                expect(a.alloc).to.equal(1.5)
                expect(entries["b"].alloc).to.equal(0)
                expect(math.abs(a.time - 0.007) < 1e-12).to.beTrue()
                expect(a.max).to.equal(0.005)
                expect(entries["b"].calls).to.equal(1)
            end
        },
        {
            name = "AddNet counts messages, payload once and bytes times recipients",
            func = function()
                local lib = stats()
                ---@type table<string, PWDev.NetEntry>
                local entries = {}
                lib.AddNet(entries, "pw_hud", 10, 3)
                lib.AddNet(entries, "pw_hud", 20, 1)
                lib.AddNet(entries, "pw_none", 8, 0)
                local hud = entries["pw_hud"]
                expect(hud.messages).to.equal(2)
                expect(hud.payload).to.equal(30)
                expect(hud.bytes).to.equal(50)
                expect(hud.sends).to.equal(4)
                expect(entries["pw_none"].bytes).to.equal(0)
                expect(entries["pw_none"].messages).to.equal(1)
            end
        },
        {
            name = "Rank sorts by a field, largest first, ties by key, and honours the limit",
            func = function()
                local lib = stats()
                local entries = {
                    c = { time = 1, calls = 1, max = 1 },
                    a = { time = 3, calls = 1, max = 3 },
                    b = { time = 1, calls = 9, max = 1 }
                }
                local ranked = lib.Rank(entries, "time", 2)
                expect(#ranked).to.equal(2)
                expect(ranked[1].key).to.equal("a")
                expect(ranked[2].key).to.equal("b")
                local byCalls = lib.Rank(entries, "calls")
                expect(#byCalls).to.equal(3)
                expect(byCalls[1].key).to.equal("b")
            end
        },
        {
            name = "GroupBy sums the entries of each owner (the part of the key before the separator)",
            func = function()
                local lib = stats()
                local entries = {}
                lib.AddTime(entries, lib.Key("module:bots_aim", "Tick"), 0.004, 2)
                lib.AddTime(entries, lib.Key("module:bots_aim", "StartCommand"), 0.001, 3)
                lib.AddTime(entries, lib.Key("PW.Match", "Think"), 0.002)
                local owners = lib.GroupBy(entries)
                expect(owners["module:bots_aim"].calls).to.equal(2)
                expect(math.abs(owners["module:bots_aim"].time - 0.005) < 1e-12).to.beTrue()
                expect(owners["module:bots_aim"].max).to.equal(0.004)
                expect(owners["module:bots_aim"].alloc).to.equal(5)
                expect(owners["PW.Match"].calls).to.equal(1)
            end
        },
        {
            name = "Owner names a string id, a registry entity as kind:id and anything else by its type",
            func = function()
                local lib = stats()
                expect(lib.Owner("PW.Match")).to.equal("PW.Match")
                local registry = { Kind = "modules" }
                expect(lib.Owner({ ClassName = "bots_aim", _Registry = registry })).to.equal("modules:bots_aim")
                expect(lib.Owner({ ClassName = "x" })).to.equal("?:x")
                expect(lib.Owner({})).to.equal("table")
                expect(lib.SchedulerKey("brain:12")).to.equal("sched:brain")
                expect(lib.SchedulerKey("follow")).to.equal("sched:follow")
                expect(lib.SchedulerKey(5)).to.equal("sched:number")
            end
        },
        {
            name = "Report lines carry the tag, the frame summary, rates per second and the top entries",
            func = function()
                local lib = stats()
                local hooks = {}
                lib.AddTime(hooks, lib.Key("modules:bots_aim", "Tick"), 0.5, 20)
                lib.AddTime(hooks, lib.Key("modules:hud", "HUDPaint"), 0.1, 300)
                local net = {}
                lib.AddNet(net, "pw_radar", 100, 2)
                local lines = lib.ReportLines({
                    tag = "t1", realm = "server", duration = 10, frames = 660,
                    series = { { name = "frame_ms", series = seriesOf({ 1, 2, 3 }) } },
                    tables = {
                        { name = "hook", entries = hooks, limit = 5 },
                        { name = "alloc", entries = hooks, limit = 1, by = "alloc" },
                        { name = "net", entries = net, limit = 5, net = true }
                    },
                    extra = { "sched budget_ms=2" }
                })
                local text = table.concat(lines, "\n")
                expect(string.find(text, "profile t1 server duration_s=10.0 frames=660", 1, true) ~= nil).to.beTrue()
                expect(string.find(text, "frame_ms n=3 avg=2.000", 1, true) ~= nil).to.beTrue()
                expect(string.find(text, "hook #1 modules:bots_aim@Tick ms_s=50.000", 1, true) ~= nil).to.beTrue()
                expect(string.find(text, "KB_s=2.0", 1, true) ~= nil).to.beTrue()
                expect(string.find(text, "alloc #1 modules:hud@HUDPaint", 1, true) ~= nil).to.beTrue()
                expect(string.find(text, "alloc #2", 1, true) == nil).to.beTrue()
                expect(string.find(text, "pw_radar msg_s=0.10 B_s=20.0", 1, true) ~= nil).to.beTrue()
                expect(string.find(text, "sched budget_ms=2", 1, true) ~= nil).to.beTrue()
                for _, line in ipairs(lines) do
                    expect(string.sub(line, 1, 5)).to.equal("[PW] ")
                end
            end
        },
        {
            name = "A missing engine probe (engine.ServerFrameTime) resolves to nil and the sampler skips it",
            func = function()
                local lib = stats()
                local fakeEngine = {}
                local probe = lib.ResolveProbe(fakeEngine, "ServerFrameTime")
                expect(probe).to.beNil()
                local ok, ms = pcall(lib.ProbeMs, probe)
                expect(ok).to.beTrue()
                expect(ms).to.beNil()
                local real = rawget(engine, "ServerFrameTime")
                rawset(engine, "ServerFrameTime", nil)
                local resolved = lib.ResolveProbe(engine, "ServerFrameTime")
                rawset(engine, "ServerFrameTime", real)
                expect(resolved).to.beNil()
            end
        },
        {
            name = "A present engine probe is reported in milliseconds; a non-function value is ignored",
            func = function()
                local lib = stats()
                local probe = lib.ResolveProbe({ ServerFrameTime = function() return 0.004 end }, "ServerFrameTime")
                expect(probe).toNot.beNil()
                expect(lib.ProbeMs(probe)).to.equal(4)
                expect(lib.ResolveProbe({ ServerFrameTime = 5 }, "ServerFrameTime")).to.beNil()
            end
        }
    }
}
