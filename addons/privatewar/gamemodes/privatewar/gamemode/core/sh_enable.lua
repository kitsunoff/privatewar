-- Enable snapshot, shared part (T-1.4, 01-extensibility.md d.11, d.16; DESIGN.md global rule 2). The server takes
-- the snapshot from the enable ConVars (sv_enable.lua) and writes it as one NW2 global bool per disabled entity
-- ("pw_off:<kind>:<id>"); the client reads those values back (cl_enable.lua). Both realms apply the snapshot with
-- _Apply, so GetEnabledList and IsValid on the client match the server and a module disabled for the match is
-- disabled on the client too. Pure functions over plain data.

local enable = (rawget(PW, "Enable") or {}) --[[@as PW.EnableLib]]
PW.Enable = enable

enable._Reason = "disabled by its enable ConVar"

function enable._Key(kindId, id)
    return "pw_off:" .. kindId .. ":" .. id
end

function enable._Apply(registries, snapshot)
    for kindId, registry in pairs(registries) do
        local disabled = snapshot[kindId] or {}
        for _, entity in ipairs(registry.GetList()) do
            local id = entity.ClassName
            local reason = registry._DisabledReason(id)
            if disabled[id] and reason == nil then
                registry._Disable(id, enable._Reason)
            elseif not disabled[id] and reason == enable._Reason then
                registry._Enable(id)
            end
        end
    end
end

function enable._Writes(registries, snapshot, published)
    ---@type table<string, boolean>
    local wanted = {}
    for key in pairs(published) do wanted[key] = false end
    for kindId, registry in pairs(registries) do
        local disabled = snapshot[kindId] or {}
        for _, entity in ipairs(registry.GetList()) do
            if disabled[entity.ClassName] then wanted[enable._Key(kindId, entity.ClassName)] = true end
        end
    end
    ---@type PW.EnableWrite[]
    local writes = {}
    for key, value in pairs(wanted) do
        if value ~= (published[key] == true) then writes[#writes + 1] = { key = key, value = value } end
    end
    table.sort(writes, function(a, b) return a.key < b.key end)
    return writes
end

function enable._ReadSnapshot(registries, read)
    ---@type PW.EnableSnapshot
    local snapshot = {}
    for kindId, registry in pairs(registries) do
        for _, entity in ipairs(registry.GetList()) do
            if read(enable._Key(kindId, entity.ClassName)) then
                local ids = snapshot[kindId] or {}
                ids[entity.ClassName] = true
                snapshot[kindId] = ids
            end
        end
    end
    return snapshot
end
