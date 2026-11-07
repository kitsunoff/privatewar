-- T-2.13 vote (TASKS.md, "Mandatory test cases" T-2.13: options sampled from the playlist; last two maps excluded
-- unless the playlist has < 3 maps; repeat excluded unless allowed; early end when all humans voted; bots never
-- vote; a vote change replaces the previous vote; a tie is broken at random among tied options; 08-lobby.md d.5,
-- 00-core.md d.2, d.5, 02-modes.md d.2, d.5b). Pure cases run over plain data with a deterministic RNG. Server cases
-- swap in a vote store with fakes (humans are plain tables, the one pool bot is a real bot). Core cases swap in a
-- fresh match store (fake clock and settings, isolated mode registry) and restore it, the vote store, the net
-- store and PW.ActiveMode afterwards; no ConVar is written.

local listenerId = "PW_Test_Vote"

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.VoteLib
local function lib()
    return must(PW.Vote)
end

---Park-Miller generator: deterministic numbers in [0, 1).
---@param seed integer
---@return fun(): number
local function seeded(seed)
    local value = seed
    return function()
        value = (value * 16807) % 2147483647
        return value / 2147483647
    end
end

---@param options PW.VoteOption[]
---@return string[]
local function keys(options)
    ---@type string[]
    local list = {}
    for _, option in ipairs(options) do list[#list + 1] = option.mode .. "@" .. option.map end
    return list
end

---@param overrides table<string, any>
---@return PW.VoteCandidateInput
local function input(overrides)
    ---@type table<string, any>
    local base = {
        modes = { tdm = 1, dom = 1 }, maps = { "gm_a", "gm_b", "gm_c", "gm_d" }, recent = {}, allowRepeat = false,
        count = 3, rng = seeded(11)
    }
    for key, value in pairs(overrides) do base[key] = value end
    return base --[[@as PW.VoteCandidateInput]]
end

---A fake human: a plain table the server glue treats like a player.
---@param name string
---@return table
local function human(name)
    return { name = name, IsBot = function() return false end }
end

---@param state table<string, any>
---@return string[]
local function logs(state)
    return state.logs --[[@as string[] ]]
end

---@param state table<string, any>
---@return table[]
local function sent(state)
    return state.sent --[[@as table[] ]]
end

---@param state table<string, any>
---@return integer
local function endCount(state)
    return state.ended --[[@as integer]]
end

---@param state table<string, any>
local function installStore(state)
    state.logs, state.sent, state.ended, state.recent = {}, {}, 0, { "gm_z" }
    state.humans = { human("a"), human("b") }
    state.source = { modes = { tdm = 1, ffa = 1 }, maps = { "gm_a", "gm_b", "gm_c", "gm_d" } }
    PW._Vote = lib()._NewStore({
        log = function(message) logs(state)[#logs(state) + 1] = message end,
        rng = seeded(5),
        source = function() return state.source or nil end,
        pool = function() return { "gm_pool" } end,
        fits = function() return true end,
        current = function() return { mode = "tdm", map = "gm_a" } end,
        getRecent = function() return state.recent end,
        setRecent = function(list) state.recent = list end,
        humans = function() return state.humans end,
        endVote = function()
            state.ended = endCount(state) + 1
            return true
        end,
        send = function(ply, view) sent(state)[#sent(state) + 1] = { ply = ply, state = view } end,
        resolveMode = function(id) return { ClassName = id, Name = string.upper(id) } end,
        count = function() return 3 end,
        allowRepeat = function() return state.allowRepeat == true end,
        canPick = function() return state.canPick == true end,
        readIndex = function() return state.index --[[@as integer]] end,
        readPick = function() return state.pickMode --[[@as string]], state.pickMap --[[@as string]] end,
        isMatchMode = function() return true end
    })
end

---Returns the one pool bot with the given usergroup.
---@param state table<string, any>
---@param group string
---@return Player
local function makeBot(state, group)
    local pool = state.pool --[[@as table<string, Player>]]
    local bot = pool.bot
    if bot == nil or not IsValid(bot) then
        bot = player.CreateNextBot("PW vote test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        pool.bot = bot
    end
    bot:SetUserGroup(group)
    return bot
end

---Sends one message from ply through the real wrapper (2 s after the previous one).
---@param state table<string, any>
---@param name string
---@param ply Player
---@return boolean
---@return string?
local function send(state, name, ply)
    local now = state.now --[[@as number]]
    state.now = now + 2
    return must(PW.Net)._Dispatch(name, 16, ply)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---A fresh match store with a fake clock and fixed durations, in rotation; two modes in an isolated registry.
---@param state table<string, any>
local function installMatch(state)
    -- The vote module hears the phase changes of this store: it must not open a vote for these test modes.
    PW._Vote.isMatchMode = function() return false end
    state.clock = 1000
    PW._Match = match()._NewStore({
        log = function(message) logs(state)[#logs(state) + 1] = message end,
        clock = function() return state.clock end,
        players = function() return {} end,
        settings = function()
            return { prematch = 60, countdown = 10, postmatch = 15, vote = 15, afterMatch = "rotation" }
        end
    })
    local registry = PW.Registry.New("test_vote", { log = function() end, preRegister = function() end })
    registry.Register({ Name = "First", Teams = 0 }, "pwt_first")
    registry.Register({ Name = "Second", Teams = 0 }, "pwt_second")
    registry.ResolveAll()
    state.registry = registry
    state.first = must(registry.Get("pwt_first"))
    state.second = must(registry.Get("pwt_second"))
end

---@param state table<string, any>
---@return table
local function second(state)
    return state.second --[[@as table]]
end

---Drives the match store from LOBBY to VOTE through the public flow.
---@param state table<string, any>
local function driveToVote(state)
    assert(match().Start(state.first), "Start failed")
    for _ = 1, 2 do
        state.clock = PW._Match.endsAt
        match()._Tick()
    end
    assert(match().Finish({}), "Finish failed")
    state.clock = PW._Match.endsAt
    match()._Tick()
    assert(match().GetPhase() == "VOTE", "not in VOTE")
end

local selectionCases = {
    {
        name = "Options are sampled from the playlist: distinct pairs of its modes and fitting maps, vote.options",
        func = function()
            local fits = function(modeId, map) return not (modeId == "dom" and map == "gm_d") end
            for seed = 1, 50 do
                local options = lib().Candidates(input({ rng = seeded(seed), fits = fits }))
                expect(#options).to.equal(3)
                ---@type table<string, true>
                local seen = {}
                for _, key in ipairs(keys(options)) do
                    expect(seen[key]).to.beNil()
                    seen[key] = true
                    expect(key ~= "dom@gm_d").to.beTrue()
                end
                for _, option in ipairs(options) do
                    expect(option.mode == "tdm" or option.mode == "dom").to.beTrue()
                    expect(table.HasValue({ "gm_a", "gm_b", "gm_c", "gm_d" }, option.map)).to.beTrue()
                end
            end
            expect(#lib().Candidates(input({ count = 20 }))).to.equal(8)
            expect(#lib().Candidates(input({ fits = function() return false end }))).to.equal(0)
        end
    },
    {
        name = "The playlist weights carry over: the first option's mode follows the mode weights",
        func = function()
            local rng = seeded(4242)
            local tdm, draws = 0, 4000
            for _ = 1, draws do
                local options = lib().Candidates(input({ modes = { tdm = 9, ffa = 1 }, count = 1, rng = rng }))
                if options[1].mode == "tdm" then tdm = tdm + 1 end
            end
            expect(math.abs(tdm / draws - 0.9) < 0.03).to.beTrue()
        end
    },
    {
        name = "The last two maps are excluded; with fewer than 3 maps in the playlist the rule is off",
        func = function()
            for seed = 1, 50 do
                local options = lib().Candidates(input({ rng = seeded(seed), recent = { "gm_a", "gm_b", "gm_c" } }))
                expect(#options).to.equal(3)
                for _, option in ipairs(options) do
                    expect(option.map == "gm_c" or option.map == "gm_d").to.beTrue()
                end
            end
            local small = lib().Candidates(input({ maps = { "gm_a", "gm_b" }, recent = { "gm_a", "gm_b" }, count = 4 }))
            expect(#small).to.equal(4)
            ---@type table<string, true>
            local maps = {}
            for _, option in ipairs(small) do maps[option.map] = true end
            expect(maps).to.deepEqual({ gm_a = true, gm_b = true })
            local fitting = lib().Candidates(input({ recent = { "gm_a", "gm_b" }, count = 8,
                fits = function(_, map) return map ~= "gm_d" end }))
            expect(#fitting).to.equal(2)
            for _, option in ipairs(fitting) do expect(option.map).to.equal("gm_c") end
        end
    },
    {
        name = "Same map and mode again is excluded unless vote.allowrepeat; a 24/7 playlist with one pair still runs",
        func = function()
            local base = { modes = { tdm = 1 }, maps = { "gm_a", "gm_b" }, count = 3,
                current = { mode = "tdm", map = "gm_a" } }
            expect(keys(lib().Candidates(input(base)))).to.deepEqual({ "tdm@gm_b" })
            base.allowRepeat = true
            local allowed = keys(lib().Candidates(input(base)))
            table.sort(allowed)
            expect(allowed).to.deepEqual({ "tdm@gm_a", "tdm@gm_b" })
            local only = input({ modes = { tdm = 1 }, maps = { "gm_a" }, current = { mode = "tdm", map = "gm_a" } })
            expect(keys(lib().Candidates(only))).to.deepEqual({ "tdm@gm_a" })
            local other = keys(lib().Candidates(input({ modes = { tdm = 1, ffa = 1 }, maps = { "gm_a" }, count = 3,
                current = { mode = "tdm", map = "gm_a" } })))
            expect(other).to.deepEqual({ "ffa@gm_a" })
        end
    },
    {
        name = "Recent maps: the newest first, no duplicates, two kept; the ConVar text round-trips",
        func = function()
            expect(lib().PushRecent({}, "gm_a")).to.deepEqual({ "gm_a" })
            expect(lib().PushRecent({ "gm_a" }, "gm_b")).to.deepEqual({ "gm_b", "gm_a" })
            expect(lib().PushRecent({ "gm_b", "gm_a" }, "gm_c")).to.deepEqual({ "gm_c", "gm_b" })
            expect(lib().PushRecent({ "gm_b", "gm_a" }, "gm_a")).to.deepEqual({ "gm_a", "gm_b" })
            expect(lib().ParseRecent(lib().FormatRecent({ "gm_a", "de_dust2" }))).to.deepEqual({ "gm_a", "de_dust2" })
            expect(lib().ParseRecent("")).to.deepEqual({})
            expect(lib().ParseRecent(" gm_a ,, ../bad, gm_b,gm_c")).to.deepEqual({ "gm_a", "gm_b" })
        end
    }
}

local tallyCases = {
    {
        name = "A vote change replaces the previous vote",
        func = function()
            local session = lib().NewSession({ { mode = "tdm", map = "gm_a" }, { mode = "ffa", map = "gm_b" } })
            local voter = human("a")
            expect(lib().Cast(session, voter, false, 1)).to.beTrue()
            expect(lib().Tally(session.votes, 2)).to.deepEqual({ 1, 0 })
            expect(lib().Cast(session, voter, false, 2)).to.beTrue()
            expect(lib().Tally(session.votes, 2)).to.deepEqual({ 0, 1 })
            expect({ lib().Cast(session, voter, false, 3) }).to.deepEqual({ false, "index" })
            expect({ lib().Cast(session, voter, false, 0) }).to.deepEqual({ false, "index" })
            expect(lib().Tally(session.votes, 2)).to.deepEqual({ 0, 1 })
        end
    },
    {
        name = "Bots never vote: a bot's vote is refused and bots are not counted as humans",
        func = function(state)
            local session = lib().NewSession({ { mode = "tdm", map = "gm_a" } })
            local bot = makeBot(state, "user")
            expect({ lib().Cast(session, bot, true, 1) }).to.deepEqual({ false, "bot" })
            expect(lib().Tally(session.votes, 1)).to.deepEqual({ 0 })
            local someone = human("a")
            expect(lib().Humans({ bot, someone })).to.deepEqual({ someone })
            expect(lib().AllVoted(lib().Humans({ bot }), session.votes)).to.beFalse()
        end
    },
    {
        name = "Early end decision: every human voted, and at least one human is there",
        func = function()
            local a, b = human("a"), human("b")
            ---@type table<any, integer>
            local votes = {}
            expect(lib().AllVoted({ a, b }, votes)).to.beFalse()
            votes[a] = 1
            expect(lib().AllVoted({ a, b }, votes)).to.beFalse()
            votes[b] = 2
            expect(lib().AllVoted({ a, b }, votes)).to.beTrue()
            expect(lib().AllVoted({}, votes)).to.beFalse()
        end
    },
    {
        name = "A tie is broken at random among the tied options only",
        func = function()
            expect(lib().Winner({ 2, 2, 1 }, function() return 0 end)).to.equal(1)
            expect(lib().Winner({ 2, 2, 1 }, function() return 0.99 end)).to.equal(2)
            expect(lib().Winner({ 1, 3, 3 }, function() return 0.5 end)).to.equal(3)
            expect(lib().Winner({ 0, 4, 1 }, function() return 0.99 end)).to.equal(2)
            local rng = seeded(77)
            local seen = { 0, 0, 0 }
            for _ = 1, 600 do
                local index = must(lib().Winner({ 2, 0, 2 }, rng))
                seen[index] = seen[index] + 1
            end
            expect(seen[2]).to.equal(0)
            expect(seen[1] > 200 and seen[3] > 200).to.beTrue()
            local none = { 0, 0, 0 }
            for _ = 1, 300 do
                local index = must(lib().Winner({ 0, 0, 0 }, rng))
                none[index] = none[index] + 1
            end
            expect(none[1] > 50 and none[2] > 50 and none[3] > 50).to.beTrue()
            expect(lib().Winner({}, rng)).to.beNil()
        end
    },
    {
        name = "The state round-trips through the explicit wire encoding; the screen model marks the own vote",
        func = function()
            ---@type PW.VoteState
            local view = { options = {
                { mode = "tdm", name = "Team Deathmatch", map = "gm_a", votes = 2 },
                { mode = "ffa", name = "Free-for-all", map = "gm_b", votes = 0 }
            }, mine = 2, canPick = true }
            ---@type any[]
            local wire = {}
            lib()._Encode(view, {
                uint = function(value) wire[#wire + 1] = value end,
                string = function(value) wire[#wire + 1] = value end,
                bool = function(value) wire[#wire + 1] = value end
            })
            local at = 0
            local function nextValue()
                at = at + 1
                return wire[at]
            end
            local decoded = lib()._Decode({ uint = nextValue, string = nextValue, bool = nextValue })
            expect(decoded).to.deepEqual(view)
            local model = lib()._Model(decoded, 9.2)
            expect(model.title).to.equal("VOTE FOR THE NEXT MATCH  10")
            expect(model.rows[1].label).to.equal("Team Deathmatch on gm_a")
            expect({ model.rows[1].votes, model.rows[1].mine }).to.deepEqual({ 2, false })
            expect(model.rows[2].mine).to.beTrue()
            expect(model.canPick).to.beTrue()
            expect(lib()._Model(decoded, nil).title).to.equal("VOTE FOR THE NEXT MATCH")
        end
    }
}

local serverCases = {
    {
        name = "Opening the vote samples the active source, excludes recent maps and sends every human the options",
        func = function(state)
            state.recent = { "gm_a", "gm_b" }
            local session = must(lib().Open())
            expect(#session.options).to.equal(3)
            for _, option in ipairs(session.options) do
                expect(option.map == "gm_c" or option.map == "gm_d").to.beTrue()
            end
            expect(#sent(state)).to.equal(2)
            expect(#sent(state)[1].state.options).to.equal(3)
            expect(sent(state)[1].state.options[1].name).to.equal(string.upper(session.options[1].mode))
            expect(sent(state)[1].state.mine).to.equal(0)
        end
    },
    {
        name = "Custom (no playlist): the current mode on the curated map list",
        func = function(state)
            state.source = false
            local session = must(lib().Open())
            expect(keys(session.options)).to.deepEqual({ "tdm@gm_pool" })
        end
    },
    {
        name = "Early end when all humans voted: the vote ends once, later votes are refused",
        func = function(state)
            lib().Open()
            local humans = state.humans --[[@as table[] ]]
            expect(lib()._Cast(humans[1], 1)).to.beTrue()
            expect(endCount(state)).to.equal(0)
            expect(lib()._Cast(humans[1], 2)).to.beTrue()
            expect(endCount(state)).to.equal(0)
            expect(lib()._Cast(humans[2], 2)).to.beTrue()
            expect(endCount(state)).to.equal(1)
            expect({ lib()._Cast(humans[2], 1) }).to.deepEqual({ false, "ended" })
            expect(endCount(state)).to.equal(1)
            local result = must(lib().Result())
            local session = must(PW._Vote.session)
            expect(result.mode.ClassName).to.equal(session.options[2].mode)
            expect(result.map).to.equal(session.options[2].map)
        end
    },
    {
        name = "Without votes the result is one of the options; a closed vote has no result",
        func = function()
            local session = must(lib().Open())
            local result = must(lib().Result())
            expect(table.HasValue(keys(session.options), result.mode.ClassName .. "@" .. result.map)).to.beTrue()
            expect(must(lib().Result()).map).to.equal(result.map)
            lib().Close()
            expect(lib().Result()).to.beNil()
        end
    },
    {
        name = "Host pick sets the next match directly and ends the vote; a mode that does not fit is refused",
        func = function(state)
            lib().Open()
            local st = PW._Vote --[[@as PW.VoteStore]]
            st.fits = function(modeId) return modeId ~= "dom" end
            expect({ lib()._Pick({}, "dom", "gm_x") }).to.deepEqual({ false, "fits" })
            expect(endCount(state)).to.equal(0)
            expect(lib()._Pick({}, "ffa", "gm_x")).to.beTrue()
            expect(endCount(state)).to.equal(1)
            local result = must(lib().Result())
            expect({ result.mode.ClassName, result.map }).to.deepEqual({ "ffa", "gm_x" })
        end
    },
    {
        name = "The map of a match that goes live is remembered as the newest recent map",
        func = function(state)
            lib()._Played("gm_new")
            expect(state.recent).to.deepEqual({ "gm_new", "gm_z" })
            lib()._Played("gm_z")
            expect(state.recent).to.deepEqual({ "gm_z", "gm_new" })
        end
    }
}

local netCases = {
    {
        name = "Bots never vote: a vote message from a bot is dropped and counts for nothing",
        func = function(state)
            lib().Open()
            local bot = makeBot(state, "superadmin")
            state.humans = { human("a") }
            state.index = 1
            expect(send(state, "pw_vote_cast", bot)).to.beTrue()
            expect(must(PW._Vote.session).votes[bot]).to.beNil()
            expect(endCount(state)).to.equal(0)
        end
    },
    {
        name = "Vote messages: VOTE phase only; the pick needs the privilege; a disabled module drops them",
        func = function(state)
            lib().Open()
            local bot = makeBot(state, "user")
            state.pickMode, state.pickMap = "ffa", "gm_b"
            expect({ send(state, "pw_vote_pick", bot) }).to.deepEqual({ false, "privilege" })
            makeBot(state, "superadmin")
            state.phase = "LOBBY"
            expect({ send(state, "pw_vote_cast", bot) }).to.deepEqual({ false, "phase" })
            state.phase = "VOTE"
            state.ownerValid = false
            expect({ send(state, "pw_vote_request", bot) }).to.deepEqual({ false, "disabled" })
            state.ownerValid = true
            expect(send(state, "pw_vote_request", bot)).to.beTrue()
            expect(#sent(state) >= 3).to.beTrue()
            expect(send(state, "pw_vote_pick", bot)).to.beTrue()
            expect(endCount(state)).to.equal(1)
        end
    },
    {
        name = "The messages registered when the module loaded are in the real net store, owned by vote",
        func = function(state)
            local real = state.previousNet --[[@as PW.NetStore]]
            local owner = must(PW.Modules.GetStored("vote"))
            for _, name in ipairs({ "pw_vote_cast", "pw_vote_pick", "pw_vote_request" }) do
                expect(must(real.defs[name]).owner).to.equal(owner)
                expect(table.GetKeys(must(real.defs[name]).phases)).to.deepEqual({ "VOTE" })
            end
            expect(must(real.defs.pw_vote_pick).who).to.equal("pw.vote.pick")
            expect(must(PW._Privileges.defs["pw.vote.pick"]).MinAccess).to.equal("superadmin")
            expect(util.NetworkStringToID("pw_vote_state")).toNot.equal(0)
        end
    }
}

local coreCases = {
    {
        name = "VOTE -> PREMATCH takes the next mode from PW_NextMatch; without an answer the same mode repeats",
        func = function(state)
            installMatch(state)
            driveToVote(state)
            hook.Add("PW_NextMatch", listenerId, function() return { mode = second(state) } end)
            state.clock = PW._Match.endsAt
            match()._Tick()
            expect(match().GetPhase()).to.equal("PREMATCH")
            expect(PW.ActiveMode).to.equal(state.second)
            hook.Remove("PW_NextMatch", listenerId)
            match().Abort("test")
            state.first = second(state)
            driveToVote(state)
            hook.Add("PW_NextMatch", listenerId, function() return { mode = "not a table" } end)
            state.clock = PW._Match.endsAt
            match()._Tick()
            expect(PW.ActiveMode).to.equal(state.second)
        end
    },
    {
        name = "EndVote ends VOTE before its timer with the next match; outside VOTE it does nothing",
        func = function(state)
            installMatch(state)
            expect(match().EndVote()).to.beFalse()
            driveToVote(state)
            hook.Add("PW_NextMatch", listenerId, function() return { mode = second(state), map = game.GetMap() } end)
            expect(match().EndVote()).to.beTrue()
            expect(match().GetPhase()).to.equal("PREMATCH")
            expect(PW.ActiveMode).to.equal(state.second)
            expect(match().GetPhaseEnd()).to.equal(state.clock + 60)
            expect(match().EndVote()).to.beFalse()
        end
    },
    {
        name = "A voted map change waits in VOTE without a timer, so the next tick does not start it again",
        func = function(state)
            installMatch(state)
            driveToVote(state)
            local begun = 0
            -- T-11.8: the core schedules the change (announced, begun after pw_mapchange_delay); count that call.
            stub(PW.MapChange, "Schedule").with(function()
                begun = begun + 1
                return true
            end)
            hook.Add("PW_NextMatch", listenerId, function() return { mode = second(state), map = "pwt_elsewhere" } end)
            expect(match().EndVote()).to.beTrue()
            expect(begun).to.equal(1)
            expect(match().GetPhase()).to.equal("VOTE")
            expect(match().GetPhaseEnd()).to.equal(-1)
            local clock = state.clock --[[@as number]]
            state.clock = clock + 100
            match()._Tick()
            expect(begun).to.equal(1)
        end
    }
}

---@param ... table[]
---@return table[]
local function join(...)
    ---@type table[]
    local all = {}
    for _, group in ipairs({ ... }) do
        for _, case in ipairs(group) do all[#all + 1] = case end
    end
    return all
end

return {
    groupName = "PW vote",
    beforeAll = function(state)
        state.pool = {}
    end,
    afterAll = function(state)
        local bot = (state.pool --[[@as table<string, Player>]]).bot
        if bot ~= nil and IsValid(bot) then bot:Kick("PW vote test finished") end
    end,
    beforeEach = function(state)
        state.previousNet = PW._Net
        state.previousVote = PW._Vote
        state.previousMatch = PW._Match
        state.previousMode = PW.ActiveMode
        state.now = 1000
        state.phase = "VOTE"
        state.ownerValid = true
        state.allowRepeat, state.canPick = false, false
        installStore(state)
        PW._Net = must(PW.Net)._NewStore({ log = function() end, clock = function() return state.now end,
            phase = function() return state.phase end })
        must(lib()._RegisterNet)({ IsValid = function() return state.ownerValid end })
    end,
    afterEach = function(state)
        hook.Remove("PW_NextMatch", listenerId)
        PW._Net = state.previousNet
        PW._Vote = state.previousVote
        PW._Match = state.previousMatch
        PW.ActiveMode = state.previousMode
        local registry = state.registry or nil --[[@as PW.Registry?]]
        if registry ~= nil then registry._Release() end
        state.registry = false
    end,
    cases = join(selectionCases, tallyCases, serverCases, netCases, coreCases)
}
