-- Bottom action hints. Hit testing uses the last painted glyph and label bounds, without adding any focus nodes.
local lib = PW.UI --[[@as PW.UILib]]
local paint = lib.Draw
local fontBody, fontHint = lib.FontName("body"), lib.FontName("hint")

---@class PWHintBar : Panel
---@field input PW.UIInputState
---@field entries PW.UIHintEntry[]
---@field items PW.UIHintItem[]
---@field reason? string
---@field OnAction? fun(self: PWHintBar, action: string)
---@field _device? string
---@field _override? string
---@field _pressed? PW.UIHintItem
---@field _paintW? number
---@field _paintH? number
local hintClass = {}

function hintClass:Init()
    self.input, self.entries, self.items = lib.Input.New(), {}, {}
    self:SetMouseInputEnabled(true)
    self:SetKeyboardInputEnabled(false)
end

function hintClass:CancelClick()
    if self._pressed == nil then return end
    self._pressed = nil
    self:MouseCapture(false)
end

---@param state PW.UIInputState
function hintClass:SetInputState(state)
    self:CancelClick()
    self.input, self._device, self.items = state, nil, {}
end

---@param entries PW.UIHintEntry[]
function hintClass:SetEntries(entries)
    self:CancelClick()
    self.entries, self._device, self.items = entries, nil, {}
end

---A locked node's reason, shown after the actions (nil hides it).
---@param reason? string
function hintClass:SetReason(reason)
    self.reason = reason
end

function hintClass:Think()
    local override = lib.HintOverride()
    if self.input.device == self._device and override == self._override then return end
    self:CancelClick()
    self._device, self._override = self.input.device, override
    self.items = lib.Hints(self.input, self.entries, override)
end

---@return PW.UIHintItem?
function hintClass:HoveredHint()
    if self.OnAction == nil or not self:IsVisible() or not self:IsHovered() then return nil end
    local x, y = self:CursorPos()
    local w, h = self:GetSize()
    if w ~= self._paintW or h ~= self._paintH or x < 0 or x >= w or y < 0 or y >= h then return nil end
    for _, item in ipairs(self.items) do
        local hit = item.hit
        if hit ~= nil and x >= hit.x and x < hit.x + hit.w and y >= hit.y and y < hit.y + hit.h then
            return item
        end
    end
    return nil
end

---@param code integer
function hintClass:OnMousePressed(code)
    if code ~= MOUSE_LEFT or self._pressed ~= nil then return end
    local item = self:HoveredHint()
    if item == nil then return end
    self._pressed = item
    self:MouseCapture(true)
end

---@param code integer
function hintClass:OnMouseReleased(code)
    local pressed = self._pressed
    if code ~= MOUSE_LEFT or pressed == nil then return end
    local hovered = self:HoveredHint()
    self:CancelClick()
    local action, handler = pressed.action, self.OnAction
    if pressed ~= hovered or action == nil or handler == nil then return end
    lib.Input.NoteMouse(self.input)
    handler(self, action)
end

function hintClass:OnSizeChanged()
    self:CancelClick()
    self._paintW, self._paintH = nil, nil
end

---@param item PW.UIHintItem
---@param x number
---@param y number
---@param ink Color
---@return number
local function drawHint(item, x, y, ink)
    local capWidth, capTop, capHeight = paint.KeyCap(item.cap, fontHint, x, y, item.device)
    local labelX = x + capWidth + paint.Px(10)
    local tw, th = draw.SimpleText(item.label, fontBody, labelX, y, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local right = labelX + tw
    if item.action ~= nil then
        local hit = item.hit or { x = 0, w = 0, y = 0, h = 0 }
        local labelTop = math.floor(y - th / 2)
        hit.x, hit.w = x, right - x
        hit.y = math.min(capTop, labelTop)
        hit.h = math.max(capTop + capHeight, labelTop + th) - hit.y
        item.hit = hit
    end
    return right + paint.Px(36)
end

---@param w number
---@param h number
function hintClass:Paint(w, h)
    self._paintW, self._paintH = w, h
    local s = lib.Style --[[@as PW.UIStyle]]
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Rect(0, 0, w, 1, s.border)
    local x = paint.Px(96)
    local y = h / 2
    for _, item in ipairs(self.items) do x = drawHint(item, x, y, s.text) end
    local reason = self.reason
    if reason == nil then return end
    local size = paint.Px(18)
    paint.Lock(x, math.floor(y - size / 2), size, s.text_muted)
    draw.SimpleText(reason, fontBody, x + size + paint.Px(10), y, s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

vgui.Register("PWHintBar", hintClass, "Panel")
