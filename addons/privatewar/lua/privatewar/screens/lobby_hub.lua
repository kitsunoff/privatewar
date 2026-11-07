-- The lobby hub, root of the PLAY tab (U-5, T-8.1; notes/16-frontend-d1-proposal.md §4a; 10-frontend.md d.8, d.9;
-- 08-lobby.md d.2, d.3). Left: playlist cards and the Custom game card; centre: the operator; right: the selection
-- summary, the MATCH card (key settings, maxplayers warning) and the PARTY list; bottom right: GAME SETUP and START.
-- Thin glue: the data is PW.Lobby._Hub over PW.Lobby.Input() (lobby_ui/sh_hub.lua); the requests go through the
-- lobby_ui client (PW.Lobby.Send*). Actions a guest may not use are locked and explain themselves in the hint bar.

SCREEN.Tab = "play"
SCREEN.Root = true
SCREEN.Order = 10
SCREEN.Title = "Private War"
SCREEN.Hints = {
    { action = "accept", label = "Select" }, { action = "secondary", label = "Game setup" },
    { action = "settings", label = "Settings" }
}

local customId = "@custom"
local hostHints = {
    { action = "accept", label = "Select" }, { action = "secondary", label = "Game setup" },
    { action = "tertiary", label = "Start match" }, { action = "settings", label = "Settings" }
}
local guestHints = {
    { action = "accept", label = "Select" }, { action = "secondary", label = "Game setup" },
    { action = "settings", label = "Settings" }
}

---@class PWLobbyHubView : Panel
---@field cardList PWCardList
---@field operator PWOperator
---@field summary PWSummary
---@field match PWInfoCard
---@field hintCard PWInfoCard entry hint (Singleplayer, P2P off); hidden without a hint
---@field players PWPlayerList
---@field setup PWButton
---@field start PWButton
---@field hub PW.LobbyHub
---@field framed boolean the status note and hints were applied after the root's frame update
---@field OnAction fun(self: PWLobbyHubView, action: string)

---@return PW.LobbyLib
local function lobby()
    return PW.Lobby --[[@as PW.LobbyLib]]
end

---@param view PWLobbyHubView
local function startMatch(view)
    local start = view.hub.start
    if start.locked or start.request == nil then return end
    lobby().SendStart(start.request)
end

---The Custom game card opens the custom screen even when it is already selected (Activate would ignore it).
---@param view PWLobbyHubView
local function wireCustomCard(view)
    for index, card in ipairs(view.cardList.cards) do
        if card.id == customId then
            view.cardList.panels[index].DoClick = function()
                lobby().SendPick("")
                lobby().OpenCustom("modemap")
            end
        end
    end
end

---@param view PWLobbyHubView
---@param hub PW.LobbyHub
local function showSummary(view, hub)
    if not hub.ready then
        view.summary:SetSelection({ Name = "Waiting for the server", Short = "..." }, "")
    elseif hub.selected ~= customId then
        local card = view.cardList.cards[1]
        for _, item in ipairs(hub.cards) do
            if item.id == hub.selected then card = item end
        end
        view.summary:SetSelection({ Name = card.title }, "Mode and map are picked by the playlist")
    else
        view.summary:SetSelection({ Name = hub.summary.mode, Short = hub.summary.badge }, hub.summary.map)
    end
end

---The entry hint (T-8.3) is an info card under the match card; without a hint the card is hidden.
---@param view PWLobbyHubView
---@param hint? PW.EntryHint
local function showHint(view, hint)
    view.hintCard:SetVisible(hint ~= nil)
    if hint == nil then return end
    view.hintCard:SetTitle(hint.title)
    view.hintCard:SetText(hint.text)
end

