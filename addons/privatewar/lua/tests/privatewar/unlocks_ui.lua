-- Unlock requirements in the pure UI models (06-progression.md d.8).

---@return PW.UnlocksLib
local function unlocks()
    return assert(PW.Unlocks)
end

---@param lookup PW.LoadoutLookup
---@return PW.ProgressionView
local function view(lookup)
    return {
        level = 1, weaponLevel = function() return 1 end, lookup = lookup, unlockAll = false, maxAttachments = 5,
        owned = function() return false end
    }
end

return {
    groupName = "PW unlock UI",
    cases = {
        {
            name = "Editor: a locked item shows the requirement lock text and reason (level, price, reward)",
            func = function()
                local u, editor = unlocks(), assert(PW.LoadoutUI)
                ---@type table<string, any>[]
                local choices = {
                    { ClassName = "ranked", Unlock = { level = 12 } },
                    { ClassName = "shop", Price = 600 },
                    { ClassName = "earned", Unlock = { level = false, hint = "Generic reward" } }
                }
                local v = view(function(_, id)
                    for _, entity in ipairs(choices) do
                        if entity.ClassName == id then return entity end
                    end
                    return nil
                end)
                v.hint = function(_, id) if id == "earned" then return "Finish this week's challenge" end end
                ---@type PW.LoadoutUIEditorInput
                local input = {
                    declared = { pick = { id = "pick", kind = "perks" } }, order = { "pick" },
                    loadout = { pick = "earned" }, list = function() return choices end,
                    ctx = { lookup = v.lookup, budget = 0, maxattachments = 5,
                        isUnlocked = function(kind, id) return (u._Decide(v, kind, id)) end,
                        requirement = function(kind, id) return u._Requirement(v, kind, id) end }
                }
                local model = editor.Editor(input)
                local options = editor.Options(input, model.rows[1], model.slots)
                expect(options[2].locked and options[3].locked and options[4].locked).to.beTrue()
                expect({ options[2].lockText, options[2].reason }).to.deepEqual({ "LV 12", "Unlocks at level 12" })
                expect({ options[3].lockText, options[3].reason })
                    .to.deepEqual({ "600 CR", "Buy it in the STORE for 600 CR" })
                expect({ options[4].lockText, options[4].reason })
                    .to.deepEqual({ "REWARD", "Finish this week's challenge" })
                expect(model.rows[1].problem).to.equal("Locked: finish this week's challenge")
            end
        },
        {
            name = "Gunsmith: a granted curated option above the weapon level is open; a locked camo shows its "
                .. "weapon level",
            func = function()
                local u, editor = unlocks(), assert(PW.LoadoutUI)
                local weapon = {
                    Attachments = { scope = { Unlock = 12 } }, Camos = { gold = { Unlock = { level = 8 } } }
                }
                local v = view(function(kind, id) if kind == "weapons" and id == "rifle" then return weapon end end)
                v.granted = function(key) return key == "attachments:rifle:scope" or key == "attachments:rifle:loan" end
                ---@type PW.LoadoutUIGunsmithInput
                local input = {
                    weaponId = "rifle", weaponName = "Rifle", weapon = weapon, weaponLevel = 1, unlockAll = false,
                    cap = 5, banned = {}, build = { optic = "scope", grip = "loan", barrel = "standard" },
                    slots = {
                        { id = "optic", name = "Optic", cosmetic = false },
                        { id = "grip", name = "Grip", cosmetic = false },
                        { id = "barrel", name = "Barrel", cosmetic = false },
                        { id = "skin", name = "Skin", cosmetic = true }
                    },
                    options = function(slot)
                        if slot == "optic" then return { { id = "scope", name = "Scope", cosmetic = false } } end
                        if slot == "grip" then return { { id = "loan", name = "Loan", cosmetic = false } } end
                        if slot == "barrel" then return { { id = "standard", name = "Standard", cosmetic = false } } end
                        return { { id = "gold", name = "Gold", cosmetic = true } }
                    end,
                    optionRequirement = function(id)
                        return u._Requirement(v, id == "gold" and "camos" or "attachments", "rifle:" .. id)
                    end,
                    optionEntitled = function(id) return id == "loan" or id == "scope" end
                }
                local model = editor.Gunsmith(input)
                expect(model.slots[1].options[2].locked).to.beFalse()
                expect(model.levelCount).to.equal(1)
                expect(model.problems).to.deepEqual({})
                local gold = model.slots[4].options[2]
                expect({ gold.locked, gold.lockText, gold.reason }).to.deepEqual({
                    true, "LV 8", "Unlocks at weapon level 8"
                })
                input.build.skin = "gold"
                expect(editor.Gunsmith(input).problems).to.deepEqual({ "Gold (locked)" })
            end
        },
        {
            name = "Operator picker: a grant-only model shows its reward text; a granted model is selectable",
            func = function()
                local u, ops = unlocks(), assert(PW.Operators)
                local v = view(function(_, id)
                    return { Unlock = { level = false, hint = "Earn the event medal" },
                        Price = id == "priced" and 2000 or nil }
                end)
                local owned = false
                v.granted = function(key) return owned and key == "models:reward" end
                ---@param id string
                ---@param name string
                ---@return PW.OperatorEconomyInput
                local function model(id, name)
                    return { id = id, name = name, path = "models/player/kleiner.mdl",
                        requirement = u._Requirement(v, "models", id) }
                end
                local function cards()
                    return ops.Cards(ops.List({
                        economy = { model("reward", "Event winner"), model("priced", "Store alternative") },
                        unlocked = function(id) return (u._Decide(v, "models", id)) end
                    }), "models:reward")
                end
                local locked, fallback = cards()
                expect(fallback).to.equal("auto")
                expect({ locked[2].locked, locked[2].lockText, locked[2].reason })
                    .to.deepEqual({ true, "REWARD", "Earn the event medal" })
                expect({ locked[3].lockText, locked[3].reason, locked[3].text })
                    .to.deepEqual({ "2000 CR", "Buy it in the STORE for 2000 CR", "Earn the event medal" })
                owned = true
                local available, selected = cards()
                expect(available[2].locked).to.beFalse()
                expect(available[2].reason).to.beNil()
                expect(selected).to.equal("models:reward")
            end
        },
        {
            name = "Store: a granted item is OWNED and its texts no longer mention the level",
            func = function()
                local store = assert(assert(PW.UI).Store)
                ---@type PW.EconomyOffer
                local offer = { key = "models:reward", kind = "models", id = "reward", name = "Reward Operator",
                    price = 600, bundle = false, items = { { key = "models:reward", kind = "models", id = "reward" } } }
                ---@type PW.UIStoreFacts
                local facts = { currency = 900, owned = function(key) return key == offer.key end,
                    unlocked = function() return true end }
                expect(store.OfferState(offer, facts)).to.equal("owned")
                expect(store.OfferCards({ offer }, facts)[1].badge).to.equal("OWNED")
                expect(store.BuyButton(offer, "owned", facts.currency).reason).to.equal("You own this item")
                local otherwiseUnlocked = table.Copy(facts) --[[@as PW.UIStoreFacts]]
                otherwiseUnlocked.owned = function() return false end
                expect(store.OfferCards({ offer }, otherwiseUnlocked)[1].footer).to.equal("Already unlocked")
                local result = { key = offer.key, ok = false, reason = "unlocked", currency = 900 }
                expect(store.ResultText(result, offer.name)).to.equal("Reward Operator is already unlocked")
                ---@type PW.UIStoreOwnershipCheck
                local function purchased(kind, id) return kind == "bundles" and id == "special" end
                ---@type PW.UIStoreOwnershipCheck
                local function entitled(kind, id) return kind == "models" and id == "reward" end
                expect(store._OwnsKey(offer.key, purchased, entitled)).to.beTrue()
                expect(store._OwnsKey("bundles:special", purchased, entitled)).to.beTrue()
                expect(store._OwnsKey("bundles:unknown", purchased, entitled)).to.beFalse()
            end
        },
        {
            name = "Next unlocks: grant-only items are left out; table and integer levels both count",
            func = function()
                local progress = assert(assert(PW.UI).Progress)
                local nextUp = progress.NextUnlocks({ perks = {
                    reward = { Unlock = false }, weekly = { Unlock = { level = false, reward = "challenge" } },
                    integer = { Unlock = 10 }, tableLevel = { Unlock = { level = 8 } },
                    invalid = { Unlock = { level = math.huge } }, hidden = { Unlock = 7, Hidden = true }
                } }, 1)
                expect(#nextUp).to.equal(2)
                expect({ nextUp[1].id, nextUp[1].level, nextUp[2].id, nextUp[2].level })
                    .to.deepEqual({ "tableLevel", 8, "integer", 10 })
            end
        }
    }
}
