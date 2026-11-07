-- Navmesh generation, server glue (T-2.12; 03-mapdata.md d.8; notes/11-navmesh-generation.md "Recommendations").
-- Thin wrappers around the pure rules in shared.lua. Every engine call (navmesh.*, file.*, RunConsoleCommand,
-- traces, bot kicks, the lobby refresh) is a store field, so tests never start a generation or reload the map.
--   Start (pw_navgen_start from the lobby, or the console command pw_navgen [fast] [force]): the privilege, LOBBY,
--     no generation or map change running, the map has no navmesh (unless force). Seeds: every spawn entity of
--     every class of PW.Map._SpawnClasses traced to the floor, plus the caller's position when on the ground. The
--     marker is written before anything else changes; then bots are kicked, the map data sampler is paused and
--     the clients get the lobby state ("generating"). Fast mode sets sv_cheats 1, nav_max_view_distance 1 and
--     nav_generate_fencetops 0 and waits one tick. navmesh.BeginGeneration() needs no sv_cheats; when the engine
--     does not start (IsGenerating false at once) the marker is deleted, sv_cheats restored, the failure shown.
--   After the reload (the engine saves maps/<map>.nav and runs changelevel itself): the marker is checked in Think
--     from InitPostEntity on, every second while the map has no navmesh areas, at most checkTriesMax times (the
--     engine loads the .nav after InitPostEntity). Then: one log line, the result in the lobby state, marker gone.
-- Never navmesh.Load()/Save(), never our own changelevel, no incremental generation (notes/11 "Things not to do").

local lib = PW.NavGen --[[@as PW.NavGenLib]]
local module = MODULE

PW.Privilege(lib.Privilege, "superadmin")

local checkTriesMax = 5
local groundDepth = Vector(0, 0, 4096)
local groundLift = Vector(0, 0, 8)
local up = Vector(0, 0, 1)

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

---@param path string
---@param text string
---@return boolean
local function writeData(path, text)
    local directory = string.match(path, "^(.*)/[^/]*$")
    if directory ~= nil then file.CreateDir(directory) end
    file.Write(path, text)
    return file.Exists(path, "DATA")
end

---@param path string
local function deleteData(path)
    if file.Exists(path, "DATA") then file.Delete(path) end
end

---@param pos Vector
---@return Vector?
---@return Vector?
local function ground(pos)
    local tr = util.TraceLine({ start = pos + groundLift, endpos = pos - groundDepth,
        mask = MASK_PLAYERSOLID_BRUSHONLY })
    if not tr.Hit or tr.StartSolid then return nil, nil end
    return tr.HitPos, tr.HitNormal
end

---@param ply Player?
---@return Vector?
---@return Vector?
local function hostSeed(ply)
    if ply == nil or not IsValid(ply) or not ply:IsOnGround() then return nil, nil end
    return ply:GetPos(), up
end

---@return PW.SpawnRecord[]
local function spawnRecords()
    local map = rawget(PW, "Map") --[[@as PW.MapLib?]]
    if map == nil or map._Collect == nil then return {} end
    return map._Collect()
end

local function kickBots()
    for _, bot in ipairs(player.GetBots()) do bot:Kick("navmesh generation") end
end

---@param paused boolean
local function pauseNav(paused)
    local map = rawget(PW, "Map") --[[@as PW.MapLib?]]
    if map ~= nil and map.PauseNav ~= nil then map.PauseNav(paused) end
end

---@return boolean
local function changing()
    local mapChange = rawget(PW, "MapChange") --[[@as PW.MapChangeLib?]]
    return mapChange ~= nil and mapChange.IsChanging()
end

---Sends the lobby state again to every human, so the navmesh line updates on open screens.
local function broadcast()
    local lobby = rawget(PW, "Lobby") --[[@as PW.LobbyLib?]]
    local owner = PW.Modules.Get("lobby_ui")
    if lobby == nil or lobby._OnRequest == nil or owner == nil or not owner:IsValid() then return end
    for _, ply in ipairs(player.GetHumans()) do lobby._OnRequest(ply) end
end

