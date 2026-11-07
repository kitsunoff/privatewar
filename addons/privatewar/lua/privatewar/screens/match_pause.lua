-- Pause menu (T-7.6; 10-frontend.md d.1 "pause menu (settings, leave)", d.7; 00-core.md "abort and return to
-- lobby"). Root of the in-match tab MATCH: Escape (or the gamepad Start) opens it during a match instead of the GMod
-- menu (ui_kit/cl_match.lua). Left: the items of PW.UI.Match.PauseItems (RESUME, CHANGE CLASS, SETTINGS, RETURN TO
-- LOBBY, LEAVE GAME, GMOD MENU); a player who may not use one sees it locked with the reason. Centre: what this
-- match is (map, class). Esc on it resumes (the router closes a root outside LOBBY). The server checks the abort
-- privilege again (pw_abort); leaving is the engine's disconnect.

SCREEN.Tab = "match"
SCREEN.Root = true
SCREEN.Title = "Match menu"
SCREEN.Hints = { { action = "accept", label = "Select" }, { action = "back", label = "Resume" } }

---@class PWMatchPauseView : Panel
---@field buttons PWButton[]
---@field info PWInfoCard
---@field root PWRoot

local buttonHeight, buttonGap = 64, 12

---@return PW.UILib
local function kit()
    return PW.UI --[[@as PW.UILib]]
end

---@return PW.UIPauseFacts
local function facts()
    local me = LocalPlayer()
    local host = IsValid(me) and me:IsListenServerHost()
    local loadout = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
    return {
        phase = PW.Phase.GetPhase(), host = host, classes = loadout ~= nil and loadout.SendPick ~= nil,
        -- pw.match.abort is declared on the server only (default superadmin); the server checks it again.
        canAbort = host or (IsValid(me) and me:IsSuperAdmin())
    }
end

---@param title string
---@param text string
---@param confirm string
---@param run fun()
local function confirmThen(title, text, confirm, run)
    kit().OpenDialog({ title = title, text = text, confirm = confirm, onConfirm = run })
end

---@type table<string, fun(view: PWMatchPauseView, item: PW.UIPauseItem)>
local actions = {
    resume = function(view) view.root:Remove() end,
    class = function(view)
        if kit().Router.Push(view.root.model, "match_classes") then view.root:Rebuild() end
    end,
    -- T-7.2: the personal settings (screens/settings.lua); Back returns here.
    settings = function(view)
        local forms = kit().Settings
        if forms ~= nil and forms.Open(view.root.model, "client") then view.root:Rebuild() end
    end,
    lobby = function(view, item)
        confirmThen("Return to lobby", item.confirm or "", "END MATCH", function()
            RunConsoleCommand("pw_abort")
            if IsValid(view.root) then view.root:Remove() end
        end)
    end,
    leave = function(_, item)
        confirmThen("Leave game", item.confirm or "", "LEAVE", function() RunConsoleCommand("disconnect") end)
    end,
    gmod = function() kit().ShowGameMenu() end
}

---@return string
local function className()
    local loadout = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
    local state = loadout ~= nil and loadout.GetClassState ~= nil and loadout.GetClassState() or nil
    if state == nil then return "Default loadout" end
    for _, entry in ipairs(state.entries) do
        if entry.ref == state.selected then return entry.name end
    end
    return "Default loadout"
end

---@param view PWMatchPauseView
---@param w number
---@param h number
local function layout(view, w, h)
    local columns = kit().Layout.Columns(w, h, { margin = 96, left = 560, gap = 48, bottom = 16 }, kit().Draw.Px)
    local left, centre = columns.left --[[@as PW.UIRect]], columns.centre
    local px = kit().Draw.Px
    for index, button in ipairs(view.buttons) do
        button:SetPos(left.x, left.y + (index - 1) * px(buttonHeight + buttonGap))
        button:SetSize(left.w, px(buttonHeight))
    end
    local width = math.min(centre.w, px(760))
    view.info:SetPos(centre.x, centre.y)
    view.info:SetSize(width, math.min(view.info:WantedHeight(width), centre.h))
end

---@param view PWMatchPauseView
local function fill(view)
    for _, item in ipairs(kit().Match.PauseItems(facts())) do
        local button = vgui.Create("PWButton", view) --[[@as PWButton]]
        button:SetText(item.label)
        button:SetAlignLeft(true)
        button:SetVariant(item.variant)
        if item.locked then button:SetLocked(true, kit().LockReason(item.reason)) end
        local run = actions[item.id]
        button.DoClick = function()
            if run ~= nil and not item.locked then run(view, item) end
        end
        view.buttons[#view.buttons + 1] = button
    end
    view.info:SetTitle("This match")
    view.info:SetRows({ { "MAP", game.GetMap() }, { "CLASS", className() } })
    view.info:SetText("A class change is used from your next spawn. Shift+Esc opens the GMod menu directly.")
end

function SCREEN:Build(ctx)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWMatchPauseView]]
    view:Dock(FILL)
    view.root, view.buttons = ctx.root --[[@as PWRoot]], {}
    view.info = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    fill(view)
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    view.PWRefresh = function() view.info:SetRows({ { "MAP", game.GetMap() }, { "CLASS", className() } }) end
    return view
end
