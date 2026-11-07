-- Kill Confirmed tags, server glue (T-2.5). Spawning (ground snap, the cap), the trigger setup, the touch handler
-- and expiry. Every decision is a pure rule of shared.lua; this file only reads the engine and acts.
--   Touch: the toucher is checked here, never trusted: a valid live player that is not an observer (spectators and
--   the dead pick nothing up), enemy or not through PW.IsEnemy against the victim kept on the server. A tag whose
--   victim is gone (left the server) is removed without a verdict.
--   Pickup marks the tag collected before anything else, drops it from the list, removes it and then fires
--   PW_KCTagCollected(collector, victim, verdict) (a notification: listeners must not return a value).
--   Expiry: the tag's own think is scheduled at its expiry time (NextThink), so a tag without a lifetime never thinks.

local lib = PW.KCTags --[[@as PW.KCTagsLib]]

local idle = 3600

---@param a any
---@param b any
---@return boolean
local function isEnemy(a, b)
    local check = PW.IsEnemy
    if check ~= nil then return check(a, b) end
    return a ~= b
end

---@param tag PW.KCTag
local function discard(tag)
    tag._PWCollected = true
    lib._Forget(tag)
    tag:Remove()
end

function lib._Init(tag)
    tag:SetMoveType(MOVETYPE_NONE)
    tag:SetSolid(SOLID_BBOX)
    tag:SetCollisionBounds(lib.Mins, lib.Maxs)
    tag:SetNotSolid(true)
    tag:SetTrigger(true)
    tag:AddEffects(EF_NODRAW)
    tag:DrawShadow(false)
    local at = tag:GetExpireAt()
    tag:NextThink(at > 0 and at or CurTime() + idle)
end

function lib._Think(tag)
    local now = CurTime()
    local at = tag:GetExpireAt()
    if lib._Expired(at, now) then
        discard(tag)
        return
    end
    tag:NextThink(at > 0 and at or now + idle)
    return true
end

function lib._Touch(tag, other)
    if tag._PWCollected then return nil end
    local victim = tag._PWVictim
    if not IsValid(victim) then
        discard(tag)
        return nil
    end
    local player = IsValid(other) and other:IsPlayer()
    local verdict = lib._Verdict({
        player = player,
        alive = player and other:Alive() and other:GetObserverMode() == OBS_MODE_NONE,
        enemy = player and isEnemy(other, victim)
    })
    if verdict == nil then return nil end
    discard(tag)
    PW.Notify("PW_KCTagCollected", other, victim, verdict)
    return verdict
end

---The ground under pos (within GroundTrace), or pos itself when nothing is below.
---@param pos Vector
---@return Vector
function lib._Ground(pos)
    local trace = util.TraceLine({
        start = pos + Vector(0, 0, 1),
        endpos = pos - Vector(0, 0, lib.GroundTrace),
        mask = MASK_SOLID_BRUSHONLY
    })
    if trace.Hit and not trace.StartSolid then return trace.HitPos end
    return pos
end

function lib.Spawn(pos, victim, lifetime)
    local list = lib._Tags
    for _ = 1, lib._Evict(#list, lib.MaxTags) do
        local oldest = list[1]
        if oldest == nil then break end
        if IsValid(oldest) then discard(oldest) else table.remove(list, 1) end
    end
    local tag = ents.Create(lib.Class) --[[@as PW.KCTag]]
    if not IsValid(tag) then return nil end
    tag._PWVictim = victim
    if isentity(victim) then tag:SetVictim(victim --[[@as Entity]]) end
    tag:SetExpireAt(lib._ExpireAt(CurTime(), lifetime))
    tag:SetPos(pos)
    tag:Spawn()
    list[#list + 1] = tag
    return tag
end

function lib.Drop(victim, lifetime)
    return lib.Spawn(lib._Ground(victim:GetPos()), victim, lifetime)
end

function lib.RemoveAll()
    local list = lib._Tags
    lib._Tags = {}
    for _, tag in ipairs(list) do
        if IsValid(tag) then
            tag._PWCollected = true
            tag:Remove()
        end
    end
end
