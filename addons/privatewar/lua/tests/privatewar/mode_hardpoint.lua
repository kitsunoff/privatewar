-- Phase 1 TEST-FIRST scaffold. Helpers do not exist yet; runtime RED is pending Deck authorization.
-- Approved preset: 60-second zones, one point per verified second, 250 points or 600 seconds, tied score draw.
-- Positions are synthetic fixtures, never authored/playable map coordinates. No alternative boundary policies.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "Hardpoint dependency is absent; implementation and runtime RED are pending")
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
    return { pointTime = 60, scoreLimit = 250, matchTime = 600 }
end

return {
    groupName = "PW Hardpoint rules",
    cases = {
        {
            name = "Hardpoint: configurable preset has positive finite clamped settings and no policy knobs",
            func = function()
                local mode = must(PW.Modes.Get("hardpoint"))
                expect(mode.Teams).to.equal(2)
                expect(mode.MapData).to.beTrue()
                local schema = PW.Settings._Schema(mode, "modes", function() end)
                for key, values in pairs({ zonetime = { 60, 5, 600 }, scorelimit = { 250, 1, 1000 },
                    timelimit = { 600, 60, 3600 } }) do
                    local definition = must(schema[key])
                    expect(definition.default).to.equal(values[1])
                    expect(definition.min).to.equal(values[2])
                    expect(definition.max).to.equal(values[3])
                    local low, lowValue = PW.Settings._Validate(definition, 0)
                    local high, highValue = PW.Settings._Validate(definition, 99999)
                    expect(low).to.beTrue()
                    expect(lowValue).to.equal(values[2])
                    expect(high).to.beTrue()
                    expect(highValue).to.equal(values[3])
                    for _, nonfinite in ipairs({ math.huge, -math.huge, 0 / 0 }) do
                        expect(PW.Settings._Validate(definition, nonfinite)).to.beFalse()
                    end
                end
                for _, key in ipairs({ "rotationBoundary", "deadlineBoundary", "limitPrecedence", "tieWinner",
                    "tickinterval", "tickpoints", "maxsamplegap" }) do expect(schema[key]).to.beNil() end
            end
        },
        {
            name = "Hardpoint: empty and unequal contested occupancy score zero",
            func = function()
                local zone = must(layout().zones[1])
                for _, actors in ipairs({ {}, { actor(1), actor(1), actor(1), actor(2) },
                    { actor(1), actor(2), actor(2), actor(2) } }) do
                    local presence = lib().Presence(zone, actors)
                    expect(presence.control).to.equal(0)
                    expect(presence.contested).to.equal(#actors > 0)
                    local delta = lib().ScoreDelta(presence, 1)
                    expect(delta[1] or 0).to.equal(0)
                    expect(delta[2] or 0).to.equal(0)
                end
                for _, team in ipairs({ 1, 2 }) do
                    local presence = lib().Presence(zone, { actor(team), actor(team), actor(team) })
                    expect(presence.control).to.equal(team)
                    expect(presence.contested).to.beFalse()
                    expect(lib().ScoreDelta(presence, 1)[team]).to.equal(1)
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
                local index, visit, endsAt = lib().VisitAt(0, 120, 60, 2)
                expect(index).to.equal(1)
                expect(visit).to.equal(3)
                expect(endsAt).to.equal(180)
                local state = lib().NewState(layout(), fixtureRules(), 0, 1)
                expect(state.index).to.equal(1)
                expect(state.visit).to.equal(1)
                for at = 0, 59 do lib().Step(state, { at = at, actors = { actor(1) } }) end
                expect(state.scores[1]).to.equal(59)
                local effects = lib().Step(state, { at = 60, actors = { actor(1) } })
                expect(state.scores[1]).to.equal(60)
                expect(state.index).to.equal(2)
                expect(state.visit).to.equal(2)
                expect(state.zoneEndsAt).to.equal(120)
                expect(effects.rotated).to.beTrue()
                expect(effects.finish).to.beNil()
                local rules = fixtureRules()
                rules.scoreLimit = 60
                local terminal = lib().NewState(layout(), rules, 0, 2)
                for at = 0, 59 do lib().Step(terminal, { at = at, actors = { actor(1) } }) end
                local finish = lib().Step(terminal, { at = 60, actors = { actor(1) } })
                expect(must(finish.finish).winner).to.equal(1)
                expect(terminal.scores[1]).to.equal(60)
                expect(finish.rotated).to.beFalse()
                expect(terminal.visit).to.equal(1)
            end
        },
        {
            name = "Hardpoint: boundary departure and new-zone entry cannot credit unseen occupancy",
            func = function()
                for _, occupied in ipairs({ true, false }) do
                    local state = lib().NewState(layout(), fixtureRules(), 0, 1)
                    for at = 0, 59 do
                        lib().Step(state, { at = at, actors = occupied and { actor(1) } or {} })
                    end
                    lib().Step(state, { at = 59.5, actors = occupied and { actor(1) } or {} })
                    local arrival = { actor(2, Vector(80, 0, 0)) }
                    lib().Step(state, { at = 60, actors = arrival })
                    expect(state.scores[1] or 0).to.equal(occupied and 59 or 0)
                    expect(state.scores[2] or 0).to.equal(0)
                    local duplicate = lib().Step(state, { at = 60, actors = { actor(1) } })
                    expect(duplicate.rotated).to.beFalse()
                    expect(duplicate.finish).to.beNil()
                    lib().Step(state, { at = 60.5, actors = arrival })
                    expect(state.scores[2] or 0).to.equal(0)
                    lib().Step(state, { at = 61, actors = arrival })
                    expect(state.scores[2]).to.equal(1)
                end
            end
        },
        {
            name = "Hardpoint: stalls cannot backfill unsampled occupancy or finish twice",
            func = function()
                local rules = fixtureRules()
                rules.pointTime = 5
                rules.matchTime = 100
                local stalled = lib().NewState(layout(), rules, 0, 1)
                lib().Step(stalled, { at = 0, actors = {} })
                local effects = lib().Step(stalled, { at = 30, actors = { actor(1) } })
                expect(stalled.scores[1] or 0).to.equal(0)
                expect(stalled.scores[2] or 0).to.equal(0)
                expect(stalled.visit).to.equal(7)
                expect(stalled.zoneEndsAt).to.equal(35)
                expect(effects.finish).to.beNil()
                lib().Step(stalled, { at = 30.5, actors = { actor(1) } })
                expect(stalled.scores[1] or 0).to.equal(0)
                lib().Step(stalled, { at = 31, actors = { actor(1) } })
                expect(stalled.scores[1]).to.equal(1)
                local fractional = lib().NewState(layout(), fixtureRules(), 0, 3)
                lib().Step(fractional, { at = 0, actors = { actor(1) } })
                lib().Step(fractional, { at = 0.5, actors = { actor(1) } })
                lib().Step(fractional, { at = 2, actors = { actor(1) } })
                lib().Step(fractional, { at = 2.5, actors = { actor(1) } })
                expect(fractional.scores[1] or 0).to.equal(0)
                lib().Step(fractional, { at = 3, actors = { actor(1) } })
                expect(fractional.scores[1]).to.equal(1)
                rules.scoreLimit = 1
                local terminal = lib().NewState(layout(), rules, 0, 2)
                lib().Step(terminal, { at = 0, actors = { actor(1) } })
                expect(lib().Step(terminal, { at = 1, actors = { actor(1) } }).finish).to.exist()
                expect(terminal.finished).to.beTrue()
                expect(lib().Step(terminal, { at = 1, actors = { actor(1) } }).finish).to.beNil()
                expect(lib().Step(terminal, { at = 40, actors = { actor(2) } }).finish).to.beNil()
                expect(terminal.scores[1]).to.equal(1)
                expect(terminal.scores[2] or 0).to.equal(0)
                expect(terminal.visit).to.equal(1)
            end
        },
        {
            name = "Hardpoint: subsecond continuity scores whole points without multiplying occupants",
            func = function()
                local state = lib().NewState(layout(), fixtureRules(), 0, 1)
                local crowd = { actor(1), actor(1), actor(1) }
                lib().Step(state, { at = 0, actors = crowd })
                for tick = 1, 9 do lib().Step(state, { at = tick / 10, actors = crowd }) end
                expect(state.scores[1] or 0).to.equal(0)
                lib().Step(state, { at = 1, actors = crowd })
                expect(state.scores[1]).to.equal(1)
                lib().Step(state, { at = 1.5, actors = crowd })
                lib().Step(state, { at = 2, actors = { actor(1), actor(2) } })
                expect(state.scores[1]).to.equal(1)
                lib().Step(state, { at = 2.5, actors = crowd })
                lib().Step(state, { at = 3, actors = crowd })
                expect(state.scores[1]).to.equal(1)
                lib().Step(state, { at = 3.5, actors = crowd })
                expect(state.scores[1]).to.equal(2)
            end
        },
        {
            name = "Hardpoint: deadline credits verified intervals before final standings and draws equal scores",
            func = function()
                local rules = fixtureRules()
                rules.scoreLimit = 1000
                for _, tied in ipairs({ true, false }) do
                    local state = lib().NewState(layout(), rules, 0, 1)
                    -- Equal starting scores isolate the final interval; this is pure state, not engine score.
                    state.scores[1], state.scores[2] = 10, tied and 11 or 10
                    lib().Step(state, { at = 599, actors = { actor(1, Vector(80, 0, 0)) } })
                    expect(state.scores[1]).to.equal(10)
                    local result = lib().Step(state, { at = 600, actors = {
                        actor(1, Vector(80, 0, 0))
                    } })
                    expect(state.scores[1]).to.equal(11)
                    expect(state.scores[2]).to.equal(tied and 11 or 10)
                    expect(must(result.finish).draw).to.equal(tied)
                    if tied then
                        expect(must(result.finish).winner).to.beNil()
                    else
                        expect(must(result.finish).winner).to.equal(1)
                    end
                    expect(result.rotated).to.beFalse()
                    expect(lib().Step(state, { at = 601, actors = { actor(2) } }).finish).to.beNil()
                end
                local noHistory = lib().NewState(layout(), rules, 0, 2)
                lib().Step(noHistory, { at = 0, actors = {} })
                local result = lib().Step(noHistory, { at = 600, actors = { actor(1) } })
                expect(noHistory.scores[1] or 0).to.equal(0)
                expect(must(result.finish).draw).to.beTrue()
                expect(result.rotated).to.beFalse()
            end
        },
        {
            name = "Hardpoint: authored schema enforces dense finite bounded unique zones",
            func = function()
                local boundary = layout()
                local first = must(boundary.zones[1])
                first.id, first.radius, first.above, first.below = string.rep("a", 32), 4096, 2048, 0
                expect(lib().ValidateLayout(boundary)).to.beTrue()
                local invalid = { layout(), layout(), layout(), layout(), layout(), layout(), layout(), layout() }
                must(invalid[1].zones[1]).id = string.rep("a", 33)
                must(invalid[2].zones[1]).radius = 4097
                must(invalid[3].zones[1]).above = 2049
                must(invalid[4].zones[1]).id = ""
                must(invalid[5].zones[1]).above = 0
                invalid[6].zones = { must(layout().zones[1]) }
                rawset(invalid[7].zones, 2, nil)
                rawset(invalid[7].zones, 3, must(layout().zones[2]))
                must(invalid[8].zones[1]).above, must(invalid[8].zones[1]).below = 2048, 1
                for _, data in ipairs(invalid) do expect(lib().ValidateLayout(data)).to.beFalse() end
                local many = layout()
                for index = 3, 16 do
                    many.zones[index] = { id = "synthetic_" .. index, pos = Vector(index * 80, 0, 0),
                        radius = 20, above = 12, below = 4 }
                end
                expect(lib().ValidateLayout(many)).to.beTrue()
                many.zones[17] = { id = "overflow", pos = Vector(0, 80, 0), radius = 20, above = 12, below = 4 }
                expect(lib().ValidateLayout(many)).to.beFalse()
                for _, raw in ipairs({ false, 12, "zones", { zones = "not an array" } }) do
                    expect(lib().ValidateLayout(raw)).to.beFalse()
                end
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
                expect(lib().ValidateLayout(layout())).to.beTrue()
                -- Exercise the existing caller filters with synthetic data, without registering a playable mode.
                local maps = must(PW.Map)
                local oldGet = maps.Get
                local mode = { ClassName = "hardpoint", MapData = true, IsValid = function() return true end,
                    ValidateMapData = function(_, data) return lib().ValidateLayout(data) end }
                local ok, err = pcall(function()
                    for _, data in ipairs(invalid) do
                        local accepted, reason = lib().ValidateLayout(data)
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
