-- Kit v1 content components (U-4; notes/16-frontend-d1-proposal.md §3 items 5-10, 13). Thin vgui glue over the
-- pure models (sh_models.lua, sh_players.lua): PWCard and PWCardList (the selected card expands; paging from the
-- column height), PWPager, PWInfoCard (title + key/value rows or text, optional warning chip), PWSummary (mode
-- monogram, mode, map) and PWPlayerList with PWPlayerRow (sections, host first, "+N bots").

local lib = PW.UI --[[@as PW.UILib]]
local paint = lib.Draw
local fontH2, fontBody, fontSmall = lib.FontName("h2"), lib.FontName("body"), lib.FontName("small")

---@return PW.UIStyle
local function style()
    return lib.Style --[[@as PW.UIStyle]]
end

local cardHeight, cardGap, pagerHeight = 64, 6, 44

-- PWCard ----------------------------------------------------------------------------------------------------------

---@class PWCard : PWButton
---@field view PW.UICardView
---@field list? PWCardList
---@field index integer
---@field _title string the title cut to the room left of the badge (layout time)
---@field _fullTitle string
---@field _lines string[]
local cardClass = {}

function cardClass:Init()
    self._title, self._fullTitle, self._lines, self.index = "", "", {}, 0
    self:SetTall(paint.Px(cardHeight))
end

---@param view PW.UICardView
---@param index integer
function cardClass:SetView(view, index)
    self.view, self.index = view, index
    self._fullTitle = string.upper(view.card.title)
    self._title = self._fullTitle
    self:SetLocked(view.locked, view.reason)
    self:InvalidateLayout()
    local spec = self._pwFocus --[[@as PW.UIFocusSpec]]
    spec.disabled = view.disabled
    self:SetEnabled(not view.disabled)
end

---Cuts the title so it never runs into the badge, the "NEW" badge or the lock glyph.
---@param w number
function cardClass:PerformLayout(w, _)
    local view = self.view
    local marked = view ~= nil and (view.locked or view.new or view.card.badge ~= nil)
    local reserve = view ~= nil and view.locked and view.card.lockText ~= nil and 150 or 72
    local room = w - paint.Px(48) - (marked and paint.Px(reserve) or 0)
    self._title = paint.Fit(self._fullTitle, fontH2, room)
end

---Height of the card at a width; the expanded card wraps its description (layout time).
---@param width number
---@return number
function cardClass:WantedHeight(width)
    local view = self.view
    if view == nil or not view.expanded then return paint.Px(cardHeight) end
    self._lines = view.card.text ~= nil and paint.Wrap(view.card.text, fontBody, width - paint.Px(48)) or {}
    local extra = #self._lines * draw.GetFontHeight(fontBody)
    if view.card.tags ~= nil then extra = extra + paint.Px(34) end
    if view.card.footer ~= nil then extra = extra + paint.Px(30) end
    return paint.Px(cardHeight) + extra + paint.Px(16)
end

---@param action string
---@return boolean, Panel?
function cardClass:PWAct(action)
    local list = self.list
    if list == nil then return false end
    return list:CardAct(self, action)
end

function cardClass:PWOnFocus()
    if self.list ~= nil then self.list.focusIndex = self.index end
end

---Expanded rows: description, tags, footer.
---@param x number
---@param y number
---@param s PW.UIStyle
function cardClass:PaintDetails(x, y, s)
    local lineH = draw.GetFontHeight(fontBody)
    for index, line in ipairs(self._lines) do
        draw.SimpleText(line, fontBody, x, y + (index - 1) * lineH, s.text_muted)
    end
    y = y + #self._lines * lineH
    local card = self.view.card
    if card.tags ~= nil then
        draw.SimpleText(card.tags, fontSmall, x, y + paint.Px(6), s.accent)
        y = y + paint.Px(34)
    end
    if card.footer ~= nil then draw.SimpleText(card.footer, fontSmall, x, y + paint.Px(4), s.text_muted) end
end

