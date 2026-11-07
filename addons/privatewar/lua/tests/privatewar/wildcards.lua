-- T-4.3 wildcards (TASKS.md, "Mandatory test cases" T-4.3; 05-loadout.md d.2, d.5): ModifySlots changes validation,
-- the budget counts wildcards, removing the wildcard restores the slots, an invalid combination is rejected, stat
-- multipliers reach PW.Perks.StatSource. Pure cases over plain data (fake catalogue, injected context) plus wiring
-- cases over the real registries and sample wildcards. No bots.

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
        pwt_smg = { Category = "smg", Attachments = {} },
        pwt_ar = { Category = "ar" },
        pwt_pistol = { Category = "pistol" }
    },
    perks = { pwt_a = { Group = 1 }, pwt_b = { Group = 1 } },
    wildcards = {
        pwt_overkill = {
            Name = "Overkill",
            ---@param slots table<string, PW.LoadoutSlot>
            ModifySlots = function(_, slots)
                ---@type string[]
                local filter = {}
                for _, entry in ipairs(slots.secondary.filter or {}) do filter[#filter + 1] = entry end
                for _, entry in ipairs(slots.primary.filter or {}) do filter[#filter + 1] = entry end
                slots.secondary.filter = filter
            end
        },
        pwt_greed = {
            Name = "Greed",
            ---@param slots table<string, PW.LoadoutSlot>
            ModifySlots = function(_, slots) slots.perk1.count = 2 end
        },
        pwt_gunfighter = {
            Name = "Gunfighter",
            Cost = 2,
            Stats = { recoil = 0.9 },
            ---@param slots table<string, PW.LoadoutSlot>
            ModifySlots = function(_, slots) slots.primary.maxattachments = slots.primary.maxattachments + 1 end
        },
        pwt_broken = { Name = "Broken", ModifySlots = function() error("boom") end },
        pwt_rogue = {
            Name = "Rogue",
            ---@param slots table<string, PW.LoadoutSlot>
            ModifySlots = function(_, slots) slots.wildcard.count = 9 end
        },
        pwt_extra = {
            Name = "Extra",
            ---@param slots table<string, PW.LoadoutSlot>
            ModifySlots = function(_, slots)
                slots.primary2 = { id = "primary2", kind = "weapons", filter = { "ar" } }
            end
        }
    }
}

---@param kind string
---@param id string
---@return table<string, any>?
local function lookup(kind, id)
    local data = catalogue[kind]
    return data ~= nil and data[id] or nil
end

---@return table<string, PW.LoadoutSlot>
local function baseSlots()
    return {
        primary = { id = "primary", kind = "weapons", filter = { "ar", "smg" } },
        secondary = { id = "secondary", kind = "weapons", filter = { "pistol" } },
        perk1 = { id = "perk1", kind = "perks", group = 1 },
        wildcard = { id = "wildcard", kind = "wildcards", count = 2 }
    }
end

---@param over table<string, any>?
---@return PW.LoadoutContext
local function ctxWith(over)
    local ctx = { lookup = lookup, budget = 10, maxattachments = 2 }
    for key, value in pairs(over or {}) do ctx[key] = value end
    return ctx --[[@as PW.LoadoutContext]]
end

---@param value PW.Loadout
---@param ctx PW.LoadoutContext?
---@return boolean, string?
local function validate(value, ctx)
    return loadout()._Validate(baseSlots(), value, lookup, ctx or ctxWith())
end

---@return PW.PerksLib
local function perks()
    return must(PW.Perks)
end

return {
    groupName = "PW wildcards",
    cases = {
        {
            name = "ModifySlots: Overkill puts a primary weapon in the secondary slot; without it the pick is rejected",
            func = function()
                local value = { primary = "pwt_smg", secondary = "pwt_ar" }
                local ok, err = validate(value)
                expect(ok).to.beFalse()
                expect(err).to.exist()
                value.wildcard = "pwt_overkill"
                expect(validate(value)).to.beTrue()
            end
        },
        {
            name = "ModifySlots: an extra perk in a group is accepted only with the wildcard",
            func = function()
                local value = { primary = "pwt_smg", perk1 = { "pwt_a", "pwt_b" } }
                expect(validate(value)).to.beFalse()
                value.wildcard = "pwt_greed"
                expect(validate(value)).to.beTrue()
                value.perk1 = { "pwt_a", "pwt_b", "pwt_a" }
                expect(validate(value)).to.beFalse()
            end
        },
        {
            name = "ModifySlots: an extra attachment raises the cap of the weapon slot by one",
            func = function()
                local build = { primary = { a = "x", b = "y", c = "z" } }
                local value = { primary = "pwt_smg", builds = build }
                local ok, err = validate(value, ctxWith({ budget = 0 }))
                expect(ok).to.beFalse()
                expect(err).to.exist()
                value.wildcard = "pwt_gunfighter"
                expect(validate(value, ctxWith({ budget = 0 }))).to.beTrue()
                build.primary.d = "w"
                expect(validate(value, ctxWith({ budget = 0 }))).to.beFalse()
            end
        },
        {
            name = "ModifySlots: a wildcard may add a new slot, and the pick in it is validated",
            func = function()
                local value = { primary = "pwt_smg", primary2 = "pwt_ar", wildcard = "pwt_extra" }
                expect(validate(value)).to.beTrue()
                value.primary2 = "pwt_pistol"
                expect(validate(value)).to.beFalse()
                value.primary2, value.wildcard = "pwt_ar", nil
                local ok, err = validate(value)
                expect(ok).to.beFalse()
                expect(err).to.exist()
            end
        },
        {
            name = "Budget: the wildcard itself and the extra picks it allows count against the budget",
            func = function()
                local slots = baseSlots()
                local plain = { primary = "pwt_smg", secondary = "pwt_pistol" }
                expect(loadout()._Cost(slots, plain, ctxWith())).to.equal(2)
                local with = { primary = "pwt_smg", secondary = "pwt_pistol", wildcard = "pwt_gunfighter" }
                expect(loadout()._Cost(slots, with, ctxWith())).to.equal(4)
                local greedy = { primary = "pwt_smg", perk1 = { "pwt_a", "pwt_b" }, wildcard = "pwt_greed" }
                expect(loadout()._Cost(slots, greedy, ctxWith())).to.equal(4)
            end
        },
        {
            name = "Budget: a wildcard that pushes the loadout over the budget is rejected",
            func = function()
                local value = { primary = "pwt_smg", secondary = "pwt_pistol", wildcard = "pwt_gunfighter" }
                expect(validate(value, ctxWith({ budget = 4 }))).to.beTrue()
                local ok, err = validate(value, ctxWith({ budget = 3 }))
                expect(ok).to.beFalse()
                expect(err).to.exist()
                expect(validate(value, ctxWith({ budget = 0 }))).to.beTrue()
            end
        },
        {
            name = "Removing the wildcard restores the slots (the effective set equals the declared set)",
            func = function()
                local slots = baseSlots()
                local with = loadout()._EffectiveSlots(slots, { wildcard = "pwt_overkill" }, lookup)
                expect(#with.secondary.filter).to.equal(3)
                expect(loadout()._EffectiveSlots(slots, { primary = "pwt_smg" }, lookup)).to.deepEqual(baseSlots())
                -- The declared slots are never mutated.
                expect(slots).to.deepEqual(baseSlots())
                local value = { primary = "pwt_smg", secondary = "pwt_ar", wildcard = "pwt_overkill" }
                expect(validate(value)).to.beTrue()
                value.wildcard = nil
                expect(validate(value)).to.beFalse()
            end
        },
        {
            name = "Invalid combination: the same wildcard twice, an unknown wildcard and a wrong kind are rejected",
            func = function()
                local ok, err = validate({ primary = "pwt_smg", wildcard = { "pwt_greed", "pwt_greed" } })
                expect(ok).to.beFalse()
                expect(err).to.exist()
                expect(validate({ primary = "pwt_smg", wildcard = "pwt_missing" })).to.beFalse()
                expect(validate({ primary = "pwt_smg", wildcard = "pwt_smg" })).to.beFalse()
                expect(validate({ primary = "pwt_smg", wildcard = { "pwt_greed", "pwt_overkill", "pwt_extra" } }))
                    .to.beFalse()
            end
        },
        {
            name = "Invalid combination: no extra wildcard slots from a wildcard; a failing ModifySlots is ignored",
            func = function()
                local three = { primary = "pwt_smg", wildcard = { "pwt_rogue", "pwt_greed", "pwt_overkill" } }
                expect(validate(three)).to.beFalse()
                -- pwt_broken errors: the loadout is judged by the declared slots plus the other wildcard.
                local both = { "pwt_broken", "pwt_greed" }
                local mixed = { primary = "pwt_smg", perk1 = { "pwt_a", "pwt_b" }, wildcard = both }
                expect(validate(mixed)).to.beTrue()
                local alone = { primary = "pwt_smg", perk1 = { "pwt_a", "pwt_b" }, wildcard = "pwt_broken" }
                expect(validate(alone)).to.beFalse()
            end
        },
        {
            name = "Repair: the pick a wildcard allows is kept; without the wildcard it is removed",
            func = function()
                local slots = baseSlots()
                local value = { primary = "pwt_smg", secondary = "pwt_ar", wildcard = "pwt_overkill" }
                local kept, removed = loadout()._RepairClass(slots, value, ctxWith())
                expect(kept.secondary).to.equal("pwt_ar")
                expect(#removed).to.equal(0)
                value.wildcard = nil
                kept, removed = loadout()._RepairClass(slots, value, ctxWith())
                expect(kept.secondary).toNot.exist()
                expect(#removed).to.equal(1)
            end
        },
        {
            name = "Stats: the equipped wildcards feed PW.Perks.StatSource and multiply with the perk chain",
            func = function()
                expect(PW._PerkSources.wildcards).to.exist()
                local ply = fakePlayer()
                expect(loadout()._WildcardStats({ "pwt_gunfighter", "pwt_greed", "pwt_missing" }, lookup))
                    .to.deepEqual({ { recoil = 0.9 } })
                -- The source reads the real registries: the sample Gunfighter has Stats = { recoil = 0.95 }.
                local real = loadout()._RegistryLookup
                loadout()._EquipWildcards(ply, { wildcard = "gunfighter" }, real)
                local lists = { { { recoil = 0.5 } }, must(PW._PerkSources.wildcards)(ply) }
                expect(math.abs(perks()._Multiply(lists).recoil - 0.475) < 0.0001).to.beTrue()
                loadout()._EquipWildcards(ply, { primary = "pwt_smg" }, real)
                expect(must(PW._PerkSources.wildcards)(ply)).to.deepEqual({})
            end
        },
        {
            name = "Wiring: the kind, the wildcard slot and three sample wildcards are registered",
            func = function()
                local registry = must(PW.Registries.wildcards)
                local slot = must(loadout().GetSlot("wildcard"))
                expect(slot.kind).to.equal("wildcards")
                for _, id in ipairs({ "overkill", "perk_greed", "gunfighter" }) do
                    local def = must(registry.Get(id))
                    expect(isstring(def.Name)).to.beTrue()
                    expect(isfunction(def.ModifySlots)).to.beTrue()
                end
            end
        },
        {
            name = "Wiring: sample wildcards on stock content pass the real Validate and cost what the design says",
            func = function()
                local base = { primary = "weapon_ar2", secondary = "weapon_pistol", melee = "weapon_crowbar",
                    lethal = "frag", tactical = "flash", perk1 = "flak_jacket", perk2 = "sleight_of_hand",
                    perk3 = "adrenaline" }
                expect(loadout().Cost(base)).to.equal(8)
                local overkill = table.Copy(base)
                overkill.secondary, overkill.wildcard = "weapon_smg1", "overkill"
                expect(loadout().Validate(fakePlayer(), overkill)).to.beTrue()
                expect(loadout().Cost(overkill)).to.equal(9)
                ---@type PW.Loadout
                local denied = table.Copy(overkill)
                denied.wildcard = nil
                expect(loadout().Validate(fakePlayer(), denied)).to.beFalse()
                local greed = table.Copy(base)
                greed.perk1, greed.wildcard = { "flak_jacket", "ready_up" }, "perk_greed"
                expect(loadout().Validate(fakePlayer(), greed)).to.beTrue()
                expect(loadout().Cost(greed)).to.equal(10)
                local gunfighter = table.Copy(base)
                gunfighter.wildcard = "gunfighter"
                expect(loadout().Validate(fakePlayer(), gunfighter)).to.beTrue()
                expect(loadout().Cost(gunfighter)).to.equal(9)
            end
        }
    }
}
