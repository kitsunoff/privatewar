-- Bots perception, the per-bot state (T-5.7; included by shared.lua, see the decisions there). Plain data: the
-- reaction queue, the contact memory, the contacts list, pending team sharing; the stimulus entry points
-- (AddStimulus, sounds, Dispatch for PW.Bot.AddStimulus) and the perception step Think.
--
-- Decisions of the lane agent (to confirm):
--   6. Stimulus kinds: "gunfire", "gunfire_suppressed", "footstep", "explosion" (sound, filtered by hearing range),
--      "damage" (direction of the attacker), "shared" (team sharing), and any other string a module chooses (for
--      example "radar" for a UAV): it becomes the contact's `source` and is not filtered by range.
--   7. The data of a stimulus is { ent, pos, vel?, time?, dir? }. `ent` (the enemy it is about) is required: memory is
--      keyed by entity. A stimulus about an entity that is not an enemy of the bot (PW.IsEnemy) is dropped.
--   8. Team sharing: a sighting recognised through the reaction queue is offered to teammates once a second per enemy;
--      the receiver gets it after its own share_delay, within its share_radius of the sharer, as a position
--      (source "shared", not visible): it still has to see the enemy itself before aim fires.
--   9. contacts = every memory entry, the seen first, then the newest. The search plan is not a blackboard field:
--      PW.Bot.GetSearchPlan(bot) computes it from the freshest lost contact.
--  10. No snapshot is jumped over: a tick recognises the latest snapshot old enough (decision 2) plus every enemy of
--      the snapshots that became old enough since the previous tick. With only the latest one, a glimpse of one
--      perception tick was lost whenever a tick came late or the delay was re-rolled, and a bot that turned away
--      right after seeing an enemy never noticed it (lua/tests/privatewar/bots_engagement.lua).

local lib = PW.BotPerception

local sharedEvery = 1 -- seconds between two sharings of the same enemy by one bot
local pendingCap = 32
local zero = Vector(0, 0, 0)

---@type table<any, PW.BotPerceptionState>
lib.States = lib.States or setmetatable({}, { __mode = "k" })

---@return PW.BotPerceptionState
function lib.NewState()
    return { queue = lib.NewQueue(), memory = {}, contacts = {}, pending = {}, sharedAt = {}, delayAt = -math.huge }
end

---Forgets everything (the bot died or the round restarted).
---@param state PW.BotPerceptionState
function lib.Clear(state)
    state.queue, state.memory, state.contacts = lib.NewQueue(), {}, {}
    state.pending, state.sharedAt, state.delay, state.delayAt = {}, {}, nil, -math.huge
    state.recognisedTo = nil
end

---Puts a stimulus into the memory of a state; false when it lacks the entity or the position.
---@param state PW.BotPerceptionState
---@param kind string
---@param data PW.BotStimulusData
---@return boolean
function lib.AddStimulus(state, kind, data)
    if not istable(data) or data.ent == nil or not isvector(data.pos) then return false end
    lib.Remember(state.memory, data.ent, {
        pos = data.pos, vel = data.vel, time = data.time or CurTime(), source = kind, visible = false, dir = data.dir
    })
    return true
end

