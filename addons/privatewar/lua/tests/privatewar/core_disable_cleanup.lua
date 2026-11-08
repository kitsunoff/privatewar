-- Generic definition-disable lifecycle: notification ordering, exact identity and cleanup-only teardown.

local event = "PW_EntityDisabled"
local listener = "PW.TestDisableCleanup"
local workHook = "PW_TestDisableCleanupWork"

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@param name string
---@param identifier any
---@return boolean
local function subscribed(name, identifier)
    return (hook.GetTable()[name] or {})[identifier] ~= nil
end

---@param instance PW.Instance
---@return boolean
local function clean(instance)
    if PW._Instances.live[instance] ~= nil or subscribed(workHook, instance) then return false end
    for name in pairs(instance._Timers) do
        if timer.Exists(name) then return false end
    end
    return true
end

---@param state table<string, any>
---@param kind string
---@param definition? table<string, any>
---@return PW.Registry, PW.Entity
local function registered(state, kind, definition)
    local registry = PW.Registry.New(kind, { preRegister = function() end, subscribe = "always" })
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    registry.Register(definition or {}, "test_disable_owner")
    registry.ResolveAll()
    return registry, must(registry.Get("test_disable_owner"))
end

---@return table<string, any>
local function workingDefinition()
    return {
        OnEquip = function(self)
            self:Hook(workHook, function(me) me.work = (me.work or 0) + 1 end)
            self:Timer(60, 0, function(me) me.work = (me.work or 0) + 1 end)
        end,
        OnUnequip = function(self, owner)
            self.unequips = (self.unequips or 0) + 1
            self.cleanedOwner = owner
        end,
        Work = function(self) self.work = (self.work or 0) + 1 end
    }
end

