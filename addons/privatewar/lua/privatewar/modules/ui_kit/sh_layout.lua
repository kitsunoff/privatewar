-- Pure layout (U-2; notes/16 Q6): column rectangles in pixels from design units. No vgui.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

local layout = (rawget(lib, "Layout") or {}) --[[@as PW.UILayoutLib]]
lib.Layout = layout

---@param w number
---@param h number
---@return fun(n: number): number
local function uniformScale(w, h)
    local factor = math.min(w / 1920, h / 1080)
    return function(n) return math.floor(n * factor + 0.5) end
end

function layout.Columns(w, h, spec, S)
    local scale = S or uniformScale(w, h)
    local margin, gap = scale(spec.margin or 0), scale(spec.gap or 0)
    local top, bottom = scale(spec.top or 0), scale(spec.bottom or 0)
    local height = h - top - bottom
    local from, to = margin, w - margin
    ---@type PW.UIColumns
    local out = { centre = { x = 0, y = top, w = 0, h = height } }
    if spec.left ~= nil then
        local width = scale(spec.left)
        out.left = { x = from, y = top, w = width, h = height }
        from = from + width + gap
    end
    if spec.right ~= nil then
        local width = scale(spec.right)
        out.right = { x = to - width, y = top, w = width, h = height }
        to = to - width - gap
    end
    out.centre.x, out.centre.w = from, to - from
    return out
end
