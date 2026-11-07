-- Search and Destroy: pure authoritative rules; engine and bounded replication are separate wrappers.
MODULE.Name = "Search and Destroy"
local lib = (rawget(PW, "SND") or {}) --[[@as PW.SNDLib]]
PW.SND = lib

function lib.Inside(site, pos)
    local delta = pos - site.pos
    return delta.x * delta.x + delta.y * delta.y <= site.radius * site.radius
        and delta.z >= -site.below and delta.z <= site.above
end

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

---@param site table<string, any>
---@return boolean
local function validSite(site)
    return isstring(site.id) and #site.id > 0 and #site.id <= 32 and vector(site.pos) and vector(site.approach)
        and finite(site.radius) and site.radius > 0 and finite(site.above) and site.above >= 0
        and finite(site.below) and site.below >= 0 and lib.Inside(site --[[@as PW.SNDSite]], site.approach)
end

function lib.Validate(data)
    ---@cast data table<string, any>
    if not istable(data) or not istable(data.sites) or #data.sites ~= 2 or not vector(data.bomb)
        or not istable(data.spawns) then return false, "S&D needs two sites, a bomb point and side spawns" end
    ---@type table<string, boolean>
    local ids = {}
    for _, site in ipairs(data.sites --[[@as table<string, any>[] ]]) do
        if not istable(site) or not validSite(site) or ids[site.id] then return false, "Invalid S&D site" end
        ids[site.id] = true
    end
    for side = 1, 2 do
        local spawns = data.spawns[side] --[[@as table<string, any>[]?]]
        if not istable(spawns) or #spawns < 1 or #spawns > 64 then return false, "Missing S&D side spawns" end
        for _, spawn in ipairs(assert(spawns)) do
            if not istable(spawn) or not vector(spawn.pos) or not finite(spawn.yaw) then
                return false, "Invalid S&D spawn"
            end
        end
    end
    return true
end

function lib.NewRound(map, actors, now, generation, carrierId)
    ---@type PW.SNDState
    local state = { generation = generation, deadline = now + 120, map = map, roster = {}, phase = "dropped",
        pos = map.bomb, fuse = 0 }
    for _, actor in ipairs(actors) do
        state.roster[actor.id] = { userId = actor.userId, team = actor.team, alive = true,
            connected = true, spawned = false }
        if actor.team == 1 and (state.carrier == nil or actor.id == carrierId) then state.carrier = actor.id end
    end
    if state.carrier ~= nil then state.phase = "carried" end
    return state
end

function lib.Admit(state, id, userId)
    local member = state.roster[id]
    if member == nil or member.userId ~= userId or member.spawned or not member.connected
        or not member.alive then return false end
    member.spawned = true
    return true
end

function lib.Death(state, id, userId, pos, now)
    local member = state.roster[id]
    if member == nil or member.userId ~= userId or not member.alive then return false end
    member.alive = false
    if state.interaction ~= nil and state.interaction.id == id then state.interaction = nil end
    if state.carrier ~= id or state.phase ~= "carried" then return false end
    if now >= state.deadline then return false end
    state.phase, state.carrier = "dropped", nil
    state.pos = vector(pos) and pos or state.map.bomb
    return true
end

function lib.Disconnect(state, id, userId, pos, now)
    local dropped = lib.Death(state, id, userId, pos, now)
    local member = state.roster[id]
    if member ~= nil and member.userId == userId then member.connected = false end
    return dropped
end

if SERVER then AddCSLuaFile("privatewar/modules/snd/sh_round.lua") end
include("privatewar/modules/snd/sh_round.lua")
if SERVER then AddCSLuaFile("privatewar/modules/snd/sh_objectives.lua") end
include("privatewar/modules/snd/sh_objectives.lua")
