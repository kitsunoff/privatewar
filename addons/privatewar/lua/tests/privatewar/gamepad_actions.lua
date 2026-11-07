-- Gamepad buttons for killstreaks and equipment (10-frontend.md d.7; 05-loadout.md d.9, d.11). Pure cases over plain
-- data: the d-pad mapping, the console command of each action, phase gating (LIVE only), no action while one of our
-- roots is open, the client setting off, and the HUD glyphs that follow the "Button hints" setting.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UIGamepadLib
local function pad() return must(must(PW.UI).Gamepad) end

---@param extra? table<string, any>
---@return PW.UIGamepadFacts
local function facts(extra)
    ---@type PW.UIGamepadFacts
    local out = { phase = "LIVE", rootOpen = false, enabled = true }
    for key, value in pairs(extra or {}) do out[key] = value end
    return out
end

---@type table<integer, string>
local expected = {
    [KEY_XBUTTON_UP] = "streak",
    [KEY_XBUTTON_RIGHT] = "streak_next",
    [KEY_XBUTTON_LEFT] = "tactical",
    [KEY_XBUTTON_DOWN] = "lethal"
}

return {
    groupName = "Gamepad streak and equipment buttons",
    cases = {
        {
            name = "The d-pad maps to streak, next streak, tactical and lethal",
            func = function()
                for code, action in pairs(expected) do
                    expect(pad().Action(code, facts())).to.equal(action)
                end
                expect(pad().Action(KEY_XBUTTON_A, facts())).to.beNil()
                expect(pad().Action(KEY_XBUTTON_RIGHT_SHOULDER, facts())).to.beNil()
                expect(pad().Action(KEY_G, facts())).to.beNil()
                expect(pad().Action(KEY_NONE, facts())).to.beNil()
            end
        },
        {
            name = "The mapping leaves fire, aim, jump, reload, use and weapon switch alone",
            func = function()
                for _, code in ipairs({
                    KEY_XBUTTON_LTRIGGER, KEY_XBUTTON_RTRIGGER, KEY_XBUTTON_A, KEY_XBUTTON_B, KEY_XBUTTON_X,
                    KEY_XBUTTON_Y, KEY_XBUTTON_LEFT_SHOULDER, KEY_XBUTTON_RIGHT_SHOULDER, KEY_XBUTTON_START,
                    KEY_XBUTTON_BACK, KEY_XBUTTON_STICK1, KEY_XBUTTON_STICK2
                }) do
                    expect(pad().Action(code, facts())).to.beNil()
                end
            end
        },
        {
            name = "Each action runs the console command of its module",
            func = function()
                expect(pad().Command("streak")).to.equal("pw_streak")
                expect(pad().Command("streak_next")).to.equal("pw_streak_next")
                expect(pad().Command("lethal")).to.equal("pw_lethal")
                expect(pad().Command("tactical")).to.equal("pw_tactical")
                local streaks = must(PW.Streaks)
                local equipment = must(PW.Equipment)
                expect(pad().Command("streak")).to.equal(streaks.Keys.use.command)
                expect(pad().Command("streak_next")).to.equal(streaks.Keys.next.command)
                expect(pad().Command("lethal")).to.equal(equipment.Keys.lethal.command)
                expect(pad().Command("tactical")).to.equal(equipment.Keys.tactical.command)
                expect(pad().Command("bogus")).to.beNil()
            end
        },
        {
            name = "Buttons act in LIVE only",
            func = function()
                for _, phase in ipairs({ "LOBBY", "PREMATCH", "POSTMATCH", "VOTE" }) do
                    expect(pad().Action(KEY_XBUTTON_UP, facts({ phase = phase }))).to.beNil()
                    expect(pad().Action(KEY_XBUTTON_DOWN, facts({ phase = phase }))).to.beNil()
                end
                expect(pad().Action(KEY_XBUTTON_UP, facts({ phase = "LIVE" }))).to.equal("streak")
            end
        },
        {
            name = "No action while one of our roots is open (the d-pad navigates the menu)",
            func = function()
                for code in pairs(expected) do
                    expect(pad().Action(code, facts({ rootOpen = true }))).to.beNil()
                end
            end
        },
        {
            name = "The setting off turns every button off",
            func = function()
                for code in pairs(expected) do
                    expect(pad().Action(code, facts({ enabled = false }))).to.beNil()
                end
            end
        },
        {
            name = "The client setting is declared on ui_kit for the Personal screen",
            func = function()
                local kit = must(PW.Modules.Get("ui_kit")) --[[@as PW.Module]]
                local def = must(must(kit.Settings).gamepad)
                expect(def.scope).to.equal("client")
                expect(def.type).to.equal("bool")
                expect(def.default).to.equal(true)
                expect(pad().SettingConVar).to.equal("pw_ui_kit_gamepad")
            end
        },
        {
            name = "HUD glyphs show only with Button hints gamepad and the buttons on",
            func = function()
                expect(pad().Glyph("streak", "gamepad", true)).to.equal("D-UP")
                expect(pad().Glyph("streak_next", "gamepad", true)).to.equal("D-RIGHT")
                expect(pad().Glyph("tactical", "gamepad", true)).to.equal("D-LEFT")
                expect(pad().Glyph("lethal", "gamepad", true)).to.equal("D-DOWN")
                expect(pad().Glyph("streak", "auto", true)).to.beNil()
                expect(pad().Glyph("streak", "keyboard", true)).to.beNil()
                expect(pad().Glyph("streak", "gamepad", false)).to.beNil()
                expect(pad().Glyph("bogus", "gamepad", true)).to.beNil()
            end
        }
    }
}
