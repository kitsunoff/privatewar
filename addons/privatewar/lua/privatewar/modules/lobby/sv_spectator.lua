-- Optional server-owned camera restriction. No client-selected entity or foreign roster/private-store access.
local lib = PW.Jip --[[@as PW.JipLib]]
---@class PW.SpectatorRestriction
---@field eligible table<integer, boolean>
---@field teams table<integer, integer>

---@type table<Player, PW.SpectatorRestriction>
local restricted = setmetatable({}, { __mode = "k" })

---@param policy any
---@return table<integer, boolean>?
local function allowedOf(policy)
    if policy == nil then return nil end
    ---@type table<integer, boolean>
    local allowed = {}
    if not istable(policy) or policy.restricted ~= true or not istable(policy.eligible) then return allowed end
    local count = 0
    for id, value in pairs(policy.eligible --[[@as table<any, any>]]) do
        count = count + 1
        if count > 128 then return {} end
        if isnumber(id) and id > 0 and id < math.huge and id == math.floor(id) and value == true then
            allowed[id] = true
        end
    end
    return allowed
end

---@param allowed table<integer, boolean>?
---@param candidates PW.SpectatorCandidate[]
---@param currentId? integer
---@return "roaming"|"fixed"|"follow", integer?
local function choose(allowed, candidates, currentId)
    if allowed == nil then return "roaming" end
    ---@type integer?
    local first
    for _, candidate in ipairs(candidates) do
        if candidate.alive and allowed[candidate.id] == true then
            if candidate.id == currentId then return "follow", currentId end
            if first == nil or candidate.id < first then first = candidate.id end
        end
    end
    if first ~= nil then return "follow", first end
    return "fixed"
end

function lib.SpectatorChoice(policy, candidates, currentId)
    return choose(allowedOf(policy), candidates, currentId)
end

---@param ply Entity?
---@return integer?
local function userId(ply)
    if not IsValid(ply) or not assert(ply):IsPlayer() then return nil end
    return (ply --[[@as Player]]):UserID()
end

---@param ply Player
---@param exclude? Player
---@return boolean
local function refresh(ply, exclude)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    local allowed = allowedOf(PW.Ask("PW_SpectatorPolicy", ply))
    if allowed == nil then restricted[ply] = nil return false end
    ---@type PW.SpectatorRestriction
    local restriction = { eligible = allowed, teams = {} }
    restricted[ply] = restriction
    ---@type PW.SpectatorCandidate[]
    local candidates = {}
    ---@type table<integer, Player>
    local byId = {}
    for _, target in ipairs(player.GetAll()) do
        if target ~= ply and target ~= exclude and IsValid(target) then
            local id = target:UserID()
            candidates[#candidates + 1] = { id = id,
                alive = target:Alive() and target:GetObserverMode() == OBS_MODE_NONE }
            byId[id] = target
            restriction.teams[id] = target:Team()
        end
    end
    local current = userId(ply:GetObserverTarget())
    local decision, id = choose(allowed, candidates, current)
    if decision == "follow" and id == current and ply:GetObserverMode() == OBS_MODE_IN_EYE then return true end
    -- Detach first, never pass through a roaming/unauthorized view while selecting another target.
    ply:Spectate(OBS_MODE_FIXED)
    ply:SpectateEntity(NULL)
    if decision == "follow" then
        local target = id ~= nil and byId[id] or nil
        if IsValid(target) then
            ply:Spectate(OBS_MODE_IN_EYE)
            ply:SpectateEntity(assert(target))
        end
    end
    return true
end

function lib.RefreshSpectator(ply) return refresh(ply) end

---@param exclude? Player
local function refreshAll(exclude)
    for _, ply in ipairs(player.GetAll()) do
        if ply == exclude or not ply:Alive() or ply:GetObserverMode() ~= OBS_MODE_NONE then refresh(ply, exclude) end
    end
end

PW.HookFor(MODULE, "PlayerDeath", function(_, ply) refreshAll(ply) end)
PW.HookFor(MODULE, "PlayerDisconnected", function(_, ply) restricted[ply] = nil refreshAll(ply) end)
PW.HookFor(MODULE, "SetupPlayerVisibility", function(_, ply)
    ---@cast ply Player
    local restriction = restricted[ply]
    if restriction == nil then return end
    if ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE then restricted[ply] = nil return end
    local target = ply:GetObserverTarget()
    local id = userId(target)
    local candidate = target --[[@as Player]]
    local valid = id ~= nil and restriction.eligible[id] == true and candidate:Alive()
        and candidate:GetObserverMode() == OBS_MODE_NONE and candidate:Team() == restriction.teams[id]
    if not valid or ply:GetObserverMode() ~= OBS_MODE_IN_EYE then refresh(ply) end
end)

---@param ply Player
function MODULE:PW_PlayerTeamChanging(ply) refreshAll(ply) end
function MODULE:PW_PlayerTeamChanged() refreshAll() end
function MODULE:PW_RoundPreparing() refreshAll() end
function MODULE:PW_RoundPrepared() refreshAll() end
function MODULE:PW_PlayerSpawned() refreshAll() end
function MODULE:PW_MatchEnd() restricted = setmetatable({}, { __mode = "k" }) end
