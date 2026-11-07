-- Kit v1 drawing and focus helpers (U-4; 10-frontend.md d.3, d.5, d.7). Thin client glue used by every PW* class:
-- token rectangles, outlines, the accent edge bar, the lock glyph, the "NEW" badge, key caps and pad badges, the
-- backdrop (blur + scrim) and word wrapping (layout time only). Nothing here allocates while painting, except Wrap,
-- which is meant for PerformLayout. Focus: a panel is made focusable by giving it a spec; PWRoot collects the specs
-- into a PW.UI.Focus model and marks the focused panel (one highlight: hovering moves the focus too).

local lib = PW.UI --[[@as PW.UILib]]

local paint = (rawget(lib, "Draw") or {}) --[[@as PW.UIDrawLib]]
lib.Draw = paint

---@return PW.UIStyle
local function style()
    return lib.Style --[[@as PW.UIStyle]]
end

---Design units to whole pixels, at least 1.
---@param value number
---@return integer
function paint.Px(value)
    return math.max(1, math.floor((lib.S --[[@as fun(v: number): number]])(value) + 0.5))
end

---@param x number
---@param y number
---@param w number
---@param h number
---@param colour Color
function paint.Rect(x, y, w, h, colour)
    surface.SetDrawColor(colour)
    surface.DrawRect(x, y, w, h)
end

---An outline of a given thickness drawn inside the rectangle.
---@param x number
---@param y number
---@param w number
---@param h number
---@param colour Color
---@param thickness? integer
function paint.Outline(x, y, w, h, colour, thickness)
    local t = thickness or 1
    surface.SetDrawColor(colour)
    surface.DrawRect(x, y, w, t)
    surface.DrawRect(x, y + h - t, w, t)
    surface.DrawRect(x, y + t, t, h - 2 * t)
    surface.DrawRect(x + w - t, y + t, t, h - 2 * t)
end

---The accent bar on the left edge of a focused or selected row.
---@param h number
---@param colour? Color
function paint.EdgeBar(h, colour)
    paint.Rect(0, 0, paint.Px(4), h, colour or style().accent)
end

---A padlock of the given pixel size with its top-left corner at x, y.
---@param x number
---@param y number
---@param size number
---@param colour Color
function paint.Lock(x, y, size, colour)
    local stroke = math.max(1, math.floor(size / 7))
    local bodyTop = y + math.floor(size * 0.45)
    paint.Rect(x, bodyTop, size, y + size - bodyTop, colour)
    local shackle = math.floor(size * 0.6)
    paint.Outline(x + math.floor((size - shackle) / 2), y, shackle, bodyTop - y + stroke, colour, stroke)
end

