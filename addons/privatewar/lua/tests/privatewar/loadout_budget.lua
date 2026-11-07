-- T-4.2 Pick X: budget sum, budget 0 = unlimited, free cosmetic attachments, PW_LoadoutCost override, maxattachments,
-- bans (TASKS.md, "Mandatory test cases" T-4.2; 05-loadout.md d.2, d.3, d.7). Pure cases over plain data: the context
-- (budget, cap, bans, cosmetic check) is injected, so no match, bots or settings snapshot are needed.

local listenerId = "PW_Test_LoadoutBudget"

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.LoadoutLib
local function loadout()
    return must(PW.Loadout)
end

---@return Player
local function fakePlayer()
    return { IsValid = function() return true end } --[[@as Player]]
end

local catalogue = {
    weapons = {
        pwt_smg = {
            Category = "smg",
            Attachments = {
                optic = {}, grip = {}, suppressor = { Cost = 2 }, camo_gold = { Cosmetic = true },
                secret = { Hidden = true }
            },
            Camos = { gold = {} }
        },
        pwt_sniper = { Category = "sniper", Cost = 2 },
        pwt_pistol = { Category = "pistol" }
    },
    perks = { pwt_perk = { Group = 1 }, pwt_pricey = { Group = 2, Cost = 3 } },
    streaks = { pwt_uav = { Cost = 9 } }
}

---@param kind string
---@param id string
---@return table<string, any>?
local function lookup(kind, id)
    local data = catalogue[kind]
    return data ~= nil and data[id] or nil
end

local slots = {
    primary = { id = "primary", kind = "weapons", filter = { "smg", "sniper" } },
    secondary = { id = "secondary", kind = "weapons", filter = { "pistol" } },
    perk1 = { id = "perk1", kind = "perks" },
    streak1 = { id = "streak1", kind = "streaks" }
}

---@param over table<string, any>?
---@return PW.LoadoutContext
local function ctxWith(over)
    local ctx = { lookup = lookup, budget = 10, maxattachments = 5 }
    for key, value in pairs(over or {}) do ctx[key] = value end
    return ctx --[[@as PW.LoadoutContext]]
end

---@param ctx PW.LoadoutContext
---@param value PW.Loadout
---@return boolean, string?
local function validate(ctx, value)
    return loadout()._Validate(slots, value, lookup, ctx)
end

