-- T-8.3 Entry hints and T-8.4 Join in progress (TASKS.md, "Mandatory test cases" T-8.3 logic and T-8.4;
-- 08-lobby.md d.2, d.4). T-8.3 is pure: facts about how the game started in, the hints and the Start lock out.
-- T-8.4 runs the join path of the `lobby` module (PlayerInitialSpawn -> PlayerSpawn -> phase change) over a fresh
-- store with a fake phase, fake setting and recorded engine calls; the one shared bot is the joiner, declared a
-- human by the store's isHuman. The bots manager is paused in tests, so the real one does not interfere.
-- The drawing of the hint card and of the spectating notice is a checkpoint item.

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

---@return PW.JipLib
local function jip()
    return must(PW.Jip)
end

---One shared bot, the joiner of the T-8.4 cases. A bot another group left behind is reused: a kicked bot frees its
---slot late and the suite is close to maxplayers, so this group adds a bot only when none exists and kicks only that.
---@param state table<string, any>
---@return Player
local function joiner(state)
    local bot = state.bot --[[@as Player?]]
    if bot ~= nil and IsValid(bot) then return bot end
    bot = player.GetBots()[1]
    if bot == nil then
        bot = player.CreateNextBot("PW jip test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        state.created = bot
    end
    state.bot = bot
    return bot
end

---@class PW.JipTestRig
---@field store PW.JipStore
---@field parked Player[]
---@field released Player[]
---@field marks table<Player, boolean>

---A store whose phase and setting come from the arguments and whose engine calls are recorded.
---@param phase PW.PhaseName
---@param enabled boolean
---@return PW.JipTestRig
local function rig(phase, enabled)
    ---@type Player[]
    local parked = {}
    ---@type Player[]
    local released = {}
    ---@type table<Player, boolean>
    local marks = {}
    local store = jip()._NewStore({
        phase = function() return phase end,
        enabled = function() return enabled end,
        isHuman = function() return true end,
        defer = function(fn) fn() end,
        park = function(ply) parked[#parked + 1] = ply end,
        unpark = function(ply) released[#released + 1] = ply end,
        mark = function(ply, on) marks[ply] = on end
    })
    return { store = store, parked = parked, released = released, marks = marks }
end

---Entry facts of a normal listen server host with P2P on; each argument overrides one fact.
---@param singlePlayer? boolean
---@param maxPlayers? integer
---@param host? boolean
---@param p2p? boolean|"unknown"
---@return PW.EntryFacts
local function facts(singlePlayer, maxPlayers, host, p2p)
    ---@type boolean?
    local value = true
    if p2p == "unknown" then
        value = nil
    elseif p2p ~= nil then
        value = p2p --[[@as boolean]]
    end
    return { singlePlayer = singlePlayer or false, maxPlayers = maxPlayers or 12, host = host ~= false, p2p = value }
end

---A minimal lobby state in which the host may start and a mode and a map exist.
---@param canStart boolean
---@param entry PW.EntryFacts
---@return PW.LobbyHubInput
local function hubInput(canStart, entry)
    ---@type PW.LobbyState
    local state = {
        map = "gm_pw_here", canStart = canStart, canEdit = canStart, canToggle = canStart, modes = {}, maps = {},
        toggles = {}
    }
    ---@type PW.LobbyHubInput
    local input = {
        state = state, selection = {}, players = {}, maxPlayers = entry.maxPlayers, seen = {}, entry = entry
    }
    return input
end

return {
    groupName = "PW ui entry and join in progress",
    afterAll = function(state)
        local bot = state.created --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then bot:Kick("test finished") end
    end,
    cases = {
        {
            name = "Entry hints: Singleplayer gives the listen-server hint and disables Start",
            func = function()
                local entry = lobby()._Entry(facts(true, 1))
                expect(#entry.hints).to.equal(1)
                expect(entry.hints[1].id).to.equal("listen")
                expect(entry.hints[1].blocking).to.beTrue()
                expect(string.find(entry.hints[1].text, "Max Players", 1, true) ~= nil).to.beTrue()
                expect(string.find(entry.hints[1].text, "12", 1, true) ~= nil).to.beTrue()
                local hub = lobby()._Hub(hubInput(true, facts(true, 1)))
                expect(hub.start.locked).to.beTrue()
                expect(hub.start.reason).to.equal(entry.startReason)
                expect((hub.hint --[[@as PW.EntryHint]]).id).to.equal("listen")
            end
        },
        {
            name = "Entry hints: maxplayers 1 outside Singleplayer is the same",
            func = function()
                local entry = lobby()._Entry(facts(false, 1))
                expect(entry.hints[1].id).to.equal("listen")
                expect(entry.startReason).to.beA("string")
                local hub = lobby()._Hub(hubInput(true, facts(false, 1)))
                expect(hub.start.locked).to.beTrue()
            end
        },
        {
            name = "Entry hints: a listen server with slots gives no hint and Start stays open",
            func = function()
                local entry = lobby()._Entry(facts())
                expect(#entry.hints).to.equal(0)
                expect(entry.startReason).to.beNil()
                local hub = lobby()._Hub(hubInput(true, facts()))
                expect(hub.hint).to.beNil()
                expect(hub.start.reason ~= lobby().EntryText.listenReason).to.beTrue()
            end
        },
        {
            name = "Entry hints: P2P off is a hint for the host only and never blocks Start",
            func = function()
                local host = lobby()._Entry(facts(false, 12, true, false))
                expect(host.hints[1].id).to.equal("p2p")
                expect(host.hints[1].blocking).to.beFalse()
                expect(host.startReason).to.beNil()
                expect(#lobby()._Entry(facts(false, 12, false, false)).hints).to.equal(0)
                expect(#lobby()._Entry(facts(false, 12, true, "unknown")).hints).to.equal(0)
            end
        },
        {
            name = "Join in progress off: a joiner during LIVE spectates",
            func = function(state)
                local bot = joiner(state)
                local r = rig("LIVE", false)
                expect(jip()._OnJoin(r.store, bot)).to.equal("spectate")
                expect(r.marks[bot]).to.beTrue()
                expect(jip()._OnSpawn(r.store, bot)).to.beTrue()
                expect(r.parked[1]).to.equal(bot)
                expect(jip()._CanRespawn(r.store, bot)).to.beFalse()
            end
        },
        {
            name = "Join in progress on: a joiner during LIVE plays",
            func = function(state)
                local bot = joiner(state)
                local r = rig("LIVE", true)
                expect(jip()._OnJoin(r.store, bot)).to.equal("play")
                expect(r.marks[bot]).to.beNil()
                expect(jip()._OnSpawn(r.store, bot)).to.beFalse()
                expect(#r.parked).to.equal(0)
                expect(jip()._CanRespawn(r.store, bot)).to.beTrue()
            end
        },
        {
            name = "Join in progress: outside LIVE the setting does not matter",
            func = function(state)
                local bot = joiner(state)
                for _, phase in ipairs({ "LOBBY", "PREMATCH", "POSTMATCH", "VOTE" }) do
                    local r = rig(phase --[[@as PW.PhaseName]], false)
                    expect(jip()._OnJoin(r.store, bot)).to.equal("normal")
                    expect(jip()._OnSpawn(r.store, bot)).to.beFalse()
                end
            end
        },
        {
            name = "Join in progress: a spectator is released when the next match is prepared",
            func = function(state)
                local bot = joiner(state)
                local r = rig("LIVE", false)
                jip()._OnJoin(r.store, bot)
                jip()._OnPhase(r.store, "POSTMATCH")
                expect(#r.released).to.equal(0)
                expect(jip()._CanRespawn(r.store, bot)).to.beFalse()
                jip()._OnPhase(r.store, "PREMATCH")
                expect(r.released[1]).to.equal(bot)
                expect(r.marks[bot]).to.beFalse()
                expect(jip()._CanRespawn(r.store, bot)).to.beTrue()
                expect(jip()._OnSpawn(r.store, bot)).to.beFalse()
            end
        },
        {
            name = "Join in progress: pure decision",
            func = function()
                local decide = jip()._Decide
                expect(decide({ phase = "LIVE", enabled = false, human = true })).to.equal("spectate")
                expect(decide({ phase = "LIVE", enabled = true, human = true })).to.equal("play")
                expect(decide({ phase = "LIVE", enabled = false, human = false })).to.equal("play")
                expect(decide({ phase = "LOBBY", enabled = false, human = true })).to.equal("normal")
            end
        },
        {
            name = "Join in progress: the setting lobby.joininprogress is a server bool, default on",
            func = function()
                local def = must(PW.Settings._CurrentIndex()["lobby.joininprogress"])
                expect(def.scope).to.equal("server")
                expect(def.type).to.equal("bool")
                expect(def.default).to.beTrue()
            end
        }
    }
}
