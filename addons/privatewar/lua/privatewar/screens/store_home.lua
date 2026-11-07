-- The store, root of the STORE tab (T-7.5; 06-progression.md d.6; 10-frontend.md d.1 "STORE: Featured | Weekly |
-- Catalogue -> bundle details"). Left: the balance and the sections (FEATURED and WEEKLY with the countdown to their
-- rotation, then the permanent offers by kind: models, calling cards, camos, others). Centre: the offers of the
-- selected section as cards (price, OWNED, UNLOCKED). Right: a preview (a model, a card material), the details and
-- BUY; a bundle also has DETAILS (or Enter on the selected bundle card). BUY opens a confirm dialog and sends
-- PW.Economy.RequestBuy; the server's answer (PW_EconomyResult) is shown under the details. Thin glue over
-- PW.UI.Store (ui_kit/sh_store.lua, cl_store.lua); the server quotes every purchase again.

SCREEN.Tab = "store"
SCREEN.Root = true
SCREEN.Order = 10
SCREEN.Title = "Store"
SCREEN.Hints = {
    { action = "accept", label = "Select" }, { action = "secondary", label = "Bundle details" },
    { action = "tertiary", label = "Buy" }
}

---@class PWStoreHomeView : Panel
---@field wallet PWInfoCard
---@field sectionList PWCardList
---@field offerList PWCardList
---@field preview PWStorePreview
---@field details PWInfoCard
---@field detailsButton PWButton
---@field buy PWButton
---@field sections PW.UIStoreSection[]
---@field section? string the selected section id
---@field offer? string the selected offer key
---@field date? string the store date the sections were built for
---@field nextTick number RealTime of the next countdown refresh
---@field OnAction fun(self: PWStoreHomeView, action: string)

---@return PW.UIStoreLib
local function store()
    return PW.UI.Store --[[@as PW.UIStoreLib]]
end

---@param view PWStoreHomeView
---@return PW.UIStoreSection?
local function sectionOf(view)
    for _, section in ipairs(view.sections) do
        if section.id == view.section then return section end
    end
    return nil
end

---@param view PWStoreHomeView
---@return PW.EconomyOffer?
local function offerOf(view)
    local section = sectionOf(view)
    for _, offer in ipairs(section ~= nil and section.offers or {}) do
        if offer.key == view.offer then return offer end
    end
    return nil
end

---@param view PWStoreHomeView
---@param offer? PW.EconomyOffer
local function showPreview(view, offer)
    if offer == nil then return view.preview:SetPreview(nil, "", "") end
    local entity = store().LiveLookup()(offer.kind, offer.id)
    local preview = store().Preview(offer.kind, entity)
    if offer.bundle then
        local items = store().ItemViews(offer, store().LiveLookup(), store().LiveFacts())
        for _, item in ipairs(items) do preview = preview or item.preview end
    end
    view.preview:SetPreview(preview, offer.name, offer.bundle and "Bundle" or store().KindLabel(offer.kind))
end

