-- UTC week math and deterministic rotation without the host clock, time zone or Economy module.
local lib = PW.Challenges --[[@as PW.ChallengesLib]]
local daySeconds = 86400
local epochMonday = 4 -- 1970-01-05

---The shop's March-based Gregorian day arithmetic, specialized to January 1.
---@param year integer
---@return integer
local function januaryFirst(year)
    local marchYear = year - 1
    local era = math.floor(marchYear / 400)
    local yearOfEra = marchYear - era * 400
    return era * 146097 + yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + 306 - 719468
end

---Inverse day arithmetic: only the year is needed, not the month or the day.
---@param day integer
---@return integer
local function yearOf(day)
    local shifted = day + 719468
    local era = math.floor(shifted / 146097)
    local dayOfEra = shifted - era * 146097
    local leaps = math.floor(dayOfEra / 1460) - math.floor(dayOfEra / 36524) + math.floor(dayOfEra / 146096)
    local yearOfEra = math.floor((dayOfEra - leaps) / 365)
    local marchDay = dayOfEra - (yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100))
    return era * 400 + yearOfEra + (marchDay >= 306 and 1 or 0)
end

function lib.WeekIndex(unixUtc)
    return math.floor((math.floor(unixUtc / daySeconds) - epochMonday) / 7)
end

function lib.WeekLabel(index)
    local thursday = index * 7 + epochMonday + 3
    local year = yearOf(thursday)
    local week = math.floor((thursday - januaryFirst(year)) / 7) + 1
    return string.format("%04d-W%02d", year, week)
end

function lib.WeekBounds(index)
    local startsAt = (index * 7 + epochMonday) * daySeconds
    return startsAt, startsAt + 7 * daySeconds
end

---@alias PW.ChallengeDraw fun(): number
---@class PW.ChallengeDomain
---@field key string
---@field values string[]
---@field reserve integer minimum bytes needed by all following segments, including separators

---@class PW.ChallengeReadyCandidate
---@field template PW.ChallengeTemplate
---@field domains PW.ChallengeDomain[]

local modulus = 2147483647
local multiplier = 48271
local spread = 2654435761

---@type PW.ChallengeTier[]
local tierOrder = { "easy", "medium", "hard" }
local tierRank = { easy = 1, medium = 2, hard = 3 }
---@type table<PW.ChallengeTier, PW.ChallengeReward>
local defaultRewards = {
    easy = { xp = 2500, currency = 50 },
    medium = { xp = 5000, currency = 100 },
    hard = { xp = 10000, currency = 200 }
}

---@param salt string
---@return integer
local function hashOf(salt)
    local hash = 5381
    for index = 1, #salt do hash = (hash * 33 + string.byte(salt, index)) % modulus end
    return hash
end

---@param index integer
---@param hostSeed integer
---@return integer, PW.ChallengeDraw
local function generator(index, hostSeed)
    local salt = hashOf("challenges")
    local seed = ((index + 1) * spread + salt + hostSeed) % modulus
    if seed == 0 then seed = 1 end
    local state = seed
    local function draw()
        state = (state * multiplier) % modulus
        return state / modulus
    end
    for _ = 1, 3 do draw() end
    return seed, draw
end

