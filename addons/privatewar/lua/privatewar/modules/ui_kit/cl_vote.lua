-- Vote card (U-7; notes/16-frontend-d1-proposal.md §4d; 10-frontend.md VOTE): PWVoteCard shows one vote option as a
-- tall card: map thumbnail (or a placeholder with the map name), mode monogram and name, map, the vote count and a
-- "YOUR VOTE" mark on the card the player voted for. The card is a focusable PWButton (accept votes). Data comes from
-- PW.Vote._Cards (vote/sh_cards.lua); this file only paints.

local lib = PW.UI --[[@as PW.UILib]]
local paint = lib.Draw
local fontH1, fontH2, fontBody, fontSmall = lib.FontName("h1"), lib.FontName("h2"), lib.FontName("body"),
    lib.FontName("small")

---@return PW.UIStyle
local function style()
    return lib.Style --[[@as PW.UIStyle]]
end

---@type table<string, IMaterial|false>
local thumbs = {}

---The thumbnail of a map, false when the file does not exist (looked up once per path).
---@param path string?
---@return IMaterial|false
local function thumbOf(path)
    if path == nil then return false end
    local cached = thumbs[path]
    if cached == nil then
        cached = file.Exists(path, "GAME") and Material(path) or false
        thumbs[path] = cached
    end
    return cached
end

---@class PWVoteCard : PWButton
---@field card PW.VoteCard
---@field _map string the map cut to the card width (layout time)
local cardClass = {}

---@param card PW.VoteCard
function cardClass:SetCard(card)
    self.card, self._map = card, card.map
    self:SetSelected(card.mine)
    self:InvalidateLayout()
end

---@param w number
function cardClass:PerformLayout(w, _)
    if self.card ~= nil then self._map = paint.Fit(self.card.map, fontBody, w - 2 * paint.Px(20)) end
end

---@param w number
---@param h number
---@param card PW.VoteCard
local function paintThumb(w, h, card)
    local s = style()
    local material = thumbOf(card.thumb)
    if material then
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(material)
        surface.DrawTexturedRect(0, 0, w, h)
        return
    end
    paint.Rect(0, 0, w, h, s.bg_raised)
    draw.SimpleText(card.map, fontH2, w / 2, h / 2, s.text_muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("NO PREVIEW", fontSmall, w / 2, h / 2 + paint.Px(30), s.text_disabled, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
end

---@param w number
---@param h number
function cardClass:Paint(w, h)
    local s, card = style(), self.card
    if card == nil then return true end
    local focused = self._pwFocused == true
    paint.Rect(0, 0, w, h, focused and s.bg_hover or s.bg_panel)
    local thumbH = math.floor(w * 9 / 16)
    paintThumb(w, thumbH, card)
    local pad = paint.Px(20)
    local y = thumbH + pad
    paint.Rect(pad, y, paint.Px(64), paint.Px(48), s.bg_raised)
    paint.Outline(pad, y, paint.Px(64), paint.Px(48), card.mine and s.accent or s.border_strong, paint.Px(2))
    draw.SimpleText(card.badge, fontH2, pad + paint.Px(32), y + paint.Px(24), s.accent, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
    local nameX = pad + paint.Px(64) + paint.Px(14)
    draw.SimpleText(string.upper(card.modeName), fontH2, nameX, y + paint.Px(24), s.text, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(self._map, fontBody, pad, y + paint.Px(64), s.text_muted)
    local bottom = h - pad
    draw.SimpleText(tostring(card.votes), fontH1, pad, bottom, s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    surface.SetFont(fontH1)
    local countW = surface.GetTextSize(tostring(card.votes))
    draw.SimpleText(card.votes == 1 and "vote" or "votes", fontSmall, pad + countW + paint.Px(10), bottom - paint.Px(6),
        s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    if card.mine then paint.Badge("YOUR VOTE", fontSmall, w - pad, bottom - paint.Px(14), s.accent, s.on_accent) end
    if card.mine then
        paint.Outline(0, 0, w, h, s.accent, paint.Px(3))
    elseif focused then
        paint.Outline(0, 0, w, h, s.border_strong, paint.Px(2))
    else
        paint.Outline(0, 0, w, h, s.border)
    end
    return true
end

vgui.Register("PWVoteCard", cardClass, "PWButton")
