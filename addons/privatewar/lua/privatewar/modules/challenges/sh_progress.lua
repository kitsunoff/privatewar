-- Week-local counters and event routing. Bound filters and scope choices are shared by all players.
local lib = PW.Challenges --[[@as PW.ChallengesLib]]

---@param plan PW.ChallengeProgressPlan
---@param event string
---@return PW.ChallengeRoutes
local function routesFor(plan, event)
    local routes = plan.byType[event]
    if routes == nil then
        routes = { increments = {}, resets = {} }
        plan.byType[event] = routes
    end
    return routes
end

---@param template PW.ChallengeTemplate
---@param objective PW.ChallengeCompiledObjective
---@param params PW.ChallengeParams
---@return PW.ChallengePredicate
local function matchObjective(template, objective, params)
    local match, filter = objective.bind(params), objective.filter
    if filter == nil then
        return function(ev) return not template.filterFailed and match(ev) end
    end
    local caller = { ClassName = template.id, Filter = function(_, ev, resolved)
        return true, filter(template.definition, ev, resolved)
    end }
    return function(ev)
        if template.filterFailed or not match(ev) then return false end
        local ran, accepted = PW.Call(caller, "Filter", ev, params)
        if ran ~= true then template.filterFailed = true end
        return ran == true and accepted == true
    end
end

