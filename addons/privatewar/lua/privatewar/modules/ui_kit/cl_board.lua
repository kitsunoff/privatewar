-- The same painted table serves results and LIVE. Text fitting and geometry are cached at layout, never Paint.
local lib = PW.UI --[[@as PW.UILib]]
local paint, board = lib.Draw, lib.Board

---@class PW.UIBoardPaintLine : PW.UIBoardLine
---@field y number
---@field h number
---@field name string fitted title
---@field botX number
---@field ink Color

---@class PWMatchBoard
---@field lines PW.UIBoardPaintLine[]
---@field label string
---@field viewport? Panel
---@field pad number
---@field edge number
---@field nameX number
---@field killsX number
---@field deathsX number
---@field scoreX number
---@field columnsH number
---@field body string
---@field small string
---@field heading string

local class = {}

---@param self PWMatchBoard
function class:Init()
    self.lines, self.label = {}, "SCORE"
    self:SetMouseInputEnabled(false)
    self:SetKeyboardInputEnabled(false)
end

---@param sections PW.UIBoardSection[]
---@param label? string
---@param self PWMatchBoard
function class:SetSections(sections, label)
    self.lines = board.Lines(sections) --[[@as PW.UIBoardPaintLine[] ]]
    self.label = label or "SCORE"
    self:InvalidateLayout(true)
end

---@param self PWMatchBoard
---@return number
function class:GetContentHeight()
    return paint.Px(board.Height(self.lines))
end

---@param viewport Panel
---@param self PWMatchBoard
function class:SetViewport(viewport)
    self.viewport = viewport
end

---@param line PW.UIBoardPaintLine
---@param width number
---@param font string
local function fitLine(line, width, font)
    surface.SetFont(font)
    line.name = board.Fit(line.title, math.max(0, width), surface.GetTextSize)
end

---@param width number
---@param self PWMatchBoard
function class:PerformLayout(width)
    local s = lib.Style --[[@as PW.UIStyle]]
    local px = paint.Px
    self.body, self.small, self.heading = lib.Font("body"), lib.Font("small"), lib.Font("h2")
    self.pad, self.edge, self.columnsH = px(20), px(4), px(36)
    self.nameX, self.killsX, self.deathsX, self.scoreX = px(76), width - px(320), width - px(200), width - px(20)
    local y = self.columnsH
    for index, line in ipairs(self.lines) do
        if line.header and index > 1 then y = y + px(12) end
        line.y, line.h = y, px(line.header and 48 or 40)
        if line.header then
            line.ink = line.relation == "friendly" and s.team_friendly
                or (line.relation == "enemy" and s.team_enemy or s.text)
            surface.SetFont(self.heading)
            local scoreW = surface.GetTextSize(line.score)
            fitLine(line, width - 3 * self.pad - scoreW, self.heading)
        else
            line.ink = line.me and s.accent or s.text
            fitLine(line, self.killsX - self.nameX - px(line.bot and 112 or 48), self.body)
            surface.SetFont(self.body)
            line.botX = self.nameX + surface.GetTextSize(line.name) + px(12)
        end
        y = y + line.h
    end
    self:SetTall(y)
end

---@param self_ PWMatchBoard
---@param line PW.UIBoardPaintLine
---@param width number
local function paintLine(self_, line, width)
    local s = lib.Style --[[@as PW.UIStyle]]
    local y, h, ink = line.y, line.h, line.ink
    local cy = y + h / 2
    if line.header then
        paint.Rect(0, y, width, h, s.bg_raised)
        paint.Rect(0, y, self_.edge, h, ink)
        draw.SimpleText(line.name, self_.heading, self_.pad, cy, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(line.score, self_.heading, self_.scoreX, cy, ink, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        return
    end
    if line.me then
        paint.Rect(0, y, width, h, s.bg_selected)
        paint.Rect(0, y, self_.edge, h, s.accent)
    end
    draw.SimpleText(line.place, self_.small, self_.pad, cy, s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(line.name, self_.body, self_.nameX, cy, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if line.bot then
        draw.SimpleText("BOT", self_.small, line.botX, cy, s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    draw.SimpleText(line.kills, self_.body, self_.killsX, cy, s.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(line.deaths, self_.body, self_.deathsX, cy, s.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(line.score, self_.body, self_.scoreX, cy, ink, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

---@param w number
---@param h number
---@param self PWMatchBoard
function class:Paint(w, h)
    if self.columnsH == nil then return end
    local s = lib.Style --[[@as PW.UIStyle]]
    paint.Rect(0, 0, w, h, s.bg_panel)
    local cy = self.columnsH / 2
    draw.SimpleText("PLAYER", self.small, self.nameX, cy, s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText("K", self.small, self.killsX, cy, s.text_muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText("D", self.small, self.deathsX, cy, s.text_muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(self.label, self.small, self.scoreX, cy, s.text_muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    local top, bottom = -math.huge, math.huge
    if IsValid(self.viewport) then
        local viewport = self.viewport --[[@as Panel]]
        local _, origin = self:LocalToScreen(0, 0)
        local _, clip = viewport:LocalToScreen(0, 0)
        top, bottom = clip - origin, clip - origin + viewport:GetTall()
    end
    for _, line in ipairs(self.lines) do
        if line.y > bottom then break end
        if line.y + line.h >= top then paintLine(self, line, w) end
    end
end

vgui.Register("PWMatchBoard", class, "Panel")
