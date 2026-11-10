-- Loaded-map safety belongs before PREMATCH, not to round preparation after playable spawns.
local match = assert(PW.Match)

---@param reason any
---@return string
function match._StartReason(reason)
    if not isstring(reason) or reason == "" then return "Match start refused; choose another map" end
    local text = string.sub(string.gsub(reason, "%c", " "), 1, 256)
    return utf8.len(text) and text or "Match start refused; choose another map"
end

---@param reason string
---@return boolean
function match._RefuseStart(reason)
    local store = PW._Match
    store.startWait, store.startReady = nil, nil
    store.abortReason = match._StartReason(reason)
    store.log("match preflight refused: " .. store.abortReason)
    PW.Notify("PW_MatchStartRefused", store.abortReason)
    match._RefusePhase()
    return false
end

---@param mode table
---@param target string?
---@param prepared? boolean
---@return PW.MapReadinessState, string?, boolean?
local function check(mode, target, prepared)
    local map, snd = PW.Map, PW.SND
    if map == nil or snd == nil then return "rejected", "S&D map preparation is unavailable" end
    local current = PW._MapChange.map()
    if target ~= nil and target ~= current then
        local fits, reason = map.ModeFits(mode, target)
        return fits and "ready" or "rejected", reason
    end
    if not map.IsNavReady() then return "pending", nil, false end
    if not prepared then snd.PrepareMap(mode.ClassName) end
    local state, reason = map.GetModeReadiness(mode.ClassName)
    return state, reason, true
end

---@param mode table
---@param target string?
---@param prepared? boolean
---@return PW.MapReadinessState, string?, boolean?
local function safeCheck(mode, target, prepared)
    local ok, state, reason, done = pcall(check, mode, target, prepared)
    if not ok then
        PW._Match.log("map preparation error: " .. tostring(state))
        return "rejected", "S&D map preparation failed; choose another map"
    end
    if state ~= "ready" and state ~= "pending" and state ~= "rejected" then
        return "rejected", "S&D map preparation returned invalid readiness"
    end
    return state, reason, done
end

---@param mode table
---@param target string?
---@param resume fun(): boolean, string?
---@return PW.MapReadinessState
function match._StartPreflight(mode, target, resume)
    if mode.MapReadiness ~= true then return "ready" end
    local store = PW._Match
    local ready = store.startReady
    store.startReady = nil
    if ready ~= nil and ready.mode == mode and ready.map == target then return "ready" end
    local state, reason, prepared = safeCheck(mode, target)
    if state == "rejected" then match._RefuseStart(reason or "S&D map layout was rejected") end
    if state ~= "pending" then return state end
    local queued = PW.Playlist ~= nil and PW.Playlist._QueueStart(mode.ClassName, target) or nil
    store.startWait = { mode = mode, map = target, current = PW._MapChange.map(), phase = store.phase,
        deadline = store.clock() + 120, prepared = prepared, resume = queued or resume }
    return "pending"
end

---@param request PW.StartWait
---@param reason string
local function fail(request, reason)
    if request.accepted then match.Abort(reason) else match._RefuseStart(reason) end
end

---@return boolean
function match._TickStart()
    local store = PW._Match
    local request = store.startWait
    if request == nil then return false end
    if store.phase ~= request.phase or PW._MapChange.map() ~= request.current
        or match._Definition(request.mode, PW.Registries or {}) ~= request.mode then
        fail(request, "Map or mode changed while waiting; start cancelled")
        return true
    end
    if store.clock() >= request.deadline then
        fail(request, "S&D map readiness timed out; choose another map")
        return true
    end
    local state, reason, prepared = safeCheck(request.mode, request.map, request.prepared)
    request.prepared = prepared
    if state == "pending" then return true end
    store.startWait = nil
    if state == "rejected" then fail(request, reason or "S&D map layout was rejected") return true end
    store.startReady = request
    local ran, ok, why = pcall(request.resume)
    store.startReady = nil
    if not ran then
        store.log("start continuation error: " .. tostring(ok))
        fail(request, "Match continuation failed; choose another match")
    elseif not ok then
        fail(request, why or store.abortReason or "Match start refused after map preparation")
    elseif store.phase == "PREMATCH" and request.applied ~= nil then
        request.applied()
    end
    return true
end
