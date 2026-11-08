-- T-1.14 map change (TASKS.md, "Mandatory test cases" T-1.14; 00-core.md d.9). The map is never really changed:
-- every case swaps in a fresh map change store whose changelevel only records the call, whose facts (current map,
-- map change count, os.time, CurTime) are fake and whose file path is a test-only DATA path deleted afterwards. A
-- fresh phase machine store, a net store (fake clock, the real message definitions) and fresh settings and enable
-- stores are swapped in too, and all of them are restored afterwards, so the real machine stays in LOBBY and the
-- real stores keep no match snapshot or pending values. Bots stand in for clients as senders of
-- pw_client_ready; the two pool bots live for the whole group (a kicked bot frees its slot late).

local testPath = "privatewar/pw_test_pending_match.json"
local listenerId = "PW_Test_MapChange"
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

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@return PW.MapChangeLib
local function changer()
    return must(PW.MapChange)
end

---@return PW.NetLib
local function netLib()
    return must(PW.Net)
end

---@param state table<string, any>
---@param message string
local function record(state, message)
    local logged = state.logged --[[@as string[] ]]
    logged[#logged + 1] = message
end

---@param state table<string, any>
local function installStores(state)
    PW._Match = match()._NewStore({
        log = function(message) record(state, message) end,
        clock = function() return state.now end,
        players = function() return state.players end,
        settings = function()
            return { prematch = 60, countdown = 10, postmatch = 15, vote = 15, afterMatch = "lobby" }
        end
    })
    PW._MapChange = changer()._NewStore({
        path = testPath,
        log = function(message) record(state, message) end,
        clock = function() return state.now end,
        time = function() return state.time end,
        map = function() return currentMap end,
        mapChangeCount = function() return 5 end,
        delay = function() return 1 end, -- minimum delay; countdown boundaries have dedicated match-flow cases
        bots = function() return 3 end,
        resolveMode = function(id) return id == "testmode" and state.mode or nil end,
        changelevel = function(map)
            local calls = state.changelevels --[[@as table[] ]]
            calls[#calls + 1] = { map = map, text = file.Read(testPath, "DATA") }
        end,
        ack = function(ply)
            local acks = state.acks --[[@as Player[] ]]
            acks[#acks + 1] = ply
        end
    })
    local fresh = netLib()._NewStore({ log = function() end, clock = function() return state.now end })
    fresh.defs = (state.previousNet --[[@as PW.NetStore]]).defs
    PW._Net = fresh
end

---Returns pool bot "a" or "b" (created once per group).
---@param state table<string, any>
---@param key "a"|"b"
---@return Player
local function poolBot(state, key)
    local pool = state.pool --[[@as table<string, Player>]]
    local bot = pool[key]
    if bot == nil or not IsValid(bot) then
        bot = player.CreateNextBot("PW map test " .. key)
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        pool[key] = bot
    end
    return bot
end

---A valid pending match for the fake facts (current map, count 5 = 4 + 1, written 5 s ago); overrides replace
---fields (a field set to false is removed).
---@param state table<string, any>
---@param overrides? table<string, any>
---@return table<string, any>
local function pendingFor(state, overrides)
    ---@type table<string, any>
    local pending = {
        v = 1, map = currentMap, mode = "testmode", settings = {}, bots = 2,
        teams = { ["76561198000000001"] = 1 }, createdAt = state.time - 5, mapChangeCount = 4
    }
    for key, value in pairs(overrides or {}) do
        if value == false then pending[key] = nil else pending[key] = value end
    end
    return pending
end

---@param pending table<string, any>
local function writePending(pending)
    file.CreateDir("privatewar")
    file.Write(testPath, util.TableToJSON(pending))
end

---@param state table<string, any>
---@return integer
local function changelevelCount(state)
    local calls = state.changelevels --[[@as table[] ]]
    return #calls
end

---@param state table<string, any>
---@param needle string
---@return boolean
local function loggedWith(state, needle)
    for _, line in ipairs(state.logged --[[@as string[] ]]) do
        if string.find(line, needle, 1, true) then return true end
    end
    return false
end

---Moves the fake clock forward.
---@param state table<string, any>
---@param seconds number
local function advance(state, seconds)
    local now = state.now --[[@as number]]
    state.now = now + seconds
end

---@param state table<string, any>
---@return integer
local function osTime(state)
    return state.time --[[@as integer]]
end

---Sends pw_client_ready from ply through the real wrapper, 2 s after the previous one (the client's retry pace).
---@param state table<string, any>
---@param ply Player
---@return boolean
local function sendReady(state, ply)
    advance(state, 2)
    return (netLib()._Dispatch("pw_client_ready", 0, ply))
end

return {
    groupName = "PW map change",
    beforeAll = function(state)
        state.pool = {}
    end,
    afterAll = function(state)
        for _, bot in pairs(state.pool --[[@as table<string, Player>]]) do
            if IsValid(bot) then bot:Kick("PW map change test finished") end
        end
    end,
    beforeEach = function(state)
        state.previousMatch = PW._Match
        state.previousSettings = PW._Settings
        state.previousEnable = PW._Enable
        -- Matches started here take their snapshots (and the pending file its values) in fresh stores.
        PW._Settings = must(PW.Settings)._NewStore()
        PW._Enable = must(PW.Enable)._NewStore({ registries = function() return {} end })
        state.previousChange = PW._MapChange
        state.previousNet = PW._Net
        state.previousMode = PW.ActiveMode
        state.now = 1000
        state.time = 1800000000
        state.players = {}
        state.logged = {}
        state.changelevels = {}
        state.acks = {}
        state.applied = {}
        state.mode = { ClassName = "testmode" }
        installStores(state)
        local applied = state.applied --[[@as table[] ]]
        hook.Add("PW_PendingMatchApplied", listenerId, function(pending) applied[#applied + 1] = pending end)
    end,
    afterEach = function(state)
        hook.Remove("PW_PendingMatchApplied", listenerId)
        hook.Remove("PW_PendingTeams", listenerId)
        if file.Exists(testPath, "DATA") then file.Delete(testPath) end
        PW._Match = state.previousMatch
        PW._Settings = state.previousSettings
        PW._Enable = state.previousEnable
        PW._MapChange = state.previousChange
        PW._Net = state.previousNet
        PW.ActiveMode = state.previousMode
    end,
    cases = {
        {
            name = "Another map: pending_match.json is written before changelevel and its contents round-trip",
            func = function(state)
                -- The settings of the file are the would-be snapshot of the live schema, whatever modules exist.
                local forFile = must(PW.Settings._ForFile)
                local expectedSettings = forFile(state.mode --[[@as table]])
                expect(match().Start(state.mode, otherMap)).to.beTrue()
                expect(changelevelCount(state)).to.equal(0)
                advance(state, 1)
                changer()._Tick()
                expect(changelevelCount(state)).to.equal(1)
                local call = state.changelevels[1] --[[@as { map: string, text: string? }]]
                expect(call.map).to.equal(otherMap)
                local written = must(changer()._Decode(must(call.text)))
                expect(written).to.deepEqual({
                    v = 1, map = otherMap, mode = "testmode", settings = expectedSettings, bots = 3, teams = {},
                    createdAt = osTime(state), mapChangeCount = 5
                })
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(changer().IsChanging()).to.beTrue()
            end
        },
        {
            name = "The teams field of the pending file is the answer to PW_PendingTeams for the target mode",
            func = function(state)
                ---@type table[]
                local asked = {}
                hook.Add("PW_PendingTeams", listenerId, function(mode)
                    asked[#asked + 1] = mode
                    return { ["76561198000000001"] = 2 }
                end)
                local ok = match().Start(state.mode, otherMap)
                expect(ok).to.beTrue()
                advance(state, 1)
                changer()._Tick()
                hook.Remove("PW_PendingTeams", listenerId)
                expect(#asked).to.equal(1)
                expect(asked[1]).to.equal(state.mode)
                local call = state.changelevels[1] --[[@as { map: string, text: string? }]]
                local written = must(changer()._Decode(must(call.text)))
                expect(written.teams).to.deepEqual({ ["76561198000000001"] = 2 })
            end
        },
        {
            name = "Encode and decode round-trip nested settings and SteamID64 team keys as strings",
            func = function(state)
                local pending = pendingFor(state, {
                    settings = { scorelimit = 75, nested = { flag = true, name = "x" } },
                    teams = { ["76561198000000001"] = 1, ["76561198000000002"] = 2 }
                })
                local decoded = must(changer()._Decode(changer()._Encode(pending --[[@as PW.PendingMatch]])))
                expect(decoded).to.deepEqual(pending)
                expect(decoded.teams["76561198000000002"]).to.equal(2)
                expect(changer()._Decode("not json")).to.beNil()
            end
        },
        {
            name = "Same target map: no changelevel and no file, straight to PREMATCH (map given or omitted)",
            func = function(state)
                expect(match().Start(state.mode, currentMap)).to.beTrue()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(changelevelCount(state)).to.equal(0)
                expect(file.Exists(testPath, "DATA")).to.beFalse()
                expect(match().Abort("test")).to.beTrue()
                expect(match().Start(state.mode)).to.beTrue()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(changelevelCount(state)).to.equal(0)
                expect(changer().IsChanging()).to.beFalse()
            end
        },
        {
            name = "A second start during a map change never calls changelevel twice (guard)",
            func = function(state)
                expect(match().Start(state.mode, otherMap)).to.beTrue()
                expect(match().Start(state.mode, otherMap)).to.beFalse()
                expect(match().Start(state.mode, "gm_pw_test_third")).to.beFalse()
                expect(match().Start(state.mode)).to.beFalse()
                expect(changelevelCount(state)).to.equal(0)
                advance(state, 1)
                changer()._Tick()
                expect(match().Start(state.mode, otherMap)).to.beFalse()
                expect(changelevelCount(state)).to.equal(1)
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(loggedWith(state, "map change")).to.beTrue()
            end
        },
        {
            name = "Guard decision: busy while changing, PREMATCH for the same or no map, changelevel otherwise",
            func = function()
                local decide = changer()._Decide
                expect(decide(currentMap, otherMap, false)).to.equal("changelevel")
                expect(decide(currentMap, currentMap, false)).to.equal("prematch")
                expect(decide(currentMap, nil, false)).to.equal("prematch")
                expect(decide(currentMap, otherMap, true)).to.equal("busy")
                expect(decide(currentMap, nil, true)).to.equal("busy")
            end
        },
        {
            name = "Failed changelevel: still on the old map after 10 s, back to LOBBY with an error for the host",
            func = function(state)
                expect(match().Start(state.mode, otherMap)).to.beTrue()
                advance(state, 1)
                changer()._Tick()
                advance(state, 9.9)
                changer()._Tick()
                expect(changer().IsChanging()).to.beTrue()
                advance(state, 0.1)
                changer()._Tick()
                expect(changer().IsChanging()).to.beFalse()
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(file.Exists(testPath, "DATA")).to.beFalse()
                local reason = must(match().GetAbortReason())
                expect(string.find(reason, otherMap, 1, true)).to.exist()
                expect(loggedWith(state, otherMap)).to.beTrue()
                expect(match().Start(state.mode, otherMap)).to.beTrue()
                advance(state, 1)
                changer()._Tick()
                expect(changelevelCount(state)).to.equal(2)
            end
        },
        {
            name = "Valid pending match: PREMATCH with the file's mode, file deleted, PW_PendingMatchApplied fired",
            func = function(state)
                writePending(pendingFor(state, { createdAt = state.time - 119 }))
                local ok = changer()._Apply()
                expect(ok).to.beTrue()
                expect(match().GetPhase()).to.equal("PREMATCH")
                expect(PW._Match.mode).to.equal(state.mode)
                expect(PW.ActiveMode).to.equal(state.mode)
                expect(file.Exists(testPath, "DATA")).to.beFalse()
                expect(#state.applied).to.equal(1)
                expect(state.applied[1].bots).to.equal(2)
                expect(state.applied[1].teams["76561198000000001"]).to.equal(1)
            end
        },
        {
            name = "Invalid pending match (map, map change count, age 120 s, version) is rejected and stays in LOBBY",
            func = function(state)
                local variants = {
                    { overrides = { map = otherMap }, reason = "map" },
                    { overrides = { mapChangeCount = 5 }, reason = "count" },
                    { overrides = { mapChangeCount = 3 }, reason = "count" },
                    { overrides = { createdAt = osTime(state) - 120 }, reason = "age" },
                    { overrides = { v = 99 }, reason = "version" }
                }
                for _, variant in ipairs(variants) do
                    writePending(pendingFor(state, variant.overrides))
                    local ok, reason = changer()._Apply()
                    expect(ok).to.beFalse()
                    expect(reason).to.equal(variant.reason)
                    expect(match().GetPhase()).to.equal("LOBBY")
                    expect(file.Exists(testPath, "DATA")).to.beFalse()
                end
                expect(#state.applied).to.equal(0)
                expect(changelevelCount(state)).to.equal(0)
                expect(loggedWith(state, "rejected")).to.beTrue()
            end
        },
        {
            name = "Validity rules: missing, corrupt and mistyped files are rejected; a valid table passes",
            func = function(state)
                local validate = changer()._Validate
                local facts = { map = currentMap, mapChangeCount = 5, now = osTime(state) }
                expect(validate(pendingFor(state), facts)).to.beTrue()
                expect(select(2, validate(nil, facts))).to.equal("missing")
                expect(select(2, validate("text", facts))).to.equal("corrupt")
                expect(select(2, validate(pendingFor(state, { mode = false }), facts))).to.equal("corrupt")
                expect(select(2, validate(pendingFor(state, { createdAt = "soon" }), facts))).to.equal("corrupt")
                expect(select(2, validate(pendingFor(state, { createdAt = state.time + 1 }), facts))).to.equal("age")
            end
        },
        {
            name = "Missing file stays in LOBBY silently; unknown mode id stays in LOBBY with a log line",
            func = function(state)
                local ok, reason = changer()._Apply()
                expect(ok).to.beFalse()
                expect(reason).to.equal("missing")
                expect(#state.logged).to.equal(0)
                writePending(pendingFor(state, { mode = "pw_no_such_mode" }))
                ok, reason = changer()._Apply()
                expect(ok).to.beFalse()
                expect(reason).to.equal("mode")
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(loggedWith(state, "pw_no_such_mode")).to.beTrue()
                expect(#state.applied).to.equal(0)
            end
        },
        {
            name = "Client ready: repeated messages are idempotent, accepted in any phase, and each one is acked",
            func = function(state)
                local human = poolBot(state, "a")
                expect(sendReady(state, human)).to.beTrue()
                expect(sendReady(state, human)).to.beTrue()
                expect(PW._Match.ready[human]).to.beTrue()
                expect(table.Count(PW._Match.ready)).to.equal(1)
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(#state.acks).to.equal(2)
                expect(state.acks[2]).to.equal(human)
                PW._Match.phase = "LIVE"
                expect(sendReady(state, human)).to.beTrue()
                expect(table.Count(PW._Match.ready)).to.equal(1)
                expect(#state.acks).to.equal(3)
            end
        },
        {
            name = "PREMATCH waits for humans only: bots count as ready, a human after pw_client_ready",
            func = function(state)
                local bot = poolBot(state, "a")
                local human = poolBot(state, "b")
                state.players = { { key = bot, bot = true }, { key = human, bot = false } }
                expect(match().Start(state.mode)).to.beTrue()
                match()._Tick()
                expect(PW._Match.countdown).to.beFalse()
                expect(sendReady(state, human)).to.beTrue()
                match()._Tick()
                expect(PW._Match.countdown).to.beTrue()
                expect(match().Abort("test")).to.beTrue()
                state.players = { { key = bot, bot = true } }
                expect(match().Start(state.mode)).to.beTrue()
                match()._Tick()
                expect(PW._Match.countdown).to.beTrue()
            end
        },
        {
            name = "A client that loaded before the match counts as ready in the next PREMATCH",
            func = function(state)
                local human = poolBot(state, "b")
                state.players = { { key = human, bot = false } }
                expect(sendReady(state, human)).to.beTrue()
                expect(match().Start(state.mode)).to.beTrue()
                match()._Tick()
                expect(PW._Match.countdown).to.beTrue()
            end
        }
    }
}
