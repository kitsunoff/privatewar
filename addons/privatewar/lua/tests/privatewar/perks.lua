-- T-4.4 perks (TASKS.md, "Mandatory test cases" T-4.4; 05-loadout.md d.4, d.8; 00-core.md d.11). Pure cases for the
-- group rule, the multiplier chain and the owner filter; module cases over a fresh perks store with test perks, a
-- recorded PW.SetStatMods and fake players (refresh only on spawn and loadout change, owner-only events, cleanup
-- on death); wiring cases for the kind, the slots, the sample perks and the hooks; the last case is the in-game
-- check: in a LIVE test match the shared bot spawns with the default perks and loses them on death.

local phaseConVars = { "pw_prematch_timeout", "pw_countdown", "pw_postmatch_time", "pw_aftermatch" }

---A recorded perk event.
---@class PW.PerksTestCall
---@field perk string
---@field method string
---@field self table
---@field owner any
---@field other any

---A recorded PW.SetStatMods call.
---@class PW.PerksTestSent
---@field ply any
---@field mods table<string, number>

---State of this group; reset in beforeEach.
---@class PW.PerksTestState
---@field calls PW.PerksTestCall[]
---@field sent PW.PerksTestSent[]
---@field sourceCalls integer
---@field wildcard table<string, number>?
---@field previousPerks PW.PerksStore?
---@field previousMode table?
---@field bot Player?
---@field created Player?
local test = { calls = {}, sent = {}, sourceCalls = 0 }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.PerksLib
local function lib()
    return must(PW.Perks)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---A player stand-in: a unique table is enough for the store.
---@return Player
local function fakePlayer()
    return { IsValid = function() return true end, Nick = function() return "fake" end } --[[@as Player]]
end

