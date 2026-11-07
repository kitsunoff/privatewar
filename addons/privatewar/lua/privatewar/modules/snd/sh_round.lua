-- One bomb and one held interaction. Deadline equality wins; completed plants survive subsequent actor death.
local lib = PW.SND --[[@as PW.SNDLib]]

---@param state PW.SNDState
---@param actor PW.SNDActor
---@return boolean
local function valid(state, actor)
    local member = state.roster[actor.id]
    return member ~= nil and member.userId == actor.userId and member.connected and member.alive
        and member.team == actor.team and actor.alive and actor.generation == state.generation
end

---@param state PW.SNDState
---@param actor PW.SNDActor
---@return string?, string?
local function interactionFor(state, actor)
    if not actor.use or not actor.clear then return nil end
    if state.phase == "carried" and state.carrier == actor.id then
        for _, site in ipairs(state.map.sites) do
            if lib.Inside(site, actor.pos) then return "plant", site.id end
        end
    elseif state.phase == "planted" and actor.team == 2 and actor.pos:DistToSqr(state.pos) <= 72 * 72 then
        return "defuse", state.site
    end
    return nil
end

---@param state PW.SNDState
---@param now number
---@param actors PW.SNDActor[]
local function hold(state, now, actors)
    local old = state.interaction
    state.interaction = nil
    for _, actor in ipairs(actors) do
        local action, site = interactionFor(state, actor)
        if valid(state, actor) and action ~= nil then
            local same = old ~= nil and old.id == actor.id and old.userId == actor.userId
                and old.generation == state.generation and old.action == action and old.site == site
            state.interaction = same and old or { id = actor.id, userId = actor.userId,
                generation = state.generation, action = action, site = assert(site), at = now }
            return
        end
    end
end

---@param state PW.SNDState
---@param now number
local function complete(state, now)
    local interaction = state.interaction
    if interaction == nil then return end
    local duration = interaction.action == "plant" and 5 or 7.5
    if now - interaction.at < duration then return end
    if interaction.action == "plant" then
        for _, site in ipairs(state.map.sites) do
            if site.id == interaction.site then state.pos = site.approach end
        end
        state.phase, state.carrier, state.site, state.fuse = "planted", nil, interaction.site, now + 45
    else
        state.phase, state.winner = "resolved", 2
    end
    state.interaction = nil
end

---@param state PW.SNDState
---@param actors PW.SNDActor[]
local function pickup(state, actors)
    if state.phase ~= "dropped" then return end
    for _, actor in ipairs(actors) do
        if valid(state, actor) and actor.team == 1 and actor.clear and actor.pos:DistToSqr(state.pos) <= 64 * 64 then
            state.phase, state.carrier = "carried", actor.id
            return
        end
    end
end

---@param state PW.SNDState
---@param actors PW.SNDActor[]
---@return integer, integer
local function counts(state, actors)
    local attacker, defender = 0, 0
    for _, actor in ipairs(actors) do
        if valid(state, actor) then
            if actor.team == 1 then attacker = attacker + 1 elseif actor.team == 2 then defender = defender + 1 end
        end
    end
    return attacker, defender
end

function lib.Step(state, now, actors)
    if state.phase == "resolved" then return state.winner, false end
    if state.phase == "planted" and now >= state.fuse then
        state.phase, state.winner, state.interaction = "resolved", 1, nil
        return 1, false
    end
    if state.phase ~= "planted" and now >= state.deadline then
        state.phase, state.winner, state.interaction = "resolved", 2, nil
        return 2, false
    end
    pickup(state, actors)
    hold(state, now, actors)
    complete(state, now)
    if state.phase == "resolved" then return state.winner, false end
    local attacker, defender = counts(state, actors)
    if defender == 0 then
        state.winner = (attacker > 0 or state.phase == "planted") and 1 or false
    elseif attacker == 0 and state.phase ~= "planted" then
        state.winner = 2
    end
    if state.winner ~= nil then
        state.phase, state.interaction = "resolved", nil
        return state.winner, false
    end
    return nil, state.phase == "planted"
end

function lib.Snapshot(state, viewerTeam, viewerId, now)
    ---@type PW.SNDSnapshot
    local out = { generation = state.generation, phase = state.phase, deadline = state.deadline,
        fuse = state.phase == "planted" and state.fuse or 0, site = state.site, progress = 0 }
    if viewerTeam == 1 and state.carrier ~= nil then out.carrier = state.roster[state.carrier].userId end
    if state.phase == "planted" or (viewerTeam == 1 and state.phase == "dropped") then out.pos = state.pos end
    local interaction = state.interaction
    if interaction ~= nil and interaction.id == viewerId then
        out.action = interaction.action
        out.progress = math.Clamp((now - interaction.at) / (interaction.action == "plant" and 5 or 7.5), 0, 1)
    end
    return out
end
