-- Lobby screen v0, server glue (T-1.19). Thin wrappers around the pure rules in shared.lua: three client messages
-- through PW.Net.Receive (privilege, phase, rate and length are checked by the wrapper) and the server -> client
-- answer pw_lobby_state. Engine calls (net reads, ConVars, the map listing, PW.Match.Start) are store fields, so
-- tests drive the handlers through PW.Net._Dispatch with bots and fakes.
--
-- Modes offered and accepted: PW.Modes.GetEnabledList() (the enable snapshot of the current match) whose enable
-- ConVar is still on. PW.Match.Start does not check the flag, and a mode switched off in the lobby would be
-- disabled by the snapshot its own match takes (01-extensibility.md d.11).
-- The messages are owned by the module's class table: while lobby_ui is disabled for the match they are dropped
-- before their handlers run (01-extensibility.md d.16).

local lib = PW.Lobby --[[@as PW.LobbyLib]]
local module = MODULE

PW.Privilege(lib.StartPrivilege, "superadmin")
PW.Privilege(lib.TogglePrivilege, "superadmin")

util.AddNetworkString("pw_lobby_state")
AddCSLuaFile("privatewar/modules/lobby_ui/cl_flow.lua")

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

---@param name string
---@return boolean
local function readFlag(name)
    local convar = GetConVar(name)
    return convar == nil or convar:GetBool()
end

---@param name string
---@param enabled boolean
---@return boolean
local function writeFlag(name, enabled)
    local convar = GetConVar(name)
    if convar == nil then return false end
    convar:SetBool(enabled)
    return true
end

---@param ply Player
---@param state PW.LobbyState
local function sendState(ply, state)
    net.Start("pw_lobby_state")
    lib._Encode(state, { uint = net.WriteUInt, string = net.WriteString, bool = net.WriteBool })
    net.Send(ply)
end

---@return string[]
local function installedMaps()
    local files = file.Find("maps/*.bsp", "GAME")
    return lib._MapsFromFiles(files or {})
end

---The navmesh line of the navgen module (T-2.12), nil when the module is missing or disabled.
---@param ply Player
---@return PW.LobbyNav?
local function navInfo(ply)
    local navgen = rawget(PW, "NavGen") --[[@as PW.NavGenLib?]]
    local owner = PW.Modules.Get("navgen")
    if navgen == nil or navgen.LobbyInfo == nil or owner == nil or not owner:IsValid() then return nil end
    return navgen.LobbyInfo(ply)
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        log = opts.log or defaultLog,
        registries = opts.registries or function() return rawget(PW, "Registries") or {} end,
        readStart = opts.readStart or function() return net.ReadString(), net.ReadString() end,
        readToggle = opts.readToggle or function() return net.ReadString(), net.ReadString(), net.ReadBool() end,
        send = opts.send or sendState,
        start = opts.start or function(mode, map) return assert(PW.Match).Start(mode, map) end,
        map = opts.map or game.GetMap,
        maps = opts.maps or installedMaps,
        mapExists = opts.mapExists or function(name) return file.Exists("maps/" .. name .. ".bsp", "GAME") end,
        readFlag = opts.readFlag or readFlag,
        writeFlag = opts.writeFlag or writeFlag,
        navInfo = opts.navInfo or navInfo
    }
end

PW._Lobby = PW._Lobby or lib._NewStore()

---The enable ConVar name of an entity ("" for an unknown kind: reads as on, cannot be written).
---@param kind string
---@param id string
---@return string
local function flagName(kind, id)
    return assert(PW.Enable).ConVarName(kind, id) or ""
end

