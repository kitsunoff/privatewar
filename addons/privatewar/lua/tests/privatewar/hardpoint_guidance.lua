-- Test-first screen guidance. These cases do not claim client visual or native multi-bot acceptance.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "Hardpoint screen guidance API is absent")
    return value
end

---@return PW.HardpointLib
local function hp() return must(PW.Hardpoint) end

---@return PW.HardpointSnapshot
local function snapshot()
    return { generation = 1, revision = 1, visit = 1, active = true,
        zone = { id = "Courtyard", pos = Vector(500, 0, 0), radius = 160, above = 100, below = 20 },
        zoneEndsAt = 60, matchEndsAt = 600, control = 0, contested = false, scores = { 0, 0 } }
end

---@return PW.HardpointWaypoint
local function point()
    return { x = 0, y = 0, angle = 0, edge = false, visible = false }
end

---@return PW.HardpointGuidance
local function guidance()
    return { visible = false, zoneId = "", action = "", token = "text", distance = 0 }
end

return {
    groupName = "PW Hardpoint screen guidance",
    cases = {
        {
            name = "Hardpoint guidance: shared HUD registration never requires client localization on the server",
            func = function()
                local element = must(PW.Hud).Get("hardpoint_guidance")
                expect(element).to.exist()
                expect(isfunction(must(element).Draw)).to.beTrue()
            end
        },
        {
            name = "Hardpoint guidance: active zone projects on screen without a world-visibility trace",
            func = function()
                stub(util, "TraceLine").with(function() error("screen guidance must not trace occlusion") end)
                local out = point()
                expect(hp().ProjectWaypoint(0, 0, 500, 90, 1280, 720, out)).to.equal(out)
                expect(out.visible).to.beTrue()
                expect(out.edge).to.beFalse()
                expect(out.x).to.equal(640)
                expect(out.y).to.equal(360)
                hp().ProjectWaypoint(100, 50, 500, 90, 1280, 720, out)
                expect(out.x > 640 and out.y < 360).to.beTrue()
            end
        },
        {
            name = "Hardpoint guidance: offscreen and behind bearings clamp inside HUD safe bounds",
            func = function()
                local out = point()
                for _, size in ipairs({ { 1280, 720 }, { 1280, 800 }, { 1920, 1080 }, { 2560, 1080 } }) do
                    local w, h = size[1], size[2]
                    for _, bearing in ipairs({ { 1000, 0, 1 }, { -1000, 0, 1 }, { 0, 1000, 1 },
                        { 0, -1000, 1 }, { 500, 0, -500 }, { -500, 0, -500 }, { 0, 0, -500 } }) do
                        hp().ProjectWaypoint(bearing[1], bearing[2], bearing[3], 90, w, h, out)
                        expect(out.visible).to.beTrue()
                        expect(out.edge).to.beTrue()
                        expect(out.x >= w * 0.26 and out.x <= w * 0.82).to.beTrue()
                        expect(out.y >= h * 0.26 and out.y <= h * 0.72).to.beTrue()
                        expect(out.angle == out.angle and math.abs(out.angle) <= 180).to.beTrue()
                    end
                end
            end
        },
        {
            name = "Hardpoint guidance: behind-right never mirrors left and exact-behind has a finite turn cue",
            func = function()
                local out = point()
                hp().ProjectWaypoint(500, 0, -500, 90, 1280, 720, out)
                expect(out.x > 640).to.beTrue()
                hp().ProjectWaypoint(-500, 0, -500, 90, 1280, 720, out)
                expect(out.x < 640).to.beTrue()
                hp().ProjectWaypoint(0, 0, -500, 90, 1280, 720, out)
                expect(out.y > 360).to.beTrue()
                expect(out.angle == out.angle).to.beTrue()
                hp().ProjectWaypoint(1, 0, 0, 90, 1280, 720, out)
                expect(out.visible and out.edge and out.x > 640).to.beTrue()
            end
        },
        {
            name = "Hardpoint guidance: invalid projection clears reused output rather than leaking stale coordinates",
            func = function()
                local out = point()
                hp().ProjectWaypoint(0, 0, 500, 90, 1280, 720, out)
                for _, invalid in ipairs({ math.huge, -math.huge, 0 / 0 }) do
                    hp().ProjectWaypoint(invalid, 0, 500, 90, 1280, 720, out)
                    expect(out.visible).to.beFalse()
                    expect(out.x == out.x and out.y == out.y and out.angle == out.angle).to.beTrue()
                end
            end
        },
        {
            name = "Hardpoint guidance: capture defend and contested reuse public control and relative palette",
            func = function()
                local state, out = snapshot(), guidance()
                expect(hp().Guidance(state, "LIVE", "hardpoint", true, 1, 1000, out)).to.equal(out)
                expect(out.visible).to.beTrue()
                expect(out.zoneId).to.equal("Courtyard")
                expect(out.action).to.equal("capture")
                expect(out.token).to.equal("text")
                expect(out.distance).to.equal(25)
                state.control = 1
                hp().Guidance(state, "LIVE", "hardpoint", true, 1, 1000, out)
                expect(out.action).to.equal("defend")
                expect(out.token).to.equal("team_friendly")
                hp().Guidance(state, "LIVE", "hardpoint", true, 2, 1000, out)
                expect(out.action).to.equal("capture")
                expect(out.token).to.equal("team_enemy")
                state.contested = true
                hp().Guidance(state, "LIVE", "hardpoint", true, 2, 1000, out)
                expect(out.action).to.equal("contested")
                expect(out.token).to.equal("warning")
            end
        },
        {
            name = "Hardpoint guidance: other mode phase dead spectator and cleanup hide the old objective",
            func = function()
                local state, out = snapshot(), guidance()
                hp().Guidance(state, "LIVE", "hardpoint", true, 1, 500, out)
                for _, phase in ipairs({ "LOBBY", "PREMATCH", "POSTMATCH" }) do
                    hp().Guidance(state, phase, "hardpoint", true, 1, 500, out)
                    expect(out.visible).to.beFalse()
                    expect(out.zoneId).to.equal("")
                end
                hp().Guidance(state, "LIVE", "dom", true, 1, 500, out)
                expect(out.visible).to.beFalse()
                hp().Guidance(state, "LIVE", "hardpoint", false, 1, 500, out)
                expect(out.visible).to.beFalse()
                hp().Guidance(state, "LIVE", "hardpoint", true, 0, 500, out)
                expect(out.visible).to.beFalse()
                state.active = false
                hp().Guidance(state, "LIVE", "hardpoint", true, 1, 500, out)
                expect(out.visible).to.beFalse()
                hp().Guidance(nil, "LIVE", "hardpoint", true, 1, 500, out)
                expect(out.visible).to.beFalse()
            end
        },
        {
            name = "Hardpoint guidance: rotation shows only the accepted current zone and drops a stale visit",
            func = function()
                local first, nextZone, out = snapshot(), snapshot(), guidance()
                nextZone.visit, nextZone.revision, nextZone.zone.id = 2, 2, "Garage"
                local accepted = hp().AcceptSnapshot(first, nextZone)
                accepted = hp().AcceptSnapshot(accepted, first)
                hp().Guidance(accepted, "LIVE", "hardpoint", true, 1, 500, out)
                expect(out.zoneId).to.equal("Garage")
                local allowed = { visible = true, zoneId = true, action = true, token = true, distance = true }
                for key in pairs(out) do expect(allowed[key]).to.beTrue() end
            end
        }
    }
}
