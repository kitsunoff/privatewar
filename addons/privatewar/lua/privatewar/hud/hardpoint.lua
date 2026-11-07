-- One active-zone marker and two labelled clocks; no preview, hidden occupants or additional paint hook.
HUDELEMENT.Order = 12
HUDELEMENT.Phases = { "LIVE" }
local hp = assert(PW.Hardpoint)
local hud = assert(PW.HUD)
local neutral = Color(232, 237, 233)
local background = Color(11, 15, 12, 220)
local warning = Color(255, 181, 71)
local view = { zoneId = "", zoneRemaining = 0, matchRemaining = 0 }
local title, clock = "", ""
local label, zoneClock, matchClock = "", "", ""
local shownSecond, shownMatch, shownRevision = -1, -1, -1

---@param text string
---@return number
local function measure(text)
    surface.SetFont(title)
    local width = surface.GetTextSize(text)
    return width
end

-- Refresh strings and fonts outside HUDPaint; drawing below allocates no tables or formatted text.
PW.HookFor(HUDELEMENT, "Think", function()
    local snapshot = hp.ClientSnapshot
    if snapshot == nil or not snapshot.active or PW.Phase.GetPhase() ~= "LIVE" then return end
    hp.View(snapshot, CurTime(), view)
    local second, match = math.ceil(view.zoneRemaining), math.ceil(view.matchRemaining)
    if title == "" then
        title, clock = hud.Font("hp_title", 26, 800), hud.Font("hp_clock", 22, 600)
    end
    if second ~= shownSecond or match ~= shownMatch or snapshot.revision ~= shownRevision then
        label = hud._FitText("HARDPOINT  " .. view.zoneId, hud.S(408), measure)
        zoneClock = "ZONE  " .. hud._FormatTime(view.zoneRemaining)
        matchClock = "MATCH  " .. hud._FormatTime(view.matchRemaining)
        shownSecond, shownMatch, shownRevision = second, match, snapshot.revision
    end
end)

function HUDELEMENT:ShouldDraw()
    local snapshot = hp.ClientSnapshot
    return IsValid(PW.Modules.Get("hardpoint")) and snapshot ~= nil and snapshot.active
end

function HUDELEMENT:Draw()
    local snapshot = hp.ClientSnapshot
    if snapshot == nil or title == "" then return end
    local style = PW.UI ~= nil and PW.UI.Style or nil
    local textColor = style ~= nil and style.text or neutral
    local panelColor = style ~= nil and style.bg_panel or background
    local contestColor = style ~= nil and style.warning or warning
    local x, y, width, height = hud.X(960), hud.Y(24), hud.S(440), hud.S(92)
    draw.RoundedBox(hud.S(6), x - width / 2, y, width, height, panelColor)
    local color = snapshot.contested and contestColor
        or snapshot.control > 0 and team.GetColor(snapshot.control) or textColor
    draw.SimpleText(label, title, x, y + hud.S(20), color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(zoneClock, clock, x - hud.S(100), y + hud.S(57), textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(matchClock, clock, x + hud.S(100), y + hud.S(57), textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
