-- T-4.12 Economy (TASKS.md, "Mandatory test cases" T-4.12; 06-progression.md d.6). Pure cases over plain tables
-- (rotation, offers, quotes, the wallet in the file, deltas and wire) and server cases over fresh stores with injected
-- settings, date, catalogue and senders. No bots, no real players, no net traffic.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.EconomyLib
local function eco()
    return must(PW.Economy)
end

---@return PW.ProgressionLib
local function prog()
    return must(PW.Progression)
end

---@return Player
local function fakePlayer()
    ---@type table<string, any>
    local fake = {}
    fake.IsValid = function() return true end
    fake.IsBot = function() return false end
    fake.SetNW2Int = function() end
    return fake --[[@as Player]]
end

---@return Player
local function fakeBot()
    ---@type table<string, any>
    local fake = {}
    fake.IsValid = function() return true end
    fake.IsBot = function() return true end
    fake.SetNW2Int = function() end
    return fake --[[@as Player]]
end

---@return PW.EconomyCatalogue
local function shop()
    return {
        weapons = { pwt_rifle = { Name = "Rifle", Camos = { gold = { Unlock = 5 }, hidden = { Hidden = true } } } },
        perks = { pwt_perk = { Name = "Perk", Price = 300, Unlock = 10 } },
        models = {
            pwt_model = { Name = "Model", Model = "models/player/swat.mdl", Price = 500, Rarity = "rare" },
            pwt_cheap = { Name = "Cheap", Model = "models/player/urban.mdl", Price = 100 },
            pwt_free = { Name = "Free", Model = "models/player/riot.mdl" }
        },
        cards = { pwt_card = { Name = "Card", Material = "icon16/bomb.png", Price = 50 } },
        bundles = {
            pwt_bundle = { Name = "Bundle", Price = 800, Rarity = "legendary", Items = {
                { kind = "weapons", id = "pwt_rifle" },
                { kind = "camo", weapon = "pwt_rifle", id = "gold" },
                { kind = "cards", id = "pwt_card" },
                { kind = "models", id = "pwt_model" }
            } },
            pwt_broken = { Name = "Broken", Price = 10, Items = { { kind = "models", id = "pwt_missing" } } },
            pwt_empty = { Name = "Empty", Price = 10, Items = {} }
        }
    }
end

---@param count integer
---@return string[]
local function numberedIds(count)
    ---@type string[]
    local ids = {}
    for index = 1, count do ids[index] = string.format("pwt_b%02d", index) end
    return ids
end

---@param list string[]
---@return string
local function joined(list)
    return table.concat(list, ",")
end

---@class PW.EconomyRig
---@field store PW.EconomyStore
---@field pstore PW.ProgressionStore
---@field deltas PW.ProgressionDelta[]
---@field results PW.EconomyResult[]
---@field notes table[]

