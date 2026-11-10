-- Input-transparent held overlay, using the exact results-table component. No popup or expensive blur passes.
local lib = PW.UI --[[@as PW.UILib]]
local sb = lib.Scoreboard --[[@as PW.UIScoreboardLib]]
local paint = lib.Draw

---@class PWLiveScoreboard
---@field scroll DScrollPanel
---@field board PWMatchBoard
---@field rect PW.UIScoreboardLayout
---@field data PW.UIScoreboardData
---@field mapText string
---@field noteText string
---@field hintText string
---@field titleFont string
---@field bodyFont string
---@field smallFont string
---@field pad number
---@field edge number
---@field titleY number
---@field noteY number
---@field footerY number

local class = {}

---@param self PWLiveScoreboard
function class:Init()
    self:SetSize(ScrW(), ScrH())
    self:SetPos(0, 0)
    self:SetDrawOnTop(true)
    self:SetMouseInputEnabled(false)
    self:SetKeyboardInputEnabled(false)
    self.scroll = vgui.Create("DScrollPanel", self) --[[@as DScrollPanel]]
    self.scroll:SetMouseInputEnabled(false)
    self.scroll:SetKeyboardInputEnabled(false)
    self.scroll:GetVBar():SetWide(0)
    self.board = vgui.Create("PWMatchBoard", self.scroll) --[[@as PWMatchBoard]]
    self.board:SetViewport(self.scroll)
    self.board:Dock(TOP)
end

---@param data PW.UIScoreboardData
---@param self PWLiveScoreboard
function class:Update(data)
    self.data = data
    self.board:SetSections(data.sections, data.scoreLabel)
    local binding = string.upper(input.LookupBinding("+showscores") or "TAB")
    local hint = GetConVar("pw_ui_kit_hints")
    local override = hint ~= nil and hint:GetString() or "auto"
    self.hintText = (override == "gamepad" or (override == "auto" and data.gamepad))
        and "Hold VIEW  |  D-pad: scroll"
        or ("Hold " .. binding .. "  |  Up / Down / D-pad: scroll  |  PgUp / PgDn: page")
    self:InvalidateLayout(true)
end

---@param self PWLiveScoreboard
function class:PerformLayout()
    self:SetSize(ScrW(), ScrH())
    local rect = sb.Layout(ScrW(), ScrH(), (lib.S --[[@as fun(value: number): number]])(1))
    self.rect = rect
    self.titleFont, self.bodyFont, self.smallFont = lib.Font("h1"), lib.Font("body"), lib.Font("small")
    self.pad, self.edge = paint.Px(24), paint.Px(4)
    self.titleY, self.noteY, self.footerY = rect.y + paint.Px(38), rect.y + paint.Px(82), rect.y + rect.h - paint.Px(30)
    surface.SetFont(self.smallFont)
    self.mapText = lib.Board.Fit(self.data ~= nil and self.data.map or "", rect.w / 2, surface.GetTextSize)
    self.noteText = lib.Board.Fit(self.data ~= nil and (self.data.note or "LIVE") or "LIVE",
        rect.w - surface.GetTextSize(self.mapText) - 3 * self.pad, surface.GetTextSize)
    self.scroll:SetPos(rect.x, rect.y + rect.boardY)
    self.scroll:SetSize(rect.w, rect.boardH)
    self.board:SetWide(rect.w)
    self.board:InvalidateLayout(true)
end

---@param delta number
---@param self PWLiveScoreboard
function class:Scroll(delta)
    local bar = self.scroll:GetVBar()
    bar:SetScroll(bar:GetScroll() + delta)
end

---@param self PWLiveScoreboard
---@return number
function class:GetViewportHeight()
    return self.scroll:GetTall()
end

---@param w number
---@param h number
---@param self PWLiveScoreboard
function class:Paint(w, h)
    if self.rect == nil or self.data == nil then return end
    local s, rect = lib.Style --[[@as PW.UIStyle]], self.rect
    paint.Rect(0, 0, w, h, s.bg_scrim)
    paint.Rect(rect.x, rect.y, rect.w, rect.h, s.bg_panel)
    paint.Rect(rect.x, rect.y, self.edge, rect.boardY, s.accent)
    paint.Outline(rect.x, rect.y, rect.w, rect.h, s.border)
    local left, right = rect.x + self.pad, rect.x + rect.w - self.pad
    draw.SimpleText("SCOREBOARD", self.titleFont, left, self.titleY, s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(self.data.timer, self.bodyFont, right, self.titleY, s.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(self.noteText, self.smallFont, left, self.noteY, s.text_muted, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(self.mapText, self.smallFont, right, self.noteY, s.text_muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(self.hintText, self.smallFont, left, self.footerY, s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

vgui.Register("PWLiveScoreboard", class, "Panel")

function sb.Create()
    return vgui.Create("PWLiveScoreboard") --[[@as PWLiveScoreboard]]
end
