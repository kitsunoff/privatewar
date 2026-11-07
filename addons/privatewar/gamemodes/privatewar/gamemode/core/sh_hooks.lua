-- Hook dispatch (T-1.6, 01-extensibility.md d.9, d.18). Every PW_* hook goes through
-- hook.Call(name, PW.ActiveMode, ...): addon listeners first, the active mode's method of the same
-- name last, as the default (the GMod GM contract). Questions and notifications share the dispatch;
-- in debug mode (pw_debug 1) a notification that returns a value logs one warning.
-- The active mode is never auto-subscribed (d.18); setting PW.ActiveMode is what switches modes. PW.HookFor: below.

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

---@type PW.HookStore
PW._Hooks = PW._Hooks or { log = defaultLog }

local debugVar = CreateConVar("pw_debug", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
    "Private War debug checks (1 = on)", 0, 1)

---@param name string
---@param ... any
---@return any ...
function PW.Ask(name, ...)
    return hook.Call(name, PW.ActiveMode, ...)
end

---@param name string
---@param ... any
function PW.Notify(name, ...)
    local result = hook.Call(name, PW.ActiveMode, ...)
    if result ~= nil and debugVar:GetBool() then
        PW._Hooks.log(string.format(
            "notification %s returned a value (a listener or the active mode); listeners must not return values",
            name))
    end
end

-- Engine hooks of an entity (01-extensibility.md d.16, d.18; DESIGN.md global rule 2). Only records the hook on the
-- entity; its registry adds it with hook.Add(name, entity, fn) while the entity is resolved and enabled, removes it
-- when the entity is disabled, replaced or released, and adds it again on re-enable (sh_registry.lua).
-- hook.Add itself is never wrapped (global rule 1).
---@param entity table
---@param name string
---@param fn fun(self: table, ...: any): ...: any
function PW.HookFor(entity, name, fn)
    local hooks = rawget(entity, "_EngineHooks") --[[@as table<string, function>?]]
    if hooks == nil then
        hooks = {}
        rawset(entity, "_EngineHooks", hooks)
    end
    hooks[name] = fn
end
