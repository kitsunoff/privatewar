-- Opaque, current-map readiness. Only the detector certifies generated geometry.
local lib = PW.Map --[[@as PW.MapLib]]

---@param field "state"|"reason"|"source"
---@param id string
---@return string
function lib._ReadinessKey(field, id)
    -- Colons cannot occur in registry ids. Field names never share an id namespace.
    return "pw_map_ready:" .. field .. ":" .. id
end

---@param modeId string
---@return string, boolean
function lib._ModeDataSource(modeId)
    local modes = rawget(PW, "Modes") --[[@as PW.Registry?]]
    local mode = modes ~= nil and modes.Get(modeId) or nil
    local chain = lib._ModeChain(mode, modeId)
    local entry = lib.Get()
    local authored = entry ~= nil and entry.Modes or nil
    if istable(authored) then
        for _, id in ipairs(chain) do
            if (authored --[[@as table<string, any>]])[id] ~= nil then return id, true end
        end
    end
    if table.HasValue(chain, "snd") then return "snd", false end
    return modeId, false
end

---@param id string
---@return PW.MapModeReadiness?
local function record(id)
    if SERVER then return PW._Map.readiness ~= nil and PW._Map.readiness[id] or nil end
    local state = GetGlobal2String(lib._ReadinessKey("state", id), "")
    if state ~= "pending" and state ~= "ready" and state ~= "rejected" then return nil end
    local reason = GetGlobal2String(lib._ReadinessKey("reason", id), "")
    if state == "rejected" and reason == "" then reason = "Map layout was rejected" end
    return { state = state, reason = reason ~= "" and reason or nil,
        source = GetGlobal2String(lib._ReadinessKey("source", id), "") }
end

---@param sourceId string
function lib._DropGeneratedReadiness(sourceId)
    for id, value in pairs(PW._Map.readiness or {}) do
        local mode = PW.Modes.Get(id)
        if value.source == "generated" and table.HasValue(lib._ModeChain(mode, id), sourceId) then
            PW._Map.readiness[id] = nil
            if PW._Map.entitiesReady then lib._ClearReadinessKeys(id) end
        end
    end
end

---@param id string
function lib._ClearReadinessKeys(id)
    SetGlobal2String(lib._ReadinessKey("state", id), "")
    SetGlobal2String(lib._ReadinessKey("reason", id), "")
    SetGlobal2String(lib._ReadinessKey("source", id), "")
end

---@param modeId string
---@return PW.MapModeReadiness
function lib._ReadModeReadiness(modeId)
    -- Certification belongs to the actual data source, not every consumer's reset placeholder.
    local source = lib._ModeDataSource(modeId)
    local current = record(source)
    local navReady = SERVER and lib.IsNavReady() or (CLIENT and GetGlobal2Bool("pw_map_nav_ready", false))
    if not navReady then return { state = "pending" } end
    return current or { state = "pending" }
end

---@param modeId string
---@param state PW.MapReadinessState
---@param reason? string
---@param source? string
function lib.SetModeReadiness(modeId, state, reason, source)
    assert(SERVER, "map readiness is server-owned")
    assert(state == "pending" or state == "ready" or state == "rejected", "invalid map readiness")
    if state == "rejected" and (not isstring(reason) or #reason == 0) then reason = "Map layout was rejected" end
    reason = reason ~= nil and string.sub(string.gsub(reason, "[%c]", " "), 1, 256) or nil
    PW._Map.readiness = PW._Map.readiness or {}
    PW._Map.readiness[modeId] = { state = state, reason = reason, source = source }
    if not PW._Map.entitiesReady then return end
    SetGlobal2String(lib._ReadinessKey("state", modeId), "pending")
    SetGlobal2String(lib._ReadinessKey("reason", modeId), reason or "")
    SetGlobal2String(lib._ReadinessKey("source", modeId), source or "")
    SetGlobal2String(lib._ReadinessKey("state", modeId), state)
end

---@param modeId string
---@return PW.MapReadinessState, string?
function lib.GetModeReadiness(modeId)
    assert(SERVER, "GetModeReadiness is a server query")
    local mode = PW.Modes.Get(modeId)
    if mode == nil or not mode:IsValid() then return "rejected", "Mode is unavailable" end
    if mode.MapData ~= true then return "ready" end
    if mode.MapReadiness == true and not lib.IsNavReady() then return "pending" end
    local entry = lib.Get()
    local data, present = lib._ResolveModeData(entry ~= nil and entry.Modes or nil, nil,
        lib._ModeChain(mode, modeId))
    if present then
        if not istable(data) then return "rejected", "Authored map data is invalid" end
        if isfunction(mode.ValidateMapData) then
            local ok = PW.Call(mode, "ValidateMapData", data)
            if ok ~= true then return "rejected", "Authored map data is invalid" end
        end
    elseif not lib._ProvisionalMode(mode, game.GetMap()) then
        return "rejected", "No compatible map data"
    end
    if mode.MapReadiness ~= true then return "ready" end
    local current = lib._ReadModeReadiness(modeId)
    return current.state, current.reason
end

---@param mode PW.Entity
---@param mapName string
---@return boolean
local function retryableSource(mode, mapName)
    if mode.MapReadiness ~= true or not table.HasValue(lib._ModeChain(mode, mode.ClassName), "snd") then
        return false
    end
    local entry = lib.Get(mapName)
    local data, authored = lib._ResolveModeData(entry ~= nil and entry.Modes or nil, nil,
        lib._ModeChain(mode, mode.ClassName))
    if not authored then return lib._ProvisionalMode(mode, mapName) end
    return istable(data) and (not isfunction(mode.ValidateMapData)
        or PW.Call(mode, "ValidateMapData", data) == true)
end

function lib.GetModeAvailability(modeId, mapName)
    mapName = mapName or game.GetMap()
    local mode = PW.Modes.Get(modeId)
    if mode == nil then return { fits = false, reason = "Mode is unavailable", canRetry = false } end
    local fits, reason, classification = lib.ModeFits(mode, mapName)
    ---@type PW.MapModeAvailability
    local status = { fits = fits, reason = reason, classification = classification, canRetry = false }
    if mapName ~= game.GetMap() or mode.MapReadiness ~= true then return status end
    local current = lib._ReadModeReadiness(modeId)
    status.readiness = current.state
    if not fits then
        status.reason = reason or current.reason or "Map layout was rejected"
        status.canRetry = current.state == "rejected" and retryableSource(mode, mapName)
    end
    return status
end
