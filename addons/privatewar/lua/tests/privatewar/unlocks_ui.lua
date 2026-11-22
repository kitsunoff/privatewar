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
        },
        {
            name = "NEW badge: a granted, unseen key is new; marking it seen clears it; purchases are not new",
            func = function()
                local ui = assert(PW.UI)
                local store = assert(ui.Store)
                local gift, purchase = "models:reward", "models:bought"
                ---@type table<string, PW.UnlockGrantMeta>
                local grants = { [gift] = { source = "purchase", at = 1 } } -- This is still a grant.
                ---@type table<string, true>
                local seen = {}
                ---@type PW.EconomyOffer
                local offer = {
                    kind = "bundles", id = "offer", key = "bundles:offer", name = "Offer", price = 1, bundle = true,
                    items = { { kind = "models", id = "reward", key = gift },
                        { kind = "models", id = "bought", key = purchase } }
                }
                local items = store.ItemViews(offer, function() return nil end, {
                    currency = 0, owned = function() return true end, unlocked = function() return true end,
                    isNew = function(key) return store._IsUnlockNew(grants, seen, key) end
                })
                local cards = store.ItemCards(items)
                expect(cards[1].new).to.beTrue()
                expect(cards[2].new == true).to.beFalse()
                expect(cards[2].badge).to.equal("OWNED")
                expect(store._HasUnseenGrants(grants, seen)).to.beTrue()
                ui.Seen.Mark(seen, ui.Tabs.SeenKey("loadout"))
                expect(store._HasUnseenGrants(grants, seen)).to.beTrue()
                expect(store._FocusUnlockCard(grants, seen, purchase, cards[2])).to.beFalse()
                expect(seen["unlock:" .. purchase]).to.beNil()
                expect(store._FocusUnlockCard(grants, seen, gift, cards[1])).to.beTrue()
                expect(ui.Cards.View(cards, nil)[1].new).to.beFalse()
                expect(cards[1].badge).to.equal("OWNED")
                expect(seen["unlock:" .. gift]).to.beTrue()
                expect(store._HasUnseenGrants(grants, seen)).to.beFalse()
                expect(store._FocusUnlockCard(grants, seen, gift, cards[1])).to.beFalse()
                grants["perks:scavenger"] = { source = "challenge", at = 2 }
                expect(store._HasUnseenGrants(grants, seen)).to.beTrue()
                grants["perks:scavenger"] = nil
                expect(store._HasUnseenGrants(grants, seen)).to.beFalse()
            end
        },
        {
            name = "Toast: a granted delta queues one unlock popup per grant group with the item name and source text",
            func = function()
                local u, hud = unlocks(), assert(PW.HUD)
                local queue = hud._MedalNew()
                ---@type PW.ProgressionLocal
                local state = {}
                ---@type PW.ProgressionDelta
                local delta = { session = 1, seq = 1, xp = 0, weapons = {}, granted = {
                    ["perks:scavenger"] = { source = "challenge", at = 1, grant = "weekly:1" },
                    ["perks:soft_landing"] = { source = "event", at = 1, grant = "event:1" },
                    ["models:swat"] = { source = "event", at = 1, grant = "event:1" }
                } }
                ---@param name string
                ---@param ... any
                local function onDelta(name, ...)
                    if name ~= "PW_UnlockGranted" then return end
                    ---@type any[]
                    local args = { ... }
                    hud._QueueUnlock(queue, args[2], args[3], "LIVE")
                end
                ---@type PW.UnlockClientIO
                local io = { writeUnlocks = function() end, writeProgression = function() end, notify = onDelta }
                local ply = NULL --[[@as Player]]
                u._ClientDelta(state, delta, ply, io)
                u._ClientDelta(state, delta, ply, io)
                expect(queue.count).to.equal(2)
                expect({ queue.list[1].kind, queue.list[1].name, queue.list[1].label, queue.list[1].sourceText })
                    .to.deepEqual({ "unlock", "UNLOCKED", "Scavenger", "Challenge reward" })
                expect({ queue.list[2].kind, queue.list[2].name, queue.list[2].label, queue.list[2].sourceText })
                    .to.deepEqual({ "unlock", "UNLOCKED", "2 items", "Event reward" })
            end
        },
        {
            name = "Unlock toast phases: PREMATCH can show grants without starting score, medal or level-up popups",
            func = function()
                local hud = assert(PW.HUD)
                for _, phase in ipairs({ "PREMATCH", "LIVE", "POSTMATCH", "LOBBY", "VOTE" }) do
                    local queue = hud._MedalNew()
                    local oldVisible = phase == "LIVE" or phase == "POSTMATCH"
                    local grantVisible = oldVisible or phase == "PREMATCH"
                    hud._MedalAdd(queue, "first_blood", "First Blood", 100, 0)
                    local medal = queue.list[1]
                    local levelUp = hud._LevelUpAdd(queue, 9)
                    expect(hud._ScorePopupPhase(phase)).to.equal(oldVisible)
                    expect(hud._QueueUnlock(queue, { "perks:scavenger" }, "admin", phase)).to.equal(grantVisible)
                    local current = hud._PopupForPhase(queue, 1, phase)
                    if phase == "PREMATCH" then
                        local grant = assert(current)
                        expect(grant.kind).to.equal("unlock")
                        expect(grant.sourceText).to.equal("Granted by the host")
                        expect(medal.startedAt).to.beNil()
                        expect(levelUp.startedAt).to.beNil()
                        expect(hud._PopupForPhase(queue, 1.1, "LIVE")).to.equal(grant)
                    elseif oldVisible then
                        expect(current).to.equal(medal)
                        expect(hud._PopupForPhase(queue, 2 + hud.MedalDuration, phase)).to.equal(levelUp)
                        local grant = hud._PopupForPhase(queue, 3 + 2 * hud.MedalDuration, phase)
                        expect(assert(grant).kind).to.equal("unlock")
                    else
                        expect(current).to.beNil()
                        expect(queue.count).to.equal(2)
                        expect(medal.startedAt).to.beNil()
                        expect(levelUp.startedAt).to.beNil()
                    end
                end
            end
        }
    }
}
