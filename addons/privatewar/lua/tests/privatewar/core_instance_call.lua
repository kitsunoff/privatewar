-- Removal must cross PW.Call (00-core.md d.6/d.11), retaining profiling and cleanup-only admission.

local workHook = "PW_TestInstanceCallWork"

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@param instance PW.Instance
---@return boolean
local function clean(instance)
    if PW._Instances.live[instance] ~= nil then return false end
    if (hook.GetTable()[workHook] or {})[instance] ~= nil then return false end
    for name in pairs(instance._Timers) do
        if timer.Exists(name) then return false end
    end
    return true
end

---@return table<string, any>
local function definition()
    return {
        ClassName = "test_instance_call",
        OnEquip = function(self)
            self:Hook(workHook, function(me) me.work = (me.work or 0) + 1 end)
            self:Timer(60, 0, function() end)
        end,
        OnUnequip = function(self)
            self.unequips = (self.unequips or 0) + 1
            local start = SysTime()
            local spins = 0
            repeat spins = spins + 1 until SysTime() - start >= 0.001
            self.cleanupSpins = spins
        end,
        Fail = function() error("instance call failure") end,
        Work = function(self) self.work = (self.work or 0) + 1 end
    }
end

---@param state table<string, any>
---@param own table<string, any>
---@return PW.Registry, PW.Entity
local function registered(state, own)
    local registry = PW.Registry.New("test_instance_call", { preRegister = function() end })
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    registry.Register(own, "test_instance_call")
    registry.ResolveAll()
    return registry, must(registry.Get("test_instance_call"))
end

