-- Hitmarker, server glue (T-6.3). After a damage event the human attacker is told with one small message. The hits
-- of one tick are merged: the first hit of an attacker schedules a flush at the end of the tick, later hits only
-- raise the kind, so a shotgun blast or an explosion is one marker. Bots are never told (nobody sees their HUD).
-- Engine calls are fields of the store, so the tests drive everything with fakes.

local lib = PW.Hitmarker --[[@as PW.HitmarkerLib]]

util.AddNetworkString("pw_hitmarker")

---@param ply Player
---@param kind integer
local function defaultSend(ply, kind)
    net.Start("pw_hitmarker")
    net.WriteUInt(kind, 2)
    net.Send(ply)
end

---@param fn fun()
local function defaultDefer(fn)
    timer.Simple(0, fn)
end

function lib._NewStore(opts)
    opts = opts or {}
    return { pending = {}, send = opts.send or defaultSend, defer = opts.defer or defaultDefer }
end

---@param store PW.HitmarkerStore
local function flush(store)
    local pending = store.pending
    store.pending = {}
    for ply, kind in pairs(pending) do
        if IsValid(ply) then store.send(ply, lib._Encode(kind)) end
    end
end

function lib._Handle(store, facts)
    if not lib._Eligible(facts.attacker, facts.victim) then return false end
    local kind = lib._Classify(facts)
    if kind == nil then return false end
    local pending = store.pending
    local first = next(pending) == nil
    pending[facts.attacker] = lib._Merge(pending[facts.attacker], kind)
    if first then store.defer(function() flush(store) end) end
    return true
end

local store = lib._NewStore()

---@param victim Entity
---@return integer
local function hitgroupOf(victim)
    if victim:IsPlayer() then return (victim --[[@as Player]]):LastHitGroup() end
    return HITGROUP_GENERIC
end

---@param victim Entity
---@return boolean
local function died(victim)
    if victim:IsPlayer() then return not (victim --[[@as Player]]):Alive() end
    return victim:Health() <= 0
end

PW.HookFor(MODULE, "PostEntityTakeDamage", function(_, victimArg, dmgArg, took)
    if not took then return end
    local victim = victimArg --[[@as Entity]]
    local dmg = dmgArg --[[@as CTakeDamageInfo]]
    if not IsValid(victim) then return end
    lib._Handle(store, {
        attacker = dmg:GetAttacker(), victim = victim, dmg = dmg:GetDamage(), killed = died(victim),
        hitgroup = hitgroupOf(victim)
    })
end)
