-- Store view model (T-7.5; 06-progression.md d.6; 10-frontend.md d.1 "STORE: Featured | Weekly | Catalogue -> bundle
-- details"). Pure and shared, so the server-side test runner covers it: the sections of the store (the daily and the
-- weekly bundles with the countdown to their rotation, then the permanent offers grouped by kind), the state of an
-- offer for the local player (in the order the server's quote checks it), the cards, the Buy button and the Buy flow
-- (one request in flight, a text for every answer, a timeout), and the bundle details (items, previews, info rows).
-- The screens are screens/store_home.lua and store_bundle.lua; the data is PW.Economy.GetStore and the progression
-- wallet. The client decides nothing: the server quotes every purchase again.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

local store = (rawget(lib, "Store") or {}) --[[@as PW.UIStoreLib]]
lib.Store = store

store.Currency = "CR"
store.RequestTimeout = 5
store.KindOrder = { "models", "cards", "camos" }

local day = 86400
local epochMonday = 4 -- 1970-01-05, the first Monday, is day 4 (the economy rotation uses the same week)

---@type table<string, { [1]: string, [2]: string }>
local kindLabels = {
    models = { "Model", "Models" }, cards = { "Calling card", "Calling cards" }, camos = { "Camo", "Camos" },
    perks = { "Perk", "Perks" }, equipment = { "Equipment", "Equipment" }, streaks = { "Killstreak", "Killstreaks" },
    weapons = { "Weapon", "Weapons" }, wildcards = { "Wildcard", "Wildcards" },
    attachments = { "Attachment", "Attachments" }, bundles = { "Bundle", "Bundles" }
}

---@type table<PW.UIStoreState, string>
local stateFooters = {
    buyable = "On sale", funds = "Not enough credits", owned = "Owned", unlocked = "Unlocked by your level",
    pending = "Waiting for the server"
}

---@param text string
---@return string
local function capitalise(text)
    return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

function store.FormatNumber(value)
    local text = tostring(math.floor(math.max(0, value)))
    local out = string.reverse(text):gsub("(%d%d%d)", "%1,")
    out = string.reverse(out)
    if string.sub(out, 1, 1) == "," then out = string.sub(out, 2) end
    return out
end

function store.PriceText(price)
    return store.FormatNumber(price) .. " " .. store.Currency
end

function store.KindLabel(kind, plural)
    local labels = kindLabels[kind]
    if labels == nil then return capitalise(kind) end
    return plural and labels[2] or labels[1]
end

function store.SecondsToRotation(now, period)
    local today = math.floor(now / day)
    if period == "daily" then return (today + 1) * day - now end
    local week = math.floor((today - epochMonday) / 7)
    return (epochMonday + (week + 1) * 7) * day - now
end

function store.CountdownText(seconds)
    local left = math.ceil(math.max(0, seconds))
    local days, hours = math.floor(left / day), math.floor(left % day / 3600)
    local minutes, secs = math.floor(left % 3600 / 60), left % 60
    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %02dm", hours, minutes) end
    return string.format("%dm %02ds", minutes, secs)
end

---@param offer PW.EconomyOffer
---@param facts PW.UIStoreFacts
---@return boolean
local function ownedOffer(offer, facts)
    if facts.owned(offer.key) then return true end
    if not offer.bundle or #offer.items == 0 then return false end
    for _, entry in ipairs(offer.items) do
        if not facts.owned(entry.key) then return false end
    end
    return true
end

function store.OfferState(offer, facts)
    if facts.pending == offer.key then return "pending" end
    if ownedOffer(offer, facts) then return "owned" end
    if not offer.bundle and facts.unlocked(offer.kind, offer.id) then return "unlocked" end
    if offer.price > facts.currency then return "funds" end
    return "buyable"
end

---@param offer PW.EconomyOffer
---@return string
local function tagsOf(offer)
    local rarity = offer.rarity ~= nil and capitalise(offer.rarity) or nil
    if offer.bundle then
        local count = #offer.items
        local items = string.format("%d item%s", count, count == 1 and "" or "s")
        return (rarity ~= nil and rarity .. " bundle" or "Bundle") .. ", " .. items
    end
    local label = store.KindLabel(offer.kind)
    if rarity == nil then return label end
    return rarity .. " " .. string.lower(label)
end

---@param state PW.UIStoreState
---@param price number
---@return string
local function badgeOf(state, price)
    if state == "owned" then return "OWNED" end
    if state == "unlocked" then return "UNLOCKED" end
    if state == "pending" then return "..." end
    return store.PriceText(price)
end

function store.OfferCards(offers, facts)
    ---@type PW.UICard[]
    local cards = {}
    for index, offer in ipairs(offers) do
        local state = store.OfferState(offer, facts)
        cards[index] = {
            id = offer.key, title = offer.name, badge = badgeOf(state, offer.price), tags = tagsOf(offer),
            footer = stateFooters[state], locked = false
        }
    end
    return cards
end

---@param id string
---@param title string
---@param offers PW.EconomyOffer[]
---@param facts PW.UIStoreFacts
---@return PW.UIStoreSection
local function sectionOf(id, title, offers, facts)
    return { id = id, title = title, offers = offers, cards = store.OfferCards(offers, facts), empty = #offers == 0 }
end

---The permanent offers by kind: the kinds of KindOrder first, then the others by name.
---@param offers PW.EconomyOffer[]
---@return string[], table<string, PW.EconomyOffer[]>
local function groupByKind(offers)
    ---@type table<string, PW.EconomyOffer[]>
    local groups = {}
    ---@type string[]
    local others = {}
    for _, offer in ipairs(offers) do
        local group = groups[offer.kind]
        if group == nil then
            group = {}
            groups[offer.kind] = group
            if not table.HasValue(store.KindOrder, offer.kind) then others[#others + 1] = offer.kind end
        end
        group[#group + 1] = offer
    end
    table.sort(others)
    ---@type string[]
    local kinds = {}
    for _, kind in ipairs(store.KindOrder) do
        if groups[kind] ~= nil then kinds[#kinds + 1] = kind end
    end
    for _, kind in ipairs(others) do kinds[#kinds + 1] = kind end
    return kinds, groups
end

function store.Sections(view, facts, now)
    ---@type PW.UIStoreSection[]
    local sections = {}
    for _, rotation in ipairs({ { "featured", "Featured", "daily" }, { "weekly", "Weekly", "weekly" } }) do
        local section = sectionOf(rotation[1], rotation[2], view[rotation[1]] or {}, facts)
        section.countdown = store.CountdownText(store.SecondsToRotation(now, rotation[3]))
        if section.empty then section.note = "No bundles in the rotation" end
        sections[#sections + 1] = section
    end
    local kinds, groups = groupByKind(view.permanent or {})
    for _, kind in ipairs(kinds) do
        sections[#sections + 1] = sectionOf("kind:" .. kind, store.KindLabel(kind, true), groups[kind], facts)
    end
    return sections
end

function store.SectionCards(sections)
    ---@type PW.UICard[]
    local cards = {}
    for index, section in ipairs(sections) do
        local card = { id = section.id, title = section.title, locked = false } ---@type PW.UICard
        if section.countdown ~= nil then
            card.badge = section.countdown
            card.text = section.note or ("New bundles in " .. section.countdown)
        else
            card.badge = tostring(#section.offers)
        end
        cards[index] = card
    end
    return cards
end

---@type table<PW.UIStoreState, string>
local lockReasons = {
    owned = "You own this item", unlocked = "Your level already unlocks this item",
    pending = "Waiting for the server"
}

function store.BuyButton(offer, state, currency)
    local price = store.PriceText(offer.price)
    if state == "buyable" then return { label = "BUY  " .. price, locked = false } end
    local reason = lockReasons[state]
    if state == "funds" then
        reason = string.format("Not enough credits: %s needed, %s held", price, store.PriceText(currency))
    end
    return { label = "BUY  " .. price, locked = true, reason = reason }
end

-- Buy flow ---------------------------------------------------------------------------------------------------------

function store.NewPurchase()
    return {}
end

function store.Request(purchase, offer, state, send, now)
    if purchase.pending ~= nil or state ~= "buyable" then return false end
    purchase.pending, purchase.sentAt, purchase.message = offer.key, now, nil
    send(offer.key)
    return true
end

---@type table<string, string>
local resultTexts = {
    badkey = "The server rejected the request", unknown = "%s is not sold any more",
    notoffered = "%s has left the rotation", owned = "You already own %s",
    unlocked = "Your level already unlocks %s", funds = "Not enough credits for %s (balance %s)"
}

function store.ResultText(result, name)
    if result.ok then return string.format("Bought %s. Balance: %s", name, store.PriceText(result.currency)) end
    local text = resultTexts[result.reason]
    if text == nil then return "Purchase failed: " .. tostring(result.reason) end
    if result.reason == "badkey" then return text end
    return (string.format(text, name, store.PriceText(result.currency)))
end

function store.OnResult(purchase, result, name)
    ---@type PW.UIStoreMessage
    local message = { ok = result.ok == true, text = store.ResultText(result, name) }
    purchase.pending, purchase.sentAt, purchase.message = nil, nil, message
    return message
end

function store.Expire(purchase, now)
    if purchase.pending == nil or purchase.sentAt == nil then return false end
    if now - purchase.sentAt < store.RequestTimeout then return false end
    purchase.pending, purchase.sentAt = nil, nil
    purchase.message = { ok = false, text = "No answer from the server" }
    return true
end

-- Bundle details ---------------------------------------------------------------------------------------------------

function store.Preview(kind, entity)
    if entity == nil then return nil end
    if kind == "models" and isstring(entity.Model) then return { type = "model", path = entity.Model } end
    if kind == "cards" and isstring(entity.Material) then return { type = "material", path = entity.Material } end
    return nil
end

---@param entity? table<string, any>
---@param fallback string
---@return string
local function nameOf(entity, fallback)
    if entity ~= nil and isstring(entity.Name) then return entity.Name --[[@as string]] end
    return fallback
end

---The display name and the entity of an item; a camo ("<weapon>:<camo>") reads the weapon's Camos.
---@param entry PW.EconomyItem
---@param lookup PW.LoadoutLookup
---@return string, table<string, any>?
local function describe(entry, lookup)
    if entry.kind ~= "camos" then
        local entity = lookup(entry.kind, entry.id)
        return nameOf(entity, entry.id), entity
    end
    local weaponId, camoId = string.match(entry.id, "^([^:]+):(.+)$")
    if weaponId == nil or camoId == nil then return entry.id, nil end
    local weapon = lookup("weapons", weaponId)
    local camos = weapon ~= nil and istable(weapon.Camos) and weapon.Camos --[[@as table<string, any>]] or {}
    local camo = istable(camos[camoId]) and camos[camoId] --[[@as table<string, any>]] or nil
    return string.format("%s %s camo", nameOf(weapon, weaponId), nameOf(camo, camoId)), nil
end

function store.ItemViews(offer, lookup, facts)
    ---@type PW.UIStoreItem[]
    local items = {}
    for index, entry in ipairs(offer.items) do
        local name, entity = describe(entry, lookup)
        local state = "locked"
        if facts.owned(entry.key) then
            state = "owned"
        elseif facts.unlocked(entry.kind, entry.id) then
            state = "unlocked"
        end
        items[index] = {
            key = entry.key, kind = entry.kind, id = entry.id, name = name, label = store.KindLabel(entry.kind),
            state = state, preview = store.Preview(entry.kind, entity)
        }
    end
    return items
end

---@type table<string, string>
local itemBadges = { owned = "OWNED", unlocked = "UNLOCKED" }

function store.ItemCards(items)
    ---@type PW.UICard[]
    local cards = {}
    for index, entry in ipairs(items) do
        cards[index] = {
            id = entry.key, title = entry.name, tags = entry.label, badge = itemBadges[entry.state], locked = false
        }
    end
    return cards
end

function store.RotationOf(view, key)
    ---@type { [1]: PW.UIStoreRotation, [2]: PW.EconomyOffer[] }[]
    local channels = { { "featured", view.featured or {} }, { "weekly", view.weekly or {} } }
    for _, channel in ipairs(channels) do
        for _, offer in ipairs(channel[2]) do
            if offer.key == key then return channel[1] end
        end
    end
    return nil
end

function store.BundleRows(offer, items, rotation, now)
    local owned = 0
    for _, entry in ipairs(items) do
        if entry.state == "owned" then owned = owned + 1 end
    end
    ---@type { [1]: string, [2]: string }[]
    local rows = { { "PRICE", store.PriceText(offer.price) } }
    if offer.rarity ~= nil then rows[#rows + 1] = { "RARITY", capitalise(offer.rarity) } end
    rows[#rows + 1] = { "ITEMS", string.format("%d (%d owned)", #items, owned) }
    if rotation ~= nil then
        local period = rotation == "featured" and "daily" or "weekly"
        rows[#rows + 1] = { "LEAVES IN", store.CountdownText(store.SecondsToRotation(now, period)) }
    end
    return rows
end
