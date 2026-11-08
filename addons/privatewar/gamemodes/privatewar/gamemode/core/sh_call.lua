-- PW.Call (T-1.8, 00-core.md d.6; 01-extensibility.md d.15): the one way the core and modules call entity
-- methods. pcall, one log line per error, the erroring entity disabled until map change through its registry
-- (IsValid false, hooks dropped); the active mode is not disabled but aborts the match (PW.Match.Abort, T-1.12).
-- With pw_profile 1 the time of every call is accumulated per "<kind>:<id>"; with 0 the cost is one check.
-- "Until map change": the disable lives in the registry, which the map's boot (or a reload) creates anew.

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

---@type PW.CallStore
PW._Call = PW._Call or { log = defaultLog, failed = setmetatable({}, { __mode = "k" }), profile = {} }

local profileVar = CreateConVar("pw_profile", "0", { FCVAR_REPLICATED },
    "Private War: accumulate PW.Call timings per entity (1 = on)", 0, 1)

---@param entity table<any, any>
---@return string kind, string id
local function describe(entity)
    local registry = entity._Registry --[[@as PW.Registry?]]
    local kind = registry ~= nil and registry.Kind or "?"
    return kind, tostring(entity.ClassName or "?")
end

---@param entity table<any, any>
---@param method string
---@param err any
local function onError(entity, method, err)
    local store = PW._Call
    local kind, id = describe(entity)
    local message = tostring(err)
    if entity == PW.ActiveMode then
        local reason = string.format("mode %s failed: %s", id, message)
        store.log(reason)
        local match = rawget(PW, "Match") --[[@as PW.MatchLib?]]
        if match ~= nil and isfunction(match.Abort) then match.Abort(reason) end
        return
    end
    store.log(string.format("%s %q: %s failed, disabled until map change: %s", kind, id, method, message))
    -- Own registry only: an instance (sh_instance.lua) inherits _Registry from its definition through
    -- __index, and its error must disable the instance, not the definition.
    local registry = rawget(entity, "_Registry") --[[@as PW.Registry?]]
    if registry ~= nil then
        registry._Disable(id, string.format("error in %s: %s", method, message))
    else
        store.failed[entity] = true
    end
end

---Removal is cleanup-only: never disable the definition, abort a mode or let logger failure skip profiling.
---@param entity table<any, any>
---@param err any
local function cleanupError(entity, err)
    local store = PW._Call
    store.failed[entity] = true
    local kind, id = describe(entity)
    local message = string.format("%s %q: OnUnequip cleanup failed: %s", kind, id, tostring(err))
    pcall(store.log, message)
end

---@param entity table<any, any>
---@param method string
---@param cleanup boolean
---@param ok boolean
---@param ... any
---@return any ...
local function finish(entity, method, cleanup, ok, ...)
    if ok then return ... end
    if cleanup then cleanupError(entity, ...) else onError(entity, method, ...) end
end

---@param entity table<any, any>
---@param start number
---@param ... any
---@return any ...
local function record(entity, start, ...)
    local elapsed = SysTime() - start
    local kind, id = describe(entity)
    local key = kind .. ":" .. id
    local profile = PW._Call.profile
    local entry = profile[key]
    if entry == nil then
        entry = { time = 0, calls = 0 }
        profile[key] = entry
    end
    entry.time = entry.time + elapsed
    entry.calls = entry.calls + 1
    return ...
end

---@param entity table<any, any>
---@param method string
---@param ... any
---@return any ...
function PW.Call(entity, method, ...)
    local cleanup = false
    if method == "OnUnequip" then
        local take = rawget(PW, "_TakeInstanceCleanup") --[[@as (fun(entity: table, method: string): boolean)?]]
        cleanup = take ~= nil and take(entity, method)
    end
    local fn = entity[method]
    if not isfunction(fn) then return end
    if not cleanup then
        if PW._Call.failed[entity] then return end
        local isValid = entity.IsValid
        if isfunction(isValid) and not isValid(entity) then return end
    end
    if profileVar:GetBool() then
        return record(entity, SysTime(), finish(entity, method, cleanup, pcall(fn, entity, ...)))
    end
    return finish(entity, method, cleanup, pcall(fn, entity, ...))
end

PW.Profile = PW.Profile or {}

function PW.Profile.Get()
    ---@type table<string, PW.ProfileEntry>
    local copy = {}
    for key, entry in pairs(PW._Call.profile) do copy[key] = { time = entry.time, calls = entry.calls } end
    return copy
end

function PW.Profile.Reset()
    PW._Call.profile = {}
end
