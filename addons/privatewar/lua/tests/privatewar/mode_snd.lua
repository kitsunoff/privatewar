-- Authoritative S&D acceptance. Pure state/input samples; no damage, teleport or shortened production timers.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil, "expected S&D implementation") return value end
---@return PW.SNDLib
local function lib() return must(PW.SND) end
---@return PW.SNDMapData
local function layout()
    return { sites = {
        { id = "A", pos = Vector(0, 0, 0), approach = Vector(0, 0, 0), radius = 160, above = 96, below = 16 },
        { id = "B", pos = Vector(500, 0, 0), approach = Vector(500, 0, 0), radius = 160, above = 96, below = 16 }
    }, bomb = Vector(0, 0, 0), spawns = {
        [1] = { { pos = Vector(0, 0, 0), yaw = 0 } }, [2] = { { pos = Vector(500, 0, 0), yaw = 180 } }
    } }
end
---@return PW.SNDActor[]
local function actors()
    return { { id = "attacker", userId = 1, team = 1, alive = true, pos = Vector(0, 0, 0),
        use = true, clear = true, generation = 1 },
    { id = "defender", userId = 2, team = 2, alive = true, pos = Vector(500, 0, 0),
        use = false, clear = true, generation = 1 } }
end
---@return PW.SNDState, PW.SNDActor[]
local function round()
    local list = actors()
    return lib().NewRound(layout(), list, 0, 1, "attacker"), list
end
---@return PW.SNDState, PW.SNDActor[]
local function planted()
    local state, list = round()
    lib().Step(state, 0, list)
    lib().Step(state, 5, list)
    return state, list
end

