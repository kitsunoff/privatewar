-- Economy module (T-4.12; 06-progression.md d.6). A meta currency earned through score events and a shop: single
-- entities with a Price, bundles (kind bundles/) and a date-seeded rotation. Disabling the module leaves level-only
-- unlocks: purchases and prices stop counting in PW.Progression.IsUnlocked. The currency and the purchased items are
-- stored by progression (the client file and the deltas, T-4.10); this module earns, sells and rotates. The store
-- screen is T-7.5 and reads this API: GetStore, GetOffer, GetCurrency, IsOwned, RequestBuy.
--
-- Pure rules: sh_rotation.lua (date-seeded selection), sh_catalogue.lua (offers), sh_purchase.lua (quote, wire).
-- The server glue is init.lua, the client requests cl_init.lua.
--
-- Settings (server scope):
--   currencyrate  currency per XP of a score event without its own EVENT.Currency (default 0.1: 10 % of XP)
--   matchbonus    currency at the end of a match for a player who earned something (default 100)
--   dailyslots    bundles featured per day (default 2); weeklyslots: bundles featured per week (default 1)
--
-- Decisions of the lane agent: bundles are sold only while featured today or this week (single offers always); a
-- bundle is charged in full even when some of its items are owned; the date is UTC; a purchase is refused for an item
-- the level already unlocks.

MODULE.Name = "Economy"

MODULE.Settings = {
    currencyrate = { scope = "server", type = "float", default = 0.1, min = 0, max = 10,
        label = "Currency per XP of a score event" },
    matchbonus = { scope = "server", type = "int", default = 100, min = 0, max = 100000,
        label = "Currency at the end of a match" },
    dailyslots = { scope = "server", type = "int", default = 2, min = 0, max = 16, label = "Daily featured bundles" },
    weeklyslots = { scope = "server", type = "int", default = 1, min = 0, max = 16, label = "Weekly featured bundles" }
}

local lib = (rawget(PW, "Economy") or {}) --[[@as PW.EconomyLib]]
PW.Economy = lib
lib._Module = MODULE

if SERVER then
    AddCSLuaFile("privatewar/modules/economy/sh_rotation.lua")
    AddCSLuaFile("privatewar/modules/economy/sh_catalogue.lua")
    AddCSLuaFile("privatewar/modules/economy/sh_purchase.lua")
end
include("privatewar/modules/economy/sh_rotation.lua")
include("privatewar/modules/economy/sh_catalogue.lua")
include("privatewar/modules/economy/sh_purchase.lua")

function lib._Active()
    local module = lib._Module
    return module ~= nil and module:IsValid()
end

---@param value any
---@param default number
---@return number
local function numberOr(value, default)
    if isnumber(value) then return value --[[@as number]] end
    return default
end

function lib._Params(read)
    return {
        currencyRate = numberOr(read("economy.currencyrate"), 0.1),
        matchBonus = math.floor(numberOr(read("economy.matchbonus"), 100)),
        dailySlots = math.floor(numberOr(read("economy.dailyslots"), 2)),
        weeklySlots = math.floor(numberOr(read("economy.weeklyslots"), 1))
    }
end

function lib.Today()
    return os.date("!%Y-%m-%d", os.time()) --[[@as string]]
end

---@param date string?
---@return PW.EconomyStoreView
local function storeOn(date)
    local params = lib._Params(function(id) return PW.Setting(id) end)
    return lib._BuildStore(lib._LiveCatalogue(), date or lib.Today(), params.dailySlots, params.weeklySlots)
end

function lib.GetStore(date)
    return storeOn(date)
end

---@param offers PW.EconomyOffer[]
---@return string[]
local function keysOf(offers)
    ---@type string[]
    local keys = {}
    for index, offer in ipairs(offers) do keys[index] = offer.key end
    return keys
end

function lib.Featured(date)
    return keysOf(storeOn(date).featured)
end

function lib.Weekly(date)
    return keysOf(storeOn(date).weekly)
end

function lib.GetOffer(key)
    local offers = lib._Offers(lib._LiveCatalogue())
    for _, offer in ipairs(offers.singles) do
        if offer.key == key then return offer end
    end
    for _, offer in ipairs(offers.bundles) do
        if offer.key == key then return offer end
    end
    return nil
end

function lib.GetCurrency(ply)
    return PW.Progression.GetCurrency(ply)
end

function lib.IsOwned(ply, kind, id)
    return PW.Progression.IsOwned(ply, PW.Progression._OwnedKey(kind, id))
end
