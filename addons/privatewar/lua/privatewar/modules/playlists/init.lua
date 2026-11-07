-- Playlists module, server glue (T-2.6; 02-modes.md d.2-d.5b). Thin wrappers around the pure rules in shared.lua: the
-- Lua playlists of the playlists registry, the host's JSON files under data/privatewar/playlists/, the facts the
-- validation needs (known modes, match settings), the map pool and the "mode fits map" test, applying the settings
-- of a playlist and starting the match, and three client messages through PW.Net.Receive. Engine calls are fields
-- of the store, so tests drive everything with fakes.
--
-- Ids: a Lua playlist's id is its file name; a JSON playlist's id is its file name without ".json". When both exist
-- the Lua playlist wins and the JSON file is skipped with one log line.
-- The active playlist is the ConVar pw_playlist_active (archived: it survives the map change a match start may
-- cause); "" means Custom. The vote (T-2.13) samples from it with PW.Playlist.Pick.

local lib = PW.Playlist --[[@as PW.PlaylistLib]]
local module = MODULE

PW.Privilege(lib.Privilege, "superadmin")

util.AddNetworkString("pw_playlist_list")

local activeVar = "pw_playlist_active"
CreateConVar(activeVar, "", { FCVAR_ARCHIVE }, "Private War: the active playlist id (empty = Custom)")

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

---@return table<string, PW.Registry>
local function registries()
    return rawget(PW, "Registries") or {}
end

---@return table[]
local function defaultLuaEntries()
    local registry = rawget(PW, "Playlists") --[[@as PW.Registry?]]
    return registry ~= nil and registry.GetEnabledList() or {}
end

---All modes and every `match` setting a playlist may override, by full id.
---@return PW.PlaylistFacts
local function defaultFacts()
    local modes = registries().modes
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

---@return string[]
local function defaultPool()
    local mapList = rawget(PW, "MapList") --[[@as PW.MapListLib?]]
    return mapList ~= nil and mapList.GetList ~= nil and mapList.GetList() or {}
end

---Whether a mode is enabled for the next match and offered on a map: installed map, and for a mode that needs map data
---(MODE.MapData) valid data for it (PW.Map.ModeFits; docs/api/map.md).
---@param modeId string
---@param map string
---@return boolean
local function defaultFits(modeId, map)
    if not file.Exists("maps/" .. map .. ".bsp", "GAME") then return false end
    local modes = registries().modes
    local mode = modes ~= nil and modes.Get(modeId) or nil
    if mode == nil or not table.HasValue(modes.GetEnabledList(), mode) then return false end
    if mode.MapData ~= true then return true end
    local mapData = PW.Map
    return mapData ~= nil and mapData.ModeFits(mode, map)
end

---@param modeId string
---@param map string
---@return boolean
local function defaultStart(modeId, map)
    local modes = registries().modes
    local mode = modes ~= nil and modes.Get(modeId) or nil
    if mode == nil then return false end
    return assert(PW.Match).Start(mode, map)
end

---@param ply Player
---@param state PW.PlaylistListState
local function sendList(ply, state)
    net.Start("pw_playlist_list")
    lib._Encode(state, { uint = net.WriteUInt, string = net.WriteString, bool = net.WriteBool })
    net.Send(ply)
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        log = opts.log or defaultLog,
        dir = opts.dir or lib.DataDir,
        luaEntries = opts.luaEntries or defaultLuaEntries,
        facts = opts.facts or defaultFacts,
        pool = opts.pool or defaultPool,
        fits = opts.fits or defaultFits,
        rng = opts.rng or math.random,
        setSetting = opts.setSetting or function(fullId, value) return PW.Settings.Set(fullId, value) end,
        start = opts.start or defaultStart,
        readId = opts.readId or net.ReadString,
        send = opts.send or sendList,
        getActive = opts.getActive or function() return GetConVar(activeVar):GetString() end,
        setActive = opts.setActive or function(id) GetConVar(activeVar):SetString(id) end
    }
end

PW._Playlist = PW._Playlist or lib._NewStore()

---@return PW.PlaylistStore
local function store()
    return PW._Playlist --[[@as PW.PlaylistStore]]
end

