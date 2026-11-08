-- Bots perception (T-5.7; 07-bots.md d.7; DESIGN.md performance rules). Pure rules over plain data: the view cone,
-- the multi-point line of sight with a trace budget, the reaction queue, hearing ranges, the contact memory with its
-- 12 s decay, the search plan and the damage stimulus. The per-bot state, the stimuli and team sharing are in
-- sh_state.lua; the engine glue (traces, hooks, the scheduler tick) is in init.lua.
--
-- Decisions of the lane agent (to confirm):
--   1. Gameplay constants (Config, HearingRanges) are in code; the per-tier values are the bot_difficulties files
--      (T-5.12), read from the bot's board.difficulty (the regular tier when a board has none).
--   2. The reaction queue is the CS snapshot queue (notes/14): a snapshot of what was visible is pushed every
--      perception tick, the bot acts on the latest snapshot that is at least `delay` seconds old. The delay is the
--      difficulty's reaction time with a log-normal style jitter, re-rolled once a second, never below the floor.
--   3. Memory is 12 s fixed (07 d.7), whatever contact_memory of a difficulty says; time is the last sighting or
--      stimulus. A newer entry replaces an older one, an older one never replaces a newer one.
--   4. A damage stimulus reveals the direction and a bounded distance (at most 800 units) toward the attacker, not
--      the exact position of a distant attacker.
--   5. A heard position has an error of 10 percent of the distance.

MODULE.Name = "Bots perception"

local lib = (rawget(PW, "BotPerception") or {}) --[[@as PW.BotPerceptionLib]]
PW.BotPerception = lib

---@param ply Player
---@param now number
---@return boolean
function lib._FlashCanSee(ply, now)
    local status = rawget(PW, "Throwables") --[[@as PW.ThrowablesLib?]]
    return status == nil or status.Impairment == nil or status.Impairment(ply, now) <= 0.05
end

lib.Config = {
    fov = 110, -- total cone in degrees (awareViewAngle)
    sightRange = 4500, -- units
    memorySeconds = 12, -- 07 d.7
    maxTraces = 6, -- line-of-sight traces per bot per perception tick
    queueSeconds = 2, -- snapshots older than this are dropped; the reaction delay never exceeds it
    damageReveal = 800, -- units, the bound of the distance a damage stimulus reveals
    hearingError = 0.1, -- fraction of the distance
    searchAhead = 350, -- units, search point ahead along the velocity
    searchSide = 300, -- units, left and right
    searchFar = 800 -- units, far ahead
}

---Hearing range per sound kind, in units (1 m is about 52 units). A kind not listed is never heard.
lib.HearingRanges = {
    gunfire = 2500,
    gunfire_suppressed = 500,
    footstep = 450, -- sprinting players only; the glue filters
    explosion = 3500
}

---The difficulty fields perception reads (declared for the T-5.12 field test; the values live in bot_difficulties/).
local fields = { "reaction_mean", "reaction_floor", "reaction_jitter", "share_delay", "share_radius", "fov" }
PW.BotProfiles.Reads("difficulty", "perception", fields)

local epsilon = 1e-9
lib._KnownRadarSources = lib._KnownRadarSources or setmetatable({}, { __mode = "k" })
lib._RetiredRadarSources = lib._RetiredRadarSources or setmetatable({}, { __mode = "k" })

---Parameters for a bot: the fields of its difficulty, the tier's (regular by default) for a field it lacks.
---@param difficulty table?
---@param tier string?
---@return PW.BotPerceptionParams
function lib.ParamsFor(difficulty, tier)
    return PW.BotProfiles.Pick(fields, difficulty, tier) --[[@as PW.BotPerceptionParams]]
end

---Whether point is inside the view cone. forward is the unit view direction, fov the total angle in degrees.
---@param eye Vector
---@param forward Vector
---@param point Vector
---@param fov number
---@return boolean
function lib.InFOV(eye, forward, point, fov)
    local delta = point - eye
    local length = delta:Length()
    if length < 1 then return true end
    return delta:Dot(forward) / length >= math.cos(math.rad(fov * 0.5))
end

---Sight check of one candidate: range, then the cone on its centre, then up to the trace budget over its body points
---(head, chest, feet). A candidate outside the range or the cone costs no trace.
---@param ctx PW.BotSightCtx
---@param cand PW.BotCandidate
---@return boolean
function lib.Visible(ctx, cand)
    if cand.center:DistToSqr(ctx.eye) > ctx.range * ctx.range then return false end
    if not lib.InFOV(ctx.eye, ctx.forward, cand.center, ctx.fov) then return false end
    for _, point in ipairs(cand.points) do
        if ctx.budget.left <= 0 then return false end
        ctx.budget.left = ctx.budget.left - 1
        if ctx.los(point, cand) then return true end
    end
    return false
