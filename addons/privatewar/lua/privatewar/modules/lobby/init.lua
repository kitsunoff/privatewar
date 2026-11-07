-- Lobby rules, server glue (T-8.4; 08-lobby.md d.4). Thin wrappers around the pure decision in shared.lua:
--   PlayerInitialSpawn: a human joining during LIVE with lobby.joininprogress off is remembered as a spectator and
--     told to the client (NW2 bool). With the setting on, nothing happens here: the teams module places the player in
--     the smaller team on spawn and the bots manager kicks a bot of that team.
--   PlayerSpawn: a spectator is parked in roaming observer mode after the other PlayerSpawn listeners ran (the teams
--     module would otherwise have placed the player, the base gamemode would have spawned one).
--   PW_CanRespawn: false for a spectator, so a round or respawn rule never brings the player in.
--   PW_PhaseChange: entering LOBBY or PREMATCH releases every spectator; the match start spawns everybody.
--     Entering LOBBY from a match unspawns every player (bots too) one tick later, after the other PW_PhaseChange
--     listeners: no team, then Spawn, so the base gamemode spawns a spectator as in the first lobby (08-lobby.md d.3).
-- Engine calls are fields of the store, so the tests drive everything with fakes.

local lib = PW.Jip --[[@as PW.JipLib]]

---@return PW.PhaseName
local function enginePhase()
    local match = PW.Match
    if match == nil then return "LOBBY" end
    return match.GetPhase()
end

---@return boolean
local function engineEnabled()
    return PW.Setting("lobby.joininprogress") ~= false
end

---@param ply Player
---@return boolean
local function engineIsHuman(ply)
    return not ply:IsBot()
end

---@param fn fun()
local function engineDefer(fn)
    timer.Simple(0, fn)
end

---@param ply Player
local function enginePark(ply)
    if not IsValid(ply) then return end
    ply:SetTeam(TEAM_SPECTATOR)
    ply:StripWeapons()
    ply:SetNoTarget(true)
    if assert(lib.RefreshSpectator)(ply) then return end
    ply:Spectate(OBS_MODE_ROAMING)
end

include("privatewar/modules/lobby/sv_spectator.lua")

---@param ply Player
local function engineUnpark(ply)
    if not IsValid(ply) then return end
    ply:UnSpectate()
    ply:SetNoTarget(false)
    ply:SetTeam(TEAM_UNASSIGNED)
end

---The first lobby's state: no team, so the base gamemode's PlayerSpawn makes a spectator (no model, no weapons).
---@param ply Player
local function engineUnspawn(ply)
    if not IsValid(ply) then return end
    ply:SetTeam(TEAM_UNASSIGNED)
    ply:Spawn()
end

---@param ply Player
---@param spectating boolean
local function engineMark(ply, spectating)
    if IsValid(ply) then ply:SetNW2Bool(lib.NetBool, spectating) end
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        spectators = setmetatable({}, { __mode = "k" }),
        phase = opts.phase or enginePhase,
        enabled = opts.enabled or engineEnabled,
        isHuman = opts.isHuman or engineIsHuman,
        defer = opts.defer or engineDefer,
        park = opts.park or enginePark,
        unpark = opts.unpark or engineUnpark,
        mark = opts.mark or engineMark,
        players = opts.players or player.GetAll,
        unspawn = opts.unspawn or engineUnspawn
    }
end

PW._Jip = PW._Jip or lib._NewStore()
-- A store made by older code (pw_reload keeps it) gets the fields added since.
PW._Jip.players = PW._Jip.players or player.GetAll
PW._Jip.unspawn = PW._Jip.unspawn or engineUnspawn

function lib._OnJoin(store, ply)
    local decision = lib._Decide({ phase = store.phase(), enabled = store.enabled(), human = store.isHuman(ply) })
    if store.phase() == "LIVE" and PW.Ask("PW_CanJoinInProgress", ply) == false then decision = "spectate" end
    if decision == "spectate" then
        store.spectators[ply] = true
        store.mark(ply, true)
    end
    return decision
end

function lib.Admit(ply)
    local s = PW._Jip
    if not IsValid(ply) or s.spectators[ply] == nil then return false end
    s.spectators[ply] = nil
    s.mark(ply, false)
    s.unpark(ply)
    return true
end

function lib._OnSpawn(store, ply)
    if store.spectators[ply] == nil then return false end
    store.defer(function()
        if store.spectators[ply] ~= nil then store.park(ply) end
    end)
    return true
end

function lib._CanRespawn(store, ply)
    return store.spectators[ply] == nil
end

function lib._OnPhase(store, phase)
    if not lib._ReleasesOn(phase) then return end
    for ply in pairs(store.spectators) do
        store.unpark(ply)
        store.mark(ply, false)
    end
    store.spectators = setmetatable({}, { __mode = "k" })
end

function lib._OnLobby(store, phase, oldPhase)
    if not lib._Unspawns(phase, oldPhase) then return 0 end
    local list = store.players()
    store.defer(function()
        for _, ply in ipairs(list) do store.unspawn(ply) end
    end)
    return #list
end

---@param phase PW.PhaseName
---@param oldPhase? PW.PhaseName
function MODULE:PW_PhaseChange(phase, oldPhase)
    lib._OnPhase(PW._Jip, phase)
    lib._OnLobby(PW._Jip, phase, oldPhase)
end

---@param ply Player
---@return boolean?
function MODULE:PW_CanRespawn(ply)
    if lib._CanRespawn(PW._Jip, ply) then return nil end
    return false
end

---@param ply Player
PW.HookFor(MODULE, "PlayerInitialSpawn", function(_, ply)
    lib._OnJoin(PW._Jip, ply)
end)

---@param ply Player
PW.HookFor(MODULE, "PlayerSpawn", function(_, ply)
    lib._OnSpawn(PW._Jip, ply)
end)
