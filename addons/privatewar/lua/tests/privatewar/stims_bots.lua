local resources = include("privatewar_fixtures/resource_lifecycle.lua") --[[@as PW.TestFixtureResources]]

---@param health number
---@param item string?
---@param count integer
---@return PW.BotCombatFacts
local function facts(health, item, count)
    local fields = {
        at = 0, pos = vector_origin, health = health, maxHealth = 100, clip = -1, capacity = 0, reserve = 0,
        reloading = false, lethal = 0, tacticalItem = item, tactical = count,
        profile = assert(PW.BotTactics).DefaultProfile
    }
    return fields --[[@as PW.BotCombatFacts]]
end

---@param f PW.BotCombatFacts
---@param visible boolean
---@return boolean
local function wanted(f, visible)
    local choose = assert(rawget(assert(PW.BotTactics), "_StimWanted"), "bot stim rank seam is not implemented")
    return choose(f, visible)
end

return {
    groupName = "PW bot heal stims",
    afterEach = function(state)
        timer.Remove("PW.BotStimSmoke")
        local bot = state.bot --[[@as Player?]]
        if state.modeSet then PW.ActiveMode = state.oldMode end
        if bot == nil or not IsValid(bot) then return end
        assert(PW.Equipment).Revoke(bot)
        bot:Kick("PW bot stim smoke complete")
    end,
    cases = {
        {
            name = "StimWanted: hurt bot with a heal stim and no visible enemy wants it",
            func = function()
                expect(wanted(facts(50, "stim_heal", 1), false)).to.beTrue()
                expect(wanted(facts(25, "stim_heal", 2), false)).to.beTrue()
            end
        },
        {
            name = "StimWanted: healthy, enemy visible, empty or speed stim does not",
            func = function()
                expect(wanted(facts(51, "stim_heal", 1), false)).to.beFalse()
                expect(wanted(facts(50, "stim_heal", 1), true)).to.beFalse()
                expect(wanted(facts(50, "stim_heal", 0), false)).to.beFalse()
                expect(wanted(facts(50, "stim_speed", 2), false)).to.beFalse()
                expect(wanted(facts(50, "stim_armor", 1), false)).to.beFalse()
                expect(wanted(facts(50, nil, 1), false)).to.beFalse()
            end
        },
        {
            name = "Bot heal stim smoke: a hurt shared bot uses the stim and its health rises",
            async = true,
            timeout = 12,
            func = function(state)
                local behavior = assert(PW.Registries).bot_behaviors.Get("use_stim")
                expect(behavior).to.exist()
                if behavior == nil then done() return end
                local match = assert(PW.Match)
                local equip = assert(PW.Equipment)
                local loadout = assert(PW.Loadout)
                local resolve = loadout.Resolve
                stub(match, "GetPhase").with(function() return "LIVE" end)
                state.oldMode, state.modeSet = PW.ActiveMode, true
                PW.ActiveMode = assert(PW.Modes.Get("ffa"))
                -- A preceding group may have queued a Kick while its bot still looks alive.
                local bot = player.CreateNextBot("PW heal stim smoke")
                assert(IsValid(bot), "heal stim smoke needs one player slot")
                state.bot = bot
                stub(loadout, "Resolve").with(function(ply)
                    if ply == bot then return { tactical = "stim_heal" }, "test" end
                    return resolve(ply)
                end)
                assert(PW.MatchRules).Spawn(bot)
                expect(bot:Alive()).to.beTrue()
                expect(equip.Item(bot, "tactical")).to.equal("stim_heal")
                expect(equip.Count(bot, "tactical")).to.equal(1)
                bot:SetHealth(math.floor(bot:GetMaxHealth() * 0.4))
                local health = bot:Health()
                local board = { bot = bot, intent = { buttons = 0 } } --[[@as PW.BotBoard]]
                assert(PW.BotTactics).Refresh(bot, board)
                local ctx = assert(PW.BotBrain).NewState().ctx
                ctx.bot, ctx.board, ctx.now = bot, board, CurTime()
                expect(PW.Call(behavior, "Rank", bot, ctx)).to.equal("survival")
                local result = PW.Call(behavior, "Update", bot, ctx) --[[@as PW.BotTransition]]
                expect(result.reason).to.equal("stim used")
                expect(equip.Count(bot, "tactical")).to.equal(0)
                local started = CurTime()
                timer.Create("PW.BotStimSmoke", 0.1, 65, function()
                    if IsValid(bot) and bot:Health() <= health and CurTime() - started < 6 then return end
                    expect(IsValid(bot) and bot:Health() > health).to.beTrue()
                    timer.Remove("PW.BotStimSmoke")
                    if IsValid(bot) then
                        equip.Revoke(bot)
                        bot:Kick("PW bot stim smoke complete")
                    end
                    state.bot = nil
                    resources.Disconnected({ bot }, done, timer.Simple)
                end)
            end
        }
    }
}
