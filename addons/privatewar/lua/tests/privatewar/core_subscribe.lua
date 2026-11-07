-- T-1.7 auto-subscription (TASKS.md, "Mandatory test cases"; 01-extensibility.md d.18). Isolated registries
-- and the fixture tree lua/privatewar_fixtures/subscribe/. Every case uses its own PW_TestSub* hook names;
-- afterEach releases every registry the case created and removes every listener of those hooks.

local testHooks = {
    "PW_TestSubOnly", "PW_TestSubNever", "PW_TestSubDisable", "PW_TestSubEnable", "PW_TestSubInherited",
    "PW_TestSubReplace", "PW_TestSubResolve", "PW_TestSubAbstract", "PW_TestSubDefault", "PW_TestSubEarly",
    "PW_TestSubRelease", "PW_TestSubKeep", "PW_TestSubBoot", "PW_TestSubInvalid", "PW_TestSubFixtureAlways",
    "PW_TestSubFixtureNever", "PW_TestSubFixtureDefault", "PW_TestSubFixtureModule"
}

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---Creates an isolated registry that the case's afterEach releases.
---@param state table<string, any>
---@param subscribe? string
---@return PW.Registry registry, string[] logged
local function newRegistry(state, subscribe)
    ---@type string[]
    local logged = {}
    local registry = PW.Registry.New("test_subscribe", {
        log = function(message) logged[#logged + 1] = message end,
        preRegister = function() end,
        subscribe = subscribe --[[@as PW.SubscribeMode]]
    })
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    return registry, logged
end

---True when the hook table holds a listener of the hook under this identifier.
---@param name string
---@param identifier any
---@return boolean
local function isSubscribed(name, identifier)
    local listeners = hook.GetTable()[name] --[[@as table<any, function>?]]
    return listeners ~= nil and listeners[identifier] ~= nil
end

---Calls the IsValid method the registry set on a resolved entity.
---@param entity PW.Entity
---@return boolean
local function valid(entity)
    return must(entity.IsValid)(entity)
end

---Number of listeners of a hook.
---@param name string
---@return integer
local function listenerCount(name)
    local count = 0
    for _ in pairs(hook.GetTable()[name] or {}) do count = count + 1 end
    return count
end

return {
    groupName = "PW auto-subscription",
    beforeEach = function(state)
        state.registries = {}
    end,
    afterEach = function(state)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        for _, name in ipairs(testHooks) do
            for identifier in pairs(hook.GetTable()[name] or {}) do hook.Remove(name, identifier) end
        end
    end,
    cases = {
        {
            name = "Lists only functions whose name starts with PW_",
            func = function()
                local noop = function() end
                local names = PW.Registry._HookMethods({
                    PW_B = noop, PW_A = noop, Think = noop, PW_Data = 5, pw_lower = noop, PWNoUnderscore = noop
                })
                expect(#names).to.equal(2)
                expect(names[1]).to.equal("PW_A")
                expect(names[2]).to.equal("PW_B")
            end
        },
        {
            name = "Only PW_* methods are subscribed (a method named Think is not)",
            func = function(state)
                local registry = newRegistry(state, "always")
                ---@type table[]
                local seen = {}
                registry.Register({
                    ---@param self PW.Entity
                    ---@param value integer
                    PW_TestSubOnly = function(self, value) seen[#seen + 1] = { self, value } end,
                    Think = function() end
                }, "one")
                registry.ResolveAll()
                local entity = must(registry.Get("one"))
                expect(isSubscribed("PW_TestSubOnly", entity)).to.beTrue()
                expect(isSubscribed("Think", entity)).to.beFalse()
                hook.Run("PW_TestSubOnly", 7)
                expect(#seen).to.equal(1)
                expect(seen[1][1]).to.equal(entity)
                expect(seen[1][2]).to.equal(7)
            end
        },
        {
            name = "KIND.Subscribe = \"never\" entities are not subscribed",
            func = function(state)
                local registry = newRegistry(state, "never")
                local calls = 0
                registry.Register({ PW_TestSubNever = function() calls = calls + 1 end }, "one")
                registry.ResolveAll()
                expect(isSubscribed("PW_TestSubNever", registry.Get("one"))).to.beFalse()
                hook.Run("PW_TestSubNever")
                expect(calls).to.equal(0)
            end
        },
        {
            -- The core disable mechanism behind both variants of the mandatory case: T-1.4 (enable ConVar)
            -- and T-1.8 (disable after an error) call registry._Disable and add their own cases on top.
            name = "Disabling an entity (core mechanism of ConVar and error) removes its subscriptions (IsValid false)",
            func = function(state)
                local registry = newRegistry(state, "always")
                local calls = 0
                registry.Register({ PW_TestSubDisable = function() calls = calls + 1 end }, "one")
                registry.ResolveAll()
                local entity = must(registry.Get("one"))
                expect(valid(entity)).to.beTrue()
                hook.Run("PW_TestSubDisable")
                expect(calls).to.equal(1)

                registry._Disable("one", "test")
                expect(valid(entity)).to.beFalse()
                expect(registry._DisabledReason("one")).to.equal("test")
                expect(isSubscribed("PW_TestSubDisable", entity)).to.beFalse()
                hook.Run("PW_TestSubDisable")
                expect(calls).to.equal(1)
            end
        },
        {
            name = "A disabled entity stays disabled and unsubscribed when it is re-registered",
            func = function(state)
                local registry = newRegistry(state, "always")
                local noop = function() end
                registry.Register({ PW_TestSubKeep = noop }, "one")
                registry.ResolveAll()
                registry._Disable("one", "test")
                registry.Register({ PW_TestSubKeep = noop }, "one")
                local entity = must(registry.Get("one"))
                expect(valid(entity)).to.beFalse()
                expect(isSubscribed("PW_TestSubKeep", entity)).to.beFalse()
            end
        },
        {
            name = "Enabling a disabled entity subscribes it again",
            func = function(state)
                local registry = newRegistry(state, "always")
                local calls = 0
                registry.Register({ PW_TestSubEnable = function() calls = calls + 1 end }, "one")
                registry.ResolveAll()
                registry._Disable("one", "test")
                registry._Enable("one")
                local entity = must(registry.Get("one"))
                expect(valid(entity)).to.beTrue()
                expect(registry._DisabledReason("one")).to.beNil()
                hook.Run("PW_TestSubEnable")
                expect(calls).to.equal(1)
            end
        },
        {
            name = "Inherited PW_ methods are subscribed on the resolved entity",
            func = function(state)
                local registry = newRegistry(state, "always")
                ---@type PW.Entity[]
                local selves = {}
                ---@param self PW.Entity
                local function record(self) selves[#selves + 1] = self end
                registry.Register({ Abstract = true, PW_TestSubInherited = record }, "base")
                registry.Register({ Base = "base" }, "child")
                registry.ResolveAll()
                local child = must(registry.Get("child"))
                expect(isSubscribed("PW_TestSubInherited", child)).to.beTrue()
                hook.Run("PW_TestSubInherited")
                expect(#selves).to.equal(1)
                expect(selves[1]).to.equal(child)
            end
        },
        {
            name = "Abstract entities are not subscribed",
            func = function(state)
                local registry = newRegistry(state, "always")
                registry.Register({ Abstract = true, PW_TestSubAbstract = function() end }, "base")
                registry.ResolveAll()
                expect(listenerCount("PW_TestSubAbstract")).to.equal(0)
            end
        },
        {
            name = "Re-registering an id replaces its subscription; the old table is no longer called",
            func = function(state)
                local registry = newRegistry(state, "always")
                ---@type string[]
                local calls = {}
                registry.Register({ PW_TestSubReplace = function() calls[#calls + 1] = "old" end }, "one")
                registry.ResolveAll()
                local old = must(registry.Get("one"))
                registry.Register({ PW_TestSubReplace = function() calls[#calls + 1] = "new" end }, "one")
                expect(valid(old)).to.beFalse()
                expect(isSubscribed("PW_TestSubReplace", old)).to.beFalse()
                expect(listenerCount("PW_TestSubReplace")).to.equal(1)
                hook.Run("PW_TestSubReplace")
                expect(#calls).to.equal(1)
                expect(calls[1]).to.equal("new")
            end
        },
        {
            name = "ResolveAll rebuilds the entities and leaves no stale or duplicate subscription",
            func = function(state)
                local registry = newRegistry(state, "always")
                local calls = 0
                registry.Register({ PW_TestSubResolve = function() calls = calls + 1 end }, "one")
                registry.ResolveAll()
                local old = must(registry.Get("one"))
                registry.ResolveAll()
                registry.ResolveAll()
                local current = must(registry.Get("one"))
                expect(current).notTo.equal(old)
                expect(valid(old)).to.beFalse()
                expect(isSubscribed("PW_TestSubResolve", old)).to.beFalse()
                expect(isSubscribed("PW_TestSubResolve", current)).to.beTrue()
                expect(listenerCount("PW_TestSubResolve")).to.equal(1)
                hook.Run("PW_TestSubResolve")
                expect(calls).to.equal(1)
            end
        },
        {
            name = "Nothing is subscribed before the registry is resolved",
            func = function(state)
                local registry = newRegistry(state, "always")
                registry.Register({ PW_TestSubEarly = function() end }, "one")
                expect(listenerCount("PW_TestSubEarly")).to.equal(0)
            end
        },
        {
            name = "A registry without a Subscribe setting does not subscribe",
            func = function(state)
                local registry = newRegistry(state, nil)
                registry.Register({ PW_TestSubDefault = function() end }, "one")
                registry.ResolveAll()
                expect(listenerCount("PW_TestSubDefault")).to.equal(0)
            end
        },
        {
            name = "An unknown Subscribe value logs one line and subscribes nothing",
            func = function(state)
                local registry, logged = newRegistry(state, "sometimes")
                registry.Register({ PW_TestSubInvalid = function() end }, "one")
                registry.ResolveAll()
                expect(listenerCount("PW_TestSubInvalid")).to.equal(0)
                expect(#logged).to.equal(1)
                expect(string.find(logged[1] or "", "sometimes", 1, true)).to.exist()
            end
        },
        {
            name = "Releasing a registry removes its subscriptions and invalidates its entities",
            func = function(state)
                local registry = newRegistry(state, "always")
                registry.Register({ PW_TestSubRelease = function() end }, "one")
                registry.ResolveAll()
                local entity = must(registry.Get("one"))
                registry._Release()
                expect(valid(entity)).to.beFalse()
                expect(listenerCount("PW_TestSubRelease")).to.equal(0)
            end
        },
        {
            name = "Loaded trees: modules and Subscribe = \"always\" kinds subscribe; \"never\" and omitted do not",
            func = function(state)
                local context = PW.Loader.LoadRoot("privatewar_fixtures/subscribe", { log = function() end })
                local registries = state.registries --[[@as PW.Registry[] ]]
                for _, registry in pairs(context.registries) do registries[#registries + 1] = registry end
                local reg = context.registries
                expect(isSubscribed("PW_TestSubFixtureModule", must(reg.modules.Get("listener")))).to.beTrue()
                expect(isSubscribed("PW_TestSubFixtureAlways", must(must(reg.sub_always).Get("one")))).to.beTrue()
                expect(isSubscribed("Think", must(must(reg.sub_always).Get("one")))).to.beFalse()
                expect(listenerCount("PW_TestSubFixtureNever")).to.equal(0)
                expect(listenerCount("PW_TestSubFixtureDefault")).to.equal(0)
            end
        },
        {
            name = "Boot releases the previous registries: their entities stop receiving hooks",
            func = function()
                local calls = 0
                local previous = PW.Modules
                previous.Register({ PW_TestSubBoot = function() calls = calls + 1 end }, "test_subscribe_boot")
                local old = must(previous.Get("test_subscribe_boot"))
                expect(isSubscribed("PW_TestSubBoot", old)).to.beTrue()
                PW.Loader.Boot()
                expect(PW.Modules).notTo.equal(previous)
                expect(valid(old)).to.beFalse()
                expect(listenerCount("PW_TestSubBoot")).to.equal(0)
                hook.Run("PW_TestSubBoot")
                expect(calls).to.equal(0)
            end
        }
    }
}
