-- Minimal S&D objective HUD. Static sites are public; bomb markers come only from the approved recipient snapshot.
HUDELEMENT.Order = 13
HUDELEMENT.Phases = { "LIVE" }
local hud = PW.HUD --[[@as PW.HudLib]]
local white, gold, background = Color(245, 245, 240), Color(255, 210, 100), Color(12, 16, 20, 210)
local font = ""

function HUDELEMENT:ShouldDraw()
    return PW.SND ~= nil and PW.SND.Display ~= nil and PW.SND.Display() ~= nil
end

---@param item PW.SNDMarker
local function marker(item)
    if not item.visible then return end
    draw.SimpleTextOutlined(item.text, font, item.x, item.y, gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
        1, background)
end

function HUDELEMENT:Draw()
    local view = assert(PW.SND).Display()
    if view == nil then return end
    if font == "" then font = hud.Font("snd_objective", 24, 700) end
    local x, y, width = hud.X(960), hud.Y(100), hud.S(470)
    draw.RoundedBox(hud.S(4), x - width / 2, y, width, hud.S(68), background)
    draw.SimpleText(view.title, font, x, y + hud.S(16), white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(view.line, font, x, y + hud.S(46), gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    if view.progress > 0 then
        surface.SetDrawColor(gold)
        surface.DrawRect(x - width / 2, y + hud.S(65), width * view.progress, hud.S(3))
    end
    for _, item in ipairs(view.markers) do marker(item) end
end
