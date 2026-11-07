-- Operator scene maths (U-9, T-7.3; notes/16-frontend-d1-proposal.md Q4; 10-frontend.md d.6). Pure and shared, so
-- the server-side test runner covers it: camera framing from the model bounds and the FOV, the model fallback, the
-- idle sequence choice and the light rig. The PWOperator panel (DModelPanel) is client glue: cl_operator.lua.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

local operator = (rawget(lib, "Operator") or {}) --[[@as PW.UIOperatorLib]]
operator.FallbackModel = "models/player/kleiner.mdl"
operator.CameraPitch = 6
operator.IdleSequences = { "idle_all_01", "idle_all_02", "idle_all", "idle" }
operator.Margin = 1.25
lib.Operator = operator

---@type table<string, boolean>
local rejected = { ["models/error.mdl"] = true }

---Distance from the model centre at which the bounding sphere fits the view (radius / tan(fov / 2) *
---1.25). Source FOV is horizontal; for a panel wider than tall the vertical FOV is the limit (half-tan / aspect).
---@param mins Vector
---@param maxs Vector
---@param fov number horizontal FOV in degrees
---@param aspect? number panel width / height
---@return number
function operator.FramingDistance(mins, maxs, fov, aspect)
    local radius = math.max((maxs - mins):Length() / 2, 1)
    local half = math.tan(math.rad(math.Clamp(fov, 1, 170)) / 2)
    if aspect ~= nil and aspect > 1 then half = half / aspect end
    return radius / half * operator.Margin
end

---@param mins Vector
---@param maxs Vector
---@param fov number
---@param aspect? number
---@return PW.UIOperatorFrame
function operator.Frame(mins, maxs, fov, aspect)
    local dist = operator.FramingDistance(mins, maxs, fov, aspect)
    local lookAt = (mins + maxs) / 2
    local pitch = math.rad(operator.CameraPitch)
    local camPos = lookAt + Vector(math.cos(pitch), 0, math.sin(pitch)) * dist
    return { dist = dist, lookAt = lookAt, camPos = camPos }
end

---The model to show: the wanted one when it is a valid .mdl and not the engine error model, else the stock model.
---@param path string?
---@param isValid fun(path: string): boolean
---@return string chosen
---@return boolean usedFallback
function operator.ChooseModel(path, isValid)
    if type(path) == "string" then
        local replaced = string.gsub(path, "\\", "/")
        local normal = string.lower(replaced)
        if string.sub(normal, 1, 7) == "models/" and string.sub(normal, -4) == ".mdl" and not rejected[normal]
            and isValid(path) then
            return path, false
        end
    end
    return operator.FallbackModel, true
end

---First idle sequence the model knows (LookupSequence returns -1 for an unknown name).
---@param lookup fun(name: string): integer
---@return integer?
function operator.ChooseSequence(lookup)
    for _, name in ipairs(operator.IdleSequences) do
        local id = lookup(name)
        if id >= 0 then return id end
    end
    return nil
end

---@param colour Color
---@param factor number
---@return Color
local function scaled(colour, factor)
    return Color(
        math.Clamp(math.floor(colour.r * factor + 0.5), 0, 255),
        math.Clamp(math.floor(colour.g * factor + 0.5), 0, 255),
        math.Clamp(math.floor(colour.b * factor + 0.5), 0, 255),
        255
    )
end

---Our own lights: a warm-white key from the front, a soft white fill from the side and an accent rim from behind. `dir`
---is the DModelPanel box direction (BOX_FRONT 0, BOX_BACK 1, BOX_RIGHT 2, BOX_LEFT 3, BOX_TOP 4, BOX_BOTTOM 5).
---@param style PW.UIStyle
---@return PW.UIOperatorRig
function operator.Lights(style)
    return {
        ambient = scaled(style.text, 0.55),
        lights = {
            { name = "key", dir = 0, colour = scaled(style.text, 1.0) },
            { name = "fill", dir = 3, colour = scaled(style.text, 0.7) },
            { name = "rim", dir = 1, colour = scaled(style.accent, 1.0) },
            { name = "top", dir = 4, colour = scaled(style.text, 0.6) }
        }
    }
end
