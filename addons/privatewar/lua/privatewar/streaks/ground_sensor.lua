STREAK.Name = "Ground Sensor"
STREAK.Description = "30 seconds of local radar: 600 units, same floor within 128 units, LOS. Destroyable, 100 HP."
STREAK.Kills = 4
STREAK.Score = 400
STREAK.Duration = 30
STREAK.Unlock = 1

function STREAK:Prepare(owner)
    local devices = PW.Devices
    return devices ~= nil and devices.Prepare(owner, "ground_sensor") or nil
end

function STREAK:OnEquip()
    if CLIENT then return end
    local devices = PW.Devices
    if devices == nil or not devices.Create(self, "ground_sensor", self.Activation --[[@as PW.DevicePlacement]]) then
        self:Remove()
    end
end

function STREAK:OnUnequip()
    if SERVER and self.Device ~= nil and PW.Devices ~= nil then PW.Devices.Remove(self.Device) end
end

function STREAK:BotShouldUse(owner)
    return self:Prepare(owner) ~= nil
end
