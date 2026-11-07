---@meta
-- Types of the gamepad buttons for killstreaks and equipment (10-frontend.md d.7; 05-loadout.md d.9, d.11).
-- Source: lua/privatewar/modules/ui_kit/sh_gamepad.lua (pure, shared) and cl_gamepad.lua (client glue).

---@alias PW.UIGamepadAction "streak"|"streak_next"|"lethal"|"tactical"

---One mapped button.
---@class PW.UIGamepadButton
---@field action PW.UIGamepadAction
---@field code integer the KEY_XBUTTON_* code
---@field command string the console command the action runs (the streaks and equipment modules own them)
---@field glyph string the HUD hint label ("D-UP")

---What a button press depends on.
---@class PW.UIGamepadFacts
---@field phase PW.PhaseName
---@field rootOpen boolean a PWRoot is open (the d-pad navigates it)
---@field enabled boolean ui_kit valid and the client setting gamepad on

---@class PW.UIGamepadLib
---@field Buttons PW.UIGamepadButton[]
---The ConVar of the client setting (module ui_kit, setting gamepad).
---@field SettingConVar string
---The action of a button now, or nil: LIVE only, no root open, the setting on.
---@field Action fun(code: integer, facts: PW.UIGamepadFacts): PW.UIGamepadAction?
---The console command of an action, or nil for an unknown one.
---@field Command fun(action: string): string?
---The HUD glyph of an action when the hints setting is "gamepad" and the buttons are on; nil otherwise (the HUD
---then shows the keyboard key).
---@field Glyph fun(action: string, hints: string, enabled: boolean): string?
---Client: Glyph for the current ConVars (pw_ui_kit_hints, pw_ui_kit_gamepad).
---@field HudGlyph? fun(action: string): string?

---@class PW.UILib
---@field Gamepad? PW.UIGamepadLib
