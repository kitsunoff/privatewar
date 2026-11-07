-- Dev-only profiler, pure aggregation (T-10.4; DESIGN.md performance rule 4, 00-core.md d.6). Never shipped (T-10.2).
-- Plain data in, plain data out: sample series (a ring buffer with percentiles), time entries per key (hook and
-- scheduler timings), net entries per message, ranking, grouping by owner and the report lines. The engine glue
-- (wrappers and samplers) is autorun/pw_profile.lua; the tests are lua/tests/privatewar/dev_profile.lua.
-- Shared and returned by include(): no global.

---@class PWDev.ProfileSeries
---@field values number[] ring buffer of the newest samples
---@field size integer capacity
---@field count integer samples stored (at most size)
---@field nextIndex integer slot of the next sample
---@field total integer samples ever added

---@class PWDev.ProfileSummary
---@field count integer
---@field avg number
---@field p50 number
---@field p95 number
---@field p99 number
---@field max number

---@class PWDev.ProfileEntry
---@field time number seconds in total
---@field calls integer
---@field max number seconds of the longest call
---@field alloc number KB the Lua heap grew during the calls (growth only; a GC step inside a call hides some)

---@class PWDev.NetEntry
---@field messages integer messages started and sent
---@field payload integer bytes of the messages, once each
---@field bytes integer bytes times recipients (what leaves the server)
---@field sends integer recipients in total

---@class PWDev.ProfileRanked
---@field key string
---@field entry table

---@class PWDev.ReportSeries
---@field name string
---@field series PWDev.ProfileSeries

---@class PWDev.ReportTable
---@field name string
---@field entries table<string, table>
---@field limit integer
---@field net? boolean net entries (PWDev.NetEntry) instead of time entries
---@field by? string the field to rank by, default "time" (or "bytes" for net)

---@class PWDev.Report
---@field tag string
---@field realm string
---@field duration number seconds
---@field frames integer
---@field series PWDev.ReportSeries[]
---@field tables PWDev.ReportTable[]
---@field extra? string[] lines added as they are

---@class PWDev.ProfileStats
local lib = {}

lib.Separator = "@"

---@param capacity integer
---@return PWDev.ProfileSeries
function lib.NewSeries(capacity)
    return { values = {}, size = math.max(1, capacity), count = 0, nextIndex = 1, total = 0 }
end

---@param series PWDev.ProfileSeries
---@param value number
function lib.Add(series, value)
    series.values[series.nextIndex] = value
    series.nextIndex = series.nextIndex % series.size + 1
    if series.count < series.size then series.count = series.count + 1 end
    series.total = series.total + 1
end

---Nearest-rank percentile of an ascending list; 0 for an empty list.
---@param sorted number[]
---@param p number 0..100
---@return number
function lib.Percentile(sorted, p)
    local n = #sorted
    if n == 0 then return 0 end
    local rank = math.ceil(p / 100 * n)
    return sorted[math.min(n, math.max(1, rank))]
end

---@param series PWDev.ProfileSeries
---@return PWDev.ProfileSummary
function lib.Summarize(series)
    ---@type number[]
    local sorted = {}
    local sum = 0
    for i = 1, series.count do
        local value = series.values[i]
        sorted[i] = value
        sum = sum + value
    end
    table.sort(sorted)
    local n = #sorted
    return {
        count = n,
        avg = n > 0 and sum / n or 0,
        p50 = lib.Percentile(sorted, 50),
        p95 = lib.Percentile(sorted, 95),
        p99 = lib.Percentile(sorted, 99),
        max = sorted[n] or 0
    }
end

---@param entries table<string, PWDev.ProfileEntry>
---@param key string
---@param seconds number
---@param kb? number heap growth during the call; a negative value (a GC step) counts as 0
function lib.AddTime(entries, key, seconds, kb)
    local entry = entries[key]
    if entry == nil then
        entry = { time = 0, calls = 0, max = 0, alloc = 0 }
        entries[key] = entry
    end
    entry.time = entry.time + seconds
    entry.calls = entry.calls + 1
    if seconds > entry.max then entry.max = seconds end
    if kb ~= nil and kb > 0 then entry.alloc = entry.alloc + kb end
end

---@param entries table<string, PWDev.NetEntry>
---@param name string
---@param bytes integer
---@param recipients integer
function lib.AddNet(entries, name, bytes, recipients)
    local entry = entries[name]
    if entry == nil then
        entry = { messages = 0, payload = 0, bytes = 0, sends = 0 }
        entries[name] = entry
    end
    entry.messages = entry.messages + 1
    entry.payload = entry.payload + bytes
    entry.bytes = entry.bytes + bytes * recipients
    entry.sends = entry.sends + recipients
end

