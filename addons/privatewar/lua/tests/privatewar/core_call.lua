-- T-1.8 PW.Call (TASKS.md, "Mandatory test cases"; 00-core.md d.6; 01-extensibility.md d.15, d.18).
-- Isolated registries; every case swaps in a fresh call store (capturing logger, empty profile) and restores
-- the store, PW.ActiveMode, PW.Match, the pw_profile ConVar and every PW_TestCall* listener afterwards.

local testHooks = { "PW_TestCallSub" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return ConVar
local function profileVar()
    return must(GetConVar("pw_profile"))
end

---Creates an isolated registry that the case's afterEach releases.
---@param state table<string, any>
---@param subscribe? PW.SubscribeMode
---@return PW.Registry
local function newRegistry(state, subscribe)
    local registry = PW.Registry.New("test_call", {
        log = function() end,
        preRegister = function() end,
        subscribe = subscribe
    })
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    return registry
end

---Calls the IsValid method the registry set on a resolved entity.
---@param entity PW.Entity
---@return boolean
local function valid(entity)
    return must(entity.IsValid)(entity)
end

---True when the hook table holds a listener of the hook under this identifier.
---@param name string
---@param identifier any
---@return boolean
local function isSubscribed(name, identifier)
    local listeners = hook.GetTable()[name] --[[@as table<any, function>?]]
    return listeners ~= nil and listeners[identifier] ~= nil
end

---Busy-waits a little so a measured call takes measurable time.
---@return integer spins
local function burn()
    local start = SysTime()
    local spins = 0
    repeat spins = spins + 1 until SysTime() - start >= 0.001
    return spins
end

return {
    groupName = "PW.Call",
    beforeEach = function(state)
        state.registries = {}
        state.previousStore = PW._Call
        state.previousMode = PW.ActiveMode
        state.previousMatch = rawget(PW, "Match")
        state.previousProfile = profileVar():GetString()
        ---@type string[]
        local logged = {}
        state.logged = logged
        PW._Call = {
            log = function(message) logged[#logged + 1] = message end,
            failed = setmetatable({}, { __mode = "k" }),
            profile = {}
        }
        profileVar():SetString("0")
    end,
    afterEach = function(state)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        for _, name in ipairs(testHooks) do
            for identifier in pairs(hook.GetTable()[name] or {}) do hook.Remove(name, identifier) end
        end
        PW._Call = state.previousStore
        PW.ActiveMode = state.previousMode
        rawset(PW, "Match", state.previousMatch)
        profileVar():SetString(state.previousProfile)
    end,
    cases = {
        {
            name = "Passes self and arguments and returns every result of the method",
            func = function()
                local entity = { ClassName = "plain" }
                function entity:Sum(a, b) return a + b, self end
                local sum, seenSelf = PW.Call(entity, "Sum", 2, 3)
                expect(sum).to.equal(5)
                expect(seenSelf).to.equal(entity)
            end
        },
        {
            name = "A missing method returns nothing and logs nothing",
            func = function(state)
                expect(select("#", PW.Call({ ClassName = "plain" }, "Missing"))).to.equal(0)
                expect(#state.logged).to.equal(0)
            end
        },
        {
            name = "An erroring entity method returns safely, logs once, and the entity is disabled until map change",
            func = function(state)
                local registry = newRegistry(state)
                local calls = 0
                registry.Register({
                    Boom = function()
                        calls = calls + 1
                        error("boom happened")
                    end
                }, "one")
                registry.ResolveAll()
                local entity = must(registry.Get("one"))

                local ok, result = pcall(PW.Call, entity, "Boom")
                expect(ok).to.beTrue()
                expect(result).to.beNil()
                expect(calls).to.equal(1)
                expect(#state.logged).to.equal(1)
                local line = state.logged[1] or ""
                expect(string.find(line, "test_call", 1, true)).to.exist()
                expect(string.find(line, "one", 1, true)).to.exist()
                expect(string.find(line, "Boom", 1, true)).to.exist()
                expect(string.find(line, "boom happened", 1, true)).to.exist()

                expect(valid(entity)).to.beFalse()
                expect(registry._DisabledReason("one")).to.exist()

                PW.Call(entity, "Boom")
                PW.Call(entity, "Boom")
                expect(calls).to.equal(1)
                expect(#state.logged).to.equal(1)

                -- Re-resolving (no map change) keeps the entity disabled.
                registry.ResolveAll()
                local again = must(registry.Get("one"))
                expect(valid(again)).to.beFalse()
                PW.Call(again, "Boom")
                expect(calls).to.equal(1)
                expect(#state.logged).to.equal(1)
            end
        },
        {
            name = "An erroring entity without a registry is not called again",
            func = function(state)
                local calls = 0
                local entity = { ClassName = "loose" }
                function entity.Boom()
                    calls = calls + 1
                    error("loose boom")
                end
                PW.Call(entity, "Boom")
                PW.Call(entity, "Boom")
                expect(calls).to.equal(1)
                expect(#state.logged).to.equal(1)
            end
        },
        {
            name = "Disabling an entity after an error removes its subscriptions (IsValid false)",
            func = function(state)
                local registry = newRegistry(state, "always")
                local hookCalls = 0
                registry.Register({
                    PW_TestCallSub = function() hookCalls = hookCalls + 1 end,
                    Boom = function() error("subscribed boom") end
                }, "one")
                registry.ResolveAll()
                local entity = must(registry.Get("one"))
                expect(isSubscribed("PW_TestCallSub", entity)).to.beTrue()

                PW.Call(entity, "Boom")
                expect(valid(entity)).to.beFalse()
                expect(isSubscribed("PW_TestCallSub", entity)).to.beFalse()
                hook.Run("PW_TestCallSub")
                PW.Call(entity, "PW_TestCallSub")
                expect(hookCalls).to.equal(0)
            end
        },
        {
            name = "The active mode erroring ends the match and returns to LOBBY with the error message",
            func = function(state)
                ---@type string[]
                local reasons = {}
                rawset(PW, "Match", { Abort = function(reason) reasons[#reasons + 1] = reason end })
                local registry = newRegistry(state)
                registry.Register({ OnKill = function() error("mode boom") end }, "testmode")
                registry.ResolveAll()
                local mode = must(registry.Get("testmode"))
                PW.ActiveMode = mode

                local ok = pcall(PW.Call, mode, "OnKill")
                expect(ok).to.beTrue()
                expect(#reasons).to.equal(1)
                local reason = reasons[1] or ""
                expect(string.find(reason, "mode testmode failed: ", 1, true)).to.equal(1)
                expect(string.find(reason, "mode boom", 1, true)).to.exist()
                -- The mode is not disabled in place: the match abort handles it.
                expect(valid(mode)).to.beTrue()
                expect(#state.logged).to.equal(1)
            end
        },
        {
            name = "Without PW.Match.Abort the active mode erroring logs the message",
            func = function(state)
                rawset(PW, "Match", nil)
                local mode = { ClassName = "testmode" }
                function mode.OnKill() error("mode boom") end
                PW.ActiveMode = mode
                expect(pcall(PW.Call, mode, "OnKill")).to.beTrue()
                expect(#state.logged).to.equal(1)
                local line = state.logged[1] or ""
                expect(string.find(line, "mode testmode failed: ", 1, true)).to.exist()
                expect(string.find(line, "mode boom", 1, true)).to.exist()
            end
        },
        {
            name = "With pw_profile 1 time is accumulated per entity id",
            func = function(state)
                profileVar():SetString("1")
                local registry = newRegistry(state)
                registry.Register({ Work = burn }, "one")
                registry.Register({ Work = burn }, "two")
                registry.ResolveAll()
                local one = must(registry.Get("one"))
                local two = must(registry.Get("two"))
                PW.Call(one, "Work")
                PW.Call(one, "Work")
                PW.Call(two, "Work")

                local profile = PW.Profile.Get()
                local first = must(profile["test_call:one"])
                local second = must(profile["test_call:two"])
                expect(first.calls).to.equal(2)
                expect(second.calls).to.equal(1)
                expect(first.time > 0).to.beTrue()
                expect(second.time > 0).to.beTrue()

                PW.Profile.Reset()
                expect(next(PW.Profile.Get())).to.beNil()
            end
        },
        {
            name = "With pw_profile 0 nothing is recorded",
            func = function(state)
                profileVar():SetString("0")
                local registry = newRegistry(state)
                registry.Register({ Work = burn }, "one")
                registry.ResolveAll()
                PW.Call(must(registry.Get("one")), "Work")
                expect(next(PW.Profile.Get())).to.beNil()
            end
        }
    }
}
