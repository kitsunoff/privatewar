-- Store and progress, client glue (T-7.5; 06-progression.md d.6; 10-frontend.md d.1). The rules are pure (sh_store.lua,
-- sh_progress.lua); this file reads the engine for them and keeps the client side of the Buy flow:
-- - LiveFacts, LiveLookup, LiveCatalogue: the local player's balance, purchases and unlocks, and the registries;
-- - one purchase state shared by the store screens (store_home, store_bundle), answered by PW_EconomyResult; the
--   answer redraws the open screen (its view's PWRefresh);
-- - OpenBundle / TakeBundle: the bundle the details screen shows;
-- - UpdateCards: refreshes a PWCardList in place when the card ids did not change (the focus survives);
-- - PWStorePreview (a model through PWOperator, a card through its material, else the name) and PWProgressBar.

local lib = PW.UI --[[@as PW.UILib]]
local store = lib.Store --[[@as PW.UIStoreLib]]
local paint = lib.Draw
local fontH2, fontBody = lib.FontName("h2"), lib.FontName("body")

---@return PW.UIStyle
local function style()
    return lib.Style --[[@as PW.UIStyle]]
end

local purchase = store._purchase or store.NewPurchase() -- kept across a reload of this file
store._purchase = purchase

function store.LiveCatalogue()
    ---@type PW.EconomyCatalogue
    local catalogue = {}
    local registries = rawget(PW, "Registries") or {} --[[@as table<string, PW.Registry>]]
    for kind, registry in pairs(registries) do
        ---@type table<string, table<string, any>>
        local entities = {}
        for _, entity in ipairs(registry.GetEnabledList()) do
            entities[entity.ClassName] = entity
        end
        catalogue[kind] = entities
    end
    return catalogue
end

function store.LiveLookup()
    local catalogue = store.LiveCatalogue()
    return function(kind, id)
        local entities = catalogue[kind]
        return entities ~= nil and entities[id] or nil
    end
end

function store.LiveFacts()
    local me = LocalPlayer()
    local progression = rawget(PW, "Progression") --[[@as PW.ProgressionLib?]]
    local pending = purchase.pending
    if not IsValid(me) or progression == nil then
        return { currency = 0, owned = function() return false end, unlocked = function() return false end,
            pending = pending }
    end
    local lib_ = progression --[[@as PW.ProgressionLib]]
    return {
        currency = lib_.GetCurrency(me),
        owned = function(key) return lib_.IsOwned(me, key) end,
        unlocked = function(kind, id) return lib_.IsUnlocked(me, kind, id) end,
        pending = pending
    }
end

function store.OpenBundle(key)
    local root = lib.CurrentRoot() --[[@as PWRoot?]]
    if root == nil then return end
    store._bundle = key
    if lib.Router.Push(root.model, "store_bundle") then root:Rebuild() end
end

function store.TakeBundle()
    return store._bundle
end

function store.Buy(offer)
    local economy = rawget(PW, "Economy") --[[@as PW.EconomyLib?]]
    if economy == nil or economy.RequestBuy == nil then return false end
    local state = store.OfferState(offer, store.LiveFacts())
    return store.Request(purchase, offer, state, economy.RequestBuy, RealTime())
end

function store.ConfirmBuy(offer, done)
    local facts = store.LiveFacts()
    local after = store.PriceText(math.max(0, facts.currency - offer.price))
    lib.OpenDialog({
        title = "Buy " .. offer.name,
        text = string.format("Spend %s on %s? Your balance after the purchase: %s.", store.PriceText(offer.price),
            offer.name, after),
        confirm = "BUY",
        onConfirm = function()
            store.Buy(offer)
            if done ~= nil then done() end
        end
    })
end

---Redraws the open screen from the current data.
local function redraw()
    local root = lib.CurrentRoot() --[[@as PWRoot?]]
    local view = root ~= nil and root.view or nil
    if view ~= nil and IsValid(view) and view.PWRefresh ~= nil then view:PWRefresh() end
end

function store.Tick()
    if store.Expire(purchase, RealTime()) then redraw() end
end

hook.Add("PW_EconomyResult", "PW_UI_Store", function(result)
    local economy = rawget(PW, "Economy") --[[@as PW.EconomyLib?]]
    local offer = economy ~= nil and economy.GetOffer(result.key) or nil
    store.OnResult(purchase, result, offer ~= nil and offer.name or result.key)
    redraw()
end)

function store.UpdateCards(panel, cards, selected)
    local list = panel --[[@as PWCardList]]
    local same = #cards == #list.cards
    for index, card in ipairs(cards) do
        if not same or list.cards[index].id ~= card.id then same = false end
    end
    if not same then return list:SetCards(cards, selected) end
    list.cards, list.selected = cards, selected
    list:Refresh()
end

-- PWStorePreview ----------------------------------------------------------------------------------------------------

---@class PWStorePreview : Panel
---@field operator PWOperator
---@field preview? PW.UIStorePreview
---@field material? IMaterial
---@field _title string
---@field _subtitle string
local previewClass = {}

function previewClass:Init()
    self._title, self._subtitle = "", ""
    self.operator = vgui.Create("PWOperator", self) --[[@as PWOperator]]
    self.operator:SetVisible(false)
end

function previewClass:SetPreview(preview, title, subtitle)
    self.preview, self._title, self._subtitle = preview, string.upper(title or ""), subtitle or ""
    local model = preview ~= nil and preview.type == "model"
    self.operator:SetVisible(model)
    if model then self.operator:SetOperatorModel(preview.path) end
    self.material = nil
    if preview ~= nil and preview.type == "material" then
        local material = Material(preview.path, "smooth")
        if not material:IsError() then self.material = material end
    end
end

function previewClass:PerformLayout(w, h)
    self.operator:SetPos(0, 0)
    self.operator:SetSize(w, h - paint.Px(72))
end

---@param w number
---@param h number
function previewClass:Paint(w, h)
    local s = style()
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Outline(0, 0, w, h, s.border)
    local material = self.material
    if material ~= nil then
        local size = math.min(w, h - paint.Px(72)) * 0.6
        surface.SetMaterial(material)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(math.floor((w - size) / 2), math.floor((h - paint.Px(72) - size) / 2), size, size)
    elseif self.preview == nil then
        draw.SimpleText("NO PREVIEW", fontBody, w / 2, (h - paint.Px(72)) / 2, s.text_disabled, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
    paint.Rect(0, h - paint.Px(72), w, paint.Px(72), s.bg_raised)
    draw.SimpleText(paint.Fit(self._title, fontH2, w - paint.Px(40)), fontH2, paint.Px(20), h - paint.Px(52), s.text,
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(self._subtitle, fontBody, paint.Px(20), h - paint.Px(20), s.text_muted, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
    return true
end

vgui.Register("PWStorePreview", previewClass, "Panel")

-- PWProgressBar -----------------------------------------------------------------------------------------------------

---@class PWProgressBar : Panel
---@field fraction number
---@field label string
local barClass = {}

function barClass:Init()
    self.fraction, self.label = 0, ""
end

function barClass:SetProgress(fraction, label)
    self.fraction, self.label = math.Clamp(fraction, 0, 1), label or ""
end

---@param w number
---@param h number
function barClass:Paint(w, h)
    local s = style()
    paint.Rect(0, 0, w, h, s.bg_panel)
    paint.Rect(0, 0, math.floor(w * self.fraction), h, s.accent)
    paint.Outline(0, 0, w, h, s.border_strong)
    if self.label ~= "" then
        draw.SimpleText(self.label, fontBody, w / 2, h / 2, s.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return true
end

vgui.Register("PWProgressBar", barClass, "Panel")
