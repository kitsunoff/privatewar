local lib = PW.Stims --[[@as PW.StimsLib]]
util.AddNetworkString("pw_stim_used")

---@type table<string, integer>
local itemIndex = {}
for index, id in ipairs(lib._WireItems) do itemIndex[id] = index end
local punch = Angle(2, 0, 0)

---@type table<PW.StimEffect, string>
local deadlineNames = { heal = "pw_stim_heal_until", armor = "pw_stim_armor_until", speed = "pw_stim_speed_until" }

function lib.Played(owner, item)
    if not IsValid(owner) then return end
    local sound = item.Sound --[[@as string?]]
    if sound ~= nil then owner:EmitSound(sound) end
    owner:ViewPunch(punch)
    local id = item.ClassName --[[@as string]]
    local index = itemIndex[id]
    if index == nil or owner:IsBot() then return end
    net.Start("pw_stim_used")
    net.WriteUInt(index, 8)
    net.Send(owner)
end

---@param owner Player
---@param key PW.StimEffect
---@param untilTime number
function lib.Mark(owner, key, untilTime)
    if not IsValid(owner) then return end
    local name = deadlineNames[key]
    if owner:GetNW2Float(name, 0) ~= untilTime then owner:SetNW2Float(name, untilTime) end
end
