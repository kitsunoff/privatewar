-- T-1.16 teams module (TASKS.md, "Mandatory test cases" T-1.16; 02-modes.md d.6; 08-lobby.md d.4; 00-core.md d.9).
-- Pure cases run over plain data (ids, team counts, preferences). The in-game cases use the listen host and one
-- bot created in beforeAll and kicked in afterAll (a kicked bot keeps its slot for a while and the suite is close
-- to maxplayers, so one bot only). Every case restores PW.ActiveMode, the module store PW._Teams, the host's team
-- and the bot's team.

local listenerId = "PW_Test_Teams"

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.TeamsLib
local function teams()
    return must(PW.Teams)
end

---Entries for _Assign: ids "p1".."pN" in order, each with the preference from prefs (same index).
---@param count integer
---@param prefs? table<integer, integer>
---@return PW.TeamEntry[]
local function entries(count, prefs)
    ---@type PW.TeamEntry[]
    local list = {}
    for i = 1, count do
        list[i] = { id = "p" .. i, pref = prefs ~= nil and prefs[i] or nil }
    end
    return list
end

---Team sizes of an assignment, indexed 1..n.
---@param assignment table<any, integer>
---@param n integer
---@return integer[]
local function sizes(assignment, n)
    ---@type integer[]
    local counts = {}
    for i = 1, n do counts[i] = 0 end
    for _, team in pairs(assignment) do counts[team] = counts[team] + 1 end
    return counts
end

---@param counts integer[]
---@return integer spread largest minus smallest team
local function spread(counts)
    local low, high = math.huge, -math.huge
    for _, count in ipairs(counts) do
        low = math.min(low, count)
        high = math.max(high, count)
    end
    return high - low
end

---A fake player for PW.IsEnemy: only Team() is read.
---@param team integer
---@return Player
local function fakePlayer(team)
    return { Team = function() return team end } --[[@as Player]]
end

---The in-game players: the listen host and the test bot.
---@param state table<string, any>
---@return Player[]
local function players(state)
    return { state.host --[[@as Player]], state.bot --[[@as Player]] }
end

