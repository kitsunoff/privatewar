-- Killstreak HUD element, redesign (T-4.6 HUD; 05-loadout.md d.9): three squares on the right, cheapest at the bottom,
-- and a progress bar beside them that reaches each square at its cost. Pure rules of modules/hud/sh_streaks.lua:
-- the square order and anchors, the bar fill between squares and past the last one (the counter does not loop), the
-- state of each square for the counter, the inventory and the selection, the key hint per hint mode, the short
-- labels and a held streak that no square shows. Drawing is a manual check (the local checklist).

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

---The default set: UAV 3, Counter-UAV 4, Airstrike 5, given out of order.
---@return PW.StreakSetEntry[]
local function defaultSet()
    return { { id = "airstrike", cost = 5 }, { id = "uav", cost = 3 }, { id = "counter_uav", cost = 4 } }
end

---@param progress number
---@param inventory string[]
---@param selected integer?
---@return PW.StreakView
local function view(progress, inventory, selected)
    return { set = defaultSet(), progress = progress, inventory = inventory, selected = selected or 1 }
end

---The states of the squares, bottom first.
---@param v PW.StreakView
---@return string[]
local function states(v)
    ---@type PW.StreakSquare[]
    local out = {}
    local count = hud()._StreakSquares(v, out)
    ---@type string[]
    local result = {}
    for i = 1, count do result[i] = (out[i] --[[@as PW.StreakSquare]]).state end
    return result
end

---@param progress number
---@return number
local function fill(progress)
    ---@type PW.StreakSquare[]
    local out = {}
    local count = hud()._StreakSquares(view(progress, {}), out)
    ---@type PW.StreakHudConfig
    local cfg = { right = 0, bottom = 0, size = 60, gap = 20, bar = 6, barGap = 10, max = 3, short = {} }
    return hud()._StreakFill(out, count, progress, cfg)
end

---@param hints string
---@param pad boolean
---@return PW.StreakHintKeys
local function keys(hints, pad)
    return { hints = hints, pad = pad, use = "5", next = "6" }
end

