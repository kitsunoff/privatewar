-- Match status (U-8, T-6.2, T-11.5; 09-hud.md d.2 and revision 2026-11-07 item 3): at the top left under the radar,
-- one horizontal bar per team in the team colour (own team on top), filled by score / score limit with an eased fill,
-- the score next to it and a semi-transparent L outline marking the full length (the limit); FFA shows you and the
-- leader, or you and second place when you lead. The local timer sits right of the bars. The POSTMATCH banner stays
-- centred; the PREMATCH countdown is the lobby's START button (lobby_ui sh_flow.lua). Everything is read from NW2
-- and counted locally, so the element causes no network traffic. The decisions are pure (modules/hud/sh_status.lua,
-- sh_scorebars.lua); this file only reads the engine and draws. A frame allocates nothing: strings are rebuilt once
-- per second or score change, the row, layout and rectangle tables are reused, colours and fonts are cached.
HUDELEMENT.Order = 10
HUDELEMENT.Phases = { "PREMATCH", "LIVE", "POSTMATCH" }

local hud = PW.HUD --[[@as PW.HudLib]]
local rules = PW.MatchRules --[[@as PW.MatchRulesLib]]

local config = hud.ScoreBars

-- Design units (1920x1080): the centred phase messages; the bar block is laid out by PW.HUD._ScoreLayout.
local messageY = 330
local panelPad = 8

local fallback = Color(255, 255, 255)
local fallbackMuted = Color(180, 180, 180)

---@class PW.HudStatusCache
---@field scores number[] per team (or per player in FFA), refilled every frame
---@field timerSecond integer
---@field timerText string
---@field shown number[] per row slot: the score whose text is cached
---@field texts string[] per row slot: the score text
---@field eased number[] per row slot: the eased fill fraction
---@field keyPrefix string
---@field keys string[] key prefix .. index, built once per prefix
local cache = {
    scores = {}, timerSecond = -1, timerText = "", shown = {}, texts = {}, eased = {},
    keyPrefix = "", keys = {}
}

---@type PW.ScoreRow[]
local rows = {}
---@type PW.ScoreLayout
local layout = hud._ScoreLayout(1920, 1080, 1, true, {})
---@type PW.ScoreBarRects
local rects = hud._ScoreBarRects(layout, 1, 0, {})

local banners = {
    victory = { text = "VICTORY", token = "positive" },
    defeat = { text = "DEFEAT", token = "negative" },
    draw = { text = "DRAW", token = "text" },
    over = { text = "MATCH OVER", token = "text" }
}

---@param token string
---@param default Color
---@return Color
local function colour(token, default)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui == nil then return default end
    return (ui.Style --[[@as table<string, Color>]])[token] or default
end

---@param step string font ladder id
---@param size number design units, used when the kit is missing
---@return string
local function fontOf(step, size)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui ~= nil then return ui.FontName(step) end
    return (hud.Font --[[@as fun(id: string, size: number, weight?: number): string]])("status_" .. step, size, 700)
end

---Name of the NW2 global of a team's score; the strings are built once per prefix.
---@param prefix string
---@param index integer
---@return string
local function keyOf(prefix, index)
    if cache.keyPrefix ~= prefix then cache.keyPrefix, cache.keys = prefix, {} end
    local key = cache.keys[index]
    if key == nil then
        key = prefix .. index
        cache.keys[index] = key
    end
    return key
end

---Fills cache.scores with the team scores 1..count; returns the count and the local entry.
---@param count integer
---@param ply Player
---@return integer, integer?
local function teamScores(count, ply)
    local prefix = GetGlobal2String(rules._ScoreKeyKey, rules._TeamKillsKey)
    for i = 1, count do cache.scores[i] = GetGlobal2Int(keyOf(prefix, i), 0) end
    local own = ply:Team()
    if own < 1 or own > count then return count, nil end
    return count, own
end

---Fills cache.scores with the players' frags; returns the count and the local index.
---@param ply Player
---@return integer, integer?
local function ffaScores(ply)
    ---@type integer
    local count = 0
    ---@type integer
    local own = 0
    -- player.Iterator allocates nothing, unlike player.GetAll.
    ---@type fun(): (fun(): integer?, Player?)
    local iterator = player.Iterator
    for _, other in iterator() do
        local entry = other --[[@as Player]]
        count = count + 1
        cache.scores[count] = rules.GetKills(entry)
        if entry == ply then own = count --[[@as integer]] end
    end
    if own == 0 then return count, nil end
    return count, own
end

