-- T-4.6 killstreaks and the deliberate reveal (TASKS.md, "Mandatory test cases" T-4.6; 05-loadout.md d.9, d.10).
-- Pure cases for costs, sets, counting, inventory, wire, the reveal filter and the airstrike line; module cases over a
-- fresh streaks store with test streaks and fake phase, settings and players (earning by kills and by score, reset on
-- death, unused streaks kept, streaks.persist, no chaining, activation through the real net wrapper, an instance that
-- ends after Duration, the bot wiring with the shared bot); reveal cases over a fresh reveal store; wiring cases for
-- the kind, the slots and the defaults; the last case activates the real streaks in a LIVE test match.

local phaseConVars = { "pw_prematch_timeout", "pw_countdown", "pw_postmatch_time", "pw_aftermatch" }

---@class PW.StreaksTestState
---@field phase string
---@field alive boolean
---@field perk boolean
---@field botUse boolean
---@field wire integer
---@field settings table<string, any>
---@field equips string[]
---@field unequips string[]
---@field published table<string, any>
---@field previousStreaks PW.StreaksStore?
---@field previousReveal PW.RevealStore?
---@field previousNet PW.NetStore?
---@field bot Player?
---@field created Player?
---@field activated boolean
local test = { phase = "LIVE", alive = true, perk = false, botUse = true, wire = 1, settings = {}, equips = {},
    unequips = {}, published = {}, activated = false }

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.StreaksLib
local function lib()
    return must(PW.Streaks)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@return Player
