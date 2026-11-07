-- Score popups and medals (T-6.4; 09-hud.md d.2). The server sends one "pw_score_popup" message (event id, points) to
-- the owner of every award. An event with Medal = true that the medals module announces goes to the medal queue
-- (large, one after another, a stock sound); every other event is a small "+100 Kill" popup near the crosshair that
-- merges with the same event and fades. The rules are pure (modules/hud/sh_popups.lua); this file receives the
-- message and draws. The pw_medal message is not used here: pw_score_popup already carries every medal.
-- The LEVEL UP popup shares the medal queue (so it never overlaps a medal): hud/progression.lua queues it, this file
-- draws it larger, with a pop-in scale and its own sound. POSTMATCH is drawn too, so a level-up from the last award of
-- a match shows before the match ends instead of waiting for the next one.
HUDELEMENT.Order = 30
HUDELEMENT.Phases = { "LIVE", "POSTMATCH" }

local hud = PW.HUD --[[@as PW.HudLib]]

local fallback = Color(255, 255, 255)
local shadow = Color(0, 0, 0)
local medalSound = "buttons/bell1.wav"
local levelUpSound = "items/suitchargeok1.wav"

-- Design units (1920x1080): popups start right of and below the crosshair, medals sit above it.
local popupX, popupY, popupStep = 36, 40, 34
local medalY = 300
local levelUpY = 250

-- Reused every frame for the pop-in scale (no allocation in HUDPaint).
local levelUpMatrix = Matrix()
local levelUpOffset = Vector(0, 0, 0)
local levelUpScale = Vector(1, 1, 1)
---@type PW.LevelUpFacts
local levelUpFacts = { width = 0, height = 0, scale = 1, anchorY = 0, titleW = 0, titleH = 0, labelW = 0, labelH = 0 }
---@type PW.LevelUpLayout
local levelUpLayout = { cx = 0, cy = 0, titleY = 0, labelY = 0, boxX = 0, boxY = 0, boxW = 0, boxH = 0 }

---@type PW.PopupState
local popups = rawget(PW, "_HudPopups") or hud._PopupNew()
PW._HudPopups = popups
---@type PW.MedalState
local medals = rawget(PW, "_HudMedals") or hud._MedalNew() -- shared with hud/progression.lua (LEVEL UP)
PW._HudMedals = medals

---@param token string
---@return Color
local function colour(token)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui == nil then return fallback end
    return (ui.Style --[[@as table<string, Color>]])[token] or fallback
end

---@param step string font ladder id
---@param size number design units, used when the kit is missing
---@return string
local function fontOf(step, size)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui ~= nil then return ui.FontName(step) end
    return (hud.Font --[[@as fun(id: string, size: number, weight?: number): string]])("popup_" .. step, size, 700)
end

---@param id string
---@return PW.ScoreEvent?
local function eventOf(id)
    local registries = PW.Registries
    local registry = registries ~= nil and registries.score_events or nil
    if registry == nil then return nil end
    local event = registry.Get(id)
    if event == nil or not event:IsValid() then return nil end
    return event --[[@as PW.ScoreEvent]]
end

---@param id string
---@param points number
local function receive(id, points)
    local event = eventOf(id)
    local text = hud._PopupText(event ~= nil and event.Name or nil, id, language.GetPhrase)
    local ids = PW.Medals ~= nil and PW.Medals.Ids or {}
    local now = CurTime()
    if hud._PopupKind(event ~= nil and event.Medal or nil, id, ids) == "medal" then
        hud._MedalAdd(medals, id, text, points, now)
    else
        hud._PopupAdd(popups, id, text, points, now)
    end
end

net.Receive("pw_score_popup", function()
    local id = net.ReadString()
    receive(id, net.ReadUInt(16))
end)

---Text with a one-pixel shadow so it reads on any background.
---@param text string
---@param font string
---@param x number
---@param y number
---@param tint Color
---@param alpha number 0..1
---@param align integer TEXT_ALIGN_*
local function drawText(text, font, x, y, tint, alpha, align)
    draw.SimpleText(text, font, x + 1, y + 1, ColorAlpha(shadow, 200 * alpha), align, TEXT_ALIGN_TOP)
    draw.SimpleText(text, font, x, y, ColorAlpha(tint, 255 * alpha), align, TEXT_ALIGN_TOP)