return {
    groupName = "PW teams",
    beforeAll = function(state)
        local host = must(player.GetHumans()[1])
        state.host = host
        state.hostTeam = host:Team()
        local bot = player.CreateNextBot("PW teams test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        state.bot = bot
    end,
    afterAll = function(state)
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then bot:Kick("PW teams test finished") end
    end,
    beforeEach = function(state)
        state.previousMode = PW.ActiveMode
        state.previousStore = PW._Teams
        PW._Teams = teams()._NewStore()
    end,
    afterEach = function(state)
        hook.Remove("PW_IsEnemy", listenerId)
        PW.ActiveMode = state.previousMode
        PW._Teams = state.previousStore
        local host, bot = state.host --[[@as Player]], state.bot --[[@as Player]]
        if IsValid(host) then host:SetTeam(state.hostTeam --[[@as integer]]) end
        if IsValid(bot) then bot:SetTeam(TEAM_UNASSIGNED) end
    end,
    cases = {
        {
            name = "Assignment for 2 teams: everyone gets team 1 or 2, sizes differ by at most one, deterministic",
            func = function()
                local assign = teams()._Assign
                local result = assign(2, entries(5))
                expect(sizes(result, 2)).to.deepEqual({ 3, 2 })
                for i = 1, 5 do
                    local team = must(result["p" .. i])
                    expect(team >= 1 and team <= 2).to.beTrue()
                end
                expect(assign(2, entries(5))).to.deepEqual(result)
                expect(sizes(assign(2, entries(4)), 2)).to.deepEqual({ 2, 2 })
                expect(sizes(assign(2, entries(1)), 2)).to.deepEqual({ 1, 0 })
                expect(assign(2, {})).to.deepEqual({})
            end
        },
        {
            name = "Assignment for N = 3 and N = 4 is balanced for every player count from 0 to 13",
            func = function()
                local assign = teams()._Assign
                expect(sizes(assign(3, entries(7)), 3)).to.deepEqual({ 3, 2, 2 })
                expect(sizes(assign(4, entries(10)), 4)).to.deepEqual({ 3, 3, 2, 2 })
                for _, n in ipairs({ 2, 3, 4 }) do
                    for count = 0, 13 do
                        local counts = sizes(assign(n, entries(count)), n)
                        expect(spread(counts)).to.beLessThan(2)
                    end
                end
            end
        },
        {
            name = "Balance keeps preferences while the teams stay balanced and moves the overflow (2, 3 and 4 teams)",
            func = function()
                local assign = teams()._Assign
                -- Everyone wants team 1: the first half keeps it, the rest is moved to keep the balance.
                local two = assign(2, entries(4, { 1, 1, 1, 1 }))
                expect(two).to.deepEqual({ p1 = 1, p2 = 1, p3 = 2, p4 = 2 })
                -- Valid, balanced preferences are kept as they are.
                local kept = assign(3, entries(6, { 3, 3, 2, 2, 1, 1 }))
                expect(kept).to.deepEqual({ p1 = 3, p2 = 3, p3 = 2, p4 = 2, p5 = 1, p6 = 1 })
                -- Only one team may grow above floor(count / n): 5 players, 4 teams, all want team 4.
                local four = assign(4, entries(5, { 4, 4, 4, 4, 4 }))
                expect(four.p1).to.equal(4)
                expect(four.p2).to.equal(4)
                expect(spread(sizes(four, 4))).to.beLessThan(2)
                -- Preferences outside 1..n (another mode's teams, unassigned) are ignored.
                local ignored = assign(2, entries(2, { 3, 1001 }))
                expect(sizes(ignored, 2)).to.deepEqual({ 1, 1 })
            end
        },
        {
            name = "FFA (0 teams) assigns nobody",
            func = function()
                expect(teams()._Assign(0, entries(4, { 1, 2, 1, 2 }))).to.deepEqual({})
            end
        },
        {
            name = "GetActive lists the teams of the active mode, empty in FFA and outside a match",
            func = function()
                PW.ActiveMode = nil
                expect(teams().GetActive()).to.deepEqual({})
                PW.ActiveMode = { ClassName = "test_ffa", Teams = 0 }
                expect(teams().GetActive()).to.deepEqual({})
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2 }
                expect(teams().GetActive()).to.deepEqual({ 1, 2 })
                PW.ActiveMode = { ClassName = "test_four", Teams = 4 }
                expect(teams().GetActive()).to.deepEqual({ 1, 2, 3, 4 })
                expect(team.Valid(4)).to.beTrue()
            end
        },
        {
            name = "IsEnemy rule: different teams in a team mode; in FFA everyone else (a ~= b)",
            func = function()
                local rule = teams()._IsEnemyRule
                expect(rule(2, false, 1, 2)).to.beTrue()
                expect(rule(2, false, 1, 1)).to.beFalse()
                expect(rule(2, true, 1, 1)).to.beFalse()
                expect(rule(0, false, 1, 1)).to.beTrue()
                expect(rule(0, false, 1, 2)).to.beTrue()
                expect(rule(0, true, 1, 1)).to.beFalse()
            end
        },
        {
            name = "PW.IsEnemy: team mode compares teams, FFA compares players; a PW_IsEnemy answer wins",
            func = function()
                local isEnemy = must(PW.IsEnemy)
                local a, b, mate = fakePlayer(1), fakePlayer(2), fakePlayer(1)
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2 }
                expect(isEnemy(a, b)).to.beTrue()
                expect(isEnemy(a, mate)).to.beFalse()
                expect(isEnemy(a, a)).to.beFalse()
                PW.ActiveMode = { ClassName = "test_ffa", Teams = 0 }
                expect(isEnemy(a, mate)).to.beTrue()
                expect(isEnemy(a, b)).to.beTrue()
                expect(isEnemy(a, a)).to.beFalse()
                -- The mode's default answer, then a listener that overrides it (02-modes.md d.6, 01 d.18).
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2, PW_IsEnemy = function() return true end }
                expect(isEnemy(a, mate)).to.beTrue()
                hook.Add("PW_IsEnemy", listenerId, function() return false end)
                expect(isEnemy(a, b)).to.beFalse()
            end
        },
        {
            name = "Late joiner goes to the smaller team; ties go to the lowest team index (2, 3 and 4 teams)",
            func = function()
                local smallest = teams()._Smallest
                expect(smallest({ 3, 2 }, 2)).to.equal(2)
                expect(smallest({ 2, 3 }, 2)).to.equal(1)
                expect(smallest({ 2, 2 }, 2)).to.equal(1)
                expect(smallest({ 2, 1, 1 }, 3)).to.equal(2)
                expect(smallest({ 2, 2, 1, 2 }, 4)).to.equal(3)
                expect(smallest({}, 3)).to.equal(1)
                expect(smallest({ 1, 1 }, 0)).to.beNil()
                expect(teams()._Counts(3, { 1, 1, 3, 1001, 0, 4 })).to.deepEqual({ 2, 0, 1 })
            end
        },
        {
            name = "Pending file: team by SteamID64 for the target mode; read back without invalid entries",
            func = function()
                local rows = {
                    { sid = "76561198000000001", team = 2 }, { sid = "76561198000000002", team = 1 },
                    { sid = "76561198000000003", team = 3 }, { sid = "76561198000000004", team = TEAM_UNASSIGNED }
                }
                expect(teams()._ForFile(2, rows)).to.deepEqual({
                    ["76561198000000001"] = 2, ["76561198000000002"] = 1
                })
                expect(teams()._ForFile(0, rows)).to.deepEqual({})
                expect(teams()._FromFile({
                    ["76561198000000001"] = 2, ["76561198000000002"] = 1.5, ["76561198000000003"] = 0,
                    ["not a sid"] = 1, ["76561198000000004"] = "1"
                })).to.deepEqual({ ["76561198000000001"] = 2 })
            end
        },
        {
            name = "In game: assignment sets Player:Team() of the host and a bot, balanced across 2 and 3 teams",
            func = function(state)
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2 }
                teams()._AssignPlayers(players(state))
                ---@type integer[]
                local found = {}
                for _, ply in ipairs(players(state)) do found[#found + 1] = ply:Team() end
                expect(teams()._Counts(2, found)).to.deepEqual({ 1, 1 })
                PW.ActiveMode = { ClassName = "test_three", Teams = 3 }
                teams()._AssignPlayers(players(state))
                found = {}
                for _, ply in ipairs(players(state)) do found[#found + 1] = ply:Team() end
                expect(teams()._Counts(3, found)).to.deepEqual({ 1, 1, 0 })
            end
        },
        {
            name = "In game: a late joining bot is put into the smaller team",
            func = function(state)
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2 }
                local list = players(state)
                list[1]:SetTeam(1)
                list[2]:SetTeam(TEAM_UNASSIGNED)
                expect(teams()._PlaceLate(list[2], list)).to.equal(2)
                expect(list[2]:Team()).to.equal(2)
                PW.ActiveMode = { ClassName = "test_ffa", Teams = 0 }
                list[2]:SetTeam(TEAM_UNASSIGNED)
                expect(teams()._PlaceLate(list[2], list)).to.beNil()
                expect(list[2]:Team()).to.equal(TEAM_UNASSIGNED)
            end
        },
        {
            name = "In game: a join-in-progress spectator is not placed late (TEAM_SPECTATOR or pw_spectating)",
            func = function(state)
                PW.ActiveMode = { ClassName = "test_tdm", Teams = 2 }
                local list = players(state)
                local bot = list[2]
                list[1]:SetTeam(1)
                bot:SetTeam(TEAM_SPECTATOR)
                expect(teams()._PlaceLate(bot, list)).to.beNil()
                expect(bot:Team()).to.equal(TEAM_SPECTATOR)
                bot:SetTeam(TEAM_UNASSIGNED)
                bot:SetNW2Bool("pw_spectating", true)
                local placed = teams()._PlaceLate(bot, list)
                bot:SetNW2Bool("pw_spectating", false)
                expect(placed).to.beNil()
                expect(bot:Team()).to.equal(TEAM_UNASSIGNED)
            end
        },
        {
            name = "The teams module is registered, enabled and answers PW_PendingTeams only with something to say",
            func = function()
                local module = must(PW.Modules.Get("teams"))
                expect(module:IsValid()).to.beTrue()
                local answer = module.PW_PendingTeams
                expect(isfunction(answer)).to.beTrue()
                expect(answer(module, { ClassName = "test_ffa", Teams = 0 })).to.beNil()
            end
        },
        {
            name = "The PlayerSpawn hook belongs to the module (PW.HookFor), so it stops when the module is disabled",
            func = function()
                local module = must(PW.Modules.Get("teams"))
                expect(isfunction(must(module._EngineHooks).PlayerSpawn)).to.beTrue()
                local listeners = hook.GetTable().PlayerSpawn --[[@as table<any, function>]]
                expect(listeners[module]).to.exist()
                expect(listeners["PW.Teams"]).to.beNil()
            end
        }
    }
}