---A filled badge with text, right-aligned at xRight and centred on yCentre. Returns its width.
---@param text string
---@param font string
---@param xRight number
---@param yCentre number
---@param fill Color
---@param ink Color
---@return number
function paint.Badge(text, font, xRight, yCentre, fill, ink)
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(text)
    local padX = paint.Px(8)
    local w, h = tw + 2 * padX, th + paint.Px(4)
    local x, y = xRight - w, math.floor(yCentre - h / 2)
    paint.Rect(x, y, w, h, fill)
    draw.SimpleText(text, font, x + padX, yCentre, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    return w
end

---A key cap (keyboard: square cap) or a pad badge (controller: round badge) at x, centred on yCentre.
---Returns its width.
---@param label string
---@param font string
---@param x number
---@param yCentre number
---@param device "keyboard"|"controller"
---@return number
function paint.KeyCap(label, font, x, yCentre, device)
    local s = style()
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(label)
    local h = th + paint.Px(6)
    local w = math.max(h, tw + paint.Px(14))
    local y = math.floor(yCentre - h / 2)
    if device == "controller" and #label <= 2 then
        draw.RoundedBox(math.floor(h / 2), x, y, w, h, s.border_strong)
    else
        paint.Rect(x, y, w, h, s.bg_raised)
        paint.Outline(x, y, w, h, s.border_strong, paint.Px(2))
    end
    draw.SimpleText(label, font, x + w / 2, yCentre, s.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return w
end

local blur = Material("pp/blurscreen")
local white = Color(255, 255, 255, 255)
local blurPasses = 3

---Blurred live view under the scrim (PWBackdrop, PWRoot). Draws over the whole panel.
---@param panel Panel
---@param w number
---@param h number
function paint.Backdrop(panel, w, h)
    local x, y = panel:LocalToScreen(0, 0)
    surface.SetMaterial(blur)
    surface.SetDrawColor(white)
    for pass = 1, blurPasses do
        blur:SetFloat("$blur", pass * 2)
        blur:Recompute()
        render.UpdateScreenEffectTexture()
        surface.DrawTexturedRect(-x, -y, ScrW(), ScrH())
    end
    paint.Rect(0, 0, w, h, style().bg_scrim)
end

---Word wrap for layout time (allocates): the lines of text that fit width in the font.
---@param text string
---@param font string
---@param width number
---@return string[]
function paint.Wrap(text, font, width)
    surface.SetFont(font)
    ---@type string[]
    local lines = {}
    local line = ""
    for word in string.gmatch(text, "%S+") do
        ---@type string
        local candidate = line == "" and word or line .. " " .. word
        if line ~= "" and surface.GetTextSize(candidate) > width then
            lines[#lines + 1] = line
            line = word
        else
            line = candidate
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

---Layout time only: the text cut to fit width, with an ellipsis when it was cut.
---@param text string
---@param font string
---@param width number
---@return string
function paint.Fit(text, font, width)
    surface.SetFont(font)
    if surface.GetTextSize(text) <= width then return text end
    local cut = #text
    while cut > 0 and surface.GetTextSize(string.sub(text, 1, cut) .. "...") > width do cut = cut - 1 end
    return string.TrimRight(string.sub(text, 1, cut)) .. "..."
end

-- Focus -----------------------------------------------------------------------------------------------------------

local nextId = 0

---Makes a panel a focus node of a group. Returns the spec (locked, reason, disabled can be changed later).
---@param panel Panel
---@param group string
---@param id? string
---@return PW.UIFocusSpec
function lib.Focusable(panel, group, id)
    if id == nil then
        nextId = nextId + 1
        id = "n" .. nextId
    end
    local spec = panel._pwFocus or { id = id, group = group }
    spec.id, spec.group = id, group
    panel._pwFocus = spec
    return spec
end

---Locks or unlocks a focusable panel; a locked panel stays focusable and shows its reason in the hint bar.
---@param panel Panel
---@param locked boolean
---@param reason? string
function lib.SetLocked(panel, locked, reason)
    local spec = panel._pwFocus or lib.Focusable(panel, "default")
    spec.locked = locked
    spec.reason = locked and reason or nil
end

---@param panel Panel
---@return boolean
function lib.IsFocused(panel)
    return panel._pwFocused == true
end

---The PWRoot that contains a panel, or nil.
---@param panel Panel
---@return Panel?
function lib.FindRoot(panel)
    local current = panel --[[@as Panel?]]
    while current ~= nil and IsValid(current) do
        if current._pwIsRoot then return current end
        current = current:GetParent() --[[@as Panel?]]
    end
    return nil
end

---Mouse hover moves the focus (one highlight). Outside a PWRoot the panel only marks itself.
---@param panel Panel
function lib.HoverFocus(panel)
    local root = lib.FindRoot(panel)
    if root ~= nil and root.FocusPanel ~= nil then
        root:FocusPanel(panel, "mouse")
        return
    end
    panel._pwFocused = true
end

---@param panel Panel
function lib.HoverLeave(panel)
    if lib.FindRoot(panel) == nil then panel._pwFocused = false end
end

---Runs a panel's action: PWActivate when it has one, else DoClick.
---@param panel Panel
function lib.Activate(panel)
    if panel.PWActivate ~= nil then return panel:PWActivate() end
    local button = panel --[[@as DButton]]
    if button.DoClick ~= nil then button:DoClick() end
end

local hintsVar = nil --[[@as ConVar?]]

function lib.HintOverride()
    hintsVar = hintsVar or GetConVar("pw_ui_kit_hints")
    if hintsVar == nil then return "auto" end
    return hintsVar:GetString()
end
