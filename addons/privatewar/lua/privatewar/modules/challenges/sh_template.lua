-- Pure validation of resolved CHALLENGE definitions. The registry owner can compile each definition once and
-- report the returned rejection reason. Keep the original entity for the later PW.Call custom predicate.
local lib = PW.Challenges --[[@as PW.ChallengesLib]]

---@type PW.ChallengeTier[]
local defaultTiers = { "easy", "medium", "hard" }
local allowedTiers = { easy = true, medium = true, hard = true }
local scopes = { cumulative = true, match = true, round = true, life = true }
local sources = { categories = true, weapons = true, modes = true, playlists = true }
local requiredLists = { modes = true, playlists = true, categories = true, events = true }
local rewardAmounts = { xp = true, currency = true, duplicateCurrency = true }
local builtins = {
    kill = true, score = true, medal = true, objective = true, death = true, match_end = true,
    time_played = true, round_end = true, streak_earned = true, streak_used = true
}
local shorthand = { "Event", "Filters", "Filter", "Target", "Count", "Scope", "Within", "ResetOn" }

---@param value any
---@param minimum integer
---@return boolean
local function integerAtLeast(value, minimum)
    return type(value) == "number" and value >= minimum and value < math.huge and value % 1 == 0
end

---@param value any
---@return boolean
local function stringList(value)
    local size = lib._ArrayLength(value)
    if size == nil then return false end
    for index = 1, size do
        if type(value[index]) ~= "string" then return false end
    end
    return true
end

---@param value any
---@return boolean
local function stringMap(value)
    if type(value) ~= "table" then return false end
    ---@cast value table<any, any>
    for key, label in pairs(value) do
        if type(key) ~= "string" or type(label) ~= "string" then return false end
    end
    return true
end

---@param raw any
---@return PW.ChallengeTier[]?
local function tiersOf(raw)
    if raw == nil then raw = defaultTiers end
    if not stringList(raw) or #raw == 0 then return nil end
    ---@cast raw PW.ChallengeTier[]
    ---@type PW.ChallengeTier[]
    local tiers = {}
    ---@type table<PW.ChallengeTier, boolean>
    local seen = {}
    for index, tier in ipairs(raw) do
        if not allowedTiers[tier] or seen[tier] then return nil end
        seen[tier] = true
        tiers[index] = tier
    end
    return tiers
end

---@param raw any
---@return boolean
local function validParams(raw)
    if raw == nil then return true end
    if type(raw) ~= "table" then return false end
    ---@cast raw table<any, any>
    for key, rule in pairs(raw) do
        if type(key) ~= "string" or key == "" or type(rule) ~= "table" then return false end
        ---@cast rule table<string, any>
        if rule.source ~= nil and not sources[rule.source] then return false end
        local values = rule.values
        if values == nil and rule.source == nil then return false end
        if values ~= nil and type(values) ~= "function" and not stringList(values) then return false end
        if rule.names ~= nil and not stringMap(rule.names) then return false end
    end
    return true
end

---@param value table<string, string[]>?
---@return boolean
local function validKinds(value)
    if type(value) ~= "table" then return false end
    for kind, ids in pairs(value) do
        if type(kind) ~= "string" or not stringList(ids) then return false end
    end
    return true
end

---@param raw any
---@return boolean
local function validRequirements(raw)
    if raw == nil then return true end
    if type(raw) ~= "table" then return false end
    ---@cast raw table<any, any>
    for key, value in pairs(raw) do
        if key == "kinds" then
            if not validKinds(value) then return false end
        elseif not requiredLists[key] or not stringList(value) then
            return false
        end
    end
    return true
end

---@param value any
---@return boolean
local function validItems(value)
    local size = lib._ArrayLength(value)
    if size == nil then return false end
    ---@cast value table<integer, any>
    for index = 1, size do
        local item = value[index]
        if type(item) ~= "table" then return false end
        ---@cast item table<string, any>
        if type(item.kind) ~= "string" or type(item.id) ~= "string"
            or (item.weapon ~= nil and type(item.weapon) ~= "string") then return false end
    end
    return true
end

