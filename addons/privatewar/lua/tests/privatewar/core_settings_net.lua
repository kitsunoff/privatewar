-- T-1.5 settings over the wire and across a map change (TASKS.md, "Mandatory test cases" T-1.5: a non-privileged
-- sender cannot change match or server settings; 00-core.md d.7, d.8, d.9). A bot is a player: the cases call the
-- receive path (PW.Net._Dispatch) with a bot as sender, and the store's readChange stands in for net.ReadString.
-- Every case swaps in a fresh settings store over isolated test registries with fake ConVars, a fresh net store
-- with the real settings messages registered into it, a fresh phase machine, enable, PW.Call and map change store
-- (test-only DATA path, changelevel only recorded), and restores all of them; the pool bots are kicked after the
-- group, so the real machine stays in LOBBY.

local testPath = "privatewar/pw_test_settings_pending.json"
local currentMap = "gm_pw_test_here"
local otherMap = "gm_pw_test_there"

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

---@return PW.MapChangeLib
local function changer()
    return must(PW.MapChange)
end

---Returns pool bot "a" or "b" with the given usergroup (created once per group: a kicked bot frees its slot late).
---@param state table<string, any>
---@param key "a"|"b"
---@param group string
---@return Player
local function makeBot(state, key, group)
    local pool = state.pool --[[@as table<string, Player>]]
    local bot = pool[key]
    if bot == nil or not IsValid(bot) then
        bot = player.CreateNextBot("PW settings test " .. key)
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        pool[key] = bot
    end
    bot:SetUserGroup(group)
    return bot
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
---@return PW.Mode
local function tdm(state)
    return must((state.map.modes --[[@as PW.Registry]]).Get("pwt_tdm")) --[[@as PW.Mode]]
end

