-- Step 10: run the registered module hooks over a fresh server session and injected engine inputs.
-- Only the constructor and dependency injection below are private seams; the assertions use
-- the public getters, actual notifications, upload decoder and timer/output boundaries.

---@class PW.TestChallengeTimer
---@field interval number
---@field left integer zero repeats indefinitely
---@field due number
---@field run fun()

---@class PW.TestChallengeOutput
---@field owner Player
---@field state? PW.ChallengeWireState
---@field progress? PW.ChallengeFileItems
---@field delta? PW.ChallengeDelta

---@class PW.TestChallengeDependencies
---@field utc fun(): integer
---@field clock fun(): number
---@field phase fun(): PW.PhaseName
---@field players fun(): Player[]
---@field isPlayer fun(ply: Player): boolean
---@field catalogue fun(): PW.ChallengeCandidate[]
---@field matchContext fun(): { mode: string, modeBase: string[], playlist: string }
---@field schedule fun(name: string, interval: number, times: integer, run: fun())
---@field log fun(message: string)
---@field sendState fun(owner: Player, state: PW.ChallengeWireState)
---@field sendProgress fun(owner: Player, items: PW.ChallengeFileItems)
---@field sendDelta fun(owner: Player, delta: PW.ChallengeDelta)

---@class PW.TestChallengeServer
---@field module PW.Module
---@field lib PW.ChallengesLib
---@field utc integer
---@field now number
---@field phase PW.PhaseName
---@field players Player[]
---@field timers table<string, PW.TestChallengeTimer>
---@field logs string[]
---@field out PW.TestChallengeOutput[]

local index = 2967
local upload = "pw_challenges_upload"
local questionProbe = "PW.Test.WeeklyChallengeCanCount"
local customId = "pw_test:escaped"

---@param userId integer
---@param bot? boolean
---@return Player
local function actor(userId, bot)
    return { IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return bot == true end, UserID = function() return userId end,
        SteamID64 = function() return tostring(userId) end, Team = function() return 1 end,
        Alive = function() return true end, GetObserverMode = function() return OBS_MODE_NONE end } --[[@as Player]]
end