function lib.LoadDir(dir)
    local st = store()
    dir = dir or st.dir
    local facts = st.facts()
    ---@type PW.PlaylistEntry[]
    local list = {}
    ---@type PW.PlaylistFileError[]
    local errors = {}
    ---@type string[]
    local names = file.Find(dir .. "/*.json", "DATA") or {}
    table.sort(names)
    for _, name in ipairs(names) do
        local id = lib.FileId(name)
        ---@type PW.PlaylistData?, string?
        local data, err
        if id == nil then
            err = "the file name must be lowercase letters, digits and _ plus .json"
        else
            data, err = lib.FromJson(file.Read(dir .. "/" .. name, "DATA"), facts)
        end
        if data ~= nil and id ~= nil then
            list[#list + 1] = { id = id, source = "json", Name = data.Name, Modes = data.Modes, Maps = data.Maps,
                Settings = data.Settings }
        else
            errors[#errors + 1] = { file = name, message = tostring(err) }
            st.log(string.format("playlist file %s/%s rejected: %s", dir, name, tostring(err)))
        end
    end
    return list, errors
end

---@param entries PW.PlaylistEntry[]
local function sortEntries(entries)
    table.sort(entries, function(a, b)
        if a.Name ~= b.Name then return a.Name < b.Name end
        return a.id < b.id
    end)
end

function lib.GetList()
    local st = store()
    local facts = st.facts()
    ---@type PW.PlaylistEntry[]
    local list = {}
    ---@type table<string, true>
    local taken = {}
    for _, entity in ipairs(st.luaEntries()) do
        local data, err = lib.Normalize(entity, facts)
        if data ~= nil then
            taken[entity.ClassName] = true
            list[#list + 1] = { id = entity.ClassName, source = "lua", Name = data.Name, Modes = data.Modes,
                Maps = data.Maps, Settings = data.Settings }
        else
            st.log(string.format("playlist %s skipped: %s", tostring(entity.ClassName), tostring(err)))
        end
    end
    local files = lib.LoadDir()
    for _, entry in ipairs(files) do
        if taken[entry.id] then
            st.log(string.format("playlist file %s.json skipped: a Lua playlist has the same id", entry.id))
        else
            list[#list + 1] = entry
        end
    end
    sortEntries(list)
    return list
end

function lib.Get(id)
    for _, entry in ipairs(lib.GetList()) do
        if entry.id == id then return entry end
    end
    return nil
end

function lib.Save(id, data, dir)
    local st = store()
    dir = dir or st.dir
    if not isstring(id) or id == "" or #id > 64 or string.match(id, "^[a-z0-9_]+$") == nil then
        return false, "the id must be lowercase letters, digits and _"
    end
    local clean, err = lib.Normalize(data, st.facts())
    if clean == nil then return false, err end
    file.CreateDir(dir)
    file.Write(dir .. "/" .. id .. ".json", lib.ToJson(clean))
    return true
end

function lib.Pick(id)
    local entry = lib.Get(id)
    if entry == nil then return nil, "unknown playlist " .. tostring(id) end
    local st = store()
    return lib.Sample(entry, { rng = st.rng, maps = st.pool(), fits = st.fits })
end

function lib.GetActive()
    return store().getActive()
end

function lib.SetActive(id)
    store().setActive(id)
end

---Whether a navmesh generation runs (navgen, T-2.12): no match may start then, the map reloads when it ends.
---nil-safe: false when the navgen module is missing.
---@return boolean
local function navGenerating()
    local navgen = rawget(PW, "NavGen") --[[@as PW.NavGenLib?]]
    return navgen ~= nil and navgen.IsGenerating ~= nil and navgen.IsGenerating()
end

function lib.Start(id)
    local st = store()
    if navGenerating() then return false, "navmesh generation running" end
    local entry = lib.Get(id)
    if entry == nil then return false, "unknown playlist " .. tostring(id) end
    local pick, err = lib.Sample(entry, { rng = st.rng, maps = st.pool(), fits = st.fits })
    if pick == nil then return false, err end
    for fullId, value in pairs(entry.Settings) do
        local ok, reason = st.setSetting(fullId, value)
        if not ok then
            st.log(string.format("playlist %s: setting %s not applied: %s", id, fullId, tostring(reason)))
        end
    end
    st.setActive(id)
    st.log(string.format("playlist %s starts %s on %s", id, pick.mode, pick.map))
    return st.start(pick.mode, pick.map), nil
end

---@param ply Player
---@return PW.PlaylistListState
local function listState(ply)
    local st = store()
    ---@type PW.PlaylistSummary[]
    local list = {}
    local active = st.getActive()
    local known = active == ""
    for _, entry in ipairs(lib.GetList()) do
        local fill = entry.Settings["bots.fill"]
        list[#list + 1] = lib._Summary(entry, isnumber(fill) and fill or 0)
        if entry.id == active then known = true end
    end
    return { list = list, active = known and active or "", canPick = PW.Can(ply, lib.Privilege) }
end

---@param ply Player
---@return string
local function nick(ply)
    return IsValid(ply) and ply:Nick() or tostring(ply)
end

function lib._OnRequest(ply)
    store().send(ply, listState(ply))
    return true
end

function lib._OnPick(ply)
    local st = store()
    local id = st.readId()
    if id ~= "" and lib.Get(id) == nil then
        st.log(string.format("playlist pick from %s refused: unknown playlist %s", nick(ply), tostring(id)))
        return false
    end
    st.setActive(id)
    st.send(ply, listState(ply))
    return true
end

function lib._OnStart(ply)
    local st = store()
    local id = st.readId()
    local ok, reason = lib.Start(id)
    if not ok then
        st.log(string.format("playlist start from %s refused: %s (%s)", nick(ply), tostring(reason), tostring(id)))
    end
    return ok
end

function lib._RegisterNet(owner)
    local netLib = assert(PW.Net)
    owner = owner or module
    netLib.Receive("pw_playlist_request",
        { who = "any", phases = { "LOBBY", "PREMATCH" }, rate = 4, maxLen = 16, owner = owner },
        function(ply) lib._OnRequest(ply) end)
    netLib.Receive("pw_playlist_pick",
        { who = lib.Privilege, phases = { "LOBBY" }, rate = 4, maxLen = 256, owner = owner },
        function(ply) lib._OnPick(ply) end)
    netLib.Receive("pw_playlist_start",
        { who = lib.Privilege, phases = { "LOBBY" }, rate = 2, maxLen = 256, owner = owner },
        function(ply) lib._OnStart(ply) end)
end

lib._RegisterNet()
