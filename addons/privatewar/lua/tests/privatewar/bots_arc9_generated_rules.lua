-- Match rules are the existing validator, not a separate generated-build allowance.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@return PW.Loadout
local function candidate()
    return { primary = "rifle", secondary = "pistol", melee = "knife", lethal = "frag", tactical = "flash",
        perk1 = "flak_jacket", perk2 = "quick_draw", perk3 = "adrenaline",
        builds = { primary = { optic = "optic", camo = "camo" } } }
end

---@param kind string
---@param id string
---@return table<string, any>?
local function lookup(kind, id)
    if kind == "weapons" then
        local categories = { rifle = "ar", pistol = "pistol" }
        if id == "knife" then return { Kind = "melee" } end
        return categories[id] ~= nil and { Category = categories[id] } or nil
    end
    return {}
end

---@return table<string, PW.LoadoutSlot>
local function slots()
    local out = {
        primary = { id = "primary", kind = "weapons", filter = { "ar" } },
        secondary = { id = "secondary", kind = "weapons", filter = { "pistol" } },
        melee = { id = "melee", kind = "weapons", filter = { "melee" } },
        lethal = { id = "lethal", kind = "equipment" }, tactical = { id = "tactical", kind = "equipment" }
    }
    for i = 1, 3 do out["perk" .. i] = { id = "perk" .. i, kind = "perks", group = i } end
    return out
end

---@return PW.LoadoutContext
local function context()
    return { lookup = lookup, budget = 10, maxattachments = 5,
        isCosmetic = function(_, _, option) return option == "camo" end }
end

return {
    groupName = "PW generated ARC9 match rules",
    cases = {
        {
            name = "Rules: generated picks obey exact Pick X costs, zero/unlimited budget and per-weapon cap",
            func = function()
                local loadout = must(PW.Loadout)
                local ctx, value = context(), candidate()
                expect(loadout._Cost(slots(), value, ctx)).to.equal(9)
                expect(loadout._Validate(slots(), value, lookup, ctx)).to.beTrue()
                ctx.budget = 8
                expect(loadout._Validate(slots(), value, lookup, ctx)).to.beFalse()
                ctx.budget = 0
                expect(loadout._Validate(slots(), value, lookup, ctx)).to.beTrue()
                ctx.maxattachments = 0
                expect(loadout._Validate(slots(), value, lookup, ctx)).to.beFalse()
            end
        },
        {
            name = "Rules: weapon and camo bans, disabled items, wrong slots and unknown slots are not bypassed",
            func = function()
                local loadout, ctx, value = must(PW.Loadout), context(), candidate()
                ctx.bannedWeapons = { rifle = true }
                expect(loadout._Validate(slots(), value, lookup, ctx)).to.beFalse()
                ctx.bannedWeapons, ctx.bannedAttachments = {}, { camo = true }
                expect(loadout._Validate(slots(), value, lookup, ctx)).to.beFalse()
                ctx.bannedAttachments = {}
                value.primary = "missing"
                expect(loadout._Validate(slots(), value, lookup, ctx)).to.beFalse()
                value.primary = "pistol"
                expect(loadout._Validate(slots(), value, lookup, ctx)).to.beFalse()
                value = candidate()
                value.extra = "rifle"
                expect(loadout._Validate(slots(), value, lookup, ctx)).to.beFalse()
            end
        },
        {
            name = "Cache isolation: match validation and spawn repair cannot mutate provider-owned cached builds",
            func = function()
                local entry = { ref = "generated:test", source = "generated", name = "Test", loadout = candidate() }
                local original = table.Copy(entry)
                local pool = {}
                must(PW.BotLoadouts).AppendCandidates(pool, { entry }, function(value)
                    value.primary = "edited_by_hook"
                    return true
                end)
                expect(pool[1].loadout.primary).to.equal("edited_by_hook")
                expect(entry).to.deepEqual(original)
                local builds = pool[1].loadout.builds --[[@as table<string, PW.Build>]]
                builds.primary.optic = nil
                expect(entry).to.deepEqual(original)
            end
        }
    }
}
