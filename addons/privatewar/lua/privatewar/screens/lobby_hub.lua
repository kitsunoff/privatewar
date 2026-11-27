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
---@field weeklyRows PW.ChallengePreviewRow[]
---@field weeklyCount string
---@field weeklyLayout? PW.ChallengePreviewLayout
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

---@param text string
---@param font string
---@param width number
---@return string
local function fit(text, font, width)
    surface.SetFont(font)
    return PW.UI.Board.Fit(text, math.max(0, width), function(value)
        local w = surface.GetTextSize(value)
        return w
    end)
end

---@param row PW.ChallengePreviewRow
---@param y number
---@param w number
local function paintWeeklyRow(row, y, w)
    local kit = PW.UI --[[@as PW.UILib]]
    local paint, s = kit.Draw, kit.Style --[[@as PW.UIStyle]]
    local px = paint.Px
    local left, right = px(36), w - px(20)
    local body, small = kit.FontName("body"), kit.FontName("small")
    surface.SetFont(small)
    local progressWidth = surface.GetTextSize(row.progressText)
    local text = fit(row.text, body, right - left - progressWidth - px(12))
    paint.Rect(px(20), y + px(10), px(4), px(30), s.border_strong)
    draw.SimpleText(text, body, left, y + px(18), s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(row.progressText, small, right, y + px(18), s.text_muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    local barWidth = math.max(0, right - left)
    paint.Rect(left, y + px(36), barWidth, px(6), s.bg_raised)
    paint.Rect(left, y + px(36), math.floor(barWidth * row.fraction), px(6), s.accent)
end

---@param view PWLobbyHubView
---@param w number
---@param h number
local function paintWeekly(view, w, h)
    local layout = view.weeklyLayout
    if challenges == nil or layout == nil then return end
    local kit = PW.UI --[[@as PW.UILib]]
    local paint, s = kit.Draw, kit.Style --[[@as PW.UIStyle]]
    local px, metrics = paint.Px, challenges._PlayPreviewMetrics
    local header, rowH = px(metrics.header), px(metrics.row)
    local active = view.weekly._pwFocused or view.weekly:IsHovered()
    local pad = px(20)
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Rect(0, 0, w, header, active and s.bg_hover or s.bg_raised)
    draw.SimpleText("WEEKLY CHALLENGES", kit.FontName("h2"), pad, header / 2, s.text,
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(view.weeklyCount, kit.FontName("body"), w - pad, header / 2, s.text_muted,
        TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    for index = 1, layout.visible do
        local row = view.weeklyRows[index]
        if row ~= nil then paintWeeklyRow(row, header + (index - 1) * rowH, w) end
    end
    local rowsEnd = header + layout.visible * rowH
    if layout.extra > 0 and h > rowsEnd then
        draw.SimpleText(string.format("+%d more", layout.extra), kit.FontName("small"), pad, (rowsEnd + h) / 2,
            s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    paint.Outline(0, 0, w, h, active and s.accent or s.border)
end

---@param view PWLobbyHubView
local function showWeekly(view)
    local owner = LocalPlayer()
    local snapshot = challenges ~= nil and IsValid(owner)
        and challenges._OwnerChallengeView(PW, owner, os.time()) or nil
    view.weeklyRows = challenges ~= nil and challenges._PlayPreviewRows(snapshot) or {}
    view.weeklyCount = snapshot ~= nil and string.format("%d/%d", snapshot.bonus.completed, #snapshot.rows) or ""
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
    view.weekly:SetVisible(false)
    PW.UI.Focusable(view.weekly, "hub_weekly", "weekly_preview")
    view.weeklyCount, view.weeklyRows = "", {}
    local weekly = view.weekly --[[@as PANEL]]
    weekly.Paint = function(_, w, h) paintWeekly(view, w, h) return true end
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
---@param budget number
---@param px fun(n: number): integer
---@return number
local function layoutWeekly(view, rect, budget, px)
    local layout = challenges ~= nil and challenges._PlayPreviewLayout(#view.weeklyRows, budget, px) or nil
    local height = layout ~= nil and layout.height or 0
    view.weeklyLayout = layout
    view.weekly:SetVisible(height > 0)
    if height > 0 then
        view.weekly:SetPos(rect.x, rect.y)
        view.weekly:SetSize(rect.w, height)
    end
    return height
end

---@param view PWLobbyHubView
---@param right PW.UIRect
---@param px fun(n: number): integer
local function layoutRight(view, right, px)
    local gap, buttonH = px(20), px(64)
    local hintH = view.hintCard:IsVisible() and view.hintCard:WantedHeight(right.w) or 0
    local partyWanted = view.players:WantedHeight(right.w)
    local hintSpace = hintH > 0 and hintH + gap or 0
    local budget = right.h - buttonH - gap * 2 - hintSpace - math.min(partyWanted, px(152))
    local weeklyH = layoutWeekly(view, right, budget, px)
    local y = right.y + (weeklyH > 0 and weeklyH + gap or 0)
    if hintH > 0 then
        view.hintCard:SetPos(right.x, y)
        view.hintCard:SetSize(right.w, hintH)
        y = y + hintSpace
    end
    local buttonsY = right.y + right.h - buttonH
    local partyH = math.min(partyWanted, math.max(0, buttonsY - gap - y))
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