---@param opts? { settings?: table<string, any>, date?: string, events?: table<string, number>,
---catalogue?: PW.EconomyCatalogue }
---@return PW.EconomyRig
local function rig(opts)
    opts = opts or {}
    local values = opts.settings or {}
    local events = opts.events or {}
    local date = opts.date or "2026-11-07"
    local data = opts.catalogue or shop()
    ---@type PW.ProgressionDelta[], PW.EconomyResult[], table[]
    local deltas, results, notes = {}, {}, {}
    local pstore = prog()._NewStore({
        read = function(id) return values[id] end,
        publish = function() end,
        notify = function() end,
        sendDelta = function(_, delta) deltas[#deltas + 1] = delta end,
        ownedActive = function() return true end
    })
    local store = eco()._NewStore({
        read = function(id) return values[id] end,
        today = function() return date end,
        catalogue = function() return data end,
        progression = pstore,
        eventCurrency = function(id) return events[id] end,
        notify = function(name, ...) notes[#notes + 1] = { name, ... } end,
        sendResult = function(_, result) results[#results + 1] = result end
    })
    return { store = store, pstore = pstore, deltas = deltas, results = results, notes = notes }
end

---Gives the player a state with the currency (and optionally the XP).
---@param r PW.EconomyRig
---@param ply Player
---@param currency number
---@param xp? number
local function fund(r, ply, currency, xp)
    prog()._SetState(r.pstore, ply, { xp = xp or 0, weapons = {}, currency = currency, owned = {} })
end

---@param r PW.EconomyRig
---@param ply Player
---@return number
local function balance(r, ply)
    return must(prog()._StateOf(r.pstore, ply).currency)
end

---@param r PW.EconomyRig
---@param ply Player
---@param key string
---@return boolean
local function owns(r, ply, key)
    return prog()._GetOwned(r.pstore, ply)[key] == true
end

---An in-memory wire (the writer appends, the reader consumes in order; missing values read as 0, "" and false).
---@return PW.ProgressionWriter writer, PW.ProgressionReader reader
local function wire()
    ---@type any[]
    local buffer = {}
    local position = 0
    ---@return any
    local function nextValue()
        position = position + 1
        return buffer[position]
    end
    ---@type PW.ProgressionWriter
    local writer = {
        uint = function(value, width)
            assert(value >= 0 and value < 2 ^ width, "uint out of range: " .. tostring(value))
            buffer[#buffer + 1] = value
        end,
        string = function(value) buffer[#buffer + 1] = value end,
        bool = function(value) buffer[#buffer + 1] = value end
    }
    ---@type PW.ProgressionReader
    local reader = {
        uint = function() return nextValue() or 0 end,
        string = function() return nextValue() or "" end,
        bool = function() return nextValue() == true end
    }
    return writer, reader
end

---@param currency? number
---@param owned? table<string, boolean>
---@return PW.ProgressionFile
local function file(currency, owned)
    return { v = 2, xp = 0, weapons = {}, batch = { session = 0, seq = 0 }, currency = currency, owned = owned }
end

return {
    groupName = "PW economy",
    cases = {
        {
            name = "Rotation: the same date gives the same items, whatever the order the catalogue was listed in",
            func = function()
                local ids = numberedIds(12)
                local first = eco()._Featured("2026-11-07", ids, 3)
                expect(#first).to.equal(3)
                expect(joined(eco()._Featured("2026-11-07", ids, 3))).to.equal(joined(first))
                ---@type string[]
                local reversed = {}
                for index = #ids, 1, -1 do reversed[#reversed + 1] = ids[index] end
                expect(joined(eco()._Featured("2026-11-07", reversed, 3))).to.equal(joined(first))
                local weekly = joined(eco()._Weekly("2026-11-07", ids, 2))
                expect(joined(eco()._Weekly("2026-11-07", ids, 2))).to.equal(weekly)
            end
        },
        {
            name = "Rotation: another date gives other items (daily); the weekly set holds for the week, then changes",
            func = function()
                local ids = numberedIds(12)
                expect(joined(eco()._Featured("2026-11-07", ids, 3)) ~= joined(eco()._Featured("2026-11-08", ids, 3)))
                    .to.beTrue()
                ---@type table<string, boolean>
                local distinct = {}
                for day = 1, 14 do
                    distinct[joined(eco()._Featured(string.format("2026-11-%02d", day), ids, 3))] = true
                end
                local count = 0
                for _ in pairs(distinct) do count = count + 1 end
                expect(count >= 10).to.beTrue()
                local monday = joined(eco()._Weekly("2026-11-02", ids, 2))
                expect(joined(eco()._Weekly("2026-11-08", ids, 2))).to.equal(monday)
                expect(joined(eco()._Weekly("2026-11-09", ids, 2)) ~= monday).to.beTrue()
            end
        },
        {
            name = "Rotation: slots bound the result, picks are distinct catalogue members, a bad date gives nothing",
            func = function()
                local ids = numberedIds(5)
                expect(#eco()._Featured("2026-11-07", ids, 0)).to.equal(0)
                expect(#eco()._Featured("2026-11-07", ids, 99)).to.equal(5)
                expect(#eco()._Featured("2026-11-07", {}, 3)).to.equal(0)
                ---@type table<string, boolean>
                local seen = {}
                for _, id in ipairs(eco()._Featured("2026-11-07", ids, 4)) do
                    expect(seen[id]).to.beNil()
                    seen[id] = true
                    expect(table.HasValue(ids, id)).to.beTrue()
                end
                expect(#eco()._Featured("not a date", ids, 3)).to.equal(0)
                expect(#eco()._Weekly("2026-02-30", ids, 3)).to.equal(0)
            end
        },
        {
            name = "Rotation: day numbers count days since 1970-01-01 and a week starts on Monday",
            func = function()
                expect(eco()._DayNumber("1970-01-01")).to.equal(0)
                expect(eco()._DayNumber("1970-01-02")).to.equal(1)
                expect(eco()._DayNumber("2000-03-01")).to.equal(11017)
                expect(eco()._DayNumber("2026-11-07")).to.equal(20764)
                expect(eco()._DayNumber("2026-13-01")).to.beNil()
                expect(eco()._DayNumber("2026-11-31")).to.beNil()
                expect(eco()._DayNumber(nil)).to.beNil()
                expect(eco()._WeekNumber(20763)).to.equal(eco()._WeekNumber(20764))
            end
        },
        {
            name = "Offers: single entities with a Price, valid bundles only; a bundle camo item keys as camos",
            func = function()
                local offers = eco()._Offers(shop())
                ---@type string[]
                local keys = {}
                for _, offer in ipairs(offers.singles) do keys[#keys + 1] = offer.key end
                expect(joined(keys)).to.equal("cards:pwt_card,models:pwt_cheap,models:pwt_model,perks:pwt_perk")
                expect(#offers.bundles).to.equal(1)
                local bundle = offers.bundles[1]
                expect(bundle.key).to.equal("bundles:pwt_bundle")
                expect(bundle.price).to.equal(800)
                expect(bundle.rarity).to.equal("legendary")
                expect(bundle.items[2].key).to.equal("camos:pwt_rifle:gold")
                expect(#bundle.items).to.equal(4)
            end
        },
        {
            name = "Currency: a score event pays 10 % of its XP, EVENT.Currency overrides it, bots earn nothing",
            func = function()
                local r = rig({ events = { pwt_big = 40 } })
                local ply = fakePlayer()
                eco()._OnScoreEvent(r.store, ply, "pwt_kill", 100, 100)
                expect(balance(r, ply)).to.equal(10)
                eco()._OnScoreEvent(r.store, ply, "pwt_big", 100, 100)
                expect(balance(r, ply)).to.equal(50)
                eco()._OnScoreEvent(r.store, ply, "pwt_kill", 5, 5)
                expect(balance(r, ply)).to.equal(50)
                local bot = fakeBot()
                eco()._OnScoreEvent(r.store, bot, "pwt_kill", 100, 100)
                expect(balance(r, bot)).to.equal(0)
                local fast = rig({ settings = { ["economy.currencyrate"] = 0.5 } })
                eco()._OnScoreEvent(fast.store, ply, "pwt_kill", 100, 100)
                expect(balance(fast, ply)).to.equal(50)
            end
        },
        {
            name = "Currency: the match bonus is paid once, only to a player who earned during the match",
            func = function()
                local r = rig({ settings = { ["economy.matchbonus"] = 70 } })
                local earner, idle = fakePlayer(), fakePlayer()
                eco()._BeginMatch(r.store)
                eco()._OnScoreEvent(r.store, earner, "pwt_kill", 100, 100)
                eco()._OnPostmatch(r.store)
                eco()._OnPostmatch(r.store)
                expect(balance(r, earner)).to.equal(80)
                expect(balance(r, idle)).to.equal(0)
                eco()._BeginMatch(r.store)
                eco()._OnPostmatch(r.store)
                expect(balance(r, earner)).to.equal(80)
            end
        },
        {
            name = "Purchase: deducts the currency, marks the item owned, and the unlock check answers true",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                fund(r, ply, 1000)
                local view = prog()._ViewOf(r.pstore, ply, eco()._LookupOf(shop()))
                expect(prog()._IsUnlocked(view, "models", "pwt_model")).to.beFalse()
                local ok, reason = eco()._Buy(r.store, ply, "models:pwt_model")
                expect(ok).to.beTrue()
                expect(reason).to.equal("")
                expect(balance(r, ply)).to.equal(500)
                expect(owns(r, ply, "models:pwt_model")).to.beTrue()
                view = prog()._ViewOf(r.pstore, ply, eco()._LookupOf(shop()))
                expect(prog()._IsUnlocked(view, "models", "pwt_model")).to.beTrue()
                expect(r.results[1].ok).to.beTrue()
                expect(r.results[1].currency).to.equal(500)
                expect(r.notes[1][1]).to.equal("PW_EconomyPurchase")
                expect(r.notes[1][3]).to.equal("models:pwt_model")
                expect(r.notes[1][4]).to.equal(500)
            end
        },
        {
            name = "Purchase: insufficient funds are rejected and nothing changes",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                fund(r, ply, 499)
                local ok, reason = eco()._Buy(r.store, ply, "models:pwt_model")
                expect(ok).to.beFalse()
                expect(reason).to.equal("funds")
                expect(balance(r, ply)).to.equal(499)
                expect(owns(r, ply, "models:pwt_model")).to.beFalse()
                expect(r.results[1].ok).to.beFalse()
                expect(r.results[1].reason).to.equal("funds")
                expect(#r.notes).to.equal(0)
                fund(r, ply, 500)
                expect(eco()._Buy(r.store, ply, "models:pwt_model")).to.beTrue()
                expect(balance(r, ply)).to.equal(0)
            end
        },
        {
            name = "Purchase: a bundle grants all its items and itself for one price",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                fund(r, ply, 1000)
                local ok = eco()._Buy(r.store, ply, "bundles:pwt_bundle")
                expect(ok).to.beTrue()
                expect(balance(r, ply)).to.equal(200)
                local granted = { "weapons:pwt_rifle", "camos:pwt_rifle:gold", "cards:pwt_card", "models:pwt_model",
                    "bundles:pwt_bundle" }
                for _, key in ipairs(granted) do
                    expect(owns(r, ply, key)).to.beTrue()
                end
                local view = prog()._ViewOf(r.pstore, ply, eco()._LookupOf(shop()))
                expect(prog()._IsUnlocked(view, "camos", "pwt_rifle:gold")).to.beTrue()
                expect(eco()._Buy(r.store, ply, "bundles:pwt_bundle")).to.beFalse()
                expect(balance(r, ply)).to.equal(200)
            end
        },
        {
            name = "Purchase: a bundle is sold only while the rotation features it; a bundle of owned items is refused",
            func = function()
                local closed = rig({ settings = { ["economy.dailyslots"] = 0, ["economy.weeklyslots"] = 0 } })
                local ply = fakePlayer()
                fund(closed, ply, 5000)
                local ok, reason = eco()._Buy(closed.store, ply, "bundles:pwt_bundle")
                expect(ok).to.beFalse()
                expect(reason).to.equal("notoffered")
                local weekly = rig({ settings = { ["economy.dailyslots"] = 0, ["economy.weeklyslots"] = 1 } })
                fund(weekly, ply, 5000)
                expect(eco()._Buy(weekly.store, ply, "bundles:pwt_bundle")).to.beTrue()
                local r = rig()
                fund(r, ply, 5000)
                prog()._GrantOwned(r.pstore, ply, { "weapons:pwt_rifle", "camos:pwt_rifle:gold", "cards:pwt_card",
                    "models:pwt_model" })
                local bought, why = eco()._Buy(r.store, ply, "bundles:pwt_bundle")
                expect(bought).to.beFalse()
                expect(why).to.equal("owned")
            end
        },
        {
            name = "Purchase: bad keys, unknown offers, owned items and items the level already unlocks are refused",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                fund(r, ply, 5000)
                local function reasonOf(key)
                    local ok, reason = eco()._Buy(r.store, ply, key)
                    expect(ok).to.beFalse()
                    return reason
                end
                expect(reasonOf("garbage")).to.equal("badkey")
                expect(reasonOf("models:BAD ID")).to.equal("badkey")
                expect(reasonOf("")).to.equal("badkey")
                expect(reasonOf("models:pwt_missing")).to.equal("unknown")
                expect(reasonOf("models:pwt_free")).to.equal("unknown")
                expect(reasonOf("bundles:pwt_broken")).to.equal("unknown")
                expect(eco()._Buy(r.store, ply, "cards:pwt_card")).to.beTrue()
                expect(reasonOf("cards:pwt_card")).to.equal("owned")
                fund(r, ply, 5000, 1000000000)
                expect(reasonOf("perks:pwt_perk")).to.equal("unlocked")
                expect(balance(r, ply)).to.equal(5000)
            end
        },
        {
            name = "Purchase: the client file applies the purchase through the delta path, once",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                fund(r, ply, 1000)
                eco()._Buy(r.store, ply, "models:pwt_model")
                local delta = must(r.deltas[#r.deltas])
                expect(delta.spent).to.equal(500)
                expect(delta.owned and delta.owned["models:pwt_model"]).to.beTrue()
                local before = file(1000)
                local after, applied = prog()._ApplyDelta(before, delta)
                expect(applied).to.beTrue()
                expect(after.currency).to.equal(500)
                expect(must(after.owned)["models:pwt_model"]).to.beTrue()
                expect(before.currency).to.equal(1000)
                local again, repeated = prog()._ApplyDelta(after, delta)
                expect(repeated).to.beFalse()
                expect(again.currency).to.equal(500)
            end
        },
        {
            name = "Wallet: earned currency joins the delta; a delta never takes the currency below zero",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                eco()._OnScoreEvent(r.store, ply, "pwt_kill", 200, 200)
                local delta = must(prog()._Flush(r.pstore, ply))
                expect(delta.earned).to.equal(20)
                expect(delta.spent).to.equal(0)
                expect(must(prog()._ApplyDelta(file(5), delta)).currency).to.equal(25)
                local drain = { session = 1, seq = 1, xp = 0, weapons = {}, earned = 0, spent = 900 }
                expect(must(prog()._ApplyDelta(file(100), drain)).currency).to.equal(0)
                local huge = { session = 1, seq = 1, xp = 0, weapons = {}, earned = prog().MaxDeltaCurrency * 5 }
                expect(must(prog()._ApplyDelta(file(7), huge)).currency).to.equal(7)
            end
        },
        {
            name = "Storage: a v1 file (no currency, no purchases) loads with zero currency; the file round trips",
            func = function()
                local loaded = prog()._FileFromJson({ v = 1, xp = 300, weapons = { pwt_a = 40 },
                    batch = { session = 5, seq = 2 } })
                expect(loaded.currency).to.equal(0)
                expect(next(must(loaded.owned))).to.beNil()
                expect(loaded.xp).to.equal(300)
                expect(loaded.v).to.equal(prog().FileVersion)
                local stored = file(250, { ["models:pwt_model"] = true, ["cards:pwt_card"] = true })
                local text = util.TableToJSON(prog()._FileToJson(stored))
                local back = prog()._FileFromJson(util.JSONToTable(text))
                expect(back.currency).to.equal(250)
                expect(must(back.owned)["models:pwt_model"]).to.beTrue()
                expect(must(back.owned)["cards:pwt_card"]).to.beTrue()
                local bad = prog()._FileFromJson({ currency = -5, owned = { "models:ok_id", "BAD", 7, "models:" } })
                expect(bad.currency).to.equal(0)
                expect(must(bad.owned)["models:ok_id"]).to.beTrue()
                expect(must(bad.owned)["BAD"]).to.beNil()
            end
        },
        {
            name = "SetState: currency and owned are clamped (negative, NaN, fractions, bad keys, too many)",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                prog()._SetState(r.pstore, ply, { xp = 5, weapons = {}, currency = -5, owned = {} })
                expect(balance(r, ply)).to.equal(0)
                prog()._SetState(r.pstore, ply, { xp = 5, weapons = {}, currency = 0 / 0, owned = {} })
                expect(balance(r, ply)).to.equal(0)
                prog()._SetState(r.pstore, ply, { xp = 5, weapons = {}, currency = prog().MaxCurrency + 1, owned = {} })
                expect(balance(r, ply)).to.equal(0)
                prog()._SetState(r.pstore, ply, { xp = 5, weapons = {}, currency = 12.9, owned = {} })
                expect(balance(r, ply)).to.equal(12)
                ---@type string[]
                local many = { "models:good", "no key", "Models:caps", string.rep("a", 200) .. ":x" }
                for index = 1, prog().MaxOwned + 10 do many[#many + 1] = "cards:c" .. index end
                prog()._SetState(r.pstore, ply, { xp = 0, weapons = {}, currency = 1, owned = many --[[@as any]] })
                local owned = prog()._GetOwned(r.pstore, ply)
                local count = 0
                for _ in pairs(owned) do count = count + 1 end
                expect(count).to.equal(prog().MaxOwned)
                expect(prog()._GetState(r.pstore, ply).currency).to.equal(1)
                prog()._SetState(r.pstore, ply, { xp = 0, weapons = {} })
                expect(balance(r, ply)).to.equal(0)
            end
        },
        {
            name = "Wallet: spending needs a whole amount the player can pay; granting counts only new items",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                fund(r, ply, 100)
                expect(prog()._SpendCurrency(r.pstore, ply, 101)).to.beFalse()
                expect(prog()._SpendCurrency(r.pstore, ply, -5)).to.beFalse()
                expect(prog()._SpendCurrency(r.pstore, ply, 0 / 0)).to.beFalse()
                expect(prog()._SpendCurrency(r.pstore, ply, 60)).to.beTrue()
                expect(balance(r, ply)).to.equal(40)
                expect(prog()._GrantOwned(r.pstore, ply, { "cards:a", "cards:b", "BAD" })).to.equal(2)
                expect(prog()._GrantOwned(r.pstore, ply, { "cards:a", "cards:c" })).to.equal(1)
            end
        },
        {
            name = "Unlock rules: a priced entity without Unlock is for sale only; no economy, no prices",
            func = function()
                local lookup = eco()._LookupOf(shop())
                ---@type PW.ProgressionView
                local active = { level = 1, weaponLevel = function() return 1 end, lookup = lookup, unlockAll = false,
                    maxAttachments = 5, owned = function(key) return key == "models:pwt_cheap" end }
                expect(prog()._IsUnlocked(active, "models", "pwt_model")).to.beFalse()
                expect(prog()._IsUnlocked(active, "models", "pwt_cheap")).to.beTrue()
                expect(prog()._IsUnlocked(active, "models", "pwt_free")).to.beTrue()
                expect(prog()._IsUnlocked(active, "perks", "pwt_perk")).to.beFalse()
                active.level = 10
                expect(prog()._IsUnlocked(active, "perks", "pwt_perk")).to.beTrue()
                ---@type PW.ProgressionView
                local inactive = { level = 1, weaponLevel = function() return 1 end, lookup = lookup, unlockAll = false,
                    maxAttachments = 5 }
                expect(prog()._IsUnlocked(inactive, "models", "pwt_model")).to.beTrue()
                active.unlockAll = true
                expect(prog()._IsUnlocked(active, "models", "pwt_model")).to.beTrue()
            end
        },
        {
            name = "Unlock rules: a purchased camo opens, a Hidden camo stays hidden even when owned",
            func = function()
                local lookup = eco()._LookupOf(shop())
                ---@type PW.ProgressionView
                local view = { level = 1, weaponLevel = function() return 1 end, lookup = lookup, unlockAll = false,
                    maxAttachments = 5, owned = function(key) return key == "camos:pwt_rifle:gold" or
                        key == "camos:pwt_rifle:hidden" end }
                expect(prog()._IsUnlocked(view, "camos", "pwt_rifle:gold")).to.beTrue()
                expect(prog()._IsUnlocked(view, "camos", "pwt_rifle:hidden")).to.beFalse()
                view.owned = function() return false end
                expect(prog()._IsUnlocked(view, "camos", "pwt_rifle:gold")).to.beFalse()
            end
        },
        {
            name = "Wire: state, delta, request and result survive encode and decode; a forged owned count is bounded",
            func = function()
                local w, rd = wire()
                prog()._EncodeState({ xp = 9, weapons = { pwt_a = 3 }, currency = 321,
                    owned = { ["models:pwt_model"] = true } }, w)
                local state = prog()._DecodeState(rd)
                expect(state.currency).to.equal(321)
                expect(must(state.owned)["models:pwt_model"]).to.beTrue()
                expect(state.weapons.pwt_a).to.equal(3)
                w, rd = wire()
                prog()._EncodeDelta({ session = 4, seq = 2, xp = 5, weapons = {}, earned = 30, spent = 12,
                    owned = { ["cards:pwt_card"] = true } }, w)
                local delta = prog()._DecodeDelta(rd)
                expect(delta.earned).to.equal(30)
                expect(delta.spent).to.equal(12)
                expect(must(delta.owned)["cards:pwt_card"]).to.beTrue()
                w, rd = wire()
                eco()._EncodeRequest("models:pwt_model", w)
                expect(eco()._DecodeRequest(rd)).to.equal("models:pwt_model")
                w, rd = wire()
                eco()._EncodeResult({ ok = false, key = "models:pwt_model", reason = "funds", currency = 77 }, w)
                local result = eco()._DecodeResult(rd)
                expect(result.ok).to.beFalse()
                expect(result.reason).to.equal("funds")
                expect(result.currency).to.equal(77)
                w, rd = wire()
                w.uint(1, 32)
                w.uint(0, 16)
                w.uint(5, 32)
                w.uint(65535, 16)
                local forged = prog()._DecodeState(rd)
                expect(forged.currency).to.equal(5)
                expect(next(must(forged.owned))).to.beNil()
                expect(prog().UploadMaxBytes < 65536).to.beTrue()
            end
        },
        {
            name = "Net: the purchase request is registered with an owner, a rate and a length bound",
            func = function()
                local def = must(PW._Net).defs["pw_economy_buy"]
                expect(def ~= nil).to.beTrue()
                expect(def.who).to.equal("any")
                expect(def.rate > 0).to.beTrue()
                expect(def.maxLen).to.equal(eco().RequestMaxBytes)
                expect(istable(def.owner)).to.beTrue()
                expect(eco().RequestMaxBytes <= 128).to.beTrue()
            end
        },
        {
            name = "Net: a forged or malformed request changes nothing; a bot cannot buy",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                fund(r, ply, 1000)
                local forged = { "", string.rep("x", 500), "models:pwt_model; drop", "../../etc", "BUNDLES:pwt_bundle" }
                for _, key in ipairs(forged) do
                    local ok, reason = eco()._OnRequest(r.store, ply, key)
                    expect(ok).to.beFalse()
                    expect(reason).to.equal("badkey")
                end
                expect(balance(r, ply)).to.equal(1000)
                expect(next(prog()._GetOwned(r.pstore, ply))).to.beNil()
                local bot = fakeBot()
                fund(r, bot, 1000)
                local ok = eco()._OnRequest(r.store, bot, "models:pwt_model")
                expect(ok).to.beFalse()
                expect(balance(r, bot)).to.equal(1000)
                expect(eco()._OnRequest(r.store, ply, "models:pwt_model")).to.beTrue()
            end
        },
        {
            name = "Store view: the permanent catalogue, the daily and the weekly bundles come from one pure function",
            func = function()
                local view = eco()._BuildStore(shop(), "2026-11-07", 2, 1)
                expect(view.date).to.equal("2026-11-07")
                expect(#view.permanent).to.equal(4)
                expect(#view.featured).to.equal(1)
                expect(view.featured[1].key).to.equal("bundles:pwt_bundle")
                expect(#view.weekly).to.equal(1)
                local none = eco()._BuildStore(shop(), "2026-11-07", 0, 0)
                expect(#none.featured).to.equal(0)
                expect(#none.weekly).to.equal(0)
            end
        },
        {
            name = "Kinds: bundles, models and cards are registered with their required fields",
            func = function()
                local registries = must(PW.Registries)
                expect(registries.bundles ~= nil).to.beTrue()
                expect(registries.models ~= nil).to.beTrue()
                expect(registries.cards ~= nil).to.beTrue()
                expect(PW.Registry.ValidateRequired({ Name = "B", Price = 1, Items = {} }, { Name = "string",
                    Price = "number", Items = "table" })).to.beTrue()
                expect(PW.Registry.ValidateRequired({ Name = "B", Items = {} }, { Name = "string", Price = "number",
                    Items = "table" })).to.beFalse()
            end
        },
        {
            name = "Samples: 2 to 3 stock entries per kind; every sample bundle resolves; live rotation is stable",
            func = function()
                local registries = must(PW.Registries)
                expect(#registries.models.GetList() >= 2).to.beTrue()
                expect(#registries.cards.GetList() >= 2).to.beTrue()
                expect(#registries.bundles.GetList() >= 2).to.beTrue()
                for _, entity in ipairs(registries.models.GetList()) do
                    expect(string.StartsWith(entity.Model --[[@as string]], "models/player/")).to.beTrue()
                end
                local live = eco()._LiveCatalogue()
                local offers = eco()._Offers(live)
                expect(#offers.bundles).to.equal(#registries.bundles.GetList())
                local first = eco().Featured("2026-11-07")
                expect(joined(eco().Featured("2026-11-07"))).to.equal(joined(first))
                for _, key in ipairs(first) do expect(string.StartsWith(key, "bundles:")).to.beTrue() end
                local store = eco().GetStore("2026-11-07")
                expect(#store.permanent >= 5).to.beTrue()
                expect(eco().GetOffer("models:swat") ~= nil).to.beTrue()
            end
        }
    }
}