---@param w number
---@param h number
function cardClass:Paint(w, h)
    local s, view = style(), self.view
    if view == nil then return true end
    local focused = self._pwFocused == true
    paint.Rect(0, 0, w, h, view.expanded and s.bg_raised or (focused and s.bg_hover or s.bg_panel))
    if focused then paint.Outline(0, 0, w, h, s.border_strong, paint.Px(2)) end
    if view.expanded or (focused and not view.locked) then paint.EdgeBar(h) end
    local pad, headerY = paint.Px(24), paint.Px(cardHeight) / 2
    local ink = (view.locked or view.disabled) and s.text_disabled or s.text
    draw.SimpleText(self._title, fontH2, pad, headerY, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if view.locked then
        local size = paint.Px(18)
        paint.Lock(w - pad - size, math.floor(headerY - size / 2), size, s.text_disabled)
        local lockText = view.card.lockText
        if lockText ~= nil then
            draw.SimpleText(lockText, fontSmall, w - pad - size - paint.Px(10), headerY, s.text_muted, TEXT_ALIGN_RIGHT,
                TEXT_ALIGN_CENTER)
        end
    elseif view.new then
        paint.Badge("NEW", fontSmall, w - pad, headerY, s.badge_new, s.on_accent)
    elseif view.card.badge ~= nil then
        draw.SimpleText(view.card.badge, fontSmall, w - pad, headerY, s.text_muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    if view.expanded then self:PaintDetails(pad, paint.Px(cardHeight) - paint.Px(4), s) end
    return true
end

vgui.Register("PWCard", cardClass, "PWButton")

-- PWPager ---------------------------------------------------------------------------------------------------------

---@class PWPagerArrow : PWButton
---@field down boolean
---@field _poly { x: number, y: number }[]
local arrowClass = {}

---@param w number
---@param h number
function arrowClass:PerformLayout(w, h)
    local size = math.min(w, h) * 0.3
    local cx, cy, sign = w / 2, h / 2, self.down and 1 or -1
    self._poly = {
        { x = cx - size, y = cy - sign * size / 2 }, { x = cx + size, y = cy - sign * size / 2 },
        { x = cx, y = cy + sign * size / 2 }
    }
    if not self.down then self._poly[1], self._poly[2] = self._poly[2], self._poly[1] end
end

---@param w number
---@param h number
function arrowClass:Paint(w, h)
    local s = style()
    local enabled = self:IsEnabled()
    if self._pwFocused and enabled then paint.Rect(0, 0, w, h, s.bg_hover) end
    paint.Outline(0, 0, w, h, enabled and s.border_strong or s.border, paint.Px(2))
    if self._poly == nil then return true end
    draw.NoTexture()
    surface.SetDrawColor(enabled and s.text or s.text_disabled)
    surface.DrawPoly(self._poly)
    return true
end

vgui.Register("PWPagerArrow", arrowClass, "PWButton")

---@class PWPager : Panel
---@field up PWPagerArrow
---@field down PWPagerArrow
---@field _text string
local pagerClass = {}

function pagerClass:Init()
    self._text = "1 / 1"
    self.up = vgui.Create("PWPagerArrow", self) --[[@as PWPagerArrow]]
    self.down = vgui.Create("PWPagerArrow", self) --[[@as PWPagerArrow]]
    self.down.down = true
    for delta, arrow in pairs({ [-1] = self.up, [1] = self.down }) do
        local spec = lib.Focusable(arrow, "pager" .. tostring(self))
        spec.axis = "horizontal"
        arrow.DoClick = function() self:OnPage(delta) end
    end
end

---@param state PW.UIPagerState
function pagerClass:SetState(state)
    self._text = string.format("%d / %d", state.page, state.pages)
    self.up:SetEnabled(not state.atStart)
    self.down:SetEnabled(not state.atEnd)
end

---@param _ integer -1 previous page, 1 next page
function pagerClass:OnPage(_)
end

---@param w number
---@param h number
function pagerClass:PerformLayout(w, h)
    local size = h
    self.up:SetSize(size, size)
    self.up:SetPos(math.floor(w / 2 - size * 2), 0)
    self.down:SetSize(size, size)
    self.down:SetPos(math.floor(w / 2 + size), 0)
end

---@param w number
---@param h number
function pagerClass:Paint(w, h)
    draw.SimpleText(self._text, fontBody, w / 2, h / 2, style().text_muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

vgui.Register("PWPager", pagerClass, "Panel")

-- PWCardList ------------------------------------------------------------------------------------------------------

---@class PWCardList : Panel
---@field cards PW.UICard[]
---@field selected? string
---@field panels PWCard[]
---@field pager PWPager
---@field focusIndex integer
---@field perPage integer
---@field state PW.UIPagerState
local listClass = {}

function listClass:Init()
    self.cards, self.panels, self.focusIndex, self.perPage = {}, {}, 1, 1
    self.state = lib.Pager.State(0, 1, 1)
    self.pager = vgui.Create("PWPager", self) --[[@as PWPager]]
    self.pager.OnPage = function(_, delta) self:Page(delta) end
end

---@param cards PW.UICard[]
---@param selected? string
function listClass:SetCards(cards, selected)
    for _, panel in ipairs(self.panels) do panel:Remove() end
    self.cards, self.selected, self.panels = cards, selected, {}
    local group = "cards" .. tostring(self)
    for index = 1, #cards do
        local card = vgui.Create("PWCard", self) --[[@as PWCard]]
        card.list = self
        lib.Focusable(card, group)
        card.DoClick = function() self:Activate(index) end
        self.panels[index] = card
    end
    self:Refresh()
end

---Applies the selection to the cards (the selected card is the expanded one) and lays them out again.
function listClass:Refresh()
    for index, view in ipairs(lib.Cards.View(self.cards, self.selected)) do
        (self.panels[index] --[[@as PWCard]]):SetView(view, index)
    end
    self:InvalidateLayout(true)
end

---@param index integer
function listClass:Activate(index)
    local card = self.cards[index]
    if card == nil then return end
    local selected = lib.Cards.Select(self.cards, self.selected, card.id)
    if selected == self.selected then return end
    self.selected, self.focusIndex = selected, index
    self:Refresh()
    if selected ~= nil then self:OnSelect(selected) end
end

---@param _ string
function listClass:OnSelect(_)
end

---The nearest card from index on that focus can reach (not disabled), searching in the step direction first.
---@param index integer
---@param step integer 1 or -1
---@return integer?
function listClass:Reachable(index, step)
    for _, direction in ipairs({ step, -step }) do
        local at = index
        while self.cards[at] ~= nil do
            if not self.cards[at].disabled then return at end
            at = at + direction
        end
    end
    return nil
end

---Moves the focus to a card index (skipping disabled cards) and shows its page.
---@param index integer
---@param step integer
---@return Panel?
function listClass:FocusIndex(index, step)
    local target = self:Reachable(math.Clamp(index, 1, math.max(1, #self.cards)), step)
    if target == nil then return nil end
    self.focusIndex = target
    self:InvalidateLayout(true)
    return self.panels[target]
end

---@param delta integer
---@return Panel?
function listClass:Page(delta)
    return self:FocusIndex(self.state.first + delta * self.perPage, delta)
end

---Up and down walk the cards in order (skipping disabled ones, turning pages); past the ends the focus graph moves
---to the neighbour group (returns false).
---@param card PWCard
---@param action string
---@return boolean, Panel?
function listClass:CardAct(card, action)
    if action == "page_down" or action == "page_up" then return true, self:Page(action == "page_down" and 1 or -1) end
    local index = card.index
    local step = (action == "down" and 1) or (action == "up" and -1) or 0
    local target = step ~= 0 and self:Reachable(index + step, step) or nil
    if target == nil or (target - index) * step <= 0 then return false end
    return true, self:FocusIndex(target, step)
end

---@param w number
---@param h number
function listClass:PerformLayout(w, h)
    local rowH, gap = paint.Px(cardHeight), paint.Px(cardGap)
    local extra = 0
    for _, card in ipairs(self.panels) do
        if card.view ~= nil and card.view.expanded then extra = card:WantedHeight(w) - rowH end
    end
    local paged = lib.Pager.RowsPerPage(h - extra, rowH, gap) < #self.cards
    local usable = paged and h - extra - paint.Px(pagerHeight) - gap or h - extra
    self.perPage = lib.Pager.RowsPerPage(usable, rowH, gap)
    self.state = lib.Pager.State(#self.cards, self.perPage, self.focusIndex)
    local y = 0
    for index, card in ipairs(self.panels) do
        local shown = index >= self.state.first and index <= self.state.last
        card:SetVisible(shown)
        if shown then
            card:SetPos(0, y)
            card:SetSize(w, card:WantedHeight(w))
            y = y + card:GetTall() + gap
        end
    end
    self.pager:SetVisible(paged)
    self.pager:SetState(self.state)
    self.pager:SetSize(w, paint.Px(pagerHeight))
    self.pager:SetPos(0, h - paint.Px(pagerHeight))
end

vgui.Register("PWCardList", listClass, "Panel")

-- PWInfoCard ------------------------------------------------------------------------------------------------------

---@class PWInfoCard : Panel
---@field _title string
---@field rows { [1]: string, [2]: string }[]
---@field text? string
---@field _lines string[]
---@field _keys string[] row keys cut to the room left of their values (layout time)
---@field chip? PWWarningChip
local infoClass = {}

local infoHeader, infoRow = 56, 40

function infoClass:Init()
    self._title, self.rows, self._lines, self._keys = "", {}, {}, {}
end

---@param text string
function infoClass:SetTitle(text)
    self._title = string.upper(text)
end

---@param rows { [1]: string, [2]: string }[] key and value pairs
function infoClass:SetRows(rows)
    self.rows, self._keys = rows, {}
    self:InvalidateLayout()
end

---@param text? string free text under the rows
function infoClass:SetText(text)
    self.text = text
end

---@param text? string warning chip at the bottom (nil removes it)
function infoClass:SetWarning(text)
    if IsValid(self.chip) then (self.chip --[[@as Panel]]):Remove() end
    self.chip = nil
    if text == nil then return end
    self.chip = vgui.Create("PWWarningChip", self) --[[@as PWWarningChip]]
    self.chip:SetText(text)
end

---Height for a width (wraps the free text; layout time).
---@param width number
---@return number
function infoClass:WantedHeight(width)
    local pad = paint.Px(20)
    self._lines = self.text ~= nil and paint.Wrap(self.text, fontBody, width - 2 * pad) or {}
    local height = paint.Px(infoHeader) + pad / 2 + #self.rows * paint.Px(infoRow)
    height = height + #self._lines * draw.GetFontHeight(fontBody)
    if self.chip ~= nil then height = height + self.chip:GetTall() + pad / 2 end
    return height + pad
end

---@param w number
---@param h number
function infoClass:PerformLayout(w, h)
    self:WantedHeight(w)
    local pad, gap = paint.Px(20), paint.Px(16)
    surface.SetFont(fontBody)
    for index, row in ipairs(self.rows) do
        local valueW = surface.GetTextSize(row[2])
        self._keys[index] = paint.Fit(row[1], fontBody, w - 2 * pad - valueW - gap)
    end
    if self.chip ~= nil then self.chip:SetPos(paint.Px(20), h - paint.Px(20) - self.chip:GetTall()) end
end

---@param w number
---@param h number
function infoClass:Paint(w, h)
    local s = style()
    local pad, header = paint.Px(20), paint.Px(infoHeader)
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Rect(0, 0, w, header, s.bg_raised)
    paint.Outline(0, 0, w, h, s.border)
    draw.SimpleText(self._title, fontH2, pad, header / 2, s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local y = header + pad / 2
    local rowH = paint.Px(infoRow)
    for index, row in ipairs(self.rows) do
        local key = self._keys[index] or row[1]
        draw.SimpleText(key, fontBody, pad, y + rowH / 2, s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(row[2], fontBody, w - pad, y + rowH / 2, s.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        y = y + rowH
    end
    local lineH = draw.GetFontHeight(fontBody)
    for index, line in ipairs(self._lines) do
        draw.SimpleText(line, fontBody, pad, y + (index - 1) * lineH, s.text_muted)
    end
end

vgui.Register("PWInfoCard", infoClass, "Panel")

-- PWSummary -------------------------------------------------------------------------------------------------------

---@class PWSummary : Panel
---@field _badge string
---@field _mode string
---@field _map string
local summaryClass = {}

function summaryClass:Init()
    self._badge, self._mode, self._map = "?", "", ""
    self:SetTall(paint.Px(104))
end

---@param mode PW.UIModeLike
---@param map string
function summaryClass:SetSelection(mode, map)
    self._badge = lib.Monogram(mode)
    self._mode = string.upper(mode.Name or "")
    self._map = map
end

---@param w number
---@param h number
function summaryClass:Paint(w, h)
    local s = style()
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Outline(0, 0, w, h, s.border)
    local pad = paint.Px(16)
    local size = h - 2 * pad
    paint.Rect(pad, pad, size, size, s.bg_raised)
    paint.Outline(pad, pad, size, size, s.accent, paint.Px(2))
    draw.SimpleText(self._badge, fontH2, pad + size / 2, h / 2, s.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    local x = pad * 2 + size
    draw.SimpleText(self._mode, fontH2, x, h / 2 + paint.Px(2), s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    draw.SimpleText(self._map, fontBody, x, h / 2 + paint.Px(4), s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end

vgui.Register("PWSummary", summaryClass, "Panel")

include("privatewar/modules/ui_kit/cl_players.lua")
