-- PWOperator (U-9, T-7.3; notes/16-frontend-d1-proposal.md Q4; 10-frontend.md d.6): the local player's model in an
-- idle pose, framed from its bounds and lit by our own key, fill and rim lights. A DModelPanel subclass: the panel
-- paints nothing itself, so the blurred backdrop of PWRoot shows around the model. Thin glue over the pure maths in
-- sh_operator.lua. Weapon in hand: after CP-3 (T-7.3).

local lib = PW.UI --[[@as PW.UILib]]
local operatorLib = lib.Operator --[[@as PW.UIOperatorLib]]

local fov = 30
local swayDegrees, swaySpeed, baseYaw = 14, 0.35, 28

---@class PWOperator : DModelPanel
---@field Entity? CSEnt
---@field _rig? PW.UIOperatorRig
---@field _angle Angle reused every frame (no allocation in the animation)
---@field _framedAspect? number
---@field _modelPath? string
local operatorClass = {}

---The local player's operator: the choice of the operators module (06-progression.md d.7; the player is a
---spectator in the lobby, so its own model is not set there), else the player's current model.
---@return string
local function playerModel()
    local operators = rawget(PW, "Operators") --[[@as PW.OperatorsLib?]]
    if operators ~= nil and operators.LocalModel ~= nil then return operators.LocalModel() end
    local ply = LocalPlayer()
    return IsValid(ply) and ply:GetModel() or ""
end

---@param self PWOperator
local function applyLights(self)
    local rig = operatorLib.Lights(lib.Style --[[@as PW.UIStyle]])
    self._rig = rig
    self:SetAmbientLight(rig.ambient)
    for index = 0, 5 do self:SetDirectionalLight(index, color_black) end
    for _, light in ipairs(rig.lights) do self:SetDirectionalLight(light.dir, light.colour) end
end

---Copies the local player's look to the preview entity: the player colour always, the skin and the bodygroups when
---the player wears the same model. A DModelPanel entity has no GetPlayerColor, so the PlayerColor material proxy of
---a player model would tint it almost black.
---@param self PWOperator
local function applyAppearance(self)
    local ent = self.Entity
    local ply = LocalPlayer()
    if ent == nil or not IsValid(ent) or not IsValid(ply) then return end
    if ply:GetModel() == self._modelPath then
        ent:SetSkin(ply:GetSkin())
        for group = 0, ent:GetNumBodyGroups() - 1 do ent:SetBodygroup(group, ply:GetBodygroup(group)) end
    end
    local colour = ply:GetPlayerColor()
    ---@diagnostic disable-next-line: inject-field
    function ent:GetPlayerColor() return colour end
end

---@param self PWOperator
local function applyFraming(self)
    local ent = self.Entity
    if ent == nil or not IsValid(ent) then return end
    local mins, maxs = ent:GetRenderBounds()
    local width, height = self:GetSize()
    local aspect = height > 0 and width / height or 1
    local frame = operatorLib.Frame(mins, maxs, fov, aspect)
    self:SetFOV(fov)
    self:SetCamPos(frame.camPos)
    self:SetLookAt(frame.lookAt)
    self._framedAspect = aspect
end

function operatorClass:Init()
    self._angle = Angle(0, baseYaw, 0)
    self:SetFOV(fov)
    self:SetAnimated(true)
    applyLights(self)
    self:ShowLocal()
end

---Shows a player model (the local player's by default); an unusable path falls back to a stock model.
---@param path? string
function operatorClass:SetOperatorModel(path)
    local chosen = operatorLib.ChooseModel(path, util.IsValidModel)
    if chosen == self._modelPath and IsValid(self.Entity) then return end
    self._modelPath = chosen
    self:SetModel(chosen)
    local ent = self.Entity
    if ent == nil or not IsValid(ent) then return end
    local sequence = operatorLib.ChooseSequence(function(name)
        local id = ent:LookupSequence(name)
        return id
    end)
    if sequence ~= nil then ent:ResetSequence(sequence) end
    self:SetColor(color_white)
    applyAppearance(self)
    applyLights(self)
    applyFraming(self)
end

---Shows the local player's operator again (the lobby hub calls it on every refresh; an unchanged model is kept).
function operatorClass:ShowLocal()
    self:SetOperatorModel(playerModel())
end

---@param ent CSEnt
function operatorClass:LayoutEntity(ent)
    if self:GetAnimated() then self:RunAnimation() end
    self._angle.y = baseYaw + math.sin(CurTime() * swaySpeed) * swayDegrees
    ent:SetAngles(self._angle)
end

function operatorClass:PerformLayout(w, h)
    if h > 0 and self._framedAspect ~= w / h then applyFraming(self) end
end

vgui.Register("PWOperator", operatorClass, "DModelPanel")