---@return integer teams the team count of this match, 0 for FFA, -1 when unknown
local function teamCount(phase)
    if phase == "POSTMATCH" then return GetGlobal2Int(rules._ResultTeamsKey, 0) end
    -- The teams module count is published at LIVE only: 0 in the first PREMATCH.
    if phase == "LIVE" then return GetGlobal2Int("pw_teams", 0) end
    return -1
end

---@param text string
---@param font string
---@param x number
---@param y number
---@param tint Color
local function centred(text, font, x, y, tint)
    draw.SimpleText(text, font, x, y, tint, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

---@param tint Color
---@param alpha number 0..1
local function setColour(tint, alpha)
    surface.SetDrawColor(tint.r, tint.g, tint.b, tint.a * alpha)
end

---Score text of a row slot, rebuilt only when the score changed.
---@param slot integer
---@param score number
---@return string
local function scoreText(slot, score)
    if cache.shown[slot] ~= score then cache.shown[slot], cache.texts[slot] = score, tostring(score) end
    return cache.texts[slot] --[[@as string]]
end

---One row: the L outline, the eased fill and the number; without a limit only the number.
---@param slot integer
---@param row PW.ScoreRow
---@param font string
local function drawRow(slot, row, font)
    local tint = colour(row.own and "team_friendly" or "team_enemy", fallback)
    local numberY = layout.top + (slot - 0.5) * layout.pitch
    local target = row.fraction
    if target ~= nil then
        local eased = hud._ScoreEase(cache.eased[slot] or 0, target, RealFrameTime(), config.ease)
        cache.eased[slot] = eased
        hud._ScoreBarRects(layout, slot, eased, rects)
        setColour(tint, config.outline)
        surface.DrawRect(rects.lineX, rects.lineY, rects.lineW, rects.lineH)
        surface.DrawRect(rects.tickX, rects.tickY, rects.tickW, rects.tickH)
        setColour(tint, 1)
        surface.DrawRect(rects.fillX, rects.fillY, rects.fillW, rects.fillH)
        numberY = rects.numberY
    end
    draw.SimpleText(scoreText(slot, row.score), font, layout.numberX, numberY, tint, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
end

---Fills the rows of this frame and the layout; returns the row count (0: nothing to show).
---@param phase PW.PhaseName
---@param ply Player
---@return integer
local function collectRows(phase, ply)
    local teams = teamCount(phase)
    local limit = GetGlobal2Int(rules._LimitKey, 0)
    ---@type integer
    local n = 0
    if teams >= 0 then
        local count, own = ffaScores(ply)
        if teams > 0 then count, own = teamScores(teams, ply) end
        n = hud._ScoreRows(cache.scores, count, own, teams == 0, limit, rows)
    end
    hud._ScoreLayout(ScrW(), ScrH(), n, limit > 0, layout)
    return n
end

---@param n integer
local function drawBars(n)
    local pad = hud.S(panelPad)
    draw.RoundedBox(hud.S(6), layout.x - pad, layout.top - pad, layout.right - layout.x + 2 * pad,
        layout.bottom - layout.top + 2 * pad, colour("bg_panel", fallbackMuted))
    local font = fontOf("body", 26)
    for slot = 1, n do drawRow(slot, rows[slot] --[[@as PW.ScoreRow]], font) end
    for slot = n + 1, config.maxRows do cache.eased[slot] = nil end
end

---@param phase PW.PhaseName
local function drawTimer(phase)
    local ends = hud._TimerEnd(phase, GetGlobal2Float("pw_phase_end", -1), GetGlobal2Float(rules._EndsKey, -1))
    local left = hud._Remaining(ends, CurTime())
    if left == nil then return end
    local second = math.ceil(left)
    if second ~= cache.timerSecond then cache.timerSecond, cache.timerText = second, hud._FormatTime(left) end
    draw.SimpleText(cache.timerText, fontOf("h2", 32), layout.timerX, layout.timerY, colour("text", fallback),
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

---@param ply Player
local function drawBanner(ply)
    local kind = hud._Verdict(GetGlobal2Bool(rules._ResultDrawKey, false), GetGlobal2Int(rules._ResultWinnerKey, 0),
        GetGlobal2Int(rules._ResultTeamsKey, 0), ply:Team(), ply:UserID())
    local banner = banners[kind or "over"] or banners.over
    centred(banner.text, fontOf("title", 64), hud.X(960), hud.Y(messageY), colour(banner.token, fallback))
end

function HUDELEMENT:Draw()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local phase = PW.Phase.GetPhase()
    -- PREMATCH: the lobby stays open and its START button counts down (lobby_ui sh_flow.lua); no HUD message.
    if phase == "PREMATCH" then return end
    local n = collectRows(phase, ply)
    if n > 0 then drawBars(n) end
    drawTimer(phase)
    if phase == "POSTMATCH" then drawBanner(ply) end
end
