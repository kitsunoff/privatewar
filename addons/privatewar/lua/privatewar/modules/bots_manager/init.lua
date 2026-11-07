-- Bots manager, server glue (T-5.1). Thin wrappers around the pure rules in shared.lua:
--   Bots exist from PREMATCH to VOTE; the lobby shows only humans (entering LOBBY kicks every bot, and so does a
--     map that starts in LOBBY). Once a second (Think) one step brings the bots to the quota: bots.fill players in
--     total, capped by maxplayers with one slot kept free so a friend can still join (08-lobby.md d.4).
--   A human joining (PlayerInitialSpawn, one tick later) is a step at once that kicks a bot of the smaller team: the
--     teams module places the human there when it spawns. A human leaving is picked up by the next periodic step.
--     A join-in-progress spectator (NW2 pw_spectating) is not a human of the quota until they play.
--   Teams: the manager never sets a team. The teams module assigns every player at PREMATCH -> LIVE and places a
--     bot created during LIVE at its first spawn; the blackboard's team field follows Player:Team().
--   Map change (00-core.md d.9): PW_PendingMatchApplied re-creates the Lua state (the blackboard) of the bots that
--     survived changelevel and pins the file's bot target for PREMATCH; extras are kicked with Player:Kick (never
--     Entity:Remove), missing bots created with player.CreateNextBot, whose NULL is logged once and retried.
--   Idle: in Singleplayer (one log line), while the navmesh is generated (navgen kicks the bots), and for the whole
--     GLuaTest run (other test groups start real matches and create their own bots).
-- The engine calls are injectable store fields, so tests never create or kick a bot through the real store.

local lib = PW.BotsManager --[[@as PW.BotsManagerLib]]

---@param message string
local function defaultLog(message)
    print("[PW] bots: " .. message)
end

---@return PW.BotsEntry[]
local function enginePlayers()
    ---@type PW.BotsEntry[]
    local list = {}
    for _, ply in ipairs(player.GetAll()) do
        list[#list + 1] = {
            ent = ply, team = ply:Team(), bot = ply:IsBot(), id = ply:UserID(), name = ply:Nick(),
            spectating = ply:GetNW2Bool("pw_spectating", false)
        }
    end
    return list
end

---@param ent any
---@param reason string
local function engineKick(ent, reason)
    (ent --[[@as Player]]):Kick(reason)
end

---@return string
local function enginePhase()
    local match = PW.Match
    if match == nil then return "LOBBY" end
    return match.GetPhase()
end

---@return integer
local function engineFill()
    return math.floor(tonumber(PW.Setting("bots.fill")) or 0)
end

---@return boolean
local function engineGenerating()
    local navgen = rawget(PW, "NavGen") --[[@as PW.NavGenLib?]]
    if navgen ~= nil and navgen.IsGenerating ~= nil then return navgen.IsGenerating() == true end
    return navmesh.IsGenerating()
end

---@return integer
local function engineTeams()
    local teams = rawget(PW, "Teams") --[[@as PW.TeamsLib?]]
    if teams == nil then return 0 end
    return #teams.GetActive()
end

---@return any
local function engineTier()
    return PW.Setting("bots.difficulty")
end

---@return integer?
local function engineSmallest()
    local teams = rawget(PW, "Teams") --[[@as PW.TeamsLib?]]
    if teams == nil or teams.Smallest == nil then return nil end
    return teams.Smallest()
end

---@param name string
---@return Player?
local function engineCreate(name)
    return player.CreateNextBot(name)
end

---@param opts? PW.BotsStoreOptions
---@return PW.BotsStore
function lib._NewStore(opts)
    opts = opts or {}
    return {
        log = opts.log or defaultLog,
        singlePlayer = opts.singlePlayer or game.SinglePlayer,
        maxPlayers = opts.maxPlayers or game.MaxPlayers,
        players = opts.players or enginePlayers,
        create = opts.create or engineCreate,
        kick = opts.kick or engineKick,
        phase = opts.phase or enginePhase,
        fill = opts.fill or engineFill,
        generating = opts.generating or engineGenerating,
        teams = opts.teams or engineTeams,
        smallest = opts.smallest or engineSmallest,
        clock = opts.clock or CurTime,
        tier = opts.tier or engineTier,
        roll = opts.roll or math.random,
        boards = setmetatable({}, { __mode = "k" }),
        kicking = setmetatable({}, { __mode = "k" }),
        paused = false,
        resumeInLobby = false,
        refused = false,
        createFailed = false,
        serial = 0,
        nextStep = 0
    }
end

PW._BotsManager = PW._BotsManager or lib._NewStore()

