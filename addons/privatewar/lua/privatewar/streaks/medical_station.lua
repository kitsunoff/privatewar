STREAK.Name = "Medical Station"
STREAK.Description = "Heal 5 HP/s after five damage-free seconds. 30 seconds, 180 units, LOS. No overlap stacking."
STREAK.Kills = 5
STREAK.Score = 500
STREAK.Duration = 30
STREAK.Unlock = 1

function STREAK:Prepare(owner)
    local devices = PW.Devices
    return devices ~= nil and devices.Prepare(owner, "medical_station") or nil
end

function STREAK:OnEquip()
    if CLIENT then return end
    local devices = PW.Devices
    if devices == nil or not devices.Create(self, "medical_station", self.Activation --[[@as PW.DevicePlacement]]) then
        self:Remove()
    end
end

function STREAK:OnUnequip()
    if SERVER and self.Device ~= nil and PW.Devices ~= nil then PW.Devices.Remove(self.Device) end
end

function STREAK:BotShouldUse(owner)
    return self:Prepare(owner) ~= nil
end
