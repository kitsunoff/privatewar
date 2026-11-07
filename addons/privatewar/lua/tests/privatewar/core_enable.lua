-- T-1.4 enable ConVars (TASKS.md, "Mandatory test cases" T-1.4 and the T-1.7 ConVar case; 01-extensibility.md
-- d.11, d.16). Every case swaps in a fresh enable store whose registries are isolated test registries of the kind
-- "pwtest_enable" (so their ConVars are recognisable as pw_pwtest_enable_<id>_enabled), a fresh phase store and a
-- fresh PW.Call store, and restores all of them, PW.ActiveMode and every ConVar value it changed afterwards, so
-- the real machine stays in LOBBY.

local testKind = "pwtest_enable"
local listenerId = "PW_Test_Enable"
local subHook = "PW_TestEnableSub"

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@return PW.EnableLib
local function enable()
    return must(PW.Enable)
end

---@param id string
---@return string
local function varName(id)
    return "pw_" .. testKind .. "_" .. id .. "_enabled"
end

---Sets an enable ConVar of a test entity; afterEach restores the value it had before the first change.
---@param state table<string, any>
---@param id string
---@param value boolean
local function setFlag(state, id, value)
    local convar = must(GetConVar(varName(id)))
    local saved = state.saved --[[@as table<ConVar, string>]]
    if saved[convar] == nil then saved[convar] = convar:GetString() end
    convar:SetBool(value)
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

---Creates a test registry of the test kind, adds it to the enable store's registries and resolves it.
---@param state table<string, any>
---@param defs table<string, table>
---@param subscribe? PW.SubscribeMode
---@return PW.Registry
local function newRegistry(state, defs, subscribe)
    local registry = PW.Registry.New(testKind, { log = function() end, preRegister = function() end,
        subscribe = subscribe })
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    local map = state.map --[[@as table<string, PW.Registry>]]
    map[testKind] = registry
    for id, def in pairs(defs) do registry.Register(def, id) end
    registry.ResolveAll()
    enable()._EnsureConVars()
    return registry
end

---A mode in its own registry (outside the enable store), counting nothing.
---@param state table<string, any>
---@return table
local function newMode(state)
    local registry = PW.Registry.New("pwtest_enable_mode", { log = function() end, preRegister = function() end })
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    registry.Register({ Name = "Test", Teams = 0 }, "testmode")
    registry.ResolveAll()
    return must(registry.Get("testmode"))
end

---Moves the fake clock to the end of the current phase and runs one machine step.
---@param state table<string, any>
local function expire(state)
    state.now = PW._Match.endsAt
    match()._Tick()
end

---LOBBY -> PREMATCH -> (countdown) -> LIVE.
---@param state table<string, any>
local function startToLive(state)
    assert(match().Start(state.mode), "Start failed")
    expire(state)
    expire(state)
    assert(match().GetPhase() == "LIVE", "not LIVE")
end

---LIVE -> POSTMATCH -> LOBBY (pw_aftermatch "lobby").
---@param state table<string, any>
local function finishToLobby(state)
    assert(match().Finish(), "Finish failed")
    expire(state)
    assert(match().GetPhase() == "LOBBY", "not LOBBY")
end

---@param name string
---@param identifier any
---@return boolean
local function isSubscribed(name, identifier)
    local listeners = hook.GetTable()[name] --[[@as table<any, function>?]]
    return listeners ~= nil and listeners[identifier] ~= nil
end

---@param entity PW.Entity
---@return boolean
local function valid(entity)
    return must(entity.IsValid)(entity)
end

