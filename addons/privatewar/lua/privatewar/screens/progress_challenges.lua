SCREEN.Tab = "progress"
SCREEN.Title = "Weekly challenges"
SCREEN.Hints = { { action = "accept", label = "Details" }, { action = "back", label = "Back" } }

---@class PWWeeklyScreen : Panel
---@field week PWInfoCard
---@field bonus PWButton
---@field bonusBar PWProgressBar
---@field bonusReward PWInfoCard
---@field list PWCardList
---@field empty PWInfoCard
---@field details PWButton
---@field info PWInfoCard
---@field bars PWProgressBar[]
---@field data? PW.ChallengeWeekView
---@field selected? string
---@field showBonus boolean
---@field nextRefresh number
---@field nextClock number
---@field clockLabel? string
---@field rowText table<string, { description: string, reward: string }>

local kit = PW.UI --[[@as PW.UILib]]
local lib = PW.Challenges --[[@as PW.ChallengesViewLib?]]
local smallFont = kit and kit.FontName("small") or "DermaDefault"

---@param view PWWeeklyScreen
local function showDetails(view)
    local data, id = view.data, view.selected
    local row = data ~= nil and id ~= nil and data.byId[id] or nil
    view.details:SetText(row ~= nil and "HIDE DETAILS" or "DETAILS")
    view.info:SetVisible(row ~= nil)
    ---@type { [1]: string, [2]: string }[]
    local info = {}
    if row ~= nil then
        for _, requirement in ipairs(row.requirements) do info[#info + 1] = { "REQUIRES", requirement } end
        if row.reward ~= "" then info[#info + 1] = { "REWARD", row.reward } end
        view.info:SetTitle(row.name)
        view.info:SetText(row.description)
        view.info:SetRows(info)
    end
    for slot, bar in ipairs(view.bars) do
        local objective = row ~= nil and row.objectives[slot] or nil
        bar:SetVisible(objective ~= nil)
        if objective ~= nil then
            local scope = objective.scope ~= "" and " · " .. objective.scope or ""
            bar:SetProgress(objective.fraction, objective.label .. scope .. "   " .. objective.progressText)
        end
    end
    view:InvalidateLayout(true)
end

---@param view PWWeeklyScreen
---@param id string
local function toggleDetails(view, id)
    if view.selected == id then view.selected = nil else view.selected = id end
    showDetails(view)
end

---@param view PWWeeklyScreen
---@param row PW.ChallengeRowView
---@param width number
local function paintRow(view, row, width)
    local px, style = kit.Draw.Px, kit.Style
    local x = px(24)
    local tint = row.done and style.accent or (row.tier == "hard" and style.warning or style.accent)
    local text = view.rowText[row.id]
    if text ~= nil then
        draw.SimpleText(text.description, smallFont, x, px(48), style.text_muted)
        draw.SimpleText(text.reward, smallFont, x, px(67), style.text)
    end
    local barWidth = math.max(0, width - px(190))
    kit.Draw.Rect(x, px(89), barWidth, px(4), style.bg_selected)
    kit.Draw.Rect(x, px(89), barWidth * row.fraction, px(4), tint)
    if view.selected == row.id then kit.Draw.Outline(0, 0, width, px(98), style.accent, px(2)) end
end

---@param view PWWeeklyScreen
---@param data? PW.ChallengeWeekView
local function showCards(view, data)
    ---@type PW.UICard[]
    local cards = {}
    if data ~= nil then
        for index, row in ipairs(data.rows) do
            cards[index] = { id = row.id, title = row.name,
                badge = (row.done and "✓  " or "") .. string.upper(row.tier), timer = row.progressText }
        end
    end
    if kit.Store ~= nil then kit.Store.UpdateCards(view.list, cards) else view.list:SetCards(cards) end
    if data == nil then return end
    for index, card in ipairs(view.list.panels) do
        local row = data.rows[index]
        card.DoClick = function() toggleDetails(view, row.id) end
        local panel = card --[[@as PANEL]]
        panel.PaintOver = function(_, width) paintRow(view, row, width) end
    end
end

---@param view PWWeeklyScreen
local function updateClock(view)
    local data = view.data
    if data ~= nil and lib ~= nil then
        view.week:SetTitle(data.weekLabel)
        view.week:SetText(lib._ChallengeCountdown(data.endsAt, os.time()))
    else
        view.week:SetTitle("Weekly challenges")
        view.week:SetText(nil)
    end
    view.nextClock = RealTime() + 30
    view:InvalidateLayout(true)
end

---@param view PWWeeklyScreen
local function refresh(view)
    view.nextRefresh = RealTime() + 2
    local enabled = IsValid(PW.Modules.Get("challenges"))
    local owner = LocalPlayer()
    local data = enabled and lib ~= nil and IsValid(owner) and lib._OwnerChallengeView(PW, owner, os.time()) or nil
    view.data = data
    local key = data and data.label
    if key ~= view.clockLabel or RealTime() >= view.nextClock then
        view.clockLabel = key
        updateClock(view)
    end
    local bonus = data and data.bonus
    local needed = bonus ~= nil and bonus.needed > 0
    view.bonus:SetVisible(needed)
    view.bonusBar:SetVisible(needed)
    view.bonusReward:SetVisible(needed and view.showBonus)
    if bonus ~= nil and needed then
        view.bonus:SetText(string.format("BONUS %d / %d", bonus.completed, bonus.needed))
        view.bonusBar:SetProgress(bonus.fraction, bonus.done and "COMPLETE" or "")
        view.bonusReward:SetText(bonus.reward)
    end
    local hasRows = data ~= nil and #data.rows > 0
    view.empty:SetVisible(not hasRows)
    view.empty:SetText(not enabled and "Weekly challenges are off on this server."
        or (data == nil and "Waiting for the host…" or "No challenges available with the installed content."))
    view.list:SetVisible(hasRows)
    view.details:SetVisible(hasRows)
    if data == nil or (view.selected ~= nil and data.byId[view.selected] == nil) then view.selected = nil end
    showCards(view, data)
    showDetails(view)
end

---@param panel Panel
---@param x number
---@param y number
---@param w number
---@param h number
---@return number
local function box(panel, x, y, w, h)
    panel:SetPos(x, y)
    panel:SetSize(w, h)
    return y + h
end

---@param view PWWeeklyScreen
---@param w number
---@param h number
local function layout(view, w, h)
    local px = kit.Draw.Px
    local columns = kit.Layout.Columns(w, h, { margin = 96, left = 520, right = 560, gap = 40, bottom = 16 }, px)
    local left, centre, right = columns.left --[[@as PW.UIRect]], columns.centre, columns.right --[[@as PW.UIRect]]
    local gap = px(16)
    local y = box(view.week, left.x, left.y, left.w, view.week:WantedHeight(left.w)) + gap
    y = box(view.bonus, left.x, y, left.w, px(64)) + gap
    y = box(view.bonusBar, left.x, y, left.w, px(36)) + gap
    box(view.bonusReward, left.x, y, left.w, view.bonusReward:WantedHeight(left.w))
    box(view.list, centre.x, centre.y, centre.w, centre.h)
    box(view.empty, centre.x, centre.y, centre.w, view.empty:WantedHeight(centre.w))
    y = box(view.details, right.x, right.y, right.w, px(64)) + gap
    y = box(view.info, right.x, y, right.w, view.info:WantedHeight(right.w)) + gap
    for _, bar in ipairs(view.bars) do y = box(bar, right.x, y, right.w, px(38)) + px(8) end
    local data = view.data
    view.rowText = {}
    if data == nil then return end
    local fit = kit.Draw.Fit
    for _, row in ipairs(data.rows) do
        view.rowText[row.id] = { description = fit(row.description, smallFont, math.max(0, centre.w - px(48))),
            reward = fit(row.reward, smallFont, math.max(0, centre.w - px(185))) }
    end
end

function SCREEN:Build(ctx)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWWeeklyScreen]]
    view:Dock(FILL)
    view.week = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.bonus = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.bonusBar = vgui.Create("PWProgressBar", view) --[[@as PWProgressBar]]
    view.bonusReward = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.bonusReward:SetTitle("Bonus reward")
    view.list = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.empty = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.details = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.info = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.bars, view.rowText, view.showBonus, view.nextRefresh, view.nextClock = {}, {}, true, 0, 0
    for slot = 1, 4 do view.bars[slot] = vgui.Create("PWProgressBar", view) --[[@as PWProgressBar]] end
    kit.Focusable(view.bonus, "weekly_bonus", "weekly_bonus")
    kit.Focusable(view.details, "weekly_details", "weekly_details")
    view.bonus.DoClick = function()
        view.showBonus = not view.showBonus
        view.bonusReward:SetVisible(view.showBonus)
    end
    view.details.DoClick = function()
        local focused = view.list.cards[view.list.focusIndex]
        local id = view.selected or (focused and focused.id)
        if id ~= nil then toggleDetails(view, id) end
    end
    local panel = view --[[@as PANEL]]
    panel.PerformLayout = function(_, w, h) layout(view, w, h) end
    panel.Think = function()
        if RealTime() >= view.nextRefresh then refresh(view) end
    end
    hook.Add("PW_ChallengesChanged", view, function() refresh(view) end)
    refresh(view)
    return view
end
