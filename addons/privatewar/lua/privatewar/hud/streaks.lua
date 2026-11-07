-- Killstreaks (T-4.6; 05-loadout.md d.9): three squares on the right edge above the equipment lines, the cheapest
-- streak of the set at the bottom, and a progress bar to their left. The bar fills from the bottom as the counter
-- grows and reaches each square at its cost; after the last one it stays full (the counter does not loop). A square
-- is dim until earned, lit while held (with the key hint: the use key on the selected one, the next key on the others,
-- or the d-pad glyphs when Button hints is gamepad), highlighted while selected, and dim again once used. Above the
-- squares: the radar notice ("UAV ONLINE", "RADAR JAMMED") and a selected held streak that no square shows.
-- Pure rules: modules/hud/sh_streaks.lua. Values are the player's NW2 values (no traffic of its own); everything is
-- rebuilt only when one of them changes, so a frame allocates nothing.
HUDELEMENT.Order = 31
HUDELEMENT.Phases = { "LIVE" }

local hud = PW.HUD --[[@as PW.HudLib]]
local cfg = hud.Streaks

-- Fill speed of the bar (fraction of the gap per second, eased).
local fillRate = 8

local fallback = {
    bg_panel = Color(11, 15, 12, 184), bg_raised = Color(20, 27, 22, 217), border = Color(31, 42, 34),
    border_strong = Color(46, 61, 50), text = Color(232, 237, 233), text_muted = Color(138, 149, 141),
    text_disabled = Color(84, 93, 87), accent = Color(91, 227, 125), on_accent = Color(6, 32, 15)
}

---@class PW.HudStreaksCache
---@field progress integer
---@field inventory string
---@field set string
---@field selected integer
---@field radar string
---@field glyph string the d-pad glyph of the use action ("" for the keyboard keys)
---@field use string
---@field next string
---@field count integer
---@field squares PW.StreakSquare[]
---@field labels string[]
---@field costs string[]
---@field hints string[]
---@field held string[]
---@field lines string[]
---@field target number
---@field shown number
---@field view PW.StreakView
---@field keys PW.StreakHintKeys

---@type PW.HudStreaksCache
local cache = {
    progress = -1, inventory = "", set = "", selected = 0, radar = "", glyph = "", use = "", next = "", count = 0,
    squares = {}, labels = {}, costs = {}, hints = {}, held = {}, lines = {}, target = 0, shown = 0,
    view = { set = {}, progress = 0, inventory = {}, selected = 1 },
    keys = { hints = "keyboard", pad = false, use = "", next = "" }
}

---@type table<string, ConVar>
local keyVars = {}

---@param name string
---@return string
local function keyOf(name)
    local var = keyVars[name]
    if var == nil then
        var = GetConVar(name)
        if var == nil then return "?" end
        keyVars[name] = var
    end
    return var:GetString()
end

---The d-pad glyph of the use action when Button hints is gamepad and the d-pad is on, else "".
---@return string
local function glyph()
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    local pad = ui ~= nil and ui.Gamepad or nil
    if pad == nil or pad.HudGlyph == nil then return "" end
    return pad.HudGlyph("streak") or ""
end

---@param token string
---@return Color
local function colour(token)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    local style = ui ~= nil and ui.Style --[[@as table<string, Color>?]] or nil
    return style ~= nil and style[token] or fallback[token] or fallback.text
end

