-- T-1.19 lobby screen v0 (TASKS.md, "Mandatory test cases" T-1.19: the Start button handler requires the
-- privilege; the enable-flag message is rejected without the privilege and accepted from a superadmin who is not
-- the host; 08-lobby.md d.3; 01-extensibility.md d.11; 00-core.md d.5, d.7, d.8). Pure cases run over plain data.
-- Net cases call the receive path (PW.Net._Dispatch) with a bot as sender; the lobby store's readers stand in for
-- net.Read*. Every net case swaps in a fresh net store (fake clock and phase) with the lobby messages registered
-- into it, a fresh lobby store over isolated test registries with fake flags, maps and start, and restores both;
-- the real phase machine is never touched (it stays in LOBBY). One pool bot lives for the whole group.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.LobbyLib
local function lobby()
    return must(PW.Lobby)
end

---Returns the one pool bot with the given usergroup. One bot for the whole group (a kicked bot frees its slot late
---and the suite is close to maxplayers): a case switches the bot between "user" and "superadmin" between sends.
---@param state table<string, any>
---@param group string
---@return Player
local function makeBot(state, group)
    local pool = state.pool --[[@as table<string, Player>]]
    local bot = pool.bot
    if bot == nil or not IsValid(bot) then
        bot = player.CreateNextBot("PW lobby test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        pool.bot = bot
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
        methods = PW.Settings.EntityMethods })
    for id, def in pairs(defs) do registry.Register(def, id) end
    registry.ResolveAll()
    local list = state.registries --[[@as PW.Registry[] ]]
    list[#list + 1] = registry
    return registry
end

---@param state table<string, any>
---@return table<string, boolean>
local function flags(state)
    return state.flags --[[@as table<string, boolean>]]
end

---@param state table<string, any>
---@return table[]
local function starts(state)
    return state.starts --[[@as table[] ]]
end

---@param state table<string, any>
---@return table[]
local function sent(state)
    return state.sent --[[@as table[] ]]
end

---@param state table<string, any>
---@param registries table<string, PW.Registry>
local function installStore(state, registries)
    PW._Lobby = must(lobby()._NewStore)({
        log = function() end,
        registries = function() return registries end,
        readStart = function()
            local request = state.request --[[@as any[] ]]
            return request[1], request[2]
        end,
        readToggle = function()
            local request = state.request --[[@as any[] ]]
            return request[1], request[2], request[3]
        end,
        send = function(ply, payload) sent(state)[#sent(state) + 1] = { ply = ply, state = payload } end,
        start = function(mode, map)
            local entity = mode --[[@as PW.Entity]]
            starts(state)[#starts(state) + 1] = { mode = entity.ClassName, map = map }
            return true
        end,
        map = function() return "gm_pw_here" end,
        maps = function() return { "gm_pw_here", "gm_pw_there" } end,
        mapExists = function(name) return name == "gm_pw_here" or name == "gm_pw_there" end,
        readFlag = function(name) return flags(state)[name] ~= false end,
        writeFlag = function(name, enabled)
            if flags(state)[name] == nil then return false end
            flags(state)[name] = enabled
            return true
        end
    })
end

---Sends one message from ply through the real wrapper (2 s after the previous one).
---@param state table<string, any>
---@param name string
---@param ply Player
---@param request any[]
---@return boolean
---@return string?
local function send(state, name, ply, request)
    state.request = request
    local now = state.now --[[@as number]]
    state.now = now + 2
    return must(PW.Net)._Dispatch(name, 64, ply)
end

---A state for the pure model cases: two modes, two maps.
---@return PW.LobbyState
local function sampleState()
    local groups = PW.Settings._Groups({
        mode = { ClassName = "pwt_a", Settings = { limit = { type = "int", default = 5, min = 1, max = 9 } } },
        modules = {}, scope = "match", log = function() end, valueOf = function(def) return def.default end
    })
    return {
        map = "gm_pw_here", maps = { "gm_pw_here", "gm_pw_there" },
        modes = { { id = "pwt_a", name = "A", groups = groups }, { id = "pwt_b", name = "B", groups = {} } },
        toggles = {}, canStart = true, canEdit = true, canToggle = false
    }
end

return {
    groupName = "PW lobby ui",
    -- The pool table is shared by every case (a field set inside a case is not).
    beforeAll = function(state)
        state.pool = {}
    end,
    afterAll = function(state)
        local bot = (state.pool --[[@as table<string, Player>]]).bot
        if bot ~= nil and IsValid(bot) then bot:Kick("PW lobby test finished") end
    end,
    beforeEach = function(state)
        state.previousNet = PW._Net
        state.previousLobby = PW._Lobby
        state.registries = {}
        state.starts = {}
        state.sent = {}
        state.now = 1000
        state.phase = "LOBBY"
        state.flags = { pw_mode_pwt_a_enabled = true, pw_mode_pwt_b_enabled = true, pw_mode_pwt_off_enabled = true,
            pw_module_pwt_mod_enabled = true }
        local registries = {
            modes = newRegistry(state, "modes", {
                pwt_a = { Name = "A", Teams = 2,
                    Settings = { limit = { type = "int", default = 5, min = 1, max = 9 } } },
                pwt_b = { Name = "B", Teams = 0 },
                pwt_off = { Name = "Off", Teams = 2 }
            }),
            modules = newRegistry(state, "modules", { pwt_mod = { Name = "Mod" } })
        }
        registries.modes._Disable("pwt_off", "test")
        state.map = registries
        installStore(state, registries)
        PW._Net = must(PW.Net)._NewStore({ log = function() end, clock = function() return state.now end,
            phase = function() return state.phase end })
        state.ownerValid = true
        must(lobby()._RegisterNet)({ IsValid = function() return state.ownerValid end })
    end,
    afterEach = function(state)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        PW._Net = state.previousNet
        PW._Lobby = state.previousLobby
    end,
    cases = {
        {
            -- Async on purpose, and first: synchronous groups run in one server frame, and a bot kicked by an
            -- earlier group frees its slot only after a frame. Waiting here lets those slots free before this
            -- group creates its bot (the suite runs close to maxplayers).
            name = "The start and toggle privileges are declared with the superadmin default",
            async = true,
            timeout = 3,
            func = function()
                expect(lobby().StartPrivilege).to.equal("pw.match.start")
                expect(lobby().TogglePrivilege).to.equal("pw.entities.toggle")
                expect(must(PW._Privileges.defs["pw.match.start"]).MinAccess).to.equal("superadmin")
                expect(must(PW._Privileges.defs["pw.entities.toggle"]).MinAccess).to.equal("superadmin")
                timer.Simple(0.2, function() done() end)
            end
        },
        {
            name = "Start button handler requires the privilege",
            func = function(state)
                local bot = makeBot(state, "user")
                expect({ send(state, "pw_lobby_start", bot, { "pwt_a", "gm_pw_there" }) })
                    .to.deepEqual({ false, "privilege" })
                expect(#starts(state)).to.equal(0)
                makeBot(state, "superadmin")
                expect(send(state, "pw_lobby_start", bot, { "pwt_a", "gm_pw_there" })).to.beTrue()
                expect(starts(state)).to.deepEqual({ { mode = "pwt_a", map = "gm_pw_there" } })
            end
        },
        {
            name = "Start is refused outside LOBBY, for a disabled, unknown or switched-off mode and a bad map",
            func = function(state)
                local admin = makeBot(state, "superadmin")
                state.phase = "LIVE"
                expect({ send(state, "pw_lobby_start", admin, { "pwt_a", "gm_pw_here" }) })
                    .to.deepEqual({ false, "phase" })
                state.phase = "LOBBY"
                flags(state).pw_mode_pwt_b_enabled = false
                send(state, "pw_lobby_start", admin, { "pwt_off", "gm_pw_here" })
                send(state, "pw_lobby_start", admin, { "pwt_nope", "gm_pw_here" })
                send(state, "pw_lobby_start", admin, { "pwt_b", "gm_pw_here" })
                send(state, "pw_lobby_start", admin, { "pwt_a", "gm_pw_missing" })
                send(state, "pw_lobby_start", admin, { "pwt_a", "../evil" })
                expect(#starts(state)).to.equal(0)
            end
        },
        {
            name = "The enable toggle is rejected without the privilege and accepted from a non-host superadmin",
            func = function(state)
                local admin = makeBot(state, "user")
                expect({ send(state, "pw_lobby_enable", admin, { "modes", "pwt_a", false }) })
                    .to.deepEqual({ false, "privilege" })
                expect(flags(state).pw_mode_pwt_a_enabled).to.beTrue()
                makeBot(state, "superadmin")
                expect(admin:IsSuperAdmin()).to.beTrue()
                expect(admin:IsListenServerHost()).to.beFalse()
                expect(send(state, "pw_lobby_enable", admin, { "modes", "pwt_a", false })).to.beTrue()
                expect(flags(state).pw_mode_pwt_a_enabled).to.beFalse()
                expect(sent(state)[1].ply).to.equal(admin)
                expect(send(state, "pw_lobby_enable", admin, { "modes", "pwt_a", true })).to.beTrue()
                expect(flags(state).pw_mode_pwt_a_enabled).to.beTrue()
            end
        },
        {
            name = "A toggle of an unknown entity, of the kinds registry or with a bad value changes nothing",
            func = function(state)
                local admin = makeBot(state, "superadmin")
                send(state, "pw_lobby_enable", admin, { "modes", "pwt_nope", false })
                send(state, "pw_lobby_enable", admin, { "kinds", "modes", false })
                send(state, "pw_lobby_enable", admin, { "modes", "pwt_b", "no" })
                expect(flags(state).pw_mode_pwt_b_enabled).to.beTrue()
                expect(#sent(state)).to.equal(0)
            end
        },
        {
            name = "The state request sends startable modes, maps and toggles only to privileged players",
            func = function(state)
                local bot = makeBot(state, "user")
                flags(state).pw_mode_pwt_b_enabled = false
                expect(send(state, "pw_lobby_request", bot, {})).to.beTrue()
                local plain = must(sent(state)[1]).state --[[@as PW.LobbyState]]
                expect(plain.map).to.equal("gm_pw_here")
                expect(plain.maps).to.deepEqual({ "gm_pw_here", "gm_pw_there" })
                expect(#plain.modes).to.equal(1)
                expect(must(plain.modes[1]).id).to.equal("pwt_a")
                expect(must(must(plain.modes[1]).groups[1]).owner).to.equal("pwt_a")
                expect(plain.canStart).to.beFalse()
                expect(plain.canToggle).to.beFalse()
                expect(#plain.toggles).to.equal(0)
                makeBot(state, "superadmin")
                expect(send(state, "pw_lobby_request", bot, {})).to.beTrue()
                local full = must(sent(state)[2]).state --[[@as PW.LobbyState]]
                expect(full.canStart).to.beTrue()
                expect(full.canEdit).to.beTrue()
                expect(#full.toggles).to.equal(4)
                expect(must(full.toggles[2]))
                    .to.deepEqual({ kind = "modes", id = "pwt_b", name = "B", enabled = false })
            end
        },
        {
            name = "The lobby state round-trips through the explicit wire encoding (no net.WriteTable)",
            func = function(state)
                local registries = state.map --[[@as table<string, PW.Registry>]]
                local modes = registries.modes
                local sentState = lobby()._BuildState({
                    map = "gm_pw_here", maps = { "gm_pw_here", "gm_pw_there" },
                    modes = { must(modes.Get("pwt_a")), must(modes.Get("pwt_b")) },
                    groupsOf = function(mode) return PW.Settings.GetGroups("match", mode) end,
                    toggles = { { kind = "modes", id = "pwt_b", name = "B", enabled = false } },
                    canStart = true, canEdit = false, canToggle = true
                })
                must(must(must(sentState.modes[1]).groups[1]).fields[1]).value = 7
                ---@type any[]
                local queue = {}
                lobby()._Encode(sentState, {
                    uint = function(value) queue[#queue + 1] = value end,
                    string = function(value) queue[#queue + 1] = value end,
                    bool = function(value) queue[#queue + 1] = value end
                })
                local position = 0
                local function nextValue()
                    position = position + 1
                    return queue[position]
                end
                local received = lobby()._Decode({ uint = nextValue, string = nextValue, bool = nextValue },
                    lobby()._Resolver(registries))
                expect(position).to.equal(#queue)
                expect(received).to.deepEqual(sentState)
            end
        },
        {
            name = "Map names come from the .bsp listing: valid, unique, sorted",
            func = function()
                expect(lobby()._MapsFromFiles({ "gm_construct.bsp", "de_dust2.bsp", "bad name.bsp", "readme.txt",
                    "gm_construct.bsp" })).to.deepEqual({ "de_dust2", "gm_construct" })
                expect(lobby()._ValidMapName("gm_construct")).to.beTrue()
                expect(lobby()._ValidMapName("../x")).to.beFalse()
                expect(lobby()._ValidMapName("")).to.beFalse()
                expect(lobby()._ValidMapName(5)).to.beFalse()
            end
        },
        {
            name = "The pure Start check names the reason",
            func = function()
                local facts = { modes = { pwt_a = true }, mapExists = function(name) return name == "gm_x" end }
                expect(lobby()._CheckStart({ mode = "pwt_a", map = "gm_x" }, facts)).to.beTrue()
                expect(select(2, lobby()._CheckStart({ mode = "pwt_b", map = "gm_x" }, facts)))
                    .to.equal("unknown mode")
                expect(select(2, lobby()._CheckStart({ mode = 1, map = "gm_x" }, facts))).to.equal("unknown mode")
                expect(select(2, lobby()._CheckStart({ mode = "pwt_a", map = "a b" }, facts))).to.equal("invalid map")
                expect(select(2, lobby()._CheckStart({ mode = "pwt_a", map = "gm_y" }, facts))).to.equal("no such map")
            end
        },
        {
            name = "The screen model selects the first mode and the current map and builds the Game Setup form",
            func = function()
                local model = lobby()._Model(sampleState(), {})
                expect(model.mode).to.equal("pwt_a")
                expect(model.map).to.equal("gm_pw_here")
                expect(model.modes).to.deepEqual({ { id = "pwt_a", label = "A" }, { id = "pwt_b", label = "B" } })
                expect(#model.sections).to.equal(1)
                expect(must(model.sections[1]).title).to.equal("A")
                expect(must(must(model.sections[1]).controls[1]).id).to.equal("pwt_a.limit")
                expect(model.canStart).to.beTrue()
                local other = lobby()._Model(sampleState(), { mode = "pwt_b", map = "gm_pw_there" })
                expect(other.mode).to.equal("pwt_b")
                expect(other.map).to.equal("gm_pw_there")
                expect(#other.sections).to.equal(0)
                local fallback = lobby()._Model(sampleState(), { mode = "gone", map = "gone" })
                expect(fallback.mode).to.equal("pwt_a")
                expect(fallback.map).to.equal("gm_pw_here")
            end
        },
        {
            name = "Without modes the screen cannot start",
            func = function()
                local empty = sampleState()
                empty.modes = {}
                local model = lobby()._Model(empty, {})
                expect(model.mode).to.equal(nil)
                expect(model.canStart).to.beFalse()
            end
        },
        {
            name = "A disabled lobby module drops its three messages before the handlers run",
            func = function(state)
                local bot = makeBot(state, "superadmin")
                state.ownerValid = false
                expect({ send(state, "pw_lobby_request", bot, {}) }).to.deepEqual({ false, "disabled" })
                expect({ send(state, "pw_lobby_start", bot, { "pwt_a", "gm_pw_there" }) })
                    .to.deepEqual({ false, "disabled" })
                expect({ send(state, "pw_lobby_enable", bot, { "modes", "pwt_b", false }) })
                    .to.deepEqual({ false, "disabled" })
                expect(#sent(state)).to.equal(0)
                expect(#starts(state)).to.equal(0)
                expect(flags(state).pw_mode_pwt_b_enabled).to.beTrue()
                state.ownerValid = true
                expect(send(state, "pw_lobby_request", bot, {})).to.beTrue()
                expect(#sent(state)).to.equal(1)
            end
        },
        {
            -- Regression: the module file registers its messages while it loads, before MODULE has IsValid; a check
            -- of the owner's IsValid at registration rejected all three and the lobby stayed empty on the Deck.
            name = "The messages registered when the module loaded are in the real net store, owned by lobby_ui",
            func = function(state)
                local real = state.previousNet --[[@as PW.NetStore]]
                local owner = must(PW.Modules.GetStored("lobby_ui"))
                for _, name in ipairs({ "pw_lobby_request", "pw_lobby_start", "pw_lobby_enable" }) do
                    expect(must(real.defs[name]).owner).to.equal(owner)
                    expect(util.NetworkStringToID(name)).toNot.equal(0)
                end
            end
        },
        {
            name = "The real registration gives the lobby messages the lobby_ui class table as owner",
            func = function()
                must(lobby()._RegisterNet)()
                local owner = must(PW.Modules.GetStored("lobby_ui"))
                for _, name in ipairs({ "pw_lobby_request", "pw_lobby_start", "pw_lobby_enable" }) do
                    expect(must(PW._Net.defs[name]).owner).to.equal(owner)
                end
                expect(IsValid(owner)).to.beTrue()
            end
        },
        {
            -- Regression (cp1 6.2 on the Deck): pw_reload re-ran cl_init.lua, which called module:IsValid() while
            -- the file ran, before the registry gave MODULE its IsValid; the error dropped lobby_ui on the client.
            name = "The lobby client file checks its module with IsValid(module), never module:IsValid()",
            func = function()
                local source = must(file.Read("privatewar/modules/lobby_ui/cl_init.lua", "LUA"))
                expect(string.find(source, "module:IsValid()", 1, true)).to.beNil()
                expect(string.find(source, "IsValid(module)", 1, true)).to.exist()
            end
        },
        {
            name = "Client decision (pure): the screen shows in LOBBY and PREMATCH with lobby_ui and ui_kit enabled",
            func = function()
                expect(lobby()._ShouldShow("LOBBY", true, true)).to.beTrue()
                expect(lobby()._ShouldShow("LOBBY", false, true)).to.beFalse()
                expect(lobby()._ShouldShow("LOBBY", true, false)).to.beFalse()
                expect(lobby()._ShouldShow("PREMATCH", true, true)).to.beTrue()
                expect(lobby()._ShouldShow("LIVE", true, true)).to.beFalse()
            end
        },
        {
            name = "Retry decision (pure): resend pw_lobby_request while open and waiting, within the rate limit",
            func = function()
                expect(lobby()._ShouldRequest(true, true)).to.beTrue()
                expect(lobby()._ShouldRequest(true, false)).to.beFalse()
                expect(lobby()._ShouldRequest(false, true)).to.beFalse()
                expect(lobby().RetryEvery).to.equal(2)
                expect(1 / lobby().RetryEvery <= must(PW._Net.defs.pw_lobby_request).rate).to.beTrue()
            end
        }
    }
}
