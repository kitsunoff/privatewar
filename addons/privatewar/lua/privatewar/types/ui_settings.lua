---@meta
-- Types of the settings forms (T-7.2; 01-extensibility.md d.17; 10-frontend.md d.1, d.8). Source:
-- lua/privatewar/modules/ui_kit/sh_forms.lua (pure, shared); screen lua/privatewar/screens/settings.lua; the Game
-- Setup form of the lobby is screens/lobby_custom.lua.

---What decides whether a form may be edited.
---@class PW.UISettingsFacts
---@field phase PW.PhaseName|string
---@field canChange boolean the player has pw.settings.change (the server checks it again)
---@field canToggle? boolean the player may toggle the enable ConVars (pw.entities.toggle, from the lobby state)

---Where a form's changes go: the validated net message of its scope, or "local" (PW.Settings.Set on the client).
---@alias PW.UISettingsTarget "pw_settings_match"|"pw_settings_server"|"local"

---A generated form of one scope with the values last written (the diff baseline).
---@class PW.UISettingsModel
---@field scope PW.SettingScope
---@field target PW.UISettingsTarget
---@field editable boolean
---@field reason? string why the form is read only
---@field sections PW.UIFormSection[] one section per owner (the mode first), one row per setting
---@field defs table<string, PW.SettingDef> by full id
---@field values table<string, any> the current value per full id (clamped)

---@class PW.UISettingsModelOptions
---@field titles? table<string, string> owner id -> section heading
---@field facts PW.UISettingsFacts

---One value to write back.
---@class PW.UISettingsChange
---@field id string full setting id
---@field value any the validated (clamped) value
---@field text string its text form (PW.Settings.Format)

---Lock reasons shown in the hint bar.
---@class PW.UISettingsReasons
---@field privilege string
---@field phase string
---@field content string

---The section of the SETTINGS screen: personal (client), host (server) or the enable toggles.
---@alias PW.UISettingsSection "client"|"server"|"content"

---Pure settings form logic (sh_forms.lua).
---@class PW.UISettingsLib
---@field Reasons PW.UISettingsReasons
---Validates a value against its definition: the stored value and "clamped" when it was clamped, or nil and the
---reason when the value is invalid (PW.Settings._Validate).
---@field Clamp fun(def: PW.SettingDef, value: any): any, string?
---Whether a form of scope may be edited: client always; server with the privilege; match with the privilege
---and in LOBBY only. The second value is the reason when not.
---@field Editable fun(scope: PW.SettingScope, facts: PW.UISettingsFacts): boolean, string?
---@field Target fun(scope: PW.SettingScope): PW.UISettingsTarget
---Settings groups (PW.Settings.GetGroups) -> the form model: rows by PW.UI.BuildForm with clamped values.
---@field Model fun(scope: PW.SettingScope, groups: PW.SettingGroup[],
---opts: PW.UISettingsModelOptions): PW.UISettingsModel
---The changes to write for edits (full id -> value): only valid values whose text form differs from the
---current value, sorted by id. Empty for a read-only form.
---@field Diff fun(model: PW.UISettingsModel, edits: table<string, any>): PW.UISettingsChange[]
---Pure: "<label>: <description>" for every control of the form that has a description, in form order (shown in
---the info column of the SETTINGS screen).
---@field Notes fun(model: PW.UISettingsModel): string[]
---Records written changes as the current values.
---@field Apply fun(model: PW.UISettingsModel, changes: PW.UISettingsChange[])
---The cards of the SETTINGS screen: Personal, Host (privilege), Enabled content (toggle privilege, LOBBY).
---@field Sections fun(facts: PW.UISettingsFacts): PW.UICard[]
---Pushes the SETTINGS screen on the active tab and asks for a section; false when the screen is unknown, the tab
---is empty or the screen is already on top.
---@field Open fun(model: PW.UIRouterModel, section: PW.UISettingsSection): boolean
---The section asked for by the last Open (read once).
---@field TakeSection fun(): PW.UISettingsSection?

---@class PW.UILib
---@field Settings? PW.UISettingsLib
