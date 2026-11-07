-- Capture only after synchronous base spawn completion. Refresh is never a heal.
local lib = PW.PlayerOverrides --[[@as PW.PlayerOverridesLib]]

---@type table<Player, PW.PlayerOverrideBaseline>
local held = PW._PlayerOverrideBaselines or setmetatable({}, { __mode = "k" })
PW._PlayerOverrideBaselines = held

---@param value any
---@return boolean
local function positive(value)
    return isnumber(value) and value > 0 and value < math.huge
end

---@param profile any
---@param baseline PW.PlayerOverrideBaseline
---@return boolean
local function valid(profile, baseline)
    if not istable(profile) then return false end
    for _, key in ipairs({ "maxHealth", "spawnHealth", "walkSpeedMult", "runSpeedMult" }) do
        if profile[key] ~= nil and not positive(profile[key]) then return false end
    end
    return (profile.spawnHealth or 0) <= (profile.maxHealth or baseline.max)
end

---@param ply Player
---@return PW.PlayerOverrideBaseline
local function capture(ply)
    return { max = ply:GetMaxHealth(), walk = ply:GetWalkSpeed(), run = ply:GetRunSpeed() }
end

function lib.Release(ply)
    local baseline = held[ply]
    if baseline == nil then return false end
    held[ply] = nil
    if not IsValid(ply) then return true end
    ply:SetMaxHealth(baseline.max)
    ply:SetWalkSpeed(baseline.walk)
    ply:SetRunSpeed(baseline.run)
    if ply:Alive() and ply:Health() > baseline.max then ply:SetHealth(baseline.max) end
    return true
end

---@param ply Player
---@param spawned boolean
---@return boolean, string?
local function apply(ply, spawned)
    if not IsValid(ply) or not ply:IsPlayer() then return false, "invalid player" end
    local profile = PW.Ask("PW_PlayerOverrides", ply)
    if profile == nil then lib.Release(ply) return false, "no provider" end
    local baseline = held[ply] or capture(ply)
    if not valid(profile, baseline) then return false, "invalid profile" end
    held[ply] = baseline
    ply:SetMaxHealth(profile.maxHealth or baseline.max)
    ply:SetWalkSpeed(baseline.walk * (profile.walkSpeedMult or 1))
    ply:SetRunSpeed(baseline.run * (profile.runSpeedMult or 1))
    if spawned and profile.spawnHealth ~= nil and ply:Alive() then ply:SetHealth(profile.spawnHealth) end
    return true
end

function lib.Refresh(ply)
    return apply(ply, false)
end

---@param ply Player
function MODULE:PW_PlayerSpawned(ply)
    held[ply] = nil -- a new life has already received ordinary engine initialization
    apply(ply, true)
end

function MODULE:PW_MatchEnd()
    for ply in pairs(held) do lib.Release(ply) end
end

PW.HookFor(MODULE, "PlayerDisconnected", function(_, ply) held[ply] = nil end)