---@param candidate PW.ChallengeCandidate
---@param key string
---@return string[]
local function availableValues(candidate, key)
    local rule = candidate.template.params[key]
    local sourceValues = rule.values
    ---@type string[]?
    local declared
    if type(sourceValues) == "table" then declared = sourceValues end
    local supplied = candidate.values
    ---@type string[]?
    local available
    if supplied ~= nil then
        available = supplied[key]
    elseif rule.source == nil then
        available = declared
    end
    if available == nil then return {} end

    ---@type table<string, boolean>
    local allowed = {}
    ---@type table<string, boolean>
    local seen = {}
    for _, value in ipairs(declared or {}) do allowed[value] = true end
    ---@type string[]
    local values = {}
    for _, value in ipairs(available) do
        -- Dots are delimiters, not part of individual values (including those from host resolvers).
        if type(value) == "string" and string.match(value, "^[%w_%-]+$") and not seen[value]
            and (declared == nil or allowed[value]) then
            seen[value] = true
            values[#values + 1] = value
        end
    end
    table.sort(values)
    return values
end

---@param candidate PW.ChallengeCandidate
---@return PW.ChallengeReadyCandidate?
local function prepare(candidate)
    local template = candidate.template
    if template.pool ~= "weekly" then return nil end
    ---@type string[]
    local keys = {}
    for key in pairs(template.params) do keys[#keys + 1] = key end
    table.sort(keys)
    ---@type PW.ChallengeDomain[]
    local domains = {}
    local reserve = 0
    for index = #keys, 1, -1 do
        local key = keys[index]
        local values = availableValues(candidate, key)
        if #values == 0 then return nil end
        local shortest = #values[1]
        for _, value in ipairs(values) do shortest = math.min(shortest, #value) end
        domains[index] = { key = key, values = values, reserve = reserve }
        reserve = reserve + 1 + shortest
    end
    if #template.id + reserve > lib._MaxInstanceId then return nil end
    return { template = template, domains = domains }
end

---@param choices PW.ChallengeReadyCandidate[]
---@param scale number
---@return number
local function weightTotal(choices, scale)
    local total = 0
    for _, choice in ipairs(choices) do total = total + choice.template.weight / scale end
    return total
end

---@param choices PW.ChallengeReadyCandidate[]
---@return number total
---@return number scale
local function weightRange(choices)
    local total = weightTotal(choices, 1)
    if total < math.huge then return total, 1 end
    -- Preserve the weight ratios if their unscaled sum overflows.
    ---@type number
    local largest = 1
    for _, choice in ipairs(choices) do
        local weight = choice.template.weight
        if weight > largest then largest = weight end
    end
    return weightTotal(choices, largest), largest
end

---@param choices PW.ChallengeReadyCandidate[]
---@param draw PW.ChallengeDraw
---@return PW.ChallengeReadyCandidate?
local function weighted(choices, draw)
    if #choices == 0 then return nil end
    local total, scale = weightRange(choices)
    local roll, cumulative = draw() * total, 0
    for _, choice in ipairs(choices) do
        cumulative = cumulative + choice.template.weight / scale
        if roll < cumulative then return choice end
    end
    return choices[#choices]
end

---@param tiers PW.ChallengeTier[]
---@param requested PW.ChallengeTier
---@return boolean
local function allows(tiers, requested)
    for _, tier in ipairs(tiers) do if tier == requested then return true end end
    return false
end

---@param pool PW.ChallengeReadyCandidate[]
---@param tier PW.ChallengeTier
---@param chosen table<string, boolean>
---@param usedGroups table<string, boolean>
---@param draw PW.ChallengeDraw
---@return PW.ChallengeReadyCandidate?
local function pick(pool, tier, chosen, usedGroups, draw)
    ---@type PW.ChallengeReadyCandidate[]
    local preferred = {}
    ---@type PW.ChallengeReadyCandidate[]
    local relaxed = {}
    for _, candidate in ipairs(pool) do
        local template = candidate.template
        if not chosen[template.id] and allows(template.tiers, tier) then
            relaxed[#relaxed + 1] = candidate
            if not usedGroups[template.group] then preferred[#preferred + 1] = candidate end
        end
    end
    return weighted(#preferred > 0 and preferred or relaxed, draw)
end

---@param pool PW.ChallengeReadyCandidate[]
---@param rank integer
---@param chosen table<string, boolean>
---@param usedGroups table<string, boolean>
---@param draw PW.ChallengeDraw
---@return PW.ChallengeReadyCandidate?, PW.ChallengeTier
local function pickTier(pool, rank, chosen, usedGroups, draw)
    for fallback = rank, 1, -1 do
        local tier = tierOrder[fallback]
        local choice = pick(pool, tier, chosen, usedGroups, draw)
        if choice ~= nil then return choice, tier end
    end
    return nil, tierOrder[rank]
end

---@param candidate PW.ChallengeReadyCandidate
---@param draw PW.ChallengeDraw
---@return string, PW.ChallengeParams
local function bind(candidate, draw)
    local id = candidate.template.id
    ---@type PW.ChallengeParams
    local params = {}
    for _, domain in ipairs(candidate.domains) do
        local budget = lib._MaxInstanceId - #id - 1 - domain.reserve
        ---@type string[]
        local values = {}
        for _, value in ipairs(domain.values) do
            if #value <= budget then values[#values + 1] = value end
        end
        local value = values[math.floor(draw() * #values) + 1]
        params[domain.key], id = value, id .. "." .. value
    end
    return id, params
end

---@param item PW.ChallengeRewardItem
---@return PW.ChallengeRewardItem
local function copyItem(item)
    return { kind = item.kind, id = item.id, weapon = item.weapon }
end

---@param template PW.ChallengeTemplate
---@param tier PW.ChallengeTier
---@param defaults? table<PW.ChallengeTier, PW.ChallengeReward>
---@return PW.ChallengeReward
local function resolveReward(template, tier, defaults)
    local reward = template.definition.Rewards
    if reward ~= nil and (rawget(reward, "easy") or rawget(reward, "medium") or rawget(reward, "hard")) then
        reward = rawget(reward, tier)
    end
    return (reward or (defaults and defaults[tier]) or defaultRewards[tier]) --[[@as PW.ChallengeReward]]
end

---@param resolved PW.ChallengeReward
---@return PW.ChallengeReward
local function copyReward(resolved)
    ---@type PW.ChallengeReward
    local result = {
        xp = resolved.xp, currency = resolved.currency, duplicateCurrency = resolved.duplicateCurrency or 250
    }
    if resolved.items ~= nil then
        result.items = {}
        for index, item in ipairs(resolved.items) do result.items[index] = copyItem(item) end
    end
    return result
end

---@param template PW.ChallengeTemplate
---@param tier PW.ChallengeTier
---@return integer[]
local function targetsFor(template, tier)
    ---@type integer[]
    local targets = {}
    for index, objective in ipairs(template.objectives) do targets[index] = objective.targets[tier] end
    return targets
end

---@param candidate PW.ChallengeReadyCandidate
---@param tier PW.ChallengeTier
---@param opts PW.ChallengeSelectOptions
---@param draw PW.ChallengeDraw
---@return PW.ChallengeInstance
local function instance(candidate, tier, opts, draw)
    local template = candidate.template
    local id, params = bind(candidate, draw)
    return {
        id = id, template = template.id, tier = tier, params = params, targets = targetsFor(template, tier),
        reward = copyReward(resolveReward(template, tier, opts.tierDefaults))
    }
end

---Both wire copies of bound values share the assembled ID's total byte budget.
---Synthetic strings let the real codec count that upper bound without spending a random draw.
---@param ready PW.ChallengeReadyCandidate
---@return string, PW.ChallengeParams
local function largestBinding(ready)
    local id = ready.template.id
    ---@type PW.ChallengeParams
    local params = {}
    for _, domain in ipairs(ready.domains) do
        local limit = lib._MaxInstanceId - #id - 1 - domain.reserve
        local longest = 0
        for _, value in ipairs(domain.values) do longest = math.max(longest, #value) end
        local value = string.rep("x", math.min(limit, longest))
        params[domain.key], id = value, id .. "." .. value
    end
    return id, params
end

---@param ready PW.ChallengeReadyCandidate
---@param opts PW.ChallengeSelectOptions
---@param share integer
---@return boolean
local function fitsShare(ready, opts, share)
    local template = ready.template
    local id, params = largestBinding(ready)
    for _, tier in ipairs(template.tiers) do
        local reward = resolveReward(template, tier, opts.tierDefaults)
        if not lib._ValidWireReward(reward) then return false end
        local bits = lib._InstanceBits({ id = id, template = template.id, tier = tier, params = params,
            targets = targetsFor(template, tier), reward = reward })
        if bits > share then return false end
    end
    return true
end

---@param pool PW.ChallengeCandidate[]
---@param opts PW.ChallengeSelectOptions
---@param share integer
---@return PW.ChallengeReadyCandidate[]
local function preparePool(pool, opts, share)
    ---@type PW.ChallengeReadyCandidate[]
    local available = {}
    for _, candidate in ipairs(pool) do
        local ready = prepare(candidate)
        if ready ~= nil and fitsShare(ready, opts, share) then available[#available + 1] = ready end
    end
    table.sort(available, function(a, b) return a.template.id < b.template.id end)
    return available
end

---@param pool? PW.ChallengeRewardItem[]
---@return PW.ChallengeRewardItem[]
local function admitBonus(pool)
    ---@type PW.ChallengeRewardItem[]
    local admitted = {}
    for _, item in ipairs(pool or {}) do
        if lib._ValidWireRewardItem(item) then admitted[#admitted + 1] = item end
    end
    return admitted
end

---@param item PW.ChallengeRewardItem
---@return string
local function itemKey(item)
    local kind = item.kind == "camo" and "camos" or item.kind
    if kind == "camos" or kind == "attachments" then return kind .. ":" .. (item.weapon or "") .. ":" .. item.id end
    return kind .. ":" .. item.id
end

---@param pool? PW.ChallengeRewardItem[]
---@param draw PW.ChallengeDraw
---@return PW.ChallengeReward
local function bonusReward(pool, draw)
    ---@type PW.ChallengeReward
    local result = { xp = 10000, currency = 300, duplicateCurrency = 250 }
    if pool == nil or #pool == 0 then return result end
    ---@type { key: string, item: PW.ChallengeRewardItem }[]
    local sorted = {}
    for index, item in ipairs(pool) do sorted[index] = { key = itemKey(item), item = item } end
    table.sort(sorted, function(a, b)
        if a.key ~= b.key then return a.key < b.key end
        if a.item.kind ~= b.item.kind then return a.item.kind < b.item.kind end
        if a.item.id ~= b.item.id then return a.item.id < b.item.id end
        return (a.item.weapon or "") < (b.item.weapon or "")
    end)
    result.items = { copyItem(sorted[math.floor(draw() * #sorted) + 1].item) }
    return result
end

function lib._Select(index, pool, opts)
    local startsAt, endsAt = lib.WeekBounds(index)
    local seed, draw = generator(index, opts.seed or 0)
    local count = math.max(0, math.min(12, opts.count or 5))
    local hard = count >= 3 and math.max(1, math.floor(count / 4)) or 0
    local rest = count - hard
    local slots = { math.ceil(rest / 2), math.floor(rest / 2), hard }
    local bonusPool = admitBonus(opts.bonusPool)
    local available = preparePool(pool, opts, lib._StateShareBits(count, bonusPool))
    ---@type table<string, boolean>
    local chosen = {}
    ---@type table<string, boolean>
    local usedGroups = {}
    ---@type PW.ChallengeInstance[]
    local items = {}
    for rank = #tierOrder, 1, -1 do
        for _ = 1, slots[rank] do
            local choice, tier = pickTier(available, rank, chosen, usedGroups, draw)
            if choice ~= nil then
                local template = choice.template
                chosen[template.id], usedGroups[template.group] = true, true
                items[#items + 1] = instance(choice, tier, opts, draw)
            end
        end
    end
    table.sort(items, function(a, b)
        if a.tier ~= b.tier then return tierRank[a.tier] < tierRank[b.tier] end
        return a.id < b.id
    end)
    local needed = math.min(#items, math.max(0, opts.bonusNeeded or 4))
    return {
        index = index, label = lib.WeekLabel(index), startsAt = startsAt, endsAt = endsAt, seed = seed, items = items,
        bonus = { needed = needed, reward = bonusReward(bonusPool, draw) }
    }
end