---The states a stimulus is for: one bot, or every bot of a team (a number).
---@param botOrTeam any
---@return { key: any, state: PW.BotPerceptionState }[]
local function targets(botOrTeam)
    ---@type { key: any, state: PW.BotPerceptionState }[]
    local list = {}
    if isnumber(botOrTeam) then
        for bot, state in pairs(lib.States) do
            if state.team == botOrTeam then list[#list + 1] = { key = bot, state = state } end
        end
    elseif botOrTeam ~= nil and lib.States[botOrTeam] ~= nil then
        list[1] = { key = botOrTeam, state = lib.States[botOrTeam] }
    end
    return list
end

---Whether ent is an enemy of the bot; plain stand-ins (not entities) pass, so the pure cases need no teams.
---@param bot any
---@param ent any
---@return boolean
local function isEnemy(bot, ent)
    local isEnemyFn = rawget(PW, "IsEnemy") --[[@as (fun(a: any, b: any): boolean)?]]
    if isEnemyFn == nil or not isentity(bot) or not isentity(ent) then return true end
    return isEnemyFn(bot, ent) == true
end

---PW.Bot.AddStimulus: the stimulus goes to a bot or to every bot of a team; returns how many bots got it. A table in
---place of the kind is the stimulus itself with its kind in `kind`. Never errors on bad input.
---@param botOrTeam any
---@param kind any
---@param data any
---@return integer
function lib.Dispatch(botOrTeam, kind, data)
    if istable(kind) and data == nil then
        local whole = kind --[[@as table<string, any>]]
        kind, data = whole.kind, whole
    end
    if not isstring(kind) or not istable(data) then return 0 end
    local stimulus = data --[[@as PW.BotStimulusData]]
    if kind == "footstep" and PW.Perks ~= nil and IsValid(stimulus.ent)
        and not PW.Perks.FootstepsAudible(stimulus.ent --[[@as Player]]) then return 0 end
    local fed = 0
    for _, target in ipairs(targets(botOrTeam)) do
        if isEnemy(target.key, stimulus.ent) and lib.AddStimulus(target.state, kind, stimulus) then
            fed = fed + 1
        end
    end
    return fed
end

---A sound reaches the listeners within its hearing range (never the source's own ears), at an uncertain position.
---@param listeners PW.BotListener[]
---@param kind string
---@param pos Vector
---@param source any
---@param random PW.BotRandomFn?
---@return integer heard
function lib.HearSound(listeners, kind, pos, source, random)
    if kind == "footstep" and PW.Perks ~= nil and IsValid(source)
        and not PW.Perks.FootstepsAudible(source) then return 0 end
    local heard = 0
    for _, listener in ipairs(listeners) do
        if listener.key ~= source and lib.CanHear(kind, listener.ear, pos) then
            heard = heard + 1
            lib.AddStimulus(listener.state, kind, {
                ent = source, pos = lib.HeardPosition(pos, listener.ear, random), vel = zero
            })
        end
    end
    return heard
end

---Offers a recognised sighting to the teammates in range; returns how many will get it (decision 8).
---@param sender PW.BotSender
---@param mates PW.BotMate[]
---@param contact PW.BotSighting
---@param now number
---@return integer
function lib.Share(sender, mates, contact, now)
    local sent = 0
    for _, mate in ipairs(mates) do
        local params = mate.params
        if mate.state ~= sender.state and mate.team == sender.team
            and mate.pos:DistToSqr(sender.pos) <= params.share_radius * params.share_radius then
            local pending = mate.state.pending
            if #pending >= pendingCap then table.remove(pending, 1) end
            pending[#pending + 1] = {
                at = now + params.share_delay, ent = contact.ent, pos = contact.pos, vel = contact.vel,
                time = contact.time
            }
            sent = sent + 1
        end
    end
    return sent
end

---Delivers the shared contacts that are due.
---@param state PW.BotPerceptionState
---@param now number
local function deliverPending(state, now)
    ---@type PW.BotPending[]
    local keep = {}
    for _, message in ipairs(state.pending) do
        if message.at <= now then
            lib.Remember(state.memory, message.ent,
                { pos = message.pos, vel = message.vel, time = message.time, source = "shared", visible = false })
        else
            keep[#keep + 1] = message
        end
    end
    state.pending = keep
end

---Re-rolls the reaction delay about once a second (a delay that changed every tick would flicker).
---@param state PW.BotPerceptionState
---@param ctx PW.BotThinkCtx
---@param now number
local function rollDelay(state, ctx, now)
    if state.delay == nil or now - state.delayAt >= 1 then
        state.delay = lib.ReactionDelay(ctx.params, ctx.random)
        state.delayAt = now
    end
end

---@param set PW.BotSnapshotSet
---@return PW.BotSnapshotSet
local function shallowCopy(set)
    ---@type PW.BotSnapshotSet
    local copy = {}
    for key, value in pairs(set) do copy[key] = value end
    return copy
end

---Adds the enemies of extra that base lacks; copies base on the first addition (merged is that copy, or nil).
---@param merged PW.BotSnapshotSet?
---@param base PW.BotSnapshotSet
---@param extra PW.BotSnapshotSet
---@return PW.BotSnapshotSet?
local function addMissing(merged, base, extra)
    for ent, data in pairs(extra) do
        if (merged or base)[ent] == nil then
            merged = merged or shallowCopy(base)
            merged[ent] = data
        end
    end
    return merged
end

---What the bot recognises now (decision 10): the latest snapshot at least the delay old, plus the enemies of the
---snapshots that became old enough since the previous tick. Snapshot tables are never modified.
---@param state PW.BotPerceptionState
---@param now number
---@return PW.BotSnapshotSet
local function recognise(state, now)
    local delay = state.delay or 0
    local seen = lib.QueueRecognised(state.queue, now, delay)
    local from, limit = state.recognisedTo, now - delay + 1e-9
    state.recognisedTo = math.max(from or -math.huge, limit)
    if from == nil then return seen end
    ---@type PW.BotSnapshotSet?
    local merged = nil
    for _, snap in ipairs(state.queue.snaps) do
        if snap.time > from and snap.time <= limit then merged = addMissing(merged, seen, snap.seen) end
    end
    return merged or seen
end

---Contacts of memory: the seen first, then the newest.
---@param memory table<any, PW.BotContact>
---@return PW.BotContact[]
local function contactList(memory)
    ---@type PW.BotContact[]
    local list = {}
    for _, contact in pairs(memory) do list[#list + 1] = contact end
    table.sort(list, function(a, b)
        if a.visible ~= b.visible then return a.visible end
        return a.time > b.time
    end)
    return list
end

---One perception step at time now: pushes the snapshot of what is visible, recognises through the reaction queue,
---delivers due shared contacts, decays the memory and rebuilds the contacts. Returns the sightings that were
---recognised and are due for sharing.
---@param state PW.BotPerceptionState
---@param ctx PW.BotThinkCtx
---@param now number
---@return PW.BotSighting[]
function lib.Think(state, ctx, now)
    rollDelay(state, ctx, now)
    lib.QueuePush(state.queue, now, ctx.seen or {})
    for _, contact in pairs(state.memory) do contact.visible = false end
    deliverPending(state, now)
    ---@type PW.BotSighting[]
    local fresh = {}
    for ent, snap in pairs(recognise(state, now)) do
        if ctx.valid == nil or ctx.valid(ent) then
            lib.Remember(state.memory, ent, { pos = snap.pos, vel = snap.vel, time = now, source = "sight",
                visible = true })
            local last = state.sharedAt[ent]
            if last == nil or now - last >= sharedEvery then
                state.sharedAt[ent] = now
                fresh[#fresh + 1] = { ent = ent, pos = snap.pos, vel = snap.vel, time = now }
            end
        end
    end
    lib.Decay(state.memory, now, nil, ctx.valid)
    for ent, at in pairs(state.sharedAt) do
        if now - at > lib.Config.memorySeconds then state.sharedAt[ent] = nil end
    end
    state.contacts = contactList(state.memory)
    return fresh
end
