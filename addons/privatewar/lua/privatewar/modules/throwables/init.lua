-- Throwables module, server glue (T-4.5). PW.Throw spawns a projectile with physics from the eye along the aim and
-- runs its fuse (opts.drop: dropped at the body instead, also for a dead owner); PW.Throwables.Blind tells a human
-- client to draw the white screen and notifies PW_Blinded for everyone (bots included: their perception may listen);
-- FlashAt picks the players a flash reaches. Live projectiles are removed without detonating when the match ends.

local lib = PW.Throwables --[[@as PW.ThrowablesLib]]

util.AddNetworkString("pw_blind")

---@type PW.ThrowablesStore
PW._Throwables = PW._Throwables or { live = {} }

-- Height above the feet where a grenade dropped on death starts.
local dropHeight = 24

---Where the projectile starts: the launch point, pulled back when a wall is in the way.
---@param ply Player
---@param eye Vector
---@param pos Vector
---@return Vector
local function clearStart(ply, eye, pos)
    local tr = util.TraceLine({ start = eye, endpos = pos, filter = ply, mask = MASK_SOLID })
    if not tr.Hit then return pos end
    return eye + (pos - eye) * math.max(0, tr.Fraction - 0.1)
end

---@param ent Entity
---@param owner Player
---@param opts PW.ThrowOptions
---@param token PW.ThrowableGeneration
local function detonate(ent, owner, opts, token)
    if PW._Throwables.live[ent] ~= token then return end
    PW._Throwables.live[ent] = nil
    if not IsValid(ent) then return end
    if opts.detonate ~= nil then opts.detonate(ent, owner) end
    if IsValid(ent) then ent:Remove() end
end

---@param ply Player
---@param entClass string
---@param options PW.ThrowOptions?
---@return Entity?
local function throw(ply, entClass, options)
    local opts = options or {}
    if not IsValid(ply) or not ply:IsPlayer() or not (ply:Alive() or opts.drop) then return nil end
    local eye = ply:EyePos()
    local pos, vel = lib._Launch(eye, ply:GetAimVector(), ply:GetVelocity(), opts)
    -- A death drop falls from the body's waist with the body's velocity (speed and lift are 0).
    if opts.drop then
        eye = ply:GetPos() + Vector(0, 0, dropHeight)
        pos = eye
    end
    local ent = ents.Create(entClass)
    if not IsValid(ent) then return nil end
    if opts.model ~= nil then ent:SetModel(opts.model) end
    if opts.color ~= nil then ent:SetColor(opts.color) end
    ent:SetPos(clearStart(ply, eye, pos))
    ent:SetAngles(ply:EyeAngles())
    ent:SetOwner(ply)
    ent:Spawn()
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(vel)
        phys:AddAngleVelocity(Vector(0, 600, 0))
    end
    local token = { owner = ply }
    PW._Throwables.live[ent] = token
    timer.Simple(lib._Fuse(opts), function() detonate(ent, ply, opts, token) end)
    return ent
end

PW.Throw = throw
lib.Throw = throw

function lib.Revoke(owner)
    local live = PW._Throwables.live
    for ent, token in pairs(live) do
        local matches = istable(token) and token.owner == owner
            or (token == true and IsValid(ent) and ent:GetOwner() == owner)
        if matches then
            live[ent] = nil
            if IsValid(ent) then ent:Remove() end
        end
    end
end

function lib.Blind(ply, strength)
    if not IsValid(ply) or strength < lib.Flash.minStrength then return false end
    local seconds = lib._BlindTime(strength)
    local store = assert(PW._Throwables)
    store.blind = store.blind or setmetatable({}, { __mode = "k" })
    local previous = store.blind[ply]
    store.blind[ply] = { untilTime = CurTime() + seconds,
        dsp = strength >= 0.5 or (previous ~= nil and previous.dsp and previous.untilTime > CurTime()) }
    if not ply:IsBot() then
        net.Start("pw_blind")
        net.WriteUInt(lib._EncodeStrength(strength), 8)
        net.Send(ply)
        if strength >= 0.5 then ply:SetDSP(35, false) end
    end
    PW.Notify("PW_Blinded", ply, strength, seconds)
    return true
end

---@param pos Vector
---@param ply Player
---@param inflictor Entity?
---@return boolean
local function seen(pos, ply, inflictor)
    local tr = util.TraceLine({ start = pos, endpos = ply:EyePos(), filter = { inflictor, ply }, mask = MASK_OPAQUE })
    return not tr.Hit
end

function lib.FlashAt(pos, inflictor)
    local blinded = 0
    local radius = lib.Flash.radius
    -- player.Iterator allocates nothing, unlike player.GetAll.
    ---@type fun(): (fun(): integer?, Player?)
    local iterator = player.Iterator
    for _, entry in iterator() do
        local ply = entry --[[@as Player]]
        local eye = ply:EyePos()
        local dist = eye:Distance(pos)
        if ply:Alive() and dist < radius then
            local dot = ply:GetAimVector():Dot((pos - eye):GetNormalized())
            if lib.Blind(ply, lib._FlashStrength(dist, dot, seen(pos, ply, inflictor))) then blinded = blinded + 1 end
        end
    end
    return blinded
end

function lib._RemoveAll()
    local live = PW._Throwables.live
    PW._Throwables.live = {}
    for ent in pairs(live) do
        if IsValid(ent) then ent:Remove() end
    end
end

---Only this owner's active flash is cancelled; already expired DSP or unrelated players are not reset.
local function clearBlind()
    local store = assert(PW._Throwables)
    local blind = store.blind or {}
    store.blind = setmetatable({}, { __mode = "k" })
    for ply, effect in pairs(blind) do
        if IsValid(ply) then
            if effect.dsp and effect.untilTime > CurTime() then ply:SetDSP(0, false) end
            if not ply:IsBot() then
                net.Start("pw_blind")
                net.WriteUInt(0, 8)
                net.Send(ply)
            end
        end
    end
end

function MODULE:PW_MatchEnd()
    lib._RemoveAll()
    clearBlind()
end

function MODULE:PW_RoundEnd()
    lib._RemoveAll()
    clearBlind()
end
