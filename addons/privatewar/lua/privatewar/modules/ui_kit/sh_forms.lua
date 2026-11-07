-- Settings forms (T-7.2; 01-extensibility.md d.17; 10-frontend.md d.1, d.8). Pure and shared, so the server-side
-- test runner covers it: the form model of one scope (rows from PW.UI.BuildForm with clamped values), clamping
-- through the core's validation, which forms the player may edit in this phase, the diff of an edit against the
-- values last written, the message each scope writes through, the sections of the SETTINGS screen and opening it on
-- the router. The client glue is screens/settings.lua (personal and host settings) and screens/lobby_custom.lua (Game
-- Setup). The server validates and clamps every value again (sv_settings.lua) and checks the privilege and phase.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

local forms = (rawget(lib, "Settings") or {}) --[[@as PW.UISettingsLib]]
lib.Settings = forms

forms.Reasons = {
    privilege = "Only the host can change these",
    phase = "Match settings change in the lobby only",
    content = "The host turns content on and off in the lobby"
}

---@type table<PW.SettingScope, PW.UISettingsTarget>
local targets = { match = "pw_settings_match", server = "pw_settings_server", client = "local" }

---@type PW.UISettingsSection?
local requested = nil

function forms.Clamp(def, value)
    local ok, stored, note = PW.Settings._Validate(def, value)
    if not ok then return nil, note or "invalid" end
    return stored, note
end

function forms.Editable(scope, facts)
    if scope == "client" then return true, nil end
    if not facts.canChange then return false, forms.Reasons.privilege end
    if scope == "match" and facts.phase ~= "LOBBY" then return false, forms.Reasons.phase end
    return true, nil
end

function forms.Target(scope)
    return targets[scope] or "local"
end

function forms.Model(scope, groups, opts)
    local editable, reason = forms.Editable(scope, opts.facts)
    ---@type PW.UISettingsModel
    local model = {
        scope = scope, target = forms.Target(scope), editable = editable, reason = reason,
        sections = lib.BuildForm(groups, opts.titles), defs = {}, values = {}
    }
    for _, section in ipairs(model.sections) do
        for _, control in ipairs(section.controls) do
            local value = forms.Clamp(control.def, control.value)
            if value == nil then value = forms.Clamp(control.def, control.def.default) end
            control.value = value
            model.defs[control.id], model.values[control.id] = control.def, value
        end
    end
    return model
end

---@param def PW.SettingDef
---@param value any
---@return string
local function textOf(def, value)
    return PW.Settings._Format(def, value)
end

function forms.Diff(model, edits)
    ---@type PW.UISettingsChange[]
    local changes = {}
    if not model.editable then return changes end
    for id, edit in pairs(edits) do
        local def = model.defs[id]
        local value = def ~= nil and forms.Clamp(def, edit) or nil
        if def ~= nil and value ~= nil then
            local text = textOf(def, value)
            if text ~= textOf(def, model.values[id]) then
                changes[#changes + 1] = { id = id, value = value, text = text }
            end
        end
    end
    table.sort(changes, function(a, b) return a.id < b.id end)
    return changes
end

function forms.Notes(model)
    ---@type string[]
    local notes = {}
    for _, section in ipairs(model.sections) do
        for _, control in ipairs(section.controls) do
            if control.description ~= nil then notes[#notes + 1] = control.label .. ": " .. control.description end
        end
    end
    return notes
end

function forms.Apply(model, changes)
    for _, change in ipairs(changes) do model.values[change.id] = change.value end
end

---@param id PW.UISettingsSection
---@param title string
---@param text string
---@param reason? string
---@return PW.UICard
local function card(id, title, text, reason)
    return { id = id, title = title, text = text, locked = reason ~= nil, reason = reason }
end

function forms.Sections(facts)
    local _, hostReason = forms.Editable("server", facts)
    local contentReason = nil
    if not facts.canToggle then
        contentReason = forms.Reasons.privilege
    elseif facts.phase ~= "LOBBY" then
        contentReason = forms.Reasons.content
    end
    return {
        card("client", "Personal", "Button hints and the match menus. Saved on this computer."),
        card("server", "Host", "How the server runs between matches: votes, bots, progression, maps.",
            hostReason),
        card("content", "Enabled content", "Turn modes, modules and other content on or off for the next match.",
            contentReason)
    }
end

function forms.Open(model, section)
    local router = lib.Router --[[@as PW.UIRouterLib]]
    if model.screens.settings == nil then return false end
    local top = router.Top(model)
    if top ~= nil and top.ClassName == "settings" then return false end
    if not router.Push(model, "settings") then return false end
    requested = section
    return true
end

function forms.TakeSection()
    local section = requested
    requested = nil
    return section
end