---@param state table<string, any>
---@param registries table<string, PW.Registry>
local function installSettings(state, registries)
    local convars = state.convars --[[@as table<string, string>]]
    local logged = state.logged --[[@as string[] ]]
    PW._Settings = settings()._NewStore({
        registries = function() return registries end,
        log = function(message) logged[#logged + 1] = message end,
        convars = {
            read = function(name) return convars[name] end,
            write = function(name, text)
                if convars[name] == nil then return false end
                convars[name] = text
                return true
            end,
            create = function(def) convars[settings()._ConVarName(def)] = settings()._Format(def, def.default) end
        },
        readChange = function()
            local change = state.change --[[@as string[] ]]
            return change[1], change[2]
        end
    })
    settings()._OnBoot()
end

---@param state table<string, any>
---@param map string
---@param count integer
local function installMapChange(state, map, count)
    PW._MapChange = changer()._NewStore({
        path = testPath,
        log = function() end,
        clock = function() return state.now end,
        time = function() return state.time end,
        map = function() return map end,
        mapChangeCount = function() return count end,
        delay = function() return 0 end, -- the delayed change has its own cases (match_flow_ui.lua)
        bots = function() return 0 end,
        resolveMode = function(id) return id == "pwt_tdm" and tdm(state) or nil end,
        changelevel = function(target)
            local calls = state.changelevels --[[@as table[] ]]
            calls[#calls + 1] = { map = target, text = file.Read(testPath, "DATA") }
        end,
        ack = function() end
    })
end

---Sends one settings change from ply through the real wrapper (2 s after the previous one).
---@param state table<string, any>
---@param name string
---@param ply Player
---@param id string
---@param text string
---@return boolean
---@return string?
local function send(state, name, ply, id, text)
    state.change = { id, text }
    local now = state.now --[[@as number]]
    state.now = now + 2
    return must(PW.Net)._Dispatch(name, 64, ply)
end

---@param state table<string, any>
---@return table<string, string>
local function convars(state)
    return state.convars --[[@as table<string, string>]]
end

return {
    groupName = "PW settings net and map change",
    beforeAll = function(state)
        state.pool = {}
    end,
    afterAll = function(state)
        for _, bot in pairs(state.pool --[[@as table<string, Player>]]) do
            if IsValid(bot) then bot:Kick("PW settings test finished") end
        end
    end,
    beforeEach = function(state)
        state.previousSettings = PW._Settings
        state.previousNet = PW._Net
        state.previousMatch = PW._Match
        state.previousEnable = PW._Enable
        state.previousCall = PW._Call
        state.previousChange = PW._MapChange
        state.previousMode = PW.ActiveMode
        state.registries = {}
        state.logged = {}
        state.convars = {}
        state.changelevels = {}
        state.now = 1000
        state.time = 1800000000
        local map = {
            modes = newRegistry(state, "modes", { pwt_tdm = { Name = "TDM", Teams = 2, Settings = {
                scorelimit = { type = "int", default = 75, min = 10, max = 1000 },
                tags = { type = "set", default = {} }
            } } }),
            modules = newRegistry(state, "modules", { pwt_bots = { Settings = {
                count = { type = "int", default = 6, min = 0, max = 16 },
                budget = { scope = "server", type = "float", default = 2, min = 0.5, max = 10 }
            } } })
        }
        state.map = map
        installSettings(state, map)
        PW._Net = must(PW.Net)._NewStore({ log = function() end, clock = function() return state.now end })
        must(settings()._RegisterNet)()
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
        installMapChange(state, currentMap, 5)
        PW.ActiveMode = nil
    end,
    afterEach = function(state)
        if file.Exists(testPath, "DATA") then file.Delete(testPath) end
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        PW._Settings = state.previousSettings
        PW._Net = state.previousNet
        PW._Match = state.previousMatch
        PW._Enable = state.previousEnable
        PW._Call = state.previousCall
        PW._MapChange = state.previousChange
        PW.ActiveMode = state.previousMode
    end,
    cases = {
        {
            name = "The change privilege is declared with the superadmin default",
            func = function()
                expect(settings().Privilege).to.equal("pw.settings.change")
                expect(must(PW._Privileges.defs[settings().Privilege]).MinAccess).to.equal("superadmin")
            end
        },
        {
            name = "A non-privileged sender cannot change a match setting; a privileged one can (clamped)",
            func = function(state)
                local user = makeBot(state, "a", "user")
                local admin = makeBot(state, "b", "superadmin")
                expect({ send(state, "pw_settings_match", user, "pwt_tdm.scorelimit", "300") })
                    .to.deepEqual({ false, "privilege" })
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(75)
                expect(first(send(state, "pw_settings_match", admin, "pwt_tdm.scorelimit", "300"))).to.beTrue()
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(300)
                expect(first(send(state, "pw_settings_match", admin, "pwt_tdm.scorelimit", "5000"))).to.beTrue()
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(1000)
                expect(first(send(state, "pw_settings_match", admin, "pwt_tdm.tags", "x,y"))).to.beTrue()
                expect(PW.Setting("pwt_tdm.tags")).to.deepEqual({ x = true, y = true })
            end
        },
        {
            name = "A non-privileged sender cannot change a server setting; a privileged one can in any phase",
            func = function(state)
                local user = makeBot(state, "a", "user")
                local admin = makeBot(state, "b", "superadmin")
                PW._Match.phase = "LIVE"
                expect({ send(state, "pw_settings_server", user, "pwt_bots.budget", "5") })
                    .to.deepEqual({ false, "privilege" })
                expect(convars(state).pw_pwt_bots_budget).to.equal("2")
                expect(first(send(state, "pw_settings_server", admin, "pwt_bots.budget", "5"))).to.beTrue()
                expect(convars(state).pw_pwt_bots_budget).to.equal("5")
                expect(PW.Setting("pwt_bots.budget")).to.equal(5)
            end
        },
        {
            name = "Match changes only in LOBBY; scope mismatch, unknown id and invalid value change nothing",
            func = function(state)
                local admin = makeBot(state, "b", "superadmin")
                PW._Match.phase = "LIVE"
                expect({ send(state, "pw_settings_match", admin, "pwt_tdm.scorelimit", "300") })
                    .to.deepEqual({ false, "phase" })
                PW._Match.phase = "LOBBY"
                send(state, "pw_settings_server", admin, "pwt_tdm.scorelimit", "300")
                send(state, "pw_settings_match", admin, "pwt_bots.budget", "5")
                send(state, "pw_settings_match", admin, "pwt_nope.key", "1")
                send(state, "pw_settings_match", admin, "pwt_tdm.scorelimit", "lots")
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(75)
                expect(convars(state).pw_pwt_bots_budget).to.equal("2")
                expect(#state.logged >= 4).to.beTrue()
            end
        },
        {
            name = "A pending match file round-trips the match settings snapshot across a map change",
            func = function(state)
                expect(settings().Set("pwt_tdm.scorelimit", 120)).to.beTrue()
                expect(settings().Set("pwt_bots.count", 2)).to.beTrue()
                expect(settings().Set("pwt_tdm.tags", { "b", "a" })).to.beTrue()
                expect(match().Start(tdm(state), otherMap)).to.beTrue()
                local call = must((state.changelevels --[[@as table[] ]])[1]) --[[@as { text: string? }]]
                local written = must(changer()._Decode(must(call.text)))
                expect(written.settings).to.deepEqual({
                    ["pwt_tdm.scorelimit"] = 120, ["pwt_tdm.tags"] = { a = true, b = true }, ["pwt_bots.count"] = 2
                })
                -- The new map: a fresh Lua state (fresh settings store), the file's facts match.
                installSettings(state, state.map --[[@as table<string, PW.Registry>]])
                installMapChange(state, otherMap, 6)
                local before = state.time --[[@as integer]]
                state.time = before + 5
                expect(first(changer()._Apply())).to.beTrue()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(120)
                expect(PW.Setting("pwt_bots.count")).to.equal(2)
                expect(PW.Setting("pwt_tdm.tags")).to.deepEqual({ a = true, b = true })
            end
        },
        {
            name = "Invalid values in a pending file are dropped with a log line; valid ones still apply",
            func = function(state)
                local restore = must(settings()._FromFile)
                restore({ ["pwt_tdm.scorelimit"] = "lots", ["pwt_nope.key"] = 1, ["pwt_bots.budget"] = 5,
                    ["pwt_bots.count"] = 40 })
                expect(PW.Setting("pwt_tdm.scorelimit")).to.equal(75)
                expect(PW.Setting("pwt_bots.count")).to.equal(16)
                expect(convars(state).pw_pwt_bots_budget).to.equal("2")
                expect(#state.logged >= 3).to.beTrue()
            end
        }
    }
}
