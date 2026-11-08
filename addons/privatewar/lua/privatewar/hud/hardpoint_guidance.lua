-- Public active-zone waypoint, drawn by the one HUD loop: no depth test and no world-visibility trace.
HUDELEMENT.Order = 14
HUDELEMENT.Phases = { "LIVE" }
local hp, hud = assert(PW.Hardpoint), assert(PW.HUD)
local guidance = { visible = false, zoneId = "", action = "", token = "text", distance = 0 }
local point = { x = 0, y = 0, angle = 0, edge = false, visible = false }
local arrow = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local turns = { 0, 2.5, -2.5 }
local neutral, background = Color(232, 237, 233), Color(11, 15, 12, 225)
---@type table<string, Color>
local colors = { text = neutral, warning = Color(255, 181, 71),
    team_friendly = Color(79, 195, 247), team_enemy = Color(255, 77, 77) }
if CLIENT then
    language.Add("pw.hp.capture", "CAPTURE")
    language.Add("pw.hp.defend", "DEFEND")
    language.Add("pw.hp.contested", "CONTESTED")
    language.Add("pw.hp.distance", "%d m")
end
local font, label, detail = "", "", ""
local cachedId, cachedAction, cachedDistance, cachedWidth = "", "", -1, -1
local shownRevision, shownPlayer = -1, NULL
local width, height, gap, radius = 0, 0, 0, 0

---@return boolean
local function correctMode()
    return GetGlobal2String(assert(PW.MatchRules)._ScoreKeyKey, "") == "pw_hp_score_"
end

---@param text string
---@return number
local function measure(text)
    surface.SetFont(font)
    local measured = surface.GetTextSize(text)
    return measured
end

-- All projection, text formatting and polygon mutation happens outside HUDPaint; tables/fonts/colors are reused.
PW.HookFor(HUDELEMENT, "Think", function()
    if not CLIENT then return end -- The shared kind registers on the server; projection/localization is client-only.
    local me, snapshot = LocalPlayer(), hp.ClientSnapshot
    local valid = IsValid(me)
    local offset = snapshot ~= nil and valid and snapshot.zone.pos - EyePos() or vector_origin
    hp.Guidance(snapshot, PW.Phase.GetPhase(), correctMode() and "hardpoint" or nil,
        hud.PlayerVisible ~= nil and hud.PlayerVisible(), valid and me:Team() or 0, offset:Length(), guidance)
    point.visible = false
    if not guidance.visible then return end
    local angle = EyeAngles()
    hp.ProjectWaypoint(offset:Dot(angle:Right()), offset:Dot(angle:Up()), offset:Dot(angle:Forward()),
        me:GetFOV(), ScrW(), ScrH(), point)
    if font == "" then font = hud.Font("hp_guidance", 24, 800) end
    width, height, gap, radius = hud.S(260), hud.S(66), hud.S(30), hud.S(12)
    if guidance.zoneId ~= cachedId or guidance.action ~= cachedAction or guidance.distance ~= cachedDistance
        or width ~= cachedWidth then
        label = hud._FitText(language.GetPhrase("pw.hp." .. guidance.action) .. "  " .. guidance.zoneId,
            width - hud.S(20), measure)
        detail = string.format(language.GetPhrase("pw.hp.distance"), guidance.distance)
        cachedId, cachedAction, cachedDistance, cachedWidth = guidance.zoneId, guidance.action, guidance.distance, width
    end
    local a = math.rad(point.edge and point.angle or -90)
    for index, turn in ipairs(turns) do
        arrow[index].x = point.x + math.cos(a + turn) * radius
        arrow[index].y = point.y + math.sin(a + turn) * radius
    end
    shownRevision, shownPlayer = assert(snapshot).revision, me
end)

function HUDELEMENT:ShouldDraw()
    local snapshot = hp.ClientSnapshot
    return guidance.visible and point.visible and correctMode() and hud.PlayerVisible ~= nil and hud.PlayerVisible()
        and IsValid(PW.Modules.Get("hardpoint")) and snapshot ~= nil and snapshot.active
        and snapshot.revision == shownRevision and LocalPlayer() == shownPlayer
end

function HUDELEMENT:Draw()
    local style = PW.UI ~= nil and PW.UI.Style or nil
    local palette = (style or colors) --[[@as table<string, Color>]]
    local color = palette[guidance.token] or neutral
    local y = point.y + gap
    draw.RoundedBox(hud.S(5), point.x - width * 0.5, y, width, height, background)
    draw.NoTexture()
    surface.SetDrawColor(color)
    surface.DrawPoly(arrow)
    draw.SimpleText(label, font, point.x, y + height * 0.27, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(detail, font, point.x, y + height * 0.72, neutral, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
