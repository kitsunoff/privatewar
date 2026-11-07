-- Economy, server glue (T-4.12; 06-progression.md d.6). Earns currency from score events and at the end of a match,
-- sells offers on a validated client request and records the result in the progression wallet (the purchase reaches
-- the client file through the progression delta, sent at once). Engine edges (settings, date, catalogue, event
-- lookup, notification, answer sender) are fields of the store, so the tests drive everything with fakes.
--
--   Earn: every score event of a human adds EVENT.Currency, or floor(xp * economy.currencyrate) without it.
--         At POSTMATCH a player who earned this match is paid economy.matchbonus once.
--   Buy:  pw_economy_buy (client to server, one key string; rate limited, bounded) -> _Buy: quote, spend, grant,
--         flush the delta, notify PW_EconomyPurchase(ply, key, price) and answer pw_economy_result.

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.EconomyModuleServer : PW.Module
local module = MODULE --[[@as PW.EconomyModuleServer]]

local lib = PW.Economy --[[@as PW.EconomyLib]]

---The progression library and store, read at call time: the module load order is not fixed and a reload replaces both.
---@return PW.ProgressionLib
local function wallet()
    return PW.Progression --[[@as PW.ProgressionLib]]
end

---@param store PW.EconomyStore
---@return PW.ProgressionStore
local function pstoreOf(store)
    return store.progression or PW._Progression --[[@as PW.ProgressionStore]]
end

---@return table
local function weakKeys()
    return setmetatable({}, { __mode = "k" })
end

---@param eventId string
---@return number?
local function defaultEventCurrency(eventId)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries.score_events or nil
    local event = registry ~= nil and registry.Get(eventId) or nil
    local currency = event ~= nil and (event --[[@as PW.ScoreEvent]]).Currency or nil
    return currency
end

---@param ply Player
---@param result PW.EconomyResult
local function defaultSendResult(ply, result)
    if not IsValid(ply) then return end
    net.Start("pw_economy_result")
    lib._EncodeResult(result, wallet()._NetWriter())
    net.Send(ply)
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        read = opts.read or function(id) return PW.Setting(id) end,
        today = opts.today or lib.Today,
        catalogue = opts.catalogue or lib._LiveCatalogue,
        progression = opts.progression,
        eventCurrency = opts.eventCurrency or defaultEventCurrency,
        notify = opts.notify or function(name, ...) PW.Notify(name, ...) end,
        sendResult = opts.sendResult or function() end,
        earned = weakKeys(), bonused = weakKeys()
    }
end

do -- a reload keeps the match bookkeeping, the functions are new
    local previous = rawget(PW, "_Economy") --[[@as PW.EconomyStore?]]
    local store = lib._NewStore({ sendResult = defaultSendResult })
    if previous ~= nil then store.earned, store.bonused = previous.earned, previous.bonused end
    PW._Economy = store
end

-- Earning ------------------------------------------------------------------------------------------------------------

---@param ply Player
---@return boolean
local function isHuman(ply)
    return IsValid(ply) and isfunction(ply.IsBot) and not ply:IsBot()
end

function lib._OnScoreEvent(store, ply, eventId, _, xp)
    if not isHuman(ply) then return end
    local own = isstring(eventId) and store.eventCurrency(eventId) or nil
    local amount = isnumber(own) and own --[[@as number]] or math.floor(xp * lib._Params(store.read).currencyRate)
    if not isnumber(amount) or amount < 1 then return end
    wallet()._AddCurrency(pstoreOf(store), ply, amount)
    store.earned[ply] = (store.earned[ply] or 0) + math.floor(amount)
end

function lib._BeginMatch(store)
    for ply in pairs(store.earned) do store.earned[ply] = nil end
    for ply in pairs(store.bonused) do store.bonused[ply] = nil end
end

function lib._OnPostmatch(store)
    local bonus = lib._Params(store.read).matchBonus
    ---@type Player[]
    local paid = {}
    for ply, earned in pairs(store.earned) do
        if IsValid(ply) and earned > 0 and not store.bonused[ply] then paid[#paid + 1] = ply end
    end
    for _, ply in ipairs(paid) do
        store.bonused[ply] = true
        wallet()._AddCurrency(pstoreOf(store), ply, bonus)
    end
end

-- Buying -------------------------------------------------------------------------------------------------------------

---Bundle keys of the offers on sale today: the daily and the weekly rotation over the valid bundles.
---@param store PW.EconomyStore
---@param catalogue PW.EconomyCatalogue
---@return table<string, boolean>
local function onSale(store, catalogue)
    local params = lib._Params(store.read)
    local view = lib._BuildStore(catalogue, store.today(), params.dailySlots, params.weeklySlots)
    ---@type table<string, boolean>
    local offered = {}
    for _, offer in ipairs(view.featured) do offered[offer.key] = true end
    for _, offer in ipairs(view.weekly) do offered[offer.key] = true end
    return offered
end

function lib._Context(store, ply)
    local catalogue = store.catalogue()
    local lookup = lib._LookupOf(catalogue)
    local pstore = pstoreOf(store)
    return {
        catalogue = catalogue, offered = onSale(store, catalogue),
        owned = function(key) return wallet()._GetOwned(pstore, ply)[key] == true end,
        unlocked = function(kind, id)
            local view = wallet()._ViewOf(pstore, ply, lookup)
            view.owned = function() return false end
            return wallet()._IsUnlocked(view, kind, id)
        end,
        currency = wallet()._StateOf(pstore, ply).currency or 0
    }
end

function lib._Buy(store, ply, key)
    local quote, reason = lib._Quote(lib._Context(store, ply), key)
    local pstore = pstoreOf(store)
    if quote == nil then
        store.sendResult(ply, { ok = false, key = tostring(key), reason = reason or "unknown",
            currency = wallet()._StateOf(pstore, ply).currency or 0 })
        return false, reason or "unknown"
    end
    wallet()._SpendCurrency(pstore, ply, quote.price)
    wallet()._GrantOwned(pstore, ply, quote.grants)
    wallet()._Flush(pstore, ply)
    store.notify("PW_EconomyPurchase", ply, quote.key, quote.price)
    store.sendResult(ply, { ok = true, key = quote.key, reason = "",
        currency = wallet()._StateOf(pstore, ply).currency or 0 })
    return true, ""
end

function lib._OnRequest(store, ply, key)
    if not isHuman(ply) then return false, "badplayer" end
    return lib._Buy(store, ply, key)
end

function lib.Buy(ply, key)
    return lib._OnRequest(PW._Economy, ply, key)
end

util.AddNetworkString("pw_economy_result")

PW.Net.Receive("pw_economy_buy", { who = "any", rate = 2, maxLen = lib.RequestMaxBytes, owner = module },
    function(ply) lib._OnRequest(PW._Economy, ply, lib._DecodeRequest(wallet()._NetReader())) end)

-- Hooks --------------------------------------------------------------------------------------------------------------

---@param ply Player
---@param eventId string
---@param points number
---@param xp number
function module:PW_ScoreEvent(ply, eventId, points, xp)
    lib._OnScoreEvent(PW._Economy, ply, eventId, points, xp)
end

function module:PW_MatchStart()
    lib._BeginMatch(PW._Economy)
end

---@param phase PW.PhaseName
function module:PW_PhaseChange(phase)
    if phase == "POSTMATCH" then lib._OnPostmatch(PW._Economy) end
end
