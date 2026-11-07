-- T-3.5 stat modifiers (TASKS.md, "Mandatory test cases" T-3.5; 04-weapons.md d.6; docs/api/adapter.md "Stat
-- modifiers"). Pure cases check the normalisation, the revision and the sweep bookkeeping over plain data. In-game
-- cases give weapon_smg1 and weapon_pistol to the host (no bots) and replace PW.Adapters.CallFor with a counting
-- fixture; the host's weapons, ammo and modifiers are restored afterwards.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.StatModsLib
local function lib()
    return must(PW.StatMods)
end

---@return Player
local function host()
    return must(player.GetHumans()[1])
end

---@param ply Player
---@return integer
local function revisionOf(ply)
    return ply:GetNW2Int(lib()._RevisionKey, 0)
end

---Counts RefreshStatMods and InstallStatMods calls per weapon; other methods go to the real CallFor.
---@class PWT.StatModCounter
---@field refresh table<Weapon, integer>
---@field install table<Weapon, integer>
---@field restore fun()

---@return PWT.StatModCounter
local function countCalls()
    local adapters = PW.Adapters --[[@as table<string, any>]]
    local original = adapters.CallFor
    ---@type PWT.StatModCounter
    local counter = { refresh = {}, install = {}, restore = function() adapters.CallFor = original end }
    adapters.CallFor = function(weaponOrClass, method, ...)
        if method == "RefreshStatMods" then
            counter.refresh[weaponOrClass] = (counter.refresh[weaponOrClass] or 0) + 1
            return nil
        elseif method == "InstallStatMods" then
            counter.install[weaponOrClass] = (counter.install[weaponOrClass] or 0) + 1
            return nil
        end
        return original(weaponOrClass, method, ...)
    end
    return counter
end

---Runs body with the counting fixture and the host holding the given classes; afterwards the host's modifiers are
---removed, the classes it did not hold are stripped and the fixture is removed.
---@param classes string[]
---@param body fun(ply: Player, counter: PWT.StatModCounter, weps: Weapon[])
local function withHost(classes, body)
    local ply = host()
    ---@type table<string, boolean>
    local held = {}
    for _, class in ipairs(classes) do
        held[class] = ply:HasWeapon(class)
    end
    local counter = countCalls()
    ---@type Weapon[]
    local weps = {}
    for _, class in ipairs(classes) do
        if not held[class] then ply:Give(class, true) end
        weps[#weps + 1] = must(ply:GetWeapon(class))
    end
    local ok, err = pcall(body, ply, counter, weps)
    counter.restore()
    lib().SetStatMods(ply, nil)
    for _, class in ipairs(classes) do
        if not held[class] then ply:StripWeapon(class) end
    end
    if not ok then error(err, 0) end
end

return {
    groupName = "PW weapon stat mods",
    cases = {
        {
            name = "Normalize: absent keys are 1.0, unknown keys dropped, bad values become 1.0",
            func = function()
                local given = { reload_time = 0.8, recoil = 0, spread = -2, bogus = 5, ads_time = 1 / 0 }
                local full = lib()._Normalize(given)
                expect(full.reload_time).to.equal(0.8)
                expect(full.recoil).to.equal(1)
                expect(full.spread).to.equal(1)
                expect(full.ads_time).to.equal(1)
                expect(full.draw_time).to.equal(1)
                expect(full.bogus).to.beNil()
                for _, stat in ipairs(lib()._Keys) do
                    expect(lib()._Normalize(nil)[stat]).to.equal(1)
                end
            end
        },
        {
            name = "Revision: counts up and wraps before the 32-bit limit",
            func = function()
                expect(lib()._NextRevision(0)).to.equal(1)
                expect(lib()._NextRevision(41)).to.equal(42)
                expect(lib()._NextRevision(2 ^ 30)).to.equal(1)
            end
        },
        {
            name = "Sweep: a weapon under revision 0 needs nothing, a changed revision refreshes it once",
            func = function()
                ---@type table<any, PW.StatModSeen>
                local seen = {}
                local owner, wepA, wepB = {}, {}, {}
                expect(lib()._Sweep(seen, owner, 0, { wepA })).to.beNil()
                local work = must(lib()._Sweep(seen, owner, 1, { wepA, wepB }))
                expect(#work).to.equal(2)
                expect(work[1].install).to.beTrue()
                expect(lib()._Sweep(seen, owner, 1, { wepA, wepB })).to.beNil()
                local again = must(lib()._Sweep(seen, owner, 2, { wepA }))
                expect(#again).to.equal(1)
                expect(again[1].install).to.beFalse()
            end
        },
        {
            name = "Sweep: a weapon that changed owner is refreshed again under the same revision",
            func = function()
                ---@type table<any, PW.StatModSeen>
                local seen = {}
                local first, second, wep = {}, {}, {}
                expect(#must(lib()._Sweep(seen, first, 3, { wep }))).to.equal(1)
                expect(#must(lib()._Sweep(seen, second, 3, { wep }))).to.equal(1)
                expect(lib()._Sweep(seen, second, 3, { wep })).to.beNil()
            end
        },
        {
            name = "SetStatMods: writes the NW2 values and bumps the revision once",
            func = function()
                withHost({}, function(ply)
                    local before = revisionOf(ply)
                    PW.SetStatMods(ply, { reload_time = 0.75, recoil = 0.5 })
                    expect(revisionOf(ply)).to.equal(lib()._NextRevision(before))
                    expect(ply:GetNW2Float(lib()._Key("reload_time"), -1)).to.equal(0.75)
                    expect(ply:GetNW2Float(lib()._Key("recoil"), -1)).to.equal(0.5)
                    expect(ply:GetNW2Float(lib()._Key("spread"), -1)).to.equal(1)
                    expect(PW.GetStatMod(ply, "reload_time")).to.equal(0.75)
                    expect(PW.GetStatMod(ply, "draw_time")).to.equal(1)
                    PW.SetStatMods(ply, { reload_time = 0.5 })
                    expect(revisionOf(ply)).to.equal(lib()._NextRevision(lib()._NextRevision(before)))
                end)
            end
        },
        {
            name = "GetStatMod: 1 for an invalid entity, a non-player and an unknown key",
            func = function()
                expect(PW.GetStatMod(nil, "reload_time")).to.equal(1)
                expect(PW.GetStatMod(NULL --[[@as Player]], "reload_time")).to.equal(1)
                expect(PW.GetStatMod(game.GetWorld() --[[@as Player]], "reload_time")).to.equal(1)
                expect(PW.GetStatMod(host(), "no_such_stat")).to.equal(1)
            end
        },
        {
            name = "Refresh: called once per revision per weapon, install once per weapon",
            func = function()
                withHost({ "weapon_smg1", "weapon_pistol" }, function(ply, counter, weps)
                    -- A weapon given under a revision left by an earlier case is refreshed on the first tick;
                    -- the counts below are relative to the state after it.
                    lib()._Tick()
                    ---@type table<Weapon, integer>
                    local base = {}
                    for _, wep in ipairs(weps) do
                        base[wep] = counter.refresh[wep] or 0
                    end
                    PW.SetStatMods(ply, { reload_time = 0.8 })
                    for _ = 1, 5 do lib()._Tick() end
                    for _, wep in ipairs(weps) do
                        expect(counter.refresh[wep]).to.equal(base[wep] + 1)
                        expect(counter.install[wep]).to.equal(1)
                    end
                    PW.SetStatMods(ply, { reload_time = 0.6 })
                    for _ = 1, 5 do lib()._Tick() end
                    for _, wep in ipairs(weps) do
                        expect(counter.refresh[wep]).to.equal(base[wep] + 2)
                        expect(counter.install[wep]).to.equal(1)
                    end
                end)
            end
        },
        {
            name = "Refresh: the Think hook runs the loop",
            async = true,
            timeout = 5,
            func = function()
                local ply = host()
                local counter = countCalls()
                local held = ply:HasWeapon("weapon_smg1")
                if not held then ply:Give("weapon_smg1", true) end
                local wep = must(ply:GetWeapon("weapon_smg1"))
                PW.SetStatMods(ply, { draw_time = 0.5 })
                timer.Simple(0.3, function()
                    counter.restore()
                    PW.SetStatMods(ply, nil)
                    if not held then ply:StripWeapon("weapon_smg1") end
                    local calls = counter.refresh[wep]
                    expect(calls).to.equal(1)
                    done()
                end)
            end
        },
        {
            name = "Removal: SetStatMods with nil or {} resets every stat to 1.0 and bumps the revision",
            func = function()
                withHost({ "weapon_smg1" }, function(ply, counter, weps)
                    PW.SetStatMods(ply, { reload_time = 0.5, draw_time = 0.5, ads_time = 0.5, sprint_to_fire = 0.5,
                        recoil = 0.5, spread = 0.5 })
                    lib()._Tick()
                    local before = revisionOf(ply)
                    PW.SetStatMods(ply, {})
                    expect(revisionOf(ply)).to.equal(lib()._NextRevision(before))
                    for _, stat in ipairs(lib()._Keys) do
                        expect(PW.GetStatMod(ply, stat)).to.equal(1)
                    end
                    lib()._Tick()
                    expect(counter.refresh[weps[1]]).to.equal(2)
                    PW.SetStatMods(ply, { recoil = 0.5 })
                    PW.SetStatMods(ply, nil)
                    for _, stat in ipairs(lib()._Keys) do
                        expect(PW.GetStatMod(ply, stat)).to.equal(1)
                    end
                end)
            end
        },
        {
            name = "Cost: one tick over every player stays far below a millisecond",
            func = function()
                withHost({ "weapon_smg1", "weapon_pistol" }, function(ply)
                    local runs = 2000
                    local start = SysTime()
                    for _ = 1, runs do lib()._Tick() end
                    local idle = (SysTime() - start) / runs
                    PW.SetStatMods(ply, { reload_time = 0.8 })
                    lib()._Tick()
                    start = SysTime()
                    for _ = 1, runs do lib()._Tick() end
                    local swept = (SysTime() - start) / runs
                    print(string.format("[PW statmods cost] idle %.2f us, swept %.2f us per tick (1 player, 2 weapons)",
                        idle * 1e6, swept * 1e6))
                    expect(idle < 0.001).to.beTrue()
                    expect(swept < 0.001).to.beTrue()
                end)
            end
        }
    }
}
