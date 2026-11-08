local hp = assert(PW.Hardpoint)
include("privatewar/modules/hardpoint/sv_activation.lua")
include("privatewar/modules/hardpoint/sv_net.lua")
---@type fun(): (fun(): integer?, Player?)
local players = player.Iterator

---@param runtime PW.HardpointRuntime
local function invalidate(runtime)
    if runtime.invalidated then return end
    runtime.invalidated = true
    -- The commander consumes this notification through its public invalidation helper; the brain can end its frame.
    PW.Notify("PW_ObjectiveInvalidated", runtime.objectiveId, runtime.objectiveRevision)
end

---@param runtime PW.HardpointRuntime
local function identity(runtime)
    runtime.objectiveId = "hp_" .. runtime.state.generation .. "_" .. runtime.state.visit
    runtime.objectiveRevision = runtime.state.visit
    runtime.invalidated = false
end

---@param runtime PW.HardpointRuntime
local function publish(runtime)
    local state = runtime.state
    runtime.revision = runtime.revision + 1
    hp.Send(hp.PublicSnapshot(state, runtime.revision))
    SetGlobal2Int("pw_hp_score_1", state.scores[1])
    SetGlobal2Int("pw_hp_score_2", state.scores[2])
    runtime.lastControl, runtime.lastContested = state.control, state.contested
    runtime.lastFirst, runtime.lastSecond = state.scores[1], state.scores[2]
end

function hp.Start(mode)
    hp.Cleanup(mode)
    local data = assert(PW.Map, "Map module unavailable").GetModeData(mode.ClassName)
    local valid, reason = hp.ValidateLayout(data)
    assert(valid, reason)
    local layout = data --[[@as PW.HardpointLayout]]
    valid, reason = hp.CheckActivation(layout)
    assert(valid, reason)
    local generation = GetGlobal2Int("pw_hp_generation", 0) + 1
    SetGlobal2Int("pw_hp_generation", generation)
    local now = CurTime()
    local state = hp.NewState(layout, { pointTime = tonumber(mode:Setting("zonetime")) or 60,
        scoreLimit = tonumber(mode:Setting("scorelimit")) or 250,
        matchTime = tonumber(mode:Setting("timelimit")) or 600 }, now, generation)
    ---@type PW.HardpointActor[]
    local actors = {}
    -- Warm reusable actor records once; Iterator below never allocates player-list tables.
    for index = 1, game.MaxPlayers() do
        actors[index] = { team = 0, pos = Vector(), alive = false, observer = false, eligible = false }
    end
    local runtime = { state = state, revision = 0, nextSample = now, actors = actors,
        sample = { at = now, actors = actors }, objectiveId = "", objectiveRevision = 0, invalidated = false,
        lastControl = 0, lastContested = false, lastFirst = 0, lastSecond = 0 }
    mode._Hardpoint = runtime
    identity(runtime)
    SetGlobal2Float(assert(PW.MatchRules)._EndsKey, state.matchEndsAt)
    publish(runtime)
end

---@param runtime PW.HardpointRuntime
local function sampleActors(runtime)
    local count = 0
    for _, ply in players() do
        count = count + 1
        local actor = runtime.actors[count]
        actor.team, actor.pos, actor.alive = ply:Team(), ply:GetPos(), ply:Alive()
        actor.observer = ply:GetObserverMode() ~= OBS_MODE_NONE or ply:GetNW2Bool("pw_spectating", false)
        actor.eligible = actor.team == 1 or actor.team == 2
    end
    for index = count + 1, #runtime.actors do runtime.actors[index].eligible = false end
end

function hp.Think(mode)
    local runtime = mode._Hardpoint
    if runtime == nil or runtime.state.finished then return end
    local now = CurTime()
    if now < runtime.nextSample then return end
    runtime.nextSample, runtime.sample.at = now + 0.1, now
    sampleActors(runtime)
    local effects = hp.Step(runtime.state, runtime.sample)
    if effects.rotated or effects.finish ~= nil then invalidate(runtime) end
    if effects.rotated then identity(runtime) end
    local state = runtime.state
    if effects.rotated or effects.finish ~= nil or state.control ~= runtime.lastControl
        or state.contested ~= runtime.lastContested or state.scores[1] ~= runtime.lastFirst
        or state.scores[2] ~= runtime.lastSecond then publish(runtime) end
    if effects.finish ~= nil then
        assert(PW.Match).Finish(effects.finish)
    end
end

function hp.Cleanup(mode)
    local runtime = mode._Hardpoint
    if runtime == nil then return end
    invalidate(runtime)
    runtime.state.finished = true
    publish(runtime)
    mode._Hardpoint = nil
    SetGlobal2Float(assert(PW.MatchRules)._EndsKey, -1)
    SetGlobal2Int("pw_hp_score_1", 0)
    SetGlobal2Int("pw_hp_score_2", 0)
end

function hp.Objectives(mode, side)
    local runtime = mode._Hardpoint
    local commander = PW.BotCommander
    if runtime == nil or runtime.state.finished or commander == nil
        or commander.InvalidateObjective == nil or commander.Sanitize == nil
        or commander.Eligible == nil then return {} end
    local zone = runtime.state.layout.zones[runtime.state.index]
    ---@type table<integer, boolean>
    local eligible = {}
    local count = 0
    for _, ply in players() do
        if ply:IsBot() and ply:Alive() and ply:Team() == side and ply:GetObserverMode() == OBS_MODE_NONE
            and not ply:GetNW2Bool("pw_spectating", false) then
            eligible[ply:UserID()], count = true, count + 1
        end
    end
    ---@type PW.HardpointObjective
    local objective = { id = runtime.objectiveId, revision = runtime.objectiveRevision,
        pos = zone.pos, radius = math.min(48, zone.radius / 4), action = "hold", weight = 1,
        want = count, eligible = eligible, zone = zone }
    local state = runtime.state
    local pressured = state.control ~= side or state.contested or state.scores[side] < state.scores[3 - side]
    objective.urgency = pressured and 1 or 0.5
    return { objective }
end
