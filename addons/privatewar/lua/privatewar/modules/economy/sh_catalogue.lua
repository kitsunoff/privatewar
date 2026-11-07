-- Economy, pure part 2 (T-4.12; 06-progression.md d.6): the catalogue and its offers. Plain data in, plain data out:
-- a catalogue is kind -> id -> entity table (the live one is built from the registries by _LiveCatalogue, the only
-- engine edge here), so the tests and the store screen read the same rules.
--
-- Offers:
--   * a single offer for every entity with a Price of 1 or more (any kind with a registry except bundles);
--   * a bundle offer for every bundle whose Items all resolve (a camo item is { kind = "camos", weapon, id }, or kind
--     "camo"); a bundle with an item that does not resolve, an empty one or one that nests a bundle is not offered.
-- Keys are "<kind>:<id>". A bundle grants every item key plus its own key. Loaded by shared.lua.

local lib = PW.Economy --[[@as PW.EconomyLib]]

function lib._LookupOf(catalogue)
    return function(kind, id)
        local entities = catalogue[kind]
        if entities == nil then return nil end
        return entities[id]
    end
end

---@param catalogue PW.EconomyCatalogue
---@param raw any
---@return PW.EconomyItem?
local function itemOf(catalogue, raw)
    if not istable(raw) then return nil end
    local source = raw --[[@as table<string, any>]]
    if not isstring(source.kind) or not isstring(source.id) then return nil end
    local kind, id = source.kind --[[@as string]], source.id --[[@as string]]
    local lookup = lib._LookupOf(catalogue)
    if kind == "camo" or kind == "camos" then
        if not isstring(source.weapon) then return nil end
        local weapon = source.weapon --[[@as string]]
        local entry = lookup("weapons", weapon)
        local camos = entry ~= nil and entry.Camos or nil
        if not istable(camos) or not istable((camos --[[@as table<string, any>]])[id]) then return nil end
        local camoId = weapon .. ":" .. id
        return { kind = "camos", id = camoId, key = "camos:" .. camoId }
    end
    if kind == "bundles" or lookup(kind, id) == nil then return nil end
    return { kind = kind, id = id, key = kind .. ":" .. id }
end

---@param catalogue PW.EconomyCatalogue
---@param entity table<string, any>
---@return PW.EconomyItem[]?
local function itemsOf(catalogue, entity)
    local list = entity.Items
    if not istable(list) or #list == 0 then return nil end
    ---@type PW.EconomyItem[]
    local items = {}
    for _, raw in ipairs(list --[[@as any[] ]]) do
        local item = itemOf(catalogue, raw)
        if item == nil then return nil end
        items[#items + 1] = item
    end
    return items
end

---@param entity table<string, any>
---@return integer?
local function priceOf(entity)
    local price = entity.Price
    if not isnumber(price) then return nil end
    local number = price --[[@as number]]
    if number ~= number or number < 1 or number > 2 ^ 31 then return nil end
    return math.floor(number)
end

---@param tbl table<string, any>
---@return string[]
local function sortedKeys(tbl)
    ---@type string[]
    local keys = {}
    for key in pairs(tbl) do
        if isstring(key) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

---@param kind string
---@param id string
---@param entity table<string, any>
---@param price integer
---@param items PW.EconomyItem[]
---@param bundle boolean
---@return PW.EconomyOffer
local function offerOf(kind, id, entity, price, items, bundle)
    local name = entity.Name
    return {
        key = kind .. ":" .. id, kind = kind, id = id, name = isstring(name) and name --[[@as string]] or id,
        price = price, rarity = isstring(entity.Rarity) and entity.Rarity --[[@as string]] or nil,
        bundle = bundle, items = items
    }
end

---Adds the offer of one entity: a single offer, or a bundle offer when its items all resolve; nothing without a price.
---@param offers PW.EconomyOffers
---@param catalogue PW.EconomyCatalogue
---@param kind string
---@param id string
local function addOffer(offers, catalogue, kind, id)
    local entity = catalogue[kind][id]
    local price = priceOf(entity)
    if price == nil then return end
    if kind ~= "bundles" then
        local items = { { kind = kind, id = id, key = kind .. ":" .. id } }
        offers.singles[#offers.singles + 1] = offerOf(kind, id, entity, price, items, false)
        return
    end
    local items = itemsOf(catalogue, entity)
    if items ~= nil then offers.bundles[#offers.bundles + 1] = offerOf(kind, id, entity, price, items, true) end
end

function lib._Offers(catalogue)
    ---@type PW.EconomyOffers
    local offers = { singles = {}, bundles = {} }
    for _, kind in ipairs(sortedKeys(catalogue)) do
        for _, id in ipairs(sortedKeys(catalogue[kind])) do addOffer(offers, catalogue, kind, id) end
    end
    return offers
end

---@param offers PW.EconomyOffer[]
---@return string[]
local function idsOf(offers)
    ---@type string[]
    local ids = {}
    for index, offer in ipairs(offers) do ids[index] = offer.id end
    return ids
end

---@param offers PW.EconomyOffer[]
---@param ids string[]
---@return PW.EconomyOffer[]
local function pick(offers, ids)
    ---@type PW.EconomyOffer[]
    local chosen = {}
    for _, id in ipairs(ids) do
        for _, offer in ipairs(offers) do
            if offer.id == id then chosen[#chosen + 1] = offer end
        end
    end
    return chosen
end

function lib._BuildStore(catalogue, date, dailySlots, weeklySlots)
    local offers = lib._Offers(catalogue)
    local ids = idsOf(offers.bundles)
    return {
        date = date, permanent = offers.singles,
        featured = pick(offers.bundles, lib._Featured(date, ids, dailySlots)),
        weekly = pick(offers.bundles, lib._Weekly(date, ids, weeklySlots))
    }
end

function lib._LiveCatalogue()
    ---@type PW.EconomyCatalogue
    local catalogue = {}
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    if registries == nil then return catalogue end
    for kind, registry in pairs(registries) do
        ---@type table<string, table<string, any>>
        local entities = {}
        for _, entity in ipairs(registry.GetEnabledList()) do entities[entity.ClassName] = entity end
        catalogue[kind] = entities
    end
    return catalogue
end
