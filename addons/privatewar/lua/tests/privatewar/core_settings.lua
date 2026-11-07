-- T-1.5 settings schema (TASKS.md, "Mandatory test cases" T-1.5; 01-extensibility.md d.17; 02-modes.md d.7).
-- Every case swaps in a fresh settings store over isolated test registries ("modes" and "modules" built here, with
-- fake ConVars), a fresh enable store, phase machine store (fake clock) and PW.Call store, and restores all of them
-- and PW.ActiveMode afterwards, so the real machine stays in LOBBY and no real ConVar is touched.

local listenerId = "PW_Test_Settings"

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---The first of several values (a call's extra results dropped).
---@param value any
---@return any
local function first(value)
    return value
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@return PW.SettingsLib
local function settings()
    return PW.Settings
end

---@return table<string, table>
local function modeDefs()
    return {
        pwt_tdm = { Name = "TDM", Teams = 2, Settings = {
            scorelimit = { type = "int", default = 75, min = 10, max = 1000, label = "#pw.set.scorelimit" },
            timelimit = { type = "int", default = 600, min = 0, max = 3600 }
        } },
        pwt_kc = { Name = "KC", Base = "pwt_tdm", Settings = {
            scorelimit = { default = 65 },
            tags = { type = "set", default = {}, options = { "a", "b" } }
        } },
        pwt_hc = { Name = "HC", Base = "pwt_tdm", SettingDefaults = { ["pwt_health.friendlyfire"] = true } },
        pwt_base = { Abstract = true, Settings = { hidden = { type = "bool", default = true } } }
    }
end

---@return table<string, table>
local function moduleDefs()
    return {
        pwt_bots = { Settings = {
            count = { scope = "match", type = "int", default = 6, min = 0, max = 16 },
            difficulty = { type = "enum", default = "regular", options = { "recruit", "regular", "veteran" } },
            budget = { scope = "server", type = "float", default = 2, min = 0.5, max = 10 },
            hudscale = { scope = "client", type = "float", default = 1, min = 0.5, max = 2 }
        } },
        pwt_health = { Settings = { friendlyfire = { type = "bool", default = false } } },
        pwt_plain = {}
    }
end

---@param state table<string, any>
---@param kind string
---@param defs table<string, table>
---@return PW.Registry
local function newRegistry(state, kind, defs)
    local registry = PW.Registry.New(kind, { log = function() end, preRegister = function() end,
        methods = settings().EntityMethods })
    for id, def in pairs(defs) do registry.Register(def, id) end
    registry.ResolveAll()
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    return registry
end

---@param state table<string, any>
---@return PW.Registry
local function modes(state)
    return state.map.modes --[[@as PW.Registry]]
end

---@param state table<string, any>
---@return PW.Registry
local function modules(state)
    return state.map.modules --[[@as PW.Registry]]
end

---@param state table<string, any>
---@param needle string
---@return integer
local function mentions(state, needle)
    local count = 0
    for _, line in ipairs(state.logged --[[@as string[] ]]) do
        if string.find(line, needle, 1, true) then count = count + 1 end
    end
    return count
end

---A validation result as one comparable table.
---@param def PW.SettingDef
---@param value any
---@return table<string, any>
local function check(def, value)
    local ok, stored, note = settings()._Validate(def, value)
    return { ok = ok, value = stored, note = note }
end

---@param decl table<string, any>
---@return PW.SettingDef
local function def(decl)
    local result, err = settings()._CheckDef("pwt_owner", "modules", "key", decl)
    assert(result ~= nil, "declaration rejected: " .. tostring(err))
    return result
end

---Moves the fake clock to the end of the current phase and runs one machine step.
---@param state table<string, any>
local function expire(state)
    state.now = PW._Match.endsAt
    match()._Tick()
end

---@param state table<string, any>
---@param mode table
local function startToLive(state, mode)
    assert(match().Start(mode), "Start failed")
    expire(state)
    expire(state)
    assert(match().GetPhase() == "LIVE", "not LIVE")
end

return {
    groupName = "PW settings",
    beforeEach = function(state)
        state.previousSettings = PW._Settings
        state.previousEnable = PW._Enable
        state.previousMatch = PW._Match
        state.previousCall = PW._Call
        state.previousMode = PW.ActiveMode
        state.registries = {}
        state.logged = {}
        state.convars = {}
        state.now = 1000
        local map = {
            modes = newRegistry(state, "modes", modeDefs()),
            modules = newRegistry(state, "modules", moduleDefs())
        }
        state.map = map
        local convars = state.convars --[[@as table<string, string>]]
        local logged = state.logged --[[@as string[] ]]
        PW._Settings = settings()._NewStore({
            registries = function() return map end,
            log = function(message) logged[#logged + 1] = message end,
            convars = {
                read = function(name) return convars[name] end,
                write = function(name, text)
                    if convars[name] == nil then return false end
                    convars[name] = text
                    return true
                end,
                create = function(created) convars[settings()._ConVarName(created)] = "" end
            }
        })
        PW._Enable = must(PW.Enable)._NewStore({ registries = function() return {} end })
        PW._Call = { log = function() end, failed = setmetatable({}, { __mode = "k" }), profile = {} }
        PW._Match = match()._NewStore({
            log = function() end,
            clock = function() return state.now end,
            players = function() return {} end,
            settings = function()
                return { prematch = 60, countdown = 10, postmatch = 15, vote = 15, afterMatch = "lobby" }
            end
        })
        PW.ActiveMode = nil
    end,
    afterEach = function(state)
        hook.Remove("PW_PhaseChange", listenerId)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        PW._Settings = state.previousSettings
        PW._Enable = state.previousEnable
        PW._Match = state.previousMatch
        PW._Call = state.previousCall
        PW.ActiveMode = state.previousMode
    end,
    cases = {
        {
            name = "int: valid accepted, fraction rounded, out-of-range clamped, wrong type rejected",
            func = function()
                local int = def({ type = "int", default = 5, min = 0, max = 10 })
                expect(check(int, 7)).to.deepEqual({ ok = true, value = 7 })
                expect(check(int, 3.6)).to.deepEqual({ ok = true, value = 4 })
                expect(check(int, 15)).to.deepEqual({ ok = true, value = 10, note = "clamped" })
                expect(check(int, -1)).to.deepEqual({ ok = true, value = 0, note = "clamped" })
                expect(check(int, "7").ok).to.beFalse()
                expect(check(int, true).ok).to.beFalse()
                expect(check(int, 0 / 0).ok).to.beFalse()
                expect(check(int, math.huge).ok).to.beFalse()
            end
        },
        {
            name = "float: valid accepted, out-of-range clamped, wrong type rejected",
            func = function()
                local float = def({ type = "float", default = 2, min = 0.5, max = 10 })
                expect(check(float, 2.25)).to.deepEqual({ ok = true, value = 2.25 })
                expect(check(float, 11)).to.deepEqual({ ok = true, value = 10, note = "clamped" })
                expect(check(float, 0.1)).to.deepEqual({ ok = true, value = 0.5, note = "clamped" })
                expect(check(float, "2").ok).to.beFalse()
                expect(check(float, 0 / 0).ok).to.beFalse()
            end
        },
        {
            name = "bool: true and false accepted, wrong type rejected (no range to clamp)",
            func = function()
                local bool = def({ type = "bool", default = false })
                expect(check(bool, true)).to.deepEqual({ ok = true, value = true })
                expect(check(bool, false)).to.deepEqual({ ok = true, value = false })
                expect(check(bool, 1).ok).to.beFalse()
                expect(check(bool, "true").ok).to.beFalse()
            end
        },
        {
            name = "enum: a declared option accepted, unknown option rejected, wrong type rejected",
            func = function()
                local enum = def({ type = "enum", default = "regular", options = { "recruit", "regular" } })
                expect(check(enum, "recruit")).to.deepEqual({ ok = true, value = "recruit" })
                local unknown = check(enum, "godlike")
                expect(unknown.ok).to.beFalse()
                expect(string.find(unknown.note, "unknown option", 1, true)).to.exist()
                expect(check(enum, 1).ok).to.beFalse()
                expect(check(enum, nil).ok).to.beFalse()
            end
        },
        {
            name = "set: list or lookup accepted, normalized; unknown or invalid member rejected; wrong type rejected",
            func = function()
                local set = def({ type = "set", default = {}, options = { "a", "b", "c" } })
                expect(check(set, { "a", "c" })).to.deepEqual({ ok = true, value = { a = true, c = true } })
                expect(check(set, { b = true })).to.deepEqual({ ok = true, value = { b = true } })
                expect(check(set, {})).to.deepEqual({ ok = true, value = {} })
                expect(check(set, { "a", "z" }).ok).to.beFalse()
                expect(check(set, { a = 1 }).ok).to.beFalse()
                expect(check(set, { "" }).ok).to.beFalse()
                expect(check(set, "a").ok).to.beFalse()
                local free = def({ type = "set", default = { "x" } })
                expect(check(free, { "anything" })).to.deepEqual({ ok = true, value = { anything = true } })
            end
        },
        {
            name = "Wire strings parse per type and format back",
            func = function()
                local int = def({ type = "int", default = 5, min = 0, max = 10 })
                local bool = def({ type = "bool", default = false })
                local set = def({ type = "set", default = {} })
                expect({ settings()._Parse(int, "12") }).to.deepEqual({ true, 10, "clamped" })
                expect(first(settings()._Parse(int, "abc"))).to.beFalse()
                expect({ settings()._Parse(bool, "1") }).to.deepEqual({ true, true })
                expect({ settings()._Parse(bool, "false") }).to.deepEqual({ true, false })
                expect(first(settings()._Parse(bool, "maybe"))).to.beFalse()
                expect({ settings()._Parse(set, "b, a") }).to.deepEqual({ true, { a = true, b = true } })
                expect({ settings()._Parse(set, "") }).to.deepEqual({ true, {} })
                expect(settings()._Format(set, { b = true, a = true })).to.equal("a,b")
                expect(settings()._Format(bool, true)).to.equal("1")
                expect(settings()._Format(int, 7)).to.equal("7")
            end
        },
        {
            name = "Invalid declarations are rejected with a reason (type, default, options, range, mode scope)",
            func = function()
                local checkDef = settings()._CheckDef
                expect(first(checkDef("o", "modules", "k", { type = "text", default = "" }))).to.beNil()
                expect(first(checkDef("o", "modules", "k", { type = "int", default = 50, max = 10 }))).to.beNil()
                expect(first(checkDef("o", "modules", "k", { type = "enum", default = "a" }))).to.beNil()
                expect(first(checkDef("o", "modules", "k", { type = "int", default = 1, min = 5, max = 0 }))).to.beNil()
                expect(first(checkDef("o", "modules", "k", { type = "int", default = 1, scope = "global" }))).to.beNil()
                expect(first(checkDef("o", "modules", "Bad.Key", { type = "int", default = 1 }))).to.beNil()
                expect(first(checkDef("o", "modes", "k", { type = "int", default = 1, scope = "server" }))).to.beNil()
                local ok = must(checkDef("o", "modes", "k", { type = "int", default = 1 }))
                expect(ok.scope).to.equal("match")
                expect(ok.id).to.equal("o.k")
            end
        },
        {
            name = "A declaration keeps an optional description; a non-string description is rejected",
            func = function()
                local checkDef = settings()._CheckDef
                local described = must(checkDef("o", "modules", "k",
                    { type = "bool", default = true, label = "K", description = "What k trades" }))
                expect(described.description).to.equal("What k trades")
                expect(must(checkDef("o", "modules", "k", { type = "bool", default = true })).description).to.beNil()
                local bad, reason = checkDef("o", "modules", "k", { type = "bool", default = true, description = 5 })
                expect(bad).to.beNil()
                expect(reason).to.equal("the description must be a string")
            end
        },
        {
            name = "Inherited settings and overridden defaults through Base",
            func = function(state)
                local kc = must(modes(state).Get("pwt_kc"))
                local schema = settings()._Schema(kc, "modes", function() end)
                local scorelimit = must(schema.scorelimit)
                expect(scorelimit.id).to.equal("pwt_kc.scorelimit")
                expect(scorelimit.default).to.equal(65)
                expect(scorelimit.max).to.equal(1000)
                expect(scorelimit.label).to.equal("#pw.set.scorelimit")
                expect(must(schema.timelimit).default).to.equal(600)
                expect(must(schema.tags).type).to.equal("set")
                expect(PW.Setting("pwt_kc.scorelimit")).to.equal(65)
                expect(PW.Setting("pwt_kc.timelimit")).to.equal(600)
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(75)
                expect(PW.Setting("pwt_tdm.tags")).to.beNil()
                expect(kc:Setting("scorelimit")).to.equal(65)
            end
        },
        {
            name = "MODE.SettingDefaults overrides a module's match default for that mode only",
            func = function(state)
                local enabled = modules(state).GetEnabledList()
                local hc = settings()._TakeSnapshot(must(modes(state).Get("pwt_hc")), enabled, {}, function() end)
                local tdm = settings()._TakeSnapshot(must(modes(state).Get("pwt_tdm")), enabled, {}, function() end)
                expect(hc["pwt_health.friendlyfire"]).to.beTrue()
                expect(tdm["pwt_health.friendlyfire"]).to.beFalse()
                expect(hc["pwt_hc.scorelimit"]).to.equal(75)
                expect(hc["pwt_bots.count"]).to.equal(6)
                expect(hc["pwt_bots.budget"]).to.beNil()
                local edited = settings()._TakeSnapshot(must(modes(state).Get("pwt_hc")), enabled,
                    { ["pwt_health.friendlyfire"] = false }, function() end)
                expect(edited["pwt_health.friendlyfire"]).to.beFalse()
            end
        },
        {
            name = "Public Format takes a definition or a full id; an unknown id gives nil",
            func = function()
                expect(settings().Format(def({ type = "bool", default = false }), true)).to.equal("1")
                expect(settings().Format("pwt_tdm.scorelimit", 80)).to.equal("80")
                expect(settings().Format("pwt_nope.key", 1)).to.beNil()
            end
        },
        {
            name = "Full ids resolve for modes and modules of every scope; an unknown id is reported once",
            func = function(state)
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(75)
                expect(PW.Setting("pwt_bots.count")).to.equal(6)
                expect(PW.Setting("pwt_bots.difficulty")).to.equal("regular")
                expect(PW.Setting("pwt_bots.budget")).to.equal(2)
                expect(must(modules(state).Get("pwt_bots")):Setting("count")).to.equal(6)
                expect(PW.Setting("pwt_nope.key")).to.beNil()
                expect(PW.Setting("pwt_nope.key")).to.beNil()
                expect(PW.Setting("nodot")).to.beNil()
                expect(PW.Setting("pwt_base.hidden")).to.beNil()
                expect(mentions(state, "unknown setting \"pwt_nope.key\"")).to.equal(1)
                expect(mentions(state, "unknown setting \"nodot\"")).to.equal(1)
            end
        },
        {
            name = "Server settings read and write their ConVar; a bad ConVar value reads as the default",
            func = function(state)
                settings()._OnBoot()
                local convars = state.convars --[[@as table<string, string>]]
                expect(convars.pw_pwt_bots_budget).to.equal("")
                expect(convars.pw_pwt_bots_count).to.beNil()
                expect(settings().Set("pwt_bots.budget", 50)).to.beTrue()
                expect(convars.pw_pwt_bots_budget).to.equal("10")
                expect(PW.Setting("pwt_bots.budget")).to.equal(10)
                convars.pw_pwt_bots_budget = "junk"
                expect(PW.Setting("pwt_bots.budget")).to.equal(2)
                expect(first(settings().Set("pwt_bots.hudscale", 1))).to.beFalse()
                expect(first(settings().Set("pwt_bots.budget", "x"))).to.beFalse()
                expect(first(settings().Set("pwt_nope.key", 1))).to.beFalse()
            end
        },
        {
            name = "Match snapshot is taken on LOBBY -> PREMATCH and is immutable during the match",
            func = function(state)
                local tdm = must(modes(state).Get("pwt_tdm"))
                expect(settings().Set("pwt_tdm.scorelimit", 100)).to.beTrue()
                expect(settings().Set("pwt_bots.count", 3)).to.beTrue()
                ---@type any[]
                local seen = {}
                hook.Add("PW_PhaseChange", listenerId, function(to)
                    if to == "PREMATCH" then seen[#seen + 1] = PW.Setting("pwt_tdm.scorelimit") end
                end)
                startToLive(state, tdm)
                expect(seen[1]).to.equal(100)
                expect(settings().Set("pwt_tdm.scorelimit", 200)).to.beTrue()
                expect(settings().Set("pwt_bots.count", 9)).to.beTrue()
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(100)
                expect(tdm:Setting("scorelimit")).to.equal(100)
                expect(PW.Setting("pwt_bots.count")).to.equal(3)
                assert(match().Finish(), "Finish failed")
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(100)
                expire(state)
                assert(match().GetPhase() == "LOBBY", "not LOBBY")
                expect(PW._Settings.snapshot).to.beNil()
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(200)
                assert(match().Start(tdm), "Start failed")
                expect(settings().Set("pwt_tdm.scorelimit", 300)).to.beTrue()
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(200)
                expect(PW.Setting("pwt_bots.count")).to.equal(9)
            end
        },
        {
            name = "A snapshot set is a copy: changing the returned table does not change the match",
            func = function(state)
                local kc = must(modes(state).Get("pwt_kc"))
                expect(settings().Set("pwt_kc.tags", { "a" })).to.beTrue()
                assert(match().Start(kc), "Start failed")
                local tags = PW.Setting("pwt_kc.tags") --[[@as table<string, boolean>]]
                tags.b = true
                expect(PW.Setting("pwt_kc.tags")).to.deepEqual({ a = true })
            end
        },
        {
            name = "Form groups: the mode group first, then enabled modules with settings of the scope",
            func = function(state)
                local hc = must(modes(state).Get("pwt_hc"))
                expect(settings().Set("pwt_bots.count", 4)).to.beTrue()
                local groups = settings().GetGroups("match", hc)
                ---@type string[]
                local owners = {}
                for index, group in ipairs(groups) do owners[index] = group.owner end
                expect(table.concat(owners, ",")).to.equal("pwt_hc,pwt_bots,pwt_health")
                local bots = must(groups[2])
                expect(must(bots.fields[1]).def.key).to.equal("count")
                expect(must(bots.fields[1]).value).to.equal(4)
                expect(must(bots.fields[2]).def.key).to.equal("difficulty")
                expect(must(must(groups[3]).fields[1]).value).to.beTrue()
                local server = settings().GetGroups("server")
                expect(#server).to.equal(1)
                expect(must(must(server[1]).fields[1]).def.id).to.equal("pwt_bots.budget")
                modules(state)._Disable("pwt_health", "test")
                expect(#settings().GetGroups("match", hc)).to.equal(2)
            end
        },
        {
            name = "The real modes kind loads: PW.Modes exists after Boot, MODE needs Name and Teams, never subscribed",
            func = function()
                local real = must(PW.Registries.modes)
                expect(PW.Modes).to.equal(real)
                local kind = must(PW.Kinds.Get("modes"))
                expect(kind.Folder).to.equal("modes")
                expect(kind.Global).to.equal("MODE")
                expect(kind.Subscribe).to.equal("never")
                expect(kind.Required).to.deepEqual({ Name = "string", Teams = "number" })
                expect(first(PW.Loader.ValidateRequired({ Name = "X" }, kind.Required))).to.beFalse()
                expect(first(PW.Loader.ValidateRequired({ Name = "X", Teams = 0 }, kind.Required))).to.beTrue()
                for _, listeners in pairs(hook.GetTable() --[[@as table<string, table<any, any>>]]) do
                    for identifier in pairs(listeners) do
                        local entity = istable(identifier) and identifier._Registry or nil
                        expect(entity == real).to.beFalse()
                    end
                end
            end
        }
    }
}
