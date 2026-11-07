-- Input actions (U-2; notes/16 Q5): one table, keyboard keys and controller codes side by side. Keyboard navigation
-- is the main path (the Deck reaches it through Steam Input); native gamepad is verified at the checkpoint. Hints
-- follow the last device used unless the client setting forces one. Pure: no vgui, no engine calls.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

-- Client setting (01-extensibility.md d.17). The module id makes its ConVar pw_ui_kit_hints.
local moduleTable = rawget(_G, "MODULE")
if moduleTable ~= nil then
    moduleTable.Settings = moduleTable.Settings or {}
    moduleTable.Settings.hints = {
        scope = "client", type = "enum", default = "auto", options = { "auto", "keyboard", "gamepad" },
        label = "Button hints"
    }
end

local input = (rawget(lib, "Input") or {}) --[[@as PW.UIInputLib]]
lib.Input = input

---@type table<string, PW.UIActionDef>
input.Actions = {
    up = { keyboard = { KEY_UP, KEY_W }, controller = { KEY_XBUTTON_UP, KEY_XSTICK1_UP }, cap = "Up", pad = "Up" },
    down = { keyboard = { KEY_DOWN, KEY_S }, controller = { KEY_XBUTTON_DOWN, KEY_XSTICK1_DOWN },
        cap = "Down", pad = "Down" },
    left = { keyboard = { KEY_LEFT, KEY_A }, controller = { KEY_XBUTTON_LEFT, KEY_XSTICK1_LEFT },
        cap = "Left", pad = "Left" },
    right = { keyboard = { KEY_RIGHT, KEY_D }, controller = { KEY_XBUTTON_RIGHT, KEY_XSTICK1_RIGHT },
        cap = "Right", pad = "Right" },
    accept = { keyboard = { KEY_ENTER, KEY_SPACE }, controller = { KEY_XBUTTON_A }, cap = "Enter", pad = "A" },
    back = { keyboard = { KEY_ESCAPE, KEY_BACKSPACE }, controller = { KEY_XBUTTON_B }, cap = "Esc", pad = "B" },
    tab_prev = { keyboard = { KEY_Q }, controller = { KEY_XBUTTON_LEFT_SHOULDER }, cap = "Q", pad = "LB" },
    tab_next = { keyboard = { KEY_E }, controller = { KEY_XBUTTON_RIGHT_SHOULDER }, cap = "E", pad = "RB" },
    secondary = { keyboard = { KEY_F }, controller = { KEY_XBUTTON_X }, cap = "F", pad = "X" },
    tertiary = { keyboard = { KEY_R }, controller = { KEY_XBUTTON_Y }, cap = "R", pad = "Y" },
    page_up = { keyboard = { KEY_PAGEUP }, controller = { KEY_XBUTTON_LTRIGGER }, cap = "PgUp", pad = "LT" },
    page_down = { keyboard = { KEY_PAGEDOWN }, controller = { KEY_XBUTTON_RTRIGGER }, cap = "PgDn", pad = "RT" },
    settings = { keyboard = { KEY_F2 }, controller = { KEY_XBUTTON_START }, cap = "F2", pad = "Start" }
}

---@type table<integer, { action: string, device: PW.UIDevice }>
local byCode = {}
for action, def in pairs(input.Actions) do
    for _, code in ipairs(def.keyboard) do byCode[code] = { action = action, device = "keyboard" } end
    for _, code in ipairs(def.controller) do byCode[code] = { action = action, device = "controller" } end
end

function input.New()
    return { device = "keyboard" }
end

function input.ActionOf(code)
    local hit = byCode[code]
    return hit ~= nil and hit.action or nil
end

function input.Press(state, code)
    local hit = byCode[code]
    if hit == nil then return nil end
    state.device = hit.device
    return hit.action
end

function input.NoteMouse(state)
    state.device = "mouse"
end

function input.Device(state)
    return state.device
end

function input.Hint(state, action, override)
    local def = input.Actions[action]
    local pad = override == "gamepad" or ((override == nil or override == "auto") and state.device == "controller")
    if pad then return { device = "controller", label = def.pad } end
    return { device = "keyboard", label = def.cap }
end
