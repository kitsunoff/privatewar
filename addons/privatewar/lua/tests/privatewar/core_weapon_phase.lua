-- T-1.17 weapon registration phase (TASKS.md, "Mandatory test cases" T-1.17; 04-weapons.md d.3;
-- 01-extensibility.md d.16 step 7, d.12). The real phase already ran at InitPostEntity before the tests start, so
-- the ordering is tested by running PW.WeaponPhase._Run with listeners added through hook.Add, on a fresh store and
-- a fresh weapons registry; one case checks what the real run recorded on PW._WeaponPhase.
-- "SWEPs exist" is checked with weapon_fists: a Lua SWEP shipped with every GMod install (garrysmod/lua/weapons/),
-- registered by the engine after the gamemode loaded. HL2 weapons (weapon_crowbar, weapon_physgun) are engine
-- weapons and never appear in weapons.GetStored.
-- Every case removes its listeners and restores PW._WeaponPhase; the Boot case boots once more afterwards, so the
-- test weapon it registered leaves the real weapons registry.

local listenerId = "PW_Test_WeaponPhase"
local stockSwep = "weapon_fists"
local testClass = "pwt_weapon_phase"
local hookNames = { "PW_RegisterWeapons", "PW_WeaponsLoaded", "PW_RegistriesLoaded" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.WeaponPhaseLib
local function phase()
    return must(PW.WeaponPhase)
end

---A store whose log lines land in lines.
---@param lines string[]
---@return PW.WeaponPhaseStore
local function newStore(lines)
    return phase()._NewStore({ log = function(message) lines[#lines + 1] = message end })
end

---A resolved, empty weapons registry, like the one LoadRoot builds; declared entries are registered first.
---@param declared? table<string, table<string, any>>
---@return PW.Registry
local function newWeapons(declared)
    local registry = PW.Registry.New("weapons", { log = function() end })
    for id, tbl in pairs(declared or {}) do registry.Register(tbl, id) end
    registry.ResolveAll()
    return registry
end

---@param name string
---@param fn function
local function listen(name, fn)
    hook.Add(name, listenerId, fn)
end

local cases = {
    {
        name = "PW_RegisterWeapons runs after SWEPs exist, then PW_WeaponsLoaded; a weapon registered in the phase "
            .. "is visible to PW_WeaponsLoaded listeners",
        func = function()
            local store = newStore({})
            local registry = newWeapons()
            ---@type string[]
            local order = {}
            local swepAtRegister = false
            local passed = nil ---@type PW.Registry?
            local seen = nil ---@type PW.Entity?
            listen("PW_RegisterWeapons", function(reg)
                order[#order + 1] = "register"
                swepAtRegister = weapons.GetStored(stockSwep) ~= nil
                passed = reg
                reg.Register({ Category = "ar", Name = "Phase test" }, testClass)
            end)
            listen("PW_WeaponsLoaded", function()
                order[#order + 1] = "loaded"
                seen = registry.Get(testClass)
            end)

            expect(phase()._Run(store, { weapons = registry }, "test")).to.beTrue()

            expect(order).to.deepEqual({ "register", "loaded" })
            expect(swepAtRegister).to.beTrue()
            expect(passed).to.equal(registry)
            expect(must(seen).Name).to.equal("Phase test")
            expect(store.runs).to.equal(1)
            expect(must(store.last).reason).to.equal("test")
            expect(must(store.last).sweps > 0).to.beTrue()
        end
    },
    {
        name = "The real phase ran at InitPostEntity with SWEPs loaded, on the weapons kind",
        func = function()
            local store = PW._WeaponPhase
            expect(store.ready).to.beTrue()
            expect(store.runs >= 1).to.beTrue()
            local first = must(store.first)
            expect(first.reason).to.equal("InitPostEntity")
            expect(first.sweps > 0).to.beTrue()
            expect(weapons.GetStored(stockSwep)).to.exist()
            local kind = must(PW.Kinds.Get("weapons"))
            expect(kind.Folder).to.equal("weapons")
            expect(kind.Global).to.equal("WEAPON")
            expect(PW.Weapons).to.equal(PW.Registries.weapons)
        end
    },
    {
        name = "A soft registration in the phase fills only the fields a declared entry lacks",
        func = function()
            local registry = newWeapons({ [testClass] = { Name = "Declared", Category = "ar" } })
            local seen = nil ---@type PW.Entity?
            listen("PW_RegisterWeapons", function(reg)
                reg.Register({ Name = "Auto", Category = "smg", Unlock = 4 }, testClass, { soft = true })
            end)
            listen("PW_WeaponsLoaded", function() seen = registry.Get(testClass) end)

            expect(phase()._Run(newStore({}), { weapons = registry }, "test")).to.beTrue()

            local entity = must(seen)
            expect(entity.Name).to.equal("Declared")
            expect(entity.Category).to.equal("ar")
            expect(entity.Unlock).to.equal(4)
        end
    },
    {
        name = "An error in a PW_RegisterWeapons listener is logged and PW_WeaponsLoaded still fires",
        func = function()
            ---@type string[]
            local lines = {}
            local loaded = 0
            listen("PW_RegisterWeapons", function() error("listener broke") end)
            listen("PW_WeaponsLoaded", function() loaded = loaded + 1 end)

            expect(phase()._Run(newStore(lines), { weapons = newWeapons() }, "test")).to.beTrue()

            expect(loaded).to.equal(1)
            expect(#lines).to.equal(1)
            expect(string.find(lines[1], "listener broke", 1, true) ~= nil).to.beTrue()
        end
    },
    {
        name = "Without a weapons registry the phase fires nothing and logs one line",
        func = function()
            ---@type string[]
            local lines = {}
            local fired = 0
            listen("PW_RegisterWeapons", function() fired = fired + 1 end)
            listen("PW_WeaponsLoaded", function() fired = fired + 1 end)
            local store = newStore(lines)

            expect(phase()._Run(store, {}, "test")).to.beFalse()

            expect(fired).to.equal(0)
            expect(#lines).to.equal(1)
            expect(store.runs).to.equal(0)
        end
    },
    {
        name = "A Boot before InitPostEntity runs nothing; after it, the phase runs on the current registries",
        func = function(state)
            local store = newStore({})
            state.previousStore = PW._WeaponPhase
            PW._WeaponPhase = store
            local passed = nil ---@type PW.Registry?
            local fired = 0
            listen("PW_RegisterWeapons", function(reg)
                fired = fired + 1
                passed = reg
            end)

            phase()._OnBoot()
            expect(fired).to.equal(0)
            expect(store.runs).to.equal(0)

            store.ready = true
            phase()._OnBoot()
            expect(fired).to.equal(1)
            expect(passed).to.equal(PW.Registries.weapons)
            expect(must(store.last).reason).to.equal("reload")
        end
    },
    {
        name = "PW.Loader.Boot (pw_reload) re-runs the phase after PW_RegistriesLoaded on the new weapons registry",
        func = function(state)
            local store = PW._WeaponPhase
            local runs = store.runs
            ---@type string[]
            local order = {}
            local passed = nil ---@type PW.Registry?
            listen("PW_RegistriesLoaded", function() order[#order + 1] = "registries" end)
            listen("PW_RegisterWeapons", function(reg)
                order[#order + 1] = "register"
                passed = reg
                reg.Register({ Category = "ar" }, testClass)
            end)
            listen("PW_WeaponsLoaded", function() order[#order + 1] = "loaded" end)
            state.booted = true

            PW.Loader.Boot()

            expect(order).to.deepEqual({ "registries", "register", "loaded" })
            expect(passed).to.equal(PW.Registries.weapons)
            expect(PW.Weapons.Get(testClass)).to.exist()
            expect(store.runs).to.equal(runs + 1)
            expect(must(store.last).reason).to.equal("reload")
        end
    }
}

return {
    groupName = "PW weapon phase",
    beforeEach = function(state)
        state.previousStore = false
        state.booted = false
    end,
    afterEach = function(state)
        for _, name in ipairs(hookNames) do hook.Remove(name, listenerId) end
        local previous = state.previousStore --[[@as PW.WeaponPhaseStore|false]]
        if previous then PW._WeaponPhase = previous end
        if state.booted then PW.Loader.Boot() end
    end,
    cases = cases
}
