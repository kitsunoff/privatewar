-- Gamepad buttons for killstreaks and equipment, client glue. The rules are pure (sh_gamepad.lua); this file reads
-- the engine: a d-pad press in LIVE with no root open runs the console command of the streaks or equipment module
-- (pw_streak, pw_streak_next, pw_tactical, pw_lethal), which checks the inventory and talks to the server. While a
-- button acts, its engine bind (the GMod controller defaults: undo, voice, noclip, spawn menu) is swallowed.

local lib = PW.UI --[[@as PW.UILib]]
local gamepad = lib.Gamepad --[[@as PW.UIGamepadLib]]

local hookName = "PW_UI_Gamepad"

---@type table<string, ConVar>
local vars = {}

---@param name string
---@return ConVar?
local function var(name)
    local found = vars[name]
    if found == nil then
        found = GetConVar(name)
        if found == nil then return nil end
        vars[name] = found
    end
    return found
end

---@return boolean
local function enabled()
    local kit = PW.Modules.Get("ui_kit")
    if kit == nil or not kit:IsValid() then return false end
    local setting = var(gamepad.SettingConVar)
    return setting == nil or setting:GetBool()
end

---@param code integer
---@return PW.UIGamepadAction?
local function actionOf(code)
    local board = lib.Scoreboard
    local boardOpen = board ~= nil and board.IsOpen ~= nil and board.IsOpen()
    return gamepad.Action(code, {
        phase = PW.Phase.GetPhase(), rootOpen = lib.RootOpen() or boardOpen, enabled = enabled()
    })
end

function gamepad.HudGlyph(action)
    local hints = var("pw_ui_kit_hints")
    return gamepad.Glyph(action, hints ~= nil and hints:GetString() or "auto", enabled())
end

hook.Add("PlayerButtonDown", hookName, function(ply, button)
    if ply ~= LocalPlayer() or not IsFirstTimePredicted() then return end
    local action = actionOf(button)
    if action == nil then return end
    local command = gamepad.Command(action)
    if command ~= nil then RunConsoleCommand(command) end
end)

hook.Add("PlayerBindPress", hookName, function(_, _, pressed, code)
    if not pressed or code == nil then return end
    if actionOf(code) ~= nil then return true end
end)
