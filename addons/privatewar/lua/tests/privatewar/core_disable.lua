-- Wave 0: a disabled entity is disabled everywhere (01-extensibility.md d.16, d.18; DESIGN.md global rule 2).
-- Its class table follows the resolved entity (IsValid), engine hooks added through PW.HookFor stop running, net
-- handlers registered with an owner drop messages, and the enable snapshot reaches clients through NW2 globals
-- (the client side is a pure decision over the NW2 values, so the server-only runner covers it).
-- Every case uses isolated registries of the kind "pwtest_disable" and a fresh net or enable store, and restores
-- them afterwards; the real modules and the real ConVars are never touched. The net case reuses a bot that is
-- already connected, or creates one and kicks it after the group.

local testKind = "pwtest_disable"
local engineHook = "PWTestDisableEngine"

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.EnableLib
local function enable()
    return must(PW.Enable)
end

---@return PW.NetLib
local function netLib()
    return must(PW.Net)
end

---Creates an isolated registry that afterEach releases; defs are registered, then resolved.
---@param state table<string, any>
---@param defs table<string, table>
---@param subscribe? PW.SubscribeMode
---@return PW.Registry
local function newRegistry(state, defs, subscribe)
    local registry = PW.Registry.New(testKind, { log = function() end, preRegister = function() end,
        subscribe = subscribe })
    local list = state.registries --[[@as PW.Registry[] ]]
    list[#list + 1] = registry
    for id, def in pairs(defs) do registry.Register(def, id) end
    registry.ResolveAll()
    return registry
end

---GMod's IsValid on any table (the identifier check of hook.Call).
---@param tbl table
---@return boolean
local function valid(tbl)
    return IsValid(tbl)
end

---A connected bot, or a new one that afterAll kicks (player slots are scarce).
---@param state table<string, any>
---@return Player
local function anyBot(state)
    local bot = player.GetBots()[1]
    if bot ~= nil and IsValid(bot) then return bot end
    local pool = state.pool --[[@as table<string, Player>]]
    bot = player.CreateNextBot("PW disable test")
    assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
    pool.bot = bot
    return bot
end

---Ids of a list of entities, in list order.
---@param list PW.Entity[]
---@return string
local function ids(list)
    ---@type string[]
    local out = {}
    for index, entity in ipairs(list) do out[index] = entity.ClassName end
    return table.concat(out, ",")
end

return {
    groupName = "PW disabled entities",
    beforeAll = function(state)
        state.pool = {}
    end,
    afterAll = function(state)
        local bot = (state.pool --[[@as table<string, Player>]]).bot
        if bot ~= nil and IsValid(bot) then bot:Kick("PW disable test finished") end
    end,
    beforeEach = function(state)
        state.registries = {}
        state.previousNet = PW._Net
        state.previousEnable = PW._Enable
    end,
    afterEach = function(state)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        for identifier in pairs(hook.GetTable()[engineHook] or {}) do hook.Remove(engineHook, identifier) end
        local receivers = net.Receivers --[[@as table<string, function?>]]
        receivers["pw_test_disable_msg"] = nil
        PW._Net = state.previousNet
        PW._Enable = state.previousEnable
    end,
    cases = {
        {
            name = "A class table's IsValid follows its entity: resolved and enabled, not disabled or replaced",
            func = function(state)
                local registry = PW.Registry.New(testKind, { log = function() end, preRegister = function() end })
                local list = state.registries --[[@as PW.Registry[] ]]
                list[#list + 1] = registry
                local class = {}
                registry.Register(class, "alpha")
                expect(valid(class)).to.beFalse()
                registry.ResolveAll()
                expect(valid(class)).to.beTrue()
                registry._Disable("alpha", "test")
                expect(valid(class)).to.beFalse()
                registry._Enable("alpha")
                expect(valid(class)).to.beTrue()
                registry.Register({}, "alpha")
                expect(valid(class)).to.beFalse()
                expect(valid(must(registry.GetStored("alpha")))).to.beTrue()
            end
        },
        {
            name = "PW.HookFor: the hook runs while the entity is enabled, not while disabled, again once re-enabled",
            func = function(state)
                ---@type any[]
                local selves = {}
                local class = {}
                PW.HookFor(class, engineHook, function(self, value) selves[#selves + 1] = { self, value } end)
                local registry = newRegistry(state, { alpha = class }, "always")
                local entity = must(registry.Get("alpha"))
                hook.Run(engineHook, 1)
                expect(#selves).to.equal(1)
                expect(selves[1][1]).to.equal(entity)
                expect(selves[1][2]).to.equal(1)
                registry._Disable("alpha", "test")
                hook.Run(engineHook, 2)
                expect(#selves).to.equal(1)
                registry._Enable("alpha")
                hook.Run(engineHook, 3)
                expect(#selves).to.equal(2)
                expect(selves[2][2]).to.equal(3)
            end
        },
        {
            name = "PW.HookFor hooks are added for a Subscribe = \"never\" kind too and dropped on release",
            func = function(state)
                local calls = 0
                local class = {}
                PW.HookFor(class, engineHook, function() calls = calls + 1 end)
                local registry = newRegistry(state, { alpha = class })
                hook.Run(engineHook)
                expect(calls).to.equal(1)
                registry._Release()
                hook.Run(engineHook)
                expect(calls).to.equal(1)
                expect(hook.GetTable()[engineHook] == nil or next(hook.GetTable()[engineHook]) == nil).to.beTrue()
            end
        },
        {
            name = "PW.Net.Receive with an owner: a disabled owner's handler is not called (bot sender)",
            func = function(state)
                PW._Net = netLib()._NewStore({ log = function() end, phase = function() return "LOBBY" end })
                local class = {}
                local registry = newRegistry(state, { alpha = class })
                local calls = 0
                expect(netLib().Receive("pw_test_disable_msg", { who = "any", rate = 50, maxLen = 8, owner = class },
                    function() calls = calls + 1 end)).to.beTrue()
                local bot = anyBot(state)
                expect(netLib()._Dispatch("pw_test_disable_msg", 8, bot)).to.beTrue()
                registry._Disable("alpha", "test")
                expect({ netLib()._Dispatch("pw_test_disable_msg", 8, bot) }).to.deepEqual({ false, "disabled" })
                expect(calls).to.equal(1)
                registry._Enable("alpha")
                expect(netLib()._Dispatch("pw_test_disable_msg", 8, bot)).to.beTrue()
                expect(calls).to.equal(2)
            end
        },
        {
            name = "Net decision (pure): an inactive owner is reported first and takes no rate token",
            func = function()
                local def = must(netLib()._MakeDef("pw_x", { who = "any", rate = 1, maxLen = 8 }, function() end))
                local reason, bucket = netLib()._Decide(def, { allowed = false, phase = "LIVE", len = 8,
                    active = false }, nil, 10)
                expect(reason).to.equal("disabled")
                expect(bucket.tokens).to.equal(1)
                expect(netLib()._Decide(def, { allowed = true, phase = "LIVE", len = 8, active = true }, bucket, 10))
                    .to.beNil()
            end
        },
        {
            name = "An owner is any table (a class table gets IsValid only when registered); none: always active",
            func = function(state)
                local _, err = netLib()._MakeDef("pw_x", { who = "any", rate = 1, maxLen = 8, owner = "lobby" },
                    function() end)
                expect(err).to.equal("owner must be a table")
                -- A module file registers its messages while it runs, before the registry gives MODULE its IsValid.
                PW._Net = netLib()._NewStore({ log = function() end, phase = function() return "LOBBY" end })
                local class = {}
                local calls = 0
                expect(netLib().Receive("pw_test_disable_msg", { who = "any", rate = 50, maxLen = 8, owner = class },
                    function() calls = calls + 1 end)).to.beTrue()
                local bot = anyBot(state)
                expect({ netLib()._Dispatch("pw_test_disable_msg", 8, bot) }).to.deepEqual({ false, "disabled" })
                newRegistry(state, { alpha = class })
                expect(netLib()._Dispatch("pw_test_disable_msg", 8, bot)).to.beTrue()
                expect(calls).to.equal(1)
                local def = must(netLib()._MakeDef("pw_x", { who = "any", rate = 1, maxLen = 8 }, function() end))
                expect(def.owner).to.beNil()
            end
        },
        {
            name = "Snapshot to NW2 (pure): disabled ids get true, re-enabled ids false, unchanged ids nothing",
            func = function(state)
                local registry = newRegistry(state, { alpha = {}, beta = {}, gamma = {}, base = { Abstract = true } })
                local registries = { [testKind] = registry }
                local key = enable()._Key
                local writes = enable()._Writes(registries, { [testKind] = { beta = true } }, {})
                expect(writes).to.deepEqual({ { key = key(testKind, "beta"), value = true } })
                writes = enable()._Writes(registries, { [testKind] = { gamma = true } },
                    { [key(testKind, "beta")] = true })
                expect(writes).to.deepEqual({
                    { key = key(testKind, "beta"), value = false }, { key = key(testKind, "gamma"), value = true }
                })
                expect(enable()._Writes(registries, {}, {})).to.deepEqual({})
                expect(key("modules", "lobby_ui")).to.equal("pw_off:modules:lobby_ui")
            end
        },
        {
            name = "Client decision (pure): the NW2 values hide a disabled module from lists and IsValid",
            func = function(state)
                local class = {}
                local registry = newRegistry(state, { lobby = class, hud = {} }, "always")
                local registries = { [testKind] = registry }
                local values = { [enable()._Key(testKind, "lobby")] = true }
                local function read(name) return values[name] == true end
                local snapshot = enable()._ReadSnapshot(registries, read)
                expect(snapshot).to.deepEqual({ [testKind] = { lobby = true } })
                enable()._Apply(registries, snapshot)
                expect(ids(registry.GetEnabledList())).to.equal("hud")
                expect(valid(class)).to.beFalse()
                values = {}
                enable()._Apply(registries, enable()._ReadSnapshot(registries, read))
                expect(ids(registry.GetEnabledList())).to.equal("hud,lobby")
                expect(valid(class)).to.beTrue()
            end
        },
        {
            name = "The server writes the snapshot to NW2 only once networked, then only the changes",
            func = function(state)
                local registry = newRegistry(state, { alpha = {}, beta = {} })
                ---@type table<string, boolean>
                local flags = { ["pw_" .. testKind .. "_beta_enabled"] = false }
                ---@type string[]
                local written = {}
                PW._Enable = enable()._NewStore({
                    registries = function() return { [testKind] = registry } end,
                    read = function(name) return flags[name] ~= false end,
                    create = function() end,
                    exists = function() return true end,
                    write = function(key, value) written[#written + 1] = key .. "=" .. tostring(value) end
                })
                enable()._NewMatch()
                expect(#written).to.equal(0)
                enable()._Publish()
                expect(written).to.deepEqual({ enable()._Key(testKind, "beta") .. "=true" })
                enable()._NewMatch()
                expect(#written).to.equal(1)
                flags = {}
                enable()._NewMatch()
                expect(written[2]).to.equal(enable()._Key(testKind, "beta") .. "=false")
                expect(#written).to.equal(2)
            end
        }
    }
}