function lib._StartableModes()
    local store = PW._Lobby --[[@as PW.LobbyStore]]
    local registries = store.registries()
    local modes = registries.modes
    ---@type table[]
    local list = {}
    if modes == nil then return list end
    for _, mode in ipairs(modes.GetEnabledList()) do
        if store.readFlag(flagName("modes", mode.ClassName)) then list[#list + 1] = mode end
    end
    return list
end

---@param ply Player
---@return string
local function nick(ply)
    return IsValid(ply) and ply:Nick() or tostring(ply)
end

function lib._OnRequest(ply)
    local store = PW._Lobby --[[@as PW.LobbyStore]]
    local registries = store.registries()
    local canToggle = PW.Can(ply, lib.TogglePrivilege)
    local toggles = {}
    if canToggle then
        toggles = lib._Toggles(registries, function(kind, id) return store.readFlag(flagName(kind, id)) end)
    end
    store.send(ply, lib._BuildState({
        map = store.map(), maps = store.maps(), modes = lib._StartableModes(),
        groupsOf = function(mode) return PW.Settings.GetGroups("match", mode) end,
        toggles = toggles, canToggle = canToggle,
        canStart = PW.Can(ply, lib.StartPrivilege), canEdit = PW.Can(ply, PW.Settings.Privilege),
        nav = store.navInfo(ply)
    }))
    return true
end

---Whether a navmesh generation runs (navgen, T-2.12): no match may start then, the map reloads when it ends.
---nil-safe: false when the navgen module is missing.
---@return boolean
local function navGenerating()
    local navgen = rawget(PW, "NavGen") --[[@as PW.NavGenLib?]]
    return navgen ~= nil and navgen.IsGenerating ~= nil and navgen.IsGenerating()
end

function lib._OnStart(ply)
    local store = PW._Lobby --[[@as PW.LobbyStore]]
    local modeId, map = store.readStart()
    if navGenerating() then
        store.log(string.format("lobby start from %s refused: navmesh generation running (%s on %s)", nick(ply),
            tostring(modeId), tostring(map)))
        return false
    end
    ---@type table<string, table>
    local byId = {}
    ---@type table<string, true>
    local ids = {}
    for _, mode in ipairs(lib._StartableModes()) do
        byId[mode.ClassName] = mode
        ids[mode.ClassName] = true
    end
    local ok, reason = lib._CheckStart({ mode = modeId, map = map },
        { modes = ids, mapExists = store.mapExists, fits = lib._Fits(store.registries()) })
    if not ok then
        store.log(string.format("lobby start from %s refused: %s (%s on %s)", nick(ply), tostring(reason),
            tostring(modeId), tostring(map)))
        return false
    end
    store.log(string.format("lobby start by %s: %s on %s", nick(ply), modeId, map))
    return store.start(byId[modeId], map)
end

function lib._OnToggle(ply)
    local store = PW._Lobby --[[@as PW.LobbyStore]]
    local registries = store.registries()
    local kind, id, enabled = store.readToggle()
    ---@type PW.LobbyListed
    local listed = {}
    for kindId, registry in pairs(registries) do
        listed[kindId] = {}
        for _, entity in ipairs(registry.GetList()) do listed[kindId][entity.ClassName] = true end
    end
    local ok, reason = lib._CheckToggle({ kind = kind, id = id, enabled = enabled }, listed)
    if ok and not store.writeFlag(flagName(kind, id), enabled) then ok, reason = false, "no ConVar" end
    if not ok then
        store.log(string.format("lobby toggle from %s refused: %s (%s %s)", nick(ply), tostring(reason),
            tostring(kind), tostring(id)))
        return false
    end
    store.log(string.format("enable flag of %s %s set to %s by %s (next match)", kind, id, tostring(enabled),
        nick(ply)))
    lib._OnRequest(ply)
    return true
end

function lib._RegisterNet(owner)
    local netLib = assert(PW.Net)
    owner = owner or module
    netLib.Receive("pw_lobby_request",
        { who = "any", phases = { "LOBBY", "PREMATCH" }, rate = 4, maxLen = 16, owner = owner },
        function(ply) lib._OnRequest(ply) end)
    netLib.Receive("pw_lobby_start",
        { who = lib.StartPrivilege, phases = { "LOBBY" }, rate = 2, maxLen = 256, owner = owner },
        function(ply) lib._OnStart(ply) end)
    netLib.Receive("pw_lobby_enable", { who = lib.TogglePrivilege, rate = 10, maxLen = 256, owner = owner },
        function(ply) lib._OnToggle(ply) end)
end

lib._RegisterNet()
