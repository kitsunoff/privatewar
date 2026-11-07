-- Hot paths of the T-10.4 load test (docs/perf-report.md). Each case pins one low-risk fix: the same answer as
-- before, without the per-tick work the profiler found. No bot is created; player.GetAll is swapped for a counter
-- and restored after each case.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---A mode stand-in for MatchRules.Check: started, `teams` teams, no limits.
---@param teams integer
---@return PW.Mode
local function fakeMode(teams)
    return {
        ClassName = "pw_test_perf", Teams = teams, _StartedAt = CurTime(),
        Setting = function() return 0 end
    } --[[@as any]]
end

---@class PWT.PerfStatModFixture
---@field reads integer GetWeapons calls for the player
---@field refresh table<Weapon, integer>
---@field install table<Weapon, integer>
---@field restore fun()

---Counts the player's GetWeapons calls and the stat mod adapter calls per weapon (the adapter calls are not run).
---@param ply Player
---@return PWT.PerfStatModFixture
local function statModFixture(ply)
    local meta = FindMetaTable("Player") --[[@as table<string, any>]]
    local adapters = PW.Adapters --[[@as table<string, any>]]
    local getWeapons, callFor = meta.GetWeapons, adapters.CallFor
    ---@type PWT.PerfStatModFixture
    local fixture = { reads = 0, refresh = {}, install = {}, restore = function() end }
    fixture.restore = function()
        rawset(meta, "GetWeapons", getWeapons)
        adapters.CallFor = callFor
    end
    rawset(meta, "GetWeapons", function(self)
        if self == ply then fixture.reads = fixture.reads + 1 end
        return getWeapons(self)
    end)
    adapters.CallFor = function(weaponOrClass, method, ...)
        if method == "RefreshStatMods" or method == "InstallStatMods" then
            local counts = method == "RefreshStatMods" and fixture.refresh or fixture.install
            counts[weaponOrClass] = (counts[weaponOrClass] or 0) + 1
            return nil
        end
        return callFor(weaponOrClass, method, ...)
    end
    return fixture
end

---Runs body with the fixture on the host; the fixture and the host's modifiers are removed afterwards.
---@param body fun(ply: Player, fixture: PWT.PerfStatModFixture)
local function withStatMods(body)
    local ply = must(player.GetHumans()[1])
    local fixture = statModFixture(ply)
    local ok, err = pcall(body, ply, fixture)
    fixture.restore()
    must(PW.StatMods).SetStatMods(ply, nil)
    if not ok then error(err, 0) end
end

