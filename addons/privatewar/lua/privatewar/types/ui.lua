---@meta
-- Types of the widget kit v0 (T-1.19, 10-frontend.md; 01-extensibility.md d.17).
-- Source: lua/privatewar/modules/ui_kit/ (sh_form.lua: pure form generation; cl_init.lua: widgets and style).

---Which widget edits a setting: int/float with min and max -> "slider", without -> "number"; bool -> "checkbox";
---enum -> "combo"; set with options -> "multiselect"; set without options -> "idlist" (comma-separated ids).
---@alias PW.UIWidget "slider"|"number"|"checkbox"|"combo"|"multiselect"|"idlist"

---One control of a generated settings form.
---@class PW.UIFormControl
---@field id string full setting id "<owner>.<key>"
---@field def PW.SettingDef the setting it edits
---@field widget PW.UIWidget
---@field label string the setting's label (a "#" localisation key or plain text)
---@field description? string the setting's description, if it declares one
---@field value any the value shown (a set is { [id] = true })
---@field min? number slider/number only
---@field max? number slider/number only
---@field decimals? integer slider/number only: 0 for int, 2 for float
---@field options? string[] combo and multiselect only

---One section of a generated settings form: one settings group (the mode first, then the modules).
---@class PW.UIFormSection
---@field owner string id of the mode or module
---@field ownerKind "modes"|"modules"
---@field title string section heading: titles[owner] or the owner id
---@field controls PW.UIFormControl[] one per field of the group, in the group's order

---Colours and fonts of the kit (U-1: palette "Field green", note 16 Q3), in one table so the ui lane can restyle
---every screen in one place. Tokens are cached Color objects; the v0 names (bg, hover, textMuted) alias them.
---@class PW.UIStyle
---@field bg_scrim Color full-screen darkening behind menus (always drawn)
---@field bg_panel Color panels, cards
---@field bg_raised Color expanded card, info card header
---@field bg_hover Color focused row
---@field bg_selected Color selected row
---@field border Color
---@field border_strong Color focused card outline
---@field text Color
---@field text_muted Color
---@field text_disabled Color
---@field accent Color
---@field on_accent Color text on accent fills
---@field positive Color
---@field negative Color
---@field warning Color
---@field team_friendly Color
---@field team_enemy Color
---@field badge_new Color
---@field bg Color alias of bg_panel
---@field hover Color alias of bg_hover
---@field textMuted Color alias of text_muted
---@field fontTitle string engine font name of the h2 step
---@field fontBody string engine font name of the body step
---@field pad integer spacing in pixels

---Font families by role: the only place a family name is written.
---@alias PW.UIFontFamilies table<"heading"|"body", string>

---One named step of the font ladder; size is in design units (1920x1080).
---@class PW.UIFontStep
---@field id string
---@field family "heading"|"body"
---@field size number
---@field weight integer

---surface.CreateFont data of a ladder step (name is the engine font name, font the family).
---@class PW.UIFontData : FontData
---@field name string
---@field size integer pixels

