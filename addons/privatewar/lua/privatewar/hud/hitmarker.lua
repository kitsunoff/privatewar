-- Hitmarker (T-6.3; 09-hud.md d.2): an X around the crosshair that fades in a quarter of a second. A hit is white, a
-- headshot gold, a kill red and larger. The kind comes from the hitmarker module (one message per tick of hits);
-- the fade is a pure function of time. A frame allocates nothing: the shapes are constant tables.
HUDELEMENT.Order = 20
HUDELEMENT.Phases = { "LIVE" }

local hud = PW.HUD --[[@as PW.HudLib]]
local marker = PW.Hitmarker --[[@as PW.HitmarkerLib]]

local fallback = Color(255, 255, 255)

-- Design units: gap from the centre, length of each stroke, stroke width.
---@type table<PW.HitKind, { gap: number, length: number, width: number, token: string }>
local shapes = {
    hit = { gap = 8, length = 10, width = 2, token = "text" },
    headshot = { gap = 9, length = 13, width = 2, token = "warning" },
    kill = { gap = 10, length = 18, width = 3, token = "negative" }
}

---@param token string
---@return Color
local function colour(token)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui == nil then return fallback end
    return (ui.Style --[[@as table<string, Color>]])[token] or fallback
end

---One diagonal stroke from the centre outwards; thickness by parallel lines.
---@param cx number
---@param cy number
---@param dx integer -1 or 1
---@param dy integer -1 or 1
---@param gap number pixels
---@param length number pixels
---@param width integer pixels
local function stroke(cx, cy, dx, dy, gap, length, width)
    local x1, y1 = cx + dx * gap, cy + dy * gap
    local x2, y2 = cx + dx * (gap + length), cy + dy * (gap + length)
    for i = 0, width - 1 do
        surface.DrawLine(x1 + i, y1, x2 + i, y2)
    end
end

function HUDELEMENT:Draw()
    local current = marker.Current
    local kind = current.kind
    if kind == nil then return end
    local alpha = marker._Alpha(CurTime() - current.at, marker.Duration)
    if alpha <= 0 then
        current.kind = nil
        return
    end
    local shape = shapes[kind]
    local tint = colour(shape.token)
    surface.SetDrawColor(tint.r, tint.g, tint.b, 255 * alpha)
    local cx, cy = ScrW() / 2, ScrH() / 2
    local gap, length = hud.S(shape.gap), hud.S(shape.length)
    local width = math.max(1, math.floor(hud.S(shape.width) + 0.5))
    stroke(cx, cy, -1, -1, gap, length, width)
    stroke(cx, cy, 1, -1, gap, length, width)
    stroke(cx, cy, -1, 1, gap, length, width)
    stroke(cx, cy, 1, 1, gap, length, width)
end
