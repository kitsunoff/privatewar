-- New device AI consumes optional ordinary-flash eligibility without depending on its owner being mounted.
---@type any
local previous

return {
    groupName = "PW support optional device safety",
    beforeEach = function()
        previous = rawget(assert(PW.Throwables), "Impairment")
    end,
    afterEach = function()
        rawset(assert(PW.Throwables), "Impairment", previous)
    end,
    cases = {
        {
            name = "Device perception: optional ordinary flash blocks new sight and attack without changing difficulty",
            func = function()
                local lib = assert(PW.BotDevices)
                local bot = {} --[[@as Player]]
                rawset(assert(PW.Throwables), "Impairment", function() return 0.5 end)
                expect(lib.CanObserve(bot, 10)).to.beFalse()
                rawset(assert(PW.Throwables), "Impairment", function() return 0.05 end)
                expect(lib.CanObserve(bot, 10)).to.beTrue()
                rawset(assert(PW.Throwables), "Impairment", nil)
                expect(lib.CanObserve(bot, 10)).to.beTrue()
            end
        },
        {
            name = "Device input ownership: cleanup releases only claimed attack bits and is idempotent",
            func = function()
                local lib = assert(PW.BotDevices)
                local bot = {} --[[@as Player]]
                local intent = { buttons = bit.bor(IN_ATTACK, IN_RELOAD, IN_DUCK) }
                lib.OwnInput(bot, intent)
                lib.ReleaseInput(bot)
                expect(intent.buttons).to.equal(IN_DUCK)
                lib.ReleaseInput(bot)
                expect(intent.buttons).to.equal(IN_DUCK)
            end
        },
        {
            name = "Device behavior Rank: legally perceived device is chosen above objectives when no player is known",
            func = function()
                stub(assert(PW.BotDevices), "Contact").returns({})
                local context = { now = 10, contacts = {} }
                local behavior = assert(assert(PW.Registries.bot_behaviors).Get("attack_device"))
                expect(PW.Call(behavior, "Rank", {} --[[@as Player]], context --[[@as PW.BotBrainCtx]])).to.equal(25)
            end
        },
        {
            name = "Device behavior Rank: visible player combat always defeats device opportunism",
            func = function()
                stub(assert(PW.BotDevices), "Contact").returns({})
                local context = { now = 10, contacts = { { visible = true, time = 10 } } }
                local behavior = assert(assert(PW.Registries.bot_behaviors).Get("attack_device"))
                expect(PW.Call(behavior, "Rank", {} --[[@as Player]], context --[[@as PW.BotBrainCtx]])).to.beFalse()
            end
        },
        {
            name = "Bot streak eligibility: inventory polling performs no floor hull or exit traces",
            func = function()
                local lib = assert(PW.Devices)
                local owner = {} --[[@as Player]]
                local calls = 0
                stub(lib, "Prepare").with(function() calls = calls + 1 return nil end)
                stub(lib, "Enabled").returns(true)
                stub(lib, "List").returns({})
                for _, id in ipairs({ "ammo_cache", "medical_station", "ground_sensor" }) do
                    local def = assert(assert(PW.Registries.streaks).Get(id))
                    expect(PW.Call(def, "BotShouldUse", owner)).to.beTrue()
                end
                expect(calls).to.equal(0)
            end
        }
    }
}
