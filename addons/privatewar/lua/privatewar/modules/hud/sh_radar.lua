-- Pure rules of the radar (T-6.6; 09-hud.md d.2: a circle in a corner, teammates always, enemies only while a UAV is
-- active, jammed by Counter-UAV). Shared, plain data in and out, so the server-side test runner covers it; the
-- drawing is hud/radar.lua. Loaded by shared.lua through include.
--
-- Enemies come only from the revealed blips (PW.Streaks.Blips(), DESIGN.md net rule): an enemy the client happens to
-- know (in its PVS) is never drawn. Nothing here allocates per frame: _RadarDots reuses the tables of `out`.

local lib = PW.HUD --[[@as PW.HudLib]]

lib.Radar = {
    -- About 38 m from the centre to the edge: a medium map fits in two radii.
    range = 2000,
    -- Top-left corner; the match status bars sit under it (sh_scorebars.lua), the streak lines bottom right.
    radius = 110,
    left = 40,
    top = 40,
    -- The UAV blip life and refresh interval (streaks/uav.lua): a blip fades out over its life, the sweep turns once
    -- per refresh.
    life = 3.5,
    period = 3,
    dot = 8,
    noise = 48
}

function lib._RadarProject(dx, dy, yaw, range, radius)
    local rad = math.rad(yaw)
    local cos, sin = math.cos(rad), math.sin(rad)
    local forward = dx * cos + dy * sin
    local right = dx * sin - dy * cos
    local x, y = right / range * radius, -forward / range * radius
    local length = math.sqrt(x * x + y * y)
    if length > radius then
        local k = radius / length
        return x * k, y * k, true
    end
    return x, y, false
end

function lib._RadarFade(ends, now, life)
    if ends <= now then return 0 end
    if life <= 0 then return 1 end
    return math.min(1, (ends - now) / life)
end

function lib._RadarState(jammed, blips)
    if jammed then return "jammed" end
    if blips > 0 then return "uav" end
    return "normal"
end

function lib._RadarSweep(now, period)
    return (now % period) / period * 2 * math.pi
end

---Writes one dot into out[index], reusing the table that is there.
---@param out PW.RadarDot[]
---@param index integer
---@param frame PW.RadarFrame
---@param wx number
---@param wy number
---@param kind "friend"|"enemy"
---@param alpha number
local function put(out, index, frame, wx, wy, kind, alpha)
    local dot = out[index]
    if dot == nil then
        dot = { x = 0, y = 0, kind = kind, alpha = 1, clamped = false }
        out[index] = dot
    end
    dot.x, dot.y, dot.clamped = lib._RadarProject(wx - frame.x, wy - frame.y, frame.yaw, frame.range, frame.radius)
    dot.kind, dot.alpha = kind, alpha
end

function lib._RadarDots(frame, people, blips, now, out)
    local count = 0
    for i = 1, #people do
        local person = people[i] --[[@as PW.RadarPerson]]
        if not person.enemy then
            count = count + 1
            put(out, count, frame, person.x, person.y, "friend", 1)
        end
    end
    if not frame.jammed then
        for i = 1, #blips do
            local blip = blips[i] --[[@as PW.RadarBlip]]
            local alpha = lib._RadarFade(blip.ends or 0, now, frame.life)
            if alpha > 0 then
                count = count + 1
                put(out, count, frame, blip.pos.x, blip.pos.y, "enemy", alpha)
            end
        end
    end
    for i = #out, count + 1, -1 do out[i] = nil end
    return count
end
