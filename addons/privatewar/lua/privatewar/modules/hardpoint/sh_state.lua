local hp = assert(PW.Hardpoint)

function hp.VisitAt(startedAt, now, pointTime, count)
    local visit = math.floor(math.max(0, now - startedAt) / pointTime) + 1
    return (visit - 1) % count + 1, visit, startedAt + visit * pointTime
end

function hp.NewState(layout, rules, startedAt, generation)
    return { layout = layout, rules = rules, startedAt = startedAt, generation = generation,
        index = 1, visit = 1, zoneEndsAt = startedAt + rules.pointTime,
        matchEndsAt = startedAt + rules.matchTime, scores = { 0, 0 }, finished = false,
        control = 0, contested = false, fraction = 0 }
end

---@param state PW.HardpointState
---@param winner? integer
---@return PW.MatchResult
local function finish(state, winner)
    state.finished = true
    if winner == nil and state.scores[1] ~= state.scores[2] then
        winner = state.scores[1] > state.scores[2] and 1 or 2
    end
    local first = state.scores[1] >= state.scores[2] and 1 or 2
    return { winner = winner, draw = winner == nil, reason = "Hardpoint", teams = true,
        standings = { { id = first, score = state.scores[first] },
            { id = 3 - first, score = state.scores[3 - first] } } }
end

---@param state PW.HardpointState
---@param presence PW.HardpointPresence
---@param at number
local function credit(state, presence, at)
    local last = state.lastAt
    if last == nil then return end
    local elapsed = at - last
    if elapsed > 1 or presence.control == 0 or presence.control ~= state.control then
        state.fraction = 0
        return
    end
    local boundary = math.min(state.zoneEndsAt, state.matchEndsAt, at)
    state.fraction = state.fraction + math.max(0, boundary - last)
    local points = math.floor(state.fraction + 0.0000001)
    if points > 0 then
        state.scores[presence.control] = math.min(state.rules.scoreLimit, state.scores[presence.control] + points)
        state.fraction = math.max(0, state.fraction - points)
    end
end

function hp.Step(state, sample)
    local effects = state.effects
    if effects == nil then effects = { rotated = false }; state.effects = effects end
    effects.rotated, effects.finish = false, nil
    local at = sample.at
    if state.finished or (state.lastAt ~= nil and at <= state.lastAt) then return effects end
    -- Observe the previous visit first; endpoint presence cannot backfill a missing interval.
    local presence = hp.Presence(state.layout.zones[state.index], sample.actors)
    credit(state, presence, at)
    state.control, state.contested, state.lastAt = presence.control, presence.contested, at
    if at >= state.matchEndsAt then
        effects.finish = finish(state)
        return effects
    end
    for side = 1, 2 do
        if state.scores[side] >= state.rules.scoreLimit then
            effects.finish = finish(state, side)
            return effects
        end
    end
    local index, visit, endsAt = hp.VisitAt(state.startedAt, at, state.rules.pointTime, #state.layout.zones)
    if visit ~= state.visit then
        state.index, state.visit, state.zoneEndsAt, state.fraction = index, visit, endsAt, 0
        presence = hp.Presence(state.layout.zones[index], sample.actors)
        state.control, state.contested = presence.control, presence.contested
        effects.rotated = true
    end
    return effects
end
