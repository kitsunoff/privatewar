-- U-9 Operator scene (TASKS.md, "Mandatory test cases" U-9; notes/16-frontend-d1-proposal.md Q4). Pure parts of
-- PWOperator: framing distance from bounds and FOV, model fallback (models/error.mdl rejected), idle sequence
-- choice and the light rig. The panel itself (DModelPanel) is a checkpoint item.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UIOperatorLib
local function op()
    return must(must(PW.UI).Operator)
end

---@param path string
---@return boolean
local function everythingValid(path)
    return path ~= nil
end

---@return boolean
local function nothingValid()
    return false
end

---@param value number
---@param expected number
---@return boolean
local function near(value, expected)
    return math.abs(value - expected) < 0.001
end

return {
    groupName = "PW UI operator",
    cases = {
        {
            name = "Framing distance is radius / tan(fov / 2) with a 1.25 margin",
            func = function()
                -- Box 60x60x60 around the origin: radius is half the diagonal, sqrt(3) * 30.
                local radius = math.sqrt(3) * 30
                local mins, maxs = Vector(-30, -30, -30), Vector(30, 30, 30)
                expect(near(op().FramingDistance(mins, maxs, 90), radius / math.tan(math.rad(45)) * 1.25)).to.beTrue()
                expect(near(op().FramingDistance(mins, maxs, 45), radius / math.tan(math.rad(22.5)) * 1.25)).to.beTrue()
            end
        },
        {
            name = "A narrower FOV or a bigger model moves the camera back",
            func = function()
                local small, big = Vector(-10, -10, -10), Vector(10, 10, 10)
                local wide = op().FramingDistance(small, big, 70)
                expect(op().FramingDistance(small, big, 35) > wide).to.beTrue()
                expect(op().FramingDistance(Vector(-20, -20, -20), Vector(20, 20, 20), 70) > wide).to.beTrue()
            end
        },
        {
            name = "A panel wider than tall uses the vertical-limited FOV",
            func = function()
                local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
                local square = op().FramingDistance(mins, maxs, 40, 1)
                expect(near(op().FramingDistance(mins, maxs, 40, 2), square * 2)).to.beTrue()
                expect(near(op().FramingDistance(mins, maxs, 40, 0.5), square)).to.beTrue()
            end
        },
        {
            name = "Degenerate bounds and FOV never give a zero or invalid distance",
            func = function()
                expect(op().FramingDistance(Vector(0, 0, 0), Vector(0, 0, 0), 70) > 0).to.beTrue()
                local badFov = op().FramingDistance(Vector(-1, -1, -1), Vector(1, 1, 1), 0)
                expect(badFov > 0 and badFov < math.huge).to.beTrue()
            end
        },
        {
            name = "Frame looks at the centre of the bounds from the front",
            func = function()
                local frame = op().Frame(Vector(-16, -16, 0), Vector(16, 16, 72), 40, 1)
                expect(near(frame.lookAt.z, 36)).to.beTrue()
                expect(near(frame.camPos.z, 36 + frame.dist * math.sin(math.rad(op().CameraPitch)))).to.beTrue()
                expect(frame.camPos.x > 0).to.beTrue()
            end
        },
        {
            name = "Model fallback: models/error.mdl is rejected in any spelling",
            func = function()
                local fallback = op().FallbackModel
                for _, path in ipairs({ "models/error.mdl", "MODELS/Error.mdl", "models\\error.mdl" }) do
                    local chosen, usedFallback = op().ChooseModel(path, everythingValid)
                    expect(chosen).to.equal(fallback)
                    expect(usedFallback).to.beTrue()
                end
            end
        },
        {
            name = "Model fallback: an invalid, empty or malformed path falls back",
            func = function()
                local fallback = op().FallbackModel
                expect(op().ChooseModel("models/player/nope.mdl", nothingValid)).to.equal(fallback)
                expect(op().ChooseModel("", everythingValid)).to.equal(fallback)
                expect(op().ChooseModel(nil, everythingValid)).to.equal(fallback)
                expect(op().ChooseModel("sound/x.wav", everythingValid)).to.equal(fallback)
                expect(op().ChooseModel("models/player/x.txt", everythingValid)).to.equal(fallback)
            end
        },
        {
            name = "Model fallback: a valid model is kept; the fallback itself is a valid stock model",
            func = function()
                local chosen, usedFallback = op().ChooseModel("models/player/alyx.mdl", everythingValid)
                expect(chosen).to.equal("models/player/alyx.mdl")
                expect(usedFallback).to.beFalse()
                expect(util.IsValidModel(op().FallbackModel)).to.beTrue()
            end
        },
        {
            name = "Idle sequence: the first known candidate wins, none gives nil",
            func = function()
                local known = { idle_all_02 = 7, idle = 3 }
                expect(op().ChooseSequence(function(name) return known[name] or -1 end)).to.equal(7)
                expect(op().ChooseSequence(function() return -1 end)).to.beNil()
                expect(op().ChooseSequence(function() return 0 end)).to.equal(0)
            end
        },
        {
            name = "Light rig: key, fill and rim exist with colours from the tokens",
            func = function()
                local rig = op().Lights(must(must(PW.UI).Style))
                expect(IsColor(rig.ambient)).to.beTrue()
                ---@type table<string, boolean>
                local names = {}
                for _, light in ipairs(rig.lights) do
                    names[light.name] = true
                    expect(IsColor(light.colour)).to.beTrue()
                    expect(light.dir >= 0 and light.dir <= 5).to.beTrue()
                end
                expect(names.key).to.beTrue()
                expect(names.fill).to.beTrue()
                expect(names.rim).to.beTrue()
            end
        }
    }
}
