-- Widget kit, client (T-1.19; v1 look U-4). The base classes on top of derma primitives: PWPanel (box with border
-- and title), PWButton v1 (flat button: normal, focused, pressed, selected, disabled, locked; variants primary,
-- secondary, danger) and PWList (selectable rows). Every colour and font comes from PW.UI.Style (tokens: sh_style.lua,
-- palette "Field green"); every class paints itself, no derma skin. The other v1 components and the settings form
-- live in cl_paint.lua (helpers, focus), cl_components.lua, cl_cards.lua and cl_form.lua, included at the end.

local lib = PW.UI --[[@as PW.UILib]]

-- Fonts and scale (U-1). Style itself (tokens, ladder maths) is sh_style.lua. The ladder fonts are created again
-- when the resolution changes; names stay the same, so panels that already use them follow.
local lastWidth, lastHeight = 0, 0
local fallbackScale = 1

---@return boolean
function lib.RefreshFonts()
    local width, height = ScrW(), ScrH()
    if width == lastWidth and height == lastHeight then return false end
    lastWidth, lastHeight = width, height
    local hud = rawget(PW, "HUD") --[[@as PW.HudLib?]]
    if hud ~= nil then hud.Refresh() end
    fallbackScale = lib.ScaleFor(width, height)
    for _, data in ipairs(lib.FontLadder(width, height)) do surface.CreateFont(data.name, data) end
    return true
end

---Design units to pixels at the current resolution.
---@param value number
---@return number
function lib.S(value)
    lib.RefreshFonts()
    local hud = rawget(PW, "HUD") --[[@as PW.HudLib?]]
    if hud ~= nil then return hud.S(value) end
    return value * fallbackScale
end

---@param id string ladder step id: title, h1, h2, body, small, hint
---@return string
function lib.Font(id)
    lib.RefreshFonts()
    return lib.FontName(id)
end

lib.RefreshFonts()
hook.Add("OnScreenSizeChanged", "PW_UI_Fonts", lib.RefreshFonts)

include("privatewar/modules/ui_kit/cl_paint.lua")

local paint = lib.Draw
local fontH2, fontBody, fontSmall = lib.FontName("h2"), lib.FontName("body"), lib.FontName("small")

---@return PW.UIStyle
local function style()
    return lib.Style --[[@as PW.UIStyle]]
end

local panelClass = {}

function panelClass:Paint(w, h)
    local s = style()
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Outline(0, 0, w, h, s.border)
    return true
end

---@param text string
function panelClass:SetTitle(text)
    local self_ = self --[[@as PWPanel]]
    if not IsValid(self_._title) then
        self_._title = vgui.Create("DLabel", self_) --[[@as DLabel]]
        self_._title:Dock(TOP)
        self_._title:DockMargin(style().pad, style().pad, style().pad, style().pad)
    end
    local title = self_._title --[[@as DLabel]]
    title:SetFont(fontH2)
    title:SetTextColor(style().text)
    title:SetText(string.upper(text))
    title:SizeToContentsY()
end

vgui.Register("PWPanel", panelClass, "DPanel")

local buttonClass = {}

function buttonClass:Init()
    local self_ = self --[[@as PWButton]]
    self_._label = ""
    FindMetaTable("Panel").SetText(self_, "") -- the derma label draws nothing; Paint draws _label
    self_._font = fontBody
    self_._align = TEXT_ALIGN_CENTER
    self_:SetTall(paint.Px(48))
    lib.Focusable(self_, "buttons")
end

---The label is drawn by Paint (never by the derma label), so it can sit next to the lock glyph and badges.
---@param text string
function buttonClass:SetText(text)
    (self --[[@as PWButton]])._label = text
end

---@return string
function buttonClass:GetText()
    return (self --[[@as PWButton]])._label
end

---@param font string
function buttonClass:SetFont(font)
    (self --[[@as PWButton]])._font = font
end

---Left-aligned label (list rows) instead of the centred default.
---@param left boolean
function buttonClass:SetAlignLeft(left)
    (self --[[@as PWButton]])._align = left and TEXT_ALIGN_LEFT or TEXT_ALIGN_CENTER
end

---"countdown": a running countdown (the lobby START button, lobby_ui sh_flow.lua): accent ink and outline on a dark
---fill, no lock glyph, never clickable.
---@param variant? "primary"|"secondary"|"danger"|"countdown"
function buttonClass:SetVariant(variant)
    (self --[[@as PWButton]])._variant = variant
end

---@param primary boolean
function buttonClass:SetPrimary(primary)
    (self --[[@as PWButton]])._variant = primary and "primary" or nil
end

---@param selected boolean
function buttonClass:SetSelected(selected)
    (self --[[@as PWButton]])._selected = selected
