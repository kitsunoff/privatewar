-- Player list (U-4; notes/16-frontend-d1-proposal.md §3 items 9-10; 10-frontend.md d.5, d.9): PWPlayerList draws the
-- sections of PW.UI.PlayerList (sh_players.lua): a header per section (title, count, team colour relative to the
-- local player; neutral text in LOBBY), one PWPlayerRow per human (host marker) and a "+N bots" row. Rows are
-- focusable; accept calls OnPlayer. lib.CollectPlayers turns the connected players into plain records.

local lib = PW.UI --[[@as PW.UILib]]
local paint = lib.Draw
local fontH2, fontBody, fontSmall = lib.FontName("h2"), lib.FontName("body"), lib.FontName("small")

---@return PW.UIStyle
local function style()
    return lib.Style --[[@as PW.UIStyle]]
end

---@param relation PW.UITeamRelation
---@return Color
local function relationColour(relation)
    local s = style()
    if relation == "friendly" then return s.team_friendly end
    if relation == "enemy" then return s.team_enemy end
    return s.text
end

local headerHeight, rowHeight, botsHeight = 52, 44, 40

---@class PWPlayerRow : PWButton
---@field info PW.UIPlayerInfo
---@field relation PW.UITeamRelation
local rowClass = {}

---@param info PW.UIPlayerInfo
---@param relation PW.UITeamRelation
function rowClass:SetPlayer(info, relation)
    self.info, self.relation = info, relation
    self:SetText(info.name)
    self:SetTall(paint.Px(rowHeight))
end

---@param w number
---@param h number
function rowClass:Paint(w, h)
    local s = style()
    if self._pwFocused then paint.Rect(0, 0, w, h, s.bg_hover) end
    local bar = self.relation == "neutral" and s.border_strong or relationColour(self.relation)
    paint.Rect(paint.Px(20), paint.Px(8), paint.Px(4), h - paint.Px(16), bar)
    local x = paint.Px(36)
    draw.SimpleText(self._label, fontBody, x, h / 2, s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if self.info ~= nil and self.info.host then
        local pad = paint.Px(20)
        surface.SetFont(fontSmall)
        local tw, th = surface.GetTextSize("HOST")
        local bw, bh = tw + paint.Px(16), th + paint.Px(4)
        local bx, by = w - pad - bw, math.floor((h - bh) / 2)
        paint.Outline(bx, by, bw, bh, s.accent, paint.Px(2))
        draw.SimpleText("HOST", fontSmall, bx + bw / 2, h / 2, s.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return true
end

vgui.Register("PWPlayerRow", rowClass, "PWButton")

---Header and bots line of a section: plain painted panels.
---@class PWPlayerLine : Panel
---@field kind "header"|"bots"
---@field title string
---@field count string
---@field colour Color
local lineClass = {}

---@param w number
---@param h number
function lineClass:Paint(w, h)
    local s, pad = style(), paint.Px(20)
    if self.kind == "bots" then
        draw.SimpleText(self.title, fontBody, paint.Px(36), h / 2, s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return
    end
    paint.Rect(0, 0, w, h, s.bg_raised)
    draw.SimpleText(self.title, fontH2, pad, h / 2, self.colour, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(self.count, fontBody, w - pad, h / 2, s.text_muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

vgui.Register("PWPlayerLine", lineClass, "Panel")

---@class PWPlayerList : Panel
---@field children Panel[]
---@field note? string
---@field _noteLines string[]
local listClass = {}

function listClass:Init()
    self.children, self._noteLines = {}, {}
end

---@param self PWPlayerList
---@param kind "header"|"bots"
---@param title string
---@param count string
---@param colour Color
---@param height number design units
local function addLine(self, kind, title, count, colour, height)
    local line = vgui.Create("PWPlayerLine", self) --[[@as PWPlayerLine]]
    line.kind, line.title, line.count, line.colour = kind, title, count, colour
    line:SetTall(paint.Px(height))
    self.children[#self.children + 1] = line
end

---@param section PW.UIPlayerSection
---@return string
local function countText(section)
    if section.capacity ~= nil then return string.format("%d/%d", section.humans, section.capacity) end
    return tostring(section.humans + section.bots)
end

---@param sections PW.UIPlayerSection[]
function listClass:SetSections(sections)
    for _, child in ipairs(self.children) do child:Remove() end
    self.children = {}
    local group = "players" .. tostring(self)
    for _, section in ipairs(sections) do
        local title, colour = string.upper(section.title), relationColour(section.relation)
        addLine(self, "header", title, countText(section), colour, headerHeight)
        for _, info in ipairs(section.rows) do
            local row = vgui.Create("PWPlayerRow", self) --[[@as PWPlayerRow]]
            row:SetPlayer(info, section.relation)
            lib.Focusable(row, group)
            row.DoClick = function() self:OnPlayer(info) end
            self.children[#self.children + 1] = row
        end
        if section.botsText ~= nil then addLine(self, "bots", section.botsText, "", style().text_muted, botsHeight) end
    end
    self:InvalidateLayout(true)
end

---@param note? string small text under the sections ("Teams are assigned when the match starts")
function listClass:SetNote(note)
    self.note = note
end

---@param _ PW.UIPlayerInfo
function listClass:OnPlayer(_)
end

---@param width number
---@return number
function listClass:WantedHeight(width)
    local height = 0
    for _, child in ipairs(self.children) do height = height + child:GetTall() end
    self._noteLines = self.note ~= nil and paint.Wrap(self.note, fontSmall, width - paint.Px(40)) or {}
    return height + #self._noteLines * draw.GetFontHeight(fontSmall) + paint.Px(12)
end

---@param w number
function listClass:PerformLayout(w, _)
    local y = 0
    for _, child in ipairs(self.children) do
        child:SetPos(0, y)
        child:SetWide(w)
        y = y + child:GetTall()
    end
    self:WantedHeight(w)
end

---@param w number
---@param h number
function listClass:Paint(w, h)
    local s = style()
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Outline(0, 0, w, h, s.border)
    local lineH = draw.GetFontHeight(fontSmall)
    local y = h - paint.Px(8) - #self._noteLines * lineH
    for index, line in ipairs(self._noteLines) do
        draw.SimpleText(line, fontSmall, paint.Px(20), y + (index - 1) * lineH, s.text_muted)
    end
end

vgui.Register("PWPlayerList", listClass, "Panel")

function lib.CollectPlayers()
    ---@type PW.UIPlayerInfo[]
    local out = {}
    for _, ply in ipairs(player.GetAll()) do
        out[#out + 1] = { name = ply:Nick(), bot = ply:IsBot(), host = ply:IsListenServerHost(), team = ply:Team() }
    end
    return out
end
