local lib = PW.Challenges --[[@as PW.ChallengesViewLib]]
local scopeText = { cumulative = "across matches", match = "in a single match", round = "in a single round",
    life = "without dying" }
local thresholds = { 75, 50, 25 }
local categoryNames = { ar = "assault rifle", smg = "SMG", shotgun = "shotgun", pistol = "pistol", special = "special" }
---@type table<PW.Challenge, PW.ChallengeTemplate>
local compiled = setmetatable({}, { __mode = "kv" })

function lib._ChallengeCountdown(endsAt, now)
    local minutes = math.floor(math.max(0, endsAt - now) / 60)
    if minutes >= 1440 then
        return string.format("Resets in %dd %dh", math.floor(minutes / 1440), math.floor(minutes / 60) % 24)
    end
    if minutes >= 60 then return string.format("Resets in %dh %dm", math.floor(minutes / 60), minutes % 60) end
    return string.format("Resets in %dm", minutes)
end

---@param amount integer
---@return string
local function grouped(amount)
    local reversed = string.reverse(tostring(amount))
    local spaced = (string.gsub(reversed, "(%d%d%d)", "%1 ")):gsub(" $", "")
    return string.reverse(spaced)
end

---@param reward PW.ChallengeReward
---@param describe fun(item: PW.ChallengeRewardItem): string
---@return string, string, string
local function rewardText(reward, describe)
    ---@type string[]
    local segments = {}
    local xp, currency = reward.xp or 0, reward.currency or 0
    if xp > 0 then segments[#segments + 1] = "+" .. grouped(xp) .. " XP" end
    if currency > 0 then segments[#segments + 1] = grouped(currency) .. " CR" end
    local payout = table.concat(segments, " · ")
    ---@type string[]
    local names = {}
    for _, item in ipairs(reward.items or {}) do
        local name = describe(item)
        segments[#segments + 1], names[#names + 1] = name, name
    end
    return table.concat(segments, " · "), payout, table.concat(names, " · ")
end

---@param count number
---@param target number
---@return number
local function fraction(count, target)
    return target > 0 and math.Clamp(count / target, 0, 1) or 0
end

---@param deps PW.ChallengeViewDeps
---@param item PW.ChallengeInstance
---@return PW.ChallengeTemplate?
local function templateFor(deps, item)
    local definition = deps.getTemplate(item.template)
    if definition == nil then return nil end
    local template = compiled[definition] --[[@as PW.ChallengeTemplate?]]
    if template == nil then
        template = lib._Compile(item.template, definition, lib._CustomEventTypes)
        if template ~= nil then compiled[definition] = template end
    end
    return template
end

---@param item PW.ChallengeInstance
---@param template PW.ChallengeTemplate
---@param deps PW.ChallengeViewDeps
---@return PW.ChallengeTextContext
local function textContext(item, template, deps)
    local ctx = { targets = item.targets, params = item.params } --[[@as PW.ChallengeTextContext]]
    if deps.getName == nil then return ctx end
    ---@type table<string, table<string, string>>
    local names = {}
    for key, value in pairs(item.params) do
        local rule = template.params[key]
        if rule ~= nil and rule.source ~= nil then names[key] = { [value] = deps.getName(rule.source, value) } end
    end
    ctx.names = names
    return ctx
end

---@param objective PW.ChallengeCompiledObjective?
---@param slot integer
---@param value integer
---@param target integer
---@return PW.ChallengeObjectiveView
local function objectiveView(objective, slot, value, target)
    local label = objective and objective.label or "Objective " .. slot
    local scope = objective and scopeText[objective.scope] or ""
    local window = objective and objective.within
    if objective ~= nil and window ~= nil then
        local windowText = string.format("within %g seconds", window.seconds)
        scope = objective.scope == "cumulative" and windowText or scope .. " · " .. windowText
    end
    return { label = label, scope = scope, fraction = fraction(value, target),
        progressText = string.format("%d / %d", value, target) }
end

---@param definition PW.Challenge?
---@param deps PW.ChallengeViewDeps
---@return string[]
local function requirementText(definition, deps)
    ---@type string[]
    local out = {}
    local requirements = definition and definition.Requires
    if requirements == nil then return out end
    local getName = deps.getName
    for _, kind in ipairs({ "modes", "playlists", "categories" }) do
        local ids = (requirements --[[@as table<string, string[]>]])[kind]
        ---@type string[]
        local names = {}
        for _, id in ipairs(ids or {}) do names[#names + 1] = getName ~= nil and getName(kind, id) or id end
        if #names > 0 then out[#out + 1] = table.concat(names, ", ") .. " only" end
    end
    return out
end

---@param item PW.ChallengeInstance
---@param deps PW.ChallengeViewDeps
---@return PW.ChallengeRowView
local function buildRow(item, deps)
    local progress, template = deps.getProgress(item.id), templateFor(deps, item)
    local name, description = item.id, ""
    if template ~= nil then
        local ctx = textContext(item, template, deps)
        name, description = lib._FormatText(template.definition.Name, template, ctx),
            lib._FormatText(template.definition.Description, template, ctx)
    end
    local total, target, bestValue, bestTarget = 0, 0, 0, 0
    ---@type PW.ChallengeObjectiveView[]
    local objectives = {}
    for slot, needed in ipairs(item.targets) do
        local value = math.Clamp(progress ~= nil and (progress.values[slot] or 0) or 0, 0, needed)
        objectives[slot] = objectiveView(template and template.objectives[slot] or nil, slot, value, needed)
        total, target = total + value, target + needed
        if bestTarget == 0 or fraction(value, needed) > fraction(bestValue, bestTarget) then
            bestValue, bestTarget = value, needed
        end
    end
    if template ~= nil and template.mode == "any" then total, target = bestValue, bestTarget end
    local done = progress ~= nil and progress.done
    local reward, payout = rewardText(item.reward, deps.describe)
    return { id = item.id, name = name, description = description, tier = item.tier,
        fraction = done and 1 or fraction(total, target), target = target,
        progressText = string.format("%d / %d", total, target), done = done,
        reward = reward, payout = payout, objectives = objectives,
        requirements = requirementText(template and template.definition or nil, deps) }
end

function lib._BuildChallengeView(week, now, deps)
    local year, number = string.match(week.label, "^(%d%d%d%d)%-W(%d%d)$")
    local heading = year and number and string.format("WEEK %d · %s", tonumber(number), year) or week.label
    local completed = 0
    local reward, _, itemNames = rewardText(week.bonus.reward, deps.describe)
    ---@type PW.ChallengeWeekView
    local model = { label = week.label, weekLabel = heading, endsAt = week.endsAt,
        countdown = lib._ChallengeCountdown(week.endsAt, now), rows = {}, byId = {},
        bonus = { completed = 0, needed = week.bonus.needed, fraction = 0, done = false,
            reward = reward, itemNames = itemNames } }
    for i, item in ipairs(week.items) do
        local row = buildRow(item, deps)
        model.rows[i], model.byId[row.id] = row, row
        if row.done then completed = completed + 1 end
    end
    local bonus = model.bonus
    bonus.completed, bonus.fraction = completed, fraction(completed, bonus.needed)
    bonus.done = bonus.needed > 0 and completed >= bonus.needed
    return model
end

---@param queue PW.ChallengeToast[]
---@param toast PW.ChallengeToast
local function enqueue(queue, toast)
    for i = #queue, 1, -1 do
        local old = queue[i]
        if old.kind == "milestone" then
            if toast.kind ~= "milestone" then
                table.remove(queue, i)
            elseif old.id == toast.id then
                queue[i] = toast
                return
            end
        end
    end
    if #queue == 3 then
        local discard = 1
        while discard <= #queue and queue[discard].kind ~= "milestone" do discard = discard + 1 end
        if discard > #queue then
            if toast.kind == "milestone" then return end
            discard = 1
        end
        table.remove(queue, discard)
    end
    queue[#queue + 1] = toast
end

---@param queue PW.ChallengeToast[]
---@param previous PW.ChallengeRowView
---@param row PW.ChallengeRowView
local function queueRow(queue, previous, row)
    if previous.done then return end
    if row.done then
        enqueue(queue, { id = row.id, kind = "complete", duration = 4,
            title = "CHALLENGE COMPLETE", detail = row.name, reward = row.payout })
        return
    end
    if row.target < 4 then return end
    for _, threshold in ipairs(thresholds) do
        if previous.fraction * 100 < threshold and row.fraction * 100 >= threshold then
            enqueue(queue, { id = row.id, kind = "milestone", duration = 2.5, threshold = threshold,
                title = string.upper(row.name), detail = row.progressText, fraction = row.fraction })
            return
        end
    end
end

function lib._UpdateChallengeToasts(queue, before, after)
    if before == nil or before.label ~= after.label then return {} end
    for _, row in ipairs(after.rows) do
        local previous = before.byId[row.id]
        if previous ~= nil then queueRow(queue, previous, row) end
    end
    if not before.bonus.done and after.bonus.done then
        enqueue(queue, { id = "bonus", kind = "bonus", duration = 4,
            title = "WEEKLY BONUS EARNED",
            detail = after.bonus.itemNames ~= "" and after.bonus.itemNames or after.bonus.reward })
    end
    return queue
end

---@param api PW
---@param kind string
---@param id string
---@return PW.Entity?
local function lookup(api, kind, id)
    local registries = rawget(api, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries[kind] or nil
    return registry ~= nil and registry.Get(id) or nil
end

function lib._OwnerChallengeView(api, owner, now)
    local challenges = api.Challenges
    if challenges == nil then return nil end
    local getWeek, getProgress = challenges.GetWeek, challenges.GetProgress
    if getWeek == nil or getProgress == nil then return nil end
    local week = getWeek()
    if week == nil then return nil end
    local unlocks = api.Unlocks
    return lib._BuildChallengeView(week, now, {
        getProgress = function(id) return getProgress(owner, id) end,
        getTemplate = function(id) return lookup(api, "challenges", id) --[[@as PW.Challenge?]] end,
        describe = function(item) return unlocks and unlocks.Describe(item).name or item.id end,
        getName = function(kind, id)
            if kind == "categories" then return categoryNames[id] or id end
            local entry = lookup(api, kind, id)
            local name = entry and entry.Name
            if type(name) ~= "string" then return id end
            if name:sub(1, 1) == "#" then return language.GetPhrase(name:sub(2)) end
            return name
        end
    })
end