---@param method string
---@param id string
---@return fun(self: table, owner: any, other: any)
local function recorder(method, id)
    return function(self, owner, other)
        test.calls[#test.calls + 1] = { perk = id, method = method, self = self, owner = owner, other = other }
    end
end

---A test perk that records every event method.
---@param id string
---@param group integer
---@param stats table<string, number>?
---@return PW.Perk
local function testPerk(id, group, stats)
    ---@type table<string, any>
    local perk = { ClassName = id, Name = string.upper(id), Group = group, Stats = stats }
    for _, method in ipairs({ "OnEquip", "OnUnequip", "OnKill", "OnDeath", "OnDamaged", "OnDealDamage" }) do
        perk[method] = recorder(method, id)
    end
    return perk --[[@as PW.Perk]]
end

local perks = {
    pwt_fast = testPerk("pwt_fast", 1, { reload_time = 0.5, move_speed = 1.25 }),
    pwt_steady = testPerk("pwt_steady", 2, { recoil = 0.5 }),
    pwt_other1 = testPerk("pwt_other1", 1, nil)
}

---Installs a fresh perks store over the test perks with recorded stat mods.
local function installStore()
    test.calls, test.sent = {}, {}
    PW._Perks = must(lib()._NewStore)({
        lookup = function(id) return perks[id] end,
        send = function(ply, mods) test.sent[#test.sent + 1] = { ply = ply, mods = mods } end,
        isPlayer = function(ent) return istable(ent) and ent.Nick ~= nil end
    })
end

---@param method string
---@return PW.PerksTestCall[]
local function callsOf(method)
    ---@type PW.PerksTestCall[]
    local found = {}
    for _, call in ipairs(test.calls) do
        if call.method == method then found[#found + 1] = call end
    end
    return found
end

local slots = {
    perk1 = { id = "perk1", kind = "perks", group = 1 },
    perk2 = { id = "perk2", kind = "perks", group = 2 },
    free = { id = "free", kind = "perks" },
    primary = { id = "primary", kind = "weapons" }
}

local pureCases = {
    {
        name = "Group rule: a perk slot accepts only perks of its own group; a slot without a group accepts any",
        func = function()
            expect(lib()._GroupError(slots.perk1, perks.pwt_fast)).to.beNil()
            expect(lib()._GroupError(slots.perk1, perks.pwt_steady)).to.exist()
            expect(lib()._GroupError(slots.perk2, perks.pwt_steady)).to.beNil()
            expect(lib()._GroupError(slots.free, perks.pwt_steady)).to.beNil()
        end
    },
    {
        name = "Group rule: one perk per group; a wildcard slot with count 2 holds two perks of its group",
        func = function()
            local lookup = function(id) return perks[id] end
            expect({ lib()._CheckGroups(slots, { perk1 = "pwt_fast", perk2 = "pwt_steady", primary = "x" }, lookup) })
                .to.deepEqual({ true })
            local ok, reason = lib()._CheckGroups(slots, { perk1 = "pwt_steady" }, lookup)
            expect(ok).to.beFalse()
            expect(must(reason):find("pwt_steady", 1, true)).to.exist()
            expect(lib()._CheckGroups(slots, { perk2 = { "pwt_steady", "pwt_fast" } }, lookup)).to.beFalse()
            local greed = table.Copy(slots)
            greed.perk1.count = 2
            expect(lib()._CheckGroups(greed, { perk1 = { "pwt_fast", "pwt_other1" } }, lookup)).to.beTrue()
        end
    },
    {
        name = "Group rule: PW.Loadout.Validate rejects a sample perk in another group's slot",
        func = function()
            local loadout = must(PW.Loadout)
            local registry = must(PW.Registries.perks)
            local reload = must(registry.Get("sleight_of_hand"))
            local wrong = reload.Group == 1 and "perk2" or "perk1"
            local ok, reason = loadout.Validate(fakePlayer(), { [wrong] = "sleight_of_hand" })
            expect(ok).to.beFalse()
            expect(must(reason):find("group", 1, true)).to.exist()
            expect(loadout.Validate(fakePlayer(), { ["perk" .. reload.Group] = "sleight_of_hand" })).to.beTrue()
        end
    },
    {
        name = "Multiplier chain: _Multiply multiplies every source per stat and ignores bad values",
        func = function()
            local combined = lib()._Multiply({
                { { reload_time = 0.5, recoil = 2 }, { reload_time = 0.5 } },
                { { reload_time = 4, spread = -1 } },
                { { recoil = 0.25, move_speed = "fast" } }
            })
            expect(combined).to.deepEqual({ reload_time = 1, recoil = 0.5 })
            expect(lib()._WeaponMods({ reload_time = 0.5, move_speed = 2 }, { "reload_time", "recoil" }))
                .to.deepEqual({ reload_time = 0.5 })
        end
    },
    {
        name = "Owner filter: a kill reaches the attacker (OnKill) and the victim (OnDeath); a suicide only OnDeath",
        func = function()
            local a, b = fakePlayer(), fakePlayer()
            local isPlayer = function(ent) return ent == a or ent == b end
            expect(lib()._Targets("kill", b, a, isPlayer)).to.deepEqual({
                { owner = a, method = "OnKill", other = b }, { owner = b, method = "OnDeath", other = a } })
            expect(lib()._Targets("kill", b, b, isPlayer))
                .to.deepEqual({ { owner = b, method = "OnDeath", other = b } })
            local world = {}
            expect(lib()._Targets("damage", b, world, isPlayer))
                .to.deepEqual({ { owner = b, method = "OnDamaged", other = world } })
            expect(lib()._Targets("damage", b, a, isPlayer)).to.deepEqual({
                { owner = a, method = "OnDealDamage", other = b }, { owner = b, method = "OnDamaged", other = a } })
        end
    }
}

local moduleCases = {
    {
        name = "PW.Stat: multiplies the perk, wildcard and mode multipliers",
        func = function()
            installStore()
            test.wildcard = { reload_time = 0.25, recoil = 2 }
            PW.ActiveMode = { Stats = { reload_time = 2, move_speed = 2 } }
            local ply = fakePlayer()
            lib()._OnLoadoutGiven(ply, { perk1 = "pwt_fast", perk2 = "pwt_steady" })
            local stat = must(PW.Stat)
            -- perk 0.5 x wildcard 0.25 x mode 2
            expect(stat(ply, "reload_time", 8)).to.equal(2)
            expect(stat(ply, "recoil", 3)).to.equal(3)
            expect(stat(ply, "move_speed", 100)).to.equal(250)
            expect(stat(ply, "unknown", 7)).to.equal(7)
            expect(stat(fakePlayer(), "reload_time", 8)).to.equal(8)
            -- The weapon stats go through PW.SetStatMods once.
            expect(#test.sent).to.equal(1)
            expect(test.sent[1].mods).to.deepEqual({ reload_time = 0.25, recoil = 1 })
        end
    },
    {
        name = "PW.Stat: recomputed on spawn and loadout change only, cached otherwise",
        func = function()
            installStore()
            test.wildcard, test.sourceCalls = { reload_time = 0.5 }, 0
            local a, b = fakePlayer(), fakePlayer()
            lib()._OnLoadoutGiven(a, { perk1 = "pwt_fast" })
            expect(test.sourceCalls).to.equal(1)
            for _ = 1, 20 do must(PW.Stat)(a, "reload_time", 1) end
            lib()._OnKilled(b, a, nil)
            lib()._OnDamaged(a, b)
            hook.Run("Think")
            expect(test.sourceCalls).to.equal(1)
            -- A source changing meanwhile is not seen until the next recompute.
            test.wildcard = { reload_time = 1 }
            expect(must(PW.Stat)(a, "reload_time", 1)).to.equal(0.25)
            -- Loadout change (a mode gives a new loadout) and the next spawn recompute.
            lib()._OnLoadoutGiven(a, { perk2 = "pwt_steady" })
            expect(test.sourceCalls).to.equal(2)
            expect(must(PW.Stat)(a, "reload_time", 1)).to.equal(1)
            expect(lib().Get(a)).to.deepEqual({ "pwt_steady" })
            lib()._OnLoadoutGiven(a, { perk2 = "pwt_steady" })
            expect(test.sourceCalls).to.equal(3)
        end
    },
    {
        name = "Events: perk event methods are called only for the owner",
        func = function()
            installStore()
            local a, b, c = fakePlayer(), fakePlayer(), fakePlayer()
            lib()._OnLoadoutGiven(a, { perk1 = "pwt_fast" })
            lib()._OnLoadoutGiven(b, { perk2 = "pwt_steady" })
            lib()._OnLoadoutGiven(c, { perk1 = "pwt_other1" })
            test.calls = {}
            lib()._OnDamaged(b, a)
            lib()._OnKilled(b, a, nil)
            local deal, damaged = callsOf("OnDealDamage"), callsOf("OnDamaged")
            local kill, death = callsOf("OnKill"), callsOf("OnDeath")
            expect(#deal + #damaged + #kill + #death).to.equal(#test.calls)
            expect(#deal).to.equal(1)
            expect(deal[1].perk).to.equal("pwt_fast")
            expect(deal[1].owner).to.equal(a)
            expect(deal[1].other).to.equal(b)
            expect(#damaged).to.equal(1)
            expect(damaged[1].perk).to.equal("pwt_steady")
            expect(#kill).to.equal(1)
            expect(kill[1].owner).to.equal(a)
            expect(kill[1].self).toNot.equal(perks.pwt_fast)
            expect(#death).to.equal(1)
            expect(death[1].owner).to.equal(b)
            for _, call in ipairs(test.calls) do expect(call.owner).toNot.equal(c) end
        end
    },
    {
        name = "Instances: every perk instance of the owner ends on death; hooks, cache and stat mods go with it",
        func = function()
            installStore()
            local a, b = fakePlayer(), fakePlayer()
            local pinged = 0
            local hooked = testPerk("pwt_hooked", 1, { reload_time = 0.5 })
            hooked.OnEquip = function(self)
                self:Hook("PW_PerksTestPing", function() pinged = pinged + 1 end)
            end
            perks.pwt_hooked = hooked
            lib()._OnLoadoutGiven(a, { perk1 = "pwt_hooked", perk2 = "pwt_steady" })
            lib()._OnLoadoutGiven(b, { perk2 = "pwt_steady" })
            local instances = must(must(PW._Perks).players[a]).instances
            expect(#instances).to.equal(2)
            hook.Run("PW_PerksTestPing")
            expect(pinged).to.equal(1)
            test.calls = {}
            lib()._OnDeath(a)
            perks.pwt_hooked = nil
            for _, instance in ipairs(instances) do expect(instance:IsValid()).to.beFalse() end
            local unequipped = callsOf("OnUnequip")
            expect(#unequipped).to.equal(2)
            for _, call in ipairs(unequipped) do expect(call.owner).to.equal(a) end
            hook.Run("PW_PerksTestPing")
            expect(pinged).to.equal(1)
            expect(lib().Get(a)).to.deepEqual({})
            expect(must(PW.Stat)(a, "reload_time", 1)).to.equal(1)
            expect(test.sent[#test.sent].ply).to.equal(a)
            expect(test.sent[#test.sent].mods).to.deepEqual({})
            -- The other player keeps theirs.
            expect(lib().Get(b)).to.deepEqual({ "pwt_steady" })
            expect(must(must(PW._Perks).players[b]).instances[1]:IsValid()).to.beTrue()
        end
    }
}

local wiringCases = {
    {
        name = "Wiring: the kind, the perk slots with one group each and the default loadout",
        func = function()
            local loadout = must(PW.Loadout)
            for group = 1, 3 do
                local slot = must(loadout.GetSlot("perk" .. group))
                expect(slot.kind).to.equal("perks")
                expect(slot.group).to.equal(group)
            end
            local default = loadout.Default()
            expect(default.perk1).to.exist()
            expect(default.perk2).to.exist()
            expect(default.perk3).to.exist()
            expect(loadout.Validate(fakePlayer(), default)).to.beTrue()
            local ctx = loadout._Context(function() return nil end, loadout._RegistryLookup)
            expect(loadout._Cost(PW._Loadout.slots, default, ctx) <= ctx.budget).to.beTrue()
        end
    },
    {
        name = "Wiring: four sample perks: two stat perks, an event perk and a custom-hook perk",
        func = function()
            local registry = must(PW.Registries.perks)
            local reload = must(registry.Get("sleight_of_hand"))
            local sprint = must(registry.Get("ready_up"))
            local regen = must(registry.Get("adrenaline"))
            local flak = must(registry.Get("flak_jacket"))
            expect(must(reload.Stats).reload_time < 1).to.beTrue()
            expect(must(sprint.Stats).sprint_to_fire < 1).to.beTrue()
            expect(regen.OnKill).to.exist()
            expect(flak.OnEquip).to.exist()
            for _, preset in ipairs(must(PW.Classes).GetList()) do
                expect(preset.Loadout.perk1).to.exist()
                expect(preset.Loadout.perk2).to.exist()
                expect(preset.Loadout.perk3).to.exist()
            end
        end
    },
    {
        name = "Wiring: PW_LoadoutGiven, PW_PlayerKilled and the death hook reach the module",
        func = function()
            installStore()
            local a, b = fakePlayer(), fakePlayer()
            -- The module's own listeners, called directly: other modules' listeners would get the fake players.
            local entity = must(PW.Modules.Get("perks"))
            local listeners = hook.GetTable()
            local given = must(must(listeners.PW_LoadoutGiven)[entity]) --[[@as fun(self: table, ...: any)]]
            local killed = must(must(listeners.PW_PlayerKilled)[entity]) --[[@as fun(self: table, ...: any)]]
            expect(must(listeners.PW_ValidateLoadout)[entity]).to.exist()
            given(entity, a, { perk1 = "pwt_fast" })
            given(entity, b, { perk2 = "pwt_steady" })
            expect(lib().Get(a)).to.deepEqual({ "pwt_fast" })
            test.calls = {}
            killed(entity, b, a, nil)
            expect(#callsOf("OnKill")).to.equal(1)
            expect(#callsOf("OnDeath")).to.equal(1)
            local hooks = must(must(PW.Modules.GetStored("perks"))._EngineHooks)
            expect(hooks.PostPlayerDeath).to.exist()
            expect(hooks.PostEntityTakeDamage).to.exist()
            expect(hooks.PlayerDisconnected).to.exist()
        end
    }
}

---@param instances PW.Instance[]
---@return boolean
local function anyValid(instances)
    for _, instance in ipairs(instances) do
        if instance:IsValid() then return true end
    end
    return false
end

---@param bot Player
---@param fail fun(message: string)
---@param after fun()
local function checkBot(bot, fail, after)
    if not IsValid(bot) then return fail("the shared bot is gone") end
    bot:Spawn()
    timer.Simple(0.3, function()
        if not IsValid(bot) then return fail("the shared bot is gone") end
        local ids = lib().Get(bot)
        if #ids ~= 3 then return fail("the bot has " .. #ids .. " perks after spawn, expected 3") end
        local instances = must(must(PW._Perks).players[bot]).instances
        bot:Kill()
        timer.Simple(0.2, function()
            if anyValid(instances) then return fail("a perk instance survived the death") end
            if #lib().Get(bot) ~= 0 then return fail("the bot still has perks after death") end
            after()
        end)
    end)
end

---The shared bot of the in-game case. A bot another group left behind is reused.
---@return Player
local function sharedBot()
    local bot = test.bot
    if bot ~= nil and IsValid(bot) then return bot end
    bot = player.GetBots()[1]
    if bot == nil then
        bot = player.CreateNextBot("PW perks test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        test.created = bot
    end
    test.bot = bot
    return bot
end

local gameCases = {
    {
        name = "In-game smoke: in a LIVE match the shared bot spawns with the default perks and loses them on death",
        async = true,
        timeout = 20,
        func = function()
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
                if match().GetPhase() ~= "LOBBY" then match().Abort("perks smoke: " .. message) end
                error(message, 0)
            end
            local function waitFor(phase, deadline, after)
                if match().GetPhase() == phase then return after() end
                if CurTime() > deadline then fail("phase " .. phase .. " not reached, still " .. match().GetPhase()) end
                timer.Simple(0.1, function() waitFor(phase, deadline, after) end)
            end
            waitFor("LIVE", CurTime() + 5, function()
                checkBot(sharedBot(), fail, function()
                    match().Abort("perks smoke done")
                    waitFor("LOBBY", CurTime() + 5, function()
                        restore()
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
    ---@type table[][]
    local lists = { ... }
    for _, list in ipairs(lists) do
        for _, case in ipairs(list) do all[#all + 1] = case end
    end
    return all
end

return {
    groupName = "PW perks",
    beforeAll = function()
        lib().StatSource("pwt_wildcard", function()
            test.sourceCalls = test.sourceCalls + 1
            return { test.wildcard }
        end)
    end,
    beforeEach = function()
        test.previousPerks = PW._Perks
        test.previousMode = rawget(PW, "ActiveMode")
        test.wildcard, test.sourceCalls = nil, 0
    end,
    afterEach = function()
        local store = PW._Perks
        if store ~= nil and store ~= test.previousPerks then
            for ply in pairs(store.players) do must(lib()._Clear)(ply) end
        end
        PW._Perks = test.previousPerks
        PW.ActiveMode = test.previousMode
    end,
    afterAll = function()
        lib().StatSource("pwt_wildcard", nil)
        local created = test.created
        if created ~= nil and IsValid(created) then created:Kick("perks tests done") end
    end,
    cases = join(pureCases, moduleCases, wiringCases, gameCases)
}
