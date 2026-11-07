-- SETTINGS (T-7.2; 10-frontend.md d.1 "SETTINGS: client settings | host settings [host]", d.8 "a hint-bar action
-- (F2 / Start)"; 01-extensibility.md d.17). Pushed on the active tab by F2 / Start (ui_kit/cl_root.lua) and by the
-- pause menu's SETTINGS item (screens/match_pause.lua); Back returns to the screen below. Left: the sections
-- (Personal, Host, Enabled content); centre: the form generated from the schema of the section's scope; right: what
-- the section changes and why it is read only. Personal settings are client ConVars written here (PW.Settings.Set);
-- host settings are sent as pw_settings_server (privilege pw.settings.change, checked and clamped again by the
-- server). Enabled content opens the lobby's toggles (screens/lobby_custom.lua). Thin glue over PW.UI.Settings
-- (ui_kit/sh_forms.lua); the match settings live in Game Setup (PLAY > Custom game).

SCREEN.Tab = "play"
SCREEN.Title = "Settings"
SCREEN.Hints = {
    { action = "accept", label = "Select" }, { action = "right", label = "Change value" },
    { action = "back", label = "Back" }
}

---@type table<PW.UISettingsSection, string>
local about = {
    client = "Saved on this computer and used at once. Every player has their own.",
    server = "Saved on the host's computer. Most apply at once; some from the next match.",
    content = "Turns modes, modules and other content on or off. Applies from the next match."
}

---@class PWSettingsView : Panel
---@field cards PWCardList
---@field heading Panel
---@field form PWSettingsForm
---@field info PWInfoCard
---@field section PW.UISettingsSection
---@field model? PW.UISettingsModel
---@field headingText string

---@return PW.UILib
local function kit()
    return PW.UI --[[@as PW.UILib]]
end

---@return PW.UISettingsLib
local function forms()
    return PW.UI.Settings --[[@as PW.UISettingsLib]]
end

---@return PW.LobbyLib?
local function lobby()
    return rawget(PW, "Lobby") --[[@as PW.LobbyLib?]]
end

---@return PW.UISettingsFacts
local function facts()
    local me = LocalPlayer()
    local lobbyLib = lobby()
    local input = lobbyLib ~= nil and lobbyLib.Input ~= nil and lobbyLib.Input() or nil
    local state = input ~= nil and input.state or nil
    return {
        phase = PW.Phase.GetPhase(), canChange = IsValid(me) and PW.Can(me, PW.Settings.Privilege),
        canToggle = state ~= nil and state ~= false and state.canToggle == true
    }
end

---Section headings: the module's Name, else its id.
---@param groups PW.SettingGroup[]
---@return table<string, string>
local function titlesOf(groups)
    ---@type table<string, string>
    local titles = {}
    for _, group in ipairs(groups) do
        local registry = PW.Registries[group.ownerKind]
        local entity = registry ~= nil and registry.Get(group.owner) or nil
        local name = entity ~= nil and entity.Name or nil
        titles[group.owner] = isstring(name) and name --[[@as string]] or group.owner
    end
    return titles
end

---Writes the changes of one edit through the scope's validated path.
---@param model PW.UISettingsModel
---@param changes PW.UISettingsChange[]
local function write(model, changes)
    ---@type PW.UISettingsChange[]
    local written = {}
    for _, change in ipairs(changes) do
        if model.target == "local" then
            local ok, note = PW.Settings.Set(change.id, change.value)
            if ok then
                written[#written + 1] = change
            else
                print("[PW] setting " .. change.id .. " not saved: " .. tostring(note))
            end
        else
            net.Start(model.target)
            net.WriteString(change.id)
            net.WriteString(change.text)
            net.SendToServer()
            written[#written + 1] = change
        end
    end
    forms().Apply(model, written)
end

---@param view PWSettingsView
local function buildForm(view)
    local scope = view.section == "server" and "server" or "client"
    local groups = PW.Settings.GetGroups(scope)
    local model = forms().Model(scope, groups, { titles = titlesOf(groups), facts = facts() })
    view.model = model
    view.headingText = string.upper(scope == "server" and "Host settings" or "Personal settings")
    if not model.editable then view.headingText = view.headingText .. " (READ ONLY)" end
    view.form:SetSections(model.sections, model.editable)
    view.form.OnChange = function(_, control, value)
        write(model, forms().Diff(model, { [control.id] = value }))
    end
    view.info:SetTitle(scope == "server" and "Host" or "Personal")
    local text = about[view.section]
    if model.reason ~= nil then text = text .. " " .. model.reason .. "." end
    for _, note in ipairs(forms().Notes(model)) do text = text .. " " .. note end
    view.info:SetText(text)
end

---@param view PWSettingsView
---@param id string
local function choose(view, id)
    if id == "content" then
        local lobbyLib = lobby()
        if lobbyLib ~= nil and lobbyLib.OpenCustom ~= nil then lobbyLib.OpenCustom("content") end
        return
    end
    view.section = id --[[@as PW.UISettingsSection]]
    view.cards.selected = id
    view.cards:Refresh()
    buildForm(view)
    view:InvalidateLayout(true)
    local root = kit().CurrentRoot ~= nil and kit().CurrentRoot() or nil
    if root ~= nil then (root --[[@as PWRoot]]).focusDirty = 2 end
end

---@param view PWSettingsView
---@param w number
---@param h number
local function layout(view, w, h)
    local px = kit().Draw.Px
    local columns = kit().Layout.Columns(w, h, { margin = 96, left = 480, right = 520, gap = 48, bottom = 16 }, px)
    local left, centre, right = columns.left --[[@as PW.UIRect]], columns.centre, columns.right --[[@as PW.UIRect]]
    view.cards:SetPos(left.x, left.y)
    view.cards:SetSize(left.w, left.h)
    local titleH, gap = px(56), px(16)
    view.heading:SetPos(centre.x, centre.y)
    view.heading:SetSize(centre.w, titleH)
    view.form:SetPos(centre.x, centre.y + titleH + gap)
    view.form:SetSize(centre.w, centre.h - titleH - gap)
    view.info:SetPos(right.x, right.y)
    view.info:SetSize(right.w, math.min(view.info:WantedHeight(right.w), right.h))
end

---@param view PWSettingsView
local function heading(view)
    view.heading = vgui.Create("Panel", view) --[[@as Panel]]
    local hooks = view.heading --[[@as PANEL]]
    hooks.Paint = function(_, w, h)
        local s = kit().Style --[[@as PW.UIStyle]]
        draw.SimpleText(view.headingText, kit().FontName("h2"), 0, h / 2, s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        kit().Draw.Rect(0, h - 1, w, 1, s.border)
    end
end

function SCREEN:Build(ctx)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWSettingsView]]
    view:Dock(FILL)
    view.headingText = ""
    view.section = forms().TakeSection() or "client"
    view.cards = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.cards:SetCards(forms().Sections(facts()), view.section)
    view.cards.OnSelect = function(_, id) choose(view, id) end
    heading(view)
    view.form = vgui.Create("PWSettingsForm", view) --[[@as PWSettingsForm]]
    view.info = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    buildForm(view)
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    view.PWRefresh = function()
        view.cards.cards = forms().Sections(facts())
        view.cards:Refresh()
    end
    return view
end
