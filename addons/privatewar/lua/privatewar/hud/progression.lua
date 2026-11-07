-- Progression (06-progression.md d.1, 09-hud.md d.2): a thin full-width XP bar along the bottom edge, the shown level
-- at its left end and the next one at its right end ("MAX" at the cap). The fill eases toward the local player's NW2
-- values and wraps through full on a level-up (modules/hud/sh_xpbar.lua). This element also watches the levels message
-- of the progression module (pw_progression_levels, owner only, sent after every level change): a higher level than the
-- previous message queues a LEVEL UP in the medal queue, drawn by hud/popups.lua. The first message after joining is
-- only the baseline, so the join upload never pops. A frame allocates nothing: labels are rebuilt only on a change.
HUDELEMENT.Order = 15
HUDELEMENT.Phases = { "PREMATCH", "LIVE", "POSTMATCH" }

local hud = PW.HUD --[[@as PW.HudLib]]

-- Design units (1920x1080). The bar sits below the vanilla health and ammo panels (they end near y 1053).
local labelWidth, barHeight, bottomGap = 64, 6, 10

local fallback = Color(255, 255, 255)
local fallbackBar = Color(255, 200, 60)
local fallbackBack = Color(0, 0, 0, 160)

---@type PW.XpBar
local bar = rawget(PW, "_HudXpBar") or hud._XpBarNew()
PW._HudXpBar = bar
---@type PW.LevelWatch
local watch = rawget(PW, "_HudLevelWatch") or hud._LevelWatchNew()
PW._HudLevelWatch = watch

local shown = { level = -1, capped = false, left = "", right = "" }
local lastTime = -1

---@param token string
---@param default Color
---@return Color
local function colour(token, default)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui == nil then return default end
    return (ui.Style --[[@as table<string, Color>]])[token] or default
end

---The medal queue of hud/popups.lua (created here when this element loads first).
---@return PW.MedalState
local function medalQueue()
    local medals = rawget(PW, "_HudMedals") --[[@as PW.MedalState?]]
    if medals == nil then
        medals = hud._MedalNew()
        PW._HudMedals = medals
    end
    return medals
end

---Feeds the latest levels message to the watch; queues a LEVEL UP when it reports a higher level.
---@param progression PW.ProgressionLib
---@param now number
local function watchLevels(progression, now)
    local cache = rawget(progression, "_Local") --[[@as PW.ProgressionLocal?]]
    local levels = cache ~= nil and cache.levels or nil
    if levels == nil then return end
    local level = hud._LevelWatch(watch, levels, levels.level, now)
    if level ~= nil then hud._LevelUpAdd(medalQueue(), level) end
end

---@param capped boolean the target level is the cap and the bar shows it
local function refreshLabels(capped)
    local level = bar.level or 1
    if level == shown.level and capped == shown.capped then return end
    shown.level, shown.capped = level, capped
    shown.left = tostring(level)
    shown.right = capped and "MAX" or tostring(level + 1)
end

local function drawBar()
    local width, height = ScrW(), ScrH()
    local thickness = math.max(2, math.floor(hud.Y(barHeight)))
    local y = height - math.floor(hud.Y(bottomGap)) - thickness
    local labelW = hud.X(labelWidth)
    local left, length = labelW, width - 2 * labelW
    surface.SetDrawColor(colour("bg_panel", fallbackBack))
    surface.DrawRect(left, y, length, thickness)
    surface.SetDrawColor(colour("accent", fallbackBar))
    surface.DrawRect(left, y, math.floor(length * bar.fill + 0.5), thickness)
    local font = (hud.Font --[[@as fun(id: string, size: number, weight?: number): string]])("xpbar_level", 24, 800)
    local middle = y + thickness / 2
    local tint = colour("text", fallback)
    draw.SimpleText(shown.left, font, labelW / 2, middle, tint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(shown.right, font, width - labelW / 2, middle, tint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function HUDELEMENT:Draw()
    local ply = LocalPlayer()
    local progression = rawget(PW, "Progression") --[[@as PW.ProgressionLib?]]
    if not IsValid(ply) or progression == nil then return end
    local now = RealTime()
    local dt = lastTime < 0 and 0 or math.min(now - lastTime, 0.1)
    lastTime = now
    watchLevels(progression, CurTime())
    local level = progression.GetLevel(ply)
    local into, need = progression.GetProgress(ply)
    hud._XpBarStep(bar, level, progression._Fraction(into, need), dt, hud._XpBarAnimate(watch, CurTime()))
    refreshLabels(need <= 0 and bar.level == level)
    drawBar()
end
