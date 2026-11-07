-- Lobby, client (T-1.19, U-5; 08-lobby.md d.3; 10-frontend.md d.1, d.8). The lobby is the kit's PWRoot: the PLAY
-- tab root is the hub (screens/lobby_hub.lua), the custom game screen (screens/lobby_custom.lua) is pushed from it.
-- This file holds the data the screens read (pw_lobby_state, the playlist list, the client's mode and map choice),
-- sends the requests and opens the root when the phase enters LOBBY or PREMATCH (the START button counts down) and
-- closes it in the other phases (PW_PhaseChanged);
-- the console command pw_lobby or F1 (the gm_showhelp bind) reopens or closes it during LOBBY. The client decides
-- nothing: the server checks privilege, phase and values again.
-- Disabled module (01-extensibility.md d.16): the root opens only while _ShouldShow holds (LOBBY, lobby_ui and
-- ui_kit valid) and a watch timer closes it as soon as it does not; F1 goes through PW.HookFor, the console command
-- and pw_lobby_state check the module. Lost request or reply: pw_lobby_request is resent every RetryEvery seconds
-- until a pw_lobby_state arrives (_ShouldRequest; garrysmod-issues #5081).

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.LobbyModuleClient : PW.Module
local module = MODULE --[[@as PW.LobbyModuleClient]]

local lib = PW.Lobby --[[@as PW.LobbyLib]]

---@class PW.LobbyClientView
---@field state? PW.LobbyState
---@field selection PW.LobbySelection
---@field waiting? boolean a request was sent and no pw_lobby_state arrived since
---@field open? boolean the lobby opened the root
---@field section? string the custom game section to show next ("modemap", "setup", ...)
---@field players? integer player count at the last refresh
---@field picker? PW.LobbyPickerOpts the options of the map picker to open next (OpenPicker)
---@field flowKey? string the START button countdown label shown last ("" for the normal button)

---@type PW.LobbyClientView
local view = rawget(lib, "_View") or { selection = {} }
rawset(lib, "_View", view)

local retryTimer, watchTimer, watchEvery = "PW.LobbyRequest", "PW.LobbyWatch", 0.25

---@return PW.UILib?
local function kit()
    return rawget(PW, "UI") --[[@as PW.UILib?]]
end

local function send()
    net.Start("pw_lobby_request")
    net.SendToServer()
end

---The playlists module's client part, nil when the module is missing or disabled (the hub then has Custom only).
---@return PW.PlaylistLib?
local function playlists()
    local found = rawget(PW, "Playlist") --[[@as PW.PlaylistLib?]]
    return found ~= nil and found.GetState ~= nil and found or nil
end

---@return boolean
local function kitValid()
    local entry = PW.Modules.Get("ui_kit")
    return kit() ~= nil and entry ~= nil and entry:IsValid()
end

---@return boolean
local function shouldShow()
    return lib._ShouldShow(PW.Phase.GetPhase(), IsValid(module), kitValid())
end

---@return boolean
local function rootOpen()
    local ui = kit()
    return view.open == true and ui ~= nil and ui.RootOpen ~= nil and ui.RootOpen()
end

local function request()
    view.waiting = true
    send()
    local list = playlists()
    if list ~= nil and list.Request ~= nil then list.Request() end
    timer.Create(retryTimer, lib.RetryEvery, 0, function()
        if lib._ShouldRequest(rootOpen(), view.waiting == true) then
            send()
        else
            timer.Remove(retryTimer)
        end
    end)
end

---Asks the open screen to redraw from the current data (its view's PWRefresh).
local function notify()
    local ui = kit()
    local root = ui ~= nil and ui.CurrentRoot ~= nil and ui.CurrentRoot() or nil
    local shown = root ~= nil and (root --[[@as PWRoot]]).view or nil --[[@as Panel?]]
    if shown ~= nil and IsValid(shown) and shown.PWRefresh ~= nil then shown:PWRefresh() end
end

---@param id string
---@return string?
local function shortOf(id)
    local modes = (rawget(PW, "Registries") or {}).modes --[[@as PW.Registry?]]
    local mode = modes ~= nil and modes.Get(id) or nil
    local short = mode ~= nil and mode.Short or nil
    return isstring(short) and short --[[@as string]] or nil
end

---The engine facts the entry hints are made from (T-8.3). p2p_enabled is nil when the engine does not expose it.
---@return PW.EntryFacts
local function entryFacts()
    local p2p = GetConVar("p2p_enabled")
    local me = LocalPlayer()
    return {
        singlePlayer = game.SinglePlayer(), maxPlayers = game.MaxPlayers(),
        host = IsValid(me) and me:IsListenServerHost(), p2p = p2p ~= nil and p2p:GetBool() or nil
    }
end

---The START countdown facts (sh_flow.lua): the phase, its end and the announced map change.
---@return PW.LobbyFlowFacts
local function flowFacts()
    local _, _, changeAt = PW.Phase.GetMapChange()
    return { phase = PW.Phase.GetPhase(), phaseEnd = PW.Phase.GetEnd(), now = CurTime(), changeAt = changeAt }
end

function lib.Input()
    local ui = kit() --[[@as PW.UILib]]
    local list = playlists()
    return {
        state = view.state or false, selection = view.selection, fits = lib._Fits(rawget(PW, "Registries") or {}),
        playlists = list ~= nil and list.GetState() or false, players = ui.CollectPlayers(),
        maxPlayers = game.MaxPlayers(), seen = ui.SeenSet(), shortOf = shortOf, entry = entryFacts(),
        flow = flowFacts()
    }
end

function lib.Select(selection)
    if selection.mode ~= nil then view.selection.mode = selection.mode end
    if selection.map ~= nil then view.selection.map = selection.map end
    notify()
end

---@param group PW.SettingGroup
---@param id string
---@param value any
local function setField(group, id, value)
    for _, field in ipairs(group.fields) do
        if field.def.id == id then field.value = value end
    end
end

function lib.SendSetting(control, value)
    net.Start("pw_settings_match")
    net.WriteString(control.id)
    net.WriteString((kit() --[[@as PW.UILib]]).ToWire(control, value))
    net.SendToServer()
    -- The match values are not replicated: keep the local copy in step with what was sent.
    for _, mode in ipairs(view.state ~= nil and view.state.modes or {}) do
        for _, group in ipairs(mode.groups) do setField(group, control.id, value) end
    end
    notify()
end

function lib.SendToggle(toggle, enabled)
    net.Start("pw_lobby_enable")
    net.WriteString(toggle.kind)
    net.WriteString(toggle.id)
    net.WriteBool(enabled)
    net.SendToServer()
    toggle.enabled = enabled
end

function lib.SendStart(plan)
    local list = playlists()
    if plan.playlist ~= nil then
        if list ~= nil then list.SendStart(plan.playlist) end
        return
    end
    net.Start("pw_lobby_start")
    net.WriteString(plan.mode or "")
    net.WriteString(plan.map or "")
    net.SendToServer()
end

function lib.SendNavGen(fast)
    net.Start("pw_navgen_start")
    net.WriteBool(fast)
    net.WriteBool(false)
    net.SendToServer()
end

---Picks a playlist ("" = Custom) when the player may; the server answers with the new list.
---@param id string
function lib.SendPick(id)
    local list = playlists()
    if list ~= nil and view.state ~= nil and view.state.canStart then list.SendPick(id) end
end

---@return PWRoot?
local function currentRoot()
    local ui = kit()
    local root = ui ~= nil and ui.CurrentRoot ~= nil and ui.CurrentRoot() or nil
    return root --[[@as PWRoot?]]
end

function lib.OpenCustom(section)
    view.section = section
    local root, ui = currentRoot(), kit()
    if root == nil or ui == nil or ui.Router == nil then return end
    if ui.Router.Push(root.model, "lobby_custom") then root:Rebuild() end
end

---Pushes the map picker (screens/map_picker.lua). With opts.pick it is the pick mode: Enter gives the choice to
---the callback and leaves the lobby selection alone (the vote's "Pick myself", U-7).
---@param opts? PW.LobbyPickerOpts
function lib.OpenPicker(opts)
    view.picker = opts or {}
    local root, ui = currentRoot(), kit()
    if root == nil or ui == nil or ui.Router == nil then return end
    if ui.Router.Push(root.model, "map_picker") then root:Rebuild() end
end

---@return PW.LobbyPickerOpts
function lib.TakePicker()
    local opts = view.picker or {}
    view.picker = nil
    return opts
end

function lib.ClosePicker()
    local root, ui = currentRoot(), kit()
    if root == nil or ui == nil or ui.Router == nil then return end
    if ui.Router.Pop(root.model) then root:Rebuild() end
end

function lib.TakeSection()
    local section = view.section
    view.section = nil
    return section
end

function lib.SetCards(list, cards, selected)
    local same = #list.cards == #cards
    for index, card in ipairs(cards) do
        if same and list.cards[index].id ~= card.id then same = false end
    end
    if not same then
        list:SetCards(cards, selected)
    else
        list.cards, list.selected = cards, selected
        list:Refresh()
    end
    lib.Refocus()
end

function lib.Refocus()
    local root = currentRoot()
    if root ~= nil then root.focusDirty = 2 end
end

function lib.SetFrame(note, hints)
    local root = currentRoot()
    if root == nil then return end
    root.status:SetNote(note)
    root.hintBar:SetEntries(hints)
end

---Marks the listed playlists seen (their "NEW" badge shows until the lobby is closed once).
local function markSeen()
    local ui = kit()
    local list = playlists()
    local listed = list ~= nil and list.GetState() or nil
    if ui == nil or ui.SeenSet == nil or listed == nil then return end
    local set, changed = ui.SeenSet(), false
    for _, item in ipairs(listed.list) do
        if ui.Seen.Mark(set, lib._SeenKey(item.id)) then changed = true end
    end
    if changed then ui.SaveSeen() end
end

-- The root closes itself outside LOBBY and PREMATCH or when a module is disabled; the party follows joins and leaves;
-- the START button follows its countdown (one refresh per shown second).
local function watch()
    if not rootOpen() or not shouldShow() then return lib.Close() end
    local count = player.GetCount()
    local over = lib._StartButton(flowFacts())
    local key = over ~= nil and over.label or ""
    if count ~= view.players or key ~= view.flowKey then
        view.players, view.flowKey = count, key
        notify()
    end
end

function lib.Open()
    if rootOpen() or not shouldShow() then
        if not kitValid() then print("[PW] lobby: the ui_kit module is missing or disabled") end
        return
    end
    local ui = kit() --[[@as PW.UILib]]
    view.open, view.players = true, player.GetCount()
    local list = playlists()
    if list ~= nil then list.OnChange = notify end
    ui.OpenRoot()
    timer.Create(watchTimer, watchEvery, 0, watch)
    request()
end

function lib.Close()
    timer.Remove(retryTimer)
    timer.Remove(watchTimer)
    local list = playlists()
    if list ~= nil then list.OnChange = nil end
    view.waiting = false
    local wasOpen = view.open == true
    view.open = false
    if not wasOpen then return end
    markSeen()
    local ui = kit()
    if ui ~= nil and ui.CloseRoot ~= nil then ui.CloseRoot() end
end

local function toggleScreen()
    if rootOpen() then
        lib.Close()
    elseif shouldShow() then
        lib.Open()
    end
end

net.Receive("pw_lobby_state", function()
    if not IsValid(module) then return end
    view.waiting = false
    timer.Remove(retryTimer)
    view.state = lib._Decode({ uint = net.ReadUInt, string = net.ReadString, bool = net.ReadBool },
        lib._Resolver(PW.Registries))
    notify()
end)

---@param phase PW.PhaseName
function module:PW_PhaseChanged(phase)
    if lib._ShouldShow(phase, IsValid(module), kitValid()) then lib.Open() else lib.Close() end
end

concommand.Add("pw_lobby", toggleScreen, nil, "Private War: open or close the lobby screen (LOBBY and PREMATCH)")

include("privatewar/modules/lobby_ui/cl_flow.lua")

---@param bind string
---@param pressed boolean
PW.HookFor(module, "PlayerBindPress", function(_, _, bind, pressed)
    if not pressed or bind ~= "gm_showhelp" or not (rootOpen() or shouldShow()) then return end
    toggleScreen()
    return true
end)

-- Drives the open root from the console (screenshots through the dev bridge: "client pw_lobby_act secondary").
concommand.Add("pw_lobby_act", function(_, _, args)
    local ui = kit()
    local root = ui ~= nil and ui.CurrentRoot ~= nil and ui.CurrentRoot() or nil
    if root == nil or args[1] == nil then return end
    (root --[[@as PWRoot]]):Act(args[1])
end, nil, "Private War: give an input action (down, accept, secondary, ...) to the open lobby")

-- A reload (pw_reload) re-runs this file: rebuild an open screen with the new code. One tick later: while this
-- file runs, MODULE is not registered yet, so it has no IsValid and the screen would refuse to open. For the same
-- reason the file checks its module with the nil-safe IsValid(module) only.
if rootOpen() then
    lib.Close()
    timer.Simple(0, function() lib.Open() end)
end
