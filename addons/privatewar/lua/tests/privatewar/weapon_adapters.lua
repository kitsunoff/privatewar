-- T-3.1 weapon adapter lookup (TASKS.md, "Mandatory test cases" T-3.1; 04-weapons.md d.1; docs/api/adapter.md).
-- Pure cases over fixture adapters registered in fresh registries of the kind weapon_adapters; no bots, no real
-- adapters. Every case releases its registries; the cases that swap PW.WeaponAdapters / PW._WeaponAdapters restore
-- them in afterEach. Every case swaps PW._Call for a capturing logger, so the errors the cases provoke on purpose
-- never reach the console (scripts/deck/cp1.sh counts them as Lua errors); the cases assert on the captured line.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.AdaptersLib
local function adapters()
    return must(PW.Adapters)
end

---Plain-data fixture adapter table: claims the classes in `claims`; fields override.
---@param claims string[]
---@param fields? table<string, any>
---@return table<string, any>
local function fixture(claims, fields)
    local tbl = {
        IsAvailable = function() return true end,
        Claims = function(_, class) return table.HasValue(claims, class) end,
        ListWeapons = function() return {} end
    }
    for key, value in pairs(fields or {}) do tbl[key] = value end
    return tbl
end

---A resolved registry of the kind with the given adapters (id -> table).
---@param state table<string, any>
---@param entries table<string, table<string, any>>
---@return PW.Registry
local function registryOf(state, entries)
    local registry = PW.Registry.New("weapon_adapters", { log = function() end })
    for id, tbl in pairs(entries) do registry.Register(tbl, id) end
    registry.ResolveAll()
    local list = state.registries --[[@as PW.Registry[] ]]
    list[#list + 1] = registry
    return registry
end

---@return PW.AdapterStore
local function newStore()
    return adapters()._NewStore({ log = function() end })
end

---@param state table<string, any>
---@param entries table<string, table<string, any>>
---@param class string
---@return PW.Adapter?
local function pick(state, entries, class)
    return adapters()._Find(newStore(), registryOf(state, entries), class, nil)
end

---A fake weapon with the engine calls the defaults use.
---@param fields? table<string, any>
---@return table<string, any>
local function fakeWeapon(fields)
    local owner = { IsValid = function() return true end, KeyDown = function(_, key) return key == IN_ATTACK2 end }
    local wep = {
        IsValid = function() return true end,
        GetClass = function() return "pwt_fake_weapon" end,
        Clip1 = function() return 7 end,
        GetMaxClip1 = function() return 30 end,
        GetPrimaryAmmoType = function() return 4 end,
        GetNextPrimaryFire = function() return 0 end,
        GetOwner = function() return owner end,
        PrintName = "Fake",
        Primary = { Damage = 25, RPM = 600, ClipSize = 30, Automatic = true }
    }
    for key, value in pairs(fields or {}) do wep[key] = value end
    return wep
end

---Optional methods of the contract (adapter.md), each with the arguments the defaults test passes.
local optionalMethods = {
    "GetBaseStats", "GetLiveStats", "PreviewBuildStats", "GetIcon", "GetSlots", "GetOptions", "Validate", "Apply",
    "SetCustomizationLocked", "SuppressDefaultAmmo", "GetAmmoType", "IsReloading", "IsAiming", "GetClip",
    "CanFireNow", "PrepareForBot", "GetFireInfo", "GetRecoil", "GetInputRules", "BotAction", "IsHeadshot",
    "GetDisplayName", "InstallStatMods", "RefreshStatMods", "SupportedStatMods"
}

---Call of every optional method on a bare adapter (only the required methods) with a fake weapon.
---@param bare PW.Adapter
---@param wep table<string, any>
---@return table<string, any[]> results by method, as a packed list
local function callAll(bare, wep)
    local call = adapters().Call
    local build = { ["1"] = "a" }
    return {
        GetBaseStats = { call(bare, "GetBaseStats", "pwt_no_such_swep") },
        GetLiveStats = { call(bare, "GetLiveStats", wep) },
        PreviewBuildStats = { call(bare, "PreviewBuildStats", "pwt_fake_weapon", build) },
        GetIcon = { call(bare, "GetIcon", "pwt_fake_weapon") },
        GetSlots = { call(bare, "GetSlots", "pwt_fake_weapon", nil) },
        GetOptions = { call(bare, "GetOptions", "pwt_fake_weapon", "1") },
        Validate = { call(bare, "Validate", "pwt_fake_weapon", build) },
        Apply = { call(bare, "Apply", wep, build) },
        SetCustomizationLocked = { call(bare, "SetCustomizationLocked", true) },
        SuppressDefaultAmmo = { call(bare, "SuppressDefaultAmmo", wep) },
        GetAmmoType = { call(bare, "GetAmmoType", wep) },
        IsReloading = { call(bare, "IsReloading", wep) },
        IsAiming = { call(bare, "IsAiming", wep) },
        GetClip = { call(bare, "GetClip", wep) },
        CanFireNow = { call(bare, "CanFireNow", wep) },
        PrepareForBot = { call(bare, "PrepareForBot", wep:GetOwner(), wep) },
        GetFireInfo = { call(bare, "GetFireInfo", wep) },
        GetRecoil = { call(bare, "GetRecoil", wep) },
        GetInputRules = { call(bare, "GetInputRules", wep) },
        BotAction = { call(bare, "BotAction", wep:GetOwner(), wep, "firemode", nil) },
        IsHeadshot = { call(bare, "IsHeadshot", nil) },
        GetDisplayName = { call(bare, "GetDisplayName", wep) },
        InstallStatMods = { call(bare, "InstallStatMods", wep) },
        RefreshStatMods = { call(bare, "RefreshStatMods", wep) },
        SupportedStatMods = { call(bare, "SupportedStatMods") }
    }
end

return {
    groupName = "PW weapon adapters",
    beforeEach = function(state)
        state.registries = {}
        state.realRegistry = rawget(PW, "WeaponAdapters")
        state.realStore = PW._WeaponAdapters
        state.previousCall = PW._Call
        ---@type string[]
        local logged = {}
        state.logged = logged
        PW._Call = {
            log = function(message) logged[#logged + 1] = message end,
            failed = setmetatable({}, { __mode = "k" }),
            profile = {}
        }
    end,
    afterEach = function(state)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        PW.WeaponAdapters = state.realRegistry
        PW._WeaponAdapters = state.realStore
        PW._Call = state.previousCall
    end,
    cases = {
        {
            name = "Lookup: the highest Priority among the adapters that claim the class wins",
            func = function(state)
                local won = pick(state, {
                    low = fixture({ "pwt_gun" }, { Priority = 10 }),
                    high = fixture({ "pwt_gun" }, { Priority = 100 }),
                    mid = fixture({ "pwt_gun" }, { Priority = 50 }),
                    loud = fixture({ "pwt_other" }, { Priority = 999 })
                }, "pwt_gun")
                expect(must(won).ClassName).to.equal("high")
            end
        },
        {
            name = "Lookup: an adapter that does not claim the class never wins, a class nobody claims gives nil",
            func = function(state)
                local entries = { only = fixture({ "pwt_gun" }) }
                expect(must(pick(state, entries, "pwt_gun")).ClassName).to.equal("only")
                expect(pick(state, entries, "pwt_unclaimed")).to.beNil()
            end
        },
        {
            name = "Lookup: Claims gets the class and the SWEP table",
            func = function(state)
                local seen = nil ---@type table?
                local swep = { PrintName = "x" }
                local registry = registryOf(state, {
                    spy = fixture({}, { Claims = function(_, class, tbl) seen = { class, tbl }; return true end })
                })
                adapters()._Find(newStore(), registry, "pwt_gun", swep)
                expect(must(seen)[1]).to.equal("pwt_gun")
                expect(must(seen)[2]).to.equal(swep)
            end
        },
        {
            name = "Lookup: adapters with IsAvailable() == false are skipped, even with the highest Priority",
            func = function(state)
                local entries = {
                    missing = fixture({ "pwt_gun" }, { Priority = 100, IsAvailable = function() return false end }),
                    present = fixture({ "pwt_gun" }, { Priority = 1 })
                }
                expect(must(pick(state, entries, "pwt_gun")).ClassName).to.equal("present")
                entries.present = nil
                expect(pick(state, entries, "pwt_gun")).to.beNil()
            end
        },
        {
            name = "Lookup: a missing IsAvailable counts as available and a missing Priority as 0",
            func = function()
                local list = {
                    { ClassName = "a", Claims = function() return true end },
                    { ClassName = "b", Priority = -1, Claims = function() return true end }
                } --[[@as any]]
                expect(must(adapters()._Pick(list, "pwt_gun", nil)).ClassName).to.equal("a")
            end
        },
        {
            name = "Lookup: equal Priority resolves to the lowest id, whatever the order of the list",
            func = function(state)
                local entries = {
                    zeta = fixture({ "pwt_gun" }, { Priority = 5 }),
                    alpha = fixture({ "pwt_gun" }, { Priority = 5 }),
                    mike = fixture({ "pwt_gun" }, { Priority = 5 })
                }
                expect(must(pick(state, entries, "pwt_gun")).ClassName).to.equal("alpha")
                local registry = registryOf(state, entries)
                local list = registry.GetEnabledList() --[[@as PW.Adapter[] ]]
                local reversed = { list[3], list[2], list[1] }
                expect(must(adapters()._Pick(reversed, "pwt_gun", nil)).ClassName).to.equal("alpha")
            end
        },
        {
            name = "Lookup: a disabled adapter is not a candidate",
            func = function(state)
                local registry = registryOf(state, {
                    off = fixture({ "pwt_gun" }, { Priority = 100 }),
                    on = fixture({ "pwt_gun" }, { Priority = 1 })
                })
                registry._Disable("off", "test")
                expect(must(adapters()._Find(newStore(), registry, "pwt_gun", nil)).ClassName).to.equal("on")
            end
        },
        {
            name = "Lookup: an adapter that fails in Claims is disabled and loses the lookup",
            func = function(state)
                local registry = registryOf(state, {
                    broken = fixture({}, { Priority = 100, Claims = function() error("boom") end }),
                    sound = fixture({ "pwt_gun" }, { Priority = 1 })
                })
                local won = adapters()._Find(newStore(), registry, "pwt_gun", nil)
                expect(must(won).ClassName).to.equal("sound")
                expect(registry._DisabledReason("broken")).to.exist()
                expect(#state.logged).to.equal(1)
                local line = state.logged[1] or ""
                expect(string.find(line, "\"broken\": Claims failed", 1, true)).to.exist()
                expect(string.find(line, "boom", 1, true)).to.exist()
            end
        },
        {
            name = "Cache: a class is resolved once; Invalidate and a new registry resolve again",
            func = function(state)
                local calls = 0
                local entries = {
                    one = fixture({}, { Claims = function() calls = calls + 1; return true end })
                }
                local registry = registryOf(state, entries)
                local store = newStore()
                adapters()._Find(store, registry, "pwt_gun", nil)
                adapters()._Find(store, registry, "pwt_gun", nil)
                expect(calls).to.equal(1)
                store.cache = {}
                adapters()._Find(store, registry, "pwt_gun", nil)
                expect(calls).to.equal(2)
                adapters()._Find(store, registryOf(state, entries), "pwt_gun", nil)
                expect(calls).to.equal(3)
            end
        },
        {
            name = "Cache: a cached adapter that became invalid is dropped, a cached miss stays a miss",
            func = function(state)
                local registry = registryOf(state, {
                    first = fixture({ "pwt_gun" }, { Priority = 9 }),
                    second = fixture({ "pwt_gun" }, { Priority = 1 })
                })
                local store = newStore()
                expect(must(adapters()._Find(store, registry, "pwt_gun", nil)).ClassName).to.equal("first")
                registry._Disable("first", "test")
                expect(must(adapters()._Find(store, registry, "pwt_gun", nil)).ClassName).to.equal("second")
                expect(adapters()._Find(store, registry, "pwt_none", nil)).to.beNil()
                expect(store.cache["pwt_none"]).to.equal(false)
            end
        },
        {
            name = "PW.Adapters.For: reads PW.WeaponAdapters, takes a class or a weapon, Invalidate flushes the cache",
            func = function(state)
                PW._WeaponAdapters = newStore()
                PW.WeaponAdapters = registryOf(state, { one = fixture({ "pwt_gun" }) })
                expect(must(adapters().For("pwt_gun")).ClassName).to.equal("one")
                expect(must(adapters().For(fakeWeapon({ GetClass = function() return "pwt_gun" end }) --[[@as Weapon]]))
                    .ClassName).to.equal("one")
                expect(adapters().For("pwt_unclaimed")).to.beNil()
                local nothing ---@type any
                expect(adapters().For(nothing)).to.beNil()
                PW.WeaponAdapters = registryOf(state, { two = fixture({ "pwt_gun" }) })
                expect(must(adapters().For("pwt_gun")).ClassName).to.equal("two")
                adapters().Invalidate()
                expect(PW._WeaponAdapters.cache["pwt_gun"]).to.beNil()
            end
        },
        {
            name = "Defaults: every optional method of the contract has a working default",
            func = function(state)
                for _, name in ipairs(optionalMethods) do
                    expect(adapters().Defaults[name]).to.beA("function")
                end
                local bare = must(pick(state, { bare = fixture({ "pwt_gun" }) }, "pwt_gun"))
                local wep = fakeWeapon()
                PW._WeaponAdapters = newStore()
                local results = callAll(bare, wep)
                for _, name in ipairs(optionalMethods) do
                    expect(results[name]).to.exist()
                end
                expect(results.GetBaseStats[1]).to.deepEqual({})
                expect(results.GetLiveStats[1]).to.deepEqual({})
                expect(results.PreviewBuildStats[1]).to.beNil()
                expect(results.GetSlots[1]).to.deepEqual({})
                expect(results.GetOptions[1]).to.deepEqual({})
                expect(results.Apply[1]).to.deepEqual({})
                expect(results.GetAmmoType[1]).to.equal(4)
                expect(results.IsReloading[1]).to.beFalse()
                expect(results.BotAction[1]).to.beFalse()
                expect(results.IsHeadshot[1]).to.beNil()
                expect(results.SupportedStatMods[1]).to.deepEqual({})
            end
        },
        {
            name = "Defaults: Validate is the identity; the state methods read the weapon",
            func = function(state)
                local bare = must(pick(state, { bare = fixture({ "pwt_gun" }) }, "pwt_gun"))
                local wep = fakeWeapon()
                local results = callAll(bare, wep)
                local build = { ["1"] = "a" }
                expect(results.Validate[1]).to.deepEqual(build)
                expect(results.Validate[2]).to.deepEqual({})
                expect(results.IsAiming[1]).to.beTrue()
                expect(results.GetClip).to.deepEqual({ 7, 30 })
                expect(results.CanFireNow[1]).to.beTrue()
                expect(results.GetDisplayName[1]).to.beA("string")
                local empty = fakeWeapon({ Clip1 = function() return 0 end })
                expect(adapters().Call(bare, "CanFireNow", empty)).to.beFalse()
                local late = fakeWeapon({ GetNextPrimaryFire = function() return CurTime() + 100 end })
                expect(adapters().Call(bare, "CanFireNow", late)).to.beFalse()
                local noClip = fakeWeapon({ Clip1 = function() return -1 end })
                expect(adapters().Call(bare, "CanFireNow", noClip)).to.beTrue()
                local ownerless = fakeWeapon({ GetOwner = function() return nil end })
                expect(adapters().Call(bare, "IsAiming", ownerless)).to.beFalse()
            end
        },
        {
            name = "Defaults: GetFireInfo, GetRecoil and GetInputRules return valid PW types",
            func = function(state)
                local bare = must(pick(state, { bare = fixture({ "pwt_gun" }) }, "pwt_gun"))
                local auto = adapters().Call(bare, "GetFireInfo", fakeWeapon()) --[[@as PW.FireInfo]]
                expect(auto.kind).to.equal("auto")
                expect(auto.burst).to.equal(1)
                expect(auto.rpm).to.equal(600)
                expect(auto.adsKey).to.equal(IN_ATTACK2)
                local semi = adapters().Call(bare, "GetFireInfo",
                    fakeWeapon({ Primary = { Automatic = false, Delay = 0.5 } })) --[[@as PW.FireInfo]]
                expect(semi.kind).to.equal("semi")
                expect(semi.rpm).to.equal(120)
                local noPrimary = fakeWeapon({ Primary = false })
                local fallback = adapters().Call(bare, "GetFireInfo", noPrimary) --[[@as PW.FireInfo]]
                expect(fallback.rpm).to.equal(600)
                expect(adapters().Call(bare, "GetRecoil", fakeWeapon())).to.deepEqual(
                    { pitch = 0, yaw = 0, affectsBotAim = false })
                local rules = adapters().Call(bare, "GetInputRules", fakeWeapon()) --[[@as PW.InputRules]]
                expect(rules.releaseBetweenShots).to.beTrue()
                expect(rules.reloadTap).to.beFalse()
                expect(rules.forbidWithAttack).to.equal(IN_USE)
                expect(rules.forbidWithReload).to.equal(IN_USE)
                expect(rules.noSprintWhileFiring).to.beTrue()
                expect(rules.reselectEveryTick).to.beTrue()
                expect(rules.reloadTapMax).to.beA("number")
                expect(rules.sprintToFire).to.beA("number")
            end
        },
        {
            name = "Defaults: stats come from the Primary table; missing or non-positive values stay nil",
            func = function()
                local stats = adapters()._StatsFromPrimary({ Damage = 25, RPM = 600, ClipSize = 30, NumShots = 8 })
                expect(stats).to.deepEqual({ damageNear = 25, damageFar = 25, rpm = 600, magazine = 30, pellets = 8 })
                expect(adapters()._StatsFromPrimary({ Damage = 0, ClipSize = -1 })).to.deepEqual({})
                expect(adapters()._StatsFromPrimary(nil)).to.deepEqual({})
            end
        },
        {
            name = "Defaults: SetCustomizationLocked logs once per adapter",
            func = function(state)
                local bare = must(pick(state, { bare = fixture({ "pwt_gun" }) }, "pwt_gun"))
                local lines = {} ---@type string[]
                PW._WeaponAdapters = adapters()._NewStore({ log = function(line) lines[#lines + 1] = line end })
                adapters().Call(bare, "SetCustomizationLocked", true)
                adapters().Call(bare, "SetCustomizationLocked", true)
                expect(#lines).to.equal(1)
            end
        },
        {
            name = "Call: an own method wins over the default and returns all its results",
            func = function(state)
                local bare = must(pick(state, {
                    own = fixture({ "pwt_gun" }, { GetClip = function() return 1, 2 end })
                }, "pwt_gun"))
                expect({ adapters().Call(bare, "GetClip", fakeWeapon()) }).to.deepEqual({ 1, 2 })
            end
        },
        {
            name = "Call: an own method that fails disables the adapter and the call answers with the default",
            func = function(state)
                local registry = registryOf(state, {
                    shaky = fixture({ "pwt_gun" }, { IsReloading = function() error("boom") end })
                })
                local shaky = must(adapters()._Find(newStore(), registry, "pwt_gun", nil))
                expect(adapters().Call(shaky, "IsReloading", fakeWeapon())).to.beFalse()
                expect(registry._DisabledReason("shaky")).to.exist()
                expect(#state.logged).to.equal(1)
                local line = state.logged[1] or ""
                expect(string.find(line, "\"shaky\": IsReloading failed", 1, true)).to.exist()
                expect(string.find(line, "boom", 1, true)).to.exist()
            end
        },
        {
            name = "Call: an own method that returns nothing is not replaced by the default",
            func = function(state)
                local bare = must(pick(state, {
                    quiet = fixture({ "pwt_gun" }, { GetAmmoType = function() return nil end })
                }, "pwt_gun"))
                expect(adapters().Call(bare, "GetAmmoType", fakeWeapon())).to.beNil()
            end
        },
        {
            name = "Call: an unknown method gives nil",
            func = function(state)
                local bare = must(pick(state, { bare = fixture({ "pwt_gun" }) }, "pwt_gun"))
                expect(adapters().Call(bare, "NoSuchMethod")).to.beNil()
            end
        },
        {
            name = "CallFor: a class nobody claims is answered by the defaults",
            func = function(state)
                PW._WeaponAdapters = newStore()
                PW.WeaponAdapters = registryOf(state, {})
                expect(adapters().CallFor("pwt_unclaimed", "IsReloading", fakeWeapon())).to.beFalse()
            end
        }
    }
}