---@param view PWLobbyHubView
local function refresh(view)
    local hub = lobby()._Hub(lobby().Input())
    view.hub = hub
    lobby().SetCards(view.cardList, hub.cards, hub.selected)
    wireCustomCard(view)
    showSummary(view, hub)
    view.operator:ShowLocal()
    view.match:SetTitle("Match")
    view.match:SetRows(hub.rows)
    view.match:SetWarning(hub.warning)
    showHint(view, hub.hint)
    view.players:SetSections(hub.party)
    view.start:SetText(hub.start.label or "START MATCH")
    view.start:SetLocked(hub.start.locked, hub.start.reason)
    view.start:SetVariant(hub.start.countdown and "countdown" or "primary")
    view.framed = false
    view:InvalidateLayout(true)
end

---@param view PWLobbyHubView
local function fill(view)
    view.cardList = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.cardList.OnSelect = function(_, id)
        if id ~= customId then lobby().SendPick(id) end
    end
    view.operator = vgui.Create("PWOperator", view) --[[@as PWOperator]]
    view.summary = vgui.Create("PWSummary", view) --[[@as PWSummary]]
    view.match = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.hintCard = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.hintCard:SetVisible(false)
    view.players = vgui.Create("PWPlayerList", view) --[[@as PWPlayerList]]
    view.players:SetNote("Teams are assigned when the match starts.")
    view.setup = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.setup:SetText("GAME SETUP")
    view.setup:SetVariant("secondary")
    view.setup.DoClick = function() lobby().OpenCustom("setup") end
    view.start = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.start:SetPrimary(true)
    view.start.DoClick = function() startMatch(view) end
    for _, button in ipairs({ view.setup, view.start }) do
        local spec = PW.UI.Focusable(button, "hub_buttons")
        spec.axis = "horizontal"
    end
end

---@param view PWLobbyHubView
---@param right PW.UIRect
---@param px fun(n: number): integer
local function layoutRight(view, right, px)
    local gap, buttonH = px(20), px(64)
    local y = right.y
    view.summary:SetPos(right.x, y)
    view.summary:SetWide(right.w)
    y = y + view.summary:GetTall() + gap
    view.match:SetPos(right.x, y)
    view.match:SetSize(right.w, view.match:WantedHeight(right.w))
    y = y + view.match:GetTall() + gap
    if view.hintCard:IsVisible() then
        view.hintCard:SetPos(right.x, y)
        view.hintCard:SetSize(right.w, view.hintCard:WantedHeight(right.w))
        y = y + view.hintCard:GetTall() + gap
    end
    local buttonsY = right.y + right.h - buttonH
    view.players:SetPos(right.x, y)
    view.players:SetSize(right.w, math.min(view.players:WantedHeight(right.w), buttonsY - gap - y))
    local setupW = math.floor((right.w - gap) * 0.4)
    view.setup:SetPos(right.x, buttonsY)
    view.setup:SetSize(setupW, buttonH)
    view.start:SetPos(right.x + setupW + gap, buttonsY)
    view.start:SetSize(right.w - setupW - gap, buttonH)
end

---@param view PWLobbyHubView
---@param w number
---@param h number
local function layout(view, w, h)
    local kit = PW.UI --[[@as PW.UILib]]
    local px = kit.Draw.Px
    local columns = kit.Layout.Columns(w, h, { margin = 96, left = 480, right = 520, gap = 48, bottom = 16 }, px)
    local left, centre = columns.left --[[@as PW.UIRect]], columns.centre
    view.cardList:SetPos(left.x, left.y)
    view.cardList:SetSize(left.w, left.h)
    view.operator:SetPos(centre.x, centre.y)
    view.operator:SetSize(centre.w, centre.h)
    layoutRight(view, columns.right --[[@as PW.UIRect]], px)
end

function SCREEN:Build(ctx)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWLobbyHubView]]
    view:Dock(FILL)
    fill(view)
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.Think = function()
        if view.framed then return end
        view.framed = true -- after the root's frame update, which resets the hints to SCREEN.Hints
        lobby().SetFrame(view.hub.note, view.hub.start.locked and guestHints or hostHints)
    end
    view.PWRefresh = function() refresh(view) end
    view.OnAction = function(_, action)
        if action == "secondary" then lobby().OpenCustom("setup") end
        if action == "tertiary" then startMatch(view) end
    end
    refresh(view)
    return view
end
