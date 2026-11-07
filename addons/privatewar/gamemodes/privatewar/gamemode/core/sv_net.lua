-- The one wrapper for client -> server messages (T-1.11, 00-core.md d.8; DESIGN.md global rule 4). Server only.
-- PW.Net.Receive registers the network string and a net.Receive callback that checks privilege, phase, rate and
-- length before the handler runs. Values are validated by the handler. The decision is pure (_Decide over plain
-- facts); the clock, the phase source and the logger are injectable, so tests drive _Dispatch with a bot.
-- Rate: a token bucket per player per message, size `rate`, refilled at `rate` per second. Rejections are logged
-- at most once per logInterval seconds per player. Debug mode (pw_debug 1) warns about pw_* receivers registered
-- with a plain net.Receive; net.Receive itself is never wrapped (global rule 1).
-- Owner (01-extensibility.md d.16, DESIGN.md global rule 2): opts.owner (usually the module's class table) ties the
-- message to an entity; while owner:IsValid() is false (disabled for the match, replaced) the message is dropped as
-- "disabled" before any other check, so a disabled module's handlers never run.

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

-- Seconds between two rejection lines for one player.
local logIntervalDefault = 5

local debugVar = GetConVar("pw_debug")

local netLib = (rawget(PW, "Net") or {}) --[[@as PW.NetLib]]
PW.Net = netLib

---@return string
local function currentPhase()
    local match = PW.Match
    if match == nil then return "LOBBY" end
    return match.GetPhase()
end

---@param opts? PW.NetStoreOptions
---@return PW.NetStore
function netLib._NewStore(opts)
    opts = opts or {}
    return {
        defs = {},
        buckets = setmetatable({}, { __mode = "k" }),
        lastLog = setmetatable({}, { __mode = "k" }),
        log = opts.log or defaultLog,
        clock = opts.clock or SysTime,
        phase = opts.phase or currentPhase,
        logInterval = opts.logInterval or logIntervalDefault
    }
end

PW._Net = PW._Net or netLib._NewStore()

---@param bucket PW.NetBucket?
---@param rate number
---@param now number
---@return boolean
---@return PW.NetBucket
function netLib._TakeToken(bucket, rate, now)
    local size = math.max(rate, 1)
    local tokens = size
    if bucket ~= nil then tokens = math.min(size, bucket.tokens + math.max(now - bucket.at, 0) * rate) end
    if tokens < 1 then return false, { tokens = tokens, at = now } end
    return true, { tokens = tokens - 1, at = now }
end

---@param def PW.NetDef
---@param facts PW.NetFacts
---@param bucket PW.NetBucket?
---@param now number
---@return PW.NetReason?
---@return PW.NetBucket
function netLib._Decide(def, facts, bucket, now)
    local current = bucket or { tokens = math.max(def.rate, 1), at = now }
    if facts.active == false then return "disabled", current end
    if not facts.allowed then return "privilege", current end
    if def.phases ~= nil and not def.phases[facts.phase] then return "phase", current end
    local ok, updated = netLib._TakeToken(bucket, def.rate, now)
    if not ok then return "rate", updated end
    if facts.len > def.maxLen * 8 then return "length", updated end
    return nil, updated
end

---@param last number?
---@param now number
---@param interval number
---@return boolean
function netLib._ShouldLog(last, now, interval)
    return last == nil or now - last >= interval
end

---@param phases any
---@return table<string, true>?
---@return string?
local function phaseSet(phases)
    if phases == nil then return nil end
    if not istable(phases) then return nil, "phases must be a list of phase names" end
    ---@type table<string, true>
    local set = {}
    for _, phase in ipairs(phases --[[@as any[] ]]) do
        if not PW.Phase.Transitions[phase] then return nil, "unknown phase " .. tostring(phase) end
        set[phase] = true
    end
    return set
end

---@param name string
---@param opts any
---@param handler any
---@return PW.NetDef?
---@return string?
function netLib._MakeDef(name, opts, handler)
    if not isstring(name) or name == "" then return nil, "name must be a non-empty string" end
    if not isfunction(handler) then return nil, "handler must be a function" end
    if not istable(opts) then return nil, "options must be a table" end
    if not isstring(opts.who) or opts.who == "" then return nil, "who must be \"any\" or a privilege name" end
    if not isnumber(opts.rate) or opts.rate <= 0 then return nil, "rate must be a number above 0" end
    if not isnumber(opts.maxLen) or opts.maxLen < 0 then return nil, "maxLen must be a number of bytes >= 0" end
    -- A class table gets its IsValid only when its registry registers it, after the file ran: not checked here.
    -- An owner without IsValid reads as not valid (GMod's IsValid), so its messages are dropped.
    if opts.owner ~= nil and not istable(opts.owner) then return nil, "owner must be a table" end
    local phases, err = phaseSet(opts.phases)
    if err ~= nil then return nil, err end
    ---@type PW.NetDef
    local def = {
        name = string.lower(name), who = opts.who --[[@as string]], phases = phases, rate = opts.rate --[[@as number]],
        maxLen = opts.maxLen --[[@as integer]], handler = handler, owner = opts.owner --[[@as table?]]
    }
    return def
end

---@param store PW.NetStore
---@param def PW.NetDef
---@param ply Player
---@param reason string
---@param now number
local function logRejection(store, def, ply, reason, now)
    if not netLib._ShouldLog(store.lastLog[ply], now, store.logInterval) then return end
    store.lastLog[ply] = now
    local who = IsValid(ply) and ply:Nick() or tostring(ply)
    store.log(string.format("net %s from %s dropped: %s (further drops from this player are not logged for %gs)",
        def.name, who, reason, store.logInterval))
end

---@param name string
---@param len integer
---@param ply Player
---@return boolean
---@return string?
function netLib._Dispatch(name, len, ply)
    local store = PW._Net
    local def = store.defs[string.lower(name)]
    if def == nil then return false, "unknown" end
    local now = store.clock()
    local playerBuckets = store.buckets[ply]
    if playerBuckets == nil then
        playerBuckets = {}
        store.buckets[ply] = playerBuckets
    end
    ---@type PW.NetFacts
    local facts = { allowed = def.who == "any" or PW.Can(ply, def.who), phase = store.phase(), len = len,
        active = def.owner == nil or IsValid(def.owner) }
    local reason, bucket = netLib._Decide(def, facts, playerBuckets[def.name], now)
    playerBuckets[def.name] = bucket
    if reason ~= nil then
        logRejection(store, def, ply, reason, now)
        return false, reason
    end
    def.handler(ply, len)
    return true
end

---@param name string
---@param opts PW.NetOptions
---@param handler fun(ply: Player, len: integer)
---@return boolean
function netLib.Receive(name, opts, handler)
    local store = PW._Net
    local def, err = netLib._MakeDef(name, opts, handler)
    if def == nil then
        store.log(string.format("PW.Net.Receive %q rejected: %s", tostring(name), tostring(err)))
        return false
    end
    store.defs[def.name] = def
    util.AddNetworkString(name)
    net.Receive(name, function(len, ply) netLib._Dispatch(name, len, ply) end)
    return true
end

---@param receivers table<string, any>
---@param defs table<string, any>
---@return string[]
function netLib._FindBypass(receivers, defs)
    ---@type string[]
    local found = {}
    for name in pairs(receivers) do
        if isstring(name) and string.sub(name, 1, 3) == "pw_" and defs[name] == nil then found[#found + 1] = name end
    end
    table.sort(found)
    return found
end

---@return string[]
function netLib._CheckBypass()
    local store = PW._Net
    local found = netLib._FindBypass(net.Receivers --[[@as table<string, any>]], store.defs)
    if debugVar ~= nil and debugVar:GetBool() then
        for _, name in ipairs(found) do
            store.log(string.format("net.Receive(%q) bypasses PW.Net.Receive: no privilege/phase/rate/length checks",
                name))
        end
    end
    return found
end

hook.Add("InitPostEntity", "PW.Net.CheckBypass", function() netLib._CheckBypass() end)