---@param lib PW.ChallengesLib
---@param defs table<string, table<string, any>>
---@param custom? PW.ChallengeEventTypes
---@return PW.ChallengeCandidate[]
local function catalogue(lib, defs, custom)
    ---@type PW.ChallengeCandidate[]
    local result = {}
    for id, def in pairs(defs) do
        def.Name, def.Description = id, id
        result[#result + 1] = { template = assert(lib._Compile(id, def, custom)) }
    end
    return result
end

---@param f PW.TestChallengeServer
---@param pool PW.ChallengeCandidate[]
---@param isPlayer? fun(ply: Player): boolean
---@return PW.TestChallengeDependencies
local function dependencies(f, pool, isPlayer)
    return {
        utc = function() return f.utc end, clock = function() return f.now end,
        phase = function() return f.phase end, players = function() return f.players end,
        isPlayer = isPlayer or function(ply) return IsValid(ply) and ply:IsPlayer() end,
        catalogue = function() return pool end,
        matchContext = function() return { mode = "ffa", modeBase = {}, playlist = "fixture" } end,
        schedule = function(name, interval, times, run)
            f.timers[name] = { interval = interval, left = times, due = f.now + interval, run = run }
        end,
        log = function(message) f.logs[#f.logs + 1] = message end,
        sendState = function(owner, state) f.out[#f.out + 1] = { owner = owner, state = state } end,
        sendProgress = function(owner, items) f.out[#f.out + 1] = { owner = owner, progress = items } end,
        sendDelta = function(owner, delta) f.out[#f.out + 1] = { owner = owner, delta = delta } end
    }
end

---@param defs table<string, table<string, any>>
---@param players Player[]
---@param isPlayer? fun(ply: Player): boolean
---@param custom? PW.ChallengeEventTypes
---@return PW.TestChallengeServer?
local function boot(defs, players, isPlayer, custom)
    local lib, module = PW.Challenges, PW.Modules.Get("challenges") --[[@as PW.Module?]]
    if lib == nil or module == nil then return nil end
    local new = rawget(lib, "_NewServer") --[[@as (fun(deps: PW.TestChallengeDependencies): table)?]]
    if new == nil then return nil end
    ---@type PW.TestChallengeServer
    local f = { lib = lib, module = module, utc = lib.WeekBounds(index), now = 0, phase = "LOBBY", players = players,
        timers = {}, logs = {}, out = {} }
    rawset(PW, "_ChallengeServer", new(dependencies(f, catalogue(lib, defs, custom), isPlayer)))
    return f
end

---@param f PW.TestChallengeServer
---@param time number
local function runDue(f, time)
    f.now = time
    local names = table.GetKeys(f.timers) --[[@as string[] ]]
    table.sort(names)
    for _, name in ipairs(names) do
        local job = f.timers[name]
        if job ~= nil and job.due <= time then
            local fn = job.run
            job.due = time + job.interval
            if job.left == 1 then f.timers[name] = nil
            elseif job.left > 1 then job.left = job.left - 1 end
            fn()
        end
    end
end

---@param f PW.TestChallengeServer
---@param time number
local function advance(f, time)
    local attempts = 0
    while true do
        ---@type number?
        local nextDue
        for _, job in pairs(f.timers) do
            if job.due <= time and (nextDue == nil or job.due < nextDue) then nextDue = job.due end
        end
        if nextDue == nil then break end
        attempts = attempts + 1
        assert(attempts <= 1000, "weekly scheduler must not rearm with zero delay")
        runDue(f, math.max(f.now, nextDue))
    end
    f.now = time
end

---@param f PW.TestChallengeServer
---@param phase PW.PhaseName
local function change(f, phase)
    local previous = f.phase
    f.phase = phase
    PW.Call(f.module, "PW_PhaseChange", phase, previous, 0)
end

---@param f PW.TestChallengeServer
local function start(f)
    change(f, "PREMATCH")
    change(f, "LIVE")
    PW.Call(f.module, "PW_MatchStart")
end

---@param f PW.TestChallengeServer
---@param ply Player
---@param ctx? table<string, any>
local function kill(f, ply, ctx)
    PW.Call(f.module, "PW_ScoreEvent", ply, "kill", 100, 100, nil, ctx)
end

---@param f PW.TestChallengeServer
---@param ply Player
local function win(f, ply)
    ---@type PW.MatchResult
    local result = { reason = "timelimit", teams = false, draw = false, winner = ply,
        standings = { { id = ply, score = 1 } } }
    PW.Call(f.module, "PW_MatchEnd", result)
end

---@param f PW.TestChallengeServer
---@param ply Player
---@param id string
---@return PW.ChallengeProgress?
local function progress(f, ply, id)
    local get = rawget(f.lib, "GetProgress") --[[@as (fun(ply: Player, id: string): PW.ChallengeProgress?)]]
    return get(ply, id)
end

---@param f PW.TestChallengeServer
---@param ply Player
---@param id string
---@return integer?
local function value(f, ply, id)
    local found = progress(f, ply, id)
    return found ~= nil and found.values[1] or nil
end

---@param f PW.TestChallengeServer
---@return integer?
local function weekIndex(f)
    local get = rawget(f.lib, "GetWeek") --[[@as (fun(): PW.ChallengeWeek?)]]
    local found = get()
    return found ~= nil and found.index or nil
end

---@param f PW.TestChallengeServer
---@param rows PW.ChallengeFileWeeks
---@return integer, fun(): integer
local function uploadWire(f, rows)
    ---@type integer[]
    local values = {}
    local bits, cursor = 0, 0
    f.lib._WriteWire("upload", rows, function(n, width)
        values[#values + 1], bits = n, bits + width
    end)
    return bits, function()
        cursor = cursor + 1
        return assert(values[cursor], "upload decoder read beyond the encoded packet")
    end
end

---@param f PW.TestChallengeServer
---@param ply Player
---@param kind "progress"|"delta"
---@return PW.TestChallengeOutput[]
local function sent(f, ply, kind)
    ---@type PW.TestChallengeOutput[]
    local messages = {}
    for _, message in ipairs(f.out) do
        if rawequal(message.owner, ply) and message[kind] ~= nil then messages[#messages + 1] = message end
    end
    return messages
end

---@param predicate PW.ChallengePredicate
---@param calls table<string, integer>
---@param kind string
---@return PW.ChallengePredicate
local function countMatcher(predicate, calls, kind)
    return function(ev)
        calls[kind] = calls[kind] + 1
        return predicate(ev)
    end
end

---@param plan PW.ChallengeProgressPlan
---@param calls table<string, integer>
local function watchPlan(plan, calls)
    for kind, route in pairs(plan.byType) do
        for _, objective in ipairs(route.increments) do
            objective.matches = countMatcher(objective.matches, calls, kind)
        end
        for _, rule in ipairs(route.resets) do rule.matches = countMatcher(rule.matches, calls, kind) end
    end
end

return {
    groupName = "PW challenges server events and scheduling",
    beforeEach = function(state) state.previous = rawget(PW, "_ChallengeServer") end,
    afterEach = function(state)
        hook.Remove("PW_ChallengeCanCount", questionProbe)
        rawset(PW, "_ChallengeServer", state.previous)
    end,
    cases = {
        {
            name = "Events: PW_ChallengeCanCount false drops the event",
            func = function()
                local ply = actor(11)
                local f = assert(boot({ kills = { Event = "kill", Target = 5 } }, { ply }))
                start(f)
                local calls = 0
                hook.Add("PW_ChallengeCanCount", questionProbe, function(owner, ev)
                    if rawequal(owner, ply) and ev.type == "kill" then
                        calls = calls + 1
                        return false
                    end
                end)
                kill(f, ply)
                expect(calls).to.equal(1)
                expect(value(f, ply, "kills") or 0).to.equal(0)
                hook.Remove("PW_ChallengeCanCount", questionProbe)
                kill(f, ply)
                expect(value(f, ply, "kills")).to.equal(1)
            end
        },
        {
            name = "Custom: Report validates type and data; an erroring Filter is isolated through PW.Call"
                .. " and other templates count",
            func = function()
                local lib = assert(PW.Challenges)
                local register = rawget(lib, "RegisterEventType")
                    --[[@as (fun(id: string, def: PW.ChallengeEventType): boolean)?]]
                local report = rawget(lib, "Report")
                    --[[@as (fun(ev: { type: string, player: Player, data?: table<string, any> }): boolean)?]]
                expect(register ~= nil and report ~= nil).to.beTrue()
                assert(register ~= nil and report ~= nil)
                local def = { fields = { role = "string", bonus = "number" } } --[[@as PW.ChallengeEventType]]
                expect(register("missing_namespace", def)).to.beFalse()
                expect(register(customId, def)).to.beTrue()
                local ply, bot = actor(11), actor(12, true)
                local brokenCalls = 0
                local f = assert(boot({
                    good = { Event = customId, Target = 5, Filters = { data = { role = "runner" } } },
                    broken = { Event = customId, Target = 5, Filter = function()
                        brokenCalls = brokenCalls + 1
                        error("intentional challenge predicate failure")
                    end }
                }, { ply, bot }, nil, { [customId] = def }))
                expect(report({ type = customId, player = ply })).to.beFalse()
                start(f)
                expect(report({ type = "pw_test:unknown", player = ply })).to.beFalse()
                expect(report({ type = customId, player = bot })).to.beFalse()
                local ev = { type = customId, player = ply, data = { role = "runner", bonus = "bad", extra = true } }
                expect(report(ev)).to.beTrue()
                expect(report(ev)).to.beTrue()
                expect(ev.data.bonus).to.equal("bad")
                expect(#f.logs).to.equal(1)
                expect(brokenCalls).to.equal(1)
                expect(value(f, ply, "broken") or 0).to.equal(0)
                expect(value(f, ply, "good")).to.equal(2)
            end
        },
        {
            name = "Events: bots never progress and bot victims count for humans",
            func = function()
                local owner, other, bot = actor(11), actor(12), actor(13, true)
                local fixture = boot({ bot_kills = { Event = "kill", Target = 2, Filters = { victimBot = true } } },
                    { owner, other, bot })
                expect(fixture ~= nil).to.beTrue()
                local f = assert(fixture)
                start(f)
                f.out = {}
                kill(f, owner, { victim = bot, victimBot = true })
                kill(f, bot, { victim = bot, victimBot = true })
                expect(value(f, owner, "bot_kills")).to.equal(1)
                expect(value(f, other, "bot_kills") or 0).to.equal(0)
                expect(progress(f, bot, "bot_kills")).to.beNil()
                advance(f, 10.1)
                for _, message in ipairs(f.out) do expect(rawequal(message.owner, owner)).to.beTrue() end
            end
        },
        {
            name = "Events: kill context reaches the matcher from PW_ScoreEvent",
            func = function()
                local ply, victim = actor(11), actor(12, true)
                local fixture = boot({
                    plain = { Event = "kill", Target = 5 },
                    precise = { Event = "kill", Target = 5,
                        Filters = { headshot = true, ads = false, distanceMin = 38, mode = "ffa",
                            playlist = "fixture" } }
                }, { ply, victim })
                expect(fixture ~= nil).to.beTrue()
                local f = assert(fixture)
                start(f)
                kill(f, ply, { victim = victim, victimBot = true, headshot = true, ads = false, distance = 38 })
                kill(f, ply)
                expect(value(f, ply, "plain")).to.equal(2)
                expect(value(f, ply, "precise")).to.equal(1)
            end
        },
        {
            name = "Events: events outside LIVE are dropped; match_end is processed at PW_MatchEnd",
            func = function()
                local owner, other = actor(11), actor(12)
                local fixture = boot({
                    kills = { Event = "kill", Target = 2 },
                    wins = { Event = "match_end", Target = 2, Filters = { won = true, placementMax = 1 } }
                }, { owner, other })
                expect(fixture ~= nil).to.beTrue()
                local f = assert(fixture)
                kill(f, owner)
                expect(value(f, owner, "kills") or 0).to.equal(0)
                start(f)
                kill(f, owner)
                win(f, owner) -- Core dispatches MatchEnd while the departing phase is still LIVE.
                change(f, "POSTMATCH")
                kill(f, owner)
                expect(value(f, owner, "kills")).to.equal(1)
                expect(value(f, owner, "wins")).to.equal(1)
                expect(value(f, other, "wins") or 0).to.equal(0)
            end
        },
        {
            name = "Events: native ingress rejects table actors without invoking player methods",
            func = function()
                local native = assert(PW._ChallengeServer).deps.isPlayer
                local calls = 0
                local mock = { IsValid = function() return true end, IsPlayer = function() return true end,
                    IsBot = function() return false end, Team = function() calls = calls + 1 return 1 end,
                    GetObserverMode = function() calls = calls + 1 return OBS_MODE_NONE end } --[[@as Player]]
                local f = assert(boot({ kills = { Event = "kill", Target = 2 } }, { mock }, native))
                start(f)
                PW.Call(f.module, "PW_PlayerSpawned", mock)
                kill(f, mock)
                stub(net, "ReadUInt").with(function() calls = calls + 1 return 0 end)
                assert(PW._Net.defs[upload]).handler(mock, 3)
                expect(calls).to.equal(0)
                expect(next(assert(PW._ChallengeServer).players)).to.beNil()
                expect(#f.out).to.equal(0)
            end
        },
        {
            name = "Events: legacy results end the match without inventing win, draw or placement facts",
            func = function()
                local ply = actor(11)
                local f = assert(boot({
                    played = { Event = "match_end", Target = 3 },
                    losses = { Event = "match_end", Target = 3, Filters = { won = false } },
                    decisive = { Event = "match_end", Target = 3, Filters = { draw = false } },
                    first = { Event = "match_end", Target = 3, Filters = { placementMax = 1 } },
                    timed = { Event = "time_played", Count = "value", Target = 100 }
                }, { ply }))
                start(f)
                advance(f, 8)
                PW.Call(f.module, "PW_MatchEnd", { winner = 2 })
                change(f, "POSTMATCH")
                expect(assert(PW._ChallengeServer).match).to.beNil()
                expect(value(f, ply, "played")).to.equal(1)
                expect(value(f, ply, "timed")).to.equal(8)
                expect(value(f, ply, "losses")).to.equal(0)
                expect(value(f, ply, "decisive")).to.equal(0)
                expect(value(f, ply, "first")).to.equal(0)
            end
        },
        {
            name = "Week: a match counts into the week it started in across a Monday boundary",
            func = function()
                local ply = actor(11)
                local fixture = boot({ kills = { Event = "kill", Target = 5 },
                    wins = { Event = "match_end", Target = 2, Filters = { won = true } } }, { ply })
                expect(fixture ~= nil).to.beTrue()
                local f = assert(fixture)
                local bits, read = uploadWire(f, {
                    [f.lib.WeekLabel(index)] = { index = index, items = { kills = { p = { 1 } } } },
                    [f.lib.WeekLabel(index + 1)] = { index = index + 1, items = {
                        kills = { p = { 999 } }, wins = { p = { 0 }, done = true }, unknown = { p = { 99 } }
                    } }
                })
                stub(net, "ReadUInt").with(read)
                assert(PW._Net.defs[upload]).handler(ply, bits)
                expect(value(f, ply, "kills")).to.equal(1)
                start(f)
                f.out = {}
                f.utc = f.lib.WeekBounds(index + 1)
                advance(f, 60.1)
                expect(weekIndex(f)).to.equal(index)
                kill(f, ply)
                win(f, ply)
                expect(value(f, ply, "kills")).to.equal(2)
                expect(value(f, ply, "wins")).to.equal(1)
                expect(weekIndex(f)).to.equal(index)
                change(f, "POSTMATCH")
                expect(weekIndex(f)).to.equal(index + 1)
                expect(value(f, ply, "kills")).to.equal(5)
                expect(value(f, ply, "wins")).to.equal(0)
                expect(progress(f, ply, "unknown")).to.beNil()
                local oldDelta, newState = 0, 0
                for i, message in ipairs(f.out) do
                    if message.delta and message.delta.index == index then oldDelta = i end
                    if message.state and message.state.week.index == index + 1 then newState = i end
                end
                expect(oldDelta > 0 and newState > oldDelta).to.beTrue()
            end
        },
        {
            name = "Week: a backwards clock jump keeps the session week; a forward jump selects the new week",
            func = function()
                local fixture = boot({ kills = { Event = "kill", Target = 5 } }, { actor(11) })
                expect(fixture ~= nil).to.beTrue()
                local f = assert(fixture)
                ---@type string[]
                local labels = {}
                stub(PW, "Notify").with(function(name, label)
                    if name == "PW_ChallengeWeek" and type(label) == "string" then labels[#labels + 1] = label end
                end)
                f.logs = {}
                f.utc = f.lib.WeekBounds(index - 1)
                advance(f, 60.1)
                advance(f, 120.2)
                expect(weekIndex(f)).to.equal(index)
                expect(#labels).to.equal(0)
                expect(#f.logs).to.equal(1)
                f.utc = f.lib.WeekBounds(index + 3)
                advance(f, 180.3)
                expect(weekIndex(f)).to.equal(index + 3)
                expect(labels).to.deepEqual({ f.lib.WeekLabel(index + 3) })
            end
        },
        {
            name = "Net: progress messages are throttled to one per interval per player and completions flush at once",
            func = function()
                local owner, other = actor(11), actor(12)
                local fixture = boot({ kills = { Event = "kill", Target = 3 },
                    untouched = { Event = "objective", Target = 3 } }, { owner, other })
                expect(fixture ~= nil).to.beTrue()
                local f = assert(fixture)
                start(f)
                f.out = {}
                kill(f, owner)
                kill(f, owner)
                kill(f, other)
                advance(f, 0.2)
                kill(f, other)
                local before = #sent(f, owner, "progress")
                expect(before <= 1).to.beTrue()
                expect(#sent(f, other, "progress") <= 1).to.beTrue()
                kill(f, owner)
                local updates = sent(f, owner, "progress")
                expect(#updates).to.equal(before + 1)
                local completed = assert(updates[#updates].progress)
                expect(completed.kills.done).to.beTrue()
                expect(completed.untouched).to.beNil()
                local saved = sent(f, owner, "delta")
                expect(#saved).to.equal(1)
                expect(assert(saved[1].delta).items.kills.p[1]).to.equal(3)
                expect(#sent(f, other, "delta")).to.equal(0)
                advance(f, 1.01)
                local otherUpdates = sent(f, other, "progress")
                expect(#otherUpdates >= 1 and #otherUpdates <= 2).to.beTrue()
                expect(assert(otherUpdates[#otherUpdates].progress).kills.p[1]).to.equal(2)
                PW.Call(f.module, "PW_ScoreEvent", other, "dom_capture", 100, 100)
                expect(#sent(f, other, "progress")).to.equal(#otherUpdates)
                change(f, "POSTMATCH")
                local after = sent(f, other, "progress")
                expect(#after).to.equal(#otherUpdates + 1)
                expect(assert(after[#after].progress).untouched.p[1]).to.equal(1)
            end
        },
        {
            name = "Net: dirty absolute deltas flush at ten seconds, phase change and disconnect",
            func = function()
                local ply, other = actor(11), actor(12)
                local fixture = boot({ kills = { Event = "kill", Target = 9 } }, { ply, other })
                expect(fixture ~= nil).to.beTrue()
                local f = assert(fixture)
                start(f)
                f.out = {}
                kill(f, ply)
                advance(f, 9.99)
                expect(#sent(f, ply, "delta")).to.equal(0)
                advance(f, 10.01)
                local first = assert(sent(f, ply, "delta")[1].delta)
                expect(first.label).to.equal(f.lib.WeekLabel(index))
                expect(first.items.kills.p[1]).to.equal(1)
                advance(f, 20.02)
                expect(#sent(f, ply, "delta")).to.equal(1)
                kill(f, ply)
                change(f, "POSTMATCH")
                local second = assert(sent(f, ply, "delta")[2].delta)
                expect(second.session).to.equal(first.session)
                expect(second.seq).to.equal(first.seq + 1)
                expect(second.items.kills.p[1]).to.equal(2)
                start(f)
                kill(f, ply)
                local disconnect = assert(assert(f.module._EngineHooks).PlayerDisconnected)
                disconnect(f.module, ply)
                local third = assert(sent(f, ply, "delta")[3].delta)
                expect(third.session).to.equal(second.session)
                expect(third.seq).to.equal(second.seq + 1)
                expect(third.items.kills.p[1]).to.equal(3)
                expect(#sent(f, other, "delta")).to.equal(0)
            end
        },
        {
            name = "Perf: one kill event touches only objectives of its type",
            func = function()
                local ply = actor(11)
                local fixture = boot({
                    kills = { Event = "kill", Target = 9 }, points = { Event = "score", Count = "value", Target = 999 },
                    deaths = { Event = "death", Target = 9 }
                }, { ply })
                expect(fixture ~= nil).to.beTrue()
                local f = assert(fixture)
                start(f)
                local apply = f.lib._AdvanceProgress
                ---@type table<string, integer>
                local calls = { kill = 0, score = 0, death = 0 }
                local watched = false
                stub(f.lib, "_AdvanceProgress").with(function(plan, state, ev)
                    if not watched then watchPlan(plan, calls) watched = true end
                    return apply(plan, state, ev)
                end)
                kill(f, ply)
                expect(calls).to.deepEqual({ kill = 1, score = 1, death = 0 })
                expect(value(f, ply, "kills")).to.equal(1)
                expect(value(f, ply, "points")).to.equal(100)
            end
        },
        {
            name = "Perf: the weekly module schedules rotation without a per-frame hook",
            func = function()
                local fixture = boot({ kills = { Event = "kill", Target = 9 } }, {})
                expect(fixture ~= nil).to.beTrue()
                local f = assert(fixture)
                local hooks = f.module._EngineHooks or {}
                expect(hooks.Think).to.beNil()
                expect(hooks.Tick).to.beNil()
                expect(rawget(f.module, "PW_Think")).to.beNil()
                local rotations = 0
                for _, job in pairs(f.timers) do
                    if job.interval == 60 and job.left == 0 then rotations = rotations + 1 end
                end
                expect(rotations).to.equal(1)
            end
        }
    }
}
