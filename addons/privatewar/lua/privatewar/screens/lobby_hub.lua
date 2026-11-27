-- PLAY: playlists and Custom Game on the left, operator in the centre, weekly challenges and party on the right.
-- Match settings and Start live on the setup screens. Selecting a playlist changes only the host's local screen.

SCREEN.Tab = "play"
SCREEN.Root = true
SCREEN.Order = 10
SCREEN.Title = "Private War"
---@type PW.UIHintEntry[]
local hints = {
    { action = "accept", label = "Select" }, { action = "secondary", label = "Game setup" },
    { action = "settings", label = "Settings" }
}
SCREEN.Hints = hints

local customId = "@custom"
local challenges = PW.Challenges --[[@as PW.ChallengesViewLib?]]

---@class PWLobbyHubView : Panel
---@field cardList PWCardList
---@field operator PWOperator
---@field weekly PWButton
---@field weeklyTitle DLabel
---@field weeklyRows { label: DLabel, bar: PWProgressBar }[]
---@field weeklyCount integer
---@field hintCard PWInfoCard entry hint (Singleplayer, P2P off)
---@field players PWPlayerList
---@field setup PWButton
---@field hub PW.LobbyHub
---@field framed boolean the status note and hints were applied after the root's frame update
---@field OnAction fun(self: PWLobbyHubView, action: string)

---@return PW.LobbyLib
local function lobby()
    return PW.Lobby --[[@as PW.LobbyLib]]
end

---@param view PWLobbyHubView
local function openSetup(view)
    local selected = view.hub.selected
    if selected == customId then
        lobby().OpenCustom("setup")
    else
        lobby().OpenPlaylist(selected)
    end
end

---@param id string
local function choosePlaylist(id)
    local lib = lobby()
    lib._ChoosePlaylist(lib.Input(), id, lib.SendPick, lib.OpenPlaylist)
end

---Activation ignores a card that is already selected; it must still reopen its setup screen.
---@param view PWLobbyHubView
local function wireSelectedCards(view)
    for index, card in ipairs(view.cardList.cards) do
        local id = card.id
        if card.id == customId then
            view.cardList.panels[index].DoClick = function()
                lobby().SendPick("")
                lobby().OpenCustom("modemap")
            end
        elseif id == view.hub.selected and not card.locked then
            view.cardList.panels[index].DoClick = function() choosePlaylist(id) end
        end
    end
end

---The entry hint (T-8.3) stays in the lobby when one applies.
---@param view PWLobbyHubView
---@param hint? PW.EntryHint
local function showHint(view, hint)
    view.hintCard:SetVisible(hint ~= nil)
    if hint == nil then return end
    view.hintCard:SetTitle(hint.title)
    view.hintCard:SetText(hint.text)
end

---@param parent Panel
---@param font "body"|"small"
---@return DLabel
local function weeklyLabel(parent, font)
    local label = vgui.Create("DLabel", parent) --[[@as DLabel]]
    label:SetMouseInputEnabled(false)
    label:SetFont(PW.UI.FontName(font))
    label:SetTextColor((PW.UI.Style --[[@as PW.UIStyle]]).text)
    return label
end

