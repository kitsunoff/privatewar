-- T-2.4 Domination (TASKS.md, "Mandatory test cases" T-2.4; 02-modes.md d.5, d.7; 03-mapdata.md d.4, d.6).
-- Pure cases over plain data: the capture step (rate x min(diff, 3), the +-100 stop, a contested point), the owner
-- rule, the held-point scoring, ValidateMapData and PW.Map.ModeFits ("mode hidden on a map without data") against
-- test registries swapped in for PW.Modes and PW.Maps, plus the playlist sampling and the lobby filter that use it.
-- The smoke case runs the real mode on the loaded map with fixture map data around the host: Start spawns the flag
-- entities, Think counts player stand-ins (no bots are created) and captures, a score tick scores the held flag.
-- PW.Score.Award and PW.Match.Finish are replaced by recorders, the mode's Setting is stubbed. Every case restores
-- what it replaced and removes its flags.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.DomMode
local function dom()
    return must(PW.Modes.Get("dom")) --[[@as PW.DomMode]]
end

---@return PW.DomFlagsLib
local function flags()
    return must(PW.DomFlags)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@return PW.MapLib
local function map()
    return must(PW.Map)
end

---@return Player
local function host()
    return must(player.GetHumans()[1])
end

---A test registry of the given kind; afterEach releases it.
---@param state table<string, any>
---@param kind string
---@return PW.Registry
local function registry(state, kind)
    local reg = PW.Registry.New(kind, { log = function() end })
    local list = state.registries --[[@as PW.Registry[] ]]
    list[#list + 1] = reg
    return reg
end

---Swaps PW.Maps for a test registry holding the given map entries by map name (afterEach restores it).
---@param state table<string, any>
---@param entries table<string, table>
local function useMaps(state, entries)
    local reg = registry(state, "maps")
    for name, entry in pairs(entries) do reg.Register(entry, map().Id(name)) end
    reg.ResolveAll()
    rawset(PW, "Maps", reg)
end

---Map data with flags A and B (and more letters when given).
---@param letters string[]
---@return table
local function domData(letters)
    ---@type table<string, Vector>
    local list = {}
    for index, letter in ipairs(letters) do list[letter] = Vector(index * 512, 0, 0) end
    return { Modes = { dom = { flags = list } } }
end

---A player stand-in for the presence pass.
---@param team integer
---@param pos Vector
---@param alive? boolean
---@return Player
local function standIn(team, pos, alive)
    ---@type table<string, any>
    local fake = {}
    fake.IsValid = function() return true end
    fake.Alive = function() return alive ~= false end
    fake.Team = function() return team end
    fake.GetPos = function() return pos end
    fake.GetObserverMode = function() return OBS_MODE_NONE end
    return fake --[[@as Player]]
end

return {
    groupName = "PW mode Domination",
    beforeEach = function(state)
        state.registries = {}
        state.maps = rawget(PW, "Maps")
        state.awards = {}
        state.finished = {}
        state.award = must(PW.Score).Award
        state.finish = match().Finish
        state.setting = rawget(dom(), "Setting")
        state.players = rawget(dom(), "_Players")
        local awards = state.awards --[[@as table[] ]]
        must(PW.Score).Award = function(ply, eventId)
            awards[#awards + 1] = { ply = ply, id = eventId }
            return true, 0, 0
        end
        local finished = state.finished --[[@as table[] ]]
        match().Finish = function(result)
            finished[#finished + 1] = result
            return true
        end
        rawset(dom(), "Setting", function(_, key)
            return ({ scorelimit = 200, timelimit = 600, capturerate = 10, tickinterval = 5 })[key]
        end)
    end,
    afterEach = function(state)
        must(dom().Cleanup)(dom())
        rawset(dom(), "Setting", state.setting)
        rawset(dom(), "_Players", state.players)
        must(PW.Score).Award = state.award --[[@as fun(ply: Player, eventId: string, opts?: PW.ScoreOpts): boolean]]
        match().Finish = state.finish --[[@as fun(result?: any): boolean]]
        rawset(PW, "Maps", state.maps)
        for _, reg in ipairs(state.registries --[[@as PW.Registry[] ]]) do reg._Release() end
    end,
    cases = {
        {
            name = "DOM is registered: two teams, needs map data, score limit 200, capture rate and tick settings",
            func = function()
                local mode = dom()
                expect(mode.Teams).to.equal(2)
                expect(mode.MapData).to.beTrue()
                local schema = PW.Settings._Schema(mode, "modes", function() end)
                expect(must(schema.scorelimit).default).to.equal(200)
                expect(must(schema.capturerate).default).to.equal(10)
                expect(must(schema.tickinterval).default).to.equal(5)
                expect(must(PW.Registries.score_events.Get("dom_capture")).Points).to.equal(200)
            end
        },
        {
            name = "The capture scalar moves by rate x min(diff, 3) toward the side with more players",
            func = function()
                local step = dom()._Step
                expect(step(0, 1, 0, 10, 1)).to.equal(10)
                expect(step(0, 2, 0, 10, 1)).to.equal(20)
                expect(step(0, 3, 0, 10, 1)).to.equal(30)
                expect(step(0, 7, 0, 10, 1)).to.equal(30)
                expect(step(0, 4, 1, 10, 1)).to.equal(30)
                expect(step(0, 3, 1, 10, 0.5)).to.equal(10)
                expect(step(0, 0, 1, 10, 1)).to.equal(-10)
                expect(step(20, 0, 5, 10, 2)).to.equal(-40)
            end
        },
        {
            name = "The capture scalar stops at +100 and -100",
            func = function()
                local step = dom()._Step
                expect(step(95, 1, 0, 10, 1)).to.equal(100)
                expect(step(100, 3, 0, 10, 1)).to.equal(100)
                expect(step(-95, 0, 2, 10, 1)).to.equal(-100)
                expect(step(-100, 0, 3, 10, 5)).to.equal(-100)
                expect(step(-100, 3, 0, 10, 1)).to.equal(-70)
            end
        },
        {
            name = "A contested point (equal counts) does not move; an empty point does not move either",
            func = function()
                local step = dom()._Step
                expect(step(40, 2, 2, 10, 1)).to.equal(40)
                expect(step(-60, 1, 1, 10, 1)).to.equal(-60)
                expect(step(40, 0, 0, 10, 1)).to.equal(40)
                expect(step(100, 3, 3, 10, 1)).to.equal(100)
            end
        },
        {
            name = "The owner changes only at +-100: team 1 at +100, team 2 at -100, kept in between",
            func = function()
                local owner = dom()._Owner
                expect(owner(100, 0)).to.equal(1)
                expect(owner(-100, 1)).to.equal(2)
                expect(owner(30, 2)).to.equal(2)
                expect(owner(-99, 0)).to.equal(0)
            end
        },
        {
            name = "Scoring per held point: each owned flag adds the tick points to its team",
            func = function()
                local scores = { [1] = 5 }
                local changed = dom()._Hold({ { owner = 1 }, { owner = 1 }, { owner = 2 }, { owner = 0 } }, scores, 1)
                expect(scores[1]).to.equal(7)
                expect(scores[2]).to.equal(1)
                expect(changed[1]).to.beTrue()
                expect(changed[2]).to.beTrue()
                local none = dom()._Hold({ { owner = 0 } }, scores, 1)
                expect(next(none)).to.beNil()
                expect(scores[1]).to.equal(7)
            end
        },
        {
            name = "ValidateMapData rejects fewer than 2 flags and flags that are not Vectors",
            func = function()
                local mode = dom()
                local ok, reason = mode:ValidateMapData({})
                expect(ok).to.beFalse()
                expect(reason).to.exist()
                expect(mode:ValidateMapData({ flags = {} })).to.beFalse()
                expect(mode:ValidateMapData({ flags = { A = Vector(0, 0, 0) } })).to.beFalse()
                expect(mode:ValidateMapData({ flags = { A = Vector(0, 0, 0), B = "here" } })).to.beFalse()
                expect(mode:ValidateMapData({ flags = { A = Vector(0, 0, 0), B = Vector(9, 0, 0) } })).to.beTrue()
                local list = dom()._ParseFlags({ flags = { C = Vector(3, 0, 0), A = Vector(1, 0, 0) } })
                expect(#list).to.equal(2)
                expect(list[1].letter).to.equal("A")
                expect(list[2].letter).to.equal("C")
            end
        },
        {
            name = "The mode is hidden on a map without data: ModeFits is false without a file, entry or 2 flags",
            func = function(state)
                useMaps(state, {
                    pw_dom_good = domData({ "A", "B", "C" }),
                    pw_dom_one = domData({ "A" }),
                    pw_dom_none = { Modes = { tdm = {} } }
                })
                local fits = map().ModeFits
                expect(fits(dom(), "pw_dom_good")).to.beTrue()
                expect(fits(dom(), "pw_dom_one")).to.beFalse()
                expect(fits(dom(), "pw_dom_none")).to.beFalse()
                expect(fits(dom(), "pw_dom_nofile")).to.beFalse()
                local tdm = must(PW.Modes.Get("tdm"))
                expect(fits(tdm, "pw_dom_nofile")).to.beTrue()
                expect(fits(tdm, "pw_dom_one")).to.beTrue()
            end
        },
        {
            name = "Hidden in playlists and the lobby: sampling never pairs DOM with a map without data",
            func = function(state)
                useMaps(state, { pw_dom_good = domData({ "A", "B" }) })
                local fits = function(modeId, name)
                    return map().ModeFits(must(PW.Modes.Get(modeId)), name)
                end
                local data = { Name = "Mixed", Modes = { dom = 1, tdm = 1 }, Settings = {} }
                for draw = 1, 40 do
                    local value = (draw - 0.5) / 40
                    local pick = must(PW.Playlist.Sample(data, {
                        rng = function() return value end, maps = { "pw_dom_plain", "pw_dom_good" }, fits = fits
                    }))
                    if pick.mode == "dom" then expect(pick.map).to.equal("pw_dom_good") end
                end
                local only = { Name = "DOM", Modes = { dom = 1 }, Maps = { "pw_dom_plain" }, Settings = {} }
                expect(PW.Playlist.Sample(only, { rng = function() return 0 end, fits = fits })).to.beNil()
                local refused, reason = PW.Lobby._CheckStart({ mode = "dom", map = "pw_dom_plain" },
                    { modes = { dom = true }, mapExists = function() return true end, fits = fits })
                expect(refused).to.beFalse()
                expect(reason).to.exist()
                local lobbyState = { map = "pw_dom_plain", maps = { "pw_dom_good", "pw_dom_plain" },
                    modes = { { id = "dom", name = "Domination", groups = {} } }, toggles = {},
                    canStart = true, canEdit = false, canToggle = false }
                local model = PW.Lobby._Model(lobbyState, { mode = "dom" }, fits)
                expect(#model.maps).to.equal(1)
                expect(model.maps[1].id).to.equal("pw_dom_good")
                expect(model.map).to.equal("pw_dom_good")
            end
        },
        {
            name = "Presence: alive players inside a flag's radius count by team; the dead and the far do not",
            func = function()
                local at = Vector(100, 100, 0)
                local lib = flags()
                local infos = lib._Infos({
                    standIn(1, at), standIn(1, at + Vector(lib.Radius - 1, 0, 0)), standIn(2, at + Vector(0, 0, 40)),
                    standIn(2, at, false), standIn(2, at + Vector(lib.Radius + 1, 0, 0)),
                    standIn(1, at + Vector(0, 0, lib.Above + 1))
                })
                local out = lib._Presence({ at }, infos)
                expect(must(out[1]).counts[1]).to.equal(2)
                expect(must(out[1]).counts[2]).to.equal(1)
                expect(#must(must(out[1]).members[1])).to.equal(2)
            end
        },
        {
            name = "Smoke: Start spawns the flags from map data, Think captures with players inside, ticks score",
            func = function(state)
                local origin = host():GetPos()
                useMaps(state, { [game.GetMap()] = { Modes = { dom = { flags = {
                    A = origin, B = origin + Vector(2048, 0, 0)
                } } } } })
                local alpha = standIn(1, origin)
                local crowd = { alpha, standIn(1, origin), standIn(2, origin + Vector(4096, 0, 0)) }
                rawset(dom(), "_Players", function() return crowd end)
                local mode = dom()
                must(mode.Start)(mode)
                local list = flags().GetAll()
                expect(#list).to.equal(2)
                expect(must(list[1]):GetLetter()).to.equal("A")
                expect(must(list[1]):UpdateTransmitState()).to.equal(TRANSMIT_ALWAYS)
                local now = CurTime()
                mode._LastStep = now - 5
                mode._NextStep = now
                must(mode.Think)(mode)
                local flagA = must(must(mode._Flags)[1])
                expect(flagA.value).to.equal(100)
                expect(flagA.owner).to.equal(1)
                expect(must(list[1]):GetOwnerTeam()).to.equal(1)
                local awards = state.awards --[[@as table[] ]]
                expect(#awards).to.equal(2)
                expect(must(awards[1]).id).to.equal("dom_capture")
                expect(must(must(mode._Flags)[2]).owner).to.equal(0)
                mode._NextTick = now
                must(mode.Think)(mode)
                expect(must(mode._Scores)[1]).to.equal(1)
                expect(dom().GetScore(1)).to.equal(1)
                local finished = state.finished --[[@as table[] ]]
                expect(#finished).to.equal(0)
                must(mode.Cleanup)(mode)
                expect(#flags().GetAll()).to.equal(0)
            end
        },
        {
            name = "Score limit: the team that reaches the limit wins",
            func = function(state)
                local mode = dom()
                mode._StartedAt = CurTime()
                mode._Scores = { [1] = 199, [2] = 50 }
                mode._Flags = { { letter = "A", pos = Vector(0, 0, 0), value = 100, owner = 1 } }
                mode._NextStep = CurTime() + 60
                mode._NextTick = CurTime()
                must(mode.Think)(mode)
                local finished = state.finished --[[@as PW.MatchResult[] ]]
                expect(#finished).to.equal(1)
                expect(must(finished[1]).reason).to.equal("scorelimit")
                expect(must(finished[1]).winner).to.equal(1)
            end
        },
        {
            name = "Cost: one presence pass for 5 flags and 24 players stays well under a millisecond",
            func = function()
                local lib = flags()
                ---@type Vector[]
                local points = {}
                for i = 1, 5 do points[i] = Vector(i * 600, 0, 0) end
                ---@type Player[]
                local players = {}
                for i = 1, 24 do players[i] = standIn(i % 2 + 1, Vector(i * 120, 10, 0)) end
                local runs = 200
                local start = SysTime()
                for _ = 1, runs do lib._Presence(points, lib._Infos(players)) end
                local perPass = (SysTime() - start) / runs * 1000
                print(string.format("[PW] DOM presence pass (5 flags, 24 players): %.4f ms", perPass))
                expect(perPass < 1).to.beTrue()
            end
        }
    }
}
