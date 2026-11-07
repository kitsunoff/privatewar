-- The generated settings form (T-1.19, T-7.2; v1 look U-4): PWSettingsForm, PWMultiSelect, the id-list row and the
-- builders of the six widgets of PW.UI.WidgetFor. The controls themselves are cl_form.lua.

local lib = PW.UI --[[@as PW.UILib]]
local paint = lib.Draw
local fontBody, fontSmall = lib.FontName("body"), lib.FontName("small")

---@return PW.UIStyle
local function style()
    return lib.Style --[[@as PW.UIStyle]]
end

-- Seconds a control must stay unchanged before its value is reported (a slider fires on every pixel).
local settleTime = 0.3
local rowHeight, formGroup = 52, "form"

-- PWMultiSelect ---------------------------------------------------------------------------------------------------

---@class PWMultiSelect : Panel
---@field label string
---@field chosen table<string, true>
---@field toggles PWToggle[]
local multiClass = {}

function multiClass:Init()
    self.label, self.chosen, self.toggles = "", {}, {}
end

---@param label string
---@param options string[]
---@param chosen table<string, true>
function multiClass:Setup(label, options, chosen)
    self.label, self.chosen = label, table.Copy(chosen)
    for _, option in ipairs(options) do
        local toggle = vgui.Create("PWToggle", self) --[[@as PWToggle]]
        toggle:SetText(option)
        toggle:SetValue(self.chosen[option] == true)
        toggle.OnToggled = function(_, value)
            self.chosen[option] = value and true or nil
            self:OnValue(table.Copy(self.chosen))
        end
        self.toggles[#self.toggles + 1] = toggle
    end
    self:SetTall(paint.Px(44) + #self.toggles * paint.Px(rowHeight))
end

---@param _ table<string, true>
function multiClass:OnValue(_)
end

---@param enabled boolean
function multiClass:SetEnabled(enabled)
    for _, toggle in ipairs(self.toggles) do toggle:SetEnabled(enabled) end
end

---@param w number
function multiClass:PerformLayout(w, _)
    local y, indent = paint.Px(44), paint.Px(24)
    for _, toggle in ipairs(self.toggles) do
        toggle:SetPos(indent, y)
        toggle:SetSize(w - indent, paint.Px(rowHeight))
        y = y + paint.Px(rowHeight)
    end
end

---@param _ number
---@param _h number
function multiClass:Paint(_, _h)
    local s = style()
    draw.SimpleText(self.label, fontBody, paint.Px(20), paint.Px(22), s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

vgui.Register("PWMultiSelect", multiClass, "Panel")

-- Id list row: a styled text entry; accept puts the keyboard into it. ---------------------------------------------

---@param parent Panel
---@param control PW.UIFormControl
---@param emit fun(value: any)
---@return Panel
local function idListRow(parent, control, emit)
    local row = vgui.Create("Panel", parent) --[[@as Panel]]
    row:SetTall(paint.Px(rowHeight))
    lib.Focusable(row, formGroup)
    local entry = vgui.Create("DTextEntry", row) --[[@as DTextEntry]]
    entry:SetFont(fontBody)
    local ids = table.GetKeys(control.value or {})
    table.sort(ids)
    entry:SetValue(table.concat(ids, ","))
    entry.OnEnter = function(self_)
        ---@type table<string, true>
        local set = {}
        for _, part in ipairs(string.Explode(",", self_:GetValue())) do
            local id = string.Trim(part)
            if id ~= "" then set[id] = true end
        end
        emit(set)
    end
    local hooks = row --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h)
        entry:SetPos(math.floor(w * 0.45), paint.Px(8))
        entry:SetSize(w - math.floor(w * 0.45) - paint.Px(20), h - paint.Px(16))
    end
    hooks.Paint = function(_, w, h)
        local s = style()
        if row._pwFocused then paint.Rect(0, 0, w, h, s.bg_hover) end
        draw.SimpleText(control.label, fontBody, paint.Px(20), h / 2, row:IsEnabled() and s.text or s.text_disabled,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local entryHooks = entry --[[@as PANEL]]
    entryHooks.Paint = function(_, w, h)
        local s = style()
        paint.Rect(0, 0, w, h, s.bg_raised)
        paint.Outline(0, 0, w, h, entry:HasFocus() and s.accent or s.border_strong, paint.Px(2))
        entry:DrawTextEntryText(s.text, s.bg_selected, s.text)
    end
    row.PWActivate = function() entry:RequestFocus() end
    return row
end

-- Builders --------------------------------------------------------------------------------------------------------

---Builders of the six widgets. Each returns the panel; emit(value) reports a change.
---@type table<PW.UIWidget, fun(parent: Panel, control: PW.UIFormControl, emit: fun(value: any)): Panel>
local builders = {}

builders.slider = function(parent, control, emit)
    local slider = vgui.Create("PWSlider", parent) --[[@as PWSlider]]
    slider:Setup(control.label, control.min or 0, control.max or 100, control.decimals or 0)
    slider:SetValue(tonumber(control.value) or 0)
    slider.OnValue = function(_, value) emit(value) end
    return slider
end

---@param parent Panel
---@param control PW.UIFormControl
---@param emit fun(value: any)
---@return PWSwitch
local function switch(parent, control, emit)
    local item = vgui.Create("PWSwitch", parent) --[[@as PWSwitch]]
    item:SetText(control.label)
    item.OnValue = function(_, value) emit(value) end
    return item
end

builders.number = function(parent, control, emit)
    local item = switch(parent, control, emit)
    item.decimals = control.decimals or 0
    item.step = item.decimals == 0 and 1 or 0.1
    item.min, item.max = control.min, control.max
    item:SetValue(tonumber(control.value) or 0)
    return item
end

builders.combo = function(parent, control, emit)
    local item = switch(parent, control, emit)
    item.options = control.options or {}
    item:SetValue(control.value)
    return item
end

builders.checkbox = function(parent, control, emit)
    local toggle = vgui.Create("PWToggle", parent) --[[@as PWToggle]]
    toggle:SetText(control.label)
    toggle:SetValue(control.value == true)
    toggle.OnToggled = function(_, value) emit(value) end
    return toggle
end

builders.multiselect = function(parent, control, emit)
    local box = vgui.Create("PWMultiSelect", parent) --[[@as PWMultiSelect]]
    box:Setup(control.label, control.options or {}, control.value or {})
    box.OnValue = function(_, value) emit(value) end
    return box
end

builders.idlist = idListRow

-- PWSettingsForm --------------------------------------------------------------------------------------------------

---@param parent Panel
---@param text string
---@return Panel
local function heading(parent, text)
    local item = vgui.Create("Panel", parent) --[[@as Panel]]
    item:SetTall(paint.Px(48))
    local title = string.upper(text)
    local hooks = item --[[@as PANEL]]
    hooks.Paint = function(_, w, h)
        local s = style()
        draw.SimpleText(title, fontSmall, paint.Px(20), h - paint.Px(10), s.text_muted, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_BOTTOM)
        paint.Rect(paint.Px(20), h - paint.Px(4), w - paint.Px(40), 1, s.border)
    end
    return item
end

---Restyles the scroll bar of a DScrollPanel with the tokens.
---@param scroll DScrollPanel
local function styleScrollBar(scroll)
    local vbar = scroll:GetVBar()
    vbar:SetHideButtons(true)
    vbar:SetWide(paint.Px(8))
    local barHooks = vbar --[[@as PANEL]]
    barHooks.Paint = function(_, w, h) paint.Rect(0, 0, w, h, style().bg_panel) end
    local grip = (vbar --[[@as { btnGrip: PANEL }]]).btnGrip
    grip.Paint = function(_, w, h) paint.Rect(0, 0, w, h, style().border_strong) end
end

local formClass = {}

function formClass:Init()
    styleScrollBar(self --[[@as DScrollPanel]])
end

---@param control PW.UIFormControl
---@param value any
function formClass:_Emit(control, value)
    local self_ = self --[[@as PWSettingsForm]]
    timer.Create("PW.UI.Form." .. control.id, settleTime, 1, function()
        if IsValid(self_) then self_:OnChange(control, value) end
    end)
end

---@param _ PW.UIFormControl
---@param _value any
function formClass:OnChange(_, _value)
end

---@param sections PW.UIFormSection[]
---@param editable boolean
function formClass:SetSections(sections, editable)
    local self_ = self --[[@as PWSettingsForm]]
    self_:Clear()
    for _, section in ipairs(sections) do
        heading(self_, section.title):Dock(TOP)
        for _, control in ipairs(section.controls) do
            local item = builders[control.widget](self_, control, function(value) self_:_Emit(control, value) end)
            item:Dock(TOP)
            item:DockMargin(0, 0, 0, paint.Px(2))
            item:SetEnabled(editable)
            item:SetMouseInputEnabled(editable)
        end
    end
    if #sections == 0 then
        local empty = vgui.Create("DLabel", self_) --[[@as DLabel]]
        empty:SetFont(fontBody)
        empty:SetTextColor(style().text_muted)
        empty:SetText("No settings for this mode.")
        empty:SizeToContentsY()
        empty:Dock(TOP)
        empty:DockMargin(paint.Px(20), paint.Px(12), 0, 0)
    end
end

vgui.Register("PWSettingsForm", formClass, "DScrollPanel")