end

---@param kind string
---@return number units, 0 for a kind that is never heard
function lib.HearingRange(kind)
    return lib.HearingRanges[kind] or 0
end

---Hearing within range only, no map-wide hearing (07 d.7); there is no cone for sound.
---@param kind string
---@param ear Vector
---@param source Vector
---@return boolean
function lib.CanHear(kind, ear, source)
    local range = lib.HearingRange(kind)
    return range > 0 and ear:DistToSqr(source) <= range * range
end

---The position the listener believes the sound came from: the source with an error of a tenth of the distance.
---@param pos Vector
---@param ear Vector
---@param random PW.BotRandomFn?
---@return Vector
function lib.HeardPosition(pos, ear, random)
    if random == nil then return pos end
    local radius = pos:Distance(ear) * lib.Config.hearingError * random()
    local angle = math.pi * 2 * random()
    return pos + Vector(math.cos(angle) * radius, math.sin(angle) * radius, 0)
end

---The reaction time of a bot: the mean with a jitter, never below the floor nor above the queue length.
---@param params PW.BotPerceptionParams
---@param random PW.BotRandomFn?
---@return number
function lib.ReactionDelay(params, random)
    local delay = params.reaction_mean
    if random ~= nil then delay = delay * math.exp(params.reaction_jitter * (random() * 2 - 1)) end
    delay = math.max(delay, params.reaction_floor)
    return math.min(delay, lib.Config.queueSeconds - 0.1)
end

---@return PW.BotReactionQueue
function lib.NewQueue()
    return { snaps = {} }
end

