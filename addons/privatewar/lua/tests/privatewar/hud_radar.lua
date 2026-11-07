-- T-6.6 radar (TASKS.md, "Mandatory test cases" T-6.6: teammates always; enemies only during UAV; Counter-UAV hides
-- enemies; 09-hud.md d.2). Pure: world to radar projection with rotation, the edge clamp, the blip fade, the state
-- selection, the sweep angle and the dot list (who is shown). Drawing is a manual check.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.HudLib
local function hud()
    return must(PW.HUD)
end

---@param a number
---@param b number
---@return boolean
local function near(a, b)
    return math.abs(a - b) < 1e-6
end

---A view of the local player at the origin facing yaw, range 1000, radius 100, blip life 4.
---@param yaw number
---@param jammed boolean
---@return PW.RadarFrame
local function view(yaw, jammed)
    return { x = 0, y = 0, yaw = yaw, range = 1000, radius = 100, life = 4, jammed = jammed }
end

---@param dots PW.RadarDot[]
---@param count integer
---@param kind string
---@return integer
local function countKind(dots, count, kind)
    local n = 0
    for i = 1, count do
        if (dots[i] --[[@as PW.RadarDot]]).kind == kind then n = n + 1 end
    end
    return n
end

return {
    groupName = "PW HUD radar",
    cases = {
        {
            name = "The radar element is registered and drawn in LIVE only",
            func = function()
                local registry = must(PW.Registries["hud"])
                local element = must(registry.Get("radar")) --[[@as PW.HudElement]]
                expect(must(element.Phases)[1]).to.equal("LIVE")
                expect(#must(element.Phases)).to.equal(1)
            end
        },
        {
            name = "Projection: facing +x, a point ahead is straight up, scaled by radius / range",
            func = function()
                local x, y, clamped = hud()._RadarProject(500, 0, 0, 1000, 100)
                expect(near(x, 0)).to.beTrue()
                expect(near(y, -50)).to.beTrue()
                expect(clamped).to.beFalse()
            end
        },
        {
            name = "Projection: rotation with the view (right is right, behind is down)",
            func = function()
                local project = hud()._RadarProject
                -- Facing +y (yaw 90): +x lies to the right.
                local x, y = project(500, 0, 90, 1000, 100)
                expect(near(x, 50)).to.beTrue()
                expect(near(y, 0)).to.beTrue()
                -- Facing +x: +y lies to the left.
                x, y = project(0, 500, 0, 1000, 100)
                expect(near(x, -50)).to.beTrue()
                expect(near(y, 0)).to.beTrue()
                -- Facing +x: -x lies behind (down on the screen).
                x, y = project(-250, 0, 0, 1000, 100)
                expect(near(x, 0)).to.beTrue()
                expect(near(y, 25)).to.beTrue()
                -- Facing -x (yaw 180): +x lies behind.
                x, y = project(250, 0, 180, 1000, 100)
                expect(near(x, 0)).to.beTrue()
                expect(near(y, 25)).to.beTrue()
            end
        },
        {
            name = "Projection: a point beyond the range is clamped to the edge, keeping its direction",
            func = function()
                local project = hud()._RadarProject
                local x, y, clamped = project(3000, 0, 0, 1000, 100)
                expect(near(x, 0)).to.beTrue()
                expect(near(y, -100)).to.beTrue()
                expect(clamped).to.beTrue()
                x, y, clamped = project(2000, 2000, 0, 1000, 100)
                expect(near(math.sqrt(x * x + y * y), 100)).to.beTrue()
                -- Ahead and to the left (facing +x, +y is left): up-left on the diagonal.
                expect(near(x, y)).to.beTrue()
                expect(x < 0).to.beTrue()
                expect(clamped).to.beTrue()
                -- Exactly on the edge is not clamped.
                x, y, clamped = project(1000, 0, 0, 1000, 100)
                expect(near(y, -100)).to.beTrue()
                expect(clamped).to.beFalse()
            end
        },
        {
            name = "Blip fade: full when fresh, linear over the life, zero at and after the end",
            func = function()
                local fade = hud()._RadarFade
                expect(fade(14, 10, 4)).to.equal(1)
                expect(near(fade(12, 10, 4), 0.5)).to.beTrue()
                expect(fade(10, 10, 4)).to.equal(0)
                expect(fade(9, 10, 4)).to.equal(0)
                -- Longer than the life (clock skew) never exceeds 1; no life means no fade.
                expect(fade(20, 10, 4)).to.equal(1)
                expect(fade(11, 10, 0)).to.equal(1)
            end
        },
        {
            name = "State: jammed wins, live blips mean uav, otherwise normal",
            func = function()
                local state = hud()._RadarState
                expect(state(false, 0)).to.equal("normal")
                expect(state(false, 3)).to.equal("uav")
                expect(state(true, 0)).to.equal("jammed")
                expect(state(true, 3)).to.equal("jammed")
            end
        },
        {
            name = "Sweep: one full turn per period, starting at the top",
            func = function()
                local sweep = hud()._RadarSweep
                expect(near(sweep(0, 3), 0)).to.beTrue()
                expect(near(sweep(0.75, 3), math.pi / 2)).to.beTrue()
                expect(near(sweep(3.75, 3), math.pi / 2)).to.beTrue()
            end
        },
        {
            name = "Dots: teammates are always shown, enemies that are not revealed never",
            func = function()
                ---@type PW.RadarPerson[]
                local people = {
                    { x = 100, y = 0, enemy = false },
                    { x = 0, y = 200, enemy = false },
                    { x = 300, y = 0, enemy = true },
                    { x = 0, y = -300, enemy = true }
                }
                ---@type PW.RadarDot[]
                local out = {}
                local count = hud()._RadarDots(view(0, false), people, {}, 10, out)
                expect(count).to.equal(2)
                expect(countKind(out, count, "friend")).to.equal(2)
                expect(countKind(out, count, "enemy")).to.equal(0)
                expect((out[1] --[[@as PW.RadarDot]]).alpha).to.equal(1)
            end
        },
        {
            name = "Dots: revealed enemies are shown only during a UAV, faded by the time left",
            func = function()
                ---@type PW.RadarPerson[]
                local people = { { x = 100, y = 0, enemy = false }, { x = 300, y = 0, enemy = true } }
                ---@type PW.RadarBlip[]
                local blips = { { pos = { x = 500, y = 0 }, ends = 12 }, { pos = { x = 0, y = 0 }, ends = 9 } }
                ---@type PW.RadarDot[]
                local out = {}
                local count = hud()._RadarDots(view(0, false), people, blips, 10, out)
                expect(count).to.equal(2)
                expect(countKind(out, count, "enemy")).to.equal(1)
                local enemy = out[2] --[[@as PW.RadarDot]]
                expect(enemy.kind).to.equal("enemy")
                expect(near(enemy.alpha, 0.5)).to.beTrue()
                expect(near(enemy.y, -50)).to.beTrue()
            end
        },
        {
            name = "Dots: a Counter-UAV jam hides every enemy blip, teammates stay",
            func = function()
                ---@type PW.RadarPerson[]
                local people = { { x = 100, y = 0, enemy = false } }
                ---@type PW.RadarBlip[]
                local blips = { { pos = { x = 500, y = 0 }, ends = 12 } }
                ---@type PW.RadarDot[]
                local out = {}
                local count = hud()._RadarDots(view(0, true), people, blips, 10, out)
                expect(count).to.equal(1)
                expect(countKind(out, count, "enemy")).to.equal(0)
                expect(countKind(out, count, "friend")).to.equal(1)
            end
        },
        {
            name = "Dots: positions are relative to the player and rotated; stale entries of out are cleared",
            func = function()
                ---@type PW.RadarPerson[]
                local people = { { x = 1000, y = 700, enemy = false } }
                ---@type PW.RadarFrame
                local frame = { x = 1000, y = 200, yaw = 90, range = 1000, radius = 100, life = 4, jammed = false }
                ---@type PW.RadarDot[]
                local out = {
                    { x = 0, y = 0, kind = "friend", alpha = 1, clamped = false },
                    { x = 0, y = 0, kind = "friend", alpha = 1, clamped = false }
                }
                local first = out[1]
                local count = hud()._RadarDots(frame, people, {}, 10, out)
                expect(count).to.equal(1)
                expect(out[1]).to.equal(first)
                expect(near((out[1] --[[@as PW.RadarDot]]).x, 0)).to.beTrue()
                expect(near((out[1] --[[@as PW.RadarDot]]).y, -50)).to.beTrue()
                expect(out[2]).to.beNil()
            end
        }
    }
}
