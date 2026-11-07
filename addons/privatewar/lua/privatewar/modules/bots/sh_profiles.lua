-- Bot profiles (T-5.12; 07-bots.md d.10, d.15): the difficulty tiers and personalities are data (kinds
-- bot_difficulties and bot_personalities, registries PW.BotDifficulties and PW.BotPersonalities); this library is the
-- pure glue around them: the tier lookup with the regular fallback, the field registry ("every field of every file is
-- read somewhere"), the mix of tiers and the 4:1 personality rule. It lives in the `bots` module because that is
-- the first of the bots_* modules to load, so the consumers (loaded after it) can declare their reads at load time.
--
-- Decisions of the lane agent (to confirm):
--   1. A field registry, not a scan: a consumer declares PW.BotProfiles.Reads("difficulty", "aim", { ... }) with the
--      fields it reads and then reads exactly those through Pick; the test fails for a data field nobody declares and
--      for a declared field that a file lacks.
--   2. The setting bots.difficulty is the 4 tier ids plus "mix": every bot gets a tier by the weights in Config.
--   3. A board without a difficulty (tests, a bot the manager does not own yet) reads the regular tier.

local lib = (rawget(PW, "BotProfiles") or {}) --[[@as PW.BotProfilesLib]]
PW.BotProfiles = lib

lib.Fallback = "regular"
lib.Mix = "mix"
---Weights of the tiers for the setting value "mix" (a bell around the middle tiers).
lib.MixWeights = { recruit = 1, regular = 2, hardened = 2, veteran = 1 }
---The per-team personality ratio of 07 d.10: four active bots for one stationary.
lib.Ratio = { active = 4, stationary = 1 }
---Registry fields that are not data fields of a profile file.
lib.MetaFields = { ClassName = true, BaseClass = true, Base = true, Abstract = true, Name = true, Description = true }

---@type table<PW.BotProfileKind, string>
local registryNames = { difficulty = "BotDifficulties", personality = "BotPersonalities" }

---Declarations survive a reload of this file: a consumer declares again when its own module reloads.
lib.Declared = lib.Declared or { difficulty = {}, personality = {} }

---@param roll number
---@return number
local function clamp01(roll)
    return math.min(math.max(roll, 0), 0.999999)
end

function lib.Reads(kind, consumer, fields)
    local byConsumer = lib.Declared[kind]
    ---@type string[]
    local copy = {}
    for i, field in ipairs(fields) do copy[i] = field end
    byConsumer[consumer] = copy
end

function lib.Readers(kind)
    ---@type table<string, string[]>
    local readers = {}
    for consumer, fields in pairs(lib.Declared[kind]) do
        for _, field in ipairs(fields) do
            readers[field] = readers[field] or {}
            table.insert(readers[field], consumer)
        end
    end
    return readers
end

function lib.Fields(entity)
    ---@type string[]
    local list = {}
    for key, value in pairs(entity --[[@as table<any, any>]]) do
        if isstring(key) and not lib.MetaFields[key] and not isfunction(value) and string.sub(key, 1, 1) ~= "_" then
            list[#list + 1] = key
        end
    end
    table.sort(list)
    return list
end

function lib.Audit(kind, entities)
    local readers = lib.Readers(kind)
    ---@type string[]
    local problems = {}
    for _, entity in ipairs(entities) do
        ---@type table<string, true>
        local own = {}
        for _, field in ipairs(lib.Fields(entity)) do
            own[field] = true
            if readers[field] == nil then
                problems[#problems + 1] = string.format("%s.%s is read by nobody", tostring(entity.ClassName), field)
            end
        end
        for field, consumers in pairs(readers) do
            if not own[field] then
                problems[#problems + 1] = string.format("%s lacks %s (read by %s)", tostring(entity.ClassName), field,
                    table.concat(consumers, ", "))
            end
        end
    end
    table.sort(problems)
    return problems
end

function lib.Entities(kind)
    local registry = rawget(PW, registryNames[kind]) --[[@as PW.Registry?]]
    if registry == nil then return {} end
    return registry.GetEnabledList()
end

function lib.Tier(id)
    local registry = rawget(PW, registryNames.difficulty) --[[@as PW.Registry?]]
    if registry == nil then return {} end
    return registry.Get(id or lib.Fallback) or registry.Get(lib.Fallback) or {}
end

function lib.TierExists(id)
    local registry = rawget(PW, registryNames.difficulty) --[[@as PW.Registry?]]
    return registry ~= nil and registry.Get(id) ~= nil
end

function lib.Pick(fields, difficulty, tier)
    local base = lib.Tier(tier) --[[@as table<string, any>]]
    local over = (istable(difficulty) and difficulty or {}) --[[@as table<string, any>]]
    ---@type table<string, any>
    local out = {}
    for _, field in ipairs(fields) do
        local value = over[field]
        if value ~= nil and type(value) == type(base[field]) then out[field] = value else out[field] = base[field] end
    end
    return out
end

function lib.Snapshot(entity)
    local source = entity --[[@as table<string, any>]]
    ---@type table<string, any>
    local copy = { ClassName = source.ClassName, Name = source.Name }
    for _, field in ipairs(lib.Fields(entity)) do copy[field] = source[field] end
    return copy
end

function lib.ResolveTier(value, roll)
    if value ~= lib.Mix then return lib.TierExists(value) and value or lib.Fallback end
    ---@type string[]
    local ids = {}
    for _, entity in ipairs(lib.Entities("difficulty")) do ids[#ids + 1] = entity.ClassName end
    table.sort(ids)
    ---@type number
    local total = 0
    for _, id in ipairs(ids) do total = total + (lib.MixWeights[id] or 1) end
    if total <= 0 then return lib.Fallback end
    ---@type number
    local point = clamp01(roll) * total
    for _, id in ipairs(ids) do
        point = point - (lib.MixWeights[id] or 1)
        if point < 0 then return id end
    end
    return ids[#ids]
end

function lib.NextType(active, stationary)
    local total = active + stationary + 1
    if (stationary + 1) * (lib.Ratio.active + lib.Ratio.stationary) <= total * lib.Ratio.stationary then
        return "stationary"
    end
    return "active"
end

function lib.PickPersonality(kind, roll)
    ---@type PW.Entity[]
    local matching = {}
    for _, entity in ipairs(lib.Entities("personality")) do
        if (entity --[[@as table<string, any>]]).type == kind then matching[#matching + 1] = entity end
    end
    if #matching == 0 then return nil end
    table.sort(matching, function(a, b) return a.ClassName < b.ClassName end)
    return matching[math.min(#matching, math.floor(clamp01(roll) * #matching) + 1)]
end
