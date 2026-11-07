-- LOADOUT tab editors, the look shared by the editor and the gunsmith screens (T-7.4): a slot row (a focusable
-- PWButton painted as label, value and a right-hand note) and the meter (title, value, bar). Built from the kit's
-- tokens and fonts only; PW.UI is read at call time (this module loads before ui_kit).

local lib = PW.LoadoutUI --[[@as PW.LoadoutUILib]]

---@return PW.UILib
local function kit()
    return PW.UI --[[@as PW.UILib]]
end

---@param row PWLoadoutRow
---@param w number
---@param h number
local function paintRow(row, w, h)
    local s, paint = kit().Style --[[@as PW.UIStyle]], kit().Draw
    local focused = row._pwFocused == true
    paint.Rect(0, 0, w, h, row.pwChosen and s.bg_selected or (focused and s.bg_hover or s.bg_panel))
    if focused then
        paint.Outline(0, 0, w, h, s.border_strong, paint.Px(2))
        paint.EdgeBar(h)
    end
    local pad = paint.Px(20)
    local small, body = kit().FontName("small"), kit().FontName("body")
    draw.SimpleText(row.pwLabel, small, pad, paint.Px(6), s.text_muted)
    local side = row.pwProblem or row.pwSide
    local sideW = 0
    if side ~= "" then
        local fitted = paint.Fit(side, small, math.floor(w * 0.45))
        surface.SetFont(small)
        sideW = surface.GetTextSize(fitted) + paint.Px(12)
        draw.SimpleText(fitted, small, w - pad, h / 2, row.pwProblem ~= nil and s.warning or s.text_muted,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    local value = paint.Fit(row.pwValue, body, w - 2 * pad - sideW)
    draw.SimpleText(value, body, pad, h - paint.Px(6), s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    return true
end

---A slot row: a focusable button of a focus group; set pwLabel, pwValue, pwSide, pwProblem and pwChosen.
---@param parent Panel
---@param group string
---@param id string
---@return PWLoadoutRow
function lib.RowButton(parent, group, id)
    local row = vgui.Create("PWButton", parent) --[[@as PWLoadoutRow]]
    row:SetTall(kit().Draw.Px(64))
    kit().Focusable(row, group, id)
    row.pwLabel, row.pwValue, row.pwSide, row.pwChosen = "", "", "", false
    local hooks = row --[[@as PANEL]]
    hooks.Paint = function(_, w, h) return paintRow(row, w, h) end
    return row
end

---The colour of a meter state.
---@param state string "ok", "full", "over", "unlimited"
---@return Color
local function meterColour(state)
    local s = kit().Style --[[@as PW.UIStyle]]
    if state == "over" then return s.negative end
    if state == "full" then return s.warning end
    if state == "unlimited" then return s.text_muted end
    return s.accent
end

---Paints a meter: a title, the value and a bar filled to fraction.
---@param w number
---@param h number
---@param title string
---@param text string
---@param fraction number
---@param state string
---@param note? string a line under the bar
function lib.PaintMeter(w, h, title, text, fraction, state, note)
    local s, paint = kit().Style --[[@as PW.UIStyle]], kit().Draw
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Outline(0, 0, w, h, state == "over" and s.negative or s.border)
    local pad = paint.Px(20)
    draw.SimpleText(title, kit().FontName("small"), pad, paint.Px(10), s.text_muted)
    draw.SimpleText(text, kit().FontName("h1"), pad, paint.Px(34), state == "over" and s.negative or s.text)
    local barY, barH = paint.Px(96), paint.Px(10)
    paint.Rect(pad, barY, w - 2 * pad, barH, s.bg_raised)
    paint.Rect(pad, barY, math.floor((w - 2 * pad) * math.Clamp(fraction, 0, 1)), barH, meterColour(state))
    if note ~= nil then
        draw.SimpleText(paint.Fit(note, kit().FontName("small"), w - 2 * pad), kit().FontName("small"), pad,
            barY + barH + paint.Px(10), state == "over" and s.negative or s.text_muted)
    end
end

---Moves the focus to a panel of the open root once its layout is known.
---@param panel? Panel
function lib.FocusLater(panel)
    local root = kit().CurrentRoot() --[[@as PWRoot?]]
    if root == nil or panel == nil then return end
    timer.Simple(0, function()
        if not IsValid(root) or not IsValid(panel) then return end
        root:RefreshFocus()
        root:FocusPanel(panel, "key")
    end)
end
