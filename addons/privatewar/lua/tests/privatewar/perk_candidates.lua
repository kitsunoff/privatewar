-- All twelve user-approved candidates. Existing four perks are a frozen regression baseline.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "approved perk or public consumer is missing")
    return value
end

---@param id string
---@return table<string, any>
local function definition(id)
    return must(must(PW.Registries.perks).Get(id)) --[[@as table<string, any>]]
end

---@type { id: string, group: integer, method?: string, stats?: table<string, number>, flag?: string }[]
local candidates = {
    { id = "stockpile", group = 1, method = "OnEquip" },
    { id = "soft_landing", group = 1, stats = { fall_damage = 0.5 } },
    { id = "flash_guard", group = 1, stats = { flash_strength = 0.5 } },
    { id = "fleet_foot", group = 1, stats = { move_speed = 1.10 } },
    { id = "quick_draw", group = 2, stats = { draw_time = 0.75 } },
    { id = "sightline", group = 2, stats = { ads_time = 0.8 } },
    { id = "recoil_control", group = 2, stats = { recoil = 0.8 } },
    { id = "scavenger", group = 2, method = "OnKill" },
    { id = "quiet_steps", group = 3, flag = "SilentFootsteps" },
    { id = "ghost", group = 3, method = "OnEquip" },
    { id = "retaliation", group = 3, method = "OnDamaged" },
    { id = "continuity", group = 3, method = "OnEquip" }
}

---@type table<string, any>[]
local cases = {}
for _, candidate in ipairs(candidates) do
    cases[#cases + 1] = {
        name = "Approved perk: " .. candidate.id .. " has frozen group cost unlock and implemented effect declaration",
        func = function()
            local def = definition(candidate.id)
            expect(def:IsValid()).to.beTrue()
            expect(def.Group).to.equal(candidate.group)
            expect(def.Cost).to.equal(1)
            expect(def.Unlock).to.equal(1)
            expect(isstring(def.Name) and #def.Name > 0).to.beTrue()
            expect(isstring(def.Description) and #def.Description > 0).to.beTrue()
            if candidate.stats ~= nil then expect(def.Stats).to.deepEqual(candidate.stats) end
            if candidate.method ~= nil then expect(isfunction(def[candidate.method])).to.beTrue() end
            if candidate.flag ~= nil then expect(def[candidate.flag]).to.beTrue() end
            local slot = { id = "perk" .. candidate.group, kind = "perks", group = candidate.group }
            expect(must(PW.Perks)._GroupError(slot, def)).to.beNil()
            slot.group = candidate.group % 3 + 1
            expect(must(PW.Perks)._GroupError(slot, def)).to.exist()
        end
    }
end

cases[#cases + 1] = {
    name = "Baseline: Adrenaline Ready Up Sleight of Hand and Flak Jacket retain their original gameplay",
    func = function()
        expect(definition("ready_up").Stats).to.deepEqual({ sprint_to_fire = 0.6 })
        expect(definition("sleight_of_hand").Stats).to.deepEqual({ reload_time = 0.65 })
        expect(definition("flak_jacket").Group).to.equal(1)
        expect(definition("adrenaline").Group).to.equal(3)
        expect(isfunction(definition("flak_jacket").OnEquip)).to.beTrue()
        expect(isfunction(definition("adrenaline").OnKill)).to.beTrue()
    end
}

cases[#cases + 1] = {
    name = "Stats: new weapon multipliers compose with reload wildcard and mode without partial overwrites",
    func = function()
        local lib = must(PW.Perks)
        local product = lib._Multiply({ {
            definition("quick_draw").Stats, definition("sightline").Stats,
            definition("recoil_control").Stats, definition("sleight_of_hand").Stats
        }, { { draw_time = 0.5, recoil = 1.25 } }, { { ads_time = 1.5 } } })
        expect(product.draw_time).to.equal(0.375)
        expect(math.abs(product.ads_time - 1.2) < 1e-9).to.beTrue()
        expect(product.recoil).to.equal(1)
        expect(product.reload_time).to.equal(0.65)
        expect(lib._WeaponMods(product, { "draw_time", "ads_time", "recoil", "reload_time" }))
            .to.deepEqual(product)
    end
}

return { groupName = "PW all twelve approved perk candidates", cases = cases }
