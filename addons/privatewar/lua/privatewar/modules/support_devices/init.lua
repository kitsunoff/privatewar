-- Owned resources; unconditional hooks are cleanup-only after module disable. Gameplay enters PW.Call.
local lib = PW.Devices --[[@as PW.DevicesLib]]
local module = MODULE
lib._Records = lib._Records or {}
lib._Damaged = lib._Damaged or setmetatable({}, { __mode = "k" })
lib._Healing = lib._Healing or setmetatable({}, { __mode = "k" })

include("privatewar/modules/support_devices/sv_placement.lua")
include("privatewar/modules/support_devices/sv_effects.lua")

function lib.List() return lib._Records end

function lib.Enabled(kind)
    local registry = PW.Registries.streaks
    local content = registry ~= nil and registry.Get(kind) or nil
    local streaks = PW.Modules.GetStored("streaks")
    return module:IsValid() and streaks ~= nil and streaks:IsValid() and content ~= nil and content:IsValid()
end

function lib.Feedback(owner, text)
    if not isentity(owner) or not IsValid(owner) then return end
    owner:SetNW2String("pw_support_notice", text)
    owner:SetNW2Float("pw_support_notice_end", CurTime() + 3)
end

function lib.Create(inst, kind, placement)
    local owner = inst._Owner --[[@as Player]]
    if not inst:IsValid() or not IsValid(owner) or not owner:Alive() or not lib.Enabled(kind)
        or not assert(PW.SupportStreaks).Capacity(lib.List(), owner, kind)
        or PW.Ask("PW_CanUseLoadoutKind", owner, "streaks") == false
        or placement == nil or not lib.Validate(owner, kind, placement.position) then return nil end
    local cfg = lib.Config[kind]
    local ent = ents.Create("pw_support_device") --[[@as PW.SupportDeviceEntity]]
    if not IsValid(ent) then return nil end
    ---@type Vector
    local mins = assert(lib.ModelBounds(kind))
    ent:SetModel(cfg.model)
    ent:SetPos(placement.position + Vector(0, 0, 2 - mins.z))
    ent:SetAngles(Angle())
    ent:Spawn()
    if not IsValid(ent:GetPhysicsObject()) then ent:Remove() return nil end
    local now = CurTime()
    local record = { owner = owner, kind = kind, entity = ent, position = placement.position, team = owner:Team(),
        ends = now + cfg.duration, instance = inst, charges = 10, receipts = {}, pulse = now }
    lib._Records[#lib._Records + 1] = record
    inst.Device = record
    ent:SetDeviceKind(kind)
    ent:SetDeviceOwner(owner)
    ent:SetDeviceEnds(record.ends)
    lib.Feedback(owner, cfg.name .. " DEPLOYED")
    return record
end

function lib.Remove(record)
    for i, held in ipairs(lib._Records) do
        if held == record then
            table.remove(lib._Records, i)
            if IsValid(record.entity) then record.entity:Remove() end
            record.instance.Device = nil
            local streaks = PW.Streaks
            if streaks ~= nil and streaks._Instances ~= nil then streaks._Instances[record.instance] = nil end
            record.instance:Remove()
            return
        end
    end
end

function lib.EntityRemoved(entity)
    for i = #lib._Records, 1, -1 do
        local record = lib._Records[i]
        if record.entity == entity then lib.Remove(record) end
    end
end

function lib.RemoveOwner(owner)
    for i = #lib._Records, 1, -1 do
        local record = lib._Records[i]
        if record.owner == owner then lib.Remove(record) end
    end
end

function lib.Clear()
    for i = #lib._Records, 1, -1 do lib.Remove(lib._Records[i]) end
    lib._Healing = setmetatable({}, { __mode = "k" })
end

---@param entity Entity
---@param damage CTakeDamageInfo
function MODULE:DamageDevice(entity, damage)
    local attacker = damage:GetAttacker()
    for _, record in ipairs(lib._Records) do
        if record.entity == entity then
            local world = IsValid(attacker) and attacker:IsWorld()
            local hostile = IsValid(attacker) and attacker:IsPlayer()
                and PW.IsEnemy(attacker --[[@as Player]], record.owner)
            if not assert(PW.SupportStreaks).DamageAllowed(hostile, world) then return end
            entity:SetHealth(entity:Health() - math.max(0, damage:GetDamage()))
            if entity:Health() <= 0 then lib.Remove(record) end
            return
        end
    end
end

function lib.Damage(entity, damage) PW.Call(module, "DamageDevice", entity, damage) end

local nextTick = 0
hook.Add("Think", "PW.SupportDevices", function()
    if not module:IsValid() then lib.Clear() return end
    local now = CurTime()
    if now < nextTick then return end
    local dt = math.min(1, math.max(0, now - nextTick + 0.25))
    nextTick = now + 0.25
    PW.Call(module, "Maintain", now, dt)
end)

PW.HookFor(module, "EntityTakeDamage", function(_, entity, damage)
    if entity:IsPlayer() and damage:GetDamage() > 0 then
        lib._Damaged[entity --[[@as Player]]] = CurTime()
        lib._Healing[entity --[[@as Player]]] = nil
    end
end)

function MODULE:PW_PlayerTeamChanged(owner) lib.RemoveOwner(owner) end
function MODULE:PW_RoundPreparing() lib.Clear() end
function MODULE:PW_MatchEnd() lib.Clear() end
PW.HookFor(module, "PlayerDisconnected", function(_, owner) lib.RemoveOwner(owner) end)
hook.Add("PreCleanupMap", "PW.SupportDevices", lib.Clear)
hook.Add("ShutDown", "PW.SupportDevices", lib.Clear)
hook.Add("PW_EntityDisabled", "PW.SupportDevices", function(kind, _, definition)
    if (kind == "modules" and (definition == module or definition == PW.Modules.GetStored("streaks"))) then
        lib.Clear()
    elseif kind == "streaks" then
        for i = #lib._Records, 1, -1 do
            local record = lib._Records[i]
            if record.instance._Definition == definition then lib.Remove(record) end
        end
    end
end)