---@param view PWStoreHomeView
local function showDetails(view)
    local offer, facts = offerOf(view), store().LiveFacts()
    local purchase = store()._purchase --[[@as PW.UIStorePurchase]]
    local message = purchase.message
    view.details:SetWarning(message ~= nil and not message.ok and message.text or nil)
    view.detailsButton:SetVisible(offer ~= nil and offer.bundle)
    if offer == nil then
        view.details:SetTitle(#view.sections == 0 and "The store is empty" or "Nothing selected")
        view.details:SetRows({})
        view.details:SetText(message ~= nil and message.ok and message.text or "Pick an offer in the middle column.")
        view.buy:SetText("BUY")
        view.buy:SetLocked(true, "Pick an offer first")
        return
    end
    local state = store().OfferState(offer, facts)
    view.details:SetTitle(offer.name)
    ---@type { [1]: string, [2]: string }[]
    local rows = { { "PRICE", store().PriceText(offer.price) } }
    if offer.rarity ~= nil then rows[#rows + 1] = { "RARITY", string.upper(offer.rarity) } end
    if offer.bundle then rows[#rows + 1] = { "ITEMS", tostring(#offer.items) } end
    view.details:SetRows(rows)
    view.details:SetText(message ~= nil and message.ok and message.text or nil)
    local button = store().BuyButton(offer, state, facts.currency)
    view.buy:SetText(button.label)
    view.buy:SetLocked(button.locked, button.reason)
end

---@param list PWCardList
---@param index integer
---@param id string
local function wireBundle(list, index, id)
    list.panels[index].DoClick = function()
        if list.selected == id then return store().OpenBundle(id) end
        list:Activate(index)
    end
end

---Bundle cards: Enter (or a click) on the selected bundle opens its details.
---@param view PWStoreHomeView
local function wireBundles(view)
    for index, card in ipairs(view.offerList.cards) do
        if string.sub(card.id, 1, 8) == "bundles:" then wireBundle(view.offerList, index, card.id) end
    end
end

---@param view PWStoreHomeView
local function refresh(view)
    local economy = rawget(PW, "Economy") --[[@as PW.EconomyLib?]]
    local data = economy ~= nil and economy.GetStore() or { date = "", permanent = {}, featured = {}, weekly = {} }
    local facts = store().LiveFacts()
    view.sections = store().Sections(data, facts, os.time())
    if sectionOf(view) == nil then view.section = view.sections[1] ~= nil and view.sections[1].id or nil end
    if view.date ~= data.date then view.offer = nil end
    view.date = data.date
    store().UpdateCards(view.sectionList, store().SectionCards(view.sections), view.section)
    local section = sectionOf(view)
    if offerOf(view) == nil then
        local first = section ~= nil and section.offers[1] or nil
        view.offer = first ~= nil and first.key or nil
    end
    store().UpdateCards(view.offerList, section ~= nil and section.cards or {}, view.offer)
    wireBundles(view)
    view.wallet:SetTitle("Wallet")
    view.wallet:SetRows({ { "BALANCE", store().PriceText(facts.currency) } })
    view.wallet:SetText(economy == nil and "The economy module is off: nothing is sold." or nil)
    showPreview(view, offerOf(view))
    showDetails(view)
    view:InvalidateLayout(true)
end

---@param view PWStoreHomeView
local function buy(view)
    local offer = offerOf(view)
    if offer == nil then return end
    if store().OfferState(offer, store().LiveFacts()) ~= "buyable" then return end
    store().ConfirmBuy(offer, function() if IsValid(view) then refresh(view) end end)
end

---@param view PWStoreHomeView
local function fill(view)
    view.wallet = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.sectionList = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.sectionList.OnSelect = function(_, id)
        view.section, view.offer = id, nil
        refresh(view)
    end
    view.offerList = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.offerList.OnSelect = function(_, key)
        local purchase = store()._purchase --[[@as PW.UIStorePurchase]]
        view.offer, purchase.message = key, nil
        showPreview(view, offerOf(view))
        showDetails(view)
        view:InvalidateLayout(true)
    end
    view.preview = vgui.Create("PWStorePreview", view) --[[@as PWStorePreview]]
    view.details = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.detailsButton = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.detailsButton:SetText("DETAILS")
    view.detailsButton:SetVariant("secondary")
    view.detailsButton.DoClick = function()
        if view.offer ~= nil and offerOf(view) ~= nil and (offerOf(view) --[[@as PW.EconomyOffer]]).bundle then
            store().OpenBundle(view.offer --[[@as string]])
        end
    end
    view.buy = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.buy:SetPrimary(true)
    view.buy.DoClick = function() buy(view) end
    for _, button in ipairs({ view.detailsButton, view.buy }) do
        local spec = PW.UI.Focusable(button, "store_buttons")
        spec.axis = "horizontal"
    end
end

---@param view PWStoreHomeView
---@param right PW.UIRect
---@param px fun(n: number): integer
local function layoutRight(view, right, px)
    local gap, buttonH = px(20), px(64)
    local buttonsY = right.y + right.h - buttonH
    local detailsH = view.details:WantedHeight(right.w)
    local previewH = math.max(px(160), buttonsY - gap - detailsH - gap - right.y)
    view.preview:SetPos(right.x, right.y)
    view.preview:SetSize(right.w, previewH)
    view.details:SetPos(right.x, right.y + previewH + gap)
    view.details:SetSize(right.w, math.min(detailsH, buttonsY - gap - right.y - previewH - gap))
    local detailsW = view.detailsButton:IsVisible() and math.floor((right.w - gap) * 0.4) or 0
    view.detailsButton:SetPos(right.x, buttonsY)
    view.detailsButton:SetSize(math.max(1, detailsW), buttonH)
    local buyX = right.x + (detailsW > 0 and detailsW + gap or 0)
    view.buy:SetPos(buyX, buttonsY)
    view.buy:SetSize(right.x + right.w - buyX, buttonH)
end

---@param view PWStoreHomeView
---@param w number
---@param h number
local function layout(view, w, h)
    local kit = PW.UI --[[@as PW.UILib]]
    local px = kit.Draw.Px
    local columns = kit.Layout.Columns(w, h, { margin = 96, left = 440, right = 560, gap = 40, bottom = 16 }, px)
    local left, centre = columns.left --[[@as PW.UIRect]], columns.centre
    local walletH = view.wallet:WantedHeight(left.w)
    view.wallet:SetPos(left.x, left.y)
    view.wallet:SetSize(left.w, walletH)
    view.sectionList:SetPos(left.x, left.y + walletH + px(20))
    view.sectionList:SetSize(left.w, left.h - walletH - px(20))
    view.offerList:SetPos(centre.x, centre.y)
    view.offerList:SetSize(centre.w, centre.h)
    layoutRight(view, columns.right --[[@as PW.UIRect]], px)
end

function SCREEN:Build(ctx)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWStoreHomeView]]
    view:Dock(FILL)
    view.sections, view.nextTick = {}, 0
    fill(view)
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.Think = function()
        store().Tick()
        if RealTime() < view.nextTick then return end
        view.nextTick = RealTime() + 1 -- the countdowns, the balance and a new day's rotation
        refresh(view)
    end
    view.PWRefresh = function() refresh(view) end
    view.OnAction = function(_, action)
        if action == "secondary" then view.detailsButton:DoClick() end
        if action == "tertiary" then buy(view) end
    end
    refresh(view)
    return view
end
