-- Widget kit v0 (T-1.19; 10-frontend.md: UI is Lua only, an in-house kit; 01-extensibility.md d.17: settings
-- screens are generated from the schema). Shared and pure: settings groups (PW.Settings.GetGroups) become form
-- sections, one control per setting with the widget for its type. The widgets themselves (PWPanel, PWButton,
-- PWList, PWSettingsForm) and the style table are client only: cl_init.lua. Styling (D1: fonts, colour tokens,
-- input) is open; everything visual reads PW.UI.Style, so the ui lane restyles in one place.

MODULE.Name = "Widget kit"

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

-- Style v1 (U-1): tokens, font ladder and scale in a separate shared file (the loader runs shared.lua only).
if SERVER then AddCSLuaFile("privatewar/modules/ui_kit/sh_style.lua") end
include("privatewar/modules/ui_kit/sh_style.lua")

---@type table<string, PW.UIWidget>
local fixedWidgets = { bool = "checkbox", enum = "combo" }

function lib.WidgetFor(def)
    local fixed = fixedWidgets[def.type]
    if fixed ~= nil then return fixed end
    if def.type == "set" then return def.options ~= nil and "multiselect" or "idlist" end
    if def.min ~= nil and def.max ~= nil then return "slider" end
    return "number"
end

---@param field PW.SettingField
---@return PW.UIFormControl
local function controlFor(field)
    local def = field.def
    ---@type PW.UIFormControl
    local control = {
        id = def.id, def = def, widget = lib.WidgetFor(def), label = def.label, description = def.description,
        value = field.value
    }
    if def.type == "int" or def.type == "float" then
        control.min, control.max = def.min, def.max
        control.decimals = def.type == "int" and 0 or 2
    else
        local options = PW.Settings._Options(def)
        if options ~= nil then control.options = table.Copy(options) end
    end
    return control
end

function lib.BuildForm(groups, titles)
    ---@type PW.UIFormSection[]
    local sections = {}
    for _, group in ipairs(groups) do
        ---@type PW.UIFormControl[]
        local controls = {}
        for index, field in ipairs(group.fields) do controls[index] = controlFor(field) end
        sections[#sections + 1] = {
            owner = group.owner, ownerKind = group.ownerKind, controls = controls,
            title = titles ~= nil and titles[group.owner] or group.owner
        }
    end
    return sections
end

function lib.ToWire(control, value)
    return PW.Settings.Format(control.def, value) or ""
end

-- Pure layout, focus and input (U-2), the router (U-3) and the component models (U-4); shared files, sent to
-- clients here. The store and progress view models (T-7.5) come last: progress reads the store's number format. The
-- settings forms (T-7.2) build on BuildForm above.
for _, name in ipairs({
    "layout", "focus", "input", "router", "models", "players", "operator", "match", "store", "progress", "forms",
    "postmatch", "gamepad"
}) do
    local path = "privatewar/modules/ui_kit/sh_" .. name .. ".lua"
    if SERVER then AddCSLuaFile(path) end
    include(path)
end

-- Client glue of the router (PWRoot). The component classes (U-4) are included by cl_init.lua after the fonts and
-- the scale exist; they are sent from here.
if SERVER then
    for _, name in ipairs({
        "root", "paint", "components", "cards", "players", "form", "settings", "operator", "vote", "match", "store",
        "postmatch", "gamepad"
    }) do
        AddCSLuaFile("privatewar/modules/ui_kit/cl_" .. name .. ".lua")
    end
elseif CLIENT then
    include("privatewar/modules/ui_kit/cl_root.lua")
end
