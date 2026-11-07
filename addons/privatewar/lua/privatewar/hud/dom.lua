-- Domination points (T-6.5; 09-hud.md d.2): a row of letter tiles at the top centre (match status: top left), drawn
-- only while the Domination flags exist. A tile shows the owner colour (friendly, enemy, neutral), a bar under it fills
-- with the capture progress in the colour of the side that is gaining, a contested point pulses a warning outline, and
-- the point the local player stands in gets an accent outline. Everything comes from data the client already has (the
-- flag network vars and the player's own position): no hidden enemy positions. The rules are pure
-- (modules/dom_flags/sh_hud.lua); this file reads the engine and draws. A frame allocates nothing.
HUDELEMENT.Order = 12
HUDELEMENT.Phases = { "LIVE" }

local hud = PW.HUD --[[@as PW.HudLib]]
local flagsLib = PW.DomFlags --[[@as PW.DomFlagsLib]]
local config = flagsLib.Hud

local fallback = Color(255, 255, 255)

---@type PW.DomFlagView
local view = { letter = "", value = 0, owner = 0, contested = false }
---@type PW.DomFlagDisplay[]
local displays = {}
---@type boolean[]
local inside = {}
local font = ""

---@param token string
---@return Color
local function colour(token)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui == nil then return fallback end
    return (ui.Style --[[@as table<string, Color>]])[token] or fallback
end

---@param token string
---@param alpha number 0..1
local function setColour(token, alpha)
    local c = colour(token)
    surface.SetDrawColor(c.r, c.g, c.b, c.a * alpha)
end

function HUDELEMENT:ShouldDraw()
    return flagsLib._Visible(#flagsLib._Flags)
end

---Fills displays (sorted by letter) and inside for the flags the client knows; returns their count.
---@param me Player
---@return integer
local function collect(me)
    local team, pos = me:Team(), me:GetPos()
    local alive = me:Alive()
    local count = 0
    for _, ent in ipairs(flagsLib._Flags) do
        if IsValid(ent) then
            count = count + 1
            view.letter, view.value, view.owner, view.contested =
                ent:GetLetter(), ent:GetValue(), ent:GetOwnerTeam(), ent:GetContested()
            local display = displays[count]
            if display == nil then
                display = flagsLib._NewDisplay()
                displays[count] = display
            end
            flagsLib._Display(view, team, display)
            inside[count] = alive and flagsLib._Inside(ent:GetPos(), pos)
        end
    end
    flagsLib._OrderDisplays(displays, count)
    return count
end

---@param display PW.DomFlagDisplay
---@param x number
---@param y number
---@param size number
local function drawTile(display, x, y, size)
    local radius = hud.S(8)
    local c = colour(display.token)
    local owned = display.relation ~= "neutral"
    local inner = size - hud.S(6)
    draw.RoundedBox(radius, x, y, size, size, colour("bg_panel"))
    surface.SetDrawColor(c.r, c.g, c.b, owned and 80 or 25)
    surface.DrawRect(x + hud.S(3), y + hud.S(3), inner, inner)
    draw.SimpleText(display.letter, font, x + size / 2, y + size / 2, owned and c or colour("text"),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

---@param display PW.DomFlagDisplay
---@param x number
---@param y number
---@param size number
local function drawProgress(display, x, y, size)
    local height = hud.S(config.bar)
    surface.SetDrawColor(0, 0, 0, 140)
    surface.DrawRect(x, y, size, height)
    if display.progress <= 0 then return end
    setColour(display.leanToken, display.capturing and 1 or 0.55)
    surface.DrawRect(x, y, size * display.progress, height)
end

---@param display PW.DomFlagDisplay
---@param here boolean the local player stands in this point
---@param x number
---@param y number
---@param size number
local function drawOutline(display, here, x, y, size)
    local thick = math.max(1, math.floor(hud.S(2)))
    if display.contested then
        local pulse = 0.5 + 0.5 * math.sin(CurTime() * 8)
        setColour("warning", 0.4 + 0.6 * pulse)
        surface.DrawOutlinedRect(x - thick, y - thick, size + 2 * thick, size + 2 * thick, thick)
    end
    if here then
        setColour("accent", 1)
        surface.DrawOutlinedRect(x, y, size, size, thick + 1)
    end
end

function HUDELEMENT:Draw()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local count = collect(me)
    if count == 0 then return end
    if font == "" then font = hud.Font("dom_letter", 30, 800) end
    local size, gap = hud.S(config.tile), hud.S(config.gap)
    local total = count * size + (count - 1) * gap
    local x, y = hud.X(960) - total / 2, hud.Y(config.top)
    for i = 1, count do
        local display = displays[i] --[[@as PW.DomFlagDisplay]]
        drawTile(display, x, y, size)
        drawProgress(display, x, y + size + hud.S(3), size)
        drawOutline(display, inside[i] == true, x, y, size)
        x = x + size + gap
    end
end