return {
    groupName = "PW Search and Destroy",
    cases = {
        { name = "SND: one bomb survives competing pickups and carrier death disconnect", func = function()
            local s, a = round()
            expect(lib().Death(s, "attacker", 1, Vector(40, 0, 0), 1)).to.beTrue()
            expect(lib().Disconnect(s, "attacker", 1, Vector(90, 0, 0), 2)).to.beFalse()
            expect(s.pos).to.equal(Vector(40, 0, 0))
            a[1].alive = false
            for i = 3, 4 do
                a[#a + 1] = { id = "extra" .. i, userId = i, team = 1, alive = true, pos = s.pos,
                    use = false, clear = true, generation = 1 }
                s.roster["extra" .. i] = { userId = i, team = 1, alive = true, connected = true, spawned = true }
            end
            lib().Step(s, 3, a)
            expect(s.phase).to.equal("carried")
            expect(s.carrier).to.equal("extra3")
            lib().Step(s, 4, a)
            expect(s.carrier).to.equal("extra3")
        end },
        { name = "SND: held interactions cancel on invalid actor range release and round generation", func = function()
            for _, field in ipairs({ "alive", "use", "clear", "generation", "pos", "userId" }) do
                local s, a = round()
                lib().Step(s, 0, a)
                local actor = must(a[1]) --[[@as table<string, any>]]
                local old = actor[field]
                actor[field] = ({ alive = false, use = false, clear = false, generation = 2,
                    pos = Vector(999, 0, 0), userId = 99 })[field]
                lib().Step(s, 4, a)
                expect(s.interaction).to.beNil()
                actor[field] = old
                if s.phase ~= "resolved" then
                    lib().Step(s, 5, a)
                    expect(s.phase == "planted").to.beFalse()
                end
            end
        end },
        { name = "SND: exact plant defuse fuse and death boundaries resolve once", func = function()
            local s, a = round()
            lib().Step(s, 115, a)
            expect(lib().Step(s, 120, a)).to.equal(2)
            expect(s.phase).to.equal("resolved")
            expect(lib().Step(s, 200, a)).to.equal(2)
            local p, b = planted()
            expect(p.phase).to.equal("planted")
            b[2].pos, b[2].use = Vector(0, 0, 0), true
            lib().Step(p, 42.5, b)
            expect(lib().Step(p, 50, b)).to.equal(1)
            local d, c = planted()
            c[2].pos, c[2].use = Vector(0, 0, 0), true
            lib().Step(d, 6, c)
            expect(lib().Step(d, 13.5, c)).to.equal(2)
            expect(lib().Step(d, 99, c)).to.equal(2)
        end },
        { name = "SND: actor death cancels unfinished plant but completed plant survives carrier death",
            func = function()
            local s, a = round()
            lib().Step(s, 0, a)
            lib().Death(s, "attacker", 1, Vector(0, 0, 0), 5)
            a[1].alive = false
            expect(lib().Step(s, 5, a)).to.equal(2)
            expect(s.site).to.beNil()
            local p, b = planted()
            lib().Death(p, "attacker", 1, Vector(0, 0, 0), 5)
            b[1].alive = false
            local verdict, defer = lib().Step(p, 49, b)
            expect(verdict).to.beNil()
            expect(defer).to.beTrue()
            expect(lib().Step(p, 50, b)).to.equal(1)
        end },
        { name = "SND: reconnect and replacement cannot grant a second life", func = function()
            local s = round()
            expect(lib().Admit(s, "attacker", 1)).to.beTrue()
            expect(lib().Admit(s, "attacker", 1)).to.beFalse()
            lib().Disconnect(s, "attacker", 1, s.pos, 1)
            expect(lib().Admit(s, "attacker", 99)).to.beFalse()
            expect(lib().Admit(s, "new_join", 4)).to.beFalse()
            expect(lib().Admit(s, "replacement_bot", 5)).to.beFalse()
        end },
        { name = "SND: snapshots disclose only approved carrier drop and spectator information", func = function()
            local s = round()
            expect(lib().Snapshot(s, 1, "attacker", 0).carrier).to.equal(1)
            expect(lib().Snapshot(s, 2, "defender", 0).carrier).to.beNil()
            expect(lib().Snapshot(s, 0, "unknown", 0).carrier).to.beNil()
            lib().Death(s, "attacker", 1, Vector(40, 0, 0), 1)
            expect(lib().Snapshot(s, 1, "attacker", 1).pos).to.equal(s.pos)
            expect(lib().Snapshot(s, 2, "defender", 1).pos).to.beNil()
            local p = planted()
            expect(lib().Snapshot(p, 2, "defender", 6).pos).to.equal(p.pos)
            expect(lib().Snapshot(p, 2, "defender", 6).fuse).to.equal(50)
            expect(lib().Snapshot(p, 2, "defender", 6).action).to.beNil()
        end },
        { name = "SND: timeout planted overtime preplant elimination and both absent are deterministic",
            func = function()
            for _, sides in ipairs({ { false, true, 2 }, { true, false, 1 }, { false, false, false } }) do
                local s, a = round()
                a[1].alive, a[2].alive = sides[1], sides[2]
                expect(lib().Step(s, 1, a)).to.equal(sides[3])
            end
            local p, a = planted()
            p.deadline = 6
            local winner, defer = lib().Step(p, 7, a)
            expect(winner).to.beNil()
            expect(defer).to.beTrue()
        end },
        { name = "SND: authored map schema rejects missing sides duplicates invalid dimensions and remote approach",
            func = function()
                expect(lib().Validate(layout())).to.beTrue()
                local broken = layout()
                broken.sites[2].id = "A"
                expect(lib().Validate(broken)).to.beFalse()
                broken = layout()
                broken.sites[1].approach = Vector(999, 0, 0)
                expect(lib().Validate(broken)).to.beFalse()
                broken = layout()
                broken.spawns[2] = {}
                expect(lib().Validate(broken)).to.beFalse()
                for _, value in ipairs({ -1, 0, math.huge, 0 / 0 }) do
                    broken = layout()
                    broken.sites[1].radius = value
                    expect(lib().Validate(broken)).to.beFalse()
                end
            end },
        { name = "SND bots: sole attacker carries plants and guards through shared input rules", func = function()
            local s = round()
            local objectives = lib().Objectives(s, 1)
            local plant = must(objectives[1])
            expect(plant.action).to.equal("plant")
            expect(must(plant.eligible)[1]).to.beTrue()
            expect(plant.revision).to.equal(1)
            local p = planted()
            expect(must(lib().Objectives(p, 1)[1]).action).to.equal("hold")
        end },
        { name = "SND bots: sole defender holds use to defuse and death promptly reassigns", func = function()
            local p = planted()
            local obj = must(lib().Objectives(p, 2)[1])
            expect(obj.action).to.equal("defuse")
            expect(must(obj.eligible)[2]).to.beTrue()
            lib().Death(p, "defender", 2, p.pos, 6)
            expect(must(must(lib().Objectives(p, 2)[1]).eligible)[2]).to.beNil()
        end },
        { name = "SND bots: defenders receive no hidden dropped bomb coordinates", func = function()
            local s = round()
            lib().Death(s, "attacker", 1, Vector(90, 90, 0), 1)
            for _, obj in ipairs(lib().Objectives(s, 2)) do
                expect(obj.pos == s.pos).to.beFalse()
                expect(obj.action == "collect").to.beFalse()
            end
        end }
    }
}
