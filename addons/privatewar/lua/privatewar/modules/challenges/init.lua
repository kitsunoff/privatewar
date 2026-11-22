local module = MODULE
local lib = assert(PW.Challenges)

include("privatewar/modules/challenges/sv_catalogue.lua")
include("privatewar/modules/challenges/sv_session.lua")
include("privatewar/modules/challenges/sv_events.lua")

local uploadName = "pw_challenges_upload"
local stateName = "pw_challenges_state"
local progressName = "pw_challenges_progress"
local deltaName = "pw_challenges_delta"

util.AddNetworkString(stateName)
util.AddNetworkString(progressName)
util.AddNetworkString(deltaName)

---@param owner Player
---@param state PW.ChallengeWireState
local function sendState(owner, state)
    if lib._StateBits(state) > lib._MaxStateBits then
        print("[PW] challenges: state exceeds the 2048-byte payload cap")
        return
    end
    net.Start(stateName)
    lib._WriteWire("state", state, net.WriteUInt)
    net.Send(owner)
end

---@param owner Player
---@param items PW.ChallengeFileItems
local function sendProgress(owner, items)
    net.Start(progressName)
    lib._WriteWire("progress", items, net.WriteUInt)
    net.Send(owner)
end

---@param owner Player
---@param delta PW.ChallengeDelta
local function sendDelta(owner, delta)
    net.Start(deltaName)
    lib._WriteWire("delta", delta, net.WriteUInt)
    net.Send(owner)
end

---@return PW.ChallengeMatchContext
local function matchContext()
    local mode, playlist = PW.ActiveMode, PW.Playlist
    ---@type string[]
    local chain = {}
    local base = mode ~= nil and mode.BaseClass or nil
    while base ~= nil and not table.HasValue(chain, base.ClassName) do
        chain[#chain + 1], base = base.ClassName, base.BaseClass
    end
    return { mode = mode ~= nil and mode.ClassName or "", modeBase = chain,
        playlist = playlist ~= nil and playlist.GetActive ~= nil and playlist.GetActive() or "" }
end

---@return PW.ChallengeSelectOptions
local function settings()
    return { count = tonumber(PW.Setting("challenges.perweek")),
        bonusNeeded = tonumber(PW.Setting("challenges.bonusneeded")),
        seed = tonumber(PW.Setting("challenges.seed")) }
end

---@param name string
---@param interval number
---@param times integer
---@param run fun()
local function schedule(name, interval, times, run)
    timer.Create(name, interval, times, function()
        if not module:IsValid() then return end
        run()
    end)
end

---@return PW.ChallengeServerDeps
local function dependencies()
    return { utc = function() return os.time() end, clock = CurTime,
        phase = function() return assert(PW.Match).GetPhase() end, players = player.GetHumans,
        isPlayer = function(ply) return isentity(ply) and IsValid(ply) and ply:IsPlayer() end,
        catalogue = lib._ChallengeCatalogue, options = settings, matchContext = matchContext,
        schedule = schedule, log = function(message) print("[PW] " .. message) end,
        sendState = sendState, sendProgress = sendProgress, sendDelta = sendDelta }
end

function module:PW_RegistriesLoaded()
    local server = PW._ChallengeServer
    local deps = dependencies()
    if server == nil then
        PW._ChallengeServer = lib._NewServer(deps)
        return
    end
    server.deps = deps
    lib._ScheduleServer(server)
end

function module:PW_WeaponsLoaded()
    local server = PW._ChallengeServer
    if server == nil then return end
    server.weaponFacts = {}
    lib._RefreshWeek(server, true)
end

---@param phase PW.PhaseName
---@param previous PW.PhaseName
function module:PW_PhaseChange(phase, previous)
    local server = PW._ChallengeServer
    if server == nil then return end
    lib._FlushChallenges(server, true, true, true)
    if phase == "LIVE" then
        -- Core announces LIVE before spawning the mode's initial roster. Preserve that first
        -- life's subsequent loadout/spawn and round notifications when MatchStart arrives.
        server.roundOpen = false
        for _, connection in pairs(server.players) do
            connection.presentAt, connection.spawnedAt, connection.lifeKills = nil, nil, 0
            connection.attachments = {}
        end
    end
    if phase == "LOBBY" or phase == "PREMATCH" or previous == "LIVE" then
        lib._RefreshWeek(server, phase == "PREMATCH")
    end
end

function module:PW_MatchStart()
    local server = PW._ChallengeServer
    if server ~= nil then lib._OpenMatch(server) end
end

function lib.GetWeek()
    local server = PW._ChallengeServer
    return module:IsValid() and server ~= nil and server.week or nil
end

function lib.GetActive()
    local week = lib.GetWeek()
    return week ~= nil and week.items or {}
end

function lib.GetProgress(ply, id)
    local server = PW._ChallengeServer
    if server == nil or not module:IsValid() or not lib._ChallengeHuman(server, ply) then return nil end
    local connection = lib._ChallengeConnection(server, ply)
    return lib._ReadProgress(server.plan, connection.progress, id)
end

assert(PW.Net).Receive(uploadName, { who = "any", rate = 0.5, maxLen = lib.UploadMaxBytes, owner = module },
    function(ply, bits)
        local server = PW._ChallengeServer
        if server == nil or not lib._ChallengeHuman(server, ply) then return end
        local connection = server.players[ply]
        if connection ~= nil and connection.upload ~= nil then return end
        local rows = lib._ReadWire("upload", bits, net.ReadUInt) --[[@as PW.ChallengeFileWeeks?]]
        if rows ~= nil then lib._AcceptUpload(server, ply, rows) end
    end)
