-- T-1.9 PW.Instance (TASKS.md, "Mandatory test cases"; 00-core.md d.3, d.11; 01-extensibility.md d.15, d.18).
-- Every case swaps in a fresh instance store, call store and hook store (capturing loggers) and restores them
-- afterwards, after removing every instance the case created and every listener of the PW_TestInstance* hooks.

local testHooks = { "PW_TestInstanceA", "PW_TestInstanceB", "PW_TestInstanceBoom" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return ConVar
local function debugVar()
    return must(GetConVar("pw_debug"))
end

---True when the hook table holds a listener of the hook under this identifier.
---@param name string
---@param identifier any
---@return boolean
local function isSubscribed(name, identifier)
    local listeners = hook.GetTable()[name] --[[@as table<any, function>?]]
    return listeners ~= nil and listeners[identifier] ~= nil
end

---Names of the instance's timers.
---@param instance PW.Instance
---@return string[]
local function timerNames(instance)
    ---@type string[]
    local names = {}
    for name in pairs(instance._Timers) do names[#names + 1] = name end
    return names
end

---True when no hook in testHooks and no timer of the instance remains.
---@param instance PW.Instance
---@return boolean
local function leftNothing(instance)
    for _, name in ipairs(testHooks) do
        if isSubscribed(name, instance) then return false end
    end
    for _, name in ipairs(timerNames(instance)) do
        if timer.Exists(name) then return false end
    end
    return true
end

---A definition that counts OnEquip/OnUnequip calls and records their owners.
---@return table<string, any>
local function countingDef()
    local def = { ClassName = "counting", equips = {}, unequips = {} }
    function def:OnEquip(owner)
        local equips = def.equips --[[@as any[] ]]
        equips[#equips + 1] = owner
        self.equipSelf = self
    end
    function def:OnUnequip(owner)
        local unequips = def.unequips --[[@as any[] ]]
        unequips[#unequips + 1] = owner
    end
    return def
end

return {
    groupName = "PW.Instance",
    beforeEach = function(state)
        state.previousInstances = PW._Instances
        state.previousCall = PW._Call
        state.previousHooks = PW._Hooks
        state.previousMode = PW.ActiveMode
        state.previousDebug = debugVar():GetString()
        state.registries = {}
        ---@type string[]
        local logged = {}
        state.logged = logged
        ---@type string[]
        local warnings = {}
        state.warnings = warnings
        PW._Instances = { live = {}, count = 0 }
        PW._Call = {
            log = function(message) logged[#logged + 1] = message end,
            failed = setmetatable({}, { __mode = "k" }),
            profile = {}
        }
        PW._Hooks = { log = function(message) warnings[#warnings + 1] = message end }
        PW.ActiveMode = nil
    end,
    afterEach = function(state)
        ---@type PW.Instance[]
        local live = {}
        for instance in pairs(PW._Instances.live) do live[#live + 1] = instance end
        for _, instance in ipairs(live) do instance:Remove() end
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        for _, name in ipairs(testHooks) do
            for identifier in pairs(hook.GetTable()[name] or {}) do hook.Remove(name, identifier) end
        end
        PW._Instances = state.previousInstances
        PW._Call = state.previousCall
        PW._Hooks = state.previousHooks
        PW.ActiveMode = state.previousMode
        debugVar():SetString(state.previousDebug)
    end,
    cases = {
        {
            name = "An instance inherits its definition, keeps per-owner state and gets OnEquip(owner)",
            func = function()
                local def = countingDef()
                local first = PW.Instance(def, "alice")
                local second = PW.Instance(def, "bob")
                expect(first.ClassName).to.equal("counting")
                expect(first._Owner).to.equal("alice")
                expect(first.equipSelf).to.equal(first)
                expect(second.equipSelf).to.equal(second)
                expect(rawget(def, "equipSelf")).to.beNil()
                expect(#def.equips).to.equal(2)
                expect(def.equips[1]).to.equal("alice")
                expect(def.equips[2]).to.equal("bob")
                expect(first:IsValid()).to.beTrue()
            end
        },
        {
            name = "self:Hook and self:Timer work while valid",
            async = true,
            timeout = 3,
            func = function()
                local def = { ClassName = "worker" }
                function def:OnEquip(owner)
                    self:Hook("PW_TestInstanceA", function(me, value)
                        me.seen = { me = me, value = value, owner = owner }
                        return value * 2
                    end)
                    self:Timer(0.05, 2, function(me)
                        me.ticks = (me.ticks or 0) + 1
                    end)
                end
                local instance = PW.Instance(def, "alice")
                expect(isSubscribed("PW_TestInstanceA", instance)).to.beTrue()
                expect(#timerNames(instance)).to.equal(1)
                expect(timer.Exists(must(timerNames(instance)[1]))).to.beTrue()

                expect(hook.Run("PW_TestInstanceA", 21)).to.equal(42)
                local seen = must(instance.seen)
                expect(seen.me).to.equal(instance)
                expect(seen.value).to.equal(21)
                expect(seen.owner).to.equal("alice")

                timer.Simple(0.5, function()
                    expect(instance.ticks).to.equal(2)
                    expect(instance:IsValid()).to.beTrue()
                    done()
                end)
            end
        },
        {
            name = "After Remove() no hook or timer of the instance remains",
            func = function()
                local def = { ClassName = "leaky" }
                function def:OnEquip()
                    self:Hook("PW_TestInstanceA", function() end)
                    self:Hook("PW_TestInstanceB", function() end)
                    self:Timer(10, 0, function() end)
                    self:Timer(20, 1, function() end)
                end
                local instance = PW.Instance(def, "alice")
                local other = PW.Instance(def, "bob")
                expect(isSubscribed("PW_TestInstanceA", instance)).to.beTrue()
                expect(isSubscribed("PW_TestInstanceB", instance)).to.beTrue()
                local names = timerNames(instance)
                expect(#names).to.equal(2)
                for _, name in ipairs(names) do expect(timer.Exists(name)).to.beTrue() end

                instance:Remove()
                expect(instance:IsValid()).to.beFalse()
                expect(leftNothing(instance)).to.beTrue()
                expect(PW._Instances.live[instance]).to.beNil()

                -- Hooks and timers requested after the end are not created.
                instance:Hook("PW_TestInstanceA", function() end)
                instance:Timer(10, 0, function() end)
                expect(leftNothing(instance)).to.beTrue()

                -- Another instance of the same definition is untouched.
                expect(other:IsValid()).to.beTrue()
                expect(isSubscribed("PW_TestInstanceA", other)).to.beTrue()
                expect(timer.Exists(must(timerNames(other)[1]))).to.beTrue()
            end
        },
        {
            name = "A removed instance's timer callback never runs",
            async = true,
            timeout = 3,
            func = function()
                local ticks = 0
                local def = { ClassName = "stopped" }
                function def:OnEquip()
                    self:Timer(0.05, 0, function() ticks = ticks + 1 end)
                end
                local instance = PW.Instance(def, "alice")
                instance:Remove()
                timer.Simple(0.3, function()
                    expect(ticks).to.equal(0)
                    done()
                end)
            end
        },
        {
            name = "OnUnequip is called exactly once",
            func = function()
                local def = countingDef()
                local instance = PW.Instance(def, "alice")
                instance:Remove()
                instance:Remove()
                PW.Notify("PW_MatchEnd")
                expect(#def.unequips).to.equal(1)
                expect(def.unequips[1]).to.equal("alice")
            end
        },
        {
            name = "OnUnequip calling Remove again does not recurse",
            func = function()
                local calls = 0
                local def = { ClassName = "reentrant" }
                function def:OnUnequip()
                    calls = calls + 1
                    self:Remove()
                end
                PW.Instance(def, "alice"):Remove()
                expect(calls).to.equal(1)
            end
        },
        {
            name = "All live instances end on PW_MatchEnd",
            func = function(state)
                debugVar():SetString("1")
                local perk = countingDef()
                local streak = countingDef()
                streak.ClassName = "streak"
                function streak:OnEquip()
                    self:Hook("PW_TestInstanceA", function() end)
                    self:Timer(10, 0, function() end)
                end
                local first = PW.Instance(perk, "alice")
                local second = PW.Instance(perk, "bob")
                local third = PW.Instance(streak, "carol")
                local early = PW.Instance(perk, "dave")
                early:Remove()

                PW.Notify("PW_MatchEnd")

                for _, instance in ipairs({ first, second, third, early }) do
                    expect(instance:IsValid()).to.beFalse()
                    expect(leftNothing(instance)).to.beTrue()
                end
                expect(#perk.unequips).to.equal(3)
                expect(#streak.unequips).to.equal(1)
                expect(next(PW._Instances.live)).to.beNil()
                -- The core listener is a notification listener: it returns no value.
                expect(#state.warnings).to.equal(0)
            end
        },
        {
            name = "An error inside an instance callback disables only that instance",
            func = function(state)
                local registry = PW.Registry.New("test_instance", {
                    log = function() end,
                    preRegister = function() end
                })
                local registries = state.registries --[[@as PW.Registry[] ]]
                registries[#registries + 1] = registry
                registry.Register({
                    OnEquip = function(self, owner)
                        self.calls = 0
                        self:Hook("PW_TestInstanceBoom", function(me)
                            me.calls = me.calls --[[@as integer]] + 1
                            if owner == "alice" then error("instance boom") end
                        end)
                        self:Timer(10, 0, function() end)
                    end
                }, "boomer")
                registry.ResolveAll()
                local def = must(registry.Get("boomer"))
                local broken = PW.Instance(def, "alice")
                local healthy = PW.Instance(def, "bob")

                expect(pcall(hook.Run, "PW_TestInstanceBoom")).to.beTrue()
                expect(pcall(hook.Run, "PW_TestInstanceBoom")).to.beTrue()

                expect(broken.calls).to.equal(1)
                expect(healthy.calls).to.equal(2)
                expect(broken:IsValid()).to.beFalse()
                expect(leftNothing(broken)).to.beTrue()
                expect(healthy:IsValid()).to.beTrue()
                expect(isSubscribed("PW_TestInstanceBoom", healthy)).to.beTrue()
                -- The definition stays enabled: only the instance is disabled.
                expect(must(def.IsValid)(def)).to.beTrue()
                expect(registry._DisabledReason("boomer")).to.beNil()
                expect(#state.logged).to.equal(1)
                local line = state.logged[1] or ""
                expect(string.find(line, "boomer", 1, true)).to.exist()
                expect(string.find(line, "instance boom", 1, true)).to.exist()

                -- A new instance of the same definition works.
                local fresh = PW.Instance(def, "carol")
                hook.Run("PW_TestInstanceBoom")
                expect(fresh.calls).to.equal(1)
            end
        },
        {
            name = "An error inside an instance timer disables only that instance",
            async = true,
            timeout = 3,
            func = function(state)
                local def = { ClassName = "ticker" }
                function def:OnEquip(owner)
                    self.ticks = 0
                    self:Timer(0.05, 0, function(me)
                        me.ticks = me.ticks --[[@as integer]] + 1
                        if owner == "alice" then error("timer boom") end
                    end)
                end
                local broken = PW.Instance(def, "alice")
                local healthy = PW.Instance(def, "bob")
                timer.Simple(0.5, function()
                    expect(broken.ticks).to.equal(1)
                    expect(broken:IsValid()).to.beFalse()
                    expect(leftNothing(broken)).to.beTrue()
                    expect(healthy.ticks > 1).to.beTrue()
                    expect(healthy:IsValid()).to.beTrue()
                    expect(#state.logged).to.equal(1)
                    done()
                end)
            end
        }
    }
}