return {
    groupName = "PW definition disable cleanup",
    beforeEach = function(state)
        state.instances = PW._Instances
        state.call = PW._Call
        state.mode = PW.ActiveMode
        state.registries = {}
        local logged = {} ---@type string[]
        state.logged = logged
        PW.ActiveMode = nil
        PW._Instances = { live = {}, count = 0 }
        PW._Call = { log = function(message) logged[#logged + 1] = message end,
            failed = setmetatable({}, { __mode = "k" }), profile = {} }
    end,
    afterEach = function(state)
        hook.Remove(event, listener)
        PW._EndInstances()
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        PW._Instances = state.instances
        PW._Call = state.call
        PW.ActiveMode = state.mode
    end,
    cases = {
        {
            name = "Module disable notifies once after invalidation and ordinary auto-unsubscription",
            func = function(state)
                local ownCalls = 0
                local registry, definition = registered(state, "modules", {
                    PW_EntityDisabled = function() ownCalls = ownCalls + 1 end,
                    PW_TestDisableCleanupWork = function() end
                })
                local seen = {} ---@type any[][]
                hook.Add(event, listener, function(kind, id, def, reason)
                    seen[#seen + 1] = { kind, id, def, reason }
                    expect(must(def.IsValid)(def)).to.beFalse()
                    expect(subscribed(workHook, def)).to.beFalse()
                    expect(subscribed(event, def)).to.beFalse()
                    expect(registry._DisabledReason(id)).to.equal(reason)
                end)
                registry._Disable(definition.ClassName, "test reason")
                registry._Disable(definition.ClassName, "test reason")
                expect(#seen).to.equal(1)
                expect(seen[1]).to.deepEqual({ "modules", definition.ClassName, definition, "test reason" })
                expect(ownCalls).to.equal(0)
            end
        },
        {
            name = "Content disable notifies once per disable and re-enable transition",
            func = function(state)
                local registry, definition = registered(state, "test_disable_content")
                local seen = 0
                hook.Add(event, listener, function(kind, id, def, reason)
                    expect(kind).to.equal("test_disable_content")
                    expect(id).to.equal(definition.ClassName)
                    expect(def).to.equal(definition)
                    expect(reason).to.equal("off")
                    seen = seen + 1
                end)
                registry._Disable(definition.ClassName, "off")
                registry._Disable(definition.ClassName, "off")
                registry._Enable(definition.ClassName)
                expect(must(definition.IsValid)(definition)).to.beTrue()
                registry._Disable(definition.ClassName, "off")
                expect(seen).to.equal(2)
            end
        },
        {
            name = "PW.Call error-disable uses the same synchronous cleanup notification path",
            func = function(state)
                local own = workingDefinition()
                own.Fail = function() error("disable callback failure") end
                local registry, definition = registered(state, "test_disable_content", own)
                local instance = PW.Instance(definition, "owner")
                local seen = 0
                hook.Add(event, listener, function(_, _, def, reason)
                    expect(def).to.equal(definition)
                    expect(string.find(reason, "error in Fail:", 1, true)).to.exist()
                    expect(instance.unequips).to.equal(1)
                    expect(clean(instance)).to.beTrue()
                    seen = seen + 1
                end)
                expect(pcall(PW.Call, definition, "Fail")).to.beTrue()
                PW.Call(definition, "Fail")
                expect(seen).to.equal(1)
                expect(#state.logged).to.equal(1)
                expect(registry._DisabledReason(definition.ClassName)).to.exist()
            end
        },
        {
            name = "Disable ends only instances of the exact resolved definition before observers",
            func = function(state)
                local registry, definition = registered(state, "test_disable_content", workingDefinition())
                local _, foreign = registered(state, "test_disable_foreign", workingDefinition())
                registry.Register(workingDefinition(), "other")
                local first = PW.Instance(definition, "alice")
                local second = PW.Instance(definition, "bob")
                local other = PW.Instance(must(registry.Get("other")), "carol")
                local sameId = PW.Instance(foreign, "dave")
                local plain = PW.Instance({ ClassName = definition.ClassName }, "eve")
                local seen = 0
                hook.Add(event, listener, function()
                    for _, instance in ipairs({ first, second }) do
                        expect(rawget(instance, "_Definition")).to.equal(definition)
                        expect(instance.unequips).to.equal(1)
                        expect(instance:IsValid()).to.beFalse()
                        expect(clean(instance)).to.beTrue()
                    end
                    seen = seen + 1
                end)
                registry._Disable(definition.ClassName, "off")
                expect(seen).to.equal(1)
                for _, instance in ipairs({ other, sameId, plain }) do expect(instance:IsValid()).to.beTrue() end
                expect(first.cleanedOwner).to.equal("alice")
                expect(second.cleanedOwner).to.equal("bob")
            end
        },
        {
            name = "Disabled definitions cannot run instance gameplay or regrant on re-enable",
            func = function(state)
                local registry, definition = registered(state, "test_disable_content", workingDefinition())
                local instance = PW.Instance(definition, "owner")
                registry._Disable(definition.ClassName, "off")
                PW.Call(instance, "Work")
                hook.Run(workHook)
                expect(instance.work).to.beNil()
                expect(instance:IsValid()).to.beFalse()
                local blocked = PW.Instance(definition, "blocked")
                PW.Call(blocked, "Work")
                expect(blocked.work).to.beNil()
                expect(next(blocked._Hooks)).to.beNil()
                expect(blocked:IsValid()).to.beFalse()
                registry._Enable(definition.ClassName)
                expect(instance:IsValid()).to.beFalse()
                expect(PW.Instance(definition, "fresh"):IsValid()).to.beTrue()
            end
        },
        {
            name = "Instance gameplay respects source IsValid even without a registry disable call",
            func = function()
                local enabled = true
                local definition = workingDefinition()
                definition.IsValid = function() return enabled end
                local instance = PW.Instance(definition, "owner")
                enabled = false
                expect(instance:IsValid()).to.beFalse()
                PW.Call(instance, "Work")
                instance:Hook(workHook, function() error("invalid definition gameplay") end)
                expect(instance.work).to.beNil()
                instance:Remove()
                expect(instance.unequips).to.equal(1)
                expect(clean(instance)).to.beTrue()
            end
        },
        {
            name = "Plain nonregistry definitions still equip and execute gameplay",
            func = function()
                local instance = PW.Instance(workingDefinition(), "owner")
                PW.Call(instance, "Work")
                hook.Run(workHook)
                expect(instance.work).to.equal(2)
                expect(instance:IsValid()).to.beTrue()
                instance:Remove()
                expect(instance.unequips).to.equal(1)
                expect(clean(instance)).to.beTrue()
            end
        },
        {
            name = "Failed instance still runs OnUnequip exactly once without resuming gameplay",
            func = function(state)
                local definition = workingDefinition()
                definition.Fail = function() error("instance failure") end
                local instance = PW.Instance(definition, "owner")
                PW.Call(instance, "Fail")
                expect(instance:IsValid()).to.beFalse()
                PW.Call(instance, "Work")
                instance:Remove()
                instance:Remove()
                expect(instance.work).to.beNil()
                expect(instance.unequips).to.equal(1)
                expect(clean(instance)).to.beTrue()
                expect(#state.logged).to.equal(1)
            end
        },
        {
            name = "Failed OnEquip can be cleaned once even though ordinary calls are blocked",
            func = function()
                local definition = workingDefinition()
                definition.OnEquip = function() error("equip failure") end
                local instance = PW.Instance(definition, "owner")
                instance:Remove()
                instance:Remove()
                expect(instance.unequips).to.equal(1)
                expect(clean(instance)).to.beTrue()
            end
        },
        {
            name = "Reentrant failing OnUnequip always drops hooks timers and live entry without disabling definition",
            func = function(state)
                local own = workingDefinition()
                own.OnUnequip = function(self)
                    self.unequips = (self.unequips or 0) + 1
                    self:Remove()
                    PW.Call(self, "Work")
                    self:Hook(workHook, function() error("cleanup regrant") end)
                    self:Timer(60, 0, function() error("cleanup regrant") end)
                    error("unequip failure")
                end
                local registry, definition = registered(state, "test_disable_content", own)
                local instance = PW.Instance(definition, "owner")
                expect(pcall(instance.Remove, instance)).to.beTrue()
                instance:Remove()
                expect(instance.unequips).to.equal(1)
                expect(instance.work).to.beNil()
                expect(clean(instance)).to.beTrue()
                expect(registry._DisabledReason(definition.ClassName)).to.beNil()
                expect(#state.logged).to.equal(1)
                expect(string.find(state.logged[1], "OnUnequip", 1, true)).to.exist()
                expect(string.find(state.logged[1], "unequip failure", 1, true)).to.exist()
            end
        },
        {
            name = "Cleanup failure still ends every matching instance before the disable notification",
            func = function(state)
                local own = workingDefinition()
                own.OnUnequip = function(self)
                    self.unequips = (self.unequips or 0) + 1
                    error("disable unequip failure")
                end
                local registry, definition = registered(state, "test_disable_content", own)
                local first = PW.Instance(definition, "alice")
                local second = PW.Instance(definition, "bob")
                local seen = 0
                hook.Add(event, listener, function()
                    for _, instance in ipairs({ first, second }) do
                        expect(instance.unequips).to.equal(1)
                        expect(clean(instance)).to.beTrue()
                    end
                    seen = seen + 1
                end)
                expect(pcall(registry._Disable, definition.ClassName, "off")).to.beTrue()
                expect(seen).to.equal(1)
                expect(#state.logged).to.equal(2)
            end
        },
        {
            name = "Notification errors cannot undo disabled state or completed instance cleanup",
            func = function(state)
                local registry, definition = registered(state, "test_disable_content", workingDefinition())
                local instance = PW.Instance(definition, "owner")
                hook.Add(event, listener, function() error("notification failure") end)
                local ok = pcall(registry._Disable, definition.ClassName, "off")
                expect(ok).to.beFalse()
                expect(must(definition.IsValid)(definition)).to.beFalse()
                expect(registry._DisabledReason(definition.ClassName)).to.equal("off")
                expect(instance.unequips).to.equal(1)
                expect(clean(instance)).to.beTrue()
                expect(pcall(registry._Disable, definition.ClassName, "off")).to.beTrue()
            end
        },
        {
            name = "Release keeps the active definition valid without emitting disable or ending its instances",
            func = function(state)
                local registry, definition = registered(state, "test_disable_modes", workingDefinition())
                local instance = PW.Instance(definition, "owner")
                local seen = 0
                hook.Add(event, listener, function() seen = seen + 1 end)
                registry._Release({ [definition.ClassName] = true })
                expect(must(definition.IsValid)(definition)).to.beTrue()
                expect(instance:IsValid()).to.beTrue()
                expect(seen).to.equal(0)
            end
        }
    }
}
