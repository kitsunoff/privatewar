-- Bots perception, server glue (T-5.7). Thin wrappers around the pure rules in shared.lua and sh_state.lua: the
-- candidate enemies (player.Iterator, no ents.Find*), the line-of-sight traces, the scheduler tick per bot, the
-- sound and damage hooks, and the blackboard writes (contacts, memory, debug.perception).
--
-- Decisions of the lane agent (to confirm):
--  10. Every managed bot is registered in the bot scheduler at 10 Hz under the id "perception:<UserID>" (so it
--      never clashes with the ids of the other layers); a bot that is gone or no longer managed unregisters itself.
--  11. Candidates are the living enemies from player.Iterator, nearest first, in the view cone, within the sight
--      range; at most Config.maxTraces traces per tick over head, chest and feet. Dead and observing players are no
--      candidates. A bot that is dead forgets everything.
--  12. Sounds: gunfire from EntityFireBullets (a weapon flagged PW_Suppressed, Silenced or GetSilenced() is
--      "gunfire_suppressed"), footsteps from PlayerFootstep only while the player sprints, explosions from
--      EntityEmitSound when the sound name contains "explo" and the emitter has a player owner (the stimulus is about
--      the owner). Damage from PostEntityTakeDamage. Only enemies (PW.IsEnemy) are heard.
--  13. Randomness: math.random until the core has its own AI PRNG (adapter.md rule 4); one place, randomFn below.

local lib = PW.BotPerception

local tickPeriod = 0.1
local syncEvery = 1
local bodyHeights = { chest = 40, feet = 8 }
local mask = MASK_OPAQUE_AND_NPCS

local function randomFn()
    return math.random()
end

local botLib = (rawget(PW, "Bot") or {}) --[[@as PW.BotLib]]
PW.Bot = botLib

function botLib.AddStimulus(botOrTeam, kind, data)
    return lib.Dispatch(botOrTeam, kind, data)
end

---@param a Player
---@param b Player
---@return boolean
local function isEnemy(a, b)
    local fn = rawget(PW, "IsEnemy") --[[@as (fun(a: any, b: any): boolean)?]]
    if fn ~= nil then return fn(a, b) == true end
    return a ~= b and a:Team() ~= b:Team()
end

---@param board PW.BotBoard
---@return PW.BotPerceptionParams
local function paramsOf(board)
    local tier = PW.Setting("bots.difficulty")
    return lib.ParamsFor(board.difficulty, isstring(tier) and tier or nil)
end

---@type fun(): (fun(): integer?, Player?)
local players = player.Iterator

---@type { mask: integer, filter: Entity[], start: Vector?, endpos: Vector? }
local trace = { mask = mask, filter = {} }

---One line-of-sight trace from the bot's eyes to a point of the candidate.
---@param ply Player
---@return fun(point: Vector, cand: PW.BotCandidate): boolean
local function losFor(ply)
    local eye = ply:EyePos()
    return function(point, cand)
        trace.start, trace.endpos = eye, point
        trace.filter[1], trace.filter[2] = ply, cand.ent --[[@as Entity]]
        return util.TraceLine(trace).Fraction >= 1
    end
end

---The living enemy as a sight candidate, or nil when it is outside the cone and the range (no points are built).
---@param other Player
---@param eye Vector
---@param forward Vector
---@param params PW.BotPerceptionParams
---@return PW.BotCandidate?
local function candidateOf(other, eye, forward, params)
    local center = other:WorldSpaceCenter()
    local range = lib.Config.sightRange
    if center:DistToSqr(eye) > range * range or not lib.InFOV(eye, forward, center, params.fov) then return nil end
    local origin = other:GetPos()
    return {
        ent = other, center = center, vel = other:GetVelocity(), dist = center:DistToSqr(eye),
        points = { other:EyePos(), origin + Vector(0, 0, bodyHeights.chest), origin + Vector(0, 0, bodyHeights.feet) }
    }
end

