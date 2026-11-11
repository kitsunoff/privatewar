local lib = PW.Map --[[@as PW.MapLib]]

function lib._ResetGenerated(reason, cause)
    local store = PW._Map
    local match = rawget(PW, "Match") --[[@as PW.MatchLib?]]
    local phase = match ~= nil and match.GetPhase() or "LOBBY"
    local keepNav = cause == "reload" and (phase == "PREMATCH" or phase == "LIVE" or phase == "POSTMATCH")
    ---@type table<string, true>
    local ids = {}
    for id in pairs(store.readiness or {}) do ids[id] = true end
    local modes = rawget(PW, "Modes") --[[@as PW.Registry?]]
    for _, mode in ipairs(modes ~= nil and modes.GetList() or {}) do
        if mode.MapReadiness == true then ids[lib._ModeDataSource(mode.ClassName)] = true end
    end
    store.generated, store.readiness = nil, nil
    if not keepNav then
        store.nav, store.detected = nil, nil
        store.navCheckAt, store.navTries = 0, 0
        if store.entitiesReady then SetGlobal2Bool("pw_map_nav_ready", false) end
    end
    for id in pairs(ids) do lib.SetModeReadiness(id, "pending") end
    -- Notify only after every getter has stopped supplying the old geometry.
    PW.Notify("PW_MapDataInvalidated", reason, cause)
end

function MODULE:PW_RegistriesLoaded()
    -- Before this field existed, only the post-InitPostEntity sampler populated nav.
    if PW._Map.entitiesReady == nil and PW._Map.nav ~= nil then PW._Map.entitiesReady = true end
    lib._ResetGenerated("Map data reloaded", "reload")
end
