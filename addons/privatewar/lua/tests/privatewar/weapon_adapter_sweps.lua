-- T-3.2 fallback adapter (TASKS.md, "Mandatory test cases" T-3.2; 04-weapons.md d.1; docs/api/adapter.md
-- "Fallback adapter"). The adapter under test is the real entity weapon_adapters/sweps from the registry of the
-- kind; SWEPs are the always-present Lua SWEPs (weapon_fists, weapon_flechettegun) or plain-data fixtures.
-- No bots.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return table<string, any>
local function sweps()
    local registry = must(rawget(PW, "WeaponAdapters")) --[[@as PW.Registry]]
    return must(registry.Get("sweps")) --[[@as table<string, any>]]
end

---@param adapter table<string, any>
---@param class string
---@param swep table?
---@return boolean
local function claims(adapter, class, swep)
    return adapter.Claims(adapter, class, swep) and true or false
end

---Calls an adapter method straight (no PW.Call): fixtures take the adapter as the first argument.
---@type PW.AdapterCallFn
local function directCall(adapter, method, ...)
    return (adapter --[[@as any]])[method](adapter, ...)
end

---@param list PW.WeaponInfo[]
---@param class string
---@return boolean
local function listed(list, class)
    for _, info in ipairs(list) do
        if info.class == class then return true end
    end
    return false
end

return {
    groupName = "PW fallback adapter sweps",
    cases = {
        {
            name = "Fallback: is registered, available, with a Priority below the default 0",
            func = function()
                local adapter = sweps()
                expect(adapter.IsAvailable(adapter)).to.beTrue()
                expect(adapter.Priority < 0).to.beTrue()
            end
        },
        {
            name = "Fallback: claims a plain SWEP",
            func = function()
                local adapter = sweps()
                local stored = must(weapons.GetStored("weapon_fists"))
                expect(claims(adapter, "weapon_fists", stored)).to.beTrue()
                expect(claims(adapter, "pwt_fixture_swep", { Primary = { Damage = 3 } })).to.beTrue()
            end
        },
        {
            name = "Fallback: claims an HL2 engine weapon that has no SWEP table",
            func = function()
                local adapter = sweps()
                for _, class in ipairs({ "weapon_crowbar", "weapon_smg1", "weapon_ar2", "weapon_pistol" }) do
                    expect(claims(adapter, class, nil)).to.beTrue()
                end
            end
        },
        {
            name = "Fallback: does not claim an unknown class without a SWEP table",
            func = function()
                expect(claims(sweps(), "pwt_no_such_class", nil)).to.beFalse()
            end
        },
        {
            name = "Fallback: stats defaults come from Primary.*",
            func = function()
                local adapter = sweps()
                local stored = must(weapons.GetStored("weapon_flechettegun")) --[[@as table<string, any>]]
                local stats = PW.Adapters.Call(adapter --[[@as PW.Adapter]], "GetBaseStats", "weapon_flechettegun")
                expect(stats).to.deepEqual(PW.Adapters._StatsFromPrimary(stored.Primary --[[@as table]]))
            end
        },
        {
            name = "Fallback: stats of a fixture SWEP read Damage, RPM and ClipSize",
            func = function()
                local adapter = sweps()
                local stats = adapter._StatsOf(adapter, "pwt_fixture", {
                    Primary = { Damage = 25, RPM = 600, ClipSize = 30 }
                }) --[[@as PW.Stats]]
                expect(stats.damageNear).to.equal(25)
                expect(stats.damageFar).to.equal(25)
                expect(stats.rpm).to.equal(600)
                expect(stats.magazine).to.equal(30)
            end
        },
        {
            name = "Fallback: an HL2 weapon gets fixed stats",
            func = function()
                local adapter = sweps()
                local smg = adapter.GetBaseStats(adapter, "weapon_smg1") --[[@as PW.Stats]]
                expect(smg.damageNear > 0).to.beTrue()
                expect(smg.magazine).to.equal(45)
                expect(adapter.GetBaseStats(adapter, "weapon_shotgun").pellets).to.equal(7)
                expect(adapter.GetBaseStats(adapter, "pwt_no_such_class")).to.deepEqual({})
            end
        },
        {
            name = "Fallback: a higher-priority adapter beats it for the same class",
            func = function()
                local fallback = sweps()
                local better = { ClassName = "pwt_better", Priority = 0, Claims = function() return true end }
                local swep = must(weapons.GetStored("weapon_fists"))
                local both = { fallback, better } --[[@as PW.Adapter[] ]]
                local won = must(PW.Adapters._Pick(both, "weapon_fists", swep, directCall))
                expect(won.ClassName).to.equal("pwt_better")
                local reversed = { better, fallback } --[[@as PW.Adapter[] ]]
                won = must(PW.Adapters._Pick(reversed, "weapon_fists", swep, directCall))
                expect(won.ClassName).to.equal("pwt_better")
                local alone = { fallback } --[[@as PW.Adapter[] ]]
                won = must(PW.Adapters._Pick(alone, "weapon_fists", swep, directCall))
                expect(won.ClassName).to.equal("sweps")
            end
        },
        {
            name = "ListWeapons: excludes base, abstract, non-spawnable and admin-only SWEPs",
            func = function()
                local adapter = sweps()
                local list = adapter._ListFrom(adapter, {
                    { ClassName = "pwt_good", Spawnable = true, Base = "weapon_base", Primary = { Damage = 5 } },
                    { ClassName = "weapon_base", Spawnable = true },
                    { ClassName = "pwt_mybase_base", Spawnable = true },
                    { ClassName = "pwt_parent", Spawnable = true },
                    { ClassName = "pwt_child", Spawnable = true, Base = "pwt_parent" },
                    { ClassName = "pwt_hidden", Spawnable = false },
                    { ClassName = "pwt_admin", Spawnable = true, AdminOnly = true }
                }) --[[@as PW.WeaponInfo[] ]]
                expect(listed(list, "pwt_good")).to.beTrue()
                expect(listed(list, "pwt_child")).to.beTrue()
                local excludedClasses = { "weapon_base", "pwt_mybase_base", "pwt_parent", "pwt_hidden", "pwt_admin" }
                for _, excluded in ipairs(excludedClasses) do
                    expect(listed(list, excluded)).to.beFalse()
                end
            end
        },
        {
            name = "ListWeapons: the live list holds the HL2 weapons, valid entries and no base",
            func = function()
                local adapter = sweps()
                local list = adapter.ListWeapons(adapter) --[[@as PW.WeaponInfo[] ]]
                expect(listed(list, "weapon_smg1")).to.beTrue()
                expect(listed(list, "weapon_crowbar")).to.beTrue()
                expect(listed(list, "weapon_base")).to.beFalse()
                for _, info in ipairs(list) do
                    expect(isstring(info.class) and isstring(info.name) and isstring(info.kind)).to.beTrue()
                    expect(info.slot >= 1 and info.slot <= 3).to.beTrue()
                end
            end
        }
    }
}
