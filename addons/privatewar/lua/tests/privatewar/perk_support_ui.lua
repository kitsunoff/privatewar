-- Selected-weapon compatibility is feedback, not a blanket promise about absent adapters.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "perk support UI consumer is missing")
    return value
end

---@param id string
---@return table<string, any>
local function definition(id)
    return must(must(PW.Registries.perks).Get(id)) --[[@as table<string, any>]]
end

---@param def table<string, any>
---@param classes string[]
---@return string
local function description(def, classes)
    local fn = rawget(must(PW.LoadoutUI), "PerkDescription")
    assert(isfunction(fn), "selected-base perk support description is missing")
    return fn(def, classes)
end

return {
    groupName = "PW perk support and class UI",
    cases = {
        {
            name = "Support: draw ADS recoil warn for selected HL2 fallback but not supported ARC9 keys",
            func = function()
                for _, id in ipairs({ "quick_draw", "sightline", "recoil_control" }) do
                    local def = definition(id)
                    local fallback = description(def, { "weapon_pistol" })
                    expect(fallback:find(def.Description, 1, true)).to.exist()
                    expect(fallback:lower():find("unsupported", 1, true)).to.exist()
                    expect(fallback:find("weapon_pistol", 1, true)).to.exist()
                end
                local original = PW.Adapters.CallFor
                rawset(PW.Adapters, "CallFor", function(class, method, ...)
                    if class == "pwt_arc9" and method == "SupportedStatMods" then
                        return { draw_time = true, ads_time = true, recoil = true }
                    end
                    return original(class, method, ...)
                end)
                local ok, err = pcall(function()
                    for _, id in ipairs({ "quick_draw", "sightline", "recoil_control" }) do
                        local def = definition(id)
                        expect(description(def, { "pwt_arc9" })).to.equal(def.Description)
                    end
                end)
                rawset(PW.Adapters, "CallFor", original)
                if not ok then error(err, 0) end
            end
        },
        {
            name = "Support: class option descriptions use selected weapon base and do not reject"
                .. " otherwise valid picks",
            func = function()
                local ui = must(PW.LoadoutUI)
                local def = definition("quick_draw")
                local slot = { id = "perk2", kind = "perks", group = 2 }
                ---@type PW.LoadoutUIEditorInput
                local input = {
                    declared = { perk2 = slot }, order = { "perk2" },
                    loadout = { primary = "weapon_pistol" },
                    ctx = { budget = 10, maxattachments = 5,
                        lookup = function(kind, id)
                            if kind == "perks" and id == "quick_draw" then return def end
                            return nil
                        end },
                    list = function(kind) return kind == "perks" and { def } or {} end
                }
                local model = ui.Editor(input)
                local choices = ui.Options(input, model.rows[1], model.slots)
                expect(#choices).to.equal(2)
                expect(choices[2].locked).to.beFalse()
                expect(must(choices[2].description):lower():find("unsupported", 1, true)).to.exist()
                expect(must(choices[2].description):find("weapon_pistol", 1, true)).to.exist()
            end
        },
        {
            name = "Support: absent TFA MW and unknown adapters never imply compatible stat handling",
            func = function()
                local def = definition("quick_draw")
                for _, class in ipairs({ "pwt_tfa_uninstalled", "pwt_mw_uninstalled", "pwt_unknown" }) do
                    expect(description(def, { class }):lower():find("unsupported", 1, true)).to.exist()
                end
            end
        },
        {
            name = "Descriptions: stock footsteps and ordinary movement limitations are accurate"
                .. " without universal compatibility",
            func = function()
                local quiet = (definition("quiet_steps").Description --[[@as string]]):lower()
                expect(quiet:find("stock", 1, true)).to.exist()
                expect(quiet:find("footstep", 1, true)).to.exist()
                expect(quiet:find("custom", 1, true)).to.exist()
                local movement = (definition("fleet_foot").Description --[[@as string]]):lower()
                expect(movement:find("walk", 1, true)).to.exist()
                expect(movement:find("run", 1, true)).to.exist()
                expect(movement:find("jump", 1, true)).to.exist()
                expect(description(definition("stockpile"), { "weapon_pistol" }))
                    .to.equal(definition("stockpile").Description)
            end
        },
        {
            name = "Recoil fairness: cached perk multiplier never boosts bot difficulty or adds a second compensation",
            func = function()
                local aim = must(PW.BotAim)
                local bot = {} --[[@as Player]]
                local paramsOf = must(aim._ParamsOf)
                local params = paramsOf(bot, nil)
                local before = table.Copy(params)
                local old = PW._Perks
                local fresh = must(must(PW.Perks)._NewStore)({ send = function() end })
                fresh.stats[bot] = { recoil = 0.8 }
                PW._Perks = fresh
                local ok, err = pcall(function()
                    expect(must(PW.Stat)(bot, "recoil", 1)).to.equal(0.8)
                    expect(paramsOf(bot, nil)).to.equal(params)
                    expect(params).to.deepEqual(before)
                    local recoil = PW.Adapters.Defaults.GetRecoil(nil, nil) --[[@as PW.Recoil]]
                    expect(recoil.affectsBotAim).to.beFalse()
                    expect(recoil.pitch).to.equal(0)
                end)
                PW._Perks = old
                if not ok then error(err, 0) end
            end
        }
    }
}
