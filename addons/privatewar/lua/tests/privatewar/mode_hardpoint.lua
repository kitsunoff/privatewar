-- Phase 1 TEST-FIRST scaffold. Helpers do not exist yet; runtime RED is pending Deck authorization.
-- Every numeric value below is a synthetic fixture, never an approved setting or authored map coordinate.
-- Alternative boundary policies exercise injection only; freeze one approved policy before production code.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "Hardpoint draft dependency is absent; implementation and runtime RED are pending")
    return value
end

---@return PW.HardpointLib
local function lib()
    return must(PW.Hardpoint)
end

---@return PW.HardpointLayout
local function layout()
    return { zones = {
        { id = "synthetic_a", pos = Vector(0, 0, 0), radius = 20, below = 4, above = 12 },
        { id = "synthetic_b", pos = Vector(80, 0, 0), radius = 18, below = 3, above = 10 }
    } }
end

---@param team integer
---@param pos? Vector
---@return PW.HardpointActor
local function actor(team, pos)
    return { team = team, pos = pos or Vector(0, 0, 0), alive = true, observer = false, eligible = true }
end

---@return PW.HardpointRules
local function fixtureRules()
    return { pointTime = 4, tickInterval = 1, tickPoints = 1, scoreLimit = 99, matchTime = 12,
        maxSampleGap = 1, rotationBoundary = "exclude", deadlineBoundary = "exclude", limitPrecedence = "score",
        tieWinner = function() return nil end }
end

---@return PW.HardpointLayoutLimits
local function fixtureLimits()
    return { minZones = 2, maxZones = 8, maxIdBytes = 32, maxRadius = 100, maxHeight = 40 }
end

