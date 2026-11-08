-- Shared objective whitelist. No enemy metadata crosses this boundary.
local lib = PW.BotCommander --[[@as PW.BotCommanderLib]]
local actions = { capture = true, hold = true, defend = true, collect = true, deny = true,
    plant = true, defuse = true }

---@param value any
---@return boolean
local function finite(value)
    return isnumber(value) and value == value and math.abs(value) < math.huge
end

---@param value any
---@return boolean
local function vector(value)
    return isvector(value) and finite(value.x) and finite(value.y) and finite(value.z)
end

---@param raw any
---@return PW.BotObjectiveZone?
local function zoneOf(raw)
    ---@cast raw table<string, any>
    if not istable(raw) or not vector(raw.pos) or not finite(raw.radius) or raw.radius <= 0
        or not finite(raw.above) or raw.above < 0 or not finite(raw.below) or raw.below < 0 then return nil end
    return { pos = Vector(raw.pos.x, raw.pos.y, raw.pos.z), radius = raw.radius,
        above = raw.above, below = raw.below }
end

---@param raw table<string, any>
---@return PW.BotObjective?
local function clean(raw)
    if not isstring(raw.id) or #raw.id < 1 or #raw.id > 64 or not vector(raw.pos)
        or not isstring(raw.action) or not actions[raw.action] then return nil end
    local radius, weight, want = tonumber(raw.radius) or 160, tonumber(raw.weight) or 0, tonumber(raw.want) or 1
    if not finite(radius) or radius <= 0 or not finite(weight) or not finite(want) then return nil end
    local revision = raw.revision
    if revision ~= nil and (not finite(revision) or revision < 0 or revision ~= math.floor(revision)) then
        return nil
    end
    if raw.eligible ~= nil and not istable(raw.eligible) then return nil end
    if (raw.action == "plant" or raw.action == "defuse")
        and (raw.eligible == nil or revision == nil or not finite(raw.radius) or raw.radius <= 0) then
        return nil
    end
    ---@type PW.BotObjective
    local out = { id = raw.id, pos = Vector(raw.pos.x, raw.pos.y, raw.pos.z), radius = radius,
        action = raw.action, weight = math.Clamp(weight, 0, 1), want = math.Clamp(math.floor(want), 0, 128),
        revision = revision }
    if raw.eligible ~= nil then
        out.eligible = {}
        for id, allowed in pairs(raw.eligible --[[@as table<any, any>]]) do
            if finite(id) and id > 0 and id == math.floor(id) and allowed == true then out.eligible[id] = true end
        end
    end
    if raw.zone ~= nil then
        out.zone = zoneOf(raw.zone)
        if out.zone == nil then return nil end
    end
    return out
end

function lib.Sanitize(raw)
    ---@type PW.BotObjective[]
    local out = {}
    ---@type table<string, boolean>
    local seen = {}
    if not istable(raw) then return out end
    for i, entry in ipairs(raw --[[@as any[] ]]) do
        if i > 64 then break end
        local obj = istable(entry) and clean(entry) or nil
        if obj ~= nil and seen[obj.id] then return {} end
        if obj ~= nil then seen[obj.id] = true out[#out + 1] = obj end
    end
    return out
end

function lib.Eligible(objective, botId)
    local eligible = objective.eligible
    if eligible == nil then return objective.action ~= "plant" and objective.action ~= "defuse" end
    return istable(eligible) and botId > 0 and eligible[botId] == true
end

function lib.Inside(objective, pos)
    local zone = objective.zone
    if zone == nil then return pos:DistToSqr(objective.pos) <= objective.radius * objective.radius end
    local delta = pos - zone.pos
    return delta.x * delta.x + delta.y * delta.y <= zone.radius * zone.radius
        and delta.z >= -zone.below and delta.z <= zone.above
end

function lib.ArrivalFits(objective, projected, radius)
    local zone = objective.zone
    if zone == nil then return true end
    if not finite(radius) or radius < 0 or radius > zone.radius or not lib.Inside(objective, projected) then
        return false
    end
    local delta = projected - zone.pos
    return delta.x * delta.x + delta.y * delta.y <= (zone.radius - radius) ^ 2
end
