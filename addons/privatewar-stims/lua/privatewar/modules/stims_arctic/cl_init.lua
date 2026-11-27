if not PW or PW.API ~= 1 then return end
local lib = PW.StimsArctic --[[@as PW.StimsArcticLib]]
local track = "pw_stim"

---@class PW.StimGcalBackend
---@field Play fun(self: PW.StimGcalBackend, name: string, track: string): boolean
---@field Anims table<string, table>
---@field IsTrackActive fun(self: PW.StimGcalBackend, track: string): boolean
---@field GetGestureModel fun(self: PW.StimGcalBackend, track: string): Entity?

---@class PW.StimVManipBackend
---@field GetAnim fun(self: PW.StimVManipBackend, name: string): table|false|nil
---@field PlayAnim fun(self: PW.StimVManipBackend, name: string): boolean
---@field GetVMGesture fun(self: PW.StimVManipBackend): Entity?

local function warnOnce()
    local debugVar = GetConVar("pw_debug")
    if lib._MissingWarned or debugVar == nil or not debugVar:GetBool() then return end
    lib._MissingWarned = true
    print("[PW] Arctic stim animation or compatible backend is unavailable; keeping core presentation")
end

---@param itemId string
function MODULE:PW_StimInjected(itemId)
    local name = lib._AnimFor(itemId, lib.Anims)
    if name == nil then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local gcal = rawget(_G, "GCAL") --[[@as PW.StimGcalBackend?]]
    local legacy = rawget(_G, "VManip") --[[@as PW.StimVManipBackend?]]
    local hasGcal = gcal ~= nil and isfunction(gcal.Play) and isfunction(gcal.IsTrackActive)
        and isfunction(gcal.GetGestureModel) and istable(gcal.Anims)
    local hasVManip = legacy ~= nil and isfunction(legacy.GetAnim) and isfunction(legacy.PlayAnim)
        and isfunction(legacy.GetVMGesture)
    local registered = gcal ~= nil and hasGcal and gcal.Anims[name] ~= nil
    local legacyRegistered = legacy ~= nil and hasVManip and not registered and not not legacy:GetAnim(name)
    local backend = lib._PickBackend(hasGcal, hasVManip, registered, legacyRegistered)
    ---@type Entity?
    local gesture
    if backend == "gcal" and gcal ~= nil then
        if gcal:Play(name, track) and gcal:IsTrackActive(track) then gesture = gcal:GetGestureModel(track) end
    elseif backend == "vmanip" and legacy ~= nil then
        if legacy:PlayAnim(name) then gesture = legacy:GetVMGesture() end
    else
        warnOnce()
    end
    if gesture ~= nil and IsValid(gesture) then gesture:SetSkin(lib.Anims[itemId].skin) end
end