return {
    groupName = "PW Hardpoint draft rules",
    cases = {
        {
            name = "Hardpoint: empty and unequal contested occupancy score zero",
            func = function()
                local zone = must(layout().zones[1])
                for _, actors in ipairs({ {}, { actor(1), actor(1), actor(1), actor(2) },
                    { actor(1), actor(2), actor(2), actor(2) } }) do
                    local presence = lib().Presence(zone, actors)
                    expect(presence.control).to.equal(0)
                    expect(presence.contested).to.equal(#actors > 0)
                    local delta = lib().ScoreDelta(presence, 7)
                    expect(delta[1] or 0).to.equal(0)
                    expect(delta[2] or 0).to.equal(0)
                end
                for _, team in ipairs({ 1, 2 }) do
                    local presence = lib().Presence(zone, { actor(team), actor(team), actor(team) })
                    expect(presence.control).to.equal(team)
                    expect(presence.contested).to.beFalse()
                    expect(lib().ScoreDelta(presence, 7)[team]).to.equal(7)
                end
            end
        },
        {
            name = "Hardpoint: dead observers and other floors never count",
            func = function()
                local zone = must(layout().zones[1])
                local dead, observer, outsider = actor(2), actor(2), actor(2)
                dead.alive, observer.observer, outsider.eligible = false, true, false
                local presence = lib().Presence(zone, { actor(1), dead, observer, outsider,
                    actor(2, Vector(0, 0, 13)), actor(2, Vector(0, 0, -5)), actor(2, Vector(21, 0, 0)) })
                expect(presence.control).to.equal(1)
                expect(presence.contested).to.beFalse()
                expect(lib().Inside(zone, Vector(20, 0, 12))).to.beTrue()
                expect(lib().Inside(zone, Vector(0, 0, -4))).to.beTrue()
                expect(lib().Inside(zone, Vector(0, 0, 13))).to.beFalse()
            end
        },
        {
            name = "Hardpoint: rotation wraps and exact boundary scoring follows approved precedence",
            func = function()
                -- Candidate policy alternatives only; production precedence is NOT approved by this case.
                local index, visit, endsAt = lib().VisitAt(0, 8, 4, 2)
                expect(index).to.equal(1)
                expect(visit).to.equal(3)
                expect(endsAt).to.equal(12)
                for _, policy in ipairs({ "exclude", "include_old" }) do
                    local rules = fixtureRules()
                    rules.rotationBoundary = policy --[[@as "exclude"|"include_old"]]
                    local state = lib().NewState(layout(), rules, 0, 1)
                    for at = 0, 4 do lib().Step(state, { at = at, actors = { actor(1) } }) end
                    expect(state.index).to.equal(2)
                    expect(state.visit).to.equal(2)
                    expect(state.scores[1]).to.equal(policy == "exclude" and 3 or 4)
                end
            end
        },
        {
            name = "Hardpoint: stalls cannot backfill unsampled occupancy or finish twice",
            func = function()
                local rules = fixtureRules()
                rules.matchTime = 100
                local stalled = lib().NewState(layout(), rules, 0, 1)
                lib().Step(stalled, { at = 0, actors = {} })
                local effects = lib().Step(stalled, { at = 30, actors = { actor(1) } })
                expect(stalled.scores[1] or 0).to.equal(0)
                expect(stalled.scores[2] or 0).to.equal(0)
                expect(stalled.visit).to.equal(8)
                expect(stalled.zoneEndsAt).to.equal(32)
                expect(effects.finish).to.beNil()
                rules.scoreLimit = 1
                local terminal = lib().NewState(layout(), rules, 0, 2)
                lib().Step(terminal, { at = 0, actors = { actor(1) } })
                expect(lib().Step(terminal, { at = 1, actors = { actor(1) } }).finish).to.exist()
                expect(terminal.finished).to.beTrue()
                expect(lib().Step(terminal, { at = 1, actors = { actor(1) } }).finish).to.beNil()
                expect(lib().Step(terminal, { at = 40, actors = { actor(2) } }).finish).to.beNil()
                expect(terminal.scores[1]).to.equal(1)
                expect(terminal.scores[2] or 0).to.equal(0)
            end
        },
        {
            name = "Hardpoint: invalid authored layouts are hidden in Custom vote and playlists",
            func = function()
                local invalid = { layout(), layout(), layout(), layout(), layout(), layout(), layout() }
                invalid[1].zones = {}
                must(invalid[2].zones[2]).id = must(invalid[2].zones[1]).id
                must(invalid[3].zones[1]).radius = 0
                must(invalid[4].zones[1]).above = math.huge
                must(invalid[5].zones[1]).pos = Vector(math.huge, 0, 0)
                must(invalid[6].zones[1]).below = -1
                must(invalid[7].zones[1]).radius = 0 / 0
                expect(lib().ValidateLayout(layout(), fixtureLimits())).to.beTrue()
                -- Exercise the existing caller filters with synthetic data, without registering a playable mode.
                local maps = must(PW.Map)
                local oldGet = maps.Get
                local mode = { ClassName = "hardpoint", MapData = true, IsValid = function() return true end,
                    ValidateMapData = function(_, data) return lib().ValidateLayout(data, fixtureLimits()) end }
                local ok, err = pcall(function()
                    for _, data in ipairs(invalid) do
                        local accepted, reason = lib().ValidateLayout(data, fixtureLimits())
                        expect(accepted).to.beFalse()
                        expect(reason).to.exist()
                        rawset(maps, "Get", function() return { Modes = { hardpoint = data } } end)
                        expect(maps.ModeFits(mode, "pw_hp_synthetic")).to.beFalse()
                        local fits = function() return maps.ModeFits(mode, "pw_hp_synthetic") end
                        expect(PW.Lobby._CheckStart({ mode = "hardpoint", map = "pw_hp_synthetic" }, {
                            modes = { hardpoint = true }, mapExists = function() return true end, fits = fits
                        })).to.beFalse()
                        expect(PW.Playlist.Sample({ Name = "Synthetic HP", Modes = { hardpoint = 1 },
                            Maps = { "pw_hp_synthetic" }, Settings = {} }, {
                            rng = function() return 0 end, fits = fits
                        })).to.beNil()
                        expect(#PW.Vote.Candidates({ modes = { hardpoint = 1 }, maps = { "pw_hp_synthetic" },
                            fits = fits, recent = {}, allowRepeat = true, count = 1,
                            rng = function() return 0 end })).to.equal(0)
                    end
                    rawset(maps, "Get", function() return { Modes = { dom = { flags = {} } } } end)
                    expect(maps.ModeFits(mode, "pw_hp_synthetic")).to.beFalse()
                end)
                rawset(maps, "Get", oldGet)
                assert(ok, tostring(err))
            end
        }
    }
}
