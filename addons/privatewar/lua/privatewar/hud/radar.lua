-- Radar (T-6.6; 09-hud.md d.2): a circle in the top-left corner, rotated with the view (the player is the arrow in the
-- centre, pointing up). Teammates are always shown; enemies only from the revealed blips of the streaks module
-- (PW.Streaks.Blips(), faded over their life), never from what the client happens to know. States: normal; UAV (live
-- blips: an accent rim and a sweep); jammed (a hostile Counter-UAV: noise, no enemy blips). The rules are pure
-- (modules/hud/sh_radar.lua); this file reads the engine and draws with style tokens and stock primitives only. A
-- frame allocates nothing: the people and dot tables are reused, the arrow and disc polygons change only on a resize.
HUDELEMENT.Order = 28
HUDELEMENT.Phases = { "LIVE" }

local hud = PW.HUD --[[@as PW.HudLib]]
local config = hud.Radar

local fallback = Color(255, 255, 255)
local trail = 8

---@type fun(): (fun(): integer?, Player?)
local players = player.Iterator

---@type PW.RadarPerson[]
local people = {}
---@type PW.RadarDot[]
local dots = {}
---@type PW.RadarBlip[]
local none = {}
---@type PW.RadarFrame
local frame = { x = 0, y = 0, yaw = 0, range = config.range, radius = 0, life = config.life, jammed = false }

---@type { cx: number, cy: number, size: number, poly: { x: number, y: number }[] }
local arrow = { cx = -1, cy = -1, size = -1, poly = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } } }

-- The background disc as a polygon (draw.RoundedBox does not make a clean circle at this size).
local segments = 48
---@type { cx: number, cy: number, r: number, poly: { x: number, y: number }[] }
local disc = { cx = -1, cy = -1, r = -1, poly = {} }
for i = 1, segments do disc.poly[i] = { x = 0, y = 0 } end

---@param token string
---@return Color
local function colour(token)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui == nil then return fallback end
    return (ui.Style --[[@as table<string, Color>]])[token] or fallback
end

---@param token string
---@param alpha number 0..1
local function setColour(token, alpha)
    local c = colour(token)
    surface.SetDrawColor(c.r, c.g, c.b, c.a * alpha)
end

---Fills `people` with the other living, non-dormant players the client knows; returns their count.
---@param me Player
---@return integer
local function collect(me)
    local count = 0
    for _, entry in players() do
        local ply = entry --[[@as Player]]
        if ply ~= me and ply:Alive() and not ply:IsDormant() then
            count = count + 1
            local person = people[count]
            if person == nil then
                person = { x = 0, y = 0, enemy = true }
                people[count] = person
            end
            local pos = ply:GetPos()
            person.x, person.y, person.enemy = pos.x, pos.y, PW.IsEnemy(me, ply)
        end
    end
    for i = #people, count + 1, -1 do people[i] = nil end
    return count
end

---The player's arrow in the centre, pointing up.
---@param cx number
---@param cy number
local function drawArrow(cx, cy)
    local size = hud.S(9)
    if arrow.cx ~= cx or arrow.cy ~= cy or arrow.size ~= size then
        arrow.cx, arrow.cy, arrow.size = cx, cy, size
        local poly = arrow.poly
        poly[1].x, poly[1].y = cx, cy - size
        poly[2].x, poly[2].y = cx + size * 0.7, cy + size * 0.7
        poly[3].x, poly[3].y = cx - size * 0.7, cy + size * 0.7
    end
    draw.NoTexture()
    setColour("text", 1)
    surface.DrawPoly(arrow.poly)
end

---The UAV sweep: a line turning once per refresh with a fading trail behind it.
---@param cx number
---@param cy number
---@param r number
local function drawSweep(cx, cy, r)
    local angle = hud._RadarSweep(CurTime(), config.period)
    for i = 0, trail do
        local a = angle - i * 0.05
        setColour("accent", (1 - i / (trail + 1)) * 0.6)
        surface.DrawLine(cx, cy, cx + math.sin(a) * r, cy - math.cos(a) * r)
    end
end

---Counter-UAV noise: random specks over the circle, new every frame.
---@param cx number
---@param cy number
---@param r number
local function drawNoise(cx, cy, r)
    local speck = math.max(1, math.floor(hud.S(3)))
    for _ = 1, config.noise do
        local a, d = math.random() * 2 * math.pi, math.sqrt(math.random()) * r
        setColour(math.random() < 0.5 and "text_muted" or "text", 0.3 + math.random() * 0.5)
        surface.DrawRect(cx + math.sin(a) * d, cy - math.cos(a) * d, speck, speck)
    end
end

---@param cx number
---@param cy number
---@param r number
---@param count integer
local function drawDots(cx, cy, r, count)
    local size = hud.S(config.dot)
    for i = 1, count do
        local dot = dots[i] --[[@as PW.RadarDot]]
        local s, x, y = size, dot.x, dot.y
        if dot.clamped then
            -- On the edge: smaller and pulled inside the rim.
            s = size * 0.6
            local k = (r - s) / r
            x, y = x * k, y * k
        end
        setColour(dot.kind == "enemy" and "team_enemy" or "team_friendly", dot.alpha)
        surface.DrawRect(cx + x - s / 2, cy + y - s / 2, s, s)
    end
end

---@param cx number
---@param cy number
---@param r number
---@param state PW.RadarState
local function drawBase(cx, cy, r, state)
    if disc.cx ~= cx or disc.cy ~= cy or disc.r ~= r then
        disc.cx, disc.cy, disc.r = cx, cy, r
        for i = 1, segments do
            local a = (i - 1) / segments * 2 * math.pi
            local point = disc.poly[i] --[[@as { x: number, y: number }]]
            point.x, point.y = cx + math.sin(a) * r, cy - math.cos(a) * r
        end
    end
    draw.NoTexture()
    setColour("bg_panel", 1)
    surface.DrawPoly(disc.poly)
    local rim = colour(state == "uav" and "accent" or (state == "jammed" and "warning" or "border_strong"))
    surface.DrawCircle(cx, cy, r, rim.r, rim.g, rim.b, rim.a)
    surface.DrawCircle(cx, cy, r * 0.5, rim.r, rim.g, rim.b, rim.a * 0.35)
end

function HUDELEMENT:Draw()
    local me = LocalPlayer()
    if not IsValid(me) or not me:Alive() then return end
    local streaks = rawget(PW, "Streaks") --[[@as PW.StreaksLib?]]
    local jammed = streaks ~= nil and streaks.Jammed ~= nil and streaks.Jammed() or false
    local blips = (streaks ~= nil and streaks.Blips ~= nil and streaks.Blips() or none) --[[@as PW.RadarBlip[] ]]
    local state = hud._RadarState(jammed, #blips)
    local r = hud.S(config.radius)
    local cx, cy = hud.X(config.left) + r, hud.Y(config.top) + r
    drawBase(cx, cy, r, state)
    local pos = me:GetPos()
    frame.x, frame.y, frame.yaw, frame.radius, frame.jammed = pos.x, pos.y, me:EyeAngles().y, r, jammed
    collect(me)
    local count = hud._RadarDots(frame, people, blips, CurTime(), dots)
    if state == "uav" then drawSweep(cx, cy, r) end
    drawDots(cx, cy, r, count)
    if state == "jammed" then drawNoise(cx, cy, r) end
    drawArrow(cx, cy)
end
