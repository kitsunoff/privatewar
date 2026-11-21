-- Register before map entity creation. Never replace a class owned by another addon.
local lib = PW.SND --[[@as PW.SNDLib]]
if scripted_ents.GetStored("func_bomb_target") == nil then
    ---@type table<string, any>
    local definition = { Type = "brush", Base = "base_brush", Spawnable = false, pwSNDAutoTarget = true }
    ---@param self PW.SNDBombTarget
    function definition:Initialize()
        self:SetNotSolid(true)
        self:SetNoDraw(true)
    end
    ---@param self PW.SNDBombTarget
    ---@param key string
    ---@param value string
    function definition:KeyValue(key, value)
        if string.lower(key) == "startdisabled" then self.pwSNDDisabled = tonumber(value) == 1 end
    end
    ---@param self PW.SNDBombTarget
    ---@param name string
    function definition:AcceptInput(name)
        name = string.lower(name)
        if name == "disable" then self.pwSNDDisabled = true return true end
        if name == "enable" then self.pwSNDDisabled = false return true end
    end
    scripted_ents.Register(definition, "func_bomb_target")
end

function lib.Detect()
    local map = assert(PW.Map)
    if not map.IsNavReady() then return nil, "S&D is waiting for navmesh readiness" end
    local areas = assert(map.GetNavAreas)()
    if #areas == 0 then return nil, "S&D requires a navmesh; generate one or choose another map" end
    if #areas > 4096 then return nil, "S&D automatic nav area limit exceeded" end
    local stored = scripted_ents.GetStored("func_bomb_target")
    if stored == nil or stored.t.pwSNDAutoTarget ~= true then
        return nil, "S&D cannot verify bomb targets owned by another addon"
    end
    ---@type PW.SNDTarget[]
    local targets = {}
    for _, ent in ipairs(ents.FindByClass("func_bomb_target")) do
        ---@cast ent PW.SNDBombTarget
        local lo, hi = ent:WorldSpaceAABB()
        local disabled = ent.pwSNDDisabled == true
        targets[#targets + 1] = { mins = lo, maxs = hi, name = ent:GetName(), disabled = disabled }
    end
    ---@type Vector[]
    local points = {}
    ---@type CNavArea[]
    local sorted = {}
    for i, area in ipairs(areas) do sorted[i] = area end
    table.sort(sorted, function(a, b) return a:GetID() < b:GetID() end)
    for _, area in ipairs(sorted) do
        if not area:IsUnderwater() and not area:HasAttributes(NAV_MESH_CROUCH) then
            points[#points + 1] = area:GetCenter()
        end
    end
    ---@type table<integer, PW.SpawnPoint[]>
    local spawns = { {}, {} }
    for side, class in ipairs({ "info_player_terrorist", "info_player_counterterrorist" }) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            spawns[side][#spawns[side] + 1] = { pos = ent:GetPos(), yaw = ent:GetAngles().y }
        end
    end
    return lib.Derive({ targets = targets, spawns = spawns, points = points,
        safe = lib._AutoSafe, mutual = lib._AutoMutual })
end

function lib.PrepareMap(modeId)
    local map = assert(PW.Map)
    local mode = PW.Modes.Get(modeId)
    if mode == nil then return nil, "S&D mode is unavailable" end
    local source, authored = map._ModeDataSource(modeId)
    map.SetModeReadiness(source, "pending")
    if not authored then map.SetGeneratedModeData(source, nil) end
    if not map.IsNavReady() then return nil, "S&D is waiting for map entities and navmesh" end
    PW._SND.mapChecked = true -- Any completed attempt, including rejection, requires an explicit retry or reset.
    local data = map.GetModeData(modeId)
    if not authored then
        if not map._ProvisionalMode(mode, game.GetMap()) then return nil, "No S&D map data" end
        local ok, detected, reason = pcall(lib.Detect)
        if not ok then
            print("[PW] S&D detection failed: " .. tostring(detected))
            reason, detected = "S&D detection failed; choose another map", nil
        end
        data = detected
        if data == nil then
            reason = isstring(reason) and #reason > 0 and reason or "S&D detection rejected this map"
            map.SetModeReadiness(source, "rejected", reason)
            return nil, reason
        end
    end
    local valid, reason = lib.Validate(data)
    if not valid then
        map.SetModeReadiness(source, "rejected", reason)
        return nil, reason
    end
    local ok, failure = pcall(lib.Activate, data --[[@as PW.SNDMapData]])
    if not ok then
        print("[PW] S&D activation failed: " .. tostring(failure))
        reason = "S&D layout has blocked or unreachable objective points"
        map.SetModeReadiness(source, "rejected", reason)
        return nil, reason
    end
    if not authored then map.SetGeneratedModeData(source, data) end
    map.SetModeReadiness(source, "ready", nil, authored and "authored" or "generated")
    PW._SND.mapChecked = true
    return data --[[@as PW.SNDMapData]]
end

---@param reason string
---@param cause? string
function MODULE:PW_MapDataInvalidated(reason, cause)
    PW._SND.mapChecked = nil
    if cause == "reload" then return end -- Definitions/readiness change for the next match, not the pinned visit.
    local mode = PW.ActiveMode
    if mode == nil or not table.HasValue(assert(PW.Map)._ModeChain(mode, mode.ClassName), "snd") then return end
    -- Cleanup is idempotent. Retire rounds and snapshots synchronously even if Abort is deferred by the core.
    PW.Call(mode, "Cleanup")
    assert(PW.Match).Abort(reason)
end

function lib._ReadinessThink()
    local map = assert(PW.Map)
    local phase = assert(PW.Match).GetPhase()
    if phase == "PREMATCH" or phase == "LIVE" or phase == "POSTMATCH" then return end
    if PW._SND.mapChecked or not map.IsNavReady() then return end
    PW._SND.mapChecked = true
    ---@type PW.Entity[]
    local modes = {}
    for _, mode in ipairs(PW.Modes.GetEnabledList()) do
        if mode.MapReadiness == true and table.HasValue(map._ModeChain(mode, mode.ClassName), "snd") then
            modes[#modes + 1] = mode
        end
    end
    table.sort(modes, function(a, b)
        local ad, bd = #map._ModeChain(a, a.ClassName), #map._ModeChain(b, b.ClassName)
        return ad < bd or (ad == bd and a.ClassName < b.ClassName)
    end)
    ---@type table<string, true>
    local checked = {}
    for _, mode in ipairs(modes) do
        local source, authored = map._ModeDataSource(mode.ClassName)
        if not checked[source] and (authored or map._ProvisionalMode(mode, game.GetMap())) then
            checked[source] = true
            lib.PrepareMap(mode.ClassName)
        end
    end
end

function lib.RetryMap(modeId)
    local phase = assert(PW.Match).GetPhase()
    if phase ~= "LOBBY" and phase ~= "VOTE" then return nil, "S&D retry is only available outside a match" end
    local status = assert(PW.Map).GetModeAvailability(modeId)
    if not status.canRetry then return nil, status.reason or "This map cannot be retried" end
    return lib.PrepareMap(modeId)
end

PW.HookFor(MODULE, "Think", function() lib._ReadinessThink() end)
