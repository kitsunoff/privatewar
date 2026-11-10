-- Lua-only playlist owner. Session data is resolved once; availability is sampled only outside matches.
---@class PW.PlaylistsServer : PW.Module
local module = MODULE --[[@as PW.PlaylistsServer]]
local lib = assert(PW.Playlist)
PW.Privilege(lib.Privilege, "superadmin")
util.AddNetworkString("pw_playlist_list")
util.AddNetworkString("pw_playlist_error")
local activeVar = "pw_playlist_active"
CreateConVar(activeVar, "", { FCVAR_ARCHIVE }, "Private War: selected playlist (not start authorization)")

---@param text string
local function defaultLog(text) print("[PW] " .. text) end

---@return PW.PlaylistFacts
local function defaultFacts()
    local modes = (PW.Registries or {}).modes --[[@as PW.Registry?]]
    ---@type table<string, true>
    local ids = {}
    ---@type PW.SettingIndex
    local index = {}
    ---@param groups PW.SettingGroup[]
    local function collect(groups)
        for _, group in ipairs(groups) do
            for _, field in ipairs(group.fields) do index[field.def.id] = field.def end
        end
    end
    for _, mode in ipairs(modes ~= nil and modes.GetList() or {}) do
        ids[mode.ClassName] = true
        collect(PW.Settings.GetGroups("match", mode))
    end
    collect(PW.Settings.GetGroups("match"))
    return { modes = ids, settings = index, validate = PW.Settings._Validate }
end

---@param id string
---@param map string
---@return boolean
local function defaultFits(id, map)
    if not file.Exists("maps/" .. map .. ".bsp", "GAME") then return false end
    local modes = (PW.Registries or {}).modes
    local mode = modes ~= nil and modes.Get(id) or nil
    if mode == nil or not table.HasValue(modes.GetEnabledList(), mode) then return false end
    return mode.MapData ~= true or (PW.Map ~= nil and PW.Map.ModeFits(mode, map))
end

---@param ply Player
---@param state PW.PlaylistListState
local function sendList(ply, state)
    net.Start("pw_playlist_list")
    lib._Encode(state,
        { uint = net.WriteUInt, string = net.WriteString, bool = net.WriteBool, number = net.WriteDouble })
    net.Send(ply)
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        log = opts.log or defaultLog,
        luaEntries = opts.luaEntries or function()
            return PW.Playlists ~= nil and PW.Playlists.GetEnabledList() or {}
        end,
        allLuaEntries = opts.allLuaEntries or opts.luaEntries or function()
            return PW.Playlists ~= nil and PW.Playlists.GetList() or {}
        end,
        facts = opts.facts or defaultFacts,
        pool = opts.pool or function() return PW.MapList ~= nil and PW.MapList.GetList() or {} end,
        fits = opts.fits or defaultFits,
        rng = opts.rng or math.random,
        setSetting = opts.setSetting or function(id, value) return PW.Settings.Set(id, value) end,
        start = opts.start or function(id, map)
            local mode = (PW.Registries or {}).modes.Get(id)
            return mode ~= nil and assert(PW.Match).Start(mode, map)
        end,
        time = opts.time or os.time,
        phase = opts.phase or function() return assert(PW.Match).GetPhase() end,
        broadcast = opts.broadcast or function()
            for _, ply in ipairs(player.GetHumans()) do lib._OnRequest(ply) end
        end,
        readId = opts.readId or net.ReadString,
        send = opts.send or sendList,
        getActive = opts.getActive or function() return GetConVar(activeVar):GetString() end,
        setActive = opts.setActive or function(id) GetConVar(activeVar):SetString(id) end,
        availability = {}, serial = 0, sampledAt = 0, retained = false, selectedActive = false, spent = false,
        bootReady = opts.phase ~= nil
    }
end

-- Deliberately not a public hot-reload contract: keep the already resolved session store on code reload.
PW._Playlist = PW._Playlist or lib._NewStore()

---@return PW.PlaylistStore
local function store() return PW._Playlist end