---@param plan PW.ChallengeProgressPlan
---@param instance PW.ChallengeInstance
---@param template PW.ChallengeTemplate
---@param rounds boolean
local function bindItem(plan, instance, template, rounds)
    ---@type PW.ChallengePlannedItem
    local item = { mode = template.mode, objectives = {} }
    plan.entries[instance.id] = item
    for slot, compiled in ipairs(template.objectives) do
        ---@type PW.ChallengePlannedObjective
        local objective = { id = instance.id, slot = slot, target = instance.targets[slot],
            scope = not rounds and compiled.scope == "round" and "match" or compiled.scope,
            count = compiled.count, within = compiled.within,
            matches = matchObjective(template, compiled, instance.params) }
        item.objectives[slot] = objective
        for _, event in ipairs(compiled.events) do
            local increments = routesFor(plan, event).increments
            increments[#increments + 1] = objective
        end
        for _, reset in ipairs(compiled.reset) do
            local resets = routesFor(plan, reset.event).resets
            local matches = reset.bind(instance.params)
            resets[#resets + 1] = { objective = objective,
                matches = function(ev) return not template.filterFailed and matches(ev) end }
        end
    end
end

function lib._ProgressPlan(week, templates, rounds)
    ---@type PW.ChallengeProgressPlan
    local plan = { index = week.index, entries = {}, byType = {}, needed = week.bonus.needed }
    for _, instance in ipairs(week.items) do
        local template = templates[instance.template]
        if template ~= nil then bindItem(plan, instance, template, rounds) end
    end
    return plan
end

---@param value number
---@return boolean
local function positive(value)
    return value > 0 and value < math.huge
end

function lib._NewProgress(plan, saved)
    ---@type PW.ChallengeProgressState
    local state = { index = plan.index, items = {}, completed = 0, bonus = false }
    local savedItems = saved ~= nil and saved.index == plan.index and saved.items or {}
    for id, entry in pairs(plan.entries) do
        local savedItem = savedItems[id]
        ---@type PW.ChallengeItemProgress
        local item = { counters = {}, remaining = #entry.objectives, done = false }
        for slot, objective in ipairs(entry.objectives) do
            local previous = savedItem ~= nil and savedItem.p[slot] or 0
            local best = positive(previous) and math.min(previous, objective.target) or 0
            item.counters[slot] = { best = best }
            if best >= objective.target then item.remaining = item.remaining - 1 end
        end
        item.done = item.remaining == 0 or (entry.mode == "any" and item.remaining < #entry.objectives)
        if item.done then state.completed = state.completed + 1 end
        state.items[id] = item
    end
    state.bonus = plan.needed > 0 and state.completed >= plan.needed
    return state
end

---@param entry PW.ChallengePlannedItem
---@param item PW.ChallengeItemProgress
---@param scope PW.ChallengeScope
---@param open boolean
local function resetItem(entry, item, scope, open)
    if item.done then return end
    for slot, objective in ipairs(entry.objectives) do
        if objective.scope == scope then
            local counter = item.counters[slot]
            counter.times = nil
            counter.run = open and 0 or nil
        end
    end
end

---@param plan PW.ChallengeProgressPlan
---@param state PW.ChallengeProgressState
---@param scope PW.ChallengeScope
---@param open boolean
local function resetScope(plan, state, scope, open)
    for id, entry in pairs(plan.entries) do resetItem(entry, state.items[id], scope, open) end
end

function lib._ResetProgress(plan, state, boundary)
    if state.index ~= plan.index then return end
    if boundary == "match_start" or boundary == "match_end" then
        local open = boundary == "match_start"
        resetScope(plan, state, "match", open)
        resetScope(plan, state, "round", false)
        resetScope(plan, state, "life", open)
    elseif boundary == "round_start" or boundary == "round_end" then
        resetScope(plan, state, "round", boundary == "round_start")
    else
        resetScope(plan, state, "life", true)
    end
end

---@param counter PW.ChallengeCounter
---@param rule PW.ChallengeWindow
---@param now number
---@return boolean
local function windowCounts(counter, rule, now)
    if not (now >= 0 and now < math.huge) then return false end
    local times = counter.times or {}
    if #times > 0 and now < times[#times] then times = {} end
    local kept = 0
    local limit = #times
    for slot = 1, limit do
        if now - times[slot] <= rule.seconds then
            kept = kept + 1
            times[kept] = times[slot]
        end
    end
    for slot = kept + 1, limit do times[slot] = nil end
    times[kept + 1] = now
    if #times >= rule.count then
        counter.times = nil
        return true
    end
    counter.times = times
    return false
end

---@param objective PW.ChallengePlannedObjective
---@param counter PW.ChallengeCounter
---@param ev PW.ChallengeEvent
local function increment(objective, counter, ev)
    local window = objective.within
    local amount = objective.count == "value" and ev.value or 1
    if window ~= nil then
        if not windowCounts(counter, window, ev.time) then return end
        amount = 1
    end
    if not positive(amount) then return end
    if objective.scope == "cumulative" then
        counter.best = math.min(objective.target, counter.best + amount)
    elseif counter.run ~= nil then
        counter.run = math.min(objective.target, counter.run + amount)
        counter.best = math.max(counter.best, counter.run)
    end
end

---@param state PW.ChallengeProgressState
---@param routes PW.ChallengeRoutes
---@param ev PW.ChallengeEvent
local function applyResets(state, routes, ev)
    for _, rule in ipairs(routes.resets) do
        local objective = rule.objective
        local item = state.items[objective.id]
        local counter = item.counters[objective.slot]
        if not item.done and counter.best < objective.target and rule.matches(ev) then
            counter.times = nil
            if objective.scope == "cumulative" then counter.best = 0
            elseif counter.run ~= nil then counter.run = 0 end
        end
    end
end

---@param plan PW.ChallengeProgressPlan
---@param state PW.ChallengeProgressState
---@param objective PW.ChallengePlannedObjective
---@param ev PW.ChallengeEvent
---@param completed string[]
local function applyIncrement(plan, state, objective, ev, completed)
    local item = state.items[objective.id]
    local counter = item.counters[objective.slot]
    if item.done or counter.best >= objective.target
        or (objective.scope ~= "cumulative" and counter.run == nil) or not objective.matches(ev) then return end
    increment(objective, counter, ev)
    if counter.best < objective.target then return end
    item.remaining = item.remaining - 1
    if item.remaining ~= 0 and plan.entries[objective.id].mode ~= "any" then return end
    item.done = true
    state.completed = state.completed + 1
    completed[#completed + 1] = objective.id
end

function lib._AdvanceProgress(plan, state, ev)
    ---@type PW.ChallengeAdvance
    local result = { completed = {}, bonus = false }
    if state.index ~= plan.index or ev.week ~= plan.index then return result end
    local routes = plan.byType[ev.type]
    if routes == nil then return result end
    applyResets(state, routes, ev)
    for _, objective in ipairs(routes.increments) do applyIncrement(plan, state, objective, ev, result.completed) end
    if not state.bonus and plan.needed > 0 and state.completed >= plan.needed then
        state.bonus, result.bonus = true, true
    end
    return result
end

function lib._ReadProgress(plan, state, id)
    local item, entry = state.items[id], plan.entries[id]
    if state.index ~= plan.index or item == nil or entry == nil then return nil end
    ---@type PW.ChallengeProgress
    local progress = { values = {}, targets = {}, done = item.done }
    for slot, objective in ipairs(entry.objectives) do
        local counter = item.counters[slot]
        local run, value = counter.run, counter.best
        if run ~= nil and value < objective.target then value = run end
        progress.values[slot], progress.targets[slot] = math.floor(value), objective.target
    end
    return progress
end

function lib._SaveProgress(plan, state)
    ---@type PW.ChallengeFileWeek
    local week = { index = plan.index, items = {}, bonus = state.bonus }
    if state.index ~= plan.index then return week end
    for id, item in pairs(state.items) do
        ---@type PW.ChallengeFileItem
        local saved = { p = {}, done = item.done }
        for slot, counter in ipairs(item.counters) do saved.p[slot] = math.floor(counter.best) end
        week.items[id] = saved
    end
    return week
end
