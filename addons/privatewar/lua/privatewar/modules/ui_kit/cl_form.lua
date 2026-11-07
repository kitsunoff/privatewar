-- Form controls v1 and the settings form (T-1.19 behaviour, T-7.2 cases; v1 look U-4; notes/16 §3 item 14).
-- PWSettingsForm builds one control per PW.UIFormControl (PW.UI.BuildForm): PWToggle (checkbox), PWSlider (slider),
-- PWSwitch ("< VALUE >": combo, and number without a range), PWMultiSelect (a toggle per option) and a styled text
-- entry for id lists. A changed value is reported through OnChange once the control has stayed unchanged for 0.3 s,
-- the same validated path as before (the caller sends PW.UI.ToWire of it). Every control paints itself from tokens
-- and is a focus node: left/right change the value, accept toggles or cycles.

local lib = PW.UI --[[@as PW.UILib]]
local paint = lib.Draw
local fontBody = lib.FontName("body")

---@return PW.UIStyle
local function style()
    return lib.Style --[[@as PW.UIStyle]]
end

local rowHeight, formGroup = 52, "form"

---Shared row background and label of the controls: focus fill and edge bar, label on the left.
---@param panel Panel
---@param label string
---@param w number
---@param h number
---@return Color ink
local function paintRow(panel, label, w, h)
    local s = style()
    local enabled = panel:IsEnabled()
    if panel._pwFocused and enabled then
        paint.Rect(0, 0, w, h, s.bg_hover)
        paint.EdgeBar(h)
    end
    local ink = enabled and s.text or s.text_disabled
    draw.SimpleText(label, fontBody, paint.Px(20), h / 2, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    return ink
end

---@param panel Panel
local function makeControl(panel)
    panel:SetTall(paint.Px(rowHeight))
    lib.Focusable(panel, formGroup)
end

-- PWToggle --------------------------------------------------------------------------------------------------------

---@class PWToggle : PWButton
---@field _value boolean
---@field _shown string the label cut to the room left of the switch
local toggleClass = {}

function toggleClass:Init()
    self._value, self._shown = false, ""
    makeControl(self)
end

---@param w number
function toggleClass:PerformLayout(w, _)
    self._shown = paint.Fit(self._label, fontBody, w - paint.Px(52) - paint.Px(64))
end

---@param value boolean
function toggleClass:SetValue(value)
    self._value = value == true
end

---@return boolean
function toggleClass:GetValue()
    return self._value
end

---@param _ boolean
function toggleClass:OnToggled(_)
end

function toggleClass:DoClick()
    self._value = not self._value
    self:OnToggled(self._value)
end

---@param w number
---@param h number
function toggleClass:Paint(w, h)
    local s = style()
    paintRow(self, self._shown, w, h)
    local trackW, trackH = paint.Px(52), paint.Px(28)
    local x, y = w - paint.Px(20) - trackW, math.floor((h - trackH) / 2)
    local on, enabled = self._value, self:IsEnabled()
    local track = on and (enabled and s.accent or s.border_strong) or s.border
    draw.RoundedBox(math.floor(trackH / 2), x, y, trackW, trackH, track)
    local thumb = trackH - paint.Px(8)
    local thumbX = on and x + trackW - thumb - paint.Px(4) or x + paint.Px(4)
    draw.RoundedBox(math.floor(thumb / 2), thumbX, y + paint.Px(4), thumb, thumb, on and s.on_accent or s.text_muted)
    return true
end

vgui.Register("PWToggle", toggleClass, "PWButton")

-- PWSlider --------------------------------------------------------------------------------------------------------

---@class PWSlider : Panel
---@field label string
---@field min number
---@field max number
---@field decimals integer
---@field value number
---@field _text string
---@field _shown string the label cut to the room left of the track
---@field _dragging boolean
local sliderClass = {}

function sliderClass:Init()
    self.label, self.min, self.max, self.decimals, self.value = "", 0, 100, 0, 0
    self._text, self._shown, self._dragging = "0", "", false
    makeControl(self)
end

---@param label string
---@param min number
---@param max number
---@param decimals integer
function sliderClass:Setup(label, min, max, decimals)
    self.label, self.min, self.max, self.decimals, self._text = label, min, max, decimals, ""
end

---@param value number
---@param notify? boolean
function sliderClass:SetValue(value, notify)
    local rounded = math.Round(math.Clamp(value, self.min, self.max), self.decimals)
    if rounded == self.value and self._text ~= "" then return end
    self.value = rounded
    self._text = string.format("%." .. self.decimals .. "f", rounded)
    if notify then self:OnValue(rounded) end
end

---@param _ number
function sliderClass:OnValue(_)
end

---@return number
function sliderClass:Step()
    local range = self.max - self.min
    if self.decimals == 0 then return math.max(1, math.Round(range / 20)) end
    return range / 20
end

---@param action string
---@return boolean
function sliderClass:PWAct(action)
    if not self:IsEnabled() or (action ~= "left" and action ~= "right") then return false end
    self:SetValue(self.value + (action == "right" and 1 or -1) * self:Step(), true)
    return true
end

---Track rectangle: left of the value text at the right edge.
---@return number x, number y, number w
function sliderClass:Track()
    local w, h = self:GetSize()
    local width = math.Clamp(math.floor(w * 0.32), paint.Px(120), paint.Px(280))
    return w - paint.Px(126) - width, h / 2, width
end

---@param w number
function sliderClass:PerformLayout(w, _)
    local x = self:Track()
    self._shown = paint.Fit(self.label, fontBody, math.max(0, x - paint.Px(44)))
    if w <= 0 then self._shown = "" end
end

function sliderClass:FollowCursor()
    local x, _, w = self:Track()
    local cx = self:CursorPos()
    self:SetValue(self.min + math.Clamp((cx - x) / math.max(1, w), 0, 1) * (self.max - self.min), true)
end

---@param code integer
function sliderClass:OnMousePressed(code)
    if code ~= MOUSE_LEFT or not self:IsEnabled() then return end
    self._dragging = true
    self:MouseCapture(true)
    self:FollowCursor()
end

function sliderClass:OnMouseReleased()
    self._dragging = false
    self:MouseCapture(false)
end

function sliderClass:Think()
    if self._dragging then self:FollowCursor() end
end

function sliderClass:OnCursorEntered()
    lib.HoverFocus(self)
end

function sliderClass:OnCursorExited()
    lib.HoverLeave(self)
end

---@param w number
---@param h number
function sliderClass:Paint(w, h)
    local s = style()
    local ink = paintRow(self, self._shown, w, h)
    local x, y, trackW = self:Track()
    local fraction = (self.value - self.min) / math.max(1e-9, self.max - self.min)
    local filled = math.floor(trackW * fraction)
    paint.Rect(x, y - paint.Px(2), trackW, paint.Px(4), s.border_strong)
    paint.Rect(x, y - paint.Px(2), filled, paint.Px(4), self:IsEnabled() and s.accent or s.text_disabled)
    local thumb = paint.Px(18)
    paint.Rect(x + filled - thumb / 2, y - thumb / 2, thumb, thumb, ink)
    draw.SimpleText(self._text, fontBody, w - paint.Px(20), h / 2, ink, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

vgui.Register("PWSlider", sliderClass, "Panel")

-- PWSwitch (enum switch and stepper) ------------------------------------------------------------------------------

---@class PWSwitch : PWButton
---@field options? string[] enum mode: the values to cycle
---@field value any
---@field step number number mode: the step
---@field decimals integer
---@field min? number
---@field max? number
---@field _text string
---@field _shown string the label cut to the room left of the value
local switchClass = {}

function switchClass:Init()
    self.step, self.decimals, self._text, self._shown = 1, 0, "", ""
    makeControl(self)
end

---@param w number
function switchClass:PerformLayout(w, _)
    self._shown = paint.Fit(self._label, fontBody, math.max(0, w - paint.Px(320)))
end

---@param value any
function switchClass:SetValue(value)
    self.value = value
    if self.options ~= nil then
        self._text = string.upper(tostring(value))
    else
        self._text = string.format("%." .. self.decimals .. "f", tonumber(value) or 0)
    end
end

---@param _ any
function switchClass:OnValue(_)
end

---@param delta integer
function switchClass:Cycle(delta)
    local options = self.options
    if options ~= nil then
        local index = 1
        for position, option in ipairs(options) do
            if option == self.value then index = position end
        end
        self:SetValue(options[(index - 1 + delta) % math.max(1, #options) + 1])
    else
        local value = (tonumber(self.value) or 0) + delta * self.step
        self:SetValue(math.Round(math.Clamp(value, self.min or -1e9, self.max or 1e9), self.decimals))
    end
    self:OnValue(self.value)
end

---@param action string
---@return boolean
function switchClass:PWAct(action)
    if not self:IsEnabled() or (action ~= "left" and action ~= "right") then return false end
    self:Cycle(action == "right" and 1 or -1)
    return true
end

function switchClass:DoClick()
    local cx = self:CursorPos()
    local right = self:GetWide() - paint.Px(20)
    self:Cycle(cx < right - paint.Px(130) and -1 or 1)
end

function switchClass:PWActivate()
    self:Cycle(1)
end

---@param w number
---@param h number
function switchClass:Paint(w, h)
    local s = style()
    local ink = paintRow(self, self._shown, w, h)
    local right = w - paint.Px(20)
    local arrows = self:IsEnabled() and s.accent or s.text_disabled
    draw.SimpleText(">", fontBody, right, h / 2, arrows, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    local centre = right - paint.Px(130)
    draw.SimpleText(self._text, fontBody, centre, h / 2, ink, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("<", fontBody, right - paint.Px(260), h / 2, arrows, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    return true
end

vgui.Register("PWSwitch", switchClass, "PWButton")

include("privatewar/modules/ui_kit/cl_settings.lua")
