local defaults = {
    use_time = { "float", 0.4, 0, 2, "Stim injection time (s)" },
    heal_amount = { "int", 60, 10, 200, "Heal stim health" },
    heal_time = { "float", 1.5, 0, 5, "Heal stim duration (s)" },
    speed_mult = { "float", 1.2, 1, 2, "Speed stim multiplier" },
    speed_time = { "float", 6, 1, 30, "Speed stim duration (s)" },
    armor_amount = { "int", 50, 10, 150, "Armor stim armor" },
    armor_time = { "float", 1, 0, 5, "Armor stim duration (s)" },
    armor_max = { "int", 150, 50, 255, "Armor stim cap" }
}

---@return table<string, any>
local function lib()
    return assert(rawget(PW, "Stims"), "Stims module is not implemented")
end

return {
    groupName = "PW pure stim rules",
    cases = {
        {
            name = "Ticks: 60 over 1.5 s at 0.25 s gives six ticks of 10",
            func = function()
                expect(lib()._Ticks(60, 1.5, 0.25)).to.deepEqual({ 10, 10, 10, 10, 10, 10 })
            end
        },
        {
            name = "Ticks: remainder is spread so the sum equals the amount",
            func = function()
                local ticks = lib()._Ticks(50, 1, 0.25) --[[@as number[] ]]
                expect(#ticks).to.equal(4)
                local total = 0
                for _, value in ipairs(ticks) do
                    expect(value == 12 or value == 13).to.beTrue()
                    total = total + value
                end
                expect(total).to.equal(50)
                expect(#lib()._Ticks(50, 0.51, 0.25)).to.equal(3)
            end
        },
        {
            name = "Ticks: zero duration gives one immediate tick",
            func = function()
                expect(lib()._Ticks(60, 0, 0.25)).to.deepEqual({ 60 })
            end
        },
        {
            name = "Step: clamps to the cap",
            func = function()
                expect(lib()._Step(395, 10, 400)).to.equal(400)
                expect(lib()._Step(80, 10, 100)).to.equal(90)
            end
        },
        {
            name = "Step: never lowers a value above the cap",
            func = function()
                expect(lib()._Step(175, 10, 150)).to.equal(175)
            end
        },
        {
            name = "Param: item field wins, nil falls back to the setting, Base-inherited field is used",
            func = function()
                stub(PW, "Setting").with(function(id)
                    assert(id == "stims.heal_amount")
                    return 62
                end)
                local registry = PW.Registry.New("test_stim_rules", { log = function() end })
                registry.Register({ Amount = 30 }, "base")
                registry.Register({ Base = "base" }, "derived")
                registry.Register({ Base = "base", Amount = 0 }, "override")
                registry.ResolveAll()
                expect(lib().Param({}, "Amount", "stims.heal_amount")).to.equal(62)
                expect(lib().Param(registry.Get("derived"), "Amount", "stims.heal_amount")).to.equal(30)
                expect(lib().Param(registry.Get("override"), "Amount", "stims.heal_amount")).to.equal(0)
            end
        },
        {
            name = "EffectLines: speed seconds rounded up to one decimal, then healing, then armor",
            func = function()
                local marks = { speed = 5.01, heal = 2, armor = 2.5 }
                expect(lib()._EffectLines(0.9, marks)).to.deepEqual({ "SPEED 4.2", "HEALING", "ARMOR" })
                expect(lib()._EffectLines(2, marks)).to.deepEqual({ "SPEED 3.1", "ARMOR" })
                expect(lib()._EffectLines(5.01, marks)).to.deepEqual({})
            end
        },
        {
            name = "Settings: defaults and bounds match the record",
            func = function()
                local module = assert(PW.Modules.Get("stims"), "stims settings module is not registered")
                local schema = PW.Settings._Schema(module, "modules", function(message) error(message) end)
                local checked = 0
                for id, expected in pairs(defaults) do
                    local def = assert(schema[id], id)
                    expect(def.scope).to.equal("match")
                    expect({ def.type, def.default, def.min, def.max, def.label }).to.deepEqual(expected)
                    checked = checked + 1
                end
                expect(table.Count(schema)).to.equal(checked)
            end
        }
    }
}