end

---@param locked boolean
---@param reason? string
function buttonClass:SetLocked(locked, reason)
    local self_ = self --[[@as PWButton]]
    self_._locked = locked
    lib.SetLocked(self_, locked, reason)
end

function buttonClass:OnCursorEntered()
    lib.HoverFocus(self --[[@as Panel]])
end

function buttonClass:OnCursorExited()
    lib.HoverLeave(self --[[@as Panel]])
end

---@param code integer
function buttonClass:OnMousePressed(code)
    local self_ = self --[[@as PWButton]]
    if not self_:IsEnabled() or code ~= MOUSE_LEFT then return end
    self_._pressed = true
    self_:MouseCapture(true)
end

---@param code integer
function buttonClass:OnMouseReleased(code)
    local self_ = self --[[@as PWButton]]
    self_:MouseCapture(false)
    local pressed = self_._pressed
    self_._pressed = false
    if not pressed or code ~= MOUSE_LEFT or self_._locked or not self_:IsEnabled() then return end
    if self_._variant == "countdown" then return end
    if self_:IsHovered() then self_:DoClick() end
end

function buttonClass:DoClick()
end

---Fill, outline and ink of the current state.
---@param self_ PWButton
---@return Color fill, Color? outline, Color ink
local function buttonColours(self_)
    local s = style()
    local focused = self_._pwFocused == true
    local variant = self_._variant
    if variant == "countdown" then return s.bg_raised, s.accent, s.accent end
    if not self_:IsEnabled() or self_._locked then return s.bg_panel, s.border, s.text_disabled end
    if variant == "primary" then return s.accent, nil, s.on_accent end
    if variant == "danger" then
        if focused then return s.negative, nil, s.text end
        return s.bg_panel, s.negative, s.negative
    end
    if self_._selected then return s.bg_selected, focused and s.border_strong or nil, s.text end
    if variant == "secondary" then
        if focused then return s.bg_hover, s.text_muted, s.text end
        return s.bg_panel, s.border_strong, s.text
    end
    return focused and s.bg_hover or s.bg_raised, focused and s.border_strong or nil, s.text
end

function buttonClass:Paint(w, h)
    local self_ = self --[[@as PWButton]]
    local fill, outline, ink = buttonColours(self_)
    paint.Rect(0, 0, w, h, fill)
    if self_._pressed then paint.Rect(0, 0, w, h, style().bg_scrim) end
    if outline ~= nil then paint.Outline(0, 0, w, h, outline, paint.Px(2)) end
    local focused = self_._pwFocused == true and self_:IsEnabled()
    if self_._locked and self_._pwFocused then
        paint.Outline(0, 0, w, h, style().text_muted, paint.Px(2))
    elseif self_._variant == "primary" then
        if focused then paint.Outline(0, 0, w, h, style().text, paint.Px(2)) end
    elseif self_._variant ~= "danger" and (self_._selected or (focused and not self_._locked)) then
        paint.EdgeBar(h)
    end
    local pad = paint.Px(16)
    local x = self_._align == TEXT_ALIGN_LEFT and pad or w / 2
    draw.SimpleText(self_._label, self_._font, x, h / 2, ink, self_._align, TEXT_ALIGN_CENTER)
    if self_._locked and self_._variant ~= "countdown" then
        local size = paint.Px(18)
        paint.Lock(w - pad - size, math.floor((h - size) / 2), size, style().text_disabled)
    end
    return true
end

vgui.Register("PWButton", buttonClass, "DButton")

local listClass = {}

---@param items PW.UIListItem[]
---@param selected? string
function listClass:SetItems(items, selected)
    local self_ = self --[[@as PWList]]
    self_:Clear()
    self_._rows = {}
    local group = "list" .. tostring(self_)
    for _, item in ipairs(items) do
        local row = vgui.Create("PWButton", self_) --[[@as PWButton]]
        row:SetText(item.label)
        row:SetAlignLeft(true)
        row:SetFont(fontSmall)
        row:SetTall(paint.Px(40))
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, 2)
        row:SetSelected(item.id == selected)
        lib.Focusable(row, group)
        row.DoClick = function() self_:OnSelect(item.id) end
        self_._rows[item.id] = row
    end
end

---@param _ string
function listClass:OnSelect(_)
end

vgui.Register("PWList", listClass, "DScrollPanel")

-- Kit v1 components (U-4), then the in-match gamepad buttons.
for _, name in ipairs({
    "components", "cards", "form", "operator", "vote", "match", "store", "postmatch", "gamepad"
}) do
    include("privatewar/modules/ui_kit/cl_" .. name .. ".lua")
end
