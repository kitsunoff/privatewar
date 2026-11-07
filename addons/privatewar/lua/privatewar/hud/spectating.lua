-- Spectating notice (T-8.4; 08-lobby.md d.4): "Spectating - you join next match" at the bottom centre while the
-- server holds the local player out of the match (lobby.joininprogress off, joined during LIVE). The flag is the NW2
-- bool of the player (PW.Jip.NetBool), so the element causes no network traffic.
HUDELEMENT.Order = 30

local hud = PW.HUD --[[@as PW.HudLib]]

local fallback = Color(255, 255, 255)
local centreY, pad = 940, 18

---@param token string
---@return Color
local function colour(token)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui == nil then return fallback end
    return (ui.Style --[[@as table<string, Color>]])[token] or fallback
end

---@return string
local function fontName()
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui ~= nil then return ui.FontName("h2") end
    return (hud.Font --[[@as fun(id: string, size: number, weight?: number): string]])("spectating", 30, 700)
end

---@return boolean
function HUDELEMENT:ShouldDraw()
    local jip = rawget(PW, "Jip") --[[@as PW.JipLib?]]
    local me = LocalPlayer()
    return jip ~= nil and IsValid(me) and me:GetNW2Bool(jip.NetBool, false)
end

function HUDELEMENT:Draw()
    local jip = rawget(PW, "Jip") --[[@as PW.JipLib]]
    local font = fontName()
    surface.SetFont(font)
    local w, h = surface.GetTextSize(jip.Notice)
    local padding = hud.S(pad)
    local x, y = ScrW() / 2, hud.Y(centreY)
    local back = colour("bg_panel")
    draw.RoundedBox(0, x - w / 2 - padding, y - h / 2 - padding / 2, w + 2 * padding, h + padding, back)
    draw.SimpleText(jip.Notice, font, x, y, colour("text"), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
