-- Bots goal, the pure path follower rules (T-5.6; included by shared.lua): waypoint advance, look-ahead, the move
-- toward a point relative to the view, arrival, retry backoff, waypoints from the area steps of a path, ladder view.

local lib = PW.BotGoal --[[@as PW.BotGoalLib]]

local stepHeight = 64

function lib.Advance(points, index, pos, reach)
    while index <= #points do
        local point = points[index]
        local within = (point - pos):Length2D() <= reach and math.abs(point.z - pos.z) <= stepHeight
        local nextPoint = points[index + 1]
        local past = nextPoint ~= nil and pos:Distance(nextPoint) < point:Distance(nextPoint)
        if not within and not past then break end
        index = index + 1
    end
    return index
end

function lib.LookAhead(points, index, pos, distance)
    local remaining, from = distance, pos
    for i = index, #points do
        local segment = points[i] - from
        local length = segment:Length()
        if length >= remaining and length > 0 then return from + segment * (remaining / length) end
        remaining = remaining - length
        from = points[i]
    end
    return points[#points] or pos
end

function lib.Remaining(points, index, pos)
    local total, from = 0, pos
    for i = index, #points do
        total = total + from:Distance(points[i])
        from = points[i]
    end
    return total
end

function lib.MoveFor(pos, target, yaw, speed)
    local dir = target - pos
    if dir.x == 0 and dir.y == 0 then return 0, 0 end
    local relative = math.rad(math.deg(math.atan2(dir.y, dir.x)) - yaw)
    return math.cos(relative) * speed, -math.sin(relative) * speed
end

local minHeight = 72

function lib.Arrived(pos, point, radius)
    return (point - pos):Length2D() <= radius and math.abs(point.z - pos.z) <= math.max(radius, minHeight)
end

local delays = { 0, 0.5, 1, 2, 4 }

function lib.RetryDelay(attempt)
    return delays[math.Clamp(attempt, 1, #delays)]
end

local entryPull = 16

function lib.Waypoints(steps, final)
    ---@type Vector[]
    local points = {}
    for _, step in ipairs(steps) do
        local toCenter = step.center - step.entry
        local length = toCenter:Length()
        if length > 0 then
            points[#points + 1] = step.entry + toCenter * (math.min(entryPull, length) / length)
        else
            points[#points + 1] = step.entry
        end
    end
    points[#points + 1] = final
    return points
end

local ladderPitch = 70

---@param value number
---@param limit number
---@return number
local function clampStep(value, limit)
    return math.max(-limit, math.min(limit, value))
end

function lib.TurnToward(from, to, maxSpeed, dt)
    local step = math.max(maxSpeed, 0) * math.max(dt, 0)
    local pitch = from.p + clampStep(math.AngleDifference(to.p, from.p), step)
    local yaw = from.y + clampStep(math.AngleDifference(to.y, from.y), step)
    return Angle(math.NormalizeAngle(pitch), math.NormalizeAngle(yaw), 0)
end

function lib.LadderView(pos, target)
    local dir = target - pos
    local yaw = math.deg(math.atan2(dir.y, dir.x))
    return Angle(dir.z >= 0 and -ladderPitch or ladderPitch, yaw, 0)
end
