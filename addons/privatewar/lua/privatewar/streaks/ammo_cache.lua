STREAK.Name = "Ammunition Cache"
STREAK.Description = "45-second allied reserve supply in 160 units with LOS. Ten receipts, five-second cooldown."
STREAK.Kills = 4
STREAK.Score = 400
STREAK.Duration = 45
STREAK.Unlock = 1

function STREAK:Prepare(owner)
    local devices = PW.Devices
    return devices ~= nil and devices.Prepare(owner, "ammo_cache") or nil
end

function STREAK:OnEquip()
    if CLIENT then return end
    local devices = PW.Devices
    if devices == nil or not devices.Create(self, "ammo_cache", self.Activation --[[@as PW.DevicePlacement]]) then
        self:Remove()
    end
end

function STREAK:OnUnequip()
    if SERVER and self.Device ~= nil and PW.Devices ~= nil then PW.Devices.Remove(self.Device) end
end

function STREAK:BotShouldUse(owner)
    return self:Prepare(owner) ~= nil
end
