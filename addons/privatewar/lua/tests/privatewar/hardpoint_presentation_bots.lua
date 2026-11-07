-- Phase 1 TEST-FIRST contract scaffold; no bots, engine input, net handlers or private stores are touched.
-- Runtime RED and the real normal-input smoke remain pending the orchestrator's Deck grant.

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

---@param id string
---@param want integer
---@param pos Vector
---@return PW.BotObjective
local function objective(id, want, pos)
    return { id = id, pos = pos, radius = 20, action = "hold", weight = 1, want = want }
end

---@param generation integer
---@param visit integer
---@param revision integer
---@return PW.HardpointSnapshot
local function snapshot(generation, visit, revision)
    return { generation = generation, visit = visit, revision = revision, active = true,
        zone = { id = "synthetic_a", pos = Vector(0, 0, 0), radius = 20, below = 4, above = 12 },
        zoneEndsAt = 10, matchEndsAt = 100, control = 0, contested = true, scores = { 0, 0 } }
end

return {
    groupName = "PW Hardpoint draft presentation and bot seams",
    cases = {
        {
            name = "Hardpoint: rotation releases sticky holds including tiny teams",
            func = function()
                local commander = must(PW.BotCommander)
                for size = 1, 3 do
                    local old = objective("hp_match1_visit1", size, Vector(0, 0, 0))
                    local nextZone = objective("hp_match1_visit2", size, Vector(80, 0, 0))
                    ---@type PW.CommanderBot[]
                    local bots = {}
                    for id = 1, size do bots[id] = { id = id, pos = Vector(0, 0, 0) } end
                    local orders = commander.Assign(bots, { old }, {}, 0)
                    local withdrawn = objective(old.id, 0, old.pos)
                    local sticky = commander.Assign(bots, { withdrawn, nextZone }, orders, 1)
                    -- Characterization: want=0 DOES NOT release an active hold in today's generic commander.
                    for id = 1, size do expect(must(sticky[id]).id).to.equal(old.id) end
                    -- Withdrawing the old visit id releases it on the next pass, even for a sole bot.
                    local rotated = commander.Assign(bots, { nextZone }, orders, 1)
                    for id = 1, size do
                        expect(must(rotated[id]).id).to.equal(nextZone.id)
                        expect(must(rotated[id]).type).to.equal("hold")
                        expect(must(rotated[id]).since).to.equal(1)
                    end
                end
                -- Immediate between-pass order/goal invalidation still needs a generic owner-provided seam.
            end
        },
        {
            name = "Hardpoint: projected arrival is inside the authoritative zone",
            func = function()
                local zone = snapshot(1, 1, 1).zone
                expect(lib().ArrivalFits(zone, Vector(0, 0, 0), 3)).to.beTrue()
                expect(lib().ArrivalFits(zone, Vector(19, 0, 0), 3)).to.beFalse()
                expect(lib().ArrivalFits(zone, Vector(0, 0, 13), 0)).to.beFalse()
                expect(lib().ArrivalFits(zone, Vector(21, 0, 0), 0)).to.beFalse()
                expect(lib().ArrivalFits(zone, Vector(0, 0, -5), 0)).to.beFalse()
                -- Necessary geometry check only; not proof the shared objective follower enforces it.
            end
        },
        {
            name = "Hardpoint: late snapshot rejects stale visits and transmits no occupants",
            func = function()
                local current = lib().AcceptSnapshot(nil, snapshot(2, 5, 8))
                expect(lib().AcceptSnapshot(current, snapshot(1, 99, 99))).to.equal(current)
                expect(lib().AcceptSnapshot(current, snapshot(2, 4, 99))).to.equal(current)
                expect(lib().AcceptSnapshot(current, snapshot(2, 5, 6))).to.equal(current)
                local updated = snapshot(2, 5, 9)
                expect(lib().AcceptSnapshot(current, updated)).to.equal(updated)
                local nextMatch = snapshot(3, 1, 1)
                expect(lib().AcceptSnapshot(current, nextMatch)).to.equal(nextMatch)
                local tombstone = snapshot(2, 5, 9)
                tombstone.active = false
                current = lib().AcceptSnapshot(current, tombstone)
                expect(lib().AcceptSnapshot(current, snapshot(2, 5, 8))).to.equal(current)
                local view = lib().View(snapshot(2, 5, 8), 7, { zoneId = "", zoneRemaining = 0, matchRemaining = 0 })
                expect(view.zoneId).to.equal("synthetic_a")
                expect(view.zoneRemaining).to.equal(3)
                expect(view.matchRemaining).to.equal(93)
                -- PublicSnapshot must be tested against a real private state, not merely this public fixture.
                -- The production codec's explicit field allowlist/length bound remains a phase 2 assertion.
                local state = lib().NewState({ zones = { snapshot(1, 1, 1).zone } }, {
                    pointTime = 10, tickInterval = 1, tickPoints = 1, scoreLimit = 99, matchTime = 100,
                    maxSampleGap = 1, rotationBoundary = "exclude", deadlineBoundary = "exclude",
                    limitPrecedence = "score", tieWinner = function() return nil end
                }, 0, 1)
                lib().Step(state, { at = 0, actors = {
                    { team = 2, pos = Vector(1, 0, 0), alive = true, observer = false, eligible = true }
                } })
                local public = lib().PublicSnapshot(state, 1)
                local allowed = { generation = true, revision = true, visit = true, active = true, zone = true,
                    zoneEndsAt = true, matchEndsAt = true, control = true, contested = true, scores = true }
                for key in pairs(public) do expect(allowed[key]).to.beTrue() end
                for key in pairs(public.zone) do
                    expect(({ id = true, pos = true, radius = true, below = true, above = true })[key]).to.beTrue()
                end
                for key, value in pairs(public.scores) do
                    expect(key == 1 or key == 2).to.beTrue()
                    expect(type(value)).to.equal("number")
                end
                expect(public.control).to.equal(2)
                expect(public.zone.pos).to.equal(Vector(0, 0, 0))
            end
        }
    }
}

-- Deferred runtime intent (not a passing/skipped placeholder case):
-- Hardpoint: bot holds then rotates through normal inputs
-- After schema/geometry/allocation freeze and an explicit Deck grant, reuse a shared bot. Observe authoritative
-- occupancy at visit A, withdraw its objective on rotation, then observe occupancy at B via normal StartCommand.
-- No SetPos, direct movement/damage, fabricated contacts or private store access in the asserted action path.