end

local function drawPopups(now)
    hud._PopupPrune(popups, now)
    local font = fontOf("body", 26)
    local tint = colour("text")
    local x, y = ScrW() / 2 + hud.S(popupX), ScrH() / 2 + hud.S(popupY)
    for i = 1, popups.count do
        local entry = popups.list[i]
        if entry ~= nil then
            drawText(entry.label, font, x, y + (i - 1) * hud.S(popupStep), tint,
                hud._PopupAlpha(now - entry.at), TEXT_ALIGN_LEFT)
        end
    end
end

---LEVEL UP: large title and the new level, centred in the upper middle, scaled around its centre while it pops in.
---The text is drawn at its unscaled screen position and the matrix scales around the layout centre: the surface clip
---rect applies before the model matrix, so text drawn around (0, 0) lost its left half and its top (the clipped
---popup). The layout (PW.HUD._LevelUpLayout) keeps the max-scale box on screen.
---@param medal PW.MedalPopup
---@param age number
local function drawLevelUp(medal, age)
    local alpha, scale = hud._MedalAlpha(age), hud._LevelUpScale(age)
    local titleFont, labelFont = fontOf("title", 64), fontOf("h2", 32)
    surface.SetFont(titleFont)
    levelUpFacts.titleW, levelUpFacts.titleH = surface.GetTextSize(medal.name)
    surface.SetFont(labelFont)
    levelUpFacts.labelW, levelUpFacts.labelH = surface.GetTextSize(medal.label)
    levelUpFacts.width, levelUpFacts.height = ScrW(), ScrH()
    levelUpFacts.scale, levelUpFacts.anchorY = hud.S(1), hud.Y(levelUpY)
    local layout = hud._LevelUpLayout(levelUpFacts, levelUpLayout)
    levelUpOffset:SetUnpacked(layout.cx, layout.cy, 0)
    levelUpScale:SetUnpacked(scale, scale, 1)
    levelUpMatrix:Identity()
    levelUpMatrix:Translate(levelUpOffset)
    levelUpMatrix:Scale(levelUpScale)
    levelUpOffset:SetUnpacked(-layout.cx, -layout.cy, 0)
    levelUpMatrix:Translate(levelUpOffset)
    local clipping = DisableClipping(true)
    cam.PushModelMatrix(levelUpMatrix, true)
    render.PushFilterMag(TEXFILTER.ANISOTROPIC)
    render.PushFilterMin(TEXFILTER.ANISOTROPIC)
    drawText(medal.name, titleFont, layout.cx, layout.titleY, colour("accent"), alpha, TEXT_ALIGN_CENTER)
    drawText(medal.label, labelFont, layout.cx, layout.labelY, colour("text"), alpha, TEXT_ALIGN_CENTER)
    render.PopFilterMin()
    render.PopFilterMag()
    cam.PopModelMatrix()
    DisableClipping(clipping)
end

---@param now number
local function drawMedal(now)
    local medal = hud._MedalCurrent(medals, now)
    if medal == nil then return end
    local levelUp = medal.kind == "levelup"
    if not medal.played then
        medal.played = true
        surface.PlaySound(levelUp and levelUpSound or medalSound)
    end
    local age = now - (medal.startedAt or now)
    if levelUp then
        drawLevelUp(medal, age)
        return
    end
    local alpha = hud._MedalAlpha(age)
    local x, y = ScrW() / 2, hud.Y(medalY)
    drawText(medal.name, fontOf("h1", 44), x, y, colour("warning"), alpha, TEXT_ALIGN_CENTER)
    drawText(medal.label, fontOf("h2", 32), x, y + hud.S(54), colour("text"), alpha, TEXT_ALIGN_CENTER)
end

function HUDELEMENT:Draw()
    local now = CurTime()
    drawPopups(now)
    drawMedal(now)
end
