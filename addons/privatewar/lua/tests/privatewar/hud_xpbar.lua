-- Bottom XP bar and the LEVEL UP popup (09-hud.md d.2, 06-progression.md d.1). Pure: the fill fraction and its
-- easing, the wrap on a level-up, multi-level jumps, the level-up detection from successive levels messages (no fire on
-- the first sync or a reset), the arming of the bar animation, and the LEVEL UP entry in the medal queue. Drawing and
-- the sound are a manual check (the local checklist).

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

---Steps the bar for `seconds` in frames of `dt`, recording every level it showed.
---@param bar PW.XpBar
---@param level integer
---@param fraction number
---@param seconds number
---@param seen? table<integer, boolean>
local function run(bar, level, fraction, seconds, seen)
    local dt = 1 / 60
    for _ = 1, math.ceil(seconds / dt) do
        hud()._XpBarStep(bar, level, fraction, dt, true)
        if seen ~= nil then seen[must(bar.level)] = true end
    end
end

return {
    groupName = "PW HUD XP bar",
    cases = {
        {
            name = "Fill: the first value snaps, with no animation; a capped level is a full bar",
            func = function()
                local l = hud()
                local bar = l._XpBarNew()
                expect(bar.level).to.beNil()
                l._XpBarStep(bar, 7, 0.3, 1 / 60, true)
                expect(bar.level).to.equal(7)
                expect(bar.fill).to.equal(0.3)
                local capped = l._XpBarNew()
                l._XpBarStep(capped, 55, PW.Progression._Fraction(5000, 0), 1 / 60, true)
                expect(capped.fill).to.equal(1)
            end
        },
        {
            name = "Easing: the fill moves toward the target, faster first, never overshoots, and arrives",
            func = function()
                local l = hud()
                local bar = l._XpBarNew()
                l._XpBarStep(bar, 3, 0.2, 0, true)
                local dt = 1 / 60
                l._XpBarStep(bar, 3, 0.8, dt, true)
                local first = bar.fill - 0.2
                expect(first > 0 and bar.fill < 0.8).to.beTrue()
                local before = bar.fill
                l._XpBarStep(bar, 3, 0.8, dt, true)
                local second = bar.fill - before
                expect(second > 0 and second < first).to.beTrue()
                run(bar, 3, 0.8, 3)
                expect(bar.fill).to.equal(0.8)
                expect(bar.level).to.equal(3)
            end
        },
        {
            name = "Easing: a fill that went down at the same level, and a lower level, snap at once",
            func = function()
                local l = hud()
                local bar = l._XpBarNew()
                l._XpBarStep(bar, 5, 0.6, 0, true)
                l._XpBarStep(bar, 5, 0.1, 1 / 60, true)
                expect(bar.fill).to.equal(0.1)
                l._XpBarStep(bar, 2, 0.4, 1 / 60, true)
                expect(bar.level).to.equal(2)
                expect(bar.fill).to.equal(0.4)
            end
        },
        {
            name = "Wrap: a level-up fills the old level to full, then restarts from 0 and fills the remainder",
            func = function()
                local l = hud()
                local bar = l._XpBarNew()
                l._XpBarStep(bar, 3, 0.5, 0, true)
                l._XpBarStep(bar, 4, 0.25, 1 / 60, true)
                -- The old level is still shown, filling up toward full.
                expect(bar.level).to.equal(3)
                expect(bar.fill > 0.5).to.beTrue()
                local dt, peak, wrapped = 1 / 60, 0, false
                for _ = 1, 600 do
                    local level = bar.level
                    l._XpBarStep(bar, 4, 0.25, dt, true)
                    if level == 3 then peak = math.max(peak, bar.fill) end
                    if level == 3 and bar.level == 4 then
                        wrapped = true
                        expect(bar.fill <= 0.25).to.beTrue()
                    end
                end
                expect(wrapped).to.beTrue()
                expect(peak).to.equal(1)
                expect(bar.level).to.equal(4)
                expect(bar.fill).to.equal(0.25)
            end
        },
        {
            name = "Multi-level jump: one fill to full, then straight to the final level and its remainder",
            func = function()
                local l = hud()
                local bar = l._XpBarNew()
                l._XpBarStep(bar, 3, 0.9, 0, true)
                ---@type table<integer, boolean>
                local seen = {}
                run(bar, 6, 0.4, 5, seen)
                expect(seen[3]).to.beTrue()
                expect(seen[4]).to.beNil()
                expect(seen[5]).to.beNil()
                expect(bar.level).to.equal(6)
                expect(near(bar.fill, 0.4)).to.beTrue()
            end
        },
        {
            name = "Not armed: without animation every change snaps, a level-up included",
            func = function()
                local l = hud()
                local bar = l._XpBarNew()
                l._XpBarStep(bar, 1, 0, 0, true)
                l._XpBarStep(bar, 12, 0.7, 1 / 60, false)
                expect(bar.level).to.equal(12)
                expect(bar.fill).to.equal(0.7)
            end
        },
        {
            name = "Level-up detection: the first levels message is the baseline, a higher level fires once",
            func = function()
                local l = hud()
                local watch = l._LevelWatchNew()
                expect(l._LevelWatch(watch, nil, 1, 0)).to.beNil()
                local join = { level = 12 }
                expect(l._LevelWatch(watch, join, 12, 1)).to.beNil()
                expect(l._LevelWatch(watch, join, 12, 2)).to.beNil()
                local gain = { level = 13 }
                expect(l._LevelWatch(watch, gain, 13, 3)).to.equal(13)
                expect(l._LevelWatch(watch, gain, 13, 4)).to.beNil()
            end
        },
        {
            name = "Level-up detection: a resend at the same level, a weapon level-up and a reset never fire",
            func = function()
                local l = hud()
                local watch = l._LevelWatchNew()
                l._LevelWatch(watch, { level = 5 }, 5, 0)
                expect(l._LevelWatch(watch, { level = 5 }, 5, 1)).to.beNil()
                expect(l._LevelWatch(watch, { level = 3 }, 3, 2)).to.beNil()
                expect(watch.level).to.equal(3)
                expect(l._LevelWatch(watch, { level = 4 }, 4, 3)).to.equal(4)
            end
        },
        {
            name = "Level-up detection: a multi-level jump reports the final level once",
            func = function()
                local l = hud()
                local watch = l._LevelWatchNew()
                l._LevelWatch(watch, { level = 2 }, 2, 0)
                expect(l._LevelWatch(watch, { level = 6 }, 6, 1)).to.equal(6)
            end
        },
        {
            name = "Join: no popup on the first sync, and the bar does not animate until it settled",
            func = function()
                local l = hud()
                local watch = l._LevelWatchNew()
                expect(l._XpBarAnimate(watch, 0)).to.beFalse()
                -- NW2 starts at the default level 1, the upload then sets the stored level 12.
                local bar = l._XpBarNew()
                l._XpBarStep(bar, 1, 0, 1 / 60, l._XpBarAnimate(watch, 0))
                expect(l._LevelWatch(watch, { level = 12 }, 12, 10)).to.beNil()
                l._XpBarStep(bar, 12, 0.5, 1 / 60, l._XpBarAnimate(watch, 10.05))
                expect(bar.level).to.equal(12)
                expect(bar.fill).to.equal(0.5)
                expect(l._XpBarAnimate(watch, 10 + l.XpBarSettle)).to.beTrue()
            end
        },
        {
            name = "Queue: a LEVEL UP after a medal waits for the medal, then shows for the medal duration",
            func = function()
                local l = hud()
                local state = l._MedalNew()
                local d = l.MedalDuration
                l._MedalAdd(state, "double_kill", "Double Kill", 50, 0)
                l._LevelUpAdd(state, 5)
                expect(must(l._MedalCurrent(state, 0)).id).to.equal("double_kill")
                expect(must(l._MedalCurrent(state, d - 0.01)).id).to.equal("double_kill")
                local up = must(l._MedalCurrent(state, d))
                expect(up.kind).to.equal("levelup")
                expect(up.level).to.equal(5)
                expect(up.name).to.equal("LEVEL UP")
                expect(up.label).to.equal("LEVEL 5")
                expect(l._MedalCurrent(state, 2 * d)).to.beNil()
            end
        },
        {
            name = "Queue: a waiting LEVEL UP takes the newer level; one already showing gets a new entry",
            func = function()
                local l = hud()
                local state = l._MedalNew()
                l._LevelUpAdd(state, 4)
                l._LevelUpAdd(state, 5)
                expect(state.count).to.equal(1)
                expect(must(l._MedalCurrent(state, 0)).label).to.equal("LEVEL 5")
                l._LevelUpAdd(state, 6)
                expect(state.count).to.equal(2)
                expect(must(state.list[2]).level).to.equal(6)
            end
        },
        {
            name = "Queue: a LEVEL UP is never dropped by a full medal queue",
            func = function()
                local l = hud()
                local state = l._MedalNew()
                for i = 1, l.MedalMax do l._MedalAdd(state, "m" .. i, "M", 1, 0) end
                l._LevelUpAdd(state, 9)
                expect(state.count).to.equal(l.MedalMax + 1)
                expect(must(state.list[state.count]).kind).to.equal("levelup")
            end
        },
        {
            name = "Pop scale: starts large, eases down to 1 by LevelUpPop and stays there",
            func = function()
                local l = hud()
                local scale, pop = l._LevelUpScale, l.LevelUpPop
                expect(scale(0) > 1).to.beTrue()
                expect(scale(pop / 2) < scale(0) and scale(pop / 2) > 1).to.beTrue()
                expect(scale(pop)).to.equal(1)
                expect(scale(l.MedalDuration)).to.equal(1)
            end
        },
        {
            name = "LEVEL UP layout: unscaled text on screen, max-scale box holds both lines at 720p, 800p and 1080p",
            func = function()
                local l = hud()
                -- Generous text estimates of a bold heading font: 0.75 px per char per px of size, 1.3 lines tall.
                local function textOf(text, design, s)
                    local px = math.floor(design * s + 0.5)
                    return #text * px * 0.75, px * 1.3
                end
                for _, res in ipairs({ { 1280, 720 }, { 1280, 800 }, { 1920, 1080 } }) do
                    local w, h = res[1], res[2]
                    local _, sy, s = l._Scale(w, h)
                    local titleW, titleH = textOf("LEVEL UP", 64, s)
                    local labelW, labelH = textOf("LEVEL 155", 32, s)
                    local facts = { width = w, height = h, scale = s, anchorY = 250 * sy, titleW = titleW,
                        titleH = titleH, labelW = labelW, labelH = labelH }
                    local out = l._LevelUpLayout(facts, { cx = 0, cy = 0, titleY = 0, labelY = 0, boxX = 0, boxY = 0,
                        boxW = 0, boxH = 0 })
                    local tag = w .. "x" .. h
                    -- Unscaled lines: inside the screen (the clip rect is applied before the model matrix).
                    expect(out.cx - titleW / 2 >= 0 and out.cx + titleW / 2 <= w).to.beTrue()
                    expect(out.titleY >= 0 and out.labelY + labelH <= h).to.beTrue()
                    -- Lines do not overlap.
                    expect(out.titleY + titleH <= out.labelY).to.beTrue()
                    -- Box inside the screen and holding both lines at every scale step of the pop-in.
                    expect(out.boxX >= 0 and out.boxY >= 0, tag).to.beTrue()
                    expect(out.boxX + out.boxW <= w and out.boxY + out.boxH <= h).to.beTrue()
                    for step = 0, 10 do
                        local k = l._LevelUpScale(l.LevelUpPop * step / 10)
                        for _, line in ipairs({ { titleW, out.titleY, titleH }, { labelW, out.labelY, labelH } }) do
                            local left = out.cx - line[1] / 2 * k
                            local top = out.cy + (line[2] - out.cy) * k
                            local bottom = out.cy + (line[2] + line[3] - out.cy) * k
                            expect(left >= out.boxX - 0.01 and out.cx + line[1] / 2 * k <= out.boxX + out.boxW + 0.01)
                                .to.beTrue()
                            expect(top >= out.boxY - 0.01 and bottom <= out.boxY + out.boxH + 0.01).to.beTrue()
                        end
                    end
                end
            end
        },
        {
            name = "LEVEL UP: measured text plus padding and shadow fit every animation scale at 720p 800p and 1080p",
            func = function()
                local l = hud()
                for _, res in ipairs({ { 1280, 720 }, { 1280, 800 }, { 1920, 1080 } }) do
                    local w, h = res[1], res[2]
                    local _, sy, s = l._Scale(w, h)
                    -- Measured-pixel inputs, including the case where the second line is the wider one.
                    for _, widths in ipairs({ { 370 * s, 180 * s }, { 270 * s, 410 * s } }) do
                        local titleW, labelW = widths[1], widths[2]
                        local titleH, labelH = 78 * s, 42 * s
                        local facts = { width = w, height = h, scale = s, anchorY = 250 * sy,
                            titleW = titleW, titleH = titleH, labelW = labelW, labelH = labelH }
                        local out = l._LevelUpLayout(facts, { cx = 0, cy = 0, titleY = 0, labelY = 0,
                            boxX = 0, boxY = 0, boxW = 0, boxH = 0 })
                        local padding, shadow = 12 * s, 1
                        local maxScale = l.LevelUpScaleFrom
                        expect(out.boxW >= (math.max(titleW, labelW) + 2 * (padding + shadow)) * maxScale - 0.01)
                            .to.beTrue()
                        expect(out.boxX >= 0 and out.boxY >= 0).to.beTrue()
                        expect(out.boxX + out.boxW <= w and out.boxY + out.boxH <= h).to.beTrue()
                        for step = 0, 60 do
                            local k = l._LevelUpScale(l.LevelUpPop * step / 60)
                            for _, line in ipairs({ { titleW, out.titleY, titleH }, { labelW, out.labelY, labelH } }) do
                                local left = out.cx - line[1] / 2 * k
                                local right = out.cx + (line[1] / 2 + shadow) * k
                                local top = out.cy + (line[2] - out.cy) * k
                                local bottom = out.cy + (line[2] + line[3] + shadow - out.cy) * k
                                expect(left - padding * k >= out.boxX - 0.01).to.beTrue()
                                expect(right + padding * k <= out.boxX + out.boxW + 0.01).to.beTrue()
                                expect(top - padding * k >= out.boxY - 0.01).to.beTrue()
                                expect(bottom + padding * k <= out.boxY + out.boxH + 0.01).to.beTrue()
                            end
                        end
                    end
                end
            end
        }
    }
}