return {
    groupName = "PW.Instance centralized cleanup calls",
    beforeEach = function(state)
        state.instances = PW._Instances
        state.call = PW._Call
        state.mode = PW.ActiveMode
        state.profile = must(GetConVar("pw_profile")):GetString()
        state.registries = {}
        local logged = {} ---@type string[]
        state.logged = logged
        PW.ActiveMode = nil
        PW._Instances = { live = {}, count = 0 }
        PW._Call = { log = function(message) logged[#logged + 1] = message end,
            failed = setmetatable({}, { __mode = "k" }), profile = {} }
        must(GetConVar("pw_profile")):SetString("1")
    end,
    afterEach = function(state)
        PW._EndInstances()
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        PW._Instances = state.instances
        PW._Call = state.call
        PW.ActiveMode = state.mode
        must(GetConVar("pw_profile")):SetString(state.profile)
    end,
    cases = {
        {
            name = "Remove crosses the actual PW.Call boundary and profiles OnUnequip",
            func = function()
                local instance = PW.Instance(definition(), "owner")
                PW.Profile.Reset()
                local original = PW.Call
                local calls = 0
                stub(PW, "Call").with(function(entity, method, ...)
                    if entity == instance and method == "OnUnequip" then calls = calls + 1 end
                    return original(entity, method, ...)
                end)
                instance:Remove()
                expect(calls).to.equal(1)
                local entry = must(PW.Profile.Get()["?:test_instance_call"])
                expect(entry.calls).to.equal(1)
                expect(entry.time > 0).to.beTrue()
                expect(instance.unequips).to.equal(1)
                expect(clean(instance)).to.beTrue()
            end
        },
        {
            name = "Failed instances admit profiled OnUnequip only during actual Remove",
            func = function()
                local instance = PW.Instance(definition(), "owner")
                PW.Call(instance, "Fail")
                PW.Profile.Reset()
                PW.Call(instance, "OnUnequip", "owner")
                expect(instance.unequips).to.beNil()
                instance:Remove()
                PW.Call(instance, "OnUnequip", "owner")
                PW.Call(instance, "Work")
                expect(instance.unequips).to.equal(1)
                expect(instance.work).to.beNil()
                expect(must(PW.Profile.Get()["?:test_instance_call"]).calls).to.equal(1)
                expect(clean(instance)).to.beTrue()
            end
        },
        {
            name = "Definition disable profiles cleanup without changing the original disable reason",
            func = function(state)
                local registry, def = registered(state, definition())
                local instance = PW.Instance(def, "owner")
                PW.Profile.Reset()
                registry._Disable(def.ClassName, "off")
                PW.Call(instance, "OnUnequip", "owner")
                expect(must(PW.Profile.Get()["test_instance_call:test_instance_call"]).calls).to.equal(1)
                expect(instance.unequips).to.equal(1)
                expect(registry._DisabledReason(def.ClassName)).to.equal("off")
                expect(clean(instance)).to.beTrue()
            end
        },
        {
            name = "Cleanup admission is single-use and cannot admit nested OnUnequip or gameplay",
            func = function()
                local own = definition()
                own.OnUnequip = function(self)
                    self.unequips = (self.unequips or 0) + 1
                    if self.unequips > 1 then error("recursive cleanup admission") end
                    PW.Call(self, "OnUnequip", "owner")
                    PW.Call(self, "Work")
                    self:Hook(workHook, function() error("regrant") end)
                    self:Timer(60, 0, function() error("regrant") end)
                    self:Remove()
                end
                local instance = PW.Instance(own, "owner")
                PW.Profile.Reset()
                instance:Remove()
                expect(instance.unequips).to.equal(1)
                expect(instance.work).to.beNil()
                expect(must(PW.Profile.Get()["?:test_instance_call"]).calls).to.equal(1)
                expect(clean(instance)).to.beTrue()
            end
        },
        {
            name = "Cleanup and profiling survive both OnUnequip and logger errors without disabling the definition",
            func = function(state)
                local own = definition()
                own.OnUnequip = function() error("unequip call failure") end
                local registry, def = registered(state, own)
                local instance = PW.Instance(def, "owner")
                PW.Profile.Reset()
                local logs = 0
                rawset(PW._Call, "log", function() logs = logs + 1 error("logger failure") end)
                expect(pcall(instance.Remove, instance)).to.beTrue()
                expect(clean(instance)).to.beTrue()
                expect(logs).to.equal(1)
                expect(registry._DisabledReason(def.ClassName)).to.beNil()
                expect(must(def.IsValid)(def)).to.beTrue()
                expect(must(PW.Profile.Get()["test_instance_call:test_instance_call"]).calls).to.equal(1)
            end
        },
        {
            name = "An already invalid constructor fails closed without a live-entry leak",
            func = function()
                local own = definition()
                own.IsValid = function() return false end
                local instance = PW.Instance(own, "owner")
                expect(instance:IsValid()).to.beFalse()
                expect(clean(instance)).to.beTrue()
                expect(next(instance._Hooks)).to.beNil()
                expect(instance.unequips).to.equal(1)
                instance:Remove()
                expect(instance.unequips).to.equal(1)
            end
        },
        {
            name = "Failed OnEquip immediately unequips once and removes resources before returning",
            func = function()
                local own = definition()
                local equip = own.OnEquip
                own.OnEquip = function(self, owner)
                    equip(self, owner)
                    error("equip call failure")
                end
                local instance = PW.Instance(own, "owner")
                expect(instance:IsValid()).to.beFalse()
                expect(clean(instance)).to.beTrue()
                expect(instance.unequips).to.equal(1)
                PW.Call(instance, "Work")
                instance:Remove()
                expect(instance.work).to.beNil()
                expect(instance.unequips).to.equal(1)
            end
        },
        {
            name = "Caller-controlled removal-looking fields cannot admit a disabled ordinary call",
            func = function()
                local calls = 0
                local fake = { _Ended = true, _Dead = true, _Removing = true, _CleanupPending = true,
                    IsValid = function() return false end,
                    OnUnequip = function() calls = calls + 1 end }
                PW.Call(fake, "OnUnequip")
                expect(calls).to.equal(0)
                expect(next(PW.Profile.Get())).to.beNil()
            end
        },
        {
            name = "A PW.Call boundary exception still finalizes resources and clears cleanup admission",
            func = function()
                local instance = PW.Instance(definition(), "owner")
                local original = PW.Call
                local calls = 0
                stub(PW, "Call").with(function()
                    calls = calls + 1
                    error("call boundary failure")
                end)
                expect(pcall(instance.Remove, instance)).to.beTrue()
                expect(calls).to.equal(1)
                expect(clean(instance)).to.beTrue()
                original(instance, "OnUnequip", "owner")
                expect(instance.unequips).to.beNil()
            end
        }
    }
}
