-- Custom game (host lobby), pushed from the hub (U-5, T-8.2; notes/16-frontend-d1-proposal.md §4b; 08-lobby.md d.2,
-- d.3; 02-modes.md d.4). Left: the lobby actions (START MATCH, MODE & MAP, GAME SETUP, ENABLED CONTENT, NAVMESH) and
-- the selection summary; centre: the section of the selected action (mode and map lists, the generated Game Setup
-- form, the enable toggles, the navmesh generation); right: the PARTY list and the MATCH card with the maxplayers
-- warning. Guests see the same screen with every action locked and a read-only Game Setup. MODE & MAP shows the
-- selection and opens the map picker (screens/map_picker.lua, U-6). Thin glue over PW.Lobby._Custom
-- (lobby_ui/sh_hub.lua).

SCREEN.Tab = "play"
SCREEN.Title = "Custom game"
local hostHints = {
    { action = "accept", label = "Select" }, { action = "back", label = "Back" },
    { action = "tertiary", label = "Start match" }
}
SCREEN.Hints = hostHints

local guestHints = { { action = "accept", label = "Select" }, { action = "back", label = "Back" } }
local playlistHints = { { action = "accept", label = "Start playlist" }, { action = "back", label = "Back" } }

-- The warning before a navmesh generation (03-mapdata.md d.8; notes/11-navmesh-generation.md "What the host sees").
local navWarning = "Generating a navmesh takes from about a minute to over an hour on huge maps. The game " ..
    "stutters heavily and may look frozen: do not close it. Large maps can crash the game (out of memory). When " ..
    "done, the map reloads by itself; everyone stays connected and the lobby resets. The file is saved to " ..
    "garrysmod/maps/<map>.nav on this computer; other players do not need it."

---@class PWLobbyCustomView : Panel
---@field actions PWCardList
---@field summary PWSummary
---@field centre Panel holds the panels of the current section
---@field players PWPlayerList
---@field match PWInfoCard
---@field afterMatch PWButton
---@field section string
---@field built? string the key the centre was built for (rebuilt when it changes)
---@field custom PW.LobbyCustom
---@field playlist? string
---@field playlistView? PW.LobbyPlaylistSetup
---@field parts table<string, Panel> panels of the current section by name
---@field framed boolean
---@field OnAction fun(self: PWLobbyCustomView, action: string)

---@return PW.LobbyLib
local function lobby()
    return PW.Lobby --[[@as PW.LobbyLib]]
end

---@return PW.UILib
local function kit()
    return PW.UI --[[@as PW.UILib]]
end

---@param view PWLobbyCustomView
local function startMatch(view)
    local id = view.playlist
    local start = id ~= nil and lobby()._PlaylistSetup(lobby().Input(), id).start or view.custom.start
    if start.locked or start.request == nil then return end
    lobby().SendStart(start.request)
end