---@return boolean
local function cheatsOn()
    local convar = GetConVar("sv_cheats")
    return convar ~= nil and convar:GetBool()
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        log = opts.log or defaultLog,
        time = opts.time or os.time,
        map = opts.map or game.GetMap,
        path = opts.path or "privatewar/navgen.json",
        read = opts.read or function(path) return file.Read(path, "DATA") end,
        write = opts.write or writeData,
        delete = opts.delete or deleteData,
        navCount = opts.navCount or navmesh.GetNavAreaCount,
        isGenerating = opts.isGenerating or navmesh.IsGenerating,
        clearSeeds = opts.clearSeeds or navmesh.ClearWalkableSeeds,
        addSeed = opts.addSeed or navmesh.AddWalkableSeed,
        begin = opts.begin or navmesh.BeginGeneration,
        command = opts.command or function(name, value) RunConsoleCommand(name, value) end,
        cheats = opts.cheats or cheatsOn,
        records = opts.records or spawnRecords,
        ground = opts.ground or ground,
        hostSeed = opts.hostSeed or hostSeed,
        kickBots = opts.kickBots or kickBots,
        pauseNav = opts.pauseNav or pauseNav,
        defer = opts.defer or function(fn) timer.Simple(0, fn) end,
        humans = opts.humans or function() return #player.GetHumans() end,
        phase = opts.phase or PW.Phase.GetPhase,
        changing = opts.changing or changing,
        broadcast = opts.broadcast or broadcast,
        readStart = opts.readStart or function() return net.ReadBool(), net.ReadBool() end
    }
end

PW._NavGen = PW._NavGen or lib._NewStore()

---@return boolean
function lib.IsGenerating()
    local store = PW._NavGen --[[@as PW.NavGenStore]]
    return store.generating == true or store.isGenerating()
end

---@param ply Player
---@return PW.LobbyNav
function lib.LobbyInfo(ply)
    local store = PW._NavGen --[[@as PW.NavGenStore]]
    local areas = store.navCount()
    local generating = lib.IsGenerating()
    local can = lib._MayGenerate({ phase = store.phase(), allowed = PW.Can(ply, lib.Privilege),
        generating = generating, changing = store.changing(), areas = areas })
    local result = store.result
    return { areas = areas, generating = generating, canGenerate = can,
        fastDefault = lib._FastDefault(store.humans()), result = result ~= nil and result.text or "" }
end

---@param ply Player?
---@return string
local function nick(ply)
    if ply == nil then return "the server console" end
    return IsValid(ply) and ply:Nick() or tostring(ply)
end

