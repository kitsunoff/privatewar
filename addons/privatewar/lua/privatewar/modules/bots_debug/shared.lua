-- Bots debug overlay (T-5.4; 07-bots.md d.11). Shared: the pure snapshot of what the bots think, its wire format
-- (explicit writes, DESIGN.md global rule 4) and the send step. Nothing here reads a blackboard, builds a table or
-- sends a byte while the server ConVar pw_bot_debug is off. The server glue is init.lua, the overlay cl_init.lua.
--
-- Wire format of pw_bot_debug (server -> privileged clients, 4 times a second):
--   string perf line; uint8 bot count (max 64);
--   per bot: uint13 entity index, string name, string behaviour, string reason, string target, bool hasGoal,
--     [int16 x, int16 y, int16 z, string status], uint6 waypoint count (max 24), int16 x, y, z per waypoint.

MODULE.Name = "Bots debug"

local lib = (rawget(PW, "BotDebug") or {}) --[[@as PW.BotDebugLib]]
PW.BotDebug = lib

lib.Privilege = "pw.bots.debug"
lib.Message = "pw_bot_debug"
lib.Interval = 0.25
lib.MaxPath = 24
lib.MaxBots = 64

local countBits, indexBits, pathBits, coordBits = 8, 13, 6, 16
local nameLength = 32
local coordLimit = 2 ^ (coordBits - 1) - 1

---@param value number
---@return integer
local function coord(value)
    return math.Clamp(math.floor(value + 0.5), -coordLimit, coordLimit)
end

---@param text any
---@return string
local function clip(text)
    if not isstring(text) then return "" end
    return string.sub(text, 1, nameLength)
end

function lib.PerfLine(counters)
    if counters == nil then return "bots: no scheduler" end
    return string.format("bots %d  tick %.2f ms (max %.2f)  runs %d  deferred %d  queued %d  over %d  err %d",
        counters.bots, counters.lastTickMs, counters.maxTickMs, counters.brainRuns, counters.deferred,
        counters.queued, counters.overBudgetTicks, counters.errors)
end

---The remaining waypoints (from the one the bot walks to), flat, capped.
---@param path PW.BotPath?
---@return integer[]
local function pathOf(path)
    ---@type integer[]
    local out = {}
    if path == nil or path.points == nil then return out end
    local first = math.max(path.index or 1, 1)
    local last = math.min(#path.points, first + lib.MaxPath - 1)
    for i = first, last do
        local point = path.points[i]
        local at = #out
        out[at + 1], out[at + 2], out[at + 3] = coord(point.x), coord(point.y), coord(point.z)
    end
    return out
end

function lib.BuildEntry(index, name, board, nameOf)
    ---@type PW.BotDebugEntry
    local entry = { index = index, name = clip(name), behavior = "", reason = "", target = "", path = {} }
    if board == nil then return entry end
    if board.behavior ~= nil then
        entry.behavior, entry.reason = clip(board.behavior.id), clip(board.behavior.reason)
    end
    local target = board.target
    if target ~= nil and IsValid(target) then entry.target = clip(nameOf(target)) end
    local goal = board.goal
    if goal ~= nil then
        local point = goal.projected or goal.point
        entry.goal = { x = coord(point.x), y = coord(point.y), z = coord(point.z), status = clip(goal.status) }
    end
    entry.path = pathOf(board.path)
    return entry
end

function lib.Collect(enabled, deps)
    if not enabled then return nil end
    ---@type PW.BotDebugEntry[]
    local entries = {}
    for _, bot in ipairs(deps.bots()) do
        if #entries >= lib.MaxBots then break end
        entries[#entries + 1] = lib.BuildEntry(bot:EntIndex(), bot:Nick(), deps.boardOf(bot), deps.nameOf)
    end
    return { perf = lib.PerfLine(deps.counters()), bots = entries }
end

function lib.Recipients(players, can)
    ---@type Player[]
    local out = {}
    for _, ply in ipairs(players) do
        if can(ply) then out[#out + 1] = ply end
    end
    return out
end

---@param entry PW.BotDebugEntry
---@param writer PW.BotDebugWriter
local function encodeEntry(entry, writer)
    writer.uint(math.Clamp(entry.index, 0, 2 ^ indexBits - 1), indexBits)
    writer.string(entry.name)
    writer.string(entry.behavior)
    writer.string(entry.reason)
    writer.string(entry.target)
    local goal = entry.goal
    writer.bool(goal ~= nil)
    if goal ~= nil then
        writer.int(goal.x, coordBits)
        writer.int(goal.y, coordBits)
        writer.int(goal.z, coordBits)
        writer.string(goal.status)
    end
    local count = math.min(math.floor(#entry.path / 3), lib.MaxPath)
    writer.uint(count, pathBits)
    for i = 1, count * 3 do writer.int(entry.path[i], coordBits) end
end

function lib.Encode(snapshot, writer)
    writer.string(snapshot.perf)
    local count = math.min(#snapshot.bots, lib.MaxBots)
    writer.uint(count, countBits)
    for i = 1, count do encodeEntry(snapshot.bots[i], writer) end
end

---@param reader PW.BotDebugReader
---@return PW.BotDebugEntry
local function decodeEntry(reader)
    local index = reader.uint(indexBits)
    local name, behavior, reason, target = reader.string(), reader.string(), reader.string(), reader.string()
    ---@type PW.BotDebugEntry
    local entry = { index = index, name = name, behavior = behavior, reason = reason, target = target, path = {} }
    if reader.bool() then
        local x, y, z = reader.int(coordBits), reader.int(coordBits), reader.int(coordBits)
        entry.goal = { x = x, y = y, z = z, status = reader.string() }
    end
    for i = 1, reader.uint(pathBits) * 3 do entry.path[i] = reader.int(coordBits) end
    return entry
end

function lib.Decode(reader)
    local perf = reader.string()
    ---@type PW.BotDebugEntry[]
    local bots = {}
    for i = 1, reader.uint(countBits) do bots[i] = decodeEntry(reader) end
    return { perf = perf, bots = bots }
end

function lib.Step(state, now, deps)
    if not deps.enabled() then return false end
    if now < state.nextAt then return false end
    state.nextAt = now + lib.Interval
    local recipients = lib.Recipients(deps.players(), deps.can)
    if #recipients == 0 then return false end
    local snapshot = lib.Collect(true, deps)
    if snapshot == nil then return false end
    deps.send(recipients, snapshot)
    return true
end