return {
    groupName = "PW perf hot paths (T-10.4)",
    beforeEach = function(state)
        state.getAll = player.GetAll
        state.calls = 0
        local original = player.GetAll
        rawset(player, "GetAll", function()
            state.calls = state.calls + 1
            return original()
        end)
    end,
    afterEach = function(state)
        rawset(player, "GetAll", state.getAll)
    end,
    cases = {
        {
            name = "MatchRules.Check in a team mode builds no player list",
            func = function(state)
                local check = must(must(PW.MatchRules).Check)
                expect(check(fakeMode(2), CurTime())).to.beNil()
                expect(state.calls).to.equal(0)
            end
        },
        {
            name = "MatchRules.Check in FFA still reads the players",
            func = function(state)
                local check = must(must(PW.MatchRules).Check)
                expect(check(fakeMode(0), CurTime())).to.beNil()
                expect(state.calls).to.equal(1)
            end
        },
        {
            name = "Aim params: one table per bot while its difficulty and tier stay the same",
            func = function()
                local aim = must(PW.BotAim)
                local paramsOf = must(aim._ParamsOf)
                local bot, other = {}, {}
                local difficulty = { aim_focus_initial = 3 }
                local board = { difficulty = difficulty } --[[@as any]]
                local first = paramsOf(bot --[[@as Player]], board)
                expect(paramsOf(bot --[[@as Player]], board)).to.equal(first)
                expect(first.aim_focus_initial).to.equal(3)
                expect(paramsOf(other --[[@as Player]], board) ~= first).to.beTrue()
                local harder = { difficulty = { aim_focus_initial = 4 } } --[[@as any]]
                local changed = paramsOf(bot --[[@as Player]], harder)
                expect(changed ~= first).to.beTrue()
                expect(changed.aim_focus_initial).to.equal(4)
                local fresh = aim.ParamsFor(nil, "veteran")
                local plain = paramsOf(bot --[[@as Player]], nil)
                expect(plain.look_stiffness ~= nil).to.beTrue()
                expect(fresh ~= aim.ParamsFor(nil, "veteran")).to.beTrue()
            end
        },
        {
            name = "Input rules: merging rules that are already merged returns them as they are",
            func = function()
                local input = must(PW.BotInput)
                local full = input._Rules({ reloadTap = true })
                expect(input._Rules(full)).to.equal(full)
                expect(full.reloadTap).to.beTrue()
                expect(full.reselectEveryTick).to.beTrue()
                local other = input._Rules({ reloadTap = true })
                expect(other ~= full).to.beTrue()
                expect(input._Rules(nil) ~= input._Rules(nil)).to.beTrue()
            end
        },
        {
            name = "Settings: the index is reused while the mode and module lists hold the same entities",
            func = function()
                local settings = must(PW.Settings)
                local saved = PW._Settings
                ---@type table[]
                local modules = { { ClassName = "pwt_perf_a", Settings = { x = { type = "int", default = 1 } } } }
                local registries = {
                    modes = { GetList = function() return {} end },
                    modules = { GetList = function() return { unpack(modules) } end }
                }
                PW._Settings = settings._NewStore({ registries = function() return registries --[[@as any]] end,
                    log = function() end })
                local ok, err = pcall(function()
                    local first = settings._CurrentIndex()
                    expect(settings._CurrentIndex()).to.equal(first)
                    expect(first["pwt_perf_a.x"] ~= nil).to.beTrue()
                    modules[2] = { ClassName = "pwt_perf_b", Settings = { y = { type = "int", default = 2 } } }
                    local second = settings._CurrentIndex()
                    expect(second ~= first).to.beTrue()
                    expect(second["pwt_perf_b.y"] ~= nil).to.beTrue()
                    modules[1] = { ClassName = "pwt_perf_a", Settings = { z = { type = "int", default = 3 } } }
                    local third = settings._CurrentIndex()
                    expect(third["pwt_perf_a.z"] ~= nil).to.beTrue()
                    expect(third["pwt_perf_a.x"]).to.beNil()
                    table.remove(modules, 2)
                    expect(settings._CurrentIndex()["pwt_perf_b.y"]).to.beNil()
                end)
                PW._Settings = saved
                if not ok then error(err, 0) end
            end
        },
        {
            name = "Stat mods: the server reads a player's weapons only after a revision change or an equip",
            func = function()
                withStatMods(function(ply, fixture)
                    local mods = must(PW.StatMods)
                    mods.SetStatMods(ply, { reload_time = 0.9 })
                    mods._Tick()
                    fixture.reads = 0
                    for _ = 1, 5 do mods._Tick() end
                    expect(fixture.reads).to.equal(0)
                    mods.SetStatMods(ply, { reload_time = 0.8 })
                    mods._Tick()
                    mods._Tick()
                    expect(fixture.reads).to.equal(1)
                end)
            end
        },
        {
            name = "Stat mods: a weapon given later still gets installed and refreshed",
            async = true,
            timeout = 5,
            func = function()
                local mods = must(PW.StatMods)
                local ply = must(player.GetHumans()[1])
                local fixture = statModFixture(ply)
                local held = ply:HasWeapon("weapon_pistol")
                if held then ply:StripWeapon("weapon_pistol") end
                mods.SetStatMods(ply, { reload_time = 0.9 })
                timer.Simple(0.2, function()
                    ply:Give("weapon_pistol", true)
                    local wep = must(ply:GetWeapon("weapon_pistol"))
                    timer.Simple(0.3, function()
                        fixture.restore()
                        mods.SetStatMods(ply, nil)
                        if not held then ply:StripWeapon("weapon_pistol") end
                        expect(fixture.install[wep]).to.equal(1)
                        expect(fixture.refresh[wep]).to.equal(1)
                        done()
                    end)
                end)
            end
        }
    }
}
