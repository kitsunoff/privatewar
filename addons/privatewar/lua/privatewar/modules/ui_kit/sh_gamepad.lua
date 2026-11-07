-- Gamepad buttons for killstreaks and equipment (10-frontend.md d.7: controller codes beside the keyboard;
-- 05-loadout.md d.9, d.11: a dedicated streak key and the slot keys). The design names no pad buttons; the d-pad is
-- used because the GMod controller defaults (cfg/360controller.cfg) bind it only to sandbox tools (undo, voice,
-- noclip, spawn menu), while triggers, face buttons and bumpers are fire, aim, jump, reload, use, flashlight and
-- weapon switch. Pure: button -> action per phase and root state; the client glue (cl_gamepad.lua) runs the commands.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

-- Client setting (01-extensibility.md d.17), shown on the Personal settings screen. ConVar pw_ui_kit_gamepad.
local moduleTable = rawget(_G, "MODULE")
if moduleTable ~= nil then
    moduleTable.Settings = moduleTable.Settings or {}
    moduleTable.Settings.gamepad = {
        scope = "client", type = "bool", default = true, label = "Gamepad d-pad for killstreaks and equipment"
    }
end

local gamepad = (rawget(lib, "Gamepad") or {}) --[[@as PW.UIGamepadLib]]
lib.Gamepad = gamepad

gamepad.SettingConVar = "pw_ui_kit_gamepad"

---@type PW.UIGamepadButton[]
gamepad.Buttons = {
    { action = "streak", code = KEY_XBUTTON_UP, command = "pw_streak", glyph = "D-UP" },
    { action = "streak_next", code = KEY_XBUTTON_RIGHT, command = "pw_streak_next", glyph = "D-RIGHT" },
    { action = "tactical", code = KEY_XBUTTON_LEFT, command = "pw_tactical", glyph = "D-LEFT" },
    { action = "lethal", code = KEY_XBUTTON_DOWN, command = "pw_lethal", glyph = "D-DOWN" }
}

---@type table<integer, PW.UIGamepadButton>
local byCode = {}
---@type table<string, PW.UIGamepadButton>
local byAction = {}
for _, button in ipairs(gamepad.Buttons) do
    byCode[button.code] = button
    byAction[button.action] = button
end

function gamepad.Action(code, facts)
    local button = byCode[code]
    if button == nil or not facts.enabled or facts.rootOpen or facts.phase ~= "LIVE" then return nil end
    return button.action
end

function gamepad.Command(action)
    local button = byAction[action]
    return button ~= nil and button.command or nil
end

function gamepad.Glyph(action, hints, enabled)
    local button = byAction[action]
    if button == nil or not enabled or hints ~= "gamepad" then return nil end
    return button.glyph
end
