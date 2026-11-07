-- Enable ConVars (T-1.4, 01-extensibility.md d.11, d.16). Server only. Every listed (resolved, non-abstract)
-- entity of every registry gets pw_<token>_<id>_enabled, token = the kind's class table name in lowercase
-- (modes -> MODE -> pw_mode_kc_enabled, modules -> pw_module_<id>_enabled). The flags are read once per match,
-- when a new match enters PREMATCH (PW.Match), and the snapshot is applied through registry._Disable/_Enable:
-- a disabled entity leaves GetEnabledList and loses its PW_* subscriptions. Until the first match the snapshot
-- taken at boot applies; a reload (Boot again) re-applies the current snapshot. Entities disabled after an error
-- keep their own reason and are never re-enabled here. Pure functions over plain data; ConVar glue injectable.
-- Every applied snapshot is written to NW2 for the clients (sh_enable.lua), from server InitPostEntity on (like the
-- phase globals, notes/10 R4): the snapshot of a new match is written before PREMATCH is published.

local enable = PW.Enable --[[@as PW.EnableLib]]

---The two built-in kinds have no declaration in the kinds registry.
---@type table<string, string>
local builtinGlobals = { kinds = "KIND", modules = "MODULE" }

function enable._KindToken(registries, kindId)
    local global = builtinGlobals[kindId]
    local kinds = registries.kinds
    if global == nil and kinds ~= nil then
        local def = kinds.Get(kindId)
        if def ~= nil and isstring(def.Global) then global = def.Global --[[@as string]] end
    end
    if global == nil then return kindId end
    return string.lower(global)
end

function enable._ConVarName(token, id)
    return "pw_" .. token .. "_" .. id .. "_enabled"
end

function enable.ConVarName(kind, id)
    local registries = PW._Enable.registries()
    if registries[kind] == nil then return nil end
    return enable._ConVarName(enable._KindToken(registries, kind), id)
end

---Calls fn(kindId, id, name) for every listed entity of every registry.
---@param registries table<string, PW.Registry>
---@param fn fun(kindId: string, id: string, name: string)
local function eachListed(registries, fn)
    for kindId, registry in pairs(registries) do
        local token = enable._KindToken(registries, kindId)
        for _, entity in ipairs(registry.GetList()) do
            fn(kindId, entity.ClassName, enable._ConVarName(token, entity.ClassName))
        end
    end
end

function enable._TakeSnapshot(registries, read)
    ---@type PW.EnableSnapshot
    local snapshot = {}
    eachListed(registries, function(kindId, id, name)
        if read(name) then return end
        local ids = snapshot[kindId]
        if ids == nil then
            ids = {}
            snapshot[kindId] = ids
        end
        ids[id] = true
    end)
    return snapshot
end

---@param name string
---@return boolean
local function readConVar(name)
    local convar = GetConVar(name)
    return convar == nil or convar:GetBool()
end

---@param name string
local function createConVar(name)
    CreateConVar(name, "1", { FCVAR_ARCHIVE }, "Private War: 0 hides this entity from the next match on", 0, 1)
end

---@param name string
---@return boolean
local function conVarExists(name)
    return GetConVar(name) ~= nil
end

function enable._NewStore(opts)
    opts = opts or {}
    return {
        registries = opts.registries or function() return PW.Registries or {} end,
        read = opts.read or readConVar,
        create = opts.create or createConVar,
        exists = opts.exists or conVarExists,
        write = opts.write or SetGlobal2Bool,
        networked = false,
        published = {}
    }
end

PW._Enable = PW._Enable or enable._NewStore()

---Writes the changes of the snapshot to NW2 once the store is networked.
---@param store PW.EnableStore
---@param registries table<string, PW.Registry>
local function publish(store, registries)
    if not store.networked then return end
    for _, write in ipairs(enable._Writes(registries, store.snapshot or {}, store.published)) do
        store.write(write.key, write.value)
        store.published[write.key] = write.value or nil
    end
end

function enable._Publish()
    local store = PW._Enable
    store.networked = true
    publish(store, store.registries())
end

---@param store PW.EnableStore
---@param name string
local function ensure(store, name)
    if not store.exists(name) then store.create(name) end
end

function enable._EnsureConVars()
    local store = PW._Enable
    eachListed(store.registries(), function(_, _, name) ensure(store, name) end)
end

function enable._NewMatch()
    local store = PW._Enable
    local registries = store.registries()
    enable._EnsureConVars()
    store.snapshot = enable._TakeSnapshot(registries, store.read)
    enable._Apply(registries, store.snapshot)
    publish(store, registries)
end

function enable._OnBoot()
    local store = PW._Enable
    local registries = store.registries()
    enable._EnsureConVars()
    if store.snapshot == nil then store.snapshot = enable._TakeSnapshot(registries, store.read) end
    enable._Apply(registries, store.snapshot)
    publish(store, registries)
end

function enable._OnRegistered(registry, id)
    local store = PW._Enable
    local registries = store.registries()
    if registries[registry.Kind] ~= registry then return end
    local entity = registry.Get(id)
    if entity == nil or entity.Abstract then return end
    ensure(store, enable._ConVarName(enable._KindToken(registries, registry.Kind), id))
end

hook.Add("InitPostEntity", "PW.Enable", function() enable._Publish() end)
