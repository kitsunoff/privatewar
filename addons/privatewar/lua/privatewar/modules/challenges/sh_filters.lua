-- Compile the vocabulary to field checks before any event is delivered. Bind parameter values once per instance.
local lib = PW.Challenges --[[@as PW.ChallengesLib]]

---@alias PW.ChallengeComparisonKind "string"|"boolean"|"number"|"scalar"
---@alias PW.ChallengeFieldCheck fun(value: any): boolean
---@alias PW.ChallengeFieldBind fun(params: PW.ChallengeParams): PW.ChallengeFieldCheck
---@class PW.ChallengeFilterRule
---@field field string
---@field on? table<string, boolean>
---@field kind? PW.ChallengeComparisonKind
---@field op? "min"|"max"|"playlist"|"list"|"set"

local kill = { kill = true }
local ends = { match_end = true, round_end = true }

---@type table<string, PW.ChallengeFilterRule>
local rules = {
    mode = { field = "mode", kind = "string" },
    modeBase = { field = "modeBase", kind = "string", op = "list" },
    playlist = { field = "playlist", kind = "string", op = "playlist" },
    weapon = { field = "weapon", on = kill, kind = "string" },
    category = { field = "weaponCategory", on = kill, kind = "string" },
    weaponKind = { field = "weaponKind", on = kill, kind = "string" },
    attachment = { field = "attachments", on = kill, kind = "string", op = "set" },
    headshot = { field = "headshot", on = kill, kind = "boolean" },
    distanceMin = { field = "distance", on = kill, op = "min" },
    distanceMax = { field = "distance", on = kill, op = "max" },
    ads = { field = "ads", on = kill, kind = "boolean" },
    crouch = { field = "crouch", on = kill, kind = "boolean" },
    airborne = { field = "airborne", on = kill, kind = "boolean" },
    victimBot = { field = "victimBot", on = kill, kind = "boolean" },
    explosive = { field = "explosive", on = kill, kind = "boolean" },
    streakKill = { field = "streakKill", on = kill, kind = "boolean" },
    streak = { field = "streak", on = { kill = true, streak_earned = true, streak_used = true }, kind = "string" },
    lifeKillsMin = { field = "lifeKills", on = kill, op = "min" },
    aliveTimeMax = { field = "aliveTime", on = kill, op = "max" },
    event = { field = "scoreEvent", on = { score = true }, kind = "string" },
    medal = { field = "medal", on = { medal = true }, kind = "string" },
    objective = { field = "objective", on = { objective = true }, kind = "string" },
    won = { field = "won", on = ends, kind = "boolean" },
    draw = { field = "draw", on = ends, kind = "boolean" },
    placementMax = { field = "placement", on = { match_end = true }, op = "max" },
    valueMin = { field = "value", op = "min" },
    suicide = { field = "suicide", on = { death = true }, kind = "boolean" }
}

function lib._ArrayLength(value)
    if type(value) ~= "table" then return nil end
    ---@cast value table<any, any>
    local size, seen = #value, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > size or key % 1 ~= 0 then return nil end
        seen = seen + 1
    end
    if seen == size then return size end
    return nil
end

---@param value any
---@return boolean
local function finite(value)
    return type(value) == "number" and math.abs(value) < math.huge
end

---@param value any
---@param kind PW.ChallengeComparisonKind
---@return boolean
local function validValue(value, kind)
    if kind == "scalar" then
        return type(value) == "string" or type(value) == "boolean" or finite(value)
    end
    if kind == "number" then return finite(value) end
    return type(value) == kind
end