return {
    groupName = "PW enable ConVars",
    beforeEach = function(state)
        state.previousEnable = PW._Enable
        state.previousMatch = PW._Match
        state.previousCall = PW._Call
        state.previousMode = PW.ActiveMode
        state.saved = {}
        state.registries = {}
        state.map = {}
        state.now = 1000
        state.created = {}
        local map = state.map --[[@as table<string, PW.Registry>]]
        PW._Enable = enable()._NewStore({ registries = function() return map end })
        PW._Call = { log = function() end, failed = setmetatable({}, { __mode = "k" }), profile = {} }
        PW._Match = match()._NewStore({
            log = function() end,
            clock = function() return state.now end,
            players = function() return {} end,
            settings = function()
                local settings = match()._ReadSettings()
                settings.prematch = 60
                settings.countdown = 10
                settings.postmatch = 15
                settings.vote = 15
                settings.afterMatch = "lobby"
                return settings
            end
        })
        PW.ActiveMode = nil
        state.mode = newMode(state)
    end,
    afterEach = function(state)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        for identifier in pairs(hook.GetTable()[subHook] or {}) do hook.Remove(subHook, identifier) end
        hook.Remove("PW_PhaseChange", listenerId)
        for convar, value in pairs(state.saved --[[@as table<ConVar, string>]]) do convar:SetString(value) end
        PW._Enable = state.previousEnable
        PW._Match = state.previousMatch
        PW._Call = state.previousCall
        PW.ActiveMode = state.previousMode
    end,
    cases = {
        {
            -- FCVAR_ARCHIVE is passed like the other pw_* ConVars, but GMod does not report it in GetFlags for Lua
            -- ConVars on the server (pw_aftermatch reads false as well), so the flag itself is not asserted.
            name = "Every entity gets pw_<kind>_<id>_enabled (default 1); abstract entities get none",
            func = function(state)
                newRegistry(state, { alpha = {}, beta = {}, base = { Abstract = true } })
                for _, id in ipairs({ "alpha", "beta" }) do
                    local convar = must(GetConVar(varName(id)))
                    expect(convar:GetDefault()).to.equal("1")
                    expect(convar:GetBool()).to.beTrue()
                end
                expect(GetConVar(varName("base"))).to.beNil()
            end
        },
        {
            name = "Every entity of the booted registries has its enable ConVar",
            func = function()
                ---@type string[]
                local missing = {}
                for kindId, registry in pairs(PW.Registries) do
                    local token = enable()._KindToken(PW.Registries, kindId)
                    for _, entity in ipairs(registry.GetList()) do
                        local name = enable()._ConVarName(token, entity.ClassName)
                        if GetConVar(name) == nil then missing[#missing + 1] = name end
                    end
                end
                expect(table.concat(missing, ",")).to.equal("")
            end
        },
        {
            name = "Names: modules -> pw_module_<id>_enabled, kinds -> pw_kind_<id>, declared kind -> its Global",
            func = function()
                local kinds = PW.Registry.New("kinds", { log = function() end, preRegister = function() end })
                kinds.Register({ Folder = "modes", Global = "MODE" }, "modes")
                kinds.ResolveAll()
                local map = { kinds = kinds }
                expect(enable()._KindToken(map, "modules")).to.equal("module")
                expect(enable()._KindToken(map, "kinds")).to.equal("kind")
                expect(enable()._KindToken(map, "modes")).to.equal("mode")
                expect(enable()._KindToken(map, "undeclared")).to.equal("undeclared")
                expect(enable()._ConVarName("mode", "kc")).to.equal("pw_mode_kc_enabled")
                kinds._Release()
            end
        },
        {
            name = "Public ConVarName: the enable ConVar of an entity of a known kind; nil for an unknown kind",
            func = function(state)
                newRegistry(state, { alpha = {} })
                expect(enable().ConVarName(testKind, "alpha")).to.equal(varName("alpha"))
                expect(enable().ConVarName("pwtest_no_such_kind", "alpha")).to.beNil()
            end
        },
        {
            name = "A late registration gets its ConVar at once; ensuring again creates no duplicate",
            func = function(state)
                ---@type string[]
                local created = {}
                local map = state.map --[[@as table<string, PW.Registry>]]
                PW._Enable = enable()._NewStore({
                    registries = function() return map end,
                    create = function(name) created[#created + 1] = name end,
                    exists = function(name)
                        for _, seen in ipairs(created) do if seen == name then return true end end
                        return false
                    end
                })
                local registry = newRegistry(state, { alpha = {} })
                expect(table.concat(created, ",")).to.equal(varName("alpha"))
                registry.Register({}, "late")
                expect(table.concat(created, ",")).to.equal(varName("alpha") .. "," .. varName("late"))
                enable()._EnsureConVars()
                expect(#created).to.equal(2)
            end
        },
        {
            name = "Snapshot (pure): ids whose flag reads false, by kind; abstract entities are not read",
            func = function(state)
                local registry = newRegistry(state, { alpha = {}, beta = {}, base = { Abstract = true } })
                ---@type string[]
                local read = {}
                local snapshot = enable()._TakeSnapshot({ [testKind] = registry }, function(name)
                    read[#read + 1] = name
                    return name ~= varName("beta")
                end)
                table.sort(read)
                expect(table.concat(read, ",")).to.equal(varName("alpha") .. "," .. varName("beta"))
                expect(must(snapshot[testKind]).beta).to.beTrue()
                expect(must(snapshot[testKind]).alpha).to.beNil()
            end
        },
        {
            name = "A disabled entity is absent from lists after the next LOBBY -> PREMATCH",
            func = function(state)
                local registry = newRegistry(state, { alpha = {}, beta = {} })
                setFlag(state, "beta", false)
                expect(ids(registry.GetEnabledList())).to.equal("alpha,beta")
                ---@type string[]
                local seen = {}
                hook.Add("PW_PhaseChange", listenerId, function(to)
                    if to == "PREMATCH" then seen[#seen + 1] = ids(registry.GetEnabledList()) end
                end)
                assert(match().Start(state.mode), "Start failed")
                expect(ids(registry.GetEnabledList())).to.equal("alpha")
                expect(seen[1]).to.equal("alpha")
                expect(ids(registry.GetList())).to.equal("alpha,beta")
                expect(registry._DisabledReason("beta")).to.equal(enable()._Reason)
                expect(valid(must(registry.Get("beta")))).to.beFalse()
            end
        },
        {
            name = "Changing the ConVar during LIVE does not change the current match's snapshot",
            func = function(state)
                local registry = newRegistry(state, { alpha = {}, beta = {} })
                startToLive(state)
                setFlag(state, "alpha", false)
                expect(ids(registry.GetEnabledList())).to.equal("alpha,beta")
                expect(valid(must(registry.Get("alpha")))).to.beTrue()
                finishToLobby(state)
                expect(ids(registry.GetEnabledList())).to.equal("alpha,beta")
                assert(match().Start(state.mode), "Start failed")
                expect(ids(registry.GetEnabledList())).to.equal("beta")
            end
        },
        {
            name = "Re-enabling the ConVar brings the entity back at the next match",
            func = function(state)
                local registry = newRegistry(state, { alpha = {} })
                setFlag(state, "alpha", false)
                startToLive(state)
                expect(ids(registry.GetEnabledList())).to.equal("")
                setFlag(state, "alpha", true)
                finishToLobby(state)
                assert(match().Start(state.mode), "Start failed")
                expect(ids(registry.GetEnabledList())).to.equal("alpha")
                expect(registry._DisabledReason("alpha")).to.beNil()
            end
        },
        {
            name = "Disabling an entity through its enable ConVar removes its subscriptions (IsValid false)",
            func = function(state)
                local calls = 0
                local registry = newRegistry(state, { alpha = { [subHook] = function() calls = calls + 1 end } },
                    "always")
                local entity = must(registry.Get("alpha"))
                expect(isSubscribed(subHook, entity)).to.beTrue()
                setFlag(state, "alpha", false)
                assert(match().Start(state.mode), "Start failed")
                expect(valid(entity)).to.beFalse()
                expect(isSubscribed(subHook, entity)).to.beFalse()
                hook.Run(subHook)
                expect(calls).to.equal(0)
            end
        },
        {
            name = "An entity disabled after an error is not re-enabled by its ConVar",
            func = function(state)
                local registry = newRegistry(state, { alpha = { Boom = function() error("boom") end } })
                PW.Call(must(registry.Get("alpha")), "Boom")
                local reason = must(registry._DisabledReason("alpha"))
                expect(string.find(reason, "boom", 1, true)).to.exist()
                setFlag(state, "alpha", false)
                startToLive(state)
                expect(registry._DisabledReason("alpha")).to.equal(reason)
                setFlag(state, "alpha", true)
                finishToLobby(state)
                assert(match().Start(state.mode), "Start failed")
                expect(registry._DisabledReason("alpha")).to.equal(reason)
                expect(ids(registry.GetEnabledList())).to.equal("")
            end
        },
        {
            name = "Boot takes a snapshot when there is none and re-applies the existing one (pw_reload mid-match)",
            func = function(state)
                local registry = newRegistry(state, { alpha = {} })
                setFlag(state, "alpha", false)
                enable()._OnBoot()
                expect(ids(registry.GetEnabledList())).to.equal("")
                setFlag(state, "alpha", true)
                local fresh = PW.Registry.New(testKind, { log = function() end, preRegister = function() end })
                local registries = state.registries --[[@as PW.Registry[] ]]
                registries[#registries + 1] = fresh
                fresh.Register({}, "alpha")
                fresh.ResolveAll()
                local map = state.map --[[@as table<string, PW.Registry>]]
                map[testKind] = fresh
                enable()._OnBoot()
                expect(ids(fresh.GetEnabledList())).to.equal("")
            end
        }
    }
}
