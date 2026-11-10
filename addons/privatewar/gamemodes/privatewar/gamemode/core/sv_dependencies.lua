-- Explicit mode dependencies. Snapshot after enable flags, before PREMATCH consumers; no implicit module graph.
local match = assert(PW.Match)

---@param definition PW.Entity?
---@return boolean
local function available(definition)
    return definition ~= nil and definition:IsValid() and not PW._Call.failed[definition]
end

---@param mode table
---@param registries table<string, PW.Registry>
---@return PW.DependencySnapshot?, string?
function match._CheckDependencies(mode, registries)
    local declared = mode.Dependencies --[[@as table<string, string[]>?]]
    if declared == nil then return {} end
    if not istable(declared) then return nil, "Dependencies must be a table" end
    ---@type PW.DependencySnapshot
    local snapshot = {}
    for kind, ids in pairs(declared) do
        if not isstring(kind) or not istable(ids) then return nil, "invalid dependency declaration" end
        local registry = registries[kind]
        snapshot[kind] = {}
        for _, id in ipairs(ids) do
            if not isstring(id) then return nil, "dependency id must be a string" end
            local definition = registry ~= nil and registry.Get(id) or nil
            if not available(definition) then
                return nil, string.format("required %s %q unavailable", kind, id)
            end
            snapshot[kind][id] = definition
        end
    end
    return snapshot
end

---@param kind string
---@param id string
---@return PW.Entity?
function match.Dependency(kind, id)
    local snapshot = PW._Match.dependencies
    if snapshot ~= nil then return snapshot[kind] ~= nil and snapshot[kind][id] or nil end
    local registry = (PW.Registries or {})[kind]
    return registry ~= nil and registry.Get(id) or nil
end

---@return PW.Entity[]
function match._DependencyEntities()
    ---@type PW.Entity[]
    local out = {}
    for _, ids in pairs(PW._Match.dependencies or {}) do
        for _, definition in pairs(ids) do out[#out + 1] = definition end
    end
    return out
end

---@param store PW.MatchStore
---@return boolean
function match._BindDependencies(store)
    local snapshot, reason = match._CheckDependencies(store.mode or {}, PW.Registries or {})
    store.dependencies = snapshot
    if snapshot ~= nil then return true end
    match.Abort("mode dependency failed: " .. tostring(reason))
    return false
end

-- A failed module cannot unsubscribe this safety path. Compare exact definitions, never just an id after reload.
hook.Add("PW_EntityDisabled", "PW.Match.Dependencies", function(kind, id, definition)
    local store = PW._Match
    local ids = store.dependencies ~= nil and store.dependencies[kind] or nil
    if ids == nil or ids[id] ~= definition then return end
    if store.phase ~= "PREMATCH" and store.phase ~= "LIVE" then return end
    match.Abort(string.format("mode dependency failed: required %s %q disabled", kind, id))
end)
