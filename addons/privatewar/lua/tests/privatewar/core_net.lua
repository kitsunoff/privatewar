-- T-1.11 PW.Net.Receive (TASKS.md, "Mandatory test cases" T-1.11; 00-core.md d.8). A bot is a player: the
-- cases call the receive path (PW.Net._Dispatch) with a bot as sender instead of real client traffic.
-- Every case swaps in a fresh net store (fake clock, capturing logger), a fresh privilege store and a fresh phase
-- machine store in LIVE, and restores them, pw_debug and the test net.Receivers entries afterwards; the two
-- pool bots are kicked after the group.

local testNames = { "pw_test_net_msg", "pw_test_net_other", "pw_test_net_raw", "pw_test_net_bad" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.NetLib
local function netLib()
    return must(PW.Net)
end

---@return ConVar
local function debugVar()
    return must(GetConVar("pw_debug"))
end

---Returns pool bot "a" or "b" with the given usergroup. The two bots live for the whole group (beforeAll creates
---the pool, afterAll kicks them): a kicked bot keeps its slot until later, so a bot per case runs out of slots.
---@param state table<string, any>
---@param key "a"|"b"
---@param group string
---@return Player
local function makeBot(state, key, group)
    local pool = state.pool --[[@as table<string, Player>]]
    local bot = pool[key]
    if bot == nil or not IsValid(bot) then
        bot = player.CreateNextBot("PW net test " .. key)
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        pool[key] = bot
    end
    bot:SetUserGroup(group)
    return bot
end

---Registers pw_test_net_msg with opts and a handler that records its calls in state.calls (expect exists only
---inside a case, so the helper asserts).
---@param state table<string, any>
---@param opts PW.NetOptions
local function register(state, opts)
    local calls = state.calls --[[@as table[] ]]
    local ok = netLib().Receive("pw_test_net_msg", opts, function(ply, len)
        calls[#calls + 1] = { ply = ply, len = len }
    end)
    assert(ok, "PW.Net.Receive rejected valid options")
end

---@return table<string, function?>
local function receivers()
    return net.Receivers --[[@as table<string, function?>]]
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
local function callCount(state)
    local calls = state.calls --[[@as table[] ]]
    return #calls
end

---@param state table<string, any>
---@return integer
local function logCount(state)
    local logged = state.logged --[[@as string[] ]]
    return #logged
end

return {
    groupName = "PW net wrapper",
    beforeAll = function(state)
        state.pool = {}
    end,
    afterAll = function(state)
        for _, bot in pairs(state.pool --[[@as table<string, Player>]]) do
            if IsValid(bot) then bot:Kick("PW net test finished") end
        end
    end,
    beforeEach = function(state)
        state.calls = {}
        state.logged = {}
        state.now = 1000
        state.previousNet = PW._Net
        state.previousPrivileges = PW._Privileges
        state.previousMatch = PW._Match
        state.previousDebug = debugVar():GetString()
        local logged = state.logged --[[@as string[] ]]
        PW._Net = netLib()._NewStore({
            log = function(message) logged[#logged + 1] = message end,
            clock = function() return state.now end
        })
        PW._Privileges = { defs = {}, log = function() end }
        PW._Match = must(PW.Match)._NewStore({ log = function() end })
        PW._Match.phase = "LIVE"
        debugVar():SetString("0")
    end,
    afterEach = function(state)
        for _, name in ipairs(testNames) do receivers()[name] = nil end
        PW._Net = state.previousNet
        PW._Privileges = state.previousPrivileges
        PW._Match = state.previousMatch
        debugVar():SetString(state.previousDebug)
    end,
    cases = {
        {
            name = "A valid message from a bot reaches the handler with the sender and the length",
            func = function(state)
                register(state, { who = "any", phases = { "LIVE" }, rate = 5, maxLen = 16 })
                local bot = makeBot(state, "a", "user")
                expect(netLib()._Dispatch("pw_test_net_msg", 64, bot)).to.beTrue()
                expect(callCount(state)).to.equal(1)
                expect(state.calls[1].ply).to.equal(bot)
                expect(state.calls[1].len).to.equal(64)
                expect(logCount(state)).to.equal(0)
            end
        },
        {
            name = "Registration adds the network string and a net.Receive callback that runs the checks",
            func = function(state)
                register(state, { who = "any", rate = 5, maxLen = 16 })
                expect(util.NetworkStringToID("pw_test_net_msg")).toNot.equal(0)
                local receiver = must(receivers()["pw_test_net_msg"])
                local bot = makeBot(state, "a", "user")
                receiver(8, bot)
                expect(callCount(state)).to.equal(1)
                receiver(16 * 8 + 1, bot)
                expect(callCount(state)).to.equal(1)
            end
        },
        {
            name = "A bot without the privilege is dropped before the handler; one with it passes",
            func = function(state)
                PW.Privilege("pw.test.net", "superadmin")
                register(state, { who = "pw.test.net", rate = 5, maxLen = 16 })
                local grunt = makeBot(state, "a", "user")
                local boss = makeBot(state, "b", "superadmin")
                local ok, reason = netLib()._Dispatch("pw_test_net_msg", 8, grunt)
                expect(ok).to.beFalse()
                expect(reason).to.equal("privilege")
                expect(callCount(state)).to.equal(0)
                expect(netLib()._Dispatch("pw_test_net_msg", 8, boss)).to.beTrue()
                expect(callCount(state)).to.equal(1)
            end
        },
        {
            name = "A message from a bot in the wrong phase is dropped before the handler",
            func = function(state)
                register(state, { who = "any", phases = { "LOBBY", "PREMATCH" }, rate = 5, maxLen = 16 })
                local bot = makeBot(state, "a", "superadmin")
                local ok, reason = netLib()._Dispatch("pw_test_net_msg", 8, bot)
                expect(ok).to.beFalse()
                expect(reason).to.equal("phase")
                expect(callCount(state)).to.equal(0)
                PW._Match.phase = "PREMATCH"
                expect(netLib()._Dispatch("pw_test_net_msg", 8, bot)).to.beTrue()
                expect(callCount(state)).to.equal(1)
            end
        },
        {
            name = "Messages from a bot over the rate are dropped before the handler; the bucket refills",
            func = function(state)
                register(state, { who = "any", rate = 2, maxLen = 16 })
                local bot = makeBot(state, "a", "user")
                local other = makeBot(state, "b", "user")
                expect(netLib()._Dispatch("pw_test_net_msg", 8, bot)).to.beTrue()
                expect(netLib()._Dispatch("pw_test_net_msg", 8, bot)).to.beTrue()
                local ok, reason = netLib()._Dispatch("pw_test_net_msg", 8, bot)
                expect(ok).to.beFalse()
                expect(reason).to.equal("rate")
                expect(callCount(state)).to.equal(2)
                expect(netLib()._Dispatch("pw_test_net_msg", 8, other)).to.beTrue()
                advance(state, 0.5)
                expect(netLib()._Dispatch("pw_test_net_msg", 8, bot)).to.beTrue()
                expect(netLib()._Dispatch("pw_test_net_msg", 8, bot)).to.beFalse()
                expect(callCount(state)).to.equal(4)
            end
        },
        {
            name = "A message from a bot over maxLen is dropped before the handler",
            func = function(state)
                register(state, { who = "any", rate = 5, maxLen = 4 })
                local bot = makeBot(state, "a", "user")
                local ok, reason = netLib()._Dispatch("pw_test_net_msg", 33, bot)
                expect(ok).to.beFalse()
                expect(reason).to.equal("length")
                expect(callCount(state)).to.equal(0)
                expect(netLib()._Dispatch("pw_test_net_msg", 32, bot)).to.beTrue()
                expect(callCount(state)).to.equal(1)
            end
        },
        {
            name = "Rejection logging is throttled: one line per 5 seconds per player",
            func = function(state)
                register(state, { who = "any", phases = { "LOBBY" }, rate = 100, maxLen = 16 })
                local bot = makeBot(state, "a", "user")
                local other = makeBot(state, "b", "user")
                for _ = 1, 3 do netLib()._Dispatch("pw_test_net_msg", 8, bot) end
                expect(logCount(state)).to.equal(1)
                local line = must(state.logged[1]) --[[@as string]]
                expect(string.find(line, "pw_test_net_msg", 1, true)).to.exist()
                expect(string.find(line, "phase", 1, true)).to.exist()
                advance(state, 4.9)
                netLib()._Dispatch("pw_test_net_msg", 8, bot)
                expect(logCount(state)).to.equal(1)
                netLib()._Dispatch("pw_test_net_msg", 8, other)
                expect(logCount(state)).to.equal(2)
                advance(state, 0.1)
                netLib()._Dispatch("pw_test_net_msg", 8, bot)
                expect(logCount(state)).to.equal(3)
                expect(callCount(state)).to.equal(0)
            end
        },
        {
            name = "Invalid options are rejected with one log line and nothing is registered",
            func = function(state)
                local handler = function() end
                local bad = {
                    { rate = 1, maxLen = 8 },
                    { who = "any", maxLen = 8 },
                    { who = "any", rate = 0, maxLen = 8 },
                    { who = "any", rate = 1 },
                    { who = "any", rate = 1, maxLen = -1 },
                    { who = "any", rate = 1, maxLen = 8, phases = { "NOPE" } }
                }
                for index, opts in ipairs(bad) do
                    expect(netLib().Receive("pw_test_net_bad", opts --[[@as PW.NetOptions]], handler)).to.beFalse()
                    expect(logCount(state)).to.equal(index)
                end
                expect(receivers()["pw_test_net_bad"]).to.beNil()
                expect(netLib()._Dispatch("pw_test_net_bad", 8, makeBot(state, "a", "user"))).to.beFalse()
            end
        },
        {
            name = "Token bucket: starts full, refills at rate per second, never above rate",
            func = function()
                local take = netLib()._TakeToken
                local ok, bucket = take(nil, 2, 10)
                expect(ok).to.beTrue()
                expect(bucket.tokens).to.equal(1)
                ok, bucket = take(bucket, 2, 10)
                expect(ok).to.beTrue()
                ok, bucket = take(bucket, 2, 10)
                expect(ok).to.beFalse()
                ok, bucket = take(bucket, 2, 100)
                expect(ok).to.beTrue()
                expect(bucket.tokens).to.equal(1)
                ok = take({ tokens = 0, at = 0 }, 0.5, 1.9)
                expect(ok).to.beFalse()
                ok = take({ tokens = 0, at = 0 }, 0.5, 2)
                expect(ok).to.beTrue()
            end
        },
        {
            name = "Debug mode warns about pw_ net.Receive registrations that bypass the wrapper",
            func = function(state)
                register(state, { who = "any", rate = 5, maxLen = 16 })
                net.Receive("pw_test_net_raw", function() end)
                local found = netLib()._CheckBypass()
                expect(logCount(state)).to.equal(0)
                expect(table.HasValue(found, "pw_test_net_raw")).to.beTrue()
                expect(table.HasValue(found, "pw_test_net_msg")).to.beFalse()
                debugVar():SetString("1")
                netLib()._CheckBypass()
                local warned = 0
                for _, line in ipairs(state.logged --[[@as string[] ]]) do
                    if string.find(line, "pw_test_net_raw", 1, true) then warned = warned + 1 end
                end
                expect(warned).to.equal(1)
            end
        }
    }
}