return {
    groupName = "PW loadout budget",
    beforeEach = function() hook.Remove("PW_LoadoutCost", listenerId) end,
    afterEach = function() hook.Remove("PW_LoadoutCost", listenerId) end,
    cases = {
        {
            name = "Budget: the sum of weapon, attachment and perk costs counts against the budget",
            func = function()
                -- smg 1 + optic 1 + suppressor 2 + pistol 1 + perk 3 = 8
                local value = {
                    primary = "pwt_smg", secondary = "pwt_pistol", perk1 = "pwt_pricey",
                    builds = { primary = { optic = "optic", muzzle = "suppressor" } }
                }
                expect(loadout()._Cost(slots, value, ctxWith())).to.equal(8)
                expect(validate(ctxWith({ budget = 8 }), value)).to.beTrue()
                local ok, err = validate(ctxWith({ budget = 7 }), value)
                expect(ok).to.beFalse()
                expect(err).to.exist()
                expect(string.find(must(err), "budget", 1, true)).to.exist()
            end
        },
        {
            name = "Budget: killstreaks are outside the budget",
            func = function()
                local value = { primary = "pwt_smg", streak1 = "pwt_uav" }
                expect(loadout()._Cost(slots, value, ctxWith())).to.equal(1)
            end
        },
        {
            name = "Budget: 0 means unlimited",
            func = function()
                local value = {
                    primary = "pwt_sniper", secondary = "pwt_pistol", perk1 = "pwt_pricey",
                    builds = { primary = { a = "optic", b = "grip", c = "suppressor" } }
                }
                expect(validate(ctxWith({ budget = 0 }), value)).to.beTrue()
                expect(validate(ctxWith({ budget = 5 }), value)).to.beFalse()
            end
        },
        {
            name = "Budget: cosmetic attachments are free and do not count toward the cap",
            func = function()
                local value = {
                    primary = "pwt_smg",
                    builds = { primary = { skin = "camo_gold", camo = "gold", optic = "optic" } }
                }
                -- smg 1 + optic 1; the skin (Cosmetic entry) and the camo (Camos) are free
                expect(loadout()._Cost(slots, value, ctxWith())).to.equal(2)
                expect(validate(ctxWith({ budget = 2, maxattachments = 1 }), value)).to.beTrue()
                -- The base adapter marks a slot or an option as cosmetic.
                local isCosmetic = function(_, slotId) return slotId == "sticker" end
                local sticker = { primary = "pwt_smg", builds = { primary = { sticker = "optic" } } }
                expect(loadout()._Cost(slots, sticker, ctxWith({ isCosmetic = isCosmetic }))).to.equal(1)
                expect(loadout()._Cost(slots, sticker, ctxWith())).to.equal(2)
            end
        },
        {
            name = "Cost: PW_LoadoutCost overrides the cost of an item",
            func = function()
                hook.Add("PW_LoadoutCost", listenerId, function(item)
                    if item.kind == "weapons" and item.entity.Category == "sniper" then return 4 end
                    if item.attachment == "grip" then return 0 end
                    return nil
                end)
                local value = { primary = "pwt_sniper", builds = { primary = { g = "grip", o = "optic" } } }
                -- sniper 4 (override of its own Cost 2) + grip 0 + optic 1
                expect(loadout()._Cost(slots, value, ctxWith())).to.equal(5)
                -- A bad answer (negative) is ignored.
                hook.Add("PW_LoadoutCost", listenerId, function() return -3 end)
                expect(loadout()._Cost(slots, { primary = "pwt_sniper" }, ctxWith())).to.equal(2)
            end
        },
        {
            name = "Cost: the default is 1, an author's Cost field applies",
            func = function()
                expect(loadout()._Cost(slots, { primary = "pwt_smg" }, ctxWith())).to.equal(1)
                expect(loadout()._Cost(slots, { primary = "pwt_sniper" }, ctxWith())).to.equal(2)
                expect(loadout()._Cost(slots, { perk1 = "pwt_perk" }, ctxWith())).to.equal(1)
            end
        },
        {
            name = "maxattachments: more non-cosmetic attachments than the cap are rejected",
            func = function()
                local value = {
                    primary = "pwt_smg", builds = { primary = { a = "optic", b = "grip", c = "suppressor" } }
                }
                expect(validate(ctxWith({ budget = 0, maxattachments = 3 }), value)).to.beTrue()
                local ok, err = validate(ctxWith({ budget = 0, maxattachments = 2 }), value)
                expect(ok).to.beFalse()
                expect(string.find(must(err), "attachments", 1, true)).to.exist()
                -- A slot's own cap (a wildcard raises or lowers it) wins over the setting.
                local custom = { primary = { id = "primary", kind = "weapons", maxattachments = 4 } }
                local loose = ctxWith({ budget = 0, maxattachments = 2 })
                expect(loadout()._Validate(custom, value, lookup, loose)).to.beTrue()
            end
        },
        {
            name = "Bans: a banned weapon is rejected",
            func = function()
                local ctx = ctxWith({ bannedWeapons = { pwt_sniper = true } })
                local ok, err = validate(ctx, { primary = "pwt_sniper" })
                expect(ok).to.beFalse()
                expect(string.find(must(err), "pwt_sniper", 1, true)).to.exist()
                expect(validate(ctx, { primary = "pwt_smg" })).to.beTrue()
            end
        },
        {
            name = "Bans: a banned attachment and a hidden attachment are rejected",
            func = function()
                local ctx = ctxWith({ bannedAttachments = { suppressor = true } })
                local value = { primary = "pwt_smg", builds = { primary = { m = "suppressor" } } }
                local ok, err = validate(ctx, value)
                expect(ok).to.beFalse()
                expect(string.find(must(err), "suppressor", 1, true)).to.exist()
                expect(validate(ctx, { primary = "pwt_smg", builds = { primary = { o = "optic" } } })).to.beTrue()
                local hidden = { primary = "pwt_smg", builds = { primary = { o = "secret" } } }
                expect(validate(ctxWith(), hidden)).to.beFalse()
            end
        },
        {
            name = "Build: a malformed builds table is rejected, a cleared option (false) is free",
            func = function()
                local unknown = { primary = "pwt_smg", builds = { nothere = { a = "optic" } } }
                expect(validate(ctxWith(), unknown)).to.beFalse()
                local empty = { primary = "pwt_smg", builds = { secondary = { a = "optic" } } }
                expect(validate(ctxWith(), empty)).to.beFalse()
                local badOption = { primary = "pwt_smg", builds = { primary = { a = 5 } } }
                expect(validate(ctxWith(), badOption --[[@as any]])).to.beFalse()
                local notTable = { primary = "pwt_smg", builds = "x" }
                expect(validate(ctxWith(), notTable --[[@as any]])).to.beFalse()
                local cleared = { primary = "pwt_smg", builds = { primary = { a = false } } }
                expect(loadout()._Cost(slots, cleared, ctxWith())).to.equal(1)
                expect(validate(ctxWith(), cleared)).to.beTrue()
            end
        },
        {
            name = "Validate without a context keeps the T-4.1 rules (no budget, no bans)",
            func = function()
                local value = { primary = "pwt_sniper", perk1 = "pwt_pricey", builds = { primary = { a = "optic" } } }
                expect(loadout()._Validate(slots, value, lookup)).to.beTrue()
            end
        },
        {
            name = "Settings: the context reads budget, cap and the two ban sets (set as lookup or list)",
            func = function()
                local values = {
                    ["loadout.budget"] = 12, ["loadout.maxattachments"] = 3,
                    ["loadout.bannedweapons"] = { pwt_sniper = true },
                    ["loadout.bannedattachments"] = { "grip" }
                }
                local ctx = loadout()._Context(function(id) return values[id] end)
                expect(ctx.budget).to.equal(12)
                expect(ctx.maxattachments).to.equal(3)
                expect(must(ctx.bannedWeapons).pwt_sniper).to.beTrue()
                expect(must(ctx.bannedAttachments).grip).to.beTrue()
                -- Missing settings fall back to the design defaults.
                local fallback = loadout()._Context(function() return nil end)
                expect(fallback.budget).to.equal(10)
                expect(fallback.maxattachments).to.equal(5)
                expect(next(must(fallback.bannedWeapons))).to.beNil()
            end
        },
        {
            name = "Validate: the public entry applies the settings and the slot rules",
            func = function()
                expect(loadout().Validate(fakePlayer(), { primary = "pwt_smg" }, lookup)).to.beTrue()
                expect(loadout().Validate(fakePlayer(), { primary = "pwt_nothere" }, lookup)).to.beFalse()
            end
        }
    }
}
