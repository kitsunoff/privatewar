-- Economy, pure part 3 (T-4.12; 06-progression.md d.6): the purchase rules and the wire of the purchase messages.
-- Plain data in, plain data out; the server glue (init.lua) feeds the context and applies the result.
--
-- _Quote(ctx, key) decides whether the player may buy an offer, in this order (the first failing reason is returned):
--   "badkey"      the key is not "<kind>:<id>"
--   "unknown"     no offer with that key (no Price, an unresolved bundle, a missing entity)
--   "notoffered"  a bundle that the date-seeded rotation does not feature today (single offers are always on sale)
--   "owned"       the key is already owned; a bundle whose items are all owned
--   "unlocked"    a single entity the player's level already unlocks
--   "funds"       the price is above the currency
-- A bundle is charged in full even when some items are owned; it grants every item key and its own key.
--
-- Wire (bits): pw_economy_buy (client to server) key string; pw_economy_result (server to the owner) ok bool, key
-- string, reason string, currency u32. Loaded by shared.lua.

local lib = PW.Economy --[[@as PW.EconomyLib]]

lib.RequestMaxBytes = 97

---@param offers PW.EconomyOffers
---@param key string
---@return PW.EconomyOffer?
local function findOffer(offers, key)
    for _, offer in ipairs(offers.singles) do
        if offer.key == key then return offer end
    end
    for _, offer in ipairs(offers.bundles) do
        if offer.key == key then return offer end
    end
    return nil
end

---@param ctx PW.EconomyContext
---@param offer PW.EconomyOffer
---@return string?
local function ownedReason(ctx, offer)
    if ctx.owned(offer.key) then return "owned" end
    if not offer.bundle then
        if ctx.unlocked(offer.kind, offer.id) then return "unlocked" end
        return nil
    end
    for _, item in ipairs(offer.items) do
        if not ctx.owned(item.key) then return nil end
    end
    return "owned"
end

function lib._Quote(ctx, key)
    if not isstring(key) or string.match(key, "^%l[%l_]*:[%w_]+$") == nil then return nil, "badkey" end
    local offer = findOffer(lib._Offers(ctx.catalogue), key)
    if offer == nil then return nil, "unknown" end
    if offer.bundle and ctx.offered[key] ~= true then return nil, "notoffered" end
    local reason = ownedReason(ctx, offer)
    if reason ~= nil then return nil, reason end
    if ctx.currency < offer.price then return nil, "funds" end
    ---@type string[]
    local grants = {}
    for _, item in ipairs(offer.items) do grants[#grants + 1] = item.key end
    if offer.bundle then grants[#grants + 1] = offer.key end
    return { key = key, price = offer.price, grants = grants }
end

function lib._EncodeRequest(key, writer)
    writer.string(key)
end

function lib._DecodeRequest(reader)
    return reader.string()
end

function lib._EncodeResult(result, writer)
    writer.bool(result.ok)
    writer.string(result.key)
    writer.string(result.reason)
    writer.uint(math.Clamp(math.floor(result.currency), 0, 2 ^ 32 - 1), 32)
end

function lib._DecodeResult(reader)
    local ok = reader.bool()
    local key = reader.string()
    local reason = reader.string()
    return { ok = ok, key = key, reason = reason, currency = reader.uint(32) }
end
