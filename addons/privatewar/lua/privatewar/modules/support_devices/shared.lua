-- Three bounded, visible stock-model support devices. No autonomous weapons or hidden position wire.
MODULE.Name = "Support devices"
local lib = (rawget(PW, "Devices") or {}) --[[@as PW.DevicesLib]]
PW.Devices = lib

lib.Config = {
    ammo_cache = { model = "models/items/boxsrounds.mdl", name = "AMMUNITION CACHE", duration = 45, radius = 160 },
    medical_station = { model = "models/items/healthkit.mdl", name = "MEDICAL STATION", duration = 30, radius = 180 },
    ground_sensor = { model = "models/props_lab/reciever01b.mdl", name = "GROUND SENSOR", duration = 30, radius = 600 }
}

local device = { Type = "anim", Base = "base_anim", PrintName = "Support device", Spawnable = false }

function device:SetupDataTables()
    local ent = self --[[@as Entity]]
    ent:NetworkVar("String", 0, "DeviceKind")
    ent:NetworkVar("Entity", 0, "DeviceOwner")
    ent:NetworkVar("Float", 0, "DeviceEnds")
end

function device:Initialize()
    if CLIENT then return end
    local ent = self --[[@as Entity]]
    ent:PhysicsInit(SOLID_VPHYSICS)
    ent:SetMoveType(MOVETYPE_NONE)
    ent:SetSolid(SOLID_VPHYSICS)
    ent:SetHealth(100)
    ent:SetMaxHealth(100)
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
end

---@param damage CTakeDamageInfo
function device:OnTakeDamage(damage)
    if SERVER and PW.Devices ~= nil then PW.Devices.Damage(self --[[@as Entity]], damage) end
end

function device:OnRemove()
    if SERVER and PW.Devices ~= nil then PW.Devices.EntityRemoved(self --[[@as Entity]]) end
end

function device:Draw()
    local ent = self --[[@as PW.SupportDeviceEntity]]
    ent:DrawModel()
    if PW.Devices ~= nil and PW.Devices.ClientTrack ~= nil then PW.Devices.ClientTrack(ent) end
end

scripted_ents.Register(device, "pw_support_device")
