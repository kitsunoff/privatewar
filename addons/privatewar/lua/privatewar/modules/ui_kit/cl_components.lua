-- Kit v1 frame components (U-4; notes/16-frontend-d1-proposal.md §3 items 1-3, 11, 15, 18-20). Thin vgui glue over
-- the pure models of sh_models.lua: PWScreenTitle (title with a thin rule), PWTab and PWTabBar (active, focused,
-- locked, "NEW", bumper hints), PWStatusLine (phase, timer, players), PWHintBar (actions of the screen in the glyphs
-- of the current input device, a locked node's reason), PWWarningChip, PWBackdrop (blur + scrim), PWTimer and
-- PWDialog. Strings and sizes are prepared in setters, Think or PerformLayout; Paint only draws.

local lib = PW.UI --[[@as PW.UILib]]
local paint = lib.Draw
local fontTitle, fontH1, fontH2 = lib.FontName("title"), lib.FontName("h1"), lib.FontName("h2")
local fontBody, fontSmall, fontHint = lib.FontName("body"), lib.FontName("small"), lib.FontName("hint")

---@return PW.UIStyle
local function style()
    return lib.Style --[[@as PW.UIStyle]]
end

-- PWScreenTitle ---------------------------------------------------------------------------------------------------

---@class PWScreenTitle : Panel
---@field _text string
local titleClass = {}

function titleClass:Init()
    self._text = ""
end

---@param text string
function titleClass:SetText(text)
    self._text = string.upper(text)
end

function titleClass:Paint(w, h)
    local s = style()
    surface.SetFont(fontTitle)
    local tw = surface.GetTextSize(self._text)
    draw.SimpleText(self._text, fontTitle, 0, h - paint.Px(14), s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    paint.Rect(0, h - paint.Px(2), math.min(w, tw + paint.Px(48)), paint.Px(2), s.border_strong)
end

vgui.Register("PWScreenTitle", titleClass, "Panel")

-- PWTab and PWTabBar ----------------------------------------------------------------------------------------------

---@class PWTab : PWButton
---@field item PW.UITabItem
local tabClass = {}

---@param item PW.UITabItem
function tabClass:SetItem(item)
    self.item = item
    self:SetText(item.label)
    self:SetFont(fontH2)
    self:SetLocked(item.locked, item.reason)
    lib.Focusable(self, "tabs", "tab:" .. item.id)
    local spec = self._pwFocus --[[@as PW.UIFocusSpec]]
    spec.axis, spec.wrap = "horizontal", true
    spec.locked, spec.reason = item.locked, item.locked and lib.LockReason(item.reason) or nil
    surface.SetFont(fontH2)
    local width = surface.GetTextSize(item.label) + paint.Px(40)
    if item.locked then width = width + paint.Px(28) end
    if item.new then
        surface.SetFont(fontSmall)
        width = width + surface.GetTextSize("NEW") + paint.Px(28)
    end
    self:SetWide(width)
end

function tabClass:Paint(w, h)
    local s, item = style(), self.item
    if item == nil then return true end
    if self._pwFocused then paint.Rect(0, 0, w, h, s.bg_hover) end
    local ink = s.text_muted
    if item.locked then ink = s.text_disabled elseif item.active then ink = s.text end
    local x = paint.Px(20)
    local tw = draw.SimpleText(self._label, fontH2, x, h / 2, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    x = x + tw + paint.Px(10)
    if item.locked then
        local size = paint.Px(16)
        paint.Lock(x, math.floor((h - size) / 2), size, s.text_disabled)
    elseif item.new then
        surface.SetFont(fontSmall)
        x = x + surface.GetTextSize("NEW") + paint.Px(16)
        paint.Badge("NEW", fontSmall, x, h / 2, s.badge_new, s.on_accent)
    end
    if item.active then paint.Rect(0, h - paint.Px(4), w, paint.Px(4), s.accent) end
    return true
end

vgui.Register("PWTab", tabClass, "PWButton")

---@class PWTabBar : Panel
---@field tabs PWTab[]
---@field input? PW.UIInputState
---@field _device? string
---@field _prev string
---@field _next string
---@field _capDevice "keyboard"|"controller"
local tabBarClass = {}

function tabBarClass:Init()
    self.tabs = {}
    self._prev, self._next, self._capDevice = "Q", "E", "keyboard"
end

---@param state PW.UIInputState
function tabBarClass:SetInputState(state)
    self.input = state
end

---@param items PW.UITabItem[]
function tabBarClass:SetItems(items)
    for _, tab in ipairs(self.tabs) do tab:Remove() end
    self.tabs = {}
    for index, item in ipairs(items) do
        local tab = vgui.Create("PWTab", self) --[[@as PWTab]]
        tab:SetItem(item)
        tab.DoClick = function() self:OnSelect(item.id) end
        self.tabs[index] = tab
    end
    self:InvalidateLayout(true)
end

---@param _ string
function tabBarClass:OnSelect(_)
end

function tabBarClass:PerformLayout(_, h)
    surface.SetFont(fontHint)
    local x = paint.Px(56)
    for _, tab in ipairs(self.tabs) do
        tab:SetPos(x, 0)
        tab:SetTall(h - paint.Px(2))
        x = x + tab:GetWide() + paint.Px(8)
    end
end

function tabBarClass:Think()
    local state = self.input
    if state == nil or state.device == self._device then return end
    self._device = state.device
    local override = lib.HintOverride()
    local prev, nxt = lib.Input.Hint(state, "tab_prev", override), lib.Input.Hint(state, "tab_next", override)
    self._prev, self._next, self._capDevice = prev.label, nxt.label, prev.device
end

---@param w number
---@param h number
function tabBarClass:Paint(w, h)
    local s = style()
    paint.Rect(0, h - paint.Px(2), w, paint.Px(2), s.border)
    local yCentre = (h - paint.Px(2)) / 2
    paint.KeyCap(self._prev, fontHint, 0, yCentre, self._capDevice)
    local last = self.tabs[#self.tabs]
    if last ~= nil then
        local x = last:GetX() + last:GetWide() + paint.Px(16)
        paint.KeyCap(self._next, fontHint, x, yCentre, self._capDevice)
    end
end

vgui.Register("PWTabBar", tabBarClass, "Panel")

-- PWStatusLine ----------------------------------------------------------------------------------------------------

---@class PWStatusLine : Panel
---@field _info? PW.UIStatusInfo fixed data (dev showcase); nil reads the game
---@field _note? string
---@field _key number CurTime() of the next refresh
---@field _text string
---@field _warning boolean
local statusClass = {}

function statusClass:Init()
    self._key, self._text, self._warning = -1, "", false
end

---@param info? PW.UIStatusInfo
function statusClass:SetInfo(info)
    self._info, self._key = info, -1
end

---@param note? string
function statusClass:SetNote(note)
    self._note, self._key = note, -1
end

---@return PW.UIStatusInfo
function statusClass:LiveInfo()
    local ends = PW.Phase.GetEnd()
    return {
        phase = PW.Phase.GetPhase(), remaining = ends > 0 and ends - CurTime() or nil,
        humans = #player.GetHumans(), maxPlayers = game.MaxPlayers(), note = self._note
    }
end

-- Seconds between two reads of the game state (the timer shows whole seconds).
local statusPeriod = 0.2

function statusClass:Think()
    local now = CurTime()
    if now < self._key then return end
    self._key = self._info ~= nil and math.huge or now + statusPeriod
    local status = lib.Status(self._info or self:LiveInfo())
    self._text, self._warning = status.text, status.warning
end

function statusClass:Paint(w, h)
    local s = style()
    draw.SimpleText(self._text, fontBody, w, h / 2, self._warning and s.warning or s.text, TEXT_ALIGN_RIGHT,
        TEXT_ALIGN_CENTER)
end

vgui.Register("PWStatusLine", statusClass, "Panel")

-- PWHintBar -------------------------------------------------------------------------------------------------------

---@class PWHintBar : Panel
---@field input PW.UIInputState
---@field entries PW.UIHintEntry[]
---@field items PW.UIHintItem[]
---@field reason? string
---@field _device? string
---@field _override? string
local hintClass = {}

function hintClass:Init()
    self.input, self.entries, self.items = lib.Input.New(), {}, {}
end

---@param state PW.UIInputState
function hintClass:SetInputState(state)
    self.input, self._device = state, nil
end

---@param entries PW.UIHintEntry[]
function hintClass:SetEntries(entries)
    self.entries, self._device = entries, nil
end

---A locked node's reason, shown after the actions (nil hides it).
---@param reason? string
function hintClass:SetReason(reason)
    self.reason = reason
end

function hintClass:Think()
    local override = lib.HintOverride()
    if self.input.device == self._device and override == self._override then return end
    self._device, self._override = self.input.device, override
    self.items = lib.Hints(self.input, self.entries, override)
end

---@param w number
---@param h number
function hintClass:Paint(w, h)
    local s = style()
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Rect(0, 0, w, 1, s.border)
    ---@type number
    local x = paint.Px(96)
    local y = h / 2
    for _, item in ipairs(self.items) do
        ---@type number
        local capWidth = paint.KeyCap(item.cap, fontHint, x, y, item.device)
        ---@type number
        local labelX = x + capWidth + paint.Px(10)
        ---@type number
        local tw = draw.SimpleText(item.label, fontBody, labelX, y, s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        x = labelX + tw + paint.Px(36)
    end
    local reason = self.reason
    if reason == nil then return end
    local size = paint.Px(18)
    paint.Lock(x, math.floor(y - size / 2), size, s.text_muted)
    draw.SimpleText(reason, fontBody, x + size + paint.Px(10), y, s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

vgui.Register("PWHintBar", hintClass, "Panel")

-- PWWarningChip ---------------------------------------------------------------------------------------------------

---@class PWWarningChip : Panel
---@field _text string
local chipClass = {}

function chipClass:Init()
    self._text = ""
    self:SetTall(paint.Px(44))
end

---Sets the text and sizes the chip to it.
---@param text string
function chipClass:SetText(text)
    self._text = text
    surface.SetFont(fontSmall)
    self:SetWide(surface.GetTextSize(text) + paint.Px(72))
end

function chipClass:Paint(w, h)
    local s = style()
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Outline(0, 0, w, h, s.warning, paint.Px(2))
    local size = paint.Px(24)
    local x, y = paint.Px(12), math.floor((h - size) / 2)
    draw.RoundedBox(math.floor(size / 2), x, y, size, size, s.warning)
    draw.SimpleText("!", fontSmall, x + size / 2, h / 2, s.on_accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(self._text, fontSmall, x + size + paint.Px(12), h / 2, s.warning, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
end

vgui.Register("PWWarningChip", chipClass, "Panel")

-- PWBackdrop ------------------------------------------------------------------------------------------------------

local backdropClass = {}

function backdropClass:Paint(w, h)
    paint.Backdrop(self --[[@as Panel]], w, h)
end

vgui.Register("PWBackdrop", backdropClass, "Panel")

-- PWTimer ---------------------------------------------------------------------------------------------------------

---@class PWTimer : Panel
---@field _ends number CurTime() at which the timer reaches 0:00
---@field _seconds integer
---@field _text string
---@field _warning boolean
local timerClass = {}

function timerClass:Init()
    self._ends, self._seconds, self._text, self._warning = 0, -1, "0:00", false
    self:SetTall(paint.Px(56))
end

---@param ends number CurTime() of the end
function timerClass:SetEndTime(ends)
    self._ends, self._seconds = ends, -1
end

function timerClass:Think()
    local left = self._ends - CurTime()
    local seconds = math.max(0, math.ceil(left))
    if seconds == self._seconds then return end
    self._seconds = seconds
    self._text = lib.FormatTime(seconds)
    self._warning = seconds <= 10
end

function timerClass:Paint(_, h)
    local s = style()
    draw.SimpleText(self._text, fontH1, 0, h / 2, self._warning and s.warning or s.text, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
end

vgui.Register("PWTimer", timerClass, "Panel")

-- PWDialog --------------------------------------------------------------------------------------------------------

---@class PWDialog : EditablePanel
---@field spec PW.UIDialogSpec
---@field lines string[]
---@field box Panel
---@field confirm PWButton
---@field cancel PWButton
---@field alt? PWButton the optional third button (spec.alt)
---@field root? Panel
local dialogClass = {}

---@param spec PW.UIDialogSpec
function dialogClass:Setup(spec)
    self.spec, self.lines = spec, {}
    self.box = vgui.Create("Panel", self) --[[@as Panel]]
    local box = self.box --[[@as PANEL]]
    box.Paint = function(_, w, h)
        local s = style()
        paint.Rect(0, 0, w, h, s.bg_raised)
        paint.Outline(0, 0, w, h, s.border_strong, paint.Px(2))
        paint.Rect(0, 0, w, paint.Px(4), s.accent)
        local pad = paint.Px(32)
        draw.SimpleText(string.upper(self.spec.title), fontH2, pad, pad, s.text)
        local lineH = draw.GetFontHeight(fontBody)
        for index, line in ipairs(self.lines) do
            draw.SimpleText(line, fontBody, pad, pad + paint.Px(56) + (index - 1) * lineH, s.text_muted)
        end
    end
    self.confirm = vgui.Create("PWButton", self.box) --[[@as PWButton]]
    self.confirm:SetText(spec.confirm)
    self.confirm:SetPrimary(true)
    self.confirm.DoClick = function() self:Finish(true) end
    self.cancel = vgui.Create("PWButton", self.box) --[[@as PWButton]]
    self.cancel:SetText(spec.cancel or "CANCEL")
    self.cancel:SetVariant("secondary")
    self.cancel.DoClick = function() self:Finish(false) end
    ---@type PWButton[]
    local buttons = { self.confirm, self.cancel }
    if spec.alt ~= nil then
        local alt = vgui.Create("PWButton", self.box) --[[@as PWButton]]
        alt:SetText(spec.alt)
        alt:SetVariant("secondary")
        alt.DoClick = function() self:Finish("alt") end
        self.alt, buttons[3] = alt, alt
    end
    for _, button in ipairs(buttons) do
        local focusSpec = lib.Focusable(button, "dialog")
        focusSpec.axis = "horizontal"
    end
end

---Closes the dialog and runs the callback of the chosen button (true: confirm, false: cancel, "alt": the third).
---@param choice boolean|"alt"
function dialogClass:Finish(choice)
    local spec, root = self.spec, self.root
    self:Remove()
    if root ~= nil and IsValid(root) and root.CloseModal ~= nil then root:CloseModal() end
    local callback = spec.onCancel
    if choice == true then callback = spec.onConfirm elseif choice == "alt" then callback = spec.onAlt end
    if callback ~= nil then callback() end
end

function dialogClass:PWBack()
    self:Finish(false)
end

function dialogClass:PerformLayout(w, h)
    local pad, width = paint.Px(32), math.min(w - paint.Px(64), paint.Px(760)) -- three buttons fit: 3 x 220 + gaps
    self.lines = paint.Wrap(self.spec.text, fontBody, width - 2 * pad)
    local lineH = draw.GetFontHeight(fontBody)
    local buttonH = paint.Px(52)
    local height = pad + paint.Px(56) + #self.lines * lineH + paint.Px(32) + buttonH + pad
    self.box:SetSize(width, height)
    self.box:SetPos(math.floor((w - width) / 2), math.floor((h - height) / 2))
    local buttonW = paint.Px(220)
    self.confirm:SetSize(buttonW, buttonH)
    self.confirm:SetPos(width - pad - buttonW, height - pad - buttonH)
    -- Right to left: confirm, the optional third button, cancel.
    local slot = 1
    if self.alt ~= nil then
        self.alt:SetSize(buttonW, buttonH)
        self.alt:SetPos(width - pad - 2 * buttonW - paint.Px(16), height - pad - buttonH)
        slot = 2
    end
    self.cancel:SetSize(buttonW, buttonH)
    self.cancel:SetPos(width - pad - (slot + 1) * buttonW - slot * paint.Px(16), height - pad - buttonH)
end

---@param w number
---@param h number
function dialogClass:Paint(w, h)
    paint.Backdrop(self, w, h) -- blurs the screen behind, the menu included
end

vgui.Register("PWDialog", dialogClass, "EditablePanel")

function lib.OpenDialog(spec)
    local root = lib.CurrentRoot()
    local dialog = vgui.Create("PWDialog", root) --[[@as PWDialog]]
    dialog:Setup(spec)
    if root ~= nil and root.OpenModal ~= nil then
        dialog.root = root
        dialog:SetSize(root:GetWide(), root:GetTall())
        root:OpenModal(dialog, dialog.confirm)
    else
        dialog:SetSize(ScrW(), ScrH())
        dialog:MakePopup()
    end
    return dialog
end
