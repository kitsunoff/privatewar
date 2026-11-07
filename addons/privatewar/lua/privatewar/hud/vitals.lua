-- User-approved T-11.11: nickname above three 50-point armor segments above a simple health bar, bottom left.
HUDELEMENT.Order = 25
HUDELEMENT.Phases = { "LIVE" }

local hud = PW.HUD --[[@as PW.HudLib]]
-- The registry loads this shared file on the server too; only the client owns engine fonts.
local font = CLIENT and hud.Font ~= nil and hud.Font("vitals_name", 22, 500) or ""
local fallbackText, fallbackBack = Color(232, 237, 233), Color(11, 15, 12, 184)
local fallbackHealth, fallbackArmor = Color(91, 227, 125), Color(79, 195, 247)
local layout = hud._PlayerLayout(1920, 1080, {})
local segments = { 0, 0, 0 }
local lastName, lastWidth, lastHeight, label = "", 0, 0, ""

---@param token string
---@param fallback Color
---@return Color
local function colour(token, fallback)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    return ui ~= nil and (ui.Style --[[@as table<string, Color>]])[token] or fallback
end

---@param text string
---@return number
local function measure(text)
    local width = surface.GetTextSize(text)
    return width
end

---@param x number
---@param y number
---@param width number
---@param height number
---@param fraction number
---@param tint Color
local function bar(x, y, width, height, fraction, tint)
    surface.SetDrawColor(colour("bg_panel", fallbackBack))
    surface.DrawRect(x, y, width, height)
    surface.SetDrawColor(tint)
    surface.DrawRect(x, y, width * fraction, height)
end

function HUDELEMENT:ShouldDraw()
    return hud.PlayerVisible()
end

function HUDELEMENT:Draw()
    local ply = LocalPlayer()
    local w, h = ScrW(), ScrH()
    hud._PlayerLayout(w, h, layout)
    local name = ply:Nick()
    if name ~= lastName or w ~= lastWidth or h ~= lastHeight then
        lastName, lastWidth, lastHeight = name, w, h
        surface.SetFont(font)
        label = hud._FitText(name, layout.width, measure)
    end
    draw.SimpleText(label, font, layout.left, layout.nameY, colour("text", fallbackText), TEXT_ALIGN_LEFT)
    hud._ArmorSegments(ply:Armor(), segments)
    local width = (layout.width - 2 * layout.armorGap) / 3
    local armor = colour("team_friendly", fallbackArmor)
    for i = 1, 3 do
        bar(layout.left + (i - 1) * (width + layout.armorGap), layout.armorY, width, layout.armorHeight,
            segments[i], armor)
    end
    bar(layout.left, layout.healthY, layout.width, layout.healthHeight,
        hud._HealthFraction(ply:Health(), ply:GetMaxHealth()), colour("accent", fallbackHealth))
end
