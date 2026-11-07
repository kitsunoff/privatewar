-- T-5.13 bot loadouts (TASKS.md, "Mandatory test cases" T-5.13; 05-loadout.md d.14). Pure cases for the class pool
-- (presets plus the players' valid classes, the sources setting, invalid classes left out), the weighted pick (a fixed
-- roll gives a fixed class; the personality weights by the primary's category) and the re-pick rule; one glue case
-- for "a player's class used by a bot is checked against the match settings, not progression" over the shared bot;
-- the last case is the in-game smoke: in a LIVE test match the shared bot spawns with a class from the pool, its
-- weapons, its lethal and its streak set.

local phaseConVars = { "pw_prematch_timeout", "pw_countdown", "pw_postmatch_time", "pw_aftermatch" }

---State of this group.
---@class PW.BotLoadoutsTestState
---@field bot Player?
---@field created Player?
local test = {}

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotLoadoutsLib
local function lib()
    return must(PW.BotLoadouts)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---Weapon categories of the fixtures.
local categories = { w_ar = "ar", w_smg = "smg", w_shotgun = "shotgun", w_sniper = "sniper" }

---@param id string
---@return string?
local function categoryOf(id)
    return categories[id]
end

---@param primary string
---@param extra? table<string, any>
---@return PW.Loadout
local function loadout(primary, extra)
    ---@type PW.Loadout
    local out = { primary = primary, secondary = "w_pistol" }
    for key, value in pairs(extra or {}) do out[key] = value end
    return out
end

---@return PW.BotPoolInput
local function poolInput()
    return {
        sources = { preset = true, players = true },
        presets = {
            { id = "assault", name = "Assault", loadout = loadout("w_ar") },
            { id = "cqb", name = "CQB", loadout = loadout("w_shotgun") },
            { id = "broken", name = "Broken", loadout = loadout("w_missing") }
        },
        players = {
            { key = "76561:2", name = "Sniper", loadout = loadout("w_sniper") },
            { key = "76561:1", name = "Mine", loadout = loadout("w_smg") },
            { key = "76562:1", name = "Over budget", loadout = loadout("w_smg", { over = true }) }
        },
        check = function(value)
            local l = value --[[@as table<string, any>]]
            return l.primary ~= "w_missing" and l.over ~= true
        end
    }
end

---@param pool PW.BotClassEntry[]
---@return string[]
local function refs(pool)
    ---@type string[]
    local out = {}
    for i, entry in ipairs(pool) do out[i] = entry.ref end
    return out
end

---How often each ref is picked over n evenly spaced rolls.
---@param pool PW.BotClassEntry[]
---@param weights table<string, number>?
---@param n integer
---@return table<string, integer>
local function sweep(pool, weights, n)
    ---@type table<string, integer>
    local counts = {}
    for i = 0, n - 1 do
        local entry = must(lib().Pick(pool, weights, (i + 0.5) / n, categoryOf))
        counts[entry.ref] = (counts[entry.ref] or 0) + 1
    end
    return counts
end

local pureCases = {
    {
        name = "Mandatory (T-5.13): the class pool holds the presets plus the players' valid classes",
        func = function()
            local pool = lib().BuildPool(poolInput())
            expect(refs(pool)).to.deepEqual({ "preset:assault", "preset:cqb", "player:76561:1", "player:76561:2" })
            expect(pool[1].source).to.equal("preset")
            expect(pool[3].source).to.equal("players")
            expect(pool[3].name).to.equal("Mine")
            expect(pool[3].loadout.primary).to.equal("w_smg")
        end
    },
    {
        name = "Mandatory (T-5.13): invalid classes are left out of the pool",
        func = function()
            local pool = lib().BuildPool(poolInput())
            for _, ref in ipairs(refs(pool)) do
                expect(ref ~= "preset:broken").to.beTrue()
                expect(ref ~= "player:76562:1").to.beTrue()
            end
            local input = poolInput()
            input.check = function() return false end
            expect(#lib().BuildPool(input)).to.equal(0)
        end
    },
    {
        name = "Pool: the sources setting picks presets, players, both or none (nil means both)",
        func = function()
            local input = poolInput()
            input.sources = { preset = true }
            expect(refs(lib().BuildPool(input))).to.deepEqual({ "preset:assault", "preset:cqb" })
            input.sources = { players = true }
            expect(refs(lib().BuildPool(input))).to.deepEqual({ "player:76561:1", "player:76561:2" })
            input.sources = {}
            expect(#lib().BuildPool(input)).to.equal(0)
            expect(lib().Sources(nil)).to.deepEqual({ preset = true, players = true })
            expect(lib().Sources({ players = true })).to.deepEqual({ preset = false, players = true })
        end
    },
    {
        name = "Mandatory (T-5.13): the weighted pick is deterministic for a roll and covers the pool",
        func = function()
            local pool = lib().BuildPool(poolInput())
            for _, roll in ipairs({ 0, 0.13, 0.5, 0.77, 0.999, 1 }) do
                local a = must(lib().Pick(pool, nil, roll, categoryOf))
                local b = must(lib().Pick(pool, nil, roll, categoryOf))
                expect(a.ref).to.equal(b.ref)
            end
            expect(must(lib().Pick(pool, nil, 0, categoryOf)).ref).to.equal("preset:assault")
            expect(must(lib().Pick(pool, nil, 0.99, categoryOf)).ref).to.equal("player:76561:2")
            expect(sweep(pool, nil, 400)).to.deepEqual({
                ["preset:assault"] = 100, ["preset:cqb"] = 100, ["player:76561:1"] = 100, ["player:76561:2"] = 100
            })
            expect(lib().Pick({}, nil, 0.5, categoryOf)).to.beNil()
        end
    },
    {
        name = "Mandatory (T-5.13): personality weights favour classes by the primary's category",
        func = function()
            local pool = lib().BuildPool(poolInput())
            local counts = sweep(pool, { shotgun = 3, sniper = 0 }, 500)
            -- weights: assault 1, cqb 3, smg 1, sniper 0 -> 100 / 300 / 100 / 0 of 500
            expect(counts["preset:cqb"]).to.equal(300)
            expect(counts["preset:assault"]).to.equal(100)
            expect(counts["player:76561:2"]).to.beNil()
            expect(lib().Weight(pool[2], { shotgun = 3 }, categoryOf)).to.equal(3)
            expect(lib().Weight(pool[1], { shotgun = 3 }, categoryOf)).to.equal(1)
            expect(lib().Weight(pool[1], nil, categoryOf)).to.equal(1)
            -- all weights zero: the pick falls back to an even draw instead of nothing
            expect(lib().Pick(pool, { ar = 0, shotgun = 0, smg = 0, sniper = 0 }, 0.5, categoryOf)).to.exist()
        end
    },
    {
        name = "Mandatory (T-5.13): the personality files carry class weights (cqb shotgun, camper sniper)",
        func = function()
            local personalities = must(PW.BotPersonalities)
            local cqb = must(personalities.Get("cqb")) --[[@as table<string, any>]]
            local camper = must(personalities.Get("camper")) --[[@as table<string, any>]]
            local runner = must(personalities.Get("run_and_gun")) --[[@as table<string, any>]]
            expect(cqb.class_weights.shotgun > 1).to.beTrue()
            expect(camper.class_weights.sniper > 1).to.beTrue()
            expect(runner.class_weights.smg > 1).to.beTrue()
            local pool = lib().BuildPool(poolInput())
            local counts = sweep(pool, cqb.class_weights, 600)
            expect(counts["preset:cqb"] > counts["preset:assault"]).to.beTrue()
            expect(lib().WeightsOf({ personality = { class_weights = { smg = 2 } } })).to.deepEqual({ smg = 2 })
            expect(lib().WeightsOf({})).to.beNil()
        end
    },
    {
        name = "Re-pick: always without a class or when the class left the pool, else by the chance",
        func = function()
            local pool = lib().BuildPool(poolInput())
            expect(lib().ShouldRepick(nil, pool, 0, 0.5)).to.beTrue()
            expect(lib().ShouldRepick("preset:gone", pool, 0, 0.5)).to.beTrue()
            expect(lib().ShouldRepick("preset:cqb", pool, 0, 0)).to.beFalse()
            expect(lib().ShouldRepick("preset:cqb", pool, 0.25, 0.2)).to.beTrue()
            expect(lib().ShouldRepick("preset:cqb", pool, 0.25, 0.3)).to.beFalse()
            expect(lib().ShouldRepick("preset:cqb", pool, 1, 0.999)).to.beTrue()
        end
    },
    {
        name = "Harvest: only the available custom classes of a player's class state enter the players' pool",
        func = function()
            ---@type PW.LoadoutClassState
            local state = { selected = "", entries = {
                { ref = "preset:assault", name = "Assault", loadout = loadout("w_ar"), removed = {}, available = true },
                { ref = "custom:1", name = "Mine", loadout = loadout("w_smg"), removed = {}, available = true },
                { ref = "custom:2", name = "N/A", loadout = loadout("w_ar"), removed = {}, available = false,
                    reason = "over budget" },
                { ref = "custom:3", name = "Long", loadout = loadout("w_sniper"), removed = {}, available = true }
            } }
            local entries = lib()._HarvestEntries("765", state)
            expect(#entries).to.equal(2)
            expect(entries[1].key).to.equal("765:1")
            expect(entries[1].name).to.equal("Mine")
            expect(entries[2].key).to.equal("765:3")
            expect(entries[2].loadout.primary).to.equal("w_sniper")
        end
    }
}

---The shared bot of the in-game cases. A bot another group left behind is reused.
---@return Player
local function sharedBot()
    local bot = test.bot
    if bot ~= nil and IsValid(bot) then return bot end
    bot = player.GetBots()[1]
    if bot == nil then
        bot = player.CreateNextBot("PW bot loadouts test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        test.created = bot
    end
    test.bot = bot
    return bot
end

local glueCases = {
    {
        name = "Mandatory (T-5.13): a player's class used by a bot is checked against match settings, not progression",
        func = function()
            local bot = sharedBot()
            local store = must(PW._BotLoadouts)
            local saved = store.players
            local setting = PW.Setting
            stub(PW, "Setting").with(function(id)
                if id == "loadout.bannedweapons" then return { weapon_shotgun = true } end
                if id == "bots.classes" then return { preset = true, players = true } end
                return setting(id)
            end)
            local progression = rawget(PW, "Progression") --[[@as table?]]
            local locked = 0
            if progression ~= nil then
                stub(progression, "IsUnlocked").with(function() locked = locked + 1 return false end)
            end
            stub(lib(), "Harvest").with(function() end)
            store.players = { pwtest = {
                { key = "pwtest:1", name = "Rifle", loadout = { primary = "weapon_ar2" } },
                { key = "pwtest:2", name = "Banned", loadout = { primary = "weapon_shotgun" } }
            } }
            local ok, pool = pcall(lib().PoolFor, bot)
            store.players = saved
            expect(ok).to.beTrue()
            ---@type table<string, boolean>
            local found = {}
            local list = pool --[[@as PW.BotClassEntry[] ]]
            for _, entry in ipairs(list) do found[entry.ref] = true end
            expect(found["player:pwtest:1"]).to.beTrue()
            expect(found["player:pwtest:2"]).to.beNil()
            expect(found["preset:close_quarters"]).to.beNil()
            expect(found["preset:assault"]).to.beTrue()
            expect(locked).to.equal(0)
        end
    },
    {
        name = "Wiring: the module answers the spawn, death and disconnect hooks and declares its settings",
        func = function()
            local hooks = must(must(PW.Modules.GetStored("bots_loadouts"))._EngineHooks)
            expect(hooks.PlayerInitialSpawn).to.exist()
            expect(hooks.PlayerSpawn).to.exist()
            expect(hooks.PostPlayerDeath).to.exist()
            expect(hooks.PlayerDisconnected).to.exist()
            local readers = must(PW.BotProfiles).Readers("personality")
            expect(must(readers.class_weights)[1]).to.equal("loadouts")
            expect(PW.Setting("bots.classrepick") ~= nil).to.beTrue()
            expect(istable(PW.Setting("bots.classes"))).to.beTrue()
        end
    }
}

---@param list (string|string[])?
---@return string?
local function first(list)
    if istable(list) then return (list --[[@as string[] ]])[1] end
    return list --[[@as string?]]
end

---Checks the spawned shared bot against the class it got from the pool.
---@param bot Player
---@return string? problem
local function checkSpawned(bot)
    local ref = lib().PickOf(bot)
    if ref == nil then return "the bot has no class after spawning in LIVE" end
    local entry = nil
    for _, candidate in ipairs(lib().PoolFor(bot)) do
        if candidate.ref == ref then entry = candidate end
    end
    if entry == nil then return "the class " .. ref .. " is not in the pool" end
    local primary = first(entry.loadout.primary)
    if primary ~= nil and not bot:HasWeapon(primary) then return "the bot lacks its primary " .. primary end
    local equipment = rawget(PW, "Equipment") --[[@as PW.EquipmentLib?]]
    if equipment ~= nil and equipment.Item(bot, "lethal") ~= first(entry.loadout.lethal) then
        return "the lethal does not follow the class"
    end
    local streaks = rawget(PW, "Streaks") --[[@as PW.StreaksLib?]]
    if streaks ~= nil then
        local l = entry.loadout
        for _, s in ipairs(streaks.Set(bot)) do
            if s.id ~= l.streak1 and s.id ~= l.streak2 and s.id ~= l.streak3 then
                return "the streak " .. s.id .. " is not in the class"
            end
        end
    end
    return nil
end

---A class without a lethal: after a respawn the bot has no grenade, so throw_equipment has nothing to throw.
---@param bot Player
---@return string? problem
local function checkNoLethal(bot)
    local equipment = rawget(PW, "Equipment") --[[@as PW.EquipmentLib?]]
    if equipment == nil then return nil end
    must(PW.Loadout).SetClass(bot, { primary = "weapon_smg1", secondary = "weapon_pistol", streak1 = "uav" })
    bot:Spawn()
    if equipment.Count(bot, "lethal") ~= 0 then return "a bot without a lethal still has grenades" end
    return nil
end

local gameCases = {
    {
        name = "Mandatory (T-5.13), smoke: a bot spawned in LIVE carries a loadout from the pool",
        async = true,
        timeout = 30,
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
            local bot = sharedBot()
            local store = must(PW._BotLoadouts)
            local paused = store.paused
            store.paused = false -- paused during the test run like the bots manager; on for this match only
            expect(match().GetPhase()).to.equal("LOBBY")
            expect(match().Start(must(PW.Modes.Get("tdm")))).to.beTrue()
            local function finish(problem)
                if match().GetPhase() ~= "LOBBY" then match().Abort("bot loadouts smoke done") end
                local deadline = CurTime() + 10
                local function wait()
                    if match().GetPhase() ~= "LOBBY" and CurTime() < deadline then return timer.Simple(0.1, wait) end
                    restore()
                    store.paused = paused
                    expect(problem).to.beNil()
                    done()
                end
                wait()
            end
            local deadline = CurTime() + 10
            local function waitLive()
                if match().GetPhase() ~= "LIVE" then
                    if CurTime() > deadline then return finish("LIVE not reached, still " .. match().GetPhase()) end
                    return timer.Simple(0.1, waitLive)
                end
                timer.Simple(1, function()
                    if not IsValid(bot) then return finish("the shared bot is gone") end
                    if not bot:Alive() then bot:Spawn() end
                    finish(checkSpawned(bot) or checkNoLethal(bot))
                end)
            end
            waitLive()
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
    groupName = "PW bot loadouts",
    afterAll = function()
        local created = test.created
        if created ~= nil and IsValid(created) then created:Kick("bot loadouts tests done") end
    end,
    cases = join(pureCases, glueCases, gameCases)
}