---The enemies the bot can see right now, as a snapshot set; nearest candidates get the traces first.
---@param ply Player
---@param params PW.BotPerceptionParams
---@return PW.BotSnapshotSet seen
---@return integer candidates
---@return integer traces
local function gatherSeen(ply, params)
    local eye, forward = ply:EyePos(), ply:EyeAngles():Forward()
    ---@type PW.BotCandidate[]
    local list = {}
    for _, entry in players() do
        local other = entry --[[@as Player]]
        if other ~= ply and other:Alive() and other:GetObserverMode() == OBS_MODE_NONE and isEnemy(ply, other) then
            local cand = candidateOf(other, eye, forward, params)
            if cand ~= nil then list[#list + 1] = cand end
        end
    end
    table.sort(list, function(a, b) return (a.dist or 0) < (b.dist or 0) end)
    local budget = { left = lib.Config.maxTraces }
    ---@type PW.BotSightCtx
    local ctx = { eye = eye, forward = forward, fov = params.fov, range = lib.Config.sightRange, los = losFor(ply),
        budget = budget }
    ---@type PW.BotSnapshotSet
    local seen = {}
    for _, cand in ipairs(list) do
        if lib.Visible(ctx, cand) then seen[cand.ent] = { pos = cand.center, vel = cand.vel } end
    end
    return seen, #list, lib.Config.maxTraces - budget.left
end

---Teammates that may receive a sharing (living bots with a state).
---@return PW.BotMate[]
local function mates()
    ---@type PW.BotMate[]
    local list = {}
    for bot, state in pairs(lib.States) do
        local board = IsValid(bot) and botLib.Get(bot) or nil
        if board ~= nil and bot:Alive() then
            list[#list + 1] = { state = state, team = state.team, pos = bot:GetPos(), params = paramsOf(board) }
        end
    end
    return list
end

---@param board PW.BotBoard
---@param candidates integer
---@param traces integer
local function writeDebug(board, candidates, traces)
    local debugInfo = (board.debug or {}) --[[@as table<string, any>]]
    board.debug = debugInfo
    local info = (debugInfo.perception or {}) --[[@as table<string, integer>]]
    info.candidates, info.traces = candidates, traces
    debugInfo.perception = info
end

---One perception tick of a bot.
---@param ply Player
---@param board PW.BotBoard
---@param now number
local function tickBot(ply, board, now)
    local state = lib.States[ply] or lib.NewState()
    lib.States[ply] = state
    state.team = board.team
    if not ply:Alive() then
        lib.Clear(state)
    else
        local params = paramsOf(board)
        local seen, candidates, traces = gatherSeen(ply, params)
        local fresh = lib.Think(state, { params = params, seen = seen, valid = IsValid, random = randomFn }, now)
        for _, sighting in ipairs(fresh) do
            lib.Share({ state = state, team = state.team, pos = ply:GetPos() }, mates(), sighting, now)
        end
        writeDebug(board, candidates, traces)
    end
    board.contacts, board.memory = state.contacts, state.memory
end

---@type table<Player, string>
local registered = setmetatable({}, { __mode = "k" })

---@param ply Player
local function register(ply)
    local scheduler = rawget(PW, "BotScheduler") --[[@as PW.BotSchedulerLib?]]
    if scheduler == nil then return end
    local id = "perception:" .. ply:UserID()
    registered[ply] = id
    -- The scheduler passes its own clock (SysTime); contacts are timed with CurTime like the stimuli.
    scheduler.Register(id, function()
        local now = CurTime()
        local board = IsValid(ply) and botLib.Get(ply) or nil
        if board == nil then
            scheduler.Unregister(id)
            registered[ply], lib.States[ply] = nil, nil
            return
        end
        tickBot(ply, board, now)
    end, { period = tickPeriod })
end

local nextSync = 0

PW.HookFor(MODULE, "Think", function()
    local now = CurTime()
    if now < nextSync or botLib.Get == nil then return end
    nextSync = now + syncEvery
    for _, entry in players() do
        local ply = entry --[[@as Player]]
        if ply:IsBot() and registered[ply] == nil and botLib.Get(ply) ~= nil then register(ply) end
    end
end)

---Sends a sound to the bots of the enemies of the source that can hear it.
---@param kind string
---@param pos Vector
---@param source Player
local function broadcast(kind, pos, source)
    ---@type PW.BotListener[]
    local ears = {}
    for key, state in pairs(lib.States) do
        local bot = key --[[@as Player]]
        if IsValid(bot) and bot ~= source and bot:Alive() and isEnemy(bot, source) then
            local ear = bot:EyePos()
            if lib.CanHear(kind, ear, pos) then ears[#ears + 1] = { key = bot, state = state, ear = ear } end
        end
    end
    lib.HearSound(ears, kind, pos, source, randomFn)
end

---@param wep Weapon
---@return boolean
local function isSuppressed(wep)
    local flagged = (wep --[[@as table]]).PW_Suppressed == true or (wep --[[@as table]]).Silenced == true
    if flagged then return true end
    local fn = (wep --[[@as table<string, any>]]).GetSilenced
    return isfunction(fn) and fn(wep) == true
end

---@param ent any
---@return Player?
local function playerOf(ent)
    if not IsValid(ent) then return nil end
    local e = ent --[[@as Entity]]
    local owner = e:IsPlayer() and e or e:GetOwner()
    if IsValid(owner) and owner:IsPlayer() then return owner --[[@as Player]] end
    return nil
end

PW.HookFor(MODULE, "EntityFireBullets", function(_, ent, data)
    local shooter = playerOf(ent)
    if shooter == nil then return end
    local wep = shooter:GetActiveWeapon()
    local suppressed = IsValid(wep) and isSuppressed(wep)
    broadcast(suppressed and "gunfire_suppressed" or "gunfire", (data --[[@as table<string, Vector>]]).Src, shooter)
end)

PW.HookFor(MODULE, "PlayerFootstep", function(_, plyArg)
    local ply = plyArg --[[@as Player]]
    if not ply:IsSprinting() or ply:GetVelocity():Length2DSqr() <= 150 * 150 then return end
    broadcast("footstep", ply:GetPos(), ply)
end)

---@type table<string, boolean>
local explosionSounds = {}

PW.HookFor(MODULE, "EntityEmitSound", function(_, dataArg)
    local data = dataArg --[[@as table<string, any>]]
    local name = data.SoundName
    if not isstring(name) then return end
    local known = explosionSounds[name]
    if known == nil then
        known = string.find(string.lower(name), "explo", 1, true) ~= nil
        explosionSounds[name] = known
    end
    local owner = known and playerOf(data.Entity) or nil
    if owner == nil then return end
    broadcast("explosion", data.Pos or (data.Entity --[[@as Entity]]):GetPos(), owner)
end)

PW.HookFor(MODULE, "PostEntityTakeDamage", function(_, victimArg, dmgArg, took)
    local victim = victimArg --[[@as Entity]]
    local state = took and lib.States[victim] or nil
    if state == nil or not IsValid(victim) then return end
    local attacker = playerOf((dmgArg --[[@as CTakeDamageInfo]]):GetAttacker())
    if attacker == nil or attacker == victim or not isEnemy(victim --[[@as Player]], attacker) then return end
    local stim = lib.DamageStimulus(victim:EyePos(), attacker, attacker:WorldSpaceCenter())
    stim.time = CurTime()
    lib.AddStimulus(state, "damage", stim)
end)

function botLib.GetSearchPlan(bot, ent)
    local state = lib.States[bot]
    if state == nil then return nil end
    local lost = ent ~= nil and state.memory[ent] or nil
    if lost == nil then
        for _, contact in ipairs(state.contacts) do
            if not contact.visible then lost = contact break end
        end
    end
    if lost == nil then return nil end
    local function project(pos)
        local area = navmesh.GetNearestNavArea(pos, false, 300, false, true)
        return area ~= nil and area:GetClosestPointOnArea(pos) or nil
    end
    local facing = IsValid(bot) and (bot --[[@as Player]]):EyeAngles():Forward() or nil
    return lib.SearchPlan(lost, { facing = facing, project = project })
end