---Pushes what is visible now; snapshots older than queueSeconds are dropped.
---@param queue PW.BotReactionQueue
---@param now number
---@param seen PW.BotSnapshotSet
function lib.QueuePush(queue, now, seen)
    local snaps = queue.snaps
    snaps[#snaps + 1] = { time = now, seen = seen }
    local oldest = now - lib.Config.queueSeconds
    local first = 1
    while first < #snaps and snaps[first].time < oldest do first = first + 1 end
    if first == 1 then return end
    local count = #snaps
    for i = first, count do snaps[i - first + 1] = snaps[i] end
    for i = count - first + 2, count do snaps[i] = nil end
end

---The latest snapshot that is at least delay seconds old: what the bot recognises now. Empty when none is old enough.
---@param queue PW.BotReactionQueue
---@param now number
---@param delay number
---@return PW.BotSnapshotSet
function lib.QueueRecognised(queue, now, delay)
    local limit = now - delay + epsilon
    local snaps = queue.snaps
    for i = #snaps, 1, -1 do
        if snaps[i].time <= limit then return snaps[i].seen end
    end
    return {}
end

---Stores or refreshes a contact. An older entry never replaces a newer one; the velocity is kept when the new one
---has none.
---@param ent any
---@param c table pos, time, source, and optionally vel, visible, dir
---@param old PW.BotContact?
---@return PW.BotContact
local function observation(ent, c, old)
    ---@type PW.BotContact
    local entry = {
        ent = ent, pos = c.pos, vel = c.vel or (old and old.vel) or Vector(0, 0, 0), time = c.time,
        visible = c.visible == true, source = c.source, dir = c.dir,
        sourceToken = c.sourceToken, expiresAt = c.expiresAt
    }
    return entry
end

---@param memory table<any, PW.BotContact>
---@param ent any
---@param view PW.BotContact
---@param now number
---@param seconds number
---@return PW.BotContact?
local function radarView(memory, ent, view, now, seconds)
    local radar, observed = assert(view.radar), view.observed
    if observed ~= nil and now - observed.time > seconds then observed = nil end
    local best = observed
    for i = #radar, 1, -1 do
        local c = radar[i]
        if now - c.time > seconds or (c.expiresAt ~= nil and c.expiresAt <= now)
            or (c.sourceToken ~= nil and lib._RetiredRadarSources[c.sourceToken]) then table.remove(radar, i)
        elseif best == nil or c.time > best.time then best = c end
    end
    if #radar == 0 then memory[ent] = observed return observed end
    if best == nil then memory[ent] = nil return nil end
    view.pos, view.vel, view.time, view.visible = best.pos, best.vel, best.time, best.visible
    view.source, view.dir = best.source, best.dir
    view.sourceToken, view.expiresAt, view.observed = best.sourceToken, best.expiresAt, observed
    return view
end

---@param memory table<any, PW.BotContact>
---@param ent any
---@param c table
---@return PW.BotContact
local function rememberRadar(memory, ent, c)
    local old = memory[ent]
    local view = old ~= nil and old.radar ~= nil and old or observation(ent, c, old)
    if view.radar == nil then view.radar, view.observed = {}, old end
    local radar = assert(view.radar)
    local entry = observation(ent, c, old)
    entry.pos, entry.vel = Vector(entry.pos.x, entry.pos.y, entry.pos.z), Vector(entry.vel.x, entry.vel.y, entry.vel.z)
    local replaced = false
    for i, previous in ipairs(radar) do
        if previous.sourceToken == c.sourceToken then
            if previous.time <= entry.time then radar[i] = entry end
            replaced = true
            break
        end
    end
    if not replaced then
        if #radar >= 128 then table.remove(radar, 1) end
        radar[#radar + 1] = entry
    end
    memory[ent] = view
    return radarView(memory, ent, view, c.now or c.time, lib.Config.memorySeconds) or entry
end

---@param memory table<any, PW.BotContact>
---@param ent any
---@param c table
---@return PW.BotContact
function lib.Remember(memory, ent, c)
    if c.source == "radar" then return rememberRadar(memory, ent, c) end
    local old = memory[ent]
    if old ~= nil and old.radar ~= nil then
        if old.observed == nil or old.observed.time <= c.time then old.observed = observation(ent, c, old.observed) end
        return radarView(memory, ent, old, c.now or c.time, lib.Config.memorySeconds) or observation(ent, c, nil)
    end
    if old ~= nil and old.time > c.time then return old end
    local entry = observation(ent, c, old)
    memory[ent] = entry
    return entry
end

---Forgets contacts older than seconds (default 12) and those whose entity is no longer valid; returns the count.
---@param memory table<any, PW.BotContact>
---@param now number
---@param seconds number?
---@param valid PW.BotValidFn?
---@return integer
function lib.Decay(memory, now, seconds, valid)
    local limit = seconds or lib.Config.memorySeconds
    local removed = 0
    for ent, contact in pairs(memory) do
        if valid ~= nil and not valid(ent) then
            memory[ent] = nil
            removed = removed + 1
        elseif contact.radar ~= nil then
            if radarView(memory, ent, contact, now, limit) == nil then removed = removed + 1 end
        elseif now - contact.time > limit then
            memory[ent], removed = nil, removed + 1
        end
    end
    return removed
end

---@param v Vector
---@return Vector flat unit vector, or the zero vector when v has no horizontal part
local function flatUnit(v)
    local flat = Vector(v.x, v.y, 0)
    if flat:LengthSqr() < 1 then return flat end
    flat:Normalize()
    return flat
end

---The 5 search points around a lost contact (07 d.7): last seen, ahead along the velocity, left, right, far ahead.
---opts.facing: direction to use when the contact stood still; opts.project(pos) -> Vector?: snaps a point to the
---navmesh, a nil answer keeps the point (the plan always has 5 points).
---@param contact PW.BotContact
---@param opts { facing: Vector?, project: (fun(pos: Vector): Vector?)? }?
---@return Vector[]
function lib.SearchPlan(contact, opts)
    local options = opts or {}
    local cfg = lib.Config
    local ahead = flatUnit(contact.vel)
    if ahead:LengthSqr() < 0.5 and options.facing ~= nil then ahead = flatUnit(options.facing) end
    if ahead:LengthSqr() < 0.5 then ahead = Vector(1, 0, 0) end
    local right = ahead:Cross(Vector(0, 0, 1))
    local last = contact.pos
    local plan = {
        last, last + ahead * cfg.searchAhead, last - right * cfg.searchSide, last + right * cfg.searchSide,
        last + ahead * cfg.searchFar
    }
    local project = options.project
    if project == nil then return plan end
    for i, point in ipairs(plan) do plan[i] = project(point) or point end
    return plan
end

---The damage stimulus: the attacker is revealed in direction, at a bounded distance (decision 4).
---@param victimEye Vector
---@param attacker any
---@param attackerPos Vector
---@return PW.BotStimulusData
function lib.DamageStimulus(victimEye, attacker, attackerPos)
    local delta = attackerPos - victimEye
    local length = delta:Length()
    if length < 1 then return { ent = attacker, pos = attackerPos } end
    local dir = delta / length
    return { ent = attacker, pos = victimEye + dir * math.min(length, lib.Config.damageReveal), dir = dir }
end

if SERVER then AddCSLuaFile("privatewar/modules/bots_perception/sh_state.lua") end
include("privatewar/modules/bots_perception/sh_state.lua")