---@param input any
---@param kind PW.ChallengeComparisonKind
---@return PW.ChallengeValue[]?
local function choicesOf(input, kind)
    if validValue(input, kind) then return { input } end
    if type(input) ~= "table" then return nil end
    ---@cast input table<any, any>
    local size = lib._ArrayLength(input)
    if size ~= nil then
        local validList = true
        for index = 1, size do
            if not validValue(input[index], kind) then validList = false break end
        end
        if validList then return input end
    end
    ---@type PW.ChallengeValue[]
    local choices = {}
    for key, enabled in pairs(input) do
        if type(enabled) ~= "boolean" or not validValue(key, kind) then return nil end
        if enabled then choices[#choices + 1] = key end
    end
    return choices
end

---@param input any
---@param kind PW.ChallengeComparisonKind
---@param params table<string, PW.ChallengeParam>
---@return PW.ChallengeFieldBind?, string?
local function membership(input, kind, params)
    local choices = choicesOf(input, kind)
    if choices == nil then return nil, "expected a scalar, list or set of " .. kind .. " values" end
    ---@type table<PW.ChallengeValue, boolean>
    local fixed = {}
    ---@type string[]
    local keys = {}
    for _, value in ipairs(choices) do
        local key = type(value) == "string" and string.match(value, "^%{param%.([^{}]+)%}$")
        if key then
            if params[key] == nil then return nil, "unknown parameter " .. key end
            keys[#keys + 1] = key
        else
            fixed[value] = true
        end
    end
    local function static(value) return fixed[value] == true end
    if #keys == 0 then return function() return static end end
    return function(bound)
        ---@type table<string, boolean>
        local dynamic = {}
        for _, key in ipairs(keys) do
            local value = bound[key]
            if value ~= nil then dynamic[value] = true end
        end
        return function(value) return static(value) or dynamic[value] == true end
    end
end

---@param rule PW.ChallengeFilterRule
---@param input any
---@param params table<string, PW.ChallengeParam>
---@return PW.ChallengeFieldBind?, string?
local function compare(rule, input, params)
    local op = rule.op
    if op == "min" or op == "max" then
        if not finite(input) then return nil, "expected a finite threshold" end
        if op == "min" then
            return function() return function(value) return finite(value) and value >= input end end
        end
        return function() return function(value) return finite(value) and value <= input end end
    end
    if op == "playlist" and type(input) == "boolean" then
        return function()
            return function(value) return type(value) == "string" and (value ~= "") == input end
        end
    end

    local bind, reason = membership(input, rule.kind or "scalar", params)
    if bind == nil then return nil, reason end
    if op ~= "set" and op ~= "list" then return bind end
    return function(bound)
        local contains = bind(bound)
        return function(value)
            if type(value) ~= "table" then return false end
            ---@cast value table<any, any>
            if op == "list" then
                for _, entry in ipairs(value) do
                    if contains(entry) then return true end
                end
            else
                for entry, enabled in pairs(value) do
                    if enabled == true and contains(entry) then return true end
                end
            end
            return false
        end
    end
end

---When all applicable custom events declare the same field type, it disambiguates numeric sets from boolean lists.
---@param key string
---@param events table<string, boolean>
---@param custom table<string, PW.ChallengeEventType>
---@return PW.ChallengeComparisonKind
local function dataKind(key, events, custom)
    ---@type PW.ChallengeComparisonKind?
    local shared
    for event in pairs(events) do
        local declaration = custom[event].fields
        local kind = declaration and declaration[key]
        if kind == nil or (shared ~= nil and kind ~= shared) then return "scalar" end
        shared = kind
    end
    return shared or "scalar"
end

---@param input any
---@param params table<string, PW.ChallengeParam>
---@param events table<string, boolean>
---@param custom table<string, PW.ChallengeEventType>
---@return PW.ChallengeFieldBind?, string?
local function compareData(input, params, events, custom)
    if type(input) ~= "table" then return nil, "expected a table of field rules" end
    ---@cast input table<any, any>
    ---@type table<string, PW.ChallengeFieldBind>
    local fields = {}
    for key, value in pairs(input) do
        if type(key) ~= "string" then return nil, "expected string data keys" end
        local bind, reason = membership(value, dataKind(key, events, custom), params)
        if bind == nil then return nil, key .. ": " .. (reason or "invalid rule") end
        fields[key] = bind
    end
    return function(bound)
        ---@type table<string, PW.ChallengeFieldCheck>
        local checks = {}
        for key, bind in pairs(fields) do checks[key] = bind(bound) end
        return function(data)
            if type(data) ~= "table" then return false end
            for key, check in pairs(checks) do
                if not check(data[key]) then return false end
            end
            return true
        end
    end
end

---@param allowed table<string, boolean>
---@param supported table<string, any>
local function limitTypes(allowed, supported)
    for event in pairs(allowed) do
        if not supported[event] then allowed[event] = nil end
    end
end

function lib._CompileFilters(input, ctx)
    if input ~= nil and type(input) ~= "table" then return nil, "Filters must be a table" end
    ---@type table<string, any>
    local filters = input or {}
    ---@type table<string, boolean>
    local allowed = {}
    for _, event in ipairs(ctx.events) do allowed[event] = true end
    ---@type { field: string, bind: PW.ChallengeFieldBind }[]
    local fields = {}
    for key, value in pairs(filters) do
        local rule = rules[key]
        ---@type PW.ChallengeFieldBind?, string?
        local bind, reason
        if key == "data" then
            limitTypes(allowed, ctx.custom)
            bind, reason = compareData(value, ctx.params, allowed, ctx.custom)
        elseif rule ~= nil then
            if rule.on ~= nil then limitTypes(allowed, rule.on) end
            bind, reason = compare(rule, value, ctx.params)
        else
            return nil, "unknown filter " .. tostring(key)
        end
        if next(allowed) == nil then return nil, "filter " .. key .. " has no compatible event type" end
        if bind == nil then return nil, "filter " .. key .. ": " .. (reason or "invalid rule") end
        fields[#fields + 1] = { field = rule and rule.field or "data", bind = bind }
    end
    return function(bound)
        ---@type PW.ChallengePredicate[]
        local checks = {}
        for index, field in ipairs(fields) do
            local name, check = field.field, field.bind(bound)
            checks[index] = function(ev) return check(rawget(ev, name)) end
        end
        return function(ev)
            if not allowed[ev.type] then return false end
            for _, check in ipairs(checks) do if not check(ev) then return false end end
            return true
        end
    end
end
