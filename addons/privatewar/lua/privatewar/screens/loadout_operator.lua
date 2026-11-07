-- OPERATOR picker (06-progression.md d.7; 10-frontend.md d.6). Pushed on the LOADOUT tab by the OPERATOR button of
-- the class screen (screens/loadout_classes.lua); Back returns. Left: Auto, then the store models, then every stock
-- player model (PW.Operators.Cards); locked store models show their price or level. Centre: the focused operator in
-- PWOperator. Right: what the selected card is. Selecting a card stores it in the client setting operators.model,
-- which sends it to the server (operators/cl_init.lua); the lobby operator panel shows it.

SCREEN.Tab = "loadout"
SCREEN.Title = "Operator"
SCREEN.Hints = {
    { action = "accept", label = "Use operator" }, { action = "page_down", label = "Next page" },
    { action = "back", label = "Back" }
}

---@class PWLoadoutOperatorView : Panel
---@field cardList PWCardList
---@field operator PWOperator
---@field details PWInfoCard
---@field entries PW.OperatorEntry[]

---@return PW.OperatorsLib
local function operators()
    return PW.Operators --[[@as PW.OperatorsLib]]
end

---@param view PWLoadoutOperatorView
---@param id string
---@return string path
---@return PW.OperatorEntry? entry
local function pathOf(view, id)
    for _, entry in ipairs(view.entries) do
        if entry.id == id then return entry.path, entry end
    end
    return operators().LocalModel and (operators().LocalModel --[[@as fun(): string]])() or "", nil
end

---@param view PWLoadoutOperatorView
---@param id string
local function preview(view, id)
    local path, entry = pathOf(view, id)
    view.operator:SetOperatorModel(path)
    local details = view.details
    if entry == nil then
        details:SetTitle("Auto")
        details:SetRows({ { "Model", path } })
        details:SetText("Your Garry's Mod player model. Change it in the Garry's Mod player model menu.")
        details:SetWarning(nil)
    else
        details:SetTitle(entry.name)
        details:SetRows({ { "Source", entry.source == "store" and "Store" or "Stock" }, { "Model", entry.path } })
        details:SetText(entry.source == "store" and "A store model: visible to everyone in matches." or nil)
        ---@type string?
        local reason = nil
        for _, card in ipairs(view.cardList.cards) do
            if card.id == id then reason = card.reason end
        end
        details:SetWarning(entry.locked and reason or nil)
    end
    view:InvalidateLayout(true)
end

---Focus and hover show the card's operator, also a locked one (it cannot be selected).
---@param view PWLoadoutOperatorView
local function wirePreview(view)
    for _, panel in ipairs(view.cardList.panels) do
        local base = panel.PWOnFocus
        panel.PWOnFocus = function(card)
            base(card)
            preview(view, card.view.card.id)
        end
        local hooks = panel --[[@as PANEL]]
        hooks.OnCursorEntered = function() preview(view, panel.view.card.id) end
    end
end

---@param view PWLoadoutOperatorView
local function refresh(view)
    local lib = operators()
    view.entries = lib.LocalList ~= nil and (lib.LocalList --[[@as fun(): PW.OperatorEntry[] ]])() or {}
    local choice = lib.LocalChoice ~= nil and (lib.LocalChoice --[[@as fun(): string]])() or lib.Auto
    local own = GetConVar("cl_playermodel")
    local cards, selected = lib.Cards(view.entries, choice, own ~= nil and own:GetString() or nil)
    view.cardList:SetCards(cards, selected)
    wirePreview(view)
    preview(view, selected)
end

---@param view PWLoadoutOperatorView
---@param w number
---@param h number
local function layout(view, w, h)
    local kit = PW.UI --[[@as PW.UILib]]
    local px = kit.Draw.Px
    local columns = kit.Layout.Columns(w, h, { margin = 96, left = 480, right = 520, gap = 48, bottom = 16 }, px)
    local left, centre, right = columns.left --[[@as PW.UIRect]], columns.centre, columns.right --[[@as PW.UIRect]]
    view.cardList:SetPos(left.x, left.y)
    view.cardList:SetSize(left.w, left.h)
    view.operator:SetPos(centre.x, centre.y)
    view.operator:SetSize(centre.w, centre.h)
    view.details:SetPos(right.x, right.y)
    view.details:SetSize(right.w, math.min(view.details:WantedHeight(right.w), right.h))
end

function SCREEN:Build(ctx)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWLoadoutOperatorView]]
    view:Dock(FILL)
    view.entries = {}
    view.cardList = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.cardList.OnSelect = function(_, id)
        local lib = operators()
        if lib.Choose ~= nil then (lib.Choose --[[@as fun(choice: string): boolean]])(id) end
        preview(view, id)
    end
    view.operator = vgui.Create("PWOperator", view) --[[@as PWOperator]]
    view.details = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    view.PWRefresh = function() end
    refresh(view)
    return view
end
