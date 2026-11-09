-- Postmatch summary (T-7.7; 08-lobby.md d.4, d.5; 10-frontend.md d.1 POSTMATCH "result + scoreboard, XP / unlocks
-- summary"). Root of the tab SUMMARY of the postmatch root (ui_kit/cl_postmatch.lua opens it in POSTMATCH and closes
-- it on VOTE or LOBBY). Left: the result banner and the final scoreboard. Right: the player's match: XP gained, the
-- level bar animating from the level before to the level after (a LEVEL UP badge on each level-up), the currency
-- earned, the weapon levels gained and the medals. The data comes from PW.UI.Postmatch.Gather (pure parts in
-- ui_kit/sh_postmatch.lua); this file lays it out and paints it with the kit's tokens. Keys: Up/Down scroll the board,
-- Enter skips the animation, Esc closes, F2 / Start opens the match menu.

SCREEN.Tab = "summary"
SCREEN.Root = true
SCREEN.Title = "Match summary"
SCREEN.Hints = {
    { action = "down", label = "Scroll" }, { action = "accept", label = "Skip" },
    { action = "settings", label = "Match menu" }, { action = "back", label = "Close" }
}

---@class PWPostmatchView : Panel
---@field data PW.UIPostmatchData
---@field banner Panel
---@field scroll DScrollPanel
---@field board PWMatchBoard
---@field xp Panel
---@field weaponsCard PWInfoCard
---@field medalsCard PWInfoCard
---@field started number RealTime when the bar animation started
---@field xpText string
---@field levelText string
---@field shownLevel integer
---@field earnedText? string
---@field earnedAt number RealTime of the last currency refresh
---@field scoreLabel string
---@field OnAction fun(self: PWPostmatchView, action: string)

local timing = { stepTime = 0.9, maxTime = 5, delay = 0.6 }
local rowH = 40
local maxRows = 5

---@return PW.UILib
local function kit()
    return PW.UI --[[@as PW.UILib]]
end

---@return PW.UIStyle
local function style()
    return kit().Style --[[@as PW.UIStyle]]
end

---@param design number
---@return integer
local function px(design)
    return kit().Draw.Px(design)
end