---@param id string
---@return string?
local function nameOf(id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries.streaks or nil
    local def = registry ~= nil and registry.Get(id) or nil
    if def == nil then return nil end
    return tostring((def --[[@as PW.Streak]]).Name)
end

---@type { label: string?, small: string? }
local fonts = {}

---Rebuilds the squares, their texts, the extra lines and the bar target for the cached inputs.
---@param lib PW.StreaksLib
---@param ply Player
local function rebuild(lib, ply)
    local view, keys = cache.view, cache.keys
    view.set, view.inventory, view.progress, view.selected = lib.Set(ply), lib.Inventory(ply), cache.progress,
        cache.selected
    keys.hints, keys.pad = cache.glyph ~= "" and "gamepad" or "keyboard", cache.glyph ~= ""
    keys.use, keys.next = cache.use, cache.next
    local count = hud._StreakSquares(view, cache.squares)
    cache.count = count
    for i = 1, count do
        local square = cache.squares[i] --[[@as PW.StreakSquare]]
        cache.labels[i] = hud._StreakShort(square.id, nameOf(square.id))
        cache.costs[i] = tostring(square.cost)
        cache.hints[i] = hud._StreakHint(square.state, keys)
        cache.held[i] = square.held > 1 and "x" .. square.held or ""
    end
    ---@type string[]
    local lines = {}
    local orphan = hud._StreakOrphan(cache.squares, count, view)
    if orphan ~= nil then
        lines[#lines + 1] = hud._StreakHint("selected", keys) .. " " .. string.upper(nameOf(orphan) or orphan)
    end
    if cache.radar ~= "" then lines[#lines + 1] = cache.radar end
    cache.lines = lines
    cache.target = hud._StreakFill(cache.squares, count, cache.progress, cfg)
end

---Reads the inputs; rebuilds when one changed. False when there is nothing to draw from.
---@return boolean
local function refresh()
    local ply = LocalPlayer()
    local lib = rawget(PW, "Streaks") --[[@as PW.StreaksLib?]]
    if lib == nil or not IsValid(ply) or lib.Blips == nil or lib.Jammed == nil then return false end
    local radar = lib.Jammed() and "RADAR JAMMED" or (#lib.Blips() > 0 and "UAV ONLINE" or "")
    local progress, inventory = ply:GetNW2Int(lib.ProgressKey, 0), ply:GetNW2String(lib.InventoryKey, "")
    local set, selected, pad = ply:GetNW2String(lib.SetKey, ""), lib.Selected or 1, glyph()
    local use, nextKey = keyOf(lib.Keys.use.convar), keyOf(lib.Keys.next.convar)
    if progress ~= cache.progress or inventory ~= cache.inventory or set ~= cache.set or selected ~= cache.selected
        or radar ~= cache.radar or pad ~= cache.glyph or use ~= cache.use or nextKey ~= cache.next then
        cache.progress, cache.inventory, cache.set, cache.selected = progress, inventory, set, selected
        cache.radar, cache.glyph, cache.use, cache.next = radar, pad, use, nextKey
        rebuild(lib, ply)
    end
    return true
end

---The bar left of the squares: track, fill from the bottom, a tick at each square's centre.
---@param x number left edge in pixels
---@param bottom number bottom edge in pixels
---@param size number square side in pixels
---@param gap number gap in pixels
local function drawBar(x, bottom, size, gap)
    local width, length = math.max(2, math.floor(hud.S(cfg.bar))), hud._StreakAnchor(cache.count, size, gap)
    surface.SetDrawColor(colour("bg_panel"))
    surface.DrawRect(x, math.floor(bottom - length), width, math.ceil(length))
    local filled = math.floor(length * cache.shown + 0.5)
    surface.SetDrawColor(colour("accent"))
    surface.DrawRect(x, bottom - filled, width, filled)
    for i = 1, cache.count do
        local at = math.floor(bottom - hud._StreakAnchor(i, size, gap))
        local reached = (cache.squares[i] --[[@as PW.StreakSquare]]).cost <= cache.progress
        surface.SetDrawColor(colour(reached and "text" or "text_muted"))
        surface.DrawRect(x - 3, at - 1, width + 6, 2)
    end
end

---One square: background and border by state, the short label, the cost, the copies held and the key hint.
---@param i integer
---@param x number left edge in pixels
---@param y number top edge in pixels
---@param size number
---@param hintX number right edge of the key hint in pixels
local function drawSquare(i, x, y, size, hintX)
    local state = (cache.squares[i] --[[@as PW.StreakSquare]]).state
    local held, selected = state == "ready" or state == "selected", state == "selected"
    surface.SetDrawColor(colour(selected and "accent" or (held and "bg_raised" or "bg_panel")))
    surface.DrawRect(x, y, size, size)
    surface.SetDrawColor(colour(selected and "text" or (held and "accent" or "border_strong")))
    surface.DrawOutlinedRect(x, y, size, size, held and 2 or 1)
    local ink = colour(selected and "on_accent" or (held and "text" or (state == "spent" and "text_muted"
        or "text_disabled")))
    local cx = x + size / 2
    draw.SimpleText(cache.labels[i], fonts.label, cx, y + size * 0.42, ink, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(cache.costs[i], fonts.small, cx, y + size - hud.S(4), ink, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    if cache.held[i] ~= "" then
        draw.SimpleText(cache.held[i], fonts.small, x + size - hud.S(4), y + hud.S(2), ink, TEXT_ALIGN_RIGHT,
            TEXT_ALIGN_TOP)
    end
    if cache.hints[i] ~= "" then
        draw.SimpleText(cache.hints[i], fonts.label, hintX, y + size / 2, colour(selected and "accent" or "text"),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
end

function HUDELEMENT:Draw()
    if not refresh() then return end
    fonts.label = fonts.label or (hud.Font --[[@as fun(id: string, size: number, weight?: number): string]])(
        "streak_label", 22, 700)
    fonts.small = fonts.small or (hud.Font --[[@as fun(id: string, size: number, weight?: number): string]])(
        "streak_small", 18, 600)
    cache.shown = cache.shown + (cache.target - cache.shown) * math.min(1, FrameTime() * fillRate)
    local size, gap = math.floor(hud.S(cfg.size)), math.floor(hud.S(cfg.gap))
    local right, bottom = math.floor((hud.X --[[@as fun(v: number): number]])(cfg.right)),
        math.floor((hud.Y --[[@as fun(v: number): number]])(cfg.bottom))
    local x = right - size
    local barX = x - math.floor(hud.S(cfg.barGap)) - math.max(2, math.floor(hud.S(cfg.bar)))
    if cache.count > 0 then drawBar(barX, bottom, size, gap) end
    for i = 1, cache.count do
        drawSquare(i, x, bottom - (i - 1) * (size + gap) - size, size, barX - hud.S(10))
    end
    local y = bottom - cache.count * (size + gap)
    for i = 1, #cache.lines do
        draw.SimpleText(cache.lines[i], fonts.small, right, y, colour(i == 1 and "accent" or "text"),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        y = y - hud.S(20)
    end
end