---Why the store must stay idle now (the Singleplayer refusal is logged once); nil when it may act.
---@param store PW.BotsStore
---@param anyPhase? boolean ignore the phase and the navmesh generation (kicking every bot)
---@return PW.BotsIdleReason?
local function idleReason(store, anyPhase)
    local reason = lib._Gate({
        singlePlayer = store.singlePlayer(), paused = store.paused,
        generating = not anyPhase and store.generating(), phase = anyPhase and "LIVE" or store.phase()
    })
    if reason == "singleplayer" and not store.refused then
        store.refused = true
        store.log("Singleplayer: bots cannot be created here; start a New Game with Max Players 2 or more")
    end
    return reason
end

---The connected players without the bots that were kicked and are not gone yet.
---@param store PW.BotsStore
---@return PW.BotsEntry[]
local function livePlayers(store)
    for ent in pairs(store.kicking) do
        if not IsValid(ent) then store.kicking[ent] = nil end
    end
    ---@type PW.BotsEntry[]
    local list = {}
    for _, entry in ipairs(store.players()) do
        if not store.kicking[entry.ent] then list[#list + 1] = entry end
    end
    return list
end

---Whether a board counts for the personality ratio of a group (a team; 0 = no teams, every bot together).
---@param board PW.BotBoard
---@param group integer
---@return boolean
local function inGroup(board, group)
    return board.personality ~= nil and (board.team or 0) == group
end

---Gives the board its difficulty (the setting's tier, a tier per bot for "mix") and, once its team is known (at once
---when the match has no teams), a personality that keeps the team at 4 active : 1 stationary (07 d.10).
---@param store PW.BotsStore
---@param board PW.BotBoard
---@param n integer active teams
local function assignProfiles(store, board, n)
    local profiles = PW.BotProfiles
    if board.difficulty == nil then
        board.difficulty = profiles.Snapshot(profiles.Tier(profiles.ResolveTier(store.tier(), store.roll())))
    end
    if board.personality ~= nil or (n > 0 and board.team == nil) then return end
    local group = board.team or 0
    local active, stationary = 0, 0
    for _, other in pairs(store.boards) do
        if inGroup(other, group) then
            if (other.personality --[[@as table<string, any>]]).type == "stationary" then
                stationary = stationary + 1
            else
                active = active + 1
            end
        end
    end
    local chosen = profiles.PickPersonality(profiles.NextType(active, stationary), store.roll())
    if chosen == nil then chosen = profiles.PickPersonality("active", store.roll()) end
    if chosen ~= nil then board.personality = profiles.Snapshot(chosen) end
end

---The blackboard of a bot, created if missing (a bot that survived changelevel gets new Lua state); team follows
---Player:Team() while it is an active team; difficulty and personality are given once.
---@param store PW.BotsStore
---@param entry PW.BotsEntry
---@param n integer
local function refreshBoard(store, entry, n)
    local board = store.boards[entry.ent]
    if board == nil then
        board = { bot = entry.ent }
        store.boards[entry.ent] = board
    end
    if entry.team >= 1 and entry.team <= n then board.team = entry.team else board.team = nil end
    assignProfiles(store, board, n)
end

---@param store PW.BotsStore
---@param ent any
---@param reason string
local function kickBot(store, ent, reason)
    store.kicking[ent] = true
    store.boards[ent] = nil
    store.kick(ent, reason)
end

---Creates up to count bots, each with a pool name no connected player has (06-progression.md d.7); stops at the
---first NULL (no free slot yet: a kicked bot holds its slot for a while) and logs it once until a creation succeeds
---again.
---@param store PW.BotsStore
---@param count integer
---@return integer created
local function createBots(store, count)
    local created = 0
    local taken = lib._TakenNames(count > 0 and store.players() or {})
    for _ = 1, count do
        store.serial = store.serial + 1
        local name = lib._PickName(lib.NamePool, taken, store.roll)
        taken[string.lower(name)] = true
        local bot = store.create(name)
        if bot == nil or not IsValid(bot) then
            if not store.createFailed then
                store.createFailed = true
                store.log(string.format("could not create a bot (player.CreateNextBot returned NULL after %d of %d)"
                    .. "; retrying every %g s", created, count, lib._Interval))
            end
            break
        end
        store.createFailed = false
        store.boards[bot] = { bot = bot }
        created = created + 1
    end
    return created
end

---The bot count to aim for with humans connected: the quota, or the file's target during PREMATCH after a map
---change (capped by the free slots).
---@param store PW.BotsStore
---@param humans integer
---@return integer
local function targetFor(store, humans)
    local maxPlayers = store.maxPlayers()
    local pinned = store.pinned
    if pinned ~= nil and store.phase() == "PREMATCH" then
        return math.min(pinned, math.max(0, maxPlayers - lib._FreeSlots - humans))
    end
    return lib._Quota({ fill = store.fill(), maxPlayers = maxPlayers, humans = humans })
end

---@param entries PW.BotsEntry[]
---@return integer
local function countHumans(entries)
    local humans = 0
    for _, entry in ipairs(entries) do
        if not entry.bot and not entry.spectating then humans = humans + 1 end
    end
    return humans
end

function lib._Step(store, prefer)
    if idleReason(store) ~= nil then return 0, 0 end
    local entries = livePlayers(store)
    local n = store.teams()
    for _, entry in ipairs(entries) do
        if entry.bot then refreshBoard(store, entry, n) end
    end
    local plan = lib._Plan(targetFor(store, countHumans(entries)), entries, n, prefer)
    for _, ent in ipairs(plan.kick) do kickBot(store, ent, "bot quota") end
    return createBots(store, plan.create), #plan.kick
end

function lib._KickAll(store, reason)
    if idleReason(store, true) ~= nil then return 0 end
    local kicked = 0
    for _, entry in ipairs(livePlayers(store)) do
        if entry.bot then
            kickBot(store, entry.ent, reason)
            kicked = kicked + 1
        end
    end
    return kicked
end

function lib._OnHumanJoined(store)
    if idleReason(store) ~= nil then return 0, 0 end
    -- the joining human has no team yet, so the smallest team is the one the teams module will place them in
    return lib._Step(store, store.smallest())
end

function lib._OnPendingApplied(store, pending)
    if idleReason(store) ~= nil then return 0, 0 end
    local bots = tonumber(pending.bots)
    if bots ~= nil then store.pinned = math.max(0, math.floor(bots)) end
    return lib._Step(store)
end

function lib._OnPhase(store, phase)
    if phase ~= "PREMATCH" then store.pinned = nil end
    if phase ~= "LOBBY" then return end
    if store.resumeInLobby then
        store.paused = false
        store.resumeInLobby = false
    end
    lib._KickAll(store, "back to the lobby")
end

function lib._SetTestRun(store, running)
    if running then
        store.paused = true
        store.resumeInLobby = false
    elseif store.phase() == "LOBBY" then
        store.paused = false
        store.resumeInLobby = false
    else
        store.resumeInLobby = true
    end
end

function lib.Target(store)
    store = store or PW._BotsManager
    if idleReason(store) ~= nil then return 0 end
    return targetFor(store, countHumans(livePlayers(store)))
end

function lib.PendingTarget(settings)
    local store = PW._BotsManager
    local fill = tonumber(settings ~= nil and settings["bots.fill"] or nil) or store.fill()
    local humans = countHumans(livePlayers(store))
    return lib._Quota({ fill = math.floor(fill), maxPlayers = store.maxPlayers(), humans = humans })
end

local botLib = (rawget(PW, "Bot") or {}) --[[@as PW.BotLib]]
PW.Bot = botLib

function botLib.Get(bot)
    return PW._BotsManager.boards[bot]
end

local function mirrorTeams()
    local n = engineTeams()
    for key, board in pairs(PW._BotsManager.boards) do
        local ply = key --[[@as Player]]
        if IsValid(ply) then
            local index = ply:Team()
            board.team = index >= 1 and index <= n and index or nil
        end
    end
end

function MODULE:PW_PlayerTeamChanged() mirrorTeams() end
function MODULE:PW_RoundPrepared() mirrorTeams() end

---@param phase PW.PhaseName
function MODULE:PW_PhaseChange(phase)
    lib._OnPhase(PW._BotsManager, phase)
end

---@param pending PW.PendingMatch
function MODULE:PW_PendingMatchApplied(pending)
    lib._OnPendingApplied(PW._BotsManager, pending)
end

PW.HookFor(MODULE, "Think", function()
    local store = PW._BotsManager
    local now = store.clock()
    if now < store.nextStep then return end
    store.nextStep = now + lib._Interval
    lib._Step(store)
end)

---@param ply Player
PW.HookFor(MODULE, "PlayerInitialSpawn", function(_, ply)
    if ply:IsBot() then return end
    -- one tick later: the lobby module marks a join-in-progress spectator in its own PlayerInitialSpawn listener
    timer.Simple(0, function()
        if IsValid(ply) then lib._OnHumanJoined(PW._BotsManager) end
    end)
end)

-- A map that stays in LOBBY (no valid pending file) drops the bots that survived changelevel. The pending file is
-- applied one tick after InitPostEntity, so the check waits two seconds.
PW.HookFor(MODULE, "InitPostEntity", function()
    timer.Simple(2, function()
        local store = PW._BotsManager
        if store.phase() == "LOBBY" then lib._KickAll(store, "the map started in the lobby") end
    end)
end)

-- Plain hooks, not PW.HookFor: the pause must hold even if the module is disabled and enabled during the run.
hook.Add("GLuaTest_StartedTestRun", "PW.BotsManager", function() lib._SetTestRun(PW._BotsManager, true) end)
hook.Add("GLuaTest_Finished", "PW.BotsManager", function() lib._SetTestRun(PW._BotsManager, false) end)
