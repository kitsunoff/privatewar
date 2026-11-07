-- T-11.5 scoreboard rework (TASKS.md, "Mandatory test cases" T-11.5; 09-hud.md revision 2026-11-07 item 3). Pure:
-- the bar rows (own team first, FFA you and the leader or you and second place), the fill fraction against the
-- score limit, the eased fill, the layout under the radar at several resolutions, the L-shaped outline geometry, the
-- score limit the server publishes and the unchanged Domination tiles. Drawing is a manual check.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.HudLib
local function hud()
    return must(PW.HUD)
end

---@param a number
---@param b number
---@return boolean
local function near(a, b)
    return math.abs(a - b) < 1e-6
end

---@param scores number[]
---@param own integer?
---@param ffa boolean
---@param limit integer
---@return PW.ScoreRow[], integer
local function rows(scores, own, ffa, limit)
    ---@type PW.ScoreRow[]
    local out = {}
    local count = hud()._ScoreRows(scores, #scores, own, ffa, limit, out)
    return out, count
end

---@param out PW.ScoreRow[]
---@param count integer
---@return integer[]
local function indices(out, count)
    ---@type integer[]
    local list = {}
    for i = 1, count do list[i] = (out[i] --[[@as PW.ScoreRow]]).index end
    return list
end

---@param width number
---@param height number
---@param count integer
---@param limited boolean
---@return PW.ScoreLayout
local function layout(width, height, count, limited)
    return hud()._ScoreLayout(width, height, count, limited, {})
end

---Bottom edge of the radar disc in pixels, as hud/radar.lua draws it.
---@param width number
---@param height number
---@return number
local function radarBottom(width, height)
    local radar = hud().Radar
    local _, sy, s = hud()._Scale(width, height)
    return radar.top * sy + 2 * radar.radius * s
end

local resolutions = { { 1280, 720 }, { 1280, 800 }, { 1920, 1080 }, { 2560, 1440 }, { 1280, 1024 } }

return {
    groupName = "PW HUD score bars",
    cases = {
        {
            name = "Team order: the own team is the first row, the others follow by score",
            func = function()
                local out, count = rows({ 10, 52 }, 2, false, 75)
                expect(count).to.equal(2)
                expect(indices(out, count)).to.deepEqual({ 2, 1 })
                expect((out[1] --[[@as PW.ScoreRow]]).own).to.beTrue()
                expect((out[2] --[[@as PW.ScoreRow]]).own).to.beFalse()
                expect((out[1] --[[@as PW.ScoreRow]]).score).to.equal(52)
                out, count = rows({ 10, 52 }, 1, false, 75)
                expect(indices(out, count)).to.deepEqual({ 1, 2 })
                out, count = rows({ 10, 52, 30, 52 }, 3, false, 75)
                expect(indices(out, count)).to.deepEqual({ 3, 2, 4, 1 })
            end
        },
        {
            name = "Team order: a spectator sees the teams in index order, team 1 in the friendly colour",
            func = function()
                local out, count = rows({ 10, 52 }, nil, false, 75)
                expect(indices(out, count)).to.deepEqual({ 1, 2 })
                expect((out[1] --[[@as PW.ScoreRow]]).own).to.beTrue()
                expect((out[2] --[[@as PW.ScoreRow]]).own).to.beFalse()
            end
        },
        {
            name = "Rows: the out table is reused and entries past the count are cleared",
            func = function()
                ---@type PW.ScoreRow[]
                local out = {}
                expect(hud()._ScoreRows({ 1, 2, 3 }, 3, 1, false, 10, out)).to.equal(3)
                local first = out[1]
                expect(hud()._ScoreRows({ 1, 2 }, 2, 1, false, 10, out)).to.equal(2)
                expect(out[1] == first).to.beTrue()
                expect(out[3]).to.beNil()
                expect(hud()._ScoreRows({}, 0, nil, false, 10, out)).to.equal(0)
                expect(out[1]).to.beNil()
            end
        },
        {
            name = "Rows: at most ScoreBars.maxRows teams, the own team always among them",
            func = function()
                local max = hud().ScoreBars.maxRows
                ---@type number[]
                local scores = {}
                for i = 1, max + 2 do scores[i] = i end
                local out, count = rows(scores, 1, false, 100)
                expect(count).to.equal(max)
                expect((out[1] --[[@as PW.ScoreRow]]).index).to.equal(1)
                expect((out[2] --[[@as PW.ScoreRow]]).index).to.equal(max + 2)
            end
        },
        {
            name = "FFA: you and the leader, you on top",
            func = function()
                local out, count = rows({ 12, 3, 8 }, 2, true, 30)
                expect(count).to.equal(2)
                expect(indices(out, count)).to.deepEqual({ 2, 1 })
                expect((out[1] --[[@as PW.ScoreRow]]).own).to.beTrue()
                expect((out[2] --[[@as PW.ScoreRow]]).own).to.beFalse()
            end
        },
        {
            name = "FFA: when you lead, you and second place",
            func = function()
                local out, count = rows({ 5, 20, 9, 7 }, 2, true, 30)
                expect(indices(out, count)).to.deepEqual({ 2, 3 })
                -- A tie for the lead is not leading: the other top player is shown.
                out, count = rows({ 9, 9, 4 }, 2, true, 30)
                expect(indices(out, count)).to.deepEqual({ 2, 1 })
            end
        },
        {
            name = "FFA: alone gives one row, a spectator sees the top two",
            func = function()
                local out, count = rows({ 4 }, 1, true, 30)
                expect(count).to.equal(1)
                expect((out[1] --[[@as PW.ScoreRow]]).own).to.beTrue()
                out, count = rows({ 4, 9, 7 }, nil, true, 30)
                expect(indices(out, count)).to.deepEqual({ 2, 3 })
                expect((out[1] --[[@as PW.ScoreRow]]).own).to.beFalse()
            end
        },
        {
            name = "Fraction: score / score limit, clamped to 0..1",
            func = function()
                local fraction = hud()._ScoreFraction
                expect(fraction(0, 75)).to.equal(0)
                expect(fraction(30, 75)).to.equal(0.4)
                expect(fraction(75, 75)).to.equal(1)
                expect(fraction(80, 75)).to.equal(1)
                expect(fraction(-3, 75)).to.equal(0)
                local out = rows({ 15, 30 }, 1, false, 60)
                expect((out[1] --[[@as PW.ScoreRow]]).fraction).to.equal(0.25)
                expect((out[2] --[[@as PW.ScoreRow]]).fraction).to.equal(0.5)
            end
        },
        {
            name = "No limit: no fraction, the rows still carry the scores",
            func = function()
                expect(hud()._ScoreFraction(10, 0)).to.beNil()
                expect(hud()._ScoreFraction(10, -1)).to.beNil()
                local out, count = rows({ 15, 30 }, 1, false, 0)
                expect(count).to.equal(2)
                expect((out[1] --[[@as PW.ScoreRow]]).fraction).to.beNil()
                expect((out[2] --[[@as PW.ScoreRow]]).score).to.equal(30)
            end
        },
        {
            name = "Ease: moves toward the target, converges, never overshoots",
            func = function()
                local ease = hud()._ScoreEase
                local value = 0
                for _ = 1, 600 do
                    local nextValue = ease(value, 0.5, 1 / 60, hud().ScoreBars.ease)
                    expect(nextValue >= value).to.beTrue()
                    expect(nextValue <= 0.5).to.beTrue()
                    value = nextValue
                end
                expect(value).to.equal(0.5)
                expect(ease(1, 0, 1 / 60, 10) < 1).to.beTrue()
                expect(ease(1, 0, 1 / 60, 10) > 0).to.beTrue()
                expect(ease(0.2, 0.7, 10, 10)).to.equal(0.7)
                expect(ease(0.2, 0.7, 0, 10)).to.equal(0.2)
            end
        },
        {
            name = "Layout: under the radar, left-aligned with it, at every tested resolution",
            func = function()
                local radar = hud().Radar
                for _, size in ipairs(resolutions) do
                    local w, h = size[1] --[[@as number]], size[2] --[[@as number]]
                    local sx = hud()._Scale(w, h)
                    local box = layout(w, h, 2, true)
                    expect(near(box.x, radar.left * sx)).to.beTrue()
                    expect(box.top > radarBottom(w, h)).to.beTrue()
                end
                -- 1920x1080 in design units: radar 40 + 2 * 110, then the gap.
                local box = layout(1920, 1080, 2, true)
                expect(box.top).to.equal(40 + 220 + hud().ScoreBars.gap)
                expect(box.barWidth).to.equal(hud().ScoreBars.width)
            end
        },
        {
            name = "Layout: the block stays in the left part, clear of the Domination tiles and the killfeed",
            func = function()
                local dom = must(PW.DomFlags).Hud
                for _, size in ipairs(resolutions) do
                    local w, h = size[1] --[[@as number]], size[2] --[[@as number]]
                    local _, sy, s = hud()._Scale(w, h)
                    local box = layout(w, h, hud().ScoreBars.maxRows, true)
                    local tilesLeft = w / 2 - (3 * dom.tile + 2 * dom.gap) * s / 2
                    local tilesBottom = (dom.top + dom.tile + dom.bar + 3) * sy
                    expect(box.right < tilesLeft or box.top > tilesBottom).to.beTrue()
                    expect(box.right < w * 0.4).to.beTrue()
                    expect(box.bottom < h * 0.5).to.beTrue()
                end
            end
        },
        {
            name = "Layout: the timer sits right of the numbers and centred on the rows",
            func = function()
                local box = layout(1920, 1080, 2, true)
                expect(box.timerX > box.numberX).to.beTrue()
                expect(near(box.timerY, box.top + box.pitch)).to.beTrue()
                local one = layout(1920, 1080, 1, true)
                expect(near(one.timerY, one.top + one.pitch / 2)).to.beTrue()
            end
        },
        {
            name = "Layout: without a limit the numbers move to the left edge, the timer follows them",
            func = function()
                local limited, free = layout(1920, 1080, 2, true), layout(1920, 1080, 2, false)
                expect(free.numberX).to.equal(free.x)
                expect(free.timerX < limited.timerX).to.beTrue()
                expect(free.timerX > free.numberX).to.beTrue()
            end
        },
        {
            name = "Outline: the bottom line spans the full bar, the tick stands at its end, the fill is the fraction",
            func = function()
                local box = layout(1920, 1080, 2, true)
                ---@type PW.ScoreBarRects
                local rect = hud()._ScoreBarRects(box, 2, 0.25, {})
                expect(rect.lineX).to.equal(box.x)
                expect(rect.lineW).to.equal(box.barWidth)
                expect(near(rect.tickX + rect.tickW, box.x + box.barWidth)).to.beTrue()
                expect(rect.tickH > box.barHeight).to.beTrue()
                expect(near(rect.tickY + rect.tickH, rect.lineY + rect.lineH)).to.beTrue()
                expect(rect.fillX).to.equal(box.x)
                expect(near(rect.fillW, box.barWidth * 0.25)).to.beTrue()
                expect(near(rect.fillY, box.top + box.pitch + (box.pitch - box.barHeight) / 2)).to.beTrue()
                expect(rect.lineY >= rect.fillY + rect.fillH).to.beTrue()
                local full = hud()._ScoreBarRects(box, 1, 1, rect)
                expect(full == rect).to.beTrue()
                expect(near(full.fillW, full.lineW)).to.beTrue()
            end
        },
        {
            name = "Timer: still formatted from the phase end (T-6.2 rules unchanged)",
            func = function()
                local ends = hud()._TimerEnd("POSTMATCH", 140, 300)
                expect(hud()._FormatTime(must(hud()._Remaining(ends, 100)))).to.equal("0:40")
                ends = hud()._TimerEnd("LIVE", 140, 700)
                expect(hud()._FormatTime(must(hud()._Remaining(ends, 100)))).to.equal("10:00")
            end
        },
        {
            name = "Score limit: the mode setting, the rounds to win of a round mode, 0 without a mode",
            func = function()
                local limitOf = must(PW.MatchRules)._HudScoreLimit
                local tdm = {
                    ClassName = "tdm", Setting = function(_, key) return key == "scorelimit" and 75 or nil end
                }
                expect(limitOf(tdm)).to.equal(75)
                local off = { ClassName = "x", Setting = function() return 0 end }
                expect(limitOf(off)).to.equal(0)
                local rounds = { ClassName = "sd", RoundsToWin = 4, Setting = function() return 99 end }
                expect(limitOf(rounds)).to.equal(4)
                local own = { ClassName = "y", HudScoreLimit = 12, Setting = function() return 99 end }
                expect(limitOf(own)).to.equal(12)
                expect(limitOf({ ClassName = "z" })).to.equal(0)
                expect(limitOf(nil)).to.equal(0)
                expect(must(PW.MatchRules)._LimitKey).to.equal("pw_hud_limit")
            end
        },
        {
            name = "Domination flag tiles are unchanged: top centre, same layout values",
            func = function()
                local dom = must(PW.DomFlags).Hud
                expect(dom.top).to.equal(100)
                expect(dom.tile).to.equal(56)
                expect(dom.gap).to.equal(12)
                expect(dom.bar).to.equal(6)
                local element = must(PW.Hud).Get("dom")
                expect(element).to.exist()
            end
        }
    }
}
