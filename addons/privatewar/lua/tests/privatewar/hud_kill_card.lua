-- Calling-card HUD (calling-card-kill-banner.md §7). Draw operations use a recording sink.
---@return PW.CallingCardsLib
local function cards()
    return assert(PW.CallingCards)
end

---@param actual number
---@param expected number
---@return boolean
local function near(actual, expected)
    return math.abs(actual - expected) < 0.0001
end

---@class PW.CardTestPaintOperation
---@field op string
---@field rarity? string
---@field x? number
---@field y? number
---@field w? number
---@field h? number
---@field alpha? number
---@field name? string
---@field label? string
---@field fallback? string

---@return PW.CardPainter, PW.CardTestPaintOperation[]
local function paintLog()
    ---@type PW.CardTestPaintOperation[]
    local log = {}
    return {
        plate = function(rarity, x, y, w, h)
            log[#log + 1] = { op = "plate", rarity = rarity, x = x, y = y, w = w, h = h }
        end,
        art = function(_, x, y, w, h)
            log[#log + 1] = { op = "art", x = x, y = y, w = w, h = h }
        end,
        gradient = function(x, y, w, h, alpha)
            log[#log + 1] = { op = "gradient", x = x, y = y, w = w, h = h, alpha = alpha }
        end,
        text = function(name, label, fallback)
            log[#log + 1] = { op = "text", name = name, label = label, fallback = fallback }
        end
    }, log
end

return {
    groupName = "PW kill card HUD",
    cases = {
        {
            name = "BannerAlpha: fade in, hold, fade out, then 0",
            func = function()
                local alpha = assert(cards()._BannerAlpha, "banner fade not implemented")
                expect(alpha(10, 9, 0.15, 2.5, 0.3)).to.equal(0)
                expect(alpha(10, 10, 0.15, 2.5, 0.3)).to.equal(0)
                expect(near(alpha(10, 10.075, 0.15, 2.5, 0.3), 0.5)).to.beTrue()
                expect(near(alpha(10, 10.15, 0.15, 2.5, 0.3), 1)).to.beTrue()
                expect(alpha(10, 12, 0.15, 2.5, 0.3)).to.equal(1)
                expect(near(alpha(10, 12.8, 0.15, 2.5, 0.3), 0.5)).to.beTrue()
                expect(near(alpha(10, 12.95, 0.15, 2.5, 0.3), 0)).to.beTrue()
                expect(alpha(10, 13.1, 0.15, 2.5, 0.3)).to.equal(0)
            end
        },
        {
            name = "A new kill replaces the banner and restarts the timer",
            func = function()
                local lib = cards()
                local show, alpha = assert(lib._PushBanner), assert(lib._VisibleAlpha)
                ---@type PW.CardBanner
                local state = {}
                show(state, { name = "First", card = "default", bot = false }, 10)
                expect(alpha(state, true, 11)).to.equal(1)
                show(state, { name = "Second", card = "bomb", bot = true }, 11)
                expect(assert(state.packet).name).to.equal("Second")
                expect(assert(state.packet).card).to.equal("bomb")
                expect(state.startedAt).to.equal(11)
                expect(alpha(state, true, 11)).to.equal(0)
                expect(alpha(state, true, 13)).to.equal(1)
            end
        },
        {
            name = "BannerRect: centred, 4:1, bottom edge above the XP bar at common resolutions",
            func = function()
                local rect = assert(cards()._BannerRect)
                for _, resolution in ipairs({ { 1280, 800 }, { 1920, 1080 } }) do
                    local w, h = resolution[1], resolution[2]
                    local scale = math.min(w / 1920, h / 1080)
                    local x, y, width, height = rect(w, h, scale)
                    local xp = h - math.floor(h * 10 / 1080) - math.max(2, math.floor(h * 6 / 1080))
                    expect(near(x + width / 2, w / 2)).to.beTrue()
                    expect(near(width, 400 * scale)).to.beTrue()
                    expect(near(height, 100 * scale)).to.beTrue()
                    expect(near(y + height, xp - 24 * scale)).to.beTrue()
                end
            end
        },
        {
            name = "Missing material falls back to a rarity plate with the card name",
            func = function()
                local lib = cards()
                local draw, style = assert(lib._PaintPlate), assert(lib._PlateStyle)
                local sink, log = paintLog()
                local rect = { x = 0, y = 0, w = 400, h = 100 }
                draw({ style = style(false, 512, 128), title = "Veteran", rarity = "rare" }, sink,
                    "Victim", "ELIMINATED", rect)
                expect(#log).to.equal(3)
                expect(log[1].op).to.equal("plate")
                expect(log[1].rarity).to.equal("rare")
                expect(log[3].fallback).to.equal("Veteran")
                local empty, emptyLog = paintLog()
                draw({ style = "missing", title = "", rarity = "neutral" }, empty,
                    "Victim", "ELIMINATED", rect)
                expect(emptyLog[1].rarity).to.equal("neutral")
            end
        },
        {
            name = "Small icon materials are drawn centred, not stretched",
            func = function()
                local lib = cards()
                local paint, style = assert(lib._PaintPlate), assert(lib._PlateStyle)
                local sink, log = paintLog()
                paint({ style = style(true, 16, 16), title = "Bomb", rarity = "rare", width = 16, height = 16 }, sink,
                    "Victim", "ELIMINATED", { x = 10, y = 20, w = 400, h = 100 })
                expect(log[1].op).to.equal("plate")
                local icon = log[2]
                expect(icon.op).to.equal("art")
                expect(icon.x).to.equal(202)
                expect(icon.y).to.equal(62)
                expect(icon.w).to.equal(16)
                expect(icon.h).to.equal(16)
            end
        },
        {
            name = "Name plate gradient is drawn under the name on every card",
            func = function()
                local paint = assert(cards()._PaintPlate)
                ---@type PW.CardPlateStyle[]
                local variants = { "art", "icon", "missing" }
                for _, variant in ipairs(variants) do
                    local sink, log = paintLog()
                    paint({ style = variant, title = "Recruit", rarity = "common", width = 16, height = 16 }, sink,
                        "Victim", "ELIMINATED", { x = 10, y = 20, w = 400, h = 100 })
                    local gradient, text = log[#log - 1], log[#log]
                    expect(gradient.op).to.equal("gradient")
                    expect(gradient.x).to.equal(10)
                    expect(gradient.y).to.equal(20)
                    expect(near(assert(gradient.w), 220)).to.beTrue()
                    expect(gradient.h).to.equal(100)
                    expect(gradient.alpha).to.equal(0.85)
                    expect(text.op).to.equal("text")
                    expect(text.name).to.equal("Victim")
                    expect(text.label).to.equal("ELIMINATED")
                end
            end
        },
        {
            name = "Banner hidden when calling_cards.banner is off",
            func = function()
                local lib = cards()
                ---@type PW.CardBanner
                local state = {}
                local show, alpha = assert(lib._PushBanner), assert(lib._VisibleAlpha)
                expect(alpha(state, true, 10)).to.equal(0)
                show(state, { name = "Victim", card = "default", bot = false }, 10)
                expect(alpha(state, true, 11)).to.equal(1)
                expect(alpha(state, false, 11)).to.equal(0)
            end
        }
    }
}