---@param raw any
---@return boolean
local function validReward(raw)
    if type(raw) ~= "table" then return false end
    ---@cast raw table<any, any>
    for key, value in pairs(raw) do
        if key == "items" then
            if not validItems(value) then return false end
        elseif not rewardAmounts[key] or not integerAtLeast(value, 0) then
            return false
        end
    end
    return true
end

---@param raw any
---@return boolean
local function validRewards(raw)
    if raw == nil or validReward(raw) then return true end
    if type(raw) ~= "table" then return false end
    ---@cast raw table<any, any>
    for tier, reward in pairs(raw) do
        if not allowedTiers[tier] or not validReward(reward) then return false end
    end
    return true
end

---@param raw any
---@param custom table<string, PW.ChallengeEventType>
---@return string[]?
local function eventsOf(raw, custom)
    local values = type(raw) == "string" and { raw } or raw
    if not stringList(values) or #values == 0 then return nil end
    ---@cast values string[]
    ---@type string[]
    local events = {}
    ---@type table<string, boolean>
    local seen = {}
    for _, event in ipairs(values) do
        if not builtins[event] and custom[event] == nil then return nil end
        if not seen[event] then
            events[#events + 1], seen[event] = event, true
        end
    end
    return events
end

---@param raw any
---@param tiers PW.ChallengeTier[]
---@return table<PW.ChallengeTier, integer>?
local function targetsOf(raw, tiers)
    ---@type table<PW.ChallengeTier, integer>
    local targets = {}
    for _, tier in ipairs(tiers) do
        local value = raw
        if type(raw) == "table" then
            ---@cast raw table<PW.ChallengeTier, any>
            value = raw[tier]
        end
        if not integerAtLeast(value, 1) then return nil end
        targets[tier] = value
    end
    return targets
end

---@param raw any
---@param params table<string, PW.ChallengeParam>
---@param custom table<string, PW.ChallengeEventType>
---@return PW.ChallengeCompiledReset[]?, string?
local function compileReset(raw, params, custom)
    if raw == nil then return {} end
    local size = lib._ArrayLength(raw)
    if size == nil then return nil, "ResetOn must be an array" end
    ---@cast raw table<integer, any>
    ---@type PW.ChallengeCompiledReset[]
    local rules = {}
    for index = 1, size do
        local rule = raw[index]
        if type(rule) ~= "table" then return nil, "expected a ResetOn rule table" end
        ---@cast rule table<string, any>
        if type(rule.Event) ~= "string" then return nil, "invalid reset event" end
        local events = eventsOf(rule.Event, custom)
        if events == nil then return nil, "unknown reset event " .. rule.Event end
        local bind, reason = lib._CompileFilters(rule.Filters, { events = events, params = params, custom = custom })
        if bind == nil then return nil, "ResetOn: " .. (reason or "invalid filter") end
        rules[index] = { event = rule.Event, bind = bind }
    end
    return rules
end

---@param raw any
---@param tiers PW.ChallengeTier[]
---@param params table<string, PW.ChallengeParam>
---@param custom table<string, PW.ChallengeEventType>
---@return PW.ChallengeCompiledObjective?, string?
local function compileObjective(raw, tiers, params, custom)
    if type(raw) ~= "table" then return nil, "expected an objective table" end
    ---@cast raw table<string, any>
    local events = eventsOf(raw.Event, custom)
    if events == nil then return nil, "expected one or more known Event types" end
    local targets = targetsOf(raw.Target, tiers)
    if targets == nil then return nil, "Target must be a positive integer for every allowed tier" end
    local scope, count = raw.Scope, raw.Count
    if scope ~= nil and not scopes[scope] then return nil, "unknown Scope" end
    if count ~= nil and count ~= 1 and count ~= "value" then return nil, "Count must be 1 or value" end
    if raw.Label ~= nil and type(raw.Label) ~= "string" then return nil, "Label must be a string" end
    if raw.Filter ~= nil and type(raw.Filter) ~= "function" then return nil, "Filter must be a function" end
    local within = raw.Within
    if within ~= nil then
        if type(within) ~= "table" then return nil, "Within must be a table" end
        ---@cast within table<string, any>
        if not integerAtLeast(within.count, 2) or type(within.seconds) ~= "number"
            or not (within.seconds > 0 and within.seconds < math.huge) then return nil, "invalid Within window" end
        within = { count = within.count, seconds = within.seconds }
    end
    local bind, reason = lib._CompileFilters(raw.Filters, { events = events, params = params, custom = custom })
    if bind == nil then return nil, reason end
    local reset, resetReason = compileReset(raw.ResetOn, params, custom)
    if reset == nil then return nil, resetReason end
    return {
        events = events, targets = targets, label = raw.Label, scope = scope or "cumulative", count = count or 1,
        within = within, bind = bind, reset = reset, filter = raw.Filter
    }
end

---@param raw table<string, any>
---@return table[]?, string?
local function objectivesOf(raw)
    if raw.Objectives == nil then return { raw } end
    for _, field in ipairs(shorthand) do
        if raw[field] ~= nil then return nil, "Objectives cannot be combined with " .. field end
    end
    local size = lib._ArrayLength(raw.Objectives)
    if size == nil or size < 1 or size > 4 then return nil, "Objectives must have 1 to 4 entries" end
    return raw.Objectives
end

function lib._Compile(id, raw, customTypes)
    -- The template is the first id segment; a dot always starts the next segment.
    if id == "bonus" or #id > lib._MaxInstanceId or not string.match(id, "^[a-z][a-z0-9_]*$") then
        return nil, "invalid or reserved template id"
    end
    if type(raw) ~= "table" then return nil, "expected a template table" end
    ---@cast raw table<string, any>
    if type(raw.Name) ~= "string" or type(raw.Description) ~= "string" then
        return nil, "Name and Description must be strings"
    end
    if raw.Icon ~= nil and type(raw.Icon) ~= "string" then return nil, "Icon must be a string" end
    if raw.Group ~= nil and type(raw.Group) ~= "string" then return nil, "Group must be a string" end
    if raw.Pool ~= nil and raw.Pool ~= "weekly" and raw.Pool ~= "none" then return nil, "unknown Pool" end
    if raw.Mode ~= nil and raw.Mode ~= "all" and raw.Mode ~= "any" then return nil, "unknown Mode" end
    if raw.Weight ~= nil and (type(raw.Weight) ~= "number" or not (raw.Weight > 0 and raw.Weight < math.huge)) then
        return nil, "Weight must be positive and finite"
    end
    local tiers = tiersOf(raw.Tiers)
    if tiers == nil then return nil, "Tiers must be a non-empty list of different known tiers" end
    if not validParams(raw.Params) then return nil, "invalid Params" end
    if not validRequirements(raw.Requires) then return nil, "invalid Requires" end
    if not validRewards(raw.Rewards) then return nil, "invalid Rewards" end
    local entries, reason = objectivesOf(raw)
    if entries == nil then return nil, reason end
    local params = raw.Params or {}
    local custom = customTypes or {}
    ---@type PW.ChallengeCompiledObjective[]
    local objectives = {}
    for index, entry in ipairs(entries) do
        local objective, invalid = compileObjective(entry, tiers, params, custom)
        if objective == nil then return nil, "objective " .. index .. ": " .. (invalid or "invalid definition") end
        objectives[index] = objective
    end
    return {
        id = id, definition = raw --[[@as PW.Challenge]], tiers = tiers, group = raw.Group or id,
        weight = raw.Weight or 1, pool = raw.Pool or "weekly", mode = raw.Mode or "all",
        params = params, objectives = objectives
    }
end

function lib._FormatText(text, template, ctx)
    local targets, params, sourceNames = ctx.targets, ctx.params, ctx.names
    return (string.gsub(text, "%{([^{}]+)%}", function(token)
        local digit = string.match(token, "^target([1-4])$")
        local index = token == "target" and 1 or (digit and tonumber(digit))
        if index ~= nil and targets[index] ~= nil then return tostring(targets[index]) end
        local key = string.match(token, "^param%.(.+)$")
        if key == nil then return "{" .. token .. "}" end
        local value = params[key]
        if value == nil then return "{" .. token .. "}" end
        local rule = template.params[key]
        local names = rule and rule.names
        local supplied = sourceNames and sourceNames[key]
        return (names and names[value]) or (supplied and supplied[value]) or value
    end))
end