---@param view PWLobbyHubView
local function showWeekly(view)
    local owner = LocalPlayer()
    local rows = challenges ~= nil and IsValid(owner)
        and challenges._PlayPreviewRows(challenges._OwnerChallengeView(PW, owner, os.time())) or {}
    view.weeklyCount = #rows
    view.weekly:SetVisible(#rows > 0)
    for index, row in ipairs(rows) do
        local pair = view.weeklyRows[index]
        if pair == nil then
            local bar = vgui.Create("PWProgressBar", view.weekly) --[[@as PWProgressBar]]
            bar:SetMouseInputEnabled(false)
            pair = { label = weeklyLabel(view.weekly, "small"), bar = bar }
            view.weeklyRows[index] = pair
        end
        pair.label:SetText(row.progressText .. "  ·  " .. row.text)
        pair.bar:SetProgress(row.fraction)
    end
    for index, pair in ipairs(view.weeklyRows) do
        pair.label:SetVisible(index <= #rows)
        pair.bar:SetVisible(index <= #rows)
    end
    view:InvalidateLayout(true)
end

---@param view PWLobbyHubView
local function refresh(view)
    local hub = lobby()._Hub(lobby().Input())
    view.hub = hub
    lobby().SetCards(view.cardList, hub.cards, hub.selected)
    wireSelectedCards(view)
    view.operator:ShowLocal()
    showHint(view, hub.hint)
    view.players:SetSections(hub.party)
    view.framed = false
    view:InvalidateLayout(true)
end

---@param view PWLobbyHubView
local function fill(view)
    view.cardList = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.cardList.OnSelect = function(_, id)
        if id ~= customId then choosePlaylist(id) end
    end
    view.operator = vgui.Create("PWOperator", view) --[[@as PWOperator]]
    view.weekly = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.weekly:SetVariant("secondary")
    PW.UI.Focusable(view.weekly, "hub_weekly", "weekly_preview")
    view.weeklyCount, view.weeklyRows = 0, {}
    view.weeklyTitle = weeklyLabel(view.weekly, "body")
    view.weeklyTitle:SetText("WEEKLY CHALLENGES")
    view.hintCard = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.hintCard:SetVisible(false)
    view.players = vgui.Create("PWPlayerList", view) --[[@as PWPlayerList]]
    view.players:SetNote("Teams are assigned when the match starts.")
    view.setup = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.setup:SetText("GAME SETUP")
    view.setup:SetVariant("secondary")
    view.setup.DoClick = function() openSetup(view) end
    PW.UI.Focusable(view.setup, "hub_buttons")
end

---@param view PWLobbyHubView
---@param rect PW.UIRect
---@param px fun(n: number): integer
---@return number
local function layoutWeekly(view, rect, px)
    local count = view.weeklyCount
    if count == 0 then return 0 end
    local height, width = px(42 + 34 * count), rect.w
    local padding = px(16)
    view.weekly:SetPos(rect.x, rect.y)
    view.weekly:SetSize(width, height)
    view.weeklyTitle:SetPos(padding, px(6))
    view.weeklyTitle:SetSize(width - 2 * padding, px(28))
    for index = 1, count do
        local pair, y = view.weeklyRows[index], px(36 + 34 * (index - 1))
        pair.label:SetPos(padding, y)
        pair.label:SetSize(width - 2 * padding, px(22))
        pair.bar:SetPos(padding, y + px(24))
        pair.bar:SetSize(width - 2 * padding, px(6))
    end
    return height
end

---@param view PWLobbyHubView
---@param right PW.UIRect
---@param px fun(n: number): integer
local function layoutRight(view, right, px)
    local gap, buttonH = px(20), px(64)
    local weeklyH = layoutWeekly(view, right, px)
    local y = right.y + (weeklyH > 0 and weeklyH + gap or 0)
    if view.hintCard:IsVisible() then
        view.hintCard:SetPos(right.x, y)
        view.hintCard:SetSize(right.w, view.hintCard:WantedHeight(right.w))
        y = y + view.hintCard:GetTall() + gap
    end
    local buttonsY = right.y + right.h - buttonH
    local partyH = math.min(view.players:WantedHeight(right.w), math.max(0, buttonsY - gap - y))
    view.players:SetPos(right.x, buttonsY - gap - partyH)
    view.players:SetSize(right.w, partyH)
    view.setup:SetPos(right.x, buttonsY)
    view.setup:SetSize(right.w, buttonH)
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
    local root = ctx.root --[[@as PWRoot]]
    view.weekly.DoClick = function()
        if challenges ~= nil and challenges._OpenPlayPreview(root.model) then root:Rebuild() end
    end
    hook.Add("PW_ChallengesChanged", view, function() showWeekly(view) end)
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.Think = function()
        if view.framed then return end
        view.framed = true -- after the root's frame update, which resets the hints to SCREEN.Hints
        lobby().SetFrame(view.hub.note, hints)
    end
    view.PWRefresh = function() refresh(view) end
    view.OnAction = function(_, action)
        if action == "secondary" then openSetup(view) end
    end
    refresh(view)
    showWeekly(view)
    return view
end
