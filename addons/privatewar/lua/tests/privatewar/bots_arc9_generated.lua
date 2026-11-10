-- Generated candidates are bot-only data, never registered classes. All engine dependencies are injected here.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@return PW.Arc9BotLoadoutsLib
local function lib()
    return must(PW.Arc9BotLoadouts)
end

---@return PW.Arc9BotGenerationApi
local function api()
    return {
        weapons = function()
            ---@type PW.Arc9BotWeapon[]
            local out = {}
            for _, category in ipairs({ "smg", "ar", "shotgun", "lmg", "sniper", "pistol" }) do
                out[#out + 1] = { class = "w_" .. category, category = category, knife = false }
            end
            out[#out + 1] = { class = "knife", knife = true }
            return out
        end,
        slots = function() return { { id = "1", name = "Optic", cosmetic = false },
            { id = "2", name = "Camo", cosmetic = true } } end,
        options = function(_, slot)
            if slot == "2" then return { { id = "camo", name = "Camo", cosmetic = true } } end
            return { { id = "optic", name = "Optic", cosmetic = false },
                { id = "receiver", name = "Receiver", cosmetic = false } }
        end,
        role = function(id) return id == "camo" and "camo" or (id == "optic" and "optic" or nil) end,
        validate = function(_, build) return table.Copy(build), {} end,
        random = function(n) return n end
    }
end

---@param input? PW.Arc9BotGenerationApi
---@return PW.Arc9BotGenerationState
local function complete(input)
    local state = lib().New("map_a", input or api())
    for _ = 1, 10000 do
        lib().Step(state, function() return 0 end, 0.001, 8)
        if state.status ~= "working" then break end
    end
    return state
end

return {
    groupName = "PW generated ARC9 bot loadouts",
    skip = function() return PW.Arc9BotLoadouts == nil end,
    cases = {
        {
            name = "Generate: 18 additive candidates, three per archetype, coherent slots and pistol-only knife",
            func = function()
                local state = complete()
                expect(state.status).to.equal("ready")
                expect(#state.entries).to.equal(18)
                ---@type table<string, integer>
                local counts = {}
                for _, entry in ipairs(state.entries) do
                    local category = must(entry.category)
                    counts[category] = (counts[category] or 0) + 1
                    expect(entry.source).to.equal("generated")
                    expect(entry.loadout.melee).to.equal("knife")
                    expect(entry.loadout.lethal).to.equal("frag")
                    expect(entry.loadout.tactical).to.equal("flash")
                    if entry.category == "pistol" then
                        expect(entry.loadout.primary).to.beNil()
                        expect(entry.loadout.secondary).to.equal("w_pistol")
                        expect(entry.loadout.perk1).to.equal("flak_jacket")
                        expect(entry.loadout.perk3).to.equal("adrenaline")
                    end
                    local builds = (entry.loadout.builds or {}) --[[@as table<string, PW.Build>]]
                    for _, build in pairs(builds) do
                        expect(build["1"]).to.equal("optic")
                        expect(build["2"]).to.equal("camo")
                    end
                end
                for _, count in pairs(counts) do expect(count).to.equal(3) end
                expect(table.Count(counts)).to.equal(6)
            end
        },
        {
            name = "Unavailable: zero weapons, missing ARC9 and missing knife preserve an empty generated pool",
            func = function()
                local input = api()
                input.weapons = function() return {} end
                expect(#complete(input).entries).to.equal(0)
                expect(lib().Available(nil, nil)).to.beFalse()
                local noKnife = api()
                local weapons = noKnife.weapons()
                table.remove(weapons)
                noKnife.weapons = function() return weapons end
                local entries = complete(noKnife).entries
                expect(#entries).to.equal(15)
                for _, entry in ipairs(entries) do expect(entry.category ~= "pistol").to.beTrue() end
            end
        },
        {
            name = "Compatibility: invalid attachment and camo rejected by adapter fall back to base appearance",
            func = function()
                local input = api()
                input.validate = function() return {}, { ["1"] = "wrong_slot", ["2"] = "unknown_option" } end
                local state = complete(input)
                expect(#state.entries).to.equal(18)
                for _, entry in ipairs(state.entries) do
                    local builds = (entry.loadout.builds or {}) --[[@as table<string, PW.Build>]]
                    for _, build in pairs(builds) do
                        expect(next(build)).to.beNil()
                    end
                end
            end
        },
        {
            name = "Metadata: mislabeled special guns are excluded, LMG families corrected locally, knife retained",
            func = function()
                expect(lib().DescribeWeapon("arc9_cod2019_lm_minigun", "shotgun", "gun", { NotForNPCs = true }))
                    .to.beNil()
                expect(lib().DescribeWeapon("xm25", "smg", "gun", { ShootEnt = "grenade" })).to.beNil()
                local lmg = must(lib().DescribeWeapon("arc9_cod2019_lm_pkm", "ar", "gun", {}))
                expect(lmg.category).to.equal("lmg")
                expect(must(lib().DescribeWeapon("arc9_cod2019_me_knife", nil, "melee",
                    { HoldType = "knife", NotForNPCs = true })).knife).to.beTrue()
            end
        },
        {
            name = "Camouflage: actual ARC9 texture/category only; receivers, stickers and invalid data not generated",
            func = function()
                expect(lib().OptionRole({ Category = "universal_camo", CustomCamoTexture = "real/texture" }))
                    .to.equal("camo")
                expect(lib().OptionRole({ Category = "universal_camo" })).to.beNil()
                expect(lib().OptionRole({ Category = "stickers", Material = "not_a_camo" })).to.beNil()
                expect(lib().OptionRole({ Category = "receiver" })).to.beNil()
                expect(lib().OptionRole(nil)).to.beNil()
                expect(must(PW.Arc9)._IsCosmetic({ Category = "universal_camo" }, {})).to.beTrue()
            end
        },
        {
            name = "Async: incomplete and failed jobs never publish a partial pool, errors remain isolated",
            func = function()
                local input = api()
                local calls = 0
                input.slots = function()
                    calls = calls + 1
                    if calls > 3 then error("injected discovery failure") end
                    return {}
                end
                local state = lib().New("map_a", input)
                lib().Step(state, function() return 0 end, 0.001, 1)
                expect(state.status).to.equal("working")
                expect(#lib().Candidates(state, "map_a", true)).to.equal(0)
                for _ = 1, 100 do lib().Step(state, function() return 0 end, 0.001, 8) end
                expect(state.status).to.equal("failed")
                expect(#state.entries).to.equal(0)
                expect(#lib().Candidates(state, "map_a", true)).to.equal(0)
            end
        },
        {
            name = "Performance: work is capped by time and resume count, and yields before weapon/option calls",
            func = function()
                local state = lib().New("map_a", api())
                local clock = 0
                local function now() clock = clock + 0.0006 return clock end
                local resumes = lib().Step(state, now, 0.001, 32)
                expect(resumes <= 2).to.beTrue()
                expect(lib().Step(state, function() return 0 end, 0.001, 3)).to.equal(3)
                expect(state.status).to.equal("working")
            end
        },
        {
            name = "Cache: matches and settings reuse exact data; map change and reload invalidate safely",
            func = function()
                local state = complete()
                local first = lib().Candidates(state, "map_a", true)
                expect(first == lib().Candidates(state, "map_a", true)).to.beTrue()
                expect(#lib().Candidates(state, "map_a", false)).to.equal(0)
                expect(first == lib().Candidates(state, "map_a", true)).to.beTrue()
                expect(#lib().Candidates(state, "map_b", true)).to.equal(0)
                expect(lib().Keep(state, "map_a") == state).to.beTrue()
                expect(lib().Keep(state, "map_b")).to.beNil()
                state.version = -1
                expect(must(lib().Keep(state, "map_a")).status).to.equal("stale")
                local pending = lib().New("map_a", api())
                expect(must(lib().Keep(pending, "map_a")).status).to.equal("failed")
            end
        },
        {
            name = "Selection: generated pistol category participates in existing weights without replacing presets",
            func = function()
                local generated = complete().entries
                local input = { sources = { preset = true, players = true },
                    presets = { { id = "old", name = "Old", loadout = { primary = "w_ar" } } },
                    players = { { key = "human:1", name = "Human", loadout = { primary = "w_smg" } } },
                    check = function() return true end }
                local pool = must(PW.BotLoadouts).BuildPool(input)
                must(PW.BotLoadouts).AppendCandidates(pool, generated, input.check)
                expect(#pool).to.equal(20)
                expect(pool[1].ref).to.equal("preset:old")
                expect(pool[2].ref).to.equal("player:human:1")
                local entry = generated[#generated]
                expect(must(PW.BotLoadouts).Weight(entry, { pistol = 4 }, function() return nil end)).to.equal(4)
                expect(must(PW.BotLoadouts).Pick({ entry }, nil, 0, function() return nil end).ref).to.equal(entry.ref)
                local refused = {}
                must(PW.BotLoadouts).AppendCandidates(refused, generated, function() return false end)
                expect(#refused).to.equal(0)
            end
        },
        {
            name = "Setting: default-on match bool is exposed through schema without changing bots.classes sources",
            func = function()
                local module = must(PW.Modules.Get("bots_arc9_loadouts")) --[[@as PW.Module]]
                local setting = must(module.Settings).generate --[[@as PW.SettingDecl]]
                expect(setting.type).to.equal("bool")
                expect(setting.default).to.beTrue()
                expect(setting.scope).to.equal("match")
                expect(setting.label).to.equal("Generate ARC9 loadouts")
                expect(must(PW.BotLoadouts).Sources({})).to.deepEqual({ preset = false, players = false })
            end
        }
    }
}
