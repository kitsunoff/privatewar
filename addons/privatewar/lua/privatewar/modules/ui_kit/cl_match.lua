-- In-match menus, client glue (T-7.6; 10-frontend.md d.1, d.7). The rules are pure (sh_match.lua); this file only
-- reads the engine and opens or closes roots:
-- - Escape (OnPauseMenuShow) and the gamepad Start open the pause menu during a match: a PWRoot over the tabs MATCH
--   (screens/match_pause.lua) and LOADOUT. The GMod menu stays reachable: Shift+Escape, the GMOD MENU item, the
--   client setting pw_ui_kit_pausemenu 0, any phase outside a match, and a pause menu that fails to build.
-- - Escape while one of our roots is open is that root's Back (it ignores a second Back in the same frame, as the key
--   may reach the panel too). At the root screen of the lobby hub Back opens the leave dialog (OpenLobbyLeave):
--   LEAVE GAME, GMOD MENU, CANCEL. Quitting GMod is not offered: "quit" is a blocked command for Lua.
-- - The death watcher (a 0.1 s timer) opens the compact class picker (screens/match_classes.lua) when the local
--   player dies in LIVE and closes it on respawn. Respawn is automatic (match_rules), so the picker never delays it.

local lib = PW.UI --[[@as PW.UILib]]
local match = lib.Match --[[@as PW.UIMatchLib]]

local hookName, timerName = "PW_UI_Match", "PW_UI_Match"
local memory = match.NewDeathMemory()
local bypassUntil = 0
local lastPhase = nil --[[@as string?]]

---@return boolean
local function kitValid()
    local kit = PW.Modules.Get("ui_kit")
    return kit ~= nil and kit:IsValid()
end

---@param name string
---@return boolean
local function settingOn(name)
    local var = GetConVar("pw_ui_kit_" .. name)
    return var == nil or var:GetBool()
end

---@return string?
local function openId()
    local root = lib.CurrentRoot() --[[@as PWRoot?]]
    return root ~= nil and root.rootId or nil
end

---@return boolean
local function classesReady()
    local loadout = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
    return loadout ~= nil and loadout.SendPick ~= nil
end

---Opens a root of the given options; false (and nothing left open) when no screen could be built.
---@param opts PW.UIRootOptions
---@return boolean
local function openRoot(opts)
    if not kitValid() then return false end
    local root = lib.OpenRoot(opts) --[[@as PWRoot]]
    if root.view ~= nil then return true end
    root:Remove()
    return false
end

function lib.OpenPause()
    return openRoot({ id = "pause", tabs = { "match", "loadout" } })
end

function lib.OpenClassPicker()
    if not classesReady() then return false end
    return openRoot({ id = "class", tabs = { "class" }, compact = true })
end

function lib.ShowGameMenu(keepRoot)
    bypassUntil = RealTime() + 0.5
    if not keepRoot then lib.CloseRoot() end
    gui.ActivateGameUI()
end

function lib.OpenLobbyLeave()
    local me = LocalPlayer()
    local spec = match.LobbyLeave(IsValid(me) and me:IsListenServerHost())
    lib.OpenDialog({
        title = spec.title, text = spec.text, confirm = spec.confirm, alt = spec.alt, cancel = spec.cancel,
        onConfirm = function() RunConsoleCommand("disconnect") end,
        -- The lobby stays open under the GMod menu.
        onAlt = function() lib.ShowGameMenu(true) end
    })
end

---@param gameUI boolean
---@return PW.UIEscapeResult
local function escape(gameUI)
    local root = lib.CurrentRoot() --[[@as PWRoot?]]
    return match.Escape({
        phase = PW.Phase.GetPhase(), enabled = kitValid() and settingOn("pausemenu"), rootOpen = root ~= nil,
        gameUI = gameUI, bypass = input.IsShiftDown() or RealTime() < bypassUntil,
        rootId = root ~= nil and root.rootId or nil, depth = root ~= nil and lib.Router.Depth(root.model) or nil,
        modal = root ~= nil and IsValid(root.modal)
    })
end

-- Escape: Back of an open root ("root"; "leave" is the same Back, which opens the lobby's leave dialog), our pause
-- menu during a match, nil (the GMod menu) whenever ours does not open. The engine menu stays suppressed while a
-- root handles Escape.
hook.Add("OnPauseMenuShow", hookName, function()
    local result = escape(gui.IsGameUIVisible())
    if result == "root" or result == "leave" then
        (lib.CurrentRoot() --[[@as PWRoot]]):Act("back")
        return false
    end
    if result == "pause" and lib.OpenPause() then return false end
end)

-- Gamepad Start during play opens the same menu (inside a root it is the root's "settings" action).
hook.Add("PlayerButtonDown", hookName, function(ply, button)
    if button ~= KEY_XBUTTON_START or ply ~= LocalPlayer() or not IsFirstTimePredicted() then return end
    if escape(false) == "pause" then lib.OpenPause() end
end)

---The pause menu follows the phase: rebuilt when it changes (its items depend on it), closed outside a match.
---@param phase string
local function followPhase(phase)
    if phase == lastPhase then return end
    lastPhase = phase
    if openId() ~= "pause" then return end
    if match.PausePhases[phase] then
        (lib.CurrentRoot() --[[@as PWRoot]]):Rebuild()
    else
        lib.CloseRoot()
    end
end

local function watch()
    local phase = PW.Phase.GetPhase()
    followPhase(phase)
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local id = openId()
    local step = match.DeathStep(memory, {
        alive = me:Alive(), phase = phase, open = id == "class", otherRoot = id ~= nil and id ~= "class",
        enabled = kitValid() and classesReady() and settingOn("deathpicker")
    })
    if step == "open" then
        lib.OpenClassPicker()
    elseif step == "close" then
        lib.CloseRoot()
    end
end

timer.Create(timerName, 0.1, 0, watch)

concommand.Add("pw_ui_pause", function()
    if openId() == "pause" then lib.CloseRoot() else lib.OpenPause() end
end, nil, "Private War: open or close the match menu (what Escape opens during a match)")

concommand.Add("pw_ui_classpick", function()
    if openId() == "class" then lib.CloseRoot() else lib.OpenClassPicker() end
end, nil, "Private War: open or close the class picker (it opens by itself on death in LIVE)")
