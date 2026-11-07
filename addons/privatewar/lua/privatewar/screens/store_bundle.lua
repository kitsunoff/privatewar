-- Bundle details, pushed on the STORE tab (T-7.5; 06-progression.md d.6; 10-frontend.md d.1 "-> bundle details").
-- Left: the items of the bundle as cards (OWNED, UNLOCKED). Centre: the preview of the selected item (a model through
-- PWOperator, a card through its material). Right: the bundle (price, rarity, items owned, time left in the rotation)
-- and BUY with a confirm dialog; the server's answer is shown under it. Esc goes back to the store. Opened through
-- PW.UI.Store.OpenBundle(key); thin glue over PW.UI.Store (sh_store.lua, cl_store.lua).

SCREEN.Tab = "store"
SCREEN.Title = "Bundle"
SCREEN.Hints = {
    { action = "accept", label = "Preview" }, { action = "tertiary", label = "Buy" },
    { action = "back", label = "Back" }
}

---@class PWStoreBundleView : Panel
---@field key? string
---@field itemList PWCardList
---@field preview PWStorePreview
---@field info PWInfoCard
---@field buy PWButton
---@field items PW.UIStoreItem[]
---@field item? string the selected item key
---@field nextTick number
---@field OnAction fun(self: PWStoreBundleView, action: string)

---@return PW.UIStoreLib
local function store()
    return PW.UI.Store --[[@as PW.UIStoreLib]]
end

---@param view PWStoreBundleView
---@return PW.EconomyOffer?, PW.EconomyStoreView?
local function offerOf(view)
    local economy = rawget(PW, "Economy") --[[@as PW.EconomyLib?]]
    if economy == nil or view.key == nil then return nil, nil end
    return economy.GetOffer(view.key --[[@as string]]), economy.GetStore()
end

---@param view PWStoreBundleView
local function showItem(view)
    for _, item in ipairs(view.items) do
        if item.key == view.item then
            local subtitle = item.label .. (item.state == "owned" and "  -  owned" or "")
            return view.preview:SetPreview(item.preview, item.name, subtitle)
        end
    end
    view.preview:SetPreview(nil, "", "")
end

---@param view PWStoreBundleView
---@param offer PW.EconomyOffer
---@param data PW.EconomyStoreView
local function showInfo(view, offer, data)
    local facts = store().LiveFacts()
    local rotation = store().RotationOf(data, offer.key)
    view.info:SetTitle(offer.name)
    view.info:SetRows(store().BundleRows(offer, view.items, rotation, os.time()))
    local message = (store()._purchase --[[@as PW.UIStorePurchase]]).message
    local text = rotation == nil and "This bundle is not in the rotation now: it cannot be bought." or nil
    view.info:SetText(message ~= nil and message.ok and message.text or text)
    view.info:SetWarning(message ~= nil and not message.ok and message.text or nil)
    local button = store().BuyButton(offer, store().OfferState(offer, facts), facts.currency)
    view.buy:SetText(button.label)
    view.buy:SetLocked(button.locked or rotation == nil, rotation == nil and "Not in the rotation" or button.reason)
end

---@param view PWStoreBundleView
local function refresh(view)
    local offer, data = offerOf(view)
    if offer == nil or data == nil or not offer.bundle then
        view.items = {}
        view.itemList:SetCards({}, nil)
        view.info:SetTitle("Bundle not available")
        view.info:SetRows({})
        view.info:SetText("The bundle is no longer sold. Press Esc to go back.")
        view.buy:SetLocked(true, "Not available")
        return
    end
    view.items = store().ItemViews(offer, store().LiveLookup(), store().LiveFacts())
    view.item = view.item or (view.items[1] ~= nil and view.items[1].key or nil)
    store().UpdateCards(view.itemList, store().ItemCards(view.items), view.item)
    showItem(view)
    showInfo(view, offer, data)
    view:InvalidateLayout(true)
end

---@param view PWStoreBundleView
local function buy(view)
    local offer, data = offerOf(view)
    if offer == nil or data == nil or store().RotationOf(data, offer.key) == nil then return end
    if store().OfferState(offer, store().LiveFacts()) ~= "buyable" then return end
    store().ConfirmBuy(offer, function() if IsValid(view) then refresh(view) end end)
end

---@param view PWStoreBundleView
---@param w number
---@param h number
local function layout(view, w, h)
    local kit = PW.UI --[[@as PW.UILib]]
    local px = kit.Draw.Px
    local columns = kit.Layout.Columns(w, h, { margin = 96, left = 480, right = 520, gap = 40, bottom = 16 }, px)
    local left, centre, right = columns.left --[[@as PW.UIRect]], columns.centre, columns.right --[[@as PW.UIRect]]
    view.itemList:SetPos(left.x, left.y)
    view.itemList:SetSize(left.w, left.h)
    view.preview:SetPos(centre.x, centre.y)
    view.preview:SetSize(centre.w, centre.h)
    local buttonH = px(64)
    view.info:SetPos(right.x, right.y)
    view.info:SetSize(right.w, math.min(view.info:WantedHeight(right.w), right.h - buttonH - px(20)))
    view.buy:SetPos(right.x, right.y + right.h - buttonH)
    view.buy:SetSize(right.w, buttonH)
end

function SCREEN:Build(ctx)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWStoreBundleView]]
    view:Dock(FILL)
    view.key, view.items, view.nextTick = store().TakeBundle(), {}, 0
    view.itemList = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.itemList.OnSelect = function(_, key)
        view.item = key
        showItem(view)
    end
    view.preview = vgui.Create("PWStorePreview", view) --[[@as PWStorePreview]]
    view.info = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.buy = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.buy:SetPrimary(true)
    view.buy.DoClick = function() buy(view) end
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.Think = function()
        store().Tick()
        if RealTime() < view.nextTick then return end
        view.nextTick = RealTime() + 1
        refresh(view)
    end
    view.PWRefresh = function() refresh(view) end
    view.OnAction = function(_, action)
        if action == "tertiary" then buy(view) end
    end
    refresh(view)
    return view
end