local function initialize()
    local st = store()
    if st.entries ~= nil then return end
    st.entries, st.definitions = {}, {}
    local facts = st.facts()
    for _, definition in ipairs(st.allLuaEntries()) do
        local id = definition.ClassName
        local data, reason = lib.Resolve(definition, facts)
        if not isstring(id) or #id == 0 or #id > 64 or not string.match(id, "^[a-z0-9_]+$") then
            data, reason = nil, "invalid playlist id"
        end
        if data ~= nil then
            local entry = { id = id, source = "lua", Name = data.Name, Modes = data.Modes,
                Maps = data.Maps, Settings = data.Settings }
            st.entries[#st.entries + 1], st.definitions[id] = entry, definition
        else
            st.log("playlist " .. tostring(id) .. " rejected: " .. tostring(reason))
        end
    end
    table.sort(st.entries, function(a, b)
        if a.Name ~= b.Name then return a.Name < b.Name end
        return a.id < b.id
    end)
    -- Freeze bounded admission with the snapshot codec. Never silently truncate a selected entry on the wire.
    while #st.entries > lib._MaxEntries do
        local rejected = table.remove(st.entries)
        st.definitions[rejected.id] = nil
        st.log("playlist " .. rejected.id .. " rejected: session limit is " .. lib._MaxEntries .. " definitions")
    end
end

function lib.GetList()
    if not store().bootReady and not store().startupResolved then return {} end
    initialize()
    -- Enablement is still live for next-match selection, but resolution is never repeated.
    ---@type table<string, boolean>
    local enabled = {}
    for _, definition in ipairs(store().luaEntries()) do enabled[definition.ClassName] = true end
    ---@type PW.PlaylistEntry[]
    local list = {}
    for _, entry in ipairs(store().entries) do
        if enabled[entry.id] then list[#list + 1] = entry end
    end
    return list
end

function lib.Get(id)
    for _, entry in ipairs(lib.GetList()) do if entry.id == id then return entry end end
end

local function nonMatch()
    local phase = store().phase()
    return phase == "LOBBY" or phase == "VOTE"
end

local function changed()
    local st = store()
    st.serial = st.serial + 1
    st.broadcast()
end

---@param now number?
---@return boolean
local function refresh(now)
    if not nonMatch() then return false end
    initialize()
    local st = store()
    now = now or st.time()
    local before = st.availability
    ---@type table<string, PW.PlaylistAvailability>
    local current = {}
    local different = false
    for _, entry in ipairs(lib.GetList()) do
        local result, reason = lib._Evaluate(st.definitions[entry.id], now)
        current[entry.id] = result
        if reason ~= nil then st.log("playlist " .. entry.id .. ": " .. reason) end
        local old = before[entry.id]
        if old == nil or old.active ~= result.active or old.valid ~= result.valid
            or old.nextChange ~= result.nextChange then
            different = true
        end
    end
    for id in pairs(before) do if current[id] == nil then different = true end end
    local selection = current[st.getActive()]
    if selection ~= nil and selection.valid and st.pendingAttempt == nil then
        if selection.active then
            -- Archived ids do not grant idle expired permission. Only a validated explicit selection does.
            if st.selectedId == st.getActive() then st.selectedActive = true end
        elseif st.selectedActive and not st.spent and st.selectedId == st.getActive() then
            st.retained, st.selectedActive = true, false
            different = true
        end
    end
    st.availability, st.sampledAt = current, now
    if different or now ~= st.publishedAt then st.publishedAt = now changed() end
    return true
end

function lib.RefreshAvailability(now) return refresh(now) end

function lib._Complete()
    lib.RefreshAvailability()
    return lib._RotationAllowed(false)
end

function lib.GetAvailability(id)
    local value = store().availability[id]
    return value ~= nil and table.Copy(value) or nil
end

function lib.GetActive() return store().getActive() end

function lib.GetSelection()
    local st = store()
    local id = st.getActive()
    if id ~= "" and lib.Get(id) == nil then id = "" end
    local availability = st.availability[id]
    local retained = st.selectedId == id and st.retained
    return { id = id, retained = retained, canStart = id == "" or
        (availability ~= nil and availability.valid and (availability.active or retained)) }
end

function lib.SetActive(id)
    local st = store()
    if st.phase() ~= "LOBBY" then return false, "playlist selection requires LOBBY" end
    if PW.MapChange ~= nil and PW.MapChange.IsChanging() then return false, "a map change is in progress" end
    if not isstring(id) or #id > 64 then return false, "invalid playlist id" end
    lib.RefreshAvailability()
    if id ~= "" then
        local available = st.availability[id]
        if lib.Get(id) == nil then return false, "unknown playlist " .. id end
        if available == nil or not available.valid or not available.active then
            if id ~= st.getActive() or not lib.GetSelection().canStart then return false, "playlist is inactive" end
            return true
        end
    end
    if id ~= st.getActive() or st.selectedId ~= id then
        st.retained = false
        st.spent = false
        st.selectedId = id
        st.selectedActive = id ~= ""
        st.pendingAttempt = nil
    end
    st.setActive(id)
    changed()
    return true
end

function lib.Pick(id)
    local entry = lib.Get(id)
    if entry == nil then return nil, "unknown playlist " .. tostring(id) end
    local st = store()
    return lib.Sample(entry, { rng = st.rng, maps = st.pool(), fits = st.fits })
end

function lib.Start(id)
    local st = store()
    if st.attempt ~= nil then return false, "playlist start already in progress" end
    if PW.NavGen ~= nil and PW.NavGen.IsGenerating() then return false, "navmesh generation running" end
    if st.phase() ~= "LOBBY" then return false, "playlist start requires LOBBY" end
    if PW.MapChange ~= nil and PW.MapChange.IsChanging() then return false, "a map change is in progress" end
    local entry = lib.Get(id)
    if entry == nil then return false, "unknown playlist " .. tostring(id) end
    lib.RefreshAvailability()
    local available = st.availability[id]
    local retained = id == st.getActive() and lib.GetSelection().canStart
    if available == nil or not available.valid or not (available.active or retained) then
        return false, "playlist is inactive"
    end
    local pick, reason = lib.Pick(id)
    if pick == nil then return false, reason end
    for setting, value in pairs(entry.Settings) do
        local ok, why = st.setSetting(setting, value)
        if not ok then st.log("playlist " .. id .. ": setting " .. setting .. " not applied: " .. tostring(why)) end
    end
    -- Reserve before entering core: PREMATCH callbacks may fail synchronously. Never refund an accepted failure.
    local grant, spent, selectedActive, previousId = st.retained, st.spent, st.selectedActive, st.getActive()
    st.retained, st.selectedActive = false, false
    st.spent = not available.active
    st.setActive(id)
    local attempt = { id = id, mode = pick.mode, map = pick.map } --[[@as PW.PlaylistAttempt]]
    st.attempt = attempt
    local ok = st.start(pick.mode, pick.map)
    if not ok and st.phase() == "LOBBY" and (PW.MapChange == nil or not PW.MapChange.IsChanging())
        and not attempt.accepted then
        -- A core preflight refusal is not activation; the core marks accepted attempts below.
        st.retained = grant
        st.spent = spent
        st.selectedActive = selectedActive
        st.setActive(previousId)
    end
    st.attempt = nil
    changed()
    return ok, not ok and "playlist start refused" or nil
end

function lib._AcceptStart(mode, map)
    local st = store()
    local attempt = st.attempt
    if attempt == nil and st.phase() == "VOTE" and lib.GetActive() ~= "" then
        attempt = { id = lib.GetActive(), mode = mode, map = map }
    end
    if attempt == nil or attempt.mode ~= mode or attempt.map ~= map then return end
    attempt.accepted = true
    st.pendingAttempt = table.Copy(attempt)
end

function lib._PendingStart(mode, map)
    local attempt = store().pendingAttempt
    if attempt ~= nil and attempt.mode == mode and attempt.map == map then return attempt.id end
end

function lib._RestoreStart(id)
    if not isstring(id) or #id > 64 or lib.Get(id) == nil then return false end
    local st = store()
    st.setActive(id)
    st.selectedId, st.selectedActive, st.retained = nil, false, false
    st.pendingAttempt = nil
    return true
end

function lib._Poll()
    local st = store()
    if not st.bootReady or not nonMatch() then return end
    local now = st.time()
    if st.lastPoll ~= nil and now >= st.lastPoll and now - st.lastPoll < 60 then return end
    st.lastPoll = now
    lib.RefreshAvailability(now)
    local acceptedChange = st.pendingAttempt ~= nil and PW.MapChange ~= nil and PW.MapChange.IsChanging()
    if st.phase() == "VOTE" and not acceptedChange and not lib._RotationAllowed(false) then
        assert(PW.Match).Abort("playlist expired during vote")
    end
end

-- Core invokes this at the non-match completion boundary (not while POSTMATCH is running).
function lib._RotationAllowed(resample)
    if resample then lib.RefreshAvailability() end
    local id = lib.GetActive()
    if id == "" then return true end
    local value = lib.GetAvailability(id)
    return value ~= nil and value.valid and value.active
end

---@param ply Player
---@return PW.PlaylistListState
local function listState(ply)
    local st = store()
    ---@type PW.PlaylistSummary[]
    local list = {}
    for _, entry in ipairs(lib.GetList()) do
        local fill = entry.Settings["bots.fill"]
        local item = lib._Summary(entry, isnumber(fill) and fill or 0)
        ---@type PW.PlaylistAvailability
        local available = st.availability[entry.id] or { active = false, valid = false }
        item.active, item.valid, item.nextChange = available.active, available.valid, available.nextChange
        list[#list + 1] = item
    end
    local selection = lib.GetSelection()
    return { list = list, active = selection.id, retained = selection.retained, canStart = selection.canStart,
        serial = st.serial, sampledAt = st.sampledAt, canPick = PW.Can(ply, lib.Privilege) }
end

function lib._OnRequest(ply)
    store().serial = store().serial + 1
    store().send(ply, listState(ply))
    return true
end

---@param ply Player
---@param reason string?
local function refuse(ply, reason)
    net.Start("pw_playlist_error")
    net.WriteString(string.sub(reason or "Playlist request refused", 1, 256))
    net.Send(ply)
end

function lib._OnPick(ply)
    local ok, reason = lib.SetActive(store().readId())
    if not ok then refuse(ply, reason) end
    store().send(ply, listState(ply))
    return ok
end

function lib._OnStart(ply)
    local ok, reason = lib.Start(store().readId())
    if not ok then refuse(ply, reason) end
    return ok
end

function lib._RegisterNet(owner)
    local netLib = assert(PW.Net)
    owner = owner or module
    netLib.Receive("pw_playlist_request",
        { who = "any", phases = { "LOBBY", "PREMATCH", "VOTE" }, rate = 4, maxLen = 16, owner = owner },
        function(ply) lib._OnRequest(ply) end)
    netLib.Receive("pw_playlist_pick",
        { who = lib.Privilege, phases = { "LOBBY" }, rate = 4, maxLen = 256, owner = owner },
        function(ply) lib._OnPick(ply) end)
    netLib.Receive("pw_playlist_start",
        { who = lib.Privilege, phases = { "LOBBY" }, rate = 2, maxLen = 256, owner = owner },
        function(ply) lib._OnStart(ply) end)
end

function lib._ResolveStartup()
    initialize()
    store().startupResolved = true
end
function lib._BootReady()
    store().bootReady = true
    lib._Poll()
end
function module:PW_PhaseChange(phase)
    if phase == "PREMATCH" or phase == "LOBBY" then
        local st = store()
        st.selectedActive, st.retained, st.pendingAttempt = false, false, nil
        st.spent = false
        if st.getActive() ~= "" then changed() end
    end
end
function lib._StartFailed(reason)
    if lib.GetActive() == "" then return end
    local st = store()
    st.selectedActive, st.retained, st.pendingAttempt, st.spent = false, false, nil, true
    net.Start("pw_playlist_error")
    net.WriteString(string.sub("Returned to lobby: " .. string.gsub(reason, "%c", " "), 1, 256))
    net.Broadcast()
end
PW.HookFor(module, "Think", function() lib._Poll() end)
lib._RegisterNet()
