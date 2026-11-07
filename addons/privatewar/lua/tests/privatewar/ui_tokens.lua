-- U-1 tokens, fonts, scaling (notes/16-frontend-d1-proposal.md Q2, Q3, Q6; TASKS.md T-7.1). Pure: the token
-- table, the font ladder maths and the scale live in ui_kit/sh_style.lua; creating fonts is a checkpoint.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UILib
local function kit()
    return must(PW.UI)
end

local tokenNames = {
    "bg_scrim", "bg_panel", "bg_raised", "bg_hover", "bg_selected", "border", "border_strong", "text",
    "text_muted", "text_disabled", "accent", "on_accent", "positive", "negative", "warning", "team_friendly",
    "team_enemy", "badge_new"
}

local resolutions = { { 1920, 1080, 1 }, { 1280, 800, 2 / 3 }, { 2560, 1440, 4 / 3 }, { 3440, 1440, 4 / 3 } }

---@param width integer
---@param height integer
---@param expected number
---@return boolean
local function scaleIs(width, height, expected)
    return math.abs(kit().ScaleFor(width, height) - expected) < 0.0001
end

return {
    groupName = "PW UI tokens",
    cases = {
        {
            name = "Every token of the spec exists and is a colour",
            func = function()
                local style = kit().Style --[[@as table<string, any>]]
                for _, name in ipairs(tokenNames) do
                    expect(IsColor(style[name])).to.beTrue()
                end
            end
        },
        {
            name = "Tokens carry the hex and alpha of the palette",
            func = function()
                local style = must(kit().Style)
                expect(style.bg_panel.r).to.equal(11)
                expect(style.bg_panel.g).to.equal(15)
                expect(style.bg_panel.b).to.equal(12)
                expect(style.bg_panel.a).to.equal(184)
                expect(style.bg_scrim.a).to.equal(140)
                expect(style.bg_raised.a).to.equal(217)
                expect(style.accent.g).to.equal(227)
                expect(style.text.a).to.equal(255)
            end
        },
        {
            name = "Legacy style fields map to the tokens",
            func = function()
                local style = must(kit().Style)
                expect(style.textMuted).to.equal(style.text_muted)
                expect(style.hover).to.equal(style.bg_hover)
                expect(style.bg).to.equal(style.bg_panel)
                expect(isstring(style.fontBody)).to.beTrue()
                expect(isstring(style.fontTitle)).to.beTrue()
            end
        },
        {
            name = "Font ladder sizes at 1280x800 are at least 14 px",
            func = function()
                local ladder = kit().FontLadder(1280, 800)
                expect(#ladder > 0).to.beTrue()
                for _, data in ipairs(ladder) do
                    expect(data.size >= 14).to.beTrue()
                end
            end
        },
        {
            name = "No ladder step is below the minimum design size",
            func = function()
                for _, step in ipairs(kit().FontSteps) do
                    expect(step.size >= kit().MinFontSize).to.beTrue()
                end
                expect(kit().MinFontSize).to.equal(22)
            end
        },
        {
            name = "Every font name and family is at most 31 characters",
            func = function()
                for _, data in ipairs(kit().FontLadder(1920, 1080)) do
                    expect(#data.name <= 31).to.beTrue()
                    expect(#data.font <= 31).to.beTrue()
                    expect(data.extended).to.beTrue()
                end
                for _, family in pairs(kit().FontFamilies) do
                    expect(#family <= 31).to.beTrue()
                end
            end
        },
        {
            name = "Scale S at 1920x1080, 1280x800, 2560x1440 and 3440x1440",
            func = function()
                for _, resolution in ipairs(resolutions) do
                    expect(scaleIs(resolution[1], resolution[2], resolution[3])).to.beTrue()
                end
            end
        },
        {
            name = "The fallback scale works when PW.HUD is nil",
            func = function()
                local hud = PW.HUD
                PW.HUD = nil
                local ok, err = pcall(function()
                    for _, resolution in ipairs(resolutions) do
                        expect(scaleIs(resolution[1], resolution[2], resolution[3])).to.beTrue()
                    end
                    expect(#kit().FontLadder(1280, 800) > 0).to.beTrue()
                end)
                PW.HUD = hud
                assert(ok, tostring(err))
            end
        },
        {
            name = "Ladder sizes grow with the resolution",
            func = function()
                local small = kit().FontLadder(1280, 800)
                local large = kit().FontLadder(2560, 1440)
                for index, data in ipairs(small) do
                    expect(must(large[index]).size > data.size).to.beTrue()
                end
            end
        }
    }
}
