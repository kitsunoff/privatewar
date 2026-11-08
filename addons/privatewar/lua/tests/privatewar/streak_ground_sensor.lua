-- K4: geometry cannot by itself disclose a target; accepted candidates still pass through PW.Reveal.

---@return PW.SupportStreaksLib
local function rules()
    return assert(PW.SupportStreaks, "support streak rules are not loaded")
end

return {
    groupName = "PW support ground sensor",
    cases = {
        {
            name = "Sensor: walls floors and height obey approved current LOS filtering",
            func = function()
                local sensor = rules().SensorEligible
                expect(sensor(Vector(), Vector(600, 0, 0), true)).to.beTrue()
                expect(sensor(Vector(), Vector(600.01, 0, 0), true)).to.beFalse()
                expect(sensor(Vector(), Vector(100, 0, 128), true)).to.beTrue()
                expect(sensor(Vector(), Vector(100, 0, -128), true)).to.beTrue()
                expect(sensor(Vector(), Vector(100, 0, 128.01), true)).to.beFalse()
                expect(sensor(Vector(), Vector(100, 0, -128.01), true)).to.beFalse()
                expect(sensor(Vector(), Vector(100, 0, 64), false)).to.beFalse()
                expect(sensor(Vector(), Vector(100, 0, 0), false)).to.beFalse()
            end
        },
        {
            name = "Sensor: range is spatial rather than a horizontal cylinder",
            func = function()
                expect(rules().SensorEligible(Vector(), Vector(599, 0, 128), true)).to.beFalse()
                expect(rules().SensorEligible(Vector(10, 20, 30), Vector(110, 20, 158), true)).to.beTrue()
            end
        },
        {
            name = "Sensor: nonfinite origin and target never pass the coverage predicate",
            func = function()
                local sensor = rules().SensorEligible
                expect(sensor(Vector(), Vector(math.huge, 0, 0), true)).to.beFalse()
                expect(sensor(Vector(0 / 0, 0, 0), Vector(), true)).to.beFalse()
            end
        },
        {
            name = "Sensor: registered content has approved cost initial unlock and lifetime",
            func = function()
                local def = assert(assert(PW.Registries.streaks).Get("ground_sensor"), "ground_sensor is missing")
                expect({ def.Kills, def.Score, def.Unlock, def.Duration }).to.deepEqual({ 4, 400, 1, 30 })
                expect(isfunction(def.Prepare)).to.beTrue()
                expect(isfunction(def.OnUnequip)).to.beTrue()
            end
        }
    }
}