---@param view PWPostmatchView
---@param w number
---@param h number
local function paintBanner(view, w, h)
    local s, result = style(), view.data.result
    kit().Draw.Rect(0, 0, w, h, s.bg_panel)
    kit().Draw.Rect(0, 0, px(6), h, s[result.token] or s.text)
    local x = px(32)
    draw.SimpleText(result.title, kit().FontName("title"), x, h / 2, s[result.token] or s.text, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(result.subtitle, kit().FontName("h1"), w - x, h / 2 - px(14), s.text, TEXT_ALIGN_RIGHT,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(view.data.map, kit().FontName("small"), w - x, h / 2 + px(28), s.text_muted, TEXT_ALIGN_RIGHT,
        TEXT_ALIGN_CENTER)
end

---@param view PWPostmatchView
---@return string? the note shown instead of the bar
local function xpNote(view)
    if not view.data.progression then return "Progression is off on this server." end
    if view.data.summary == nil then return "Waiting for the match summary..." end
    return nil
end

---@param view PWPostmatchView
---@param w number
---@param y number top of the bar row
local function paintBar(view, w, y)
    local s, pad = style(), px(20)
    local frame = kit().Postmatch.BarAt(view.data.steps, RealTime() - view.started, timing)
    if frame.level ~= view.shownLevel then view.shownLevel, view.levelText = frame.level, "LVL " .. frame.level end
    local up = frame.levelUps > 0
    draw.SimpleText(view.levelText, kit().FontName("h2"), pad, y, up and s.accent or s.text, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_TOP)
    if up then
        kit().Draw.Badge("LEVEL UP", kit().FontName("small"), w - pad, y + px(16), s.accent, s.on_accent)
    end
    local barY, barW, barH = y + px(48), w - 2 * pad, px(12)
    kit().Draw.Rect(pad, barY, barW, barH, s.bg_hover)
    kit().Draw.Rect(pad, barY, math.floor(barW * frame.fraction), barH, s.accent)
end

---@param view PWPostmatchView
---@param w number
---@param h number
local function paintXp(view, w, h)
    local s, pad, header = style(), px(20), px(56)
    kit().Draw.Rect(0, 0, w, h, s.bg_panel)
    kit().Draw.Rect(0, 0, w, header, s.bg_raised)
    kit().Draw.Outline(0, 0, w, h, s.border)
    draw.SimpleText("YOUR MATCH", kit().FontName("h2"), pad, header / 2, s.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local y = header + px(16)
    local note = xpNote(view)
    if note ~= nil then
        draw.SimpleText(note, kit().FontName("body"), pad, y, s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    else
        draw.SimpleText(view.xpText, kit().FontName("h1"), pad, y, s.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        paintBar(view, w, y + px(64))
    end
    if view.earnedText ~= nil then
        local cy = h - px(28)
        draw.SimpleText("CURRENCY", kit().FontName("body"), pad, cy, s.text_muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(view.earnedText, kit().FontName("body"), w - pad, cy, s.text, TEXT_ALIGN_RIGHT,
            TEXT_ALIGN_CENTER)
    end
end

---Rows of an info card, at most maxRows (the rest summed up in one row).
---@param card PWInfoCard
---@param title string
---@param list { name: string, text: string }[]
---@param empty string
local function fillCard(card, title, list, empty)
    card:SetTitle(title)
    ---@type { [1]: string, [2]: string }[]
    local rows = {}
    for index, entry in ipairs(list) do
        if index > maxRows then
            rows[maxRows] = { "And " .. (#list - maxRows + 1) .. " more", "" }
            break
        end
        rows[index] = { entry.name, entry.text }
    end
    card:SetRows(rows)
    card:SetText(#list == 0 and empty or nil)
end

---@param view PWPostmatchView
local function fill(view)
    local data = view.data
    view.scoreLabel = data.scoreLabel or "SCORE"
    view.board:SetSections(data.sections, view.scoreLabel)
    local summary = data.summary
    view.xpText = "+" .. kit().Postmatch.Number(summary ~= nil and summary.xp or 0) .. " XP"
    view.started, view.shownLevel, view.levelText = RealTime(), -1, ""
    view.earnedText = data.earned ~= nil and "+" .. kit().Postmatch.Number(data.earned) or nil
    fillCard(view.weaponsCard, "Weapon levels", data.weapons, "No weapon levelled up this match.")
    fillCard(view.medalsCard, "Medals", data.medals, "No medals this match.")
end

---@param view PWPostmatchView
---@param w number
---@param h number
local function layout(view, w, h)
    local columns = kit().Layout.Columns(w, h, { margin = 96, left = 1060, right = 640, gap = 48, bottom = 16 },
        px)
    local left, right = columns.left --[[@as PW.UIRect]], columns.right --[[@as PW.UIRect]]
    local bannerH, gap = px(150), px(16)
    view.banner:SetPos(left.x, left.y)
    view.banner:SetSize(left.w, bannerH)
    view.scroll:SetPos(left.x, left.y + bannerH + gap)
    view.scroll:SetSize(left.w, left.h - bannerH - gap)
    view.board:SetWide(left.w)
    local xpH = px(260)
    view.xp:SetPos(right.x, right.y)
    view.xp:SetSize(right.w, xpH)
    local y = right.y + xpH + gap
    for _, card in ipairs({ view.weaponsCard, view.medalsCard }) do
        local height = math.min(card:WantedHeight(right.w), math.max(0, right.y + right.h - y))
        card:SetPos(right.x, y)
        card:SetSize(right.w, height)
        y = y + height + gap
    end
end

---@param view PWPostmatchView
---@param delta number pixels
local function scrollBy(view, delta)
    local bar = view.scroll:GetVBar()
    bar:SetScroll(bar:GetScroll() + delta)
end

---@param view PWPostmatchView
---@param action string
local function onAction(view, action)
    if action == "accept" then view.started = -math.huge end
    if action == "down" or action == "up" then scrollBy(view, (action == "down" and 1 or -1) * px(rowH * 3)) end
    if action == "page_down" or action == "page_up" then
        scrollBy(view, (action == "page_down" and 1 or -1) * view.scroll:GetTall())
    end
    if action == "settings" then (kit().Postmatch.Pause --[[@as fun()]])() end
end

---@param view PWPostmatchView
---@param name string
---@param paint fun(view: PWPostmatchView, w: number, h: number)
---@param parent? Panel
---@return Panel
local function painted(view, name, paint, parent)
    local panel = vgui.Create("Panel", parent or view) --[[@as Panel]]
    panel:SetName(name)
    local hooks = panel --[[@as PANEL]]
    hooks.Paint = function(_, w, h) paint(view, w, h) end
    return panel
end

function SCREEN:Build(ctx)
    local gather = kit().Postmatch.Gather
    if gather == nil then return nil end
    for _, step in ipairs({ "title", "h1", "h2", "body", "small" }) do kit().Font(step) end
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWPostmatchView]]
    view:Dock(FILL)
    view.data = gather()
    view.banner = painted(view, "PWPostmatchBanner", paintBanner)
    view.scroll = vgui.Create("DScrollPanel", view) --[[@as DScrollPanel]]
    view.board = vgui.Create("PWMatchBoard", view.scroll) --[[@as PWMatchBoard]]
    view.board:SetViewport(view.scroll)
    view.board:Dock(TOP)
    view.xp = painted(view, "PWPostmatchXp", paintXp)
    view.weaponsCard = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.medalsCard = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    fill(view)
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    view.earnedAt = RealTime()
    hooks.Think = function()
        if RealTime() - view.earnedAt < 1 then return end
        view.earnedAt = RealTime()
        local earned = (kit().Postmatch.EarnedNow --[[@as fun(): integer?]])()
        view.earnedText = earned ~= nil and "+" .. kit().Postmatch.Number(earned) or nil
    end
    view.OnAction = function(_, action) onAction(view, action) end
    return view
end
