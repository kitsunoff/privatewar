-- T-7.5 Store, bundle details and progress screens (TASKS.md "Mandatory test cases": T-7.4-T-7.7 each screen's data
-- model built from registries without drawing; 06-progression.md d.4, d.6; 10-frontend.md d.1). Pure cases over plain
-- data: the store view model (sections, grouping by kind, owned/unlocked/funds/price states), the rotation countdown
-- and its text, the Buy flow (the request is sent once, every result reason gets a text, a lost answer expires),
-- bundle details (items, previews), the progress model (level bar, next unlocks order, weapon list, last match
-- summary) and the registration of the screens in the STORE and PROGRESS tabs.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UIStoreLib
local function store() return must(must(PW.UI).Store) end

---@return PW.UIProgressLib
local function progress() return must(must(PW.UI).Progress) end

local day = 86400

---@param kind string
---@param id string
---@param price integer
---@param items? PW.EconomyItem[]
---@param rarity? string
---@return PW.EconomyOffer
local function offer(kind, id, price, items, rarity)
    local key = kind .. ":" .. id
    return {
        key = key, kind = kind, id = id, name = string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2), price = price,
        rarity = rarity, bundle = items ~= nil, items = items or { { kind = kind, id = id, key = key } }
    }
end

---@param kind string
---@param id string
---@return PW.EconomyItem
local function item(kind, id)
    return { kind = kind, id = id, key = kind .. ":" .. id }
end

---@return PW.EconomyStoreView
local function storeView()
    return {
        date = "2026-11-07",
        featured = { offer("bundles", "operator_pack", 700, { item("models", "swat"), item("cards", "gold_medal") },
            "common") },
        weekly = { offer("bundles", "elite_force", 2400, {
            item("models", "combine_elite"), item("cards", "lightning"), item("streaks", "uav"),
            item("camos", "weapon_smg1:tiger")
        }, "legendary") },
        permanent = {
            offer("cards", "bomb", 300, nil, "rare"), offer("camos", "weapon_smg1:gold", 900),
            offer("models", "riot", 800), offer("models", "swat", 600), offer("perks", "adrenaline", 500)
        }
    }
end

---@param extra? table<string, any>
---@return PW.UIStoreFacts
local function facts(extra)
    local owned = { ["models:swat"] = true }
    local unlocked = { ["perks:adrenaline"] = true }
    ---@type PW.UIStoreFacts
    local out = {
        currency = 650,
        owned = function(key) return owned[key] == true end,
        unlocked = function(kind, id) return unlocked[kind .. ":" .. id] == true end
    }
    for key, value in pairs(extra or {}) do out[key] = value end
    return out
end

---@param list { id: string }[]
---@return string[]
local function ids(list)
    ---@type string[]
    local out = {}
    for index, entry in ipairs(list) do out[index] = entry.id end
    return out
end

---@param cards PW.UICard[]
---@param id string
---@return PW.UICard
local function cardOf(cards, id)
    for _, card in ipairs(cards) do
        if card.id == id then return card end
    end
    error("no card " .. id)
end

---The catalogue a lookup reads (kind -> id -> entity).
---@return PW.EconomyCatalogue
local function catalogue()
    return {
        models = {
            swat = { Name = "SWAT Operator", Model = "models/player/swat.mdl", Price = 600 },
            combine_elite = { Name = "Combine Elite", Model = "models/player/combine_super_soldier.mdl", Unlock = 20 }
        },
        cards = {
            gold_medal = { Name = "Gold Medal", Material = "icon16/medal_gold_1.png", Unlock = 4 },
            lightning = { Name = "Lightning", Material = "icon16/lightning.png", Unlock = { level = 12 } }
        },
        streaks = { uav = { Name = "UAV", Unlock = 3 }, airstrike = { Name = "Airstrike", Unlock = 12 } },
        perks = { ghost = { Name = "Ghost", Unlock = 30, Hidden = true }, scavenger = { Name = "Scavenger" } },
        weapons = {
            weapon_smg1 = { Name = "SMG", Camos = { tiger = { Name = "Tiger" } } },
            weapon_ar2 = { Name = "Pulse Rifle", Unlock = 9 },
            weapon_pistol = {}
        }
    }
end

---@param kind string
---@param id string
---@return table<string, any>?
local function lookup(kind, id)
    local entities = catalogue()[kind]
    return entities ~= nil and entities[id] or nil
