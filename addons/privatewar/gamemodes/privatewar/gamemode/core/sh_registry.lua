-- Registries (T-1.2, 01-extensibility.md d.8, d.10, d.12; 04-weapons.md d.3): one per kind, SWEP-style
-- Register/Get/GetStored/GetList, deferred Base resolution, Abstract, replace on re-register, soft merge,
-- PW_PreRegister (via PW.Ask) for every registration. Pure logic: the hook and the logger are injectable.
-- Required fields (T-1.1, d.15): checked on the resolved entity, after Base, so a field inherited from the Base
-- chain counts. A non-abstract entity that fails is logged once (per registered table and reason) and is absent
-- from Get, GetList and the subscriptions, but it still serves as a Base. Late registrations are checked too.
-- Auto-subscription (T-1.7, 01-extensibility.md d.18): a registry with subscribe = "always" adds every PW_*
-- method of its resolved, enabled, non-abstract entities with hook.Add(name, entity, fn). IsValid ties the
-- subscription to the current resolved table: a disabled, replaced or re-resolved entity returns false, and
-- the registry also removes its subscriptions at once, so hook.GetTable() never holds stale entries.
-- Hooks added through PW.HookFor (entity._EngineHooks, sh_hooks.lua) follow the same life cycle in every registry,
-- whatever its subscribe mode (d.16: a disabled module's engine hooks stop running).
-- The registered class table (MODULE, MODE, ...) gets an IsValid that follows its resolved entity, so a file can
-- use its class table as owner (PW.HookFor, PW.Net.Receive opts.owner, MODULE:IsValid()).
-- A late registration re-resolves only the registered id and the entities whose Base chain includes it; every
-- other resolved table (for example the active mode) stays valid.
-- Enable ConVars (T-1.4, d.11): GetEnabledList is GetList without disabled entities; a late registration is
-- reported to PW.Enable so the new entity gets its ConVar at once.
-- Methods (T-1.5): opts.methods are put on every resolved entity that has no field of that name (modes and
-- modules get Setting from the loader).
-- Release (T-1.15, d.12): a replaced registry drops every subscription; its entities turn invalid except the
-- kept ids (the active mode keeps running until its match ends).

PW.Registry = PW.Registry or {}

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

---@type PW.PreRegisterFn
local function firePreRegister(kind, id, tbl)
    return PW.Ask("PW_PreRegister", kind, id, tbl)
end

---Tells PW.Enable about a late registration.
---@param registry PW.Registry
---@param id string
local function notifyRegistered(registry, id)
    local enableLib = rawget(PW, "Enable") --[[@as PW.EnableLib?]]
    if enableLib ~= nil then enableLib._OnRegistered(registry, id) end
end

---@type table<string, true>
local subscribeModes = { always = true, never = true }

---Names of the functions of a table whose name starts with PW_ (d.18: only the PW_ prefix), sorted.
---@param tbl table<any, any>
---@return string[]
function PW.Registry._HookMethods(tbl)
    ---@type string[]
    local names = {}
    for key, value in pairs(tbl) do
        if isstring(key) and isfunction(value) and string.sub(key, 1, 3) == "PW_" then names[#names + 1] = key end
    end
    table.sort(names)
    return names
end

---Checks the required fields of a kind (01-extensibility.md d.15). Fields are checked in name order.
---@param tbl table<string, any>
---@param required? table<string, type>
---@return boolean ok
---@return string? err readable reason
function PW.Registry.ValidateRequired(tbl, required)
    if required == nil then return true end
    ---@type string[]
    local names = {}
    for name in pairs(required) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local want = required[name]
        local value = tbl[name]
        if value == nil then
            return false, string.format("missing required field %s (%s)", name, want)
        end
        if type(value) ~= want then
            return false, string.format("field %s must be %s, got %s", name, want, type(value))
        end
    end
    return true
end

---Copies fields of source that target lacks; nested tables present in both are merged per key.
---@param target table<any, any>
---@param source table<any, any>
local function fillMissing(target, source)
    for key, value in pairs(source) do
        local existing = target[key]
        if existing == nil then
            target[key] = value
        elseif istable(existing) and istable(value) then
            fillMissing(existing, value)
        end
    end
end

---True when the stored Base chain of id (id itself included) reaches target. Stops on a cycle.
---@param stored table<string, table<any, any>>
---@param id string
---@param target string
---@return boolean
local function chainIncludes(stored, id, target)
    ---@type table<any, true>
    local seen = {}
    local current = id ---@type string?
    while current ~= nil and not seen[current] do
        if current == target then return true end
        seen[current] = true
        local own = stored[current]
        current = own ~= nil and own.Base or nil
    end
    return false
end

---Builds the resolved entity: base fields first, own fields on top. Abstract is never inherited.
---@param id string
---@param own table<any, any>
---@param base PW.Entity?
---@return PW.Entity
local function compose(id, own, base)
    ---@type PW.Entity
    local entity = { ClassName = id }
    if base ~= nil then
        for key, value in pairs(base --[[@as table<any, any>]]) do entity[key] = value end
        entity.Abstract = nil
    end
    for key, value in pairs(own) do entity[key] = value end
    entity.BaseClass = base
    entity.ClassName = id
    return entity
end

---The resolved entity of id when it exists and passed the required-field check.
---@param s PW.RegistryState
---@param id string
---@return PW.Entity?
local function usable(s, id)
    local entity = s.resolved[id]
    if not entity or s.invalid[id] then return nil end
    return entity
end

---@param s PW.RegistryState
---@param entity PW.Entity
---@return boolean
local function entityValid(s, entity)
    local id = entity.ClassName
    return (not s.released or s.kept[id] == true) and usable(s, id) == entity and s.disabled[id] == nil
end

---Checks the required fields of a freshly resolved entity; logs a failure once per registered table and reason.
---@param s PW.RegistryState
---@param id string
---@param entity PW.Entity
local function validate(s, id, entity)
    if entity.Abstract then return end
    local ok, reason = PW.Registry.ValidateRequired(entity --[[@as table<string, any>]], s.required)
    if ok then return end
    s.invalid[id] = true
    local own = s.stored[id]
    if s.reported[own] == reason then return end
    s.reported[own] = reason
    s.log(string.format("%s %q: %s", s.kind, id, tostring(reason)))
end

---@param s PW.RegistryState
---@param id string
---@param visiting table<string, true>
---@return PW.Entity?
local function resolve(s, id, visiting)
    local done = s.resolved[id]
    if done ~= nil then return done or nil end
    local own = s.stored[id]
    if visiting[id] then
        s.log(string.format("%s %q: Base cycle", s.kind, id))
        s.resolved[id] = false
        return nil
    end
    local base = nil
    if own.Base ~= nil then
        if s.stored[own.Base] == nil then
            s.log(string.format("%s %q: Base %q is not registered", s.kind, id, tostring(own.Base)))
            s.resolved[id] = false
            return nil
        end
        visiting[id] = true
        base = resolve(s, own.Base, visiting)
        visiting[id] = nil
        if base == nil then
            s.log(string.format("%s %q: Base %q failed to resolve", s.kind, id, own.Base))
            s.resolved[id] = false
            return nil
        end
    end
    local entity = compose(id, own, base)
    for name, fn in pairs(s.methods) do
        if entity[name] == nil then entity[name] = fn end
    end
    entity.IsValid = s.isValid
    entity._Registry = s.registry
    s.resolved[id] = entity
    validate(s, id, entity)
    return entity
end

---@param s PW.RegistryState
---@param id string
local function unsubscribe(s, id)
    local subscription = s.subscriptions[id]
    if subscription == nil then return end
    for _, name in ipairs(subscription.names) do hook.Remove(name, subscription.entity) end
    s.subscriptions[id] = nil
end

---Disables before cleanup/notification, so ordinary entity hooks cannot receive their own disable event.
---@param s PW.RegistryState
---@param id string
---@param reason? string
local function disable(s, id, reason)
    local entity = usable(s, id)
    local wasEnabled = entity ~= nil and entityValid(s, entity)
    local message = reason or "disabled"
    s.disabled[id] = message
    unsubscribe(s, id)
    if not wasEnabled or entity == nil then return end
    local endInstances = rawget(PW, "_EndDefinitionInstances") --[[@as (fun(definition: table))?]]
    if endInstances ~= nil then endInstances(entity) end
    PW.Notify("PW_EntityDisabled", s.kind, id, entity, message)
end

---The hooks of an entity by name: its PW_* methods when the kind subscribes, then its PW.HookFor hooks.
---@param s PW.RegistryState
---@param entity PW.Entity
---@return table<string, function>
local function hooksOf(s, entity)
    ---@type table<string, function>
    local hooks = {}
    if s.subscribe == "always" then
        for _, name in ipairs(PW.Registry._HookMethods(entity --[[@as table<any, any>]])) do
            hooks[name] = entity[name]
        end
    end
    for name, fn in pairs(entity._EngineHooks or {}) do hooks[name] = fn end
    return hooks
end

---@param s PW.RegistryState
---@param id string
local function subscribeEntity(s, id)
    local entity = usable(s, id)
    if s.released or entity == nil or entity.Abstract or s.disabled[id] ~= nil then return end
    unsubscribe(s, id)
    ---@type string[]
    local names = {}
    for name, fn in pairs(hooksOf(s, entity)) do
        hook.Add(name, entity, fn)
        names[#names + 1] = name
    end
    s.subscriptions[id] = { entity = entity, names = names }
end

---@param s PW.RegistryState
local function resolveAll(s)
    for id in pairs(s.subscriptions) do unsubscribe(s, id) end
    s.resolved = {}
    s.invalid = {}
    for id in pairs(s.stored) do resolve(s, id, {}) end
    s.loaded = true
    for id in pairs(s.resolved) do subscribeEntity(s, id) end
end

---Re-resolves only changed and the entities inheriting it; the others keep their resolved tables.
---@param s PW.RegistryState
---@param changed string
local function resolveChanged(s, changed)
    ---@type string[]
    local affected = {}
    for id in pairs(s.stored) do
        if chainIncludes(s.stored, id, changed) then affected[#affected + 1] = id end
    end
    for _, id in ipairs(affected) do
        unsubscribe(s, id)
        s.resolved[id] = nil
        s.invalid[id] = nil
    end
    for _, id in ipairs(affected) do resolve(s, id, {}) end
    for _, id in ipairs(affected) do subscribeEntity(s, id) end
end

---Gives a registered class table an IsValid that follows its resolved entity.
---@param s PW.RegistryState
---@param tbl table<any, any>
---@param id string
local function bindClassTable(s, tbl, id)
    rawset(tbl, "IsValid", function()
        local entity = usable(s, id)
        return s.stored[id] == tbl and entity ~= nil and entityValid(s, entity)
    end)
end

---@param s PW.RegistryState
---@param tbl any
---@param id any
---@param registerOpts? PW.RegisterOptions
---@return boolean
local function register(s, tbl, id, registerOpts)
    if not istable(tbl) or not isstring(id) then
        s.log(string.format("%s: Register needs a table and a string id", s.kind))
        return false
    end
    if s.preRegister(s.kind, id, tbl) == false then return false end
    local existing = s.stored[id]
    if registerOpts ~= nil and registerOpts.soft and existing ~= nil then
        fillMissing(existing, tbl)
    else
        s.stored[id] = tbl
        bindClassTable(s, tbl, id)
    end
    if s.loaded then
        resolveChanged(s, id)
        notifyRegistered(s.registry, id)
    end
    return true
end

---@param s PW.RegistryState
---@return PW.Entity[]
local function getList(s)
    ---@type string[]
    local ids = {}
    for id in pairs(s.resolved) do
        local entity = usable(s, id)
        if entity ~= nil and not entity.Abstract then ids[#ids + 1] = id end
    end
    table.sort(ids)
    ---@type PW.Entity[]
    local list = {}
    for index, id in ipairs(ids) do list[index] = usable(s, id) --[[@as PW.Entity]] end
    return list
end

---@param kind string
---@param opts PW.RegistryOptions
---@return PW.RegistryState
local function newState(kind, opts)
    local log = opts.log or defaultLog
    local subscribe = opts.subscribe or "never"
    if not subscribeModes[subscribe] then
        log(string.format("%s: Subscribe must be \"always\" or \"never\", got %q; using \"never\"", kind,
            tostring(subscribe)))
        subscribe = "never"
    end
    local registry = { Kind = kind }
    ---@type PW.RegistryState
    local s
    s = {
        kind = kind, log = log, preRegister = opts.preRegister or firePreRegister, subscribe = subscribe,
        methods = opts.methods or {}, required = opts.required, stored = {}, resolved = {}, invalid = {},
        loaded = false, released = false, kept = {}, disabled = {}, subscriptions = {},
        reported = setmetatable({}, { __mode = "k" }), registry = registry --[[@as PW.Registry]],
        isValid = function(self) return entityValid(s, self) end
    }
    return s
end

---@param kind string
---@param opts? PW.RegistryOptions
---@return PW.Registry
function PW.Registry.New(kind, opts)
    local s = newState(kind, opts or {})
    local registry = s.registry
    registry.ResolveAll = function() resolveAll(s) end
    registry._Disable = function(id, reason) disable(s, id, reason) end
    registry._Enable = function(id)
        s.disabled[id] = nil
        if s.loaded then subscribeEntity(s, id) end
    end
    registry._DisabledReason = function(id) return s.disabled[id] end
    registry._Release = function(keep)
        for id in pairs(s.subscriptions) do unsubscribe(s, id) end
        s.released = true
        s.kept = keep or {}
    end
    registry._Released = function() return s.released end
    registry.Register = function(tbl, id, registerOpts) return register(s, tbl, id, registerOpts) end
    registry.Get = function(id) return usable(s, id) end
    registry.GetStored = function(id) return s.stored[id] end
    registry.GetList = function() return getList(s) end
    registry.GetEnabledList = function()
        ---@type PW.Entity[]
        local list = {}
        for _, entity in ipairs(getList(s)) do
            if s.disabled[entity.ClassName] == nil then list[#list + 1] = entity end
        end
        return list
    end
    return registry
end