---A section title with a thin rule (h2 font).
---@param parent Panel
---@param text string
---@return Panel
local function title(parent, text)
    local item = vgui.Create("Panel", parent) --[[@as Panel]]
    local shown = string.upper(text)
    local hooks = item --[[@as PANEL]]
    hooks.Paint = function(_, w, h)
        local s = kit().Style --[[@as PW.UIStyle]]
        draw.SimpleText(shown, kit().FontName("h2"), 0, h / 2, s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        kit().Draw.Rect(0, h - 1, w, 1, s.border)
    end
    return item
end

-- Sections ----------------------------------------------------------------------------------------------------------

---@type table<string, fun(view: PWLobbyCustomView, centre: Panel)>
local builders = {}

builders.modemap = function(view, centre)
    view.parts.title = title(centre, "Mode & map")
    local info = vgui.Create("PWInfoCard", centre) --[[@as PWInfoCard]]
    info:SetTitle("Selected")
    local summary = view.custom.summary
    info:SetRows({ { "Mode", summary.mode }, { "Map", summary.map } })
    local open = vgui.Create("PWButton", centre) --[[@as PWButton]]
    open:SetText("CHOOSE MODE & MAP")
    open:SetPrimary(true)
    local reason = view.custom.modeMap.reason
    open:SetLocked(view.custom.modeMap.locked, reason)
    open.DoClick = function() lobby().OpenPicker() end
    view.parts.info, view.parts.open = info, open
end

builders.setup = function(view, centre)
    view.parts.title = title(centre, view.custom.canEdit and "Game setup" or "Game setup (read only)")
    local form = vgui.Create("PWSettingsForm", centre) --[[@as PWSettingsForm]]
    form:SetSections(view.custom.sections, view.custom.canEdit)
    form.OnChange = function(_, control, value) lobby().SendSetting(control, value) end
    view.parts.body = form
end

builders.playlist = function(view, centre)
    view.parts.title = title(centre, "Game setup (read only)")
    view.parts.info = vgui.Create("PWInfoCard", centre) --[[@as PWInfoCard]]
end

---The enable toggles as a generated form: one checkbox per entity, one section per kind.
---@param toggles PW.LobbyToggle[]
---@return PW.UIFormSection[]
---@return table<string, PW.LobbyToggle>
local function toggleSections(toggles)
    ---@type PW.UIFormSection[]
    local sections = {}
    ---@type table<string, PW.LobbyToggle>
    local byId = {}
    for _, toggle in ipairs(toggles) do
        local last = sections[#sections]
        if last == nil or last.owner ~= toggle.kind then
            last = { owner = toggle.kind, ownerKind = "modules", title = toggle.kind, controls = {} }
            sections[#sections + 1] = last
        end
        local id = toggle.kind .. "/" .. toggle.id
        byId[id] = toggle
        last.controls[#last.controls + 1] = {
            id = id, widget = "checkbox", label = toggle.name, value = toggle.enabled,
            def = {
                id = id, owner = toggle.kind, ownerKind = "modules", key = toggle.id, type = "bool", scope = "match",
                label = toggle.name, default = true
            }
        }
    end
    return sections, byId
end

builders.content = function(view, centre)
    view.parts.title = title(centre, "Enabled content: applies at the next match")
    local sections, byId = toggleSections(view.custom.toggles)
    local form = vgui.Create("PWSettingsForm", centre) --[[@as PWSettingsForm]]
    form:SetSections(sections, view.custom.canToggle)
    form.OnChange = function(_, control, value)
        local toggle = byId[control.id]
        if toggle ~= nil then lobby().SendToggle(toggle, value == true) end
    end
    view.parts.body = form
end

builders.navmesh = function(view, centre)
    view.parts.title = title(centre, "Navmesh")
    local info = vgui.Create("PWInfoCard", centre) --[[@as PWInfoCard]]
    info:SetTitle("Current map")
    info:SetText(view.custom.navLine)
    local nav = view.custom.nav
    local fast = vgui.Create("PWToggle", centre) --[[@as PWToggle]]
    fast:SetText("Fast mode: turns sv_cheats on until the map reloads")
    fast:SetValue(nav ~= nil and nav.fastDefault)
    local generate = vgui.Create("PWButton", centre) --[[@as PWButton]]
    generate:SetText("GENERATE NAVMESH")
    generate:SetPrimary(true)
    local locked = nav == nil or not nav.canGenerate or nav.generating
    generate:SetLocked(locked, view.custom.actions[#view.custom.actions].reason)
    fast:SetEnabled(not locked)
    generate.DoClick = function()
        kit().OpenDialog({
            title = "Generate navmesh", text = navWarning, confirm = "GENERATE",
            onConfirm = function() lobby().SendNavGen(fast:GetValue()) end
        })
    end
    view.parts.info, view.parts.fast, view.parts.generate = info, fast, generate
end

---What the centre was built from: a change rebuilds it (a mode change rebuilds the Game Setup form).
---@param view PWLobbyCustomView
---@return string
local function buildKey(view)
    if view.playlist ~= nil then return "playlist" end
    local custom = view.custom
    return table.concat({ view.section, tostring(custom.modeSelected), tostring(custom.mapSelected),
        tostring(custom.canEdit),
        tostring(custom.canToggle), tostring(#custom.toggles), custom.navLine }, "|")
end

---@param view PWLobbyCustomView
local function buildCentre(view)
    local key = buildKey(view)
    if key == view.built then return end
    view.built = key
    view.centre:Clear()
    view.parts = {}
    local builder = builders[view.section] or builders.setup
    builder(view, view.centre)
    view:InvalidateLayout(true)
    lobby().Refocus()
end

-- Screen ------------------------------------------------------------------------------------------------------------

---@param view PWLobbyCustomView
local function refresh(view)
    local lib = lobby()
    local input = lib.Input()
    local id = view.playlist
    if id ~= nil then
        local playlist = lib._PlaylistSetup(input, id)
        view.playlistView = playlist
        lib.SetCards(view.actions, playlist.actions)
        view.summary:SetSelection({ Name = playlist.name }, "Playlist")
        view.players:SetSections(playlist.party)
        view.match:SetRows(playlist.rows)
        view.match:SetWarning(playlist.warning)
        view.afterMatch:SetVisible(false)
        buildCentre(view)
        local info = view.parts.info --[[@as PWInfoCard]]
        info:SetTitle(playlist.name)
        info:SetText(playlist.description)
    else
        local custom = lib._Custom(input)
        view.custom = custom
        lib.SetCards(view.actions, custom.actions, view.section)
        view.summary:SetSelection({ Name = custom.summary.mode, Short = custom.summary.badge }, custom.summary.map)
        view.players:SetSections(custom.party)
        view.match:SetRows(custom.rows)
        view.match:SetWarning(custom.warning)
        view.afterMatch:SetVisible(custom.afterMatch ~= nil)
        view.afterMatch:SetText(custom.afterMatch or "")
        buildCentre(view)
    end
    view.match:SetTitle("Match")
    view.framed = false
    view:InvalidateLayout(true)
end

---@param view PWLobbyCustomView
---@param id string
local function onAction(view, id)
    if id == "start" then
        startMatch(view)
        view.actions.selected = view.section -- Start is a command, not a section
        view.actions:Refresh()
        return
    end
    if view.playlist ~= nil then return end
    view.section = id
    buildCentre(view)
    if id == "modemap" and not view.custom.modeMap.locked then lobby().OpenPicker() end
end

---@param view PWLobbyCustomView
---@param rect PW.UIRect
---@param px fun(n: number): integer
local function layoutCentre(view, rect, px)
    local parts, titleH, gap = view.parts, px(56), px(16)
    view.centre:SetPos(rect.x, rect.y)
    view.centre:SetSize(rect.w, rect.h)
    local bodyY, bodyH = titleH + gap, rect.h - titleH - gap
    parts.title:SetPos(0, 0)
    parts.title:SetSize(rect.w, titleH)
    if parts.body ~= nil then
        parts.body:SetPos(0, bodyY)
        parts.body:SetSize(rect.w, bodyH)
    elseif parts.open ~= nil then
        local info = parts.info --[[@as PWInfoCard]]
        info:SetPos(0, bodyY)
        info:SetSize(rect.w, info:WantedHeight(rect.w))
        parts.open:SetPos(0, bodyY + info:GetTall() + gap)
        parts.open:SetSize(px(360), px(64))
    elseif parts.info ~= nil then
        local info = parts.info --[[@as PWInfoCard]]
        info:SetPos(0, bodyY)
        info:SetSize(rect.w, info:WantedHeight(rect.w))
        if parts.fast ~= nil and parts.generate ~= nil then
            local y = bodyY + info:GetTall() + gap
            parts.fast:SetPos(0, y)
            parts.fast:SetWide(rect.w)
            parts.generate:SetPos(0, y + parts.fast:GetTall() + gap)
            parts.generate:SetSize(px(360), px(64))
        end
    end
end

---@param view PWLobbyCustomView
---@param w number
---@param h number
local function layout(view, w, h)
    local px = kit().Draw.Px
    local columns = kit().Layout.Columns(w, h, { margin = 96, left = 480, right = 520, gap = 48, bottom = 16 }, px)
    local left, right = columns.left --[[@as PW.UIRect]], columns.right --[[@as PW.UIRect]]
    local gap = px(20)
    local summaryH = view.summary:GetTall()
    view.actions:SetPos(left.x, left.y)
    view.actions:SetSize(left.w, left.h - summaryH - gap)
    view.summary:SetPos(left.x, left.y + left.h - summaryH)
    view.summary:SetWide(left.w)
    layoutCentre(view, columns.centre, px)
    view.match:SetPos(right.x, right.y)
    view.match:SetSize(right.w, view.match:WantedHeight(right.w))
    local y = right.y + view.match:GetTall() + gap
    if view.afterMatch:IsVisible() then
        view.afterMatch:SetPos(right.x, y)
        view.afterMatch:SetSize(right.w, px(52))
        y = y + view.afterMatch:GetTall() + gap
    end
    view.players:SetPos(right.x, y)
    view.players:SetSize(right.w, math.min(view.players:WantedHeight(right.w), right.y + right.h - y))
end

---@param playlist? string
function SCREEN:Build(ctx, playlist)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWLobbyCustomView]]
    view:Dock(FILL)
    view.playlist = playlist
    view.parts = {}
    view.actions = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.actions.OnSelect = function(_, id) onAction(view, id) end
    view.summary = vgui.Create("PWSummary", view) --[[@as PWSummary]]
    view.centre = vgui.Create("Panel", view) --[[@as Panel]]
    view.match = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.afterMatch = lobby()._AfterMatchButton(view)
    view.players = vgui.Create("PWPlayerList", view) --[[@as PWPlayerList]]
    view.players:SetNote("Teams are assigned when the match starts.")
    local state = lobby().Input().state
    local host = state ~= false and state ~= nil and state.canStart
    view.section = playlist ~= nil and "playlist" or lobby().TakeSection() or (host and "modemap" or "setup")
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.Think = function()
        if view.framed then return end
        view.framed = true
        local playlistView = view.playlistView
        if playlistView ~= nil then
            lobby().SetFrame(playlistView.start.reason, playlistHints)
        else
            lobby().SetFrame(view.custom.note, view.custom.start.locked and guestHints or hostHints)
        end
    end
    view.PWRefresh = function() refresh(view) end
    view.OnAction = function(_, action)
        if action == "tertiary" and view.playlist == nil then startMatch(view) end
    end
    refresh(view)
    return view
end