---Widget kit v0 (T-1.19). Pure parts are shared; the widgets (vgui classes PWPanel, PWButton, PWList,
---PWSettingsForm) exist on the client only.
---@class PW.UILib
---Pure: the widget that edits a setting definition.
---@field WidgetFor fun(def: PW.SettingDef): PW.UIWidget
---Pure: settings groups (PW.Settings.GetGroups) -> form sections, one control per field, groups in order.
---titles maps an owner id to a section heading (default: the owner id).
---@field BuildForm fun(groups: PW.SettingGroup[], titles?: table<string, string>): PW.UIFormSection[]
---Pure: the text form of a control's value for pw_settings_match / pw_settings_server.
---@field ToWire fun(control: PW.UIFormControl, value: any): string
---The style table every kit widget reads at paint time (tokens are shared; sh_style.lua).
---@field Style PW.UIStyle
---@field DesignWidth integer 1920
---@field DesignHeight integer 1080
---Smallest font of the ladder in design units (22).
---@field MinFontSize integer
---@field FontFamilies PW.UIFontFamilies
---@field FontSteps PW.UIFontStep[]
---Pure: engine font name of a ladder step id.
---@field FontName fun(id: string): string
---Pure: uniform scale (smaller axis over 1920x1080); PW.HUD._Scale when the hud module is loaded.
---@field ScaleFor fun(width: number, height: number): number
---Pure: pixel size of a design-unit font size, clamped to 4..255.
---@field FontPixels fun(design: number, scale: number): integer
---Pure: CreateFont data of one step at a scale.
---@field FontData fun(step: PW.UIFontStep, scale: number): PW.UIFontData
---Pure: CreateFont data of the whole ladder at a resolution.
---@field FontLadder fun(width: number, height: number): PW.UIFontData[]
---Client: design units to pixels at the current resolution (PW.HUD.S, or the fallback scale).
---@field S? fun(value: number): number
---Client: create the ladder fonts when the resolution changed; true when it did.
---@field RefreshFonts? fun(): boolean
---Client: engine font name of a ladder step, creating the ladder first when needed.
---@field Font? fun(id: string): string

---@class PW
---@field UI? PW.UILib the widget kit (nil when the ui_kit module is missing)

---One row of a PWList.
---@class PW.UIListItem
---@field id string
---@field label string

---Kit panel: a dark box with a border (PW.UI.Style), an optional title on top.
---@class PWPanel : DPanel
---@field SetTitle fun(self: PWPanel, text: string)
---@field _title? DLabel

---Kit button v1 (U-4): flat, painted from tokens. States: normal, focused (hover or keyboard), pressed, selected
---(bg_selected + accent edge bar), disabled, locked (lock glyph, focusable, never clicks). Variants: primary (accent
---fill), secondary (outline), danger. The label is drawn by Paint, not by the derma label.
---@class PWButton : DButton
---@field SetPrimary fun(self: PWButton, primary: boolean)
---@field SetSelected fun(self: PWButton, selected: boolean)
---@field SetVariant fun(self: PWButton, variant?: "primary"|"secondary"|"danger"|"countdown")
---@field SetLocked fun(self: PWButton, locked: boolean, reason?: string)
---@field SetAlignLeft fun(self: PWButton, left: boolean)
---@field _label string
---@field _font string
---@field _align integer TEXT_ALIGN_LEFT or TEXT_ALIGN_CENTER
---@field _variant? "primary"|"secondary"|"danger"|"countdown"
---@field _selected? boolean
---@field _locked? boolean
---@field _pressed? boolean

---Kit list: one selectable button per item; OnSelect(id) is called on a click.
---@class PWList : DScrollPanel
---@field SetItems fun(self: PWList, items: PW.UIListItem[], selected?: string)
---@field OnSelect fun(self: PWList, id: string)
---@field _rows? table<string, PWButton>

---Generated settings form: SetSections builds one widget per control; OnChange(control, value) is called once
---the player stops editing a control for a moment.
---@class PWSettingsForm : DScrollPanel
---@field SetSections fun(self: PWSettingsForm, sections: PW.UIFormSection[], editable: boolean)
---@field OnChange fun(self: PWSettingsForm, control: PW.UIFormControl, value: any)
---@field _Emit fun(self: PWSettingsForm, control: PW.UIFormControl, value: any)

-- Derma callbacks and fields the GMod annotations do not declare (overridden by assignment, wiki: DNumSlider,
-- DNumberWang, DCheckBoxLabel, DComboBox, DTextEntry, DButton).

---@class DNumSlider
---@field Label DLabel
---@field OnValueChanged fun(self: DNumSlider, value: number)

---@class DNumberWang
---@field OnValueChanged fun(self: DNumberWang, value: number)

---@class DCheckBoxLabel
---@field OnChange fun(self: DCheckBoxLabel, value: boolean)

---@class DComboBox
---@field OnSelect fun(self: DComboBox, index: number, value: string, data: any)

---@class DTextEntry
---@field OnEnter fun(self: DTextEntry, value: string)

---@class DButton
---@field DoClick fun(self: DButton)
