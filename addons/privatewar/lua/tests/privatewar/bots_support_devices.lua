-- These pure gates are prerequisites, not a substitute for native weapon-fire device counterplay smoke.

---@return PW.BotDevicesLib
local function devices()
    return assert(PW.BotDevices, "bot device perception is not loaded")
end

return {
    groupName = "PW bot support device perception",
    cases = {
        {
            name = "Sensor: hidden device creates no bot contact before perception",
            func = function()
                local visible = devices().Perceivable
                expect(visible(Vector(), Vector(1, 0, 0), Vector(100, 0, 0), 1200, 110, false)).to.beFalse()
                expect(visible(Vector(), Vector(1, 0, 0), Vector(-100, 0, 0), 1200, 110, true)).to.beFalse()
                expect(visible(Vector(), Vector(1, 0, 0), Vector(1201, 0, 0), 1200, 110, true)).to.beFalse()
                expect(visible(Vector(), Vector(1, 0, 0), Vector(100, 0, 0), 1200, 110, true)).to.beTrue()
            end
        },
        {
            name = "Device perception: FOV total angle range and LOS are independently required",
            func = function()
                local visible = devices().Perceivable
                expect(visible(Vector(), Vector(1, 0, 0), Vector(100, 100, 0), 1200, 90, true)).to.beTrue()
                expect(visible(Vector(), Vector(1, 0, 0), Vector(100, 101, 0), 1200, 90, true)).to.beFalse()
                expect(visible(Vector(), Vector(), Vector(100, 0, 0), 1200, 90, true)).to.beFalse()
                expect(visible(Vector(), Vector(1, 0, 0), Vector(math.huge, 0, 0), 1200, 90, true)).to.beFalse()
            end
        },
        {
            name = "Device perception: normal reaction delay precedes recognition and lost sight revokes it",
            func = function()
                local recognized = devices().Recognized
                expect(recognized(nil, 10, 0.45, true)).to.beFalse()
                expect(recognized(10, 10.449, 0.45, true)).to.beFalse()
                expect(recognized(10, 10.45, 0.45, true)).to.beTrue()
                expect(recognized(10, 11, 0.45, false)).to.beFalse()
                expect(recognized(12, 11, 0.45, true)).to.beFalse()
                expect(recognized(10, math.huge, 0.45, true)).to.beFalse()
            end
        },
        {
            name = "Device behavior: player fights retain priority over visible enemy devices",
            func = function()
                local wanted = devices().AttackWanted
                expect(wanted(true, true)).to.beFalse()
                expect(wanted(true, false)).to.beFalse()
                expect(wanted(false, false)).to.beFalse()
                expect(wanted(false, true)).to.beTrue()
            end
        },
        {
            name = "Device behavior: dedicated optional behavior registers without replacing player fight",
            func = function()
                local registry = assert(PW.Registries.bot_behaviors)
                local attack = assert(registry.Get("attack_device"), "attack_device is missing")
                local fight = assert(registry.Get("fight"))
                expect(attack == fight).to.beFalse()
                expect(isfunction(attack.Rank)).to.beTrue()
                expect(isfunction(attack.Update)).to.beTrue()
                expect(isfunction(attack.OnEnd)).to.beTrue()
                expect(isfunction(attack.OnSuspend)).to.beTrue()
            end
        }
    }
}