local function sharedBot()
    local bot = test.bot
    if bot ~= nil and IsValid(bot) then return bot end
    bot = player.GetBots()[1]
    if bot == nil then
        bot = player.CreateNextBot("PW streaks test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        test.created = bot
    end
    test.bot = bot
    return bot
end

---@param name? string
---@param team? integer
---@return Player
local function fakePlayer(name, team)
    local pos = Vector(#(name or "") * 10, 0, 0)
    return { IsValid = function() return true end, Nick = function() return name or "fake" end, team = team,
        EntIndex = function() return #(name or "") end, GetPos = function() return pos end } --[[@as Player]]
end

---@param id string
---@param kills integer
---@param score? number
---@return PW.Streak
local function testStreak(id, kills, score)
    return {
        ClassName = id, Name = string.upper(id), Kills = kills, Score = score, Duration = 0.2,
        OnEquip = function() test.equips[#test.equips + 1] = id end,
        OnUnequip = function() test.unequips[#test.unequips + 1] = id end,
        BotShouldUse = function() return test.botUse end
    } --[[@as PW.Streak]]
end

local defs = { pwt_uav = testStreak("pwt_uav", 3), pwt_cuav = testStreak("pwt_cuav", 4, 450),
    pwt_strike = testStreak("pwt_strike", 5) }

local function installStore()
    test.equips, test.unequips, test.published = {}, {}, {}
    PW._Streaks = must(lib()._NewStore)({
        lookup = function(id) return defs[id] end,
        resolve = function() return { streak1 = "pwt_strike", streak2 = "pwt_uav", streak3 = "pwt_cuav" } end,
        publish = function(_, key, value) test.published[key] = value end,
        phase = function() return test.phase end,
        alive = function() return test.alive end,
        setting = function(key) return test.settings[key] end,
        persist = function() return test.perk end,
        read = function() return test.wire end
    })
end

---@param ply Player
---@param n integer
---@param event? string
---@param points? number
local function score(ply, n, event, points)
    for _ = 1, n do must(lib()._OnScore)(ply, event or "kill", points or 100) end
end

local pureCases = {
    {
        name = "Cost: kills mode uses Kills; score mode uses Score, else Kills x 100",
        func = function()
            expect(lib()._Cost({ Kills = 3 }, "kills")).to.equal(3)
            expect(lib()._Cost({ Kills = 3 }, "score")).to.equal(300)
            expect(lib()._Cost({ Kills = 4, Score = 450 }, "score")).to.equal(450)
            expect(lib()._Cost({ Kills = 0 }, "kills")).to.equal(1)
        end
    },
    {
        name = "Set: streak slots in cost order, duplicates and unknown ids skipped; round-trips the wire",
        func = function()
            local lookup = function(id) return defs[id] end
            local set = lib()._Set({ streak1 = "pwt_strike", streak2 = "pwt_uav", streak3 = "pwt_uav",
                primary = "pwt_cuav" }, lookup, "kills")
            expect(set).to.deepEqual({ { id = "pwt_uav", cost = 3 }, { id = "pwt_strike", cost = 5 } })
            expect(lib()._DecodeSet(lib()._EncodeSet(set))).to.deepEqual(set)
            expect(lib()._Set({ streak1 = "nope" }, lookup, "kills")).to.deepEqual({})
        end
    },
    {
        name = "Counting: kills mode counts kill events, score mode points; crossing, goal and death rules",
        func = function()
            expect(lib()._Gain("kills", "kill", 100)).to.equal(1)
            expect(lib()._Gain("kills", "headshot", 50)).to.equal(0)
            expect(lib()._Gain("score", "dom_capture", 200)).to.equal(200)
            expect(lib()._Counts(false, true)).to.beFalse()
            expect(lib()._Counts(true, true)).to.beTrue()
            expect(lib()._Counts(false, false)).to.beTrue()
            local set = { { id = "a", cost = 3 }, { id = "b", cost = 5 } }
            expect(lib()._Crossed(set, 2, 3)).to.deepEqual({ "a" })
            expect(lib()._Crossed(set, 0, 9)).to.deepEqual({ "a", "b" })
            expect(lib()._Crossed(set, 5, 6)).to.deepEqual({})
            expect(must(lib()._NextGoal(set, 3)).id).to.equal("b")
            expect(lib()._NextGoal(set, 5)).to.beNil()
            expect(lib()._AfterDeath(4, false)).to.equal(0)
            expect(lib()._AfterDeath(4, true)).to.equal(4)
        end
    },
    {
        name = "Inventory: push caps the size, find, selection wraps, the wire round-trips; keys",
        func = function()
            local inv = lib()._Push({ "a", "b" }, "c", 2)
            expect(inv).to.deepEqual({ "b", "c" })
            expect(lib()._Find(inv, "c")).to.equal(2)
            expect(lib()._Find(inv, "x")).to.beNil()
            expect(lib()._Select(2, 2, 1)).to.equal(1)
            expect(lib()._Select(5, 3, 0)).to.equal(2)
            expect(lib()._Select(1, 0, 1)).to.equal(1)
            expect(lib()._DecodeInventory(lib()._EncodeInventory(inv))).to.deepEqual(inv)
            expect(lib()._DecodeInventory("")).to.deepEqual({})
            local codes = { use = KEY_5, next = KEY_6 }
            expect(lib()._KeyAction(KEY_5, codes)).to.equal("use")
            expect(lib()._KeyAction(KEY_6, codes)).to.equal("next")
            expect(lib()._KeyAction(KEY_G, codes)).to.beNil()
            expect(lib().Keys.use.default).to.equal("5")
        end
    },
    {
        name = "Reveal filter: a live Counter-UAV hides its side from hostile viewers only, until it expires",
        func = function()
            local isEnemy = function(a, b) return a.team ~= b.team end
            local a1, a2, b1 = fakePlayer("a1", 1), fakePlayer("a2", 1), fakePlayer("b1", 2)
            local jams = { { owner = a1, ends = 10 } }
            expect(lib()._Visible(a2, b1, jams, 5, isEnemy)).to.beFalse()
            expect(lib()._Visible(a2, a1, jams, 5, isEnemy)).to.beTrue()
            expect(lib()._Visible(b1, a1, jams, 5, isEnemy)).to.beTrue()
            expect(lib()._Visible(a2, b1, jams, 11, isEnemy)).to.beTrue()
            expect(lib()._Filter({ a1, b1 }, b1, jams, 5, isEnemy)).to.deepEqual({ b1 })
            expect(#lib()._Prune(jams, 11)).to.equal(0)
        end
    },
    {
        name = "Wire numbers and the airstrike line: quantized positions and times round-trip; bombs centred",
        func = function()
            expect(lib()._Dequantize(lib()._Quantize(1234.4))).to.aboutEqual(1234.4, lib().PosScale)
            expect(lib()._Dequantize(lib()._Quantize(-99999))).to.aboutEqual(-(2 ^ (lib().PosBits - 1) - 1)
                * lib().PosScale, 0.01)
            expect(lib()._DecodeTime(lib()._EncodeTime(3.5))).to.equal(3.5)
            expect(lib()._EncodeTime(-1)).to.equal(0)
            local points = lib()._AirstrikePoints(Vector(0, 0, 0), Vector(2, 0, 0), 3, 100)
            expect(points).to.deepEqual({ Vector(-100, 0, 0), Vector(0, 0, 0), Vector(100, 0, 0) })
            local blips = { { index = 1, pos = Vector(), ends = 5 }, { index = 2, pos = Vector(), ends = 1 } }
            local live = lib()._Live(blips, 2, {})
            expect(#live).to.equal(1)
            expect(live[1].index).to.equal(1)
        end
    }
}

local moduleCases = {
    {
        name = "Mandatory: earning by kills: each streak of the set is earned when the kill count reaches its cost",
        func = function()
            test.settings.earn = "kills"
            local ply = fakePlayer("p")
            expect(must(lib()._OnSpawn)(ply)).to.beTrue()
            score(ply, 2)
            score(ply, 3, "headshot", 50)
            expect(lib().Progress(ply)).to.equal(2)
            expect(must(lib()._OnScore)(ply, "kill", 100)).to.deepEqual({ "pwt_uav" })
            score(ply, 2)
            expect(lib().Inventory(ply)).to.deepEqual({ "pwt_uav", "pwt_cuav", "pwt_strike" })
            expect(test.published[lib().InventoryKey]).to.equal("pwt_uav,pwt_cuav,pwt_strike")
            expect(test.published[lib().ProgressKey]).to.equal(5)
            score(ply, 3)
            expect(#lib().Inventory(ply)).to.equal(3)
        end
    },
    {
        name = "Mandatory: earning by score: points of every score event count toward Score costs",
        func = function()
            test.settings.earn = "score"
            local ply = fakePlayer("p")
            must(lib()._OnSpawn)(ply)
            expect(lib().Set(ply)).to.deepEqual({ { id = "pwt_uav", cost = 300 }, { id = "pwt_cuav", cost = 450 },
                { id = "pwt_strike", cost = 500 } })
            score(ply, 1, "kill", 100)
            score(ply, 1, "dom_capture", 200)
            expect(lib().Inventory(ply)).to.deepEqual({ "pwt_uav" })
            score(ply, 1, "headshot", 150)
            expect(lib().Inventory(ply)).to.deepEqual({ "pwt_uav", "pwt_cuav" })
            score(ply, 1, "kc_deny", 50)
            expect(lib().Inventory(ply)).to.deepEqual({ "pwt_uav", "pwt_cuav", "pwt_strike" })
        end
    },
    {
        name = "Mandatory: reset on death: the counter returns to zero and the streaks are earned again",
        func = function()
            local ply = fakePlayer("p")
            must(lib()._OnSpawn)(ply)
            score(ply, 2)
            must(lib()._OnDeath)(ply)
            expect(lib().Progress(ply)).to.equal(0)
            expect(test.published[lib().ProgressKey]).to.equal(0)
            score(ply, 2)
            expect(lib().Inventory(ply)).to.deepEqual({})
            score(ply, 1)
            expect(lib().Inventory(ply)).to.deepEqual({ "pwt_uav" })
        end
    },
    {
        name = "Mandatory: unused streaks are kept across death and respawn and can still be activated",
        func = function()
            local ply = fakePlayer("p")
            must(lib()._OnSpawn)(ply)
            score(ply, 4)
            must(lib()._OnDeath)(ply)
            must(lib()._OnSpawn)(ply)
            expect(lib().Inventory(ply)).to.deepEqual({ "pwt_uav", "pwt_cuav" })
            expect(must(lib().Use)(ply, "pwt_cuav")).to.beTrue()
            expect(lib().Inventory(ply)).to.deepEqual({ "pwt_uav" })
        end
    },
    {
        name = "Mandatory: streaks.persist keeps the counter after death (also for a perk via PW_StreaksPersist)",
        func = function()
            local ply = fakePlayer("p")
            must(lib()._OnSpawn)(ply)
            test.settings.persist = true
            score(ply, 2)
            must(lib()._OnDeath)(ply)
            expect(lib().Progress(ply)).to.equal(2)
            score(ply, 1)
            expect(lib().Inventory(ply)).to.deepEqual({ "pwt_uav" })
            test.settings.persist = false
            test.perk = true
            must(lib()._OnDeath)(ply)
            expect(lib().Progress(ply)).to.equal(3)
            test.perk = false
            must(lib()._OnDeath)(ply)
            expect(lib().Progress(ply)).to.equal(0)
        end
    },
    {
        name = "Mandatory: streak kills do not chain unless streaks.chain is on",
        func = function()
            local ply = fakePlayer("p")
            must(lib()._OnSpawn)(ply)
            score(ply, 2)
            must(lib().StreakDamage)(score, ply, 3)
            expect(lib().Progress(ply)).to.equal(2)
            expect(lib().Inventory(ply)).to.deepEqual({})
            expect(must(PW._Streaks).depth).to.equal(0)
            test.settings.chain = true
            must(lib().StreakDamage)(score, ply, 1)
            expect(lib().Progress(ply)).to.equal(3)
            expect(lib().Inventory(ply)).to.deepEqual({ "pwt_uav" })
            must(lib().StreakDamage)(error, "boom")
            expect(must(PW._Streaks).depth).to.equal(0)
        end
    },
    {
        name = "Mandatory: activation creates an instance (OnEquip) that ends after Duration (OnUnequip)",
        async = true,
        timeout = 3,
        func = function()
            local ply = fakePlayer("p")
            must(lib()._OnSpawn)(ply)
            expect(must(lib().Give)(ply, "pwt_uav")).to.beTrue()
            expect(must(lib().Use)(ply, "pwt_uav")).to.beTrue()
            expect(test.equips).to.deepEqual({ "pwt_uav" })
            ---@type PW.StreakInstance?
            local found = nil
            for inst in pairs(must(lib()._Instances)) do
                if inst.ClassName == "pwt_uav" and inst._Owner == ply then found = inst end
            end
            local inst = must(found)
            expect(inst:IsValid()).to.beTrue()
            timer.Simple(0.05, function()
                expect(inst:IsValid()).to.beTrue()
                timer.Simple(0.5, function()
                    expect(inst:IsValid()).to.beFalse()
                    expect(test.unequips).to.deepEqual({ "pwt_uav" })
                    expect(must(lib()._Instances)[inst]).to.beNil()
                    done()
                end)
            end)
        end
    },
    {
        name = "Use: refused outside LIVE, for a dead player, for a streak not held; the key goes through the net",
        func = function()
            local ply = fakePlayer("p")
            must(lib()._OnSpawn)(ply)
            must(lib().Give)(ply, "pwt_uav")
            must(lib().Give)(ply, "pwt_strike")
            expect(must(lib().Give)(ply, "nope")).to.beFalse()
            local use = must(lib().Use)
            expect(use(ply, "pwt_cuav")).to.beFalse()
            test.alive = false
            expect(use(ply, "pwt_uav")).to.beFalse()
            test.alive = true
            test.phase = "PREMATCH"
            expect(use(ply, "pwt_uav")).to.beFalse()
            expect({ must(PW.Net)._Dispatch(lib().NetName, 4, ply) }).to.deepEqual({ false, "phase" })
            test.phase = "LIVE"
            test.wire = 2
            expect(must(PW.Net)._Dispatch(lib().NetName, 4, ply)).to.beTrue()
            expect(test.equips).to.deepEqual({ "pwt_strike" })
            test.wire = 7
            expect(must(PW.Net)._Dispatch(lib().NetName, 4, ply)).to.beTrue()
            expect(lib().Inventory(ply)).to.deepEqual({ "pwt_uav" })
        end
    },
    {
        name = "Bots: ReadyStreak returns a held streak BotShouldUse agrees to; UseStreak activates it",
        func = function()
            local bot = sharedBot()
            local objectives = must(PW.BotObjectives)
            expect(objectives.ReadyStreak(bot)).to.beNil()
            must(lib().Give)(bot, "pwt_uav")
            expect(must(objectives.ReadyStreak(bot)).id).to.equal("pwt_uav")
            test.botUse = false
            expect(objectives.ReadyStreak(bot)).to.beNil()
            test.botUse = true
            ---@type table
            local raw = { _api = {}, bot = bot }
            expect(objectives.UseStreak(raw --[[@as PW.BotBrainCtx]], "pwt_uav")).to.beTrue()
            expect(test.equips).to.deepEqual({ "pwt_uav" })
            expect(objectives.UseStreak(raw --[[@as PW.BotBrainCtx]], "pwt_uav")).to.beFalse()
        end
    }
}

---@class PW.StreaksTestReveal
---@field sent { recipients: any[], blips: PW.RevealBlip[], duration: number }[]
---@field jammed { recipients: any[], duration: number }[]
---@field stimuli { viewer: any, target: any }[]
---@field now number

---@param players Player[]
---@return PW.StreaksTestReveal
local function installReveal(players)
    ---@type PW.StreaksTestReveal
    local rec = { sent = {}, jammed = {}, stimuli = {}, now = 100 }
    PW._Reveal = must(lib()._NewRevealStore)({
        clock = function() return rec.now end,
        isEnemy = function(a, b) return a ~= b and (a.team == nil or a.team ~= b.team) end,
        members = function(viewer)
            if not isnumber(viewer) then return { viewer } end
            ---@type any[]
            local list = {}
            for _, p in ipairs(players) do if (p --[[@as table]]).team == viewer then list[#list + 1] = p end end
            return list
        end,
        players = function() return players end,
        send = function(recipients, blips, duration)
            rec.sent[#rec.sent + 1] = { recipients = recipients, blips = blips, duration = duration }
        end,
        jamSend = function(recipients, duration)
            rec.jammed[#rec.jammed + 1] = { recipients = recipients, duration = duration }
        end,
        stimulus = function(viewer, target) rec.stimuli[#rec.stimuli + 1] = { viewer = viewer, target = target } end
    })
    return rec
end

local revealCases = {
    {
        name = "PW.Reveal: sends only the given targets to the viewer's players and feeds its bots",
        func = function()
            local a1, a2, b1, b2 = fakePlayer("a1", 1), fakePlayer("a2", 1), fakePlayer("b1", 2), fakePlayer("b22", 2)
            local rec = installReveal({ a1, a2, b1, b2 })
            expect(must(PW.Reveal)(1, { b1, b2 }, 3)).to.equal(2)
            expect(#rec.sent).to.equal(1)
            expect(rec.sent[1].recipients).to.deepEqual({ a1, a2 })
            expect(rec.sent[1].duration).to.equal(3)
            expect(rec.sent[1].blips[1].index).to.equal(b1:EntIndex())
            expect(rec.sent[1].blips[2].pos).to.equal(b2:GetPos())
            expect(#rec.stimuli).to.equal(2)
            expect(rec.stimuli[1].viewer).to.equal(1)
            expect(must(PW.Reveal)(b1, { a1 }, 3)).to.equal(1)
            expect(rec.sent[2].recipients).to.deepEqual({ b1 })
        end
    },
    {
        name = "Counter-UAV: Jam notifies the hostile players and hides its side from their reveals until it ends",
        func = function()
            local a1, a2, b1 = fakePlayer("a1", 1), fakePlayer("a2", 1), fakePlayer("b1", 2)
            local rec = installReveal({ a1, a2, b1 })
            must(lib().Jam)(a1, 5)
            expect(rec.jammed[1].recipients).to.deepEqual({ b1 })
            expect(rec.jammed[1].duration).to.equal(5)
            expect(must(PW.Reveal)(2, { a1, a2 }, 3)).to.equal(0)
            expect(#rec.sent).to.equal(0)
            expect(must(PW.Reveal)(1, { b1 }, 3)).to.equal(1)
            rec.now = rec.now + 6
            expect(must(PW.Reveal)(2, { a1, a2 }, 3)).to.equal(2)
        end
    }
}

local wiringCases = {
    {
        name = "Wiring: the kind and the MVP streaks, the three slots, the default loadout and the presets",
        func = function()
            local registry = must(PW.Registries.streaks)
            local uav, cuav = must(registry.Get("uav")), must(registry.Get("counter_uav"))
            local strike = must(registry.Get("airstrike"))
            expect({ uav.Kills, cuav.Kills, strike.Kills }).to.deepEqual({ 3, 4, 5 })
            local loadout = must(PW.Loadout)
            for _, slot in ipairs(lib().Slots) do expect(must(loadout.GetSlot(slot)).kind).to.equal("streaks") end
            local default = loadout.Default()
            expect({ default.streak1, default.streak2, default.streak3 }).to.deepEqual({ "uav", "counter_uav",
                "airstrike" })
            expect(loadout.Validate(fakePlayer(), default)).to.beTrue()
            expect(loadout.Validate(fakePlayer(), { streak1 = "frag" })).to.beFalse()
            for _, preset in ipairs(must(PW.Registries.classes).GetList()) do
                expect(preset.Loadout.streak1).to.equal("uav")
            end
        end
    },
    {
        name = "Wiring: the use message is registered in the real net store, LIVE only, owned by streaks",
        func = function()
            local def = must(must(test.previousNet).defs[lib().NetName])
            expect(def.owner).to.equal(must(PW.Modules.GetStored("streaks")))
            expect(table.GetKeys(def.phases)).to.deepEqual({ "LIVE" })
            expect(util.NetworkStringToID(lib().RevealNet)).toNot.equal(0)
        end
    }
}

---@param bot Player
---@param fail fun(message: string)
local function activateAll(bot, fail)
    if not IsValid(bot) then return fail("the shared bot is gone") end
    if not bot:Alive() then bot:Spawn() end
    for _, id in ipairs({ "uav", "counter_uav", "airstrike" }) do
        if not must(lib().Give)(bot, id) then return fail("Give refused " .. id) end
        if not must(lib().Use)(bot, id) then return fail("Use refused " .. id) end
    end
    local live = 0
    for inst in pairs(must(lib()._Instances)) do
        if inst:IsValid() and inst._Owner == bot then live = live + 1 end
    end
    if live ~= 3 then return fail("expected 3 live activations, got " .. live) end
    if #must(PW._Reveal).jams < 1 then return fail("the Counter-UAV did not jam") end
    test.activated = true
end

local gameCases = {
    {
        name = "In-game: in a LIVE test match the shared bot activates UAV, Counter-UAV and airstrike",
        async = true,
        timeout = 20,
        func = function()
            PW._Streaks, PW._Reveal, PW._Net = test.previousStreaks, test.previousReveal, test.previousNet
            ---@type table<string, string>
            local saved = {}
            for _, name in ipairs(phaseConVars) do saved[name] = must(GetConVar(name)):GetString() end
            local function restore()
                for name, value in pairs(saved) do must(GetConVar(name)):SetString(value) end
            end
            must(GetConVar("pw_prematch_timeout")):SetString("0")
            must(GetConVar("pw_countdown")):SetString("0")
            must(GetConVar("pw_postmatch_time")):SetString("0.5")
            must(GetConVar("pw_aftermatch")):SetString("lobby")
            expect(match().GetPhase()).to.equal("LOBBY")
            expect(match().Start(must(PW.Modes.Get("tdm")))).to.beTrue()
            local function fail(message)
                restore()
                if match().GetPhase() ~= "LOBBY" then match().Abort("streaks smoke: " .. message) end
                error(message, 0)
            end
            local function waitFor(phase, deadline, after)
                if match().GetPhase() == phase then return after() end
                if CurTime() > deadline then fail("phase " .. phase .. " not reached, still " .. match().GetPhase()) end
                timer.Simple(0.1, function() waitFor(phase, deadline, after) end)
            end
            waitFor("LIVE", CurTime() + 5, function()
                local bot = sharedBot()
                timer.Simple(0.5, function()
                    activateAll(bot, fail)
                    match().Abort("streaks smoke done")
                    waitFor("LOBBY", CurTime() + 5, function()
                        restore()
                        expect(test.activated).to.beTrue()
                        expect(next(must(lib()._Instances))).to.beNil()
                        expect(#lib().Inventory(bot)).to.equal(0)
                        done()
                    end)
                end)
            end)
        end
    }
}

---@param ... table[]
---@return table[]
local function join(...)
    ---@type table[]
    local all = {}
    for _, list in ipairs({ ... }) do
        for _, case in ipairs(list) do all[#all + 1] = case end
    end
    return all
end

return {
    groupName = "PW streaks",
    beforeEach = function()
        test.previousStreaks, test.previousReveal, test.previousNet = PW._Streaks, PW._Reveal, PW._Net
        test.phase, test.alive, test.perk, test.botUse, test.wire, test.activated = "LIVE", true, false, true, 1, false
        test.settings = { earn = "kills", persist = false, chain = false }
        installStore()
        PW._Net = must(PW.Net)._NewStore({ log = function() end, clock = CurTime,
            phase = function() return test.phase end })
        must(lib()._RegisterNet)({ IsValid = function() return true end })
    end,
    afterEach = function()
        for inst in pairs(must(lib()._Instances)) do
            if defs[inst.ClassName] ~= nil then inst:Remove() end
        end
        PW._Streaks, PW._Reveal, PW._Net = test.previousStreaks, test.previousReveal, test.previousNet
    end,
    afterAll = function()
        local created = test.created
        if created ~= nil and IsValid(created) then created:Kick("streaks tests done") end
    end,
    cases = join(pureCases, moduleCases, revealCases, wiringCases, gameCases)
}
