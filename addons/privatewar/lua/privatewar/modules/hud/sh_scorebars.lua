-- Pure rules of the score bars of the match status element (T-11.5; 09-hud.md revision 2026-11-07 item 3): which rows
-- are shown in which order (own team first; FFA you and the leader, or you and second place when you lead), the fill
-- fraction against the score limit, the eased fill, the layout under the radar and the bar and L-outline rectangles.
-- Shared, plain data in and out, so the server-side test runner covers it; the drawing is hud/match_status.lua.
-- Loaded by shared.lua through include, after sh_radar.lua (the layout reads PW.HUD.Radar). Nothing here allocates:
-- every function fills a table the caller reuses.

local lib = PW.HUD --[[@as PW.HudLib]]

-- Design units (1920x1080) unless noted.
lib.ScoreBars = {
    -- Space between the radar disc and the first row.
    gap = 16,
    -- Full bar length (the score limit); the radar diameter, so the block lines up with the disc.
    width = 220,
    -- Bar thickness and row pitch.
    bar = 12,
    pitch = 30,
    -- The L outline: line thickness and how far the end tick rises above the bar.
    line = 2,
    tick = 4,
    -- Opacity of the outline (0..1).
    outline = 0.35,
    -- Score number: space after the bar and the room it takes; then the timer.
    numberGap = 10,
    numberWidth = 56,
    timerGap = 14,
    timerWidth = 80,
    -- Rows shown at most (team modes with many teams).
    maxRows = 4,
    -- Ease rate of the fill (1/s): the fill closes 1 - e^(-rate * dt) of the gap per frame.
    ease = 10
}

function lib._ScoreFraction(score, limit)
    if limit <= 0 then return nil end
    return math.min(1, math.max(0, score / limit))
end

---Writes one row into out[slot], reusing the table that is there.
---@param out PW.ScoreRow[]
---@param slot integer
---@param index integer
---@param score number
---@param own boolean
---@param limit integer
local function put(out, slot, index, score, own, limit)
    local row = out[slot]
    if row == nil then
        row = { index = 0, score = 0, own = false }
        out[slot] = row
    end
    row.index, row.score, row.own, row.fraction = index, score, own, lib._ScoreFraction(score, limit)
end

---@param out PW.ScoreRow[]
---@param filled integer
---@param index integer
---@return boolean
local function taken(out, filled, index)
    for i = 1, filled do
        if (out[i] --[[@as PW.ScoreRow]]).index == index then return true end
    end
    return false
end

---Team rows: the own team (team 1 for a spectator) first, then the others by score, ties to the lower index; a
---spectator sees the teams in index order.
---@param scores number[]
---@param count integer
---@param own integer?
---@param limit integer
---@param out PW.ScoreRow[]
---@return integer
local function teamRows(scores, count, own, limit, out)
    local max = math.min(count, lib.ScoreBars.maxRows)
    if own == nil then
        for i = 1, max do put(out, i, i, scores[i], i == 1, limit) end
        return max
    end
    put(out, 1, own, scores[own], true, limit)
    for slot = 2, max do
        ---@type integer?
        local best = nil
        for i = 1, count do
            if not taken(out, slot - 1, i) and (best == nil or scores[i] > scores[best]) then best = i end
        end
        local pick = best --[[@as integer]]
        put(out, slot, pick, scores[pick], false, limit)
    end
    return max
end

function lib._ScoreRows(scores, count, own, ffa, limit, list)
    local out = list --[[@as PW.ScoreRow[] ]]
    if own ~= nil and (own < 1 or own > count) then own = nil end
    local filled = 0
    if count >= 1 then
        if ffa then
            local first, second = lib._Lead(scores, count, own)
            local top = first --[[@as integer]]
            put(out, 1, top, scores[top], top == own, limit)
            filled = 1
            if second ~= nil then
                put(out, 2, second, scores[second], false, limit)
                filled = 2
            end
        else
            filled = teamRows(scores, count, own, limit, out)
        end
    end
    for i = #out, filled + 1, -1 do out[i] = nil end
    return filled
end

function lib._ScoreEase(current, target, dt, rate)
    if dt <= 0 then return current end
    local value = current + (target - current) * (1 - math.exp(-rate * dt))
    if math.abs(target - value) < 0.001 then return target end
    return value
end

function lib._ScoreLayout(width, height, count, limited, out)
    local config, radar = lib.ScoreBars, lib.Radar
    local sx, sy, s = lib._Scale(width, height)
    local rows = math.max(1, count)
    out.x = radar.left * sx
    out.top = radar.top * sy + (2 * radar.radius + config.gap) * s
    out.barWidth, out.barHeight, out.pitch = config.width * s, config.bar * s, config.pitch * s
    out.line, out.tick = config.line * s, config.tick * s
    out.numberX = limited and out.x + (config.width + config.numberGap) * s or out.x
    out.timerX = out.numberX + (config.numberWidth + config.timerGap) * s
    out.timerY = out.top + rows * out.pitch / 2
    out.right = out.timerX + config.timerWidth * s
    out.bottom = out.top + rows * out.pitch
    return out
end

function lib._ScoreBarRects(layout, slot, fraction, out)
    local y = layout.top + (slot - 1) * layout.pitch + (layout.pitch - layout.barHeight) / 2
    out.fillX, out.fillY, out.fillW, out.fillH = layout.x, y, layout.barWidth * fraction, layout.barHeight
    out.lineX, out.lineY, out.lineW, out.lineH = layout.x, y + layout.barHeight, layout.barWidth, layout.line
    out.tickW = layout.line
    out.tickX, out.tickY = layout.x + layout.barWidth - layout.line, y - layout.tick
    out.tickH = out.lineY + out.lineH - out.tickY
    out.numberY = y + layout.barHeight / 2
    return out
end