end

---A toy weapon curve: 100 XP per level, cap 5.
---@param xp number
---@return integer, number, number
local function levelOf(xp)
    local level = math.min(5, math.floor(xp / 100) + 1)
    if level >= 5 then return 5, 0, 0 end
    return level, xp - (level - 1) * 100, 100
end

---@param reason string
---@param ok? boolean
---@return PW.EconomyResult
local function result(reason, ok)
    return { ok = ok == true, key = "bundles:operator_pack", reason = reason, currency = 1250 }
end

return {
    groupName = "PW UI store and progress",
    cases = {
        {
            name = "Store sections: featured, weekly, then the permanent offers grouped by kind (models, cards, camos)",
            func = function()
                local sections = store().Sections(storeView(), facts(), 0)
                local order = ids(sections)
                expect(table.concat(order, ",")).to.equal(
                    "featured,weekly,kind:models,kind:cards,kind:camos,kind:perks")
                expect(sections[1].title).to.equal("Featured")
                expect(sections[2].title).to.equal("Weekly")
                expect(sections[3].title).to.equal("Models")
                expect(sections[4].title).to.equal("Calling cards")
                expect(sections[5].title).to.equal("Camos")
                expect(sections[6].title).to.equal("Perks")
                expect(table.concat(ids(sections[3].cards), ",")).to.equal("models:riot,models:swat")
                expect(#sections[1].cards).to.equal(1)
                expect(sections[1].cards[1].id).to.equal("bundles:operator_pack")
            end
        },
        {
            name = "Store sections: an empty kind is left out; empty rotations stay with a note",
            func = function()
                local view = storeView()
                view.featured, view.weekly, view.permanent = {}, {}, { offer("cards", "bomb", 300) }
                local sections = store().Sections(view, facts(), 0)
                expect(table.concat(ids(sections), ",")).to.equal("featured,weekly,kind:cards")
                expect(sections[1].empty).to.beTrue()
                expect(sections[1].note).to.equal("No bundles in the rotation")
                expect(sections[3].empty).to.beFalse()
            end
        },
        {
            name = "Store states: owned, unlocked by level, not enough currency, buyable, pending",
            func = function()
                local f = facts()
                local view = storeView()
                expect(store().OfferState(view.permanent[4], f)).to.equal("owned") -- models:swat
                expect(store().OfferState(view.permanent[5], f)).to.equal("unlocked") -- perks:adrenaline
                expect(store().OfferState(view.permanent[3], f)).to.equal("funds") -- models:riot 800 > 650
                expect(store().OfferState(view.permanent[1], f)).to.equal("buyable") -- cards:bomb 300
                local pending = facts({ pending = "cards:bomb" })
                expect(store().OfferState(view.permanent[1], pending)).to.equal("pending")
            end
        },
        {
            name = "Store states: a bundle is owned by its key or when every item is owned; never 'unlocked'",
            func = function()
                local bundle = storeView().featured[1]
                local all = facts({
                    owned = function(key) return key == "models:swat" or key == "cards:gold_medal" end,
                    unlocked = function() return true end
                })
                expect(store().OfferState(bundle, all)).to.equal("owned")
                local byKey = facts({ owned = function(key) return key == "bundles:operator_pack" end })
                expect(store().OfferState(bundle, byKey)).to.equal("owned")
                local some = facts({ currency = 1000, unlocked = function() return true end })
                expect(store().OfferState(bundle, some)).to.equal("buyable")
            end
        },
        {
            name = "Store cards: price badge, OWNED, UNLOCKED; tags carry the rarity and the kind",
            func = function()
                local sections = store().Sections(storeView(), facts(), 0)
                local models = sections[3].cards
                expect(cardOf(models, "models:riot").badge).to.equal("800 CR")
                expect(cardOf(models, "models:swat").badge).to.equal("OWNED")
                expect(cardOf(sections[6].cards, "perks:adrenaline").badge).to.equal("UNLOCKED")
                expect(cardOf(sections[4].cards, "cards:bomb").tags).to.equal("Rare calling card")
                expect(cardOf(models, "models:riot").tags).to.equal("Model")
                expect(sections[1].cards[1].tags).to.equal("Common bundle, 2 items")
                expect(cardOf(models, "models:riot").footer).to.equal("Not enough credits")
                for _, card in ipairs(models) do expect(card.locked).to.beFalse() end
            end
        },
        {
            name = "Store section cards: the rotations show their countdown, a kind its offer count",
            func = function()
                local now = 20 * day + 3600 -- 1970-01-21 01:00 UTC, a Wednesday
                local cards = store().SectionCards(store().Sections(storeView(), facts(), now))
                expect(cards[1].badge).to.equal("23h 00m")
                expect(cards[1].text).to.equal("New bundles in 23h 00m")
                expect(cards[2].badge).to.equal("4d 23h")
                expect(cards[3].badge).to.equal("2")
            end
        },
        {
            name = "Countdown: seconds to the next UTC midnight and to the next Monday 00:00 UTC",
            func = function()
                expect(store().SecondsToRotation(0, "daily")).to.equal(day)
                expect(store().SecondsToRotation(day - 1, "daily")).to.equal(1)
                expect(store().SecondsToRotation(0, "weekly")).to.equal(4 * day) -- Thursday to Monday
                expect(store().SecondsToRotation(4 * day, "weekly")).to.equal(7 * day) -- Monday 00:00
                expect(store().SecondsToRotation(4 * day + 1, "weekly")).to.equal(7 * day - 1)
            end
        },
        {
            name = "Countdown text: days and hours, hours and minutes, minutes and seconds, never negative",
            func = function()
                expect(store().CountdownText(2 * day + 4 * 3600 + 59)).to.equal("2d 4h")
                expect(store().CountdownText(13 * 3600 + 20 * 60)).to.equal("13h 20m")
                expect(store().CountdownText(3600)).to.equal("1h 00m")
                expect(store().CountdownText(4 * 60 + 5)).to.equal("4m 05s")
                expect(store().CountdownText(0.2)).to.equal("0m 01s")
                expect(store().CountdownText(-5)).to.equal("0m 00s")
            end
        },
        {
            name = "Number and price text: thousands separated, floored",
            func = function()
                expect(store().FormatNumber(0)).to.equal("0")
                expect(store().FormatNumber(999)).to.equal("999")
                expect(store().FormatNumber(2400)).to.equal("2,400")
                expect(store().FormatNumber(1234567.9)).to.equal("1,234,567")
                expect(store().PriceText(2400)).to.equal("2,400 CR")
            end
        },
        {
            name = "Buy button: open with the price only when buyable; otherwise locked with the reason",
            func = function()
                local bomb = offer("cards", "bomb", 300)
                local open = store().BuyButton(bomb, "buyable", 650)
                expect(open.locked).to.beFalse()
                expect(open.label).to.equal("BUY  300 CR")
                expect(store().BuyButton(bomb, "owned", 650).reason).to.equal("You own this item")
                expect(store().BuyButton(bomb, "unlocked", 650).reason).to.equal("Your level already unlocks this item")
                local poor = store().BuyButton(offer("models", "riot", 800), "funds", 650)
                expect(poor.locked).to.beTrue()
                expect(poor.reason).to.equal("Not enough credits: 800 CR needed, 650 CR held")
                expect(store().BuyButton(bomb, "pending", 650).reason).to.equal("Waiting for the server")
            end
        },
        {
            name = "Buy sends one request for a buyable offer and nothing while pending or not buyable",
            func = function()
                ---@type string[]
                local sent = {}
                local function send(key) sent[#sent + 1] = key end
                local purchase = store().NewPurchase()
                local bomb = offer("cards", "bomb", 300)
                expect(store().Request(purchase, bomb, "funds", send, 10)).to.beFalse()
                expect(store().Request(purchase, bomb, "owned", send, 10)).to.beFalse()
                expect(#sent).to.equal(0)
                expect(store().Request(purchase, bomb, "buyable", send, 10)).to.beTrue()
                expect(purchase.pending).to.equal("cards:bomb")
                expect(store().Request(purchase, bomb, "buyable", send, 11)).to.beFalse()
                expect(#sent).to.equal(1)
                expect(sent[1]).to.equal("cards:bomb")
            end
        },
        {
            name = "Buy result: every reason gets a text; the answer clears the pending request",
            func = function()
                local texts = {
                    [""] = "Bought Operator Pack. Balance: 1,250 CR",
                    badkey = "The server rejected the request",
                    unknown = "Operator Pack is not sold any more",
                    notoffered = "Operator Pack has left the rotation",
                    owned = "You already own Operator Pack",
                    unlocked = "Your level already unlocks Operator Pack",
                    funds = "Not enough credits for Operator Pack (balance 1,250 CR)",
                    strange = "Purchase failed: strange"
                }
                for reason, text in pairs(texts) do
                    local purchase = store().NewPurchase()
                    purchase.pending, purchase.sentAt = "bundles:operator_pack", 1
                    local message = store().OnResult(purchase, result(reason, reason == ""), "Operator Pack")
                    expect(message.text).to.equal(text)
                    expect(message.ok).to.equal(reason == "")
                    expect(purchase.pending).to.beNil()
                    expect(purchase.message).to.equal(message)
                end
            end
        },
        {
            name = "Buy: a request without an answer expires after the timeout with a message",
            func = function()
                local purchase = store().NewPurchase()
                store().Request(purchase, offer("cards", "bomb", 300), "buyable", function() end, 100)
                expect(store().Expire(purchase, 100 + store().RequestTimeout - 1)).to.beFalse()
                expect(purchase.pending).to.equal("cards:bomb")
                expect(store().Expire(purchase, 100 + store().RequestTimeout)).to.beTrue()
                expect(purchase.pending).to.beNil()
                expect(must(purchase.message).text).to.equal("No answer from the server")
                expect(must(purchase.message).ok).to.beFalse()
            end
        },
        {
            name = "Bundle details: items with names, kinds, owned/unlocked/locked states and previews",
            func = function()
                local bundle = storeView().weekly[1]
                local f = facts({
                    owned = function(key) return key == "cards:lightning" end,
                    unlocked = function(kind) return kind == "streaks" end
                })
                local items = store().ItemViews(bundle, lookup, f)
                expect(#items).to.equal(4)
                expect(items[1].name).to.equal("Combine Elite")
                expect(items[1].state).to.equal("locked")
                expect(must(items[1].preview).type).to.equal("model")
                expect(must(items[1].preview).path).to.equal("models/player/combine_super_soldier.mdl")
                expect(items[2].state).to.equal("owned")
                expect(must(items[2].preview).type).to.equal("material")
                expect(items[3].state).to.equal("unlocked")
                expect(items[3].preview).to.beNil()
                expect(items[4].name).to.equal("SMG Tiger camo")
                local cards = store().ItemCards(items)
                expect(cards[1].tags).to.equal("Model")
                expect(cards[2].badge).to.equal("OWNED")
                expect(cards[3].badge).to.equal("UNLOCKED")
                expect(cards[1].badge).to.beNil()
            end
        },
        {
            name = "Bundle details: the rotation it is in and the info rows",
            func = function()
                local view = storeView()
                expect(store().RotationOf(view, "bundles:operator_pack")).to.equal("featured")
                expect(store().RotationOf(view, "bundles:elite_force")).to.equal("weekly")
                expect(store().RotationOf(view, "bundles:shadow_ops")).to.beNil()
                local bundle = view.featured[1]
                local items = store().ItemViews(bundle, lookup, facts())
                local rows = store().BundleRows(bundle, items, "featured", 0)
                expect(rows[1][1]).to.equal("PRICE")
                expect(rows[1][2]).to.equal("700 CR")
                expect(rows[2][2]).to.equal("Common")
                expect(rows[3][2]).to.equal("2 (1 owned)")
                expect(rows[4][1]).to.equal("LEAVES IN")
                expect(rows[4][2]).to.equal("1d 0h")
            end
        },
        {
            name = "Preview: models show their model, cards their material, other kinds nothing",
            func = function()
                local model = must(store().Preview("models", { Model = "models/player/swat.mdl" }))
                expect(model.type).to.equal("model")
                local card = must(store().Preview("cards", { Material = "icon16/bomb.png" }))
                expect(card.type).to.equal("material")
                expect(card.path).to.equal("icon16/bomb.png")
                expect(store().Preview("perks", { Name = "Ghost" })).to.beNil()
                expect(store().Preview("models", { Model = 5 })).to.beNil()
            end
        },
        {
            name = "Progress level: title, XP text and bar fraction; full bar at the cap",
            func = function()
                local view = progress().LevelView(7, 1200, 7000)
                expect(view.title).to.equal("LEVEL 7")
                expect(view.xpText).to.equal("1,200 / 7,000 XP")
                expect(view.fraction).to.equal(1200 / 7000)
                expect(view.maxed).to.beFalse()
                local capped = progress().LevelView(55, 0, 0)
                expect(capped.fraction).to.equal(1)
                expect(capped.maxed).to.beTrue()
                expect(capped.xpText).to.equal("Max level")
            end
        },
        {
            name = "Next unlocks: only above the current level, the closest first, Hidden left out",
            func = function()
                local unlocks = progress().NextUnlocks(catalogue(), 4)
                ---@type string[]
                local order = {}
                for index, unlock in ipairs(unlocks) do order[index] = unlock.kind .. ":" .. unlock.id end
                expect(table.concat(order, ",")).to.equal(
                    "weapons:weapon_ar2,streaks:airstrike,cards:lightning,models:combine_elite")
                expect(unlocks[1].level).to.equal(9)
                expect(unlocks[1].name).to.equal("Pulse Rifle")
                expect(unlocks[3].level).to.equal(12)
                local limited = progress().NextUnlocks(catalogue(), 4, 2)
                expect(#limited).to.equal(2)
                expect(#progress().NextUnlocks(catalogue(), 30)).to.equal(0)
                local rows = progress().UnlockRows(limited)
                expect(rows[1][1]).to.equal("LV 9")
                expect(rows[1][2]).to.equal("Pulse Rifle (Weapon)")
            end
        },
        {
            name = "Weapon list: every weapon with its level and progress, highest level first",
            func = function()
                local weapons = catalogue().weapons
                local rows = progress().Weapons(weapons, { weapon_smg1 = 250, weapon_ar2 = 900, weapon_old = 30 },
                    levelOf)
                expect(table.concat(ids(rows), ",")).to.equal("weapon_ar2,weapon_smg1,weapon_old,weapon_pistol")
                expect(rows[1].level).to.equal(5)
                expect(rows[1].maxed).to.beTrue()
                expect(rows[2].level).to.equal(3)
                expect(rows[2].into).to.equal(50)
                expect(rows[2].fraction).to.equal(0.5)
                expect(rows[2].name).to.equal("SMG")
                expect(rows[3].name).to.equal("weapon_old")
                expect(rows[4].level).to.equal(1)
                local cards = progress().WeaponCards(rows)
                expect(cards[1].badge).to.equal("LV 5")
                expect(cards[1].text).to.equal("Max level")
                expect(cards[2].badge).to.equal("LV 3")
                expect(cards[2].text).to.equal("50 / 100 XP to level 4")
            end
        },
        {
            name = "Last match summary: rows when a summary exists, nil before the first match",
            func = function()
                expect(progress().SummaryRows(nil)).to.beNil()
                ---@type PW.ProgressionSummary
                local summary = {
                    xp = 1250, levelBefore = 3, levelAfter = 4,
                    weapons = { { class = "weapon_smg1", before = 2, after = 3 } },
                    medals = { { id = "first_blood", count = 1 }, { id = "double", count = 2 } }
                }
                local rows = must(progress().SummaryRows(summary, function(class)
                    return class == "weapon_smg1" and "SMG" or class
                end))
                expect(rows[1][1]).to.equal("XP")
                expect(rows[1][2]).to.equal("+1,250")
                expect(rows[2][2]).to.equal("3 > 4")
                expect(rows[3][1]).to.equal("SMG")
                expect(rows[3][2]).to.equal("LV 2 > 3")
                expect(rows[4][1]).to.equal("MEDALS")
                expect(rows[4][2]).to.equal("3")
            end
        },
        {
            name = "The STORE and PROGRESS tabs have root screens; bundle details is pushed on STORE",
            func = function()
                local registry = must(PW.Registries["screens"])
                local home = must(registry.Get("store_home")) --[[@as PW.Screen]]
                local details = must(registry.Get("store_bundle")) --[[@as PW.Screen]]
                local levels = must(registry.Get("progress_home")) --[[@as PW.Screen]]
                expect(home.Tab).to.equal("store")
                expect(home.Root).to.beTrue()
                expect(details.Tab).to.equal("store")
                expect(details.Root).to.beNil()
                expect(levels.Tab).to.equal("progress")
                expect(levels.Root).to.beTrue()
                local model = must(PW.UI).Router.New(registry.GetEnabledList() --[[@as PW.Screen[] ]])
                expect(model.tabById.store.locked).to.beFalse()
                expect(model.tabById.progress.locked).to.beFalse()
            end
        }
    }
}
