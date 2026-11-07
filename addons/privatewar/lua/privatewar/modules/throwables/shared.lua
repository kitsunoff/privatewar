-- Throwables module (T-4.5; 05-loadout.md d.11: quick throw is a helper of a throwables module; items may use it or
-- not, the loadout module knows nothing about throwing). Shared and pure: the throw vector, the fuse, the flash
-- strength and the blind fade. Also the generic projectile entity pw_grenade (a physics model with an owner; the
-- fuse is PW.Throw's). PW.Throw and the blind message are init.lua; the white screen is cl_init.lua.
--
-- Wire (server -> client, "pw_blind"): one UInt(8), the strength times 255.
--
-- Gameplay values (lane agent decisions): throw 900 u/s along the aim plus 180 u/s up, spawned 18 units in front
-- of the eye, the thrower's velocity added; default fuse 3 s, clamped to 0.05..10 s. Flash: radius 1500, full
-- strength inside 300 when facing it, 0.2 of it when facing away, linear falloff to the radius, no effect without
-- line of sight; a full blind lasts 4 s (white held for the first 30 %, then fading).

MODULE.Name = "Throwables"

local lib = (rawget(PW, "Throwables") or {}) --[[@as PW.ThrowablesLib]]
PW.Throwables = lib

lib.Defaults = { speed = 900, lift = 180, forward = 18, fuse = 3, minFuse = 0.05, maxFuse = 10 }
lib.Flash = { radius = 1500, near = 300, behind = 0.2, maxTime = 4, minStrength = 0.05 }
lib.EntityClass = "pw_grenade"

local hold = 0.3

function lib._Launch(eye, aim, ownerVel, opts)
    local d = lib.Defaults
    opts = opts or {}
    local dir = aim:GetNormalized()
    local pos = eye + dir * (opts.forward or d.forward)
    local vel = dir * (opts.speed or d.speed) + Vector(0, 0, opts.lift or d.lift)
    if ownerVel ~= nil then vel = vel + ownerVel end
    return pos, vel
end

function lib._Fuse(opts)
    local d = lib.Defaults
    local fuse = d.fuse
    if opts ~= nil then fuse = opts.cook or opts.fuse or fuse end
    return math.Clamp(fuse, d.minFuse, d.maxFuse)
end

function lib._FlashStrength(dist, dot, visible)
    local f = lib.Flash
    if not visible or dist >= f.radius then return 0 end
    local distance = 1
    if dist > f.near then distance = 1 - (dist - f.near) / (f.radius - f.near) end
    -- Facing within 60 degrees (dot >= 0.5) is full; facing away (dot = -1) is the floor.
    local angle = math.Clamp((dot + 1) / 1.5, f.behind, 1)
    return math.Clamp(distance * angle, 0, 1)
end

function lib._BlindTime(strength)
    return lib.Flash.maxTime * math.Clamp(strength, 0, 1)
end

function lib._BlindAlpha(age, strength)
    local total = lib._BlindTime(strength)
    if total <= 0 or age >= total then return 0 end
    local peak = math.min(1, strength * 2)
    local held = total * hold
    if age <= held then return peak end
    return peak * (1 - (age - held) / (total - held))
end

function lib._EncodeStrength(strength)
    return math.Clamp(math.floor(strength * 255 + 0.5), 0, 255)
end

function lib._DecodeStrength(byte)
    return math.Clamp(byte / 255, 0, 1)
end

-- The projectile: a physics model with an owner (the owner does not collide with it). Bounce sounds only.
local defaultModel = "models/weapons/w_grenade.mdl"
local grenade = { Type = "anim", Base = "base_anim", PrintName = "Grenade", Spawnable = false, AdminOnly = true }

function grenade:Initialize()
    if CLIENT then return end
    local ent = self --[[@as Entity]]
    if ent:GetModel() == nil or ent:GetModel() == "" then ent:SetModel(defaultModel) end
    ent:PhysicsInit(SOLID_VPHYSICS)
    ent:SetMoveType(MOVETYPE_VPHYSICS)
    ent:SetSolid(SOLID_VPHYSICS)
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

---@param data CollisionData
function grenade:PhysicsCollide(data)
    if data.Speed > 80 and data.DeltaTime > 0.2 then
        (self --[[@as Entity]]):EmitSound("physics/metal/metal_grenade_impact_hard" .. math.random(1, 3) .. ".wav")
    end
end

scripted_ents.Register(grenade, lib.EntityClass)
