-- Controlled native LIVE transitions, not an extrapolated per-bot microbenchmark. Test-only wrappers delegate
-- unchanged production functions; no validation result or player permission is cached by this fixture.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@class PW.Arc9StartSample
---@field order integer
---@field enabled boolean
---@field regime string
---@field cold boolean discovery-cold, not OS/model-cold
---@field phase number
---@field frame number
---@field nextTick number
---@field assign number
---@field pool number
---@field provider number
---@field give number
---@field weaponGive number
---@field apply number
---@field assignments integer
---@field spawns integer
---@field picked string[]

---@class PW.Arc9StartPerfTest
---@field created? Player[]
---@field bots? Player[]
---@field humans? Player[]
---@field uploads? table<Player, PW.LoadoutClass[]>
---@field players? table<string, PW.BotPlayerClass[]>
---@field paused? boolean
---@field saved? table<string, any>
---@field cvars? table<string, string>
---@field current? PW.Arc9StartSample
---@field results? PW.Arc9StartSample[]
---@field finish fun()
---@field makeStub fun(tbl: table, key: any): GLuaTest_Stub

local hookId = "PW.Arc9StartPerf"

---@param test PW.Arc9StartPerfTest
---@param key string
---@param call function
---@param ... any
---@return any ...
local function timed(test, key, call, ...)
    local start = SysTime()
    local result = { call(...) }
    local current = test.current --[[@as table<string, any>?]]
    if current ~= nil then current[key] = current[key] + (SysTime() - start) * 1000 end
    return unpack(result)
end