return {
    groupName = "PW HUD streaks v2",
    cases = {
        {
            name = "The streaks element is registered and drawn in LIVE only",
            func = function()
                local element = must(must(PW.Registries["hud"]).Get("streaks")) --[[@as PW.HudElement]]
                expect(must(element.Phases)[1]).to.equal("LIVE")
                expect(#must(element.Phases)).to.equal(1)
            end
        },
        {
            name = "Squares: ordered by cost, cheapest at the bottom (index 1), at most three; stale entries cleared",
            func = function()
                ---@type PW.StreakSquare[]
                local out = {}
                for i = 1, 4 do out[i] = { id = "stale", cost = 1, state = "locked", held = 0 } end
                local count = hud()._StreakSquares(view(0, {}), out)
                expect(count).to.equal(3)
                expect({ must(out[1]).id, must(out[2]).id, must(out[3]).id }).to.deepEqual({ "uav", "counter_uav",
                    "airstrike" })
                expect({ must(out[1]).cost, must(out[2]).cost, must(out[3]).cost }).to.deepEqual({ 3, 4, 5 })
                expect(out[4]).to.beNil()
                -- Equal costs: by id. More than three entries: the three cheapest.
                ---@type PW.StreakView
                local many = { set = { { id = "b", cost = 2 }, { id = "a", cost = 2 }, { id = "z", cost = 9 },
                    { id = "c", cost = 1 } }, progress = 0, inventory = {}, selected = 1 }
                count = hud()._StreakSquares(many, out)
                expect(count).to.equal(3)
                expect({ must(out[1]).id, must(out[2]).id, must(out[3]).id }).to.deepEqual({ "c", "a", "b" })
                -- An empty set gives no squares.
                many.set = {}
                expect(hud()._StreakSquares(many, out)).to.equal(0)
                expect(out[1]).to.beNil()
            end
        },
        {
            name = "Anchors: square i is centred (i - 1) * (size + gap) + size / 2 above the bottom edge",
            func = function()
                expect(hud()._StreakAnchor(1, 60, 20)).to.equal(30)
                expect(hud()._StreakAnchor(2, 60, 20)).to.equal(110)
                expect(hud()._StreakAnchor(3, 60, 20)).to.equal(190)
            end
        },
        {
            name = "Bar: empty at 0, reaches each square exactly at its cost, linear between squares",
            func = function()
                -- size 60, gap 20: anchors 30, 110, 190; the bar is 190 long.
                expect(fill(0)).to.equal(0)
                expect(near(fill(3), 30 / 190)).to.beTrue()
                expect(near(fill(1.5), 15 / 190)).to.beTrue()
                expect(near(fill(4), 110 / 190)).to.beTrue()
                expect(near(fill(3.5), 70 / 190)).to.beTrue()
                expect(near(fill(4.5), 150 / 190)).to.beTrue()
                expect(fill(5)).to.equal(1)
            end
        },
        {
            name = "Bar: stays full past the last cost (the counter does not loop); no squares gives 0",
            func = function()
                expect(fill(6)).to.equal(1)
                expect(fill(40)).to.equal(1)
                expect(fill(-2)).to.equal(0)
                ---@type PW.StreakHudConfig
                local cfg = { right = 0, bottom = 0, size = 60, gap = 20, bar = 6, barGap = 10, max = 3, short = {} }
                expect(hud()._StreakFill({}, 0, 7, cfg)).to.equal(0)
                -- Two squares of equal cost: no division by zero, full at that cost.
                ---@type PW.StreakSquare[]
                local twin = { { id = "a", cost = 2, state = "locked", held = 0 },
                    { id = "b", cost = 2, state = "locked", held = 0 } }
                expect(near(hud()._StreakFill(twin, 2, 1, cfg), 15 / 110)).to.beTrue()
                expect(hud()._StreakFill(twin, 2, 2, cfg)).to.equal(1)
            end
        },
        {
            name = "States: below a cost locked; reached and held ready or selected; reached and used spent",
            func = function()
                expect(states(view(0, {}))).to.deepEqual({ "locked", "locked", "locked" })
                -- 3 kills: the UAV is earned (held, the only one, so selected).
                expect(states(view(3, { "uav" }))).to.deepEqual({ "selected", "locked", "locked" })
                -- The UAV was used: the bar passed it but it is no longer held, so it is dim again.
                expect(states(view(3, {}))).to.deepEqual({ "spent", "locked", "locked" })
                -- All three earned, none used: the first held is selected, the others ready.
                expect(states(view(5, { "uav", "counter_uav", "airstrike" }))).to.deepEqual({ "selected", "ready",
                    "ready" })
                -- After death (counter 0) the held streaks stay lit.
                expect(states(view(0, { "counter_uav" }))).to.deepEqual({ "locked", "selected", "locked" })
            end
        },
        {
            name = "States: the selected inventory index picks the highlighted square; wraps like _Select",
            func = function()
                local inventory = { "uav", "airstrike" }
                expect(states(view(5, inventory, 2))).to.deepEqual({ "ready", "spent", "selected" })
                expect(states(view(5, inventory, 3))).to.deepEqual({ "selected", "spent", "ready" })
                expect(states(view(5, inventory, 0))).to.deepEqual({ "ready", "spent", "selected" })
                ---@type PW.StreakSquare[]
                local out = {}
                hud()._StreakSquares(view(5, { "uav", "airstrike", "uav" }, 1), out)
                expect(must(out[1]).held).to.equal(2)
                expect(must(out[2]).held).to.equal(0)
                expect(must(out[3]).held).to.equal(1)
            end
        },
        {
            name = "Hint: use key on the selected square, next key on the other held ones, none on dim squares",
            func = function()
                local hint = hud()._StreakHint
                expect(hint("selected", keys("keyboard", true))).to.equal("[5]")
                expect(hint("ready", keys("keyboard", true))).to.equal("[6]")
                expect(hint("locked", keys("keyboard", true))).to.equal("")
                expect(hint("spent", keys("gamepad", true))).to.equal("")
                local custom = { hints = "auto", pad = true, use = "kp_end", next = "6" }
                expect(hint("selected", custom)).to.equal("[KP_END]")
            end
        },
        {
            name = "Hint: gamepad hints show the d-pad glyphs; auto, keyboard or the d-pad off show the keys",
            func = function()
                local hint = hud()._StreakHint
                expect(hint("selected", keys("gamepad", true))).to.equal("[D-UP]")
                expect(hint("ready", keys("gamepad", true))).to.equal("[D-RIGHT]")
                expect(hint("selected", keys("gamepad", false))).to.equal("[5]")
                expect(hint("selected", keys("auto", true))).to.equal("[5]")
                expect(hint("ready", keys("keyboard", true))).to.equal("[6]")
            end
        },
        {
            name = "Short labels: UAV, CUAV, AIR for the MVP streaks; else the first 4 letters of the name",
            func = function()
                local short = hud()._StreakShort
                expect(short("uav", "UAV")).to.equal("UAV")
                expect(short("counter_uav", "Counter-UAV")).to.equal("CUAV")
                expect(short("airstrike", "Airstrike")).to.equal("AIR")
                expect(short("sentry_gun", "Sentry gun")).to.equal("SENT")
                expect(short("emp", nil)).to.equal("EMP")
            end
        },
        {
            name = "Orphan: a selected held streak outside the squares is reported; one in the squares is not",
            func = function()
                ---@type PW.StreakSquare[]
                local out = {}
                local v = view(2, { "uav", "pwt_other" }, 2)
                local count = hud()._StreakSquares(v, out)
                expect(hud()._StreakOrphan(out, count, v)).to.equal("pwt_other")
                v.selected = 1
                expect(hud()._StreakOrphan(out, count, v)).to.beNil()
                v.inventory = {}
                expect(hud()._StreakOrphan(out, count, v)).to.beNil()
            end
        }
    }
}
