-- Opaque, current-map readiness. Only the detector certifies generated geometry.
local lib = PW.Map --[[@as PW.MapLib]]

---@param id string
---@return PW.MapModeReadiness?
local function record(id)
    if SERVER then return PW._Map.readiness ~= nil and PW._Map.readiness[id] or nil end
    local prefix = "pw_map_ready_" .. id
    local state = GetGlobal2String(prefix, "")
    if state ~= "pending" and state ~= "ready" and state ~= "rejected" then return nil end
    local reason = GetGlobal2String(prefix .. "_reason", "")
    if state == "rejected" and reason == "" then reason = "Map layout was rejected" end
    return { state = state, reason = reason ~= "" and reason or nil,
        source = GetGlobal2String(prefix .. "_source", "") }
end

---@param sourceId string
function lib._DropGeneratedReadiness(sourceId)
    for id, value in pairs(PW._Map.readiness or {}) do
        local mode = PW.Modes.Get(id)
        if value.source == "generated" and table.HasValue(lib._ModeChain(mode, id), sourceId) then
            PW._Map.readiness[id] = nil
            if PW._Map.entitiesReady then
                local prefix = "pw_map_ready_" .. id
                SetGlobal2String(prefix, "")
                SetGlobal2String(prefix .. "_reason", "")
                SetGlobal2String(prefix .. "_source", "")
            end
        end
    end
end

---@param modeId string
---@return PW.MapModeReadiness
function lib._ReadModeReadiness(modeId)
    local modes = rawget(PW, "Modes") --[[@as PW.Registry?]]
    local mode = modes ~= nil and modes.Get(modeId) or nil
    local chain = lib._ModeChain(mode, modeId)
    local entry = lib.Get()
    local authored = entry ~= nil and entry.Modes or nil
    local current = record(modeId)
    if current == nil then
        for _, id in ipairs(chain) do
            if istable(authored) and (authored --[[@as table<string, any>]])[id] ~= nil then
                current = record(id)
                break -- Authored child data never borrows a base layout's certification.
            end
        end
    end
    local _, present = lib._ResolveModeData(authored, nil, chain)
    if current == nil and not present then
        for _, id in ipairs(chain) do
            current = record(id)
            if current ~= nil then break end
        end
    end
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
    local prefix = "pw_map_ready_" .. modeId
    SetGlobal2String(prefix, "pending")
    SetGlobal2String(prefix .. "_reason", reason or "")
    SetGlobal2String(prefix .. "_source", source or "")
    SetGlobal2String(prefix, state)
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