---@param test PW.Arc9StartPerfTest
local function instrument(test)
    local makeStub = test.makeStub
    local bots, loadout = must(PW.BotLoadouts), must(PW.Loadout)
    local assign, pool, give = bots.Assign, bots.PoolFor, loadout.Give
    local notify, ammoGive, adapterCall = PW.Notify, PW.WeaponAmmo.Give, PW.Adapters.Call
    local phase = must(PW.Match)._SetPhase
    makeStub(bots, "PoolFor").with(function(...) return timed(test, "pool", pool, ...) end)
    makeStub(bots, "Assign").with(function(...)
        local entry = timed(test, "assign", assign, ...)
        if test.current ~= nil then
            test.current.assignments = test.current.assignments + 1
            test.current.picked[#test.current.picked + 1] = entry ~= nil and entry.ref or "default"
        end
        return entry
    end)
    makeStub(loadout, "Give").with(function(ply, ...)
        if not ply:IsBot() then return give(ply, ...) end
        if test.current ~= nil then
            assert(bots.PickOf(ply) ~= nil, "first spawn reached Give without an assigned class")
            test.current.spawns = test.current.spawns + 1
        end
        return timed(test, "give", give, ply, ...)
    end)
    makeStub(PW.WeaponAmmo, "Give").with(function(...) return timed(test, "weaponGive", ammoGive, ...) end)
    makeStub(PW.Adapters, "Call").with(function(adapter, method, ...)
        if method == "Apply" then return timed(test, "apply", adapterCall, adapter, method, ...) end
        return adapterCall(adapter, method, ...)
    end)
    makeStub(PW, "Notify").with(function(name, ...)
        if name == "PW_BotLoadoutCandidates" then return timed(test, "provider", notify, name, ...) end
        return notify(name, ...)
    end)
    makeStub(must(PW.Match), "_SetPhase").with(function(to, ...)
        if to ~= "LIVE" or test.current == nil then return phase(to, ...) end
        local sample, start = test.current, SysTime()
        local result = phase(to, ...)
        sample.phase = (SysTime() - start) * 1000
        timer.Simple(0, function() sample.nextTick = (SysTime() - start) * 1000 end)
        return result
    end)
    local previous = SysTime()
    hook.Add("Think", hookId, function()
        local now = SysTime()
        if test.current ~= nil then test.current.frame = math.max(test.current.frame, (now - previous) * 1000) end
        previous = now
    end)
end

---@param test PW.Arc9StartPerfTest
local function setup(test)
    test.created, test.bots, test.humans = {}, player.GetBots(), player.GetHumans()
    assert(#test.bots <= 9 and #test.humans == 1, "benchmark needs one host and at most nine existing bots")
    test.uploads, test.players = must(PW._LoadoutClasses).uploads, PW._BotLoadouts.players
    test.paused = PW._BotLoadouts.paused
    test.saved, test.cvars, test.results = {}, {}, {}
    for _, id in ipairs({ "bots.classes", "bots_arc9_loadouts.generate", "loadout.budget",
        "loadout.maxattachments", "loadout.bannedweapons", "loadout.bannedattachments", "progression.unlockall" }) do
        test.saved[id] = PW.Setting(id)
    end
    for _, name in ipairs({ "pw_prematch_timeout", "pw_countdown" }) do
        test.cvars[name] = must(GetConVar(name)):GetString()
        must(GetConVar(name)):SetString("0")
    end
    for _, id in ipairs({ "loadout.bannedweapons", "loadout.bannedattachments" }) do must(PW.Settings).Set(id, {}) end
    must(PW.Settings).Set("loadout.budget", 10)
    must(PW.Settings).Set("loadout.maxattachments", 5)
    must(PW.Settings).Set("bots.classes", { "preset", "players" })
    must(PW.Settings).Set("progression.unlockall", true)
    local entries = must(PW._Arc9BotLoadouts).entries
    local recorded = file.Read("privatewar_dev/arc9_start_dataset.json", "DATA")
    if recorded ~= nil then
        entries = must(util.JSONToTable(recorded)) --[[@as PW.BotClassEntry[] ]]
        assert(#entries == 18, "invalid controlled benchmark dataset")
        for _, entry in ipairs(entries) do assert(must(PW.Arc9BotLoadouts).Legal(entry), "stale benchmark dataset") end
        test.makeStub(must(PW.Arc9BotLoadouts), "Candidates").with(function() return entries end)
    end
    PW._LoadoutClasses.uploads = { [test.humans[1]] = {
        { name = "Perf human A", loadout = table.Copy(entries[1].loadout) },
        { name = "Perf human B", loadout = table.Copy(entries[4].loadout) }
    } }
    PW._BotLoadouts.players = {}
    while #test.bots < 9 do
        local bot = player.CreateNextBot("PW startup measurement " .. (#test.bots + 1))
        assert(IsValid(bot), "not enough real player slots for nine bots")
        test.created[#test.created + 1], test.bots[#test.bots + 1] = bot, bot
    end
    for _, bot in ipairs(test.bots) do must(PW.BotInput).SetScripted(bot, { buttons = 0 }) end
    instrument(test)
end

---@param test PW.Arc9StartPerfTest
---@param trials { enabled: boolean, regime: string, cold: boolean }[]
---@param index integer
local function trial(test, trials, index)
    local item = trials[index]
    if item == nil then
        for _, sample in ipairs(must(test.results)) do
            print("[PW] ARC9 START PERF " .. util.TableToJSON(sample))
        end
        print("[PW] ARC9 START PERF complete: nine real bots; two fixed human ARC9 classes; existing enabled presets")
        test.finish()
        return
    end
    local match = must(PW.Match)
    assert(match.GetPhase() == "LOBBY", "benchmark must start each trial in LOBBY")
    must(PW.Settings).Set("bots_arc9_loadouts.generate", item.enabled)
    if item.cold then
        -- Our integration's discovery cache only. ARC9's internals and map-stable generated candidates are untouched.
        must(PW._Arc9).memo = { revision = nil, values = {} }
        PW.Adapters.Invalidate()
    end
    ---@type PW.Arc9StartSample
    local sample = { order = index, enabled = item.enabled, regime = item.regime, cold = item.cold,
        phase = 0, frame = 0, nextTick = 0, assign = 0, pool = 0, provider = 0, give = 0,
        weaponGive = 0, apply = 0, assignments = 0, spawns = 0, picked = {} }
    test.current = sample
    PW._BotLoadouts.paused = false
    local started = match.Start(must(PW.Modes.Get("tdm")))
    assert(started, "public match start refused")
    local deadline = CurTime() + 10
    local function wait()
        assert(CurTime() < deadline, "LIVE transition timed out")
        if match.GetPhase() ~= "LIVE" then timer.Simple(0.02, wait) return end
        timer.Simple(0.5, function()
            test.current = nil
            assert(sample.assignments == 9, "expected exactly nine pre-spawn assignments")
            assert(sample.spawns == 9, "expected exactly nine first bot spawns")
            assert(sample.phase > 0 and sample.nextTick > 0, "missing real transition timing")
            table.insert(must(test.results), sample)
            PW._BotLoadouts.paused = true
            match.Abort("ARC9 startup trial complete")
            timer.Simple(0.2, function() trial(test, trials, index + 1) end)
        end)
    end
    wait()
end

return {
    groupName = "PW ARC9 actual LIVE startup timings",
    skip = function() return PW.Arc9BotLoadouts == nil or ARC9 == nil end,
    cases = {
        {
            name = "Controlled native startup: nine assigned before first spawn, cold/warm paired ON/OFF frame timings",
            async = true,
            timeout = 240,
            ---@param test PW.Arc9StartPerfTest
            cleanup = function(test)
                test.current = nil
                hook.Remove("Think", hookId)
                PW._BotLoadouts.paused = true
                if must(PW.Match).GetPhase() ~= "LOBBY" then must(PW.Match).Abort("startup benchmark cleanup") end
                for _, bot in ipairs(test.bots or {}) do must(PW.BotInput).SetScripted(bot, nil) end
                for _, bot in ipairs(test.created or {}) do
                    if IsValid(bot) then bot:Kick("startup benchmark done") end
                end
                if test.uploads ~= nil then PW._LoadoutClasses.uploads = test.uploads end
                if test.players ~= nil then PW._BotLoadouts.players = test.players end
                if test.paused ~= nil then PW._BotLoadouts.paused = test.paused end
                for id, value in pairs(test.saved or {}) do must(PW.Settings).Set(id, value) end
                for name, value in pairs(test.cvars or {}) do must(GetConVar(name)):SetString(value) end
            end,
            ---@param test PW.Arc9StartPerfTest
            func = function(test)
                test.makeStub, test.finish = stub, done
                local deadline = CurTime() + 60
                local function ready()
                    local state = PW._Arc9BotLoadouts
                    if state == nil or state.status == "working" then
                        assert(CurTime() < deadline, "generator not ready for startup benchmark")
                        timer.Simple(0.05, ready)
                        return
                    end
                    assert(state.status == "ready" and #state.entries == 18, "benchmark requires the mounted full pool")
                    setup(test)
                    local pick, roll = must(PW.BotLoadouts).Pick, 0
                    stub(must(PW.BotLoadouts), "Pick").with(function(pool, weights, _, categoryOf)
                        roll = roll + 1
                        local current = must(test.current)
                        local value = current.regime == "fixed" and 0 or (((roll - 1) % 9) + 0.5) / 9
                        return pick(pool, weights, value, categoryOf)
                    end)
                    ---@type { enabled: boolean, regime: string, cold: boolean }[]
                    local trials = {}
                    for _, name in ipairs({ "fixed", "mixed" }) do
                        for pair = 1, 9 do
                            local first = pair % 2 == 0
                            trials[#trials + 1] = { enabled = first, regime = name, cold = pair <= 3 }
                            trials[#trials + 1] = { enabled = not first, regime = name, cold = pair <= 3 }
                        end
                    end
                    timer.Simple(0.5, function() trial(test, trials, 1) end)
                end
                ready()
            end
        }
    }
}