---Entries sorted by a numeric field, largest first, ties by key.
---@param entries table<string, table>
---@param field string
---@param limit? integer
---@return PWDev.ProfileRanked[]
function lib.Rank(entries, field, limit)
    ---@type PWDev.ProfileRanked[]
    local list = {}
    for key, entry in pairs(entries) do list[#list + 1] = { key = key, entry = entry } end
    table.sort(list, function(a, b)
        local x, y = a.entry[field] or 0, b.entry[field] or 0
        if x ~= y then return x > y end
        return a.key < b.key
    end)
    if limit ~= nil then
        for i = #list, limit + 1, -1 do list[i] = nil end
    end
    return list
end

-- An engine function that may be missing in this realm or on a listen server (engine.ServerFrameTime,
-- RealFrameTime). Resolve it once at file load; nil means "not available": fall back to the other measures.
---@param holder table
---@param name string
---@return (fun(): number)?
function lib.ResolveProbe(holder, name)
    local probe = rawget(holder, name)
    if type(probe) == "function" then return probe end
    return nil
end

---@param probe (fun(): number)?
---@return number? milliseconds, nil when the probe is missing
function lib.ProbeMs(probe)
    if probe == nil then return nil end
    return probe() * 1000
end

---@param owner string
---@param event string
---@return string
function lib.Key(owner, event)
    return owner .. lib.Separator .. event
end

---Time entries summed per owner (the key up to the separator).
---@param entries table<string, PWDev.ProfileEntry>
---@return table<string, PWDev.ProfileEntry>
function lib.GroupBy(entries)
    ---@type table<string, PWDev.ProfileEntry>
    local owners = {}
    for key, entry in pairs(entries) do
        local owner = string.match(key, "^(.-)" .. lib.Separator) or key
        local sum = owners[owner]
        if sum == nil then
            sum = { time = 0, calls = 0, max = 0, alloc = 0 }
            owners[owner] = sum
        end
        sum.time = sum.time + entry.time
        sum.calls = sum.calls + entry.calls
        sum.alloc = sum.alloc + (entry.alloc or 0)
        if entry.max > sum.max then sum.max = entry.max end
    end
    return owners
end

---The owner of a hook: a string id as is, a registry entity (or an instance of one) as "<kind>:<ClassName>",
---anything else by its type.
---@param id any
---@return string
function lib.Owner(id)
    if isstring(id) then return id end
    if istable(id) and id.ClassName ~= nil then
        local registry = id._Registry --[[@as any]]
        local kind = istable(registry) and (registry --[[@as table]]).Kind or "?"
        return tostring(kind) .. ":" .. tostring(id.ClassName)
    end
    return type(id)
end

---The key of a scheduler id: "sched:<part before the first colon>" ("brain:12" -> "sched:brain").
---@param id any
---@return string
function lib.SchedulerKey(id)
    if not isstring(id) then return "sched:" .. type(id) end
    return "sched:" .. (string.match(id, "^([^:]*)") or id)
end

---@param name string
---@param summary PWDev.ProfileSummary
---@return string
local function seriesLine(name, summary)
    return string.format("%s n=%d avg=%.3f p50=%.3f p95=%.3f p99=%.3f max=%.3f", name, summary.count, summary.avg,
        summary.p50, summary.p95, summary.p99, summary.max)
end

---@param key string
---@param entry PWDev.ProfileEntry
---@param duration number
---@param frames integer
---@return string
local function timeLine(key, entry, duration, frames)
    return string.format("%s ms_s=%.3f calls_s=%.1f us_call=%.1f ms_frame=%.4f max_ms=%.3f KB_s=%.1f", key,
        entry.time * 1000 / duration, entry.calls / duration, entry.time * 1e6 / math.max(1, entry.calls),
        entry.time * 1000 / math.max(1, frames), entry.max * 1000, (entry.alloc or 0) / duration)
end

---@param key string
---@param entry PWDev.NetEntry
---@param duration number
---@return string
local function netLine(key, entry, duration)
    return string.format("%s msg_s=%.2f B_s=%.1f payload_B=%.1f recipients=%.2f", key, entry.messages / duration,
        entry.bytes / duration, entry.payload / math.max(1, entry.messages), entry.sends / math.max(1, entry.messages))
end

---The report as console lines, each starting with "[PW] profile <tag> <realm>".
---@param report PWDev.Report
---@return string[]
function lib.ReportLines(report)
    local duration = math.max(report.duration, 1e-6)
    local head = string.format("[PW] profile %s %s ", report.tag, report.realm)
    local lines = { head .. string.format("duration_s=%.1f frames=%d", report.duration, report.frames) }
    for _, item in ipairs(report.series) do
        lines[#lines + 1] = head .. seriesLine(item.name, lib.Summarize(item.series))
    end
    for _, item in ipairs(report.tables) do
        local field = item.by or (item.net and "bytes" or "time")
        for i, ranked in ipairs(lib.Rank(item.entries, field, item.limit)) do
            local body = item.net and netLine(ranked.key, ranked.entry --[[@as PWDev.NetEntry]], duration)
                or timeLine(ranked.key, ranked.entry --[[@as PWDev.ProfileEntry]], duration, report.frames)
            lines[#lines + 1] = head .. string.format("%s #%d %s", item.name, i, body)
        end
    end
    for _, line in ipairs(report.extra or {}) do lines[#lines + 1] = head .. line end
    return lines
end

return lib