---The seeds traced to the floor: one per spawn entity, plus the caller's position.
---@param store PW.NavGenStore
---@param ply Player?
---@return { pos: Vector, normal: Vector }[]
local function floorSeeds(store, ply)
    ---@type { pos: Vector, normal: Vector }[]
    local seeds = {}
    local map = rawget(PW, "Map") --[[@as PW.MapLib?]]
    local classes = map ~= nil and map._SpawnClasses or {}
    for _, seed in ipairs(lib._Seeds(store.records(), classes)) do
        local pos, normal = store.ground(seed.pos)
        if pos ~= nil and normal ~= nil then seeds[#seeds + 1] = { pos = pos, normal = normal } end
    end
    local pos, normal = store.hostSeed(ply)
    if pos ~= nil and normal ~= nil then seeds[#seeds + 1] = { pos = pos, normal = normal } end
    return seeds
end

---Adds the seeds and starts the engine; on a refusal undoes the start and shows the failure.
---@param store PW.NavGenStore
---@param seeds { pos: Vector, normal: Vector }[]
---@param marker PW.NavGenMarker
---@return boolean
local function begin(store, seeds, marker)
    store.clearSeeds()
    for _, seed in ipairs(seeds) do store.addSeed(seed.pos, seed.normal) end
    store.begin()
    if store.isGenerating() then return true end
    store.generating = nil
    store.delete(store.path)
    if marker.fast and not marker.cheatsWasOn then store.command("sv_cheats", "0") end
    store.pauseNav(false)
    store.result = { kind = "failure", text = string.format("Navmesh generation on %s could not start: the " ..
        "engine found no walkable start point.", marker.map) }
    store.log(store.result.text)
    store.broadcast()
    return false
end

---@param ply Player?
---@param fast boolean
---@param force boolean
---@return boolean
---@return string?
function lib._Start(ply, fast, force)
    local store = PW._NavGen --[[@as PW.NavGenStore]]
    local ok, reason = lib._MayGenerate({ phase = store.phase(), allowed = ply == nil or PW.Can(ply, lib.Privilege),
        generating = lib.IsGenerating(), changing = store.changing(), areas = store.navCount(), force = force })
    local seeds = ok and floorSeeds(store, ply) or {}
    if ok and #seeds == 0 then ok, reason = false, "no seeds" end
    ---@type PW.NavGenMarker
    local marker = { v = lib.Version, map = store.map(), startedAt = store.time(), fast = fast,
        cheatsWasOn = store.cheats() }
    if ok and not store.write(store.path, lib._Encode(marker)) then ok, reason = false, "marker" end
    if not ok then
        store.log(string.format("navmesh generation from %s refused: %s", nick(ply), tostring(reason)))
        return false, reason
    end
    store.generating = true
    store.result = nil
    store.kickBots()
    store.pauseNav(true)
    store.log(string.format("navmesh generation of %s started by %s (%s mode, %d seeds); the map reloads when done",
        marker.map, nick(ply), fast and "fast" or "full", #seeds))
    store.broadcast()
    if fast then
        store.command("sv_cheats", "1")
        store.command("nav_max_view_distance", "1")
        store.command("nav_generate_fencetops", "0")
    end
    local started = true
    store.defer(function() started = begin(store, seeds, marker) end)
    if not started then return false, "engine" end
    return true
end

---@param final boolean
---@return PW.NavGenOutcome?
function lib._Check(final)
    local store = PW._NavGen --[[@as PW.NavGenStore]]
    local text = store.read(store.path)
    if text == nil then return nil end
    local areas = store.navCount()
    if areas == 0 and not final then return nil end
    store.delete(store.path)
    local marker = lib._Decode(text)
    local map = store.map()
    local outcome, reason = lib._ValidateMarker(marker, { map = map, now = store.time(), areas = areas })
    if outcome == "stale" or marker == nil then
        local oneLine = string.gsub(text, "%s+", " ")
        store.log(string.format("navmesh generation marker ignored (%s): %s", tostring(reason), oneLine))
        return outcome
    end
    if marker.fast and not marker.cheatsWasOn then store.command("sv_cheats", "0") end
    local kind = outcome --[[@as "success"|"failure"]]
    store.result = { kind = kind, text = lib._ResultText(kind, map, areas) }
    store.log(store.result.text)
    store.broadcast()
    return outcome
end

function lib._RegisterNet(owner)
    assert(PW.Net).Receive("pw_navgen_start",
        { who = lib.Privilege, phases = { "LOBBY" }, rate = 1, maxLen = 8, owner = owner or module },
        function(ply)
            local fast, force = PW._NavGen.readStart()
            lib._Start(ply, fast == true, force == true)
        end)
end

lib._RegisterNet()

PW.HookFor(module, "InitPostEntity", function()
    PW._NavGen.checkAt = 0
    PW._NavGen.checkTries = 0
end)

PW.HookFor(module, "Think", function()
    local store = PW._NavGen --[[@as PW.NavGenStore]]
    local at = store.checkAt
    if at == nil or CurTime() < at then return end
    local tries = (store.checkTries or 0) + 1
    store.checkTries = tries
    local final = tries >= checkTriesMax
    if lib._Check(final) ~= nil or final or store.read(store.path) == nil then
        store.checkAt = nil
    else
        store.checkAt = CurTime() + 1
    end
end)

---@param ply Player
---@param args string[]
local function onCommand(ply, args)
    local caller = IsValid(ply) and ply or nil
    ---@type table<string, true>
    local flags = {}
    for _, arg in ipairs(args) do flags[arg] = true end
    lib._Start(caller, flags.fast == true, flags.force == true)
end

concommand.Add("pw_navgen", function(ply, _, args) onCommand(ply, args) end, nil,
    "Private War: generate the navmesh of the current map (LOBBY only; args: fast, force)")
