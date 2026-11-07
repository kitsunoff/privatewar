-- Kit style v1 (U-1; notes/16-frontend-d1-proposal.md Q2, Q3, Q6; 10-frontend.md d.2). Pure and shared, so the
-- server-side test runner covers it: the colour tokens of palette "Field green" as cached Color objects, the font
-- families (an indirection: switching to another family is a rename here plus resource.AddFile, nothing else), the
-- font ladder maths and the uniform design-unit scale. Creating the fonts (surface.CreateFont) is client glue in
-- cl_init.lua. Loaded by shared.lua through include.

local lib = PW.UI --[[@as PW.UILib]]

-- Palette Variant A "Field green" (note 16 Q3). Hex RGB and alpha 0..1; an opaque token has no alpha.
---@type table<string, { [1]: string, [2]: number? }>
local palette = {
    bg_scrim = { "050806", 0.55 },
    bg_panel = { "0B0F0C", 0.72 },
    bg_raised = { "141B16", 0.85 },
    bg_hover = { "1C2620" },
    bg_selected = { "163020" },
    border = { "1F2A22" },
    border_strong = { "2E3D32" },
    text = { "E8EDE9" },
    text_muted = { "8A958D" },
    text_disabled = { "545D57" },
    accent = { "5BE37D" },
    on_accent = { "06200F" },
    positive = { "5BE37D" },
    negative = { "FF4D4D" },
    warning = { "FFB547" },
    team_friendly = { "4FC3F7" },
    team_enemy = { "FF4D4D" },
    badge_new = { "FFB547" }
}

---@param hex string six hex digits RRGGBB
---@param alpha? number 0..1
---@return Color
local function colourOf(hex, alpha)
    local red = tonumber(hex:sub(1, 2), 16) or 0
    local green = tonumber(hex:sub(3, 4), 16) or 0
    local blue = tonumber(hex:sub(5, 6), 16) or 0
    return Color(red, green, blue, math.floor((alpha or 1) * 255 + 0.5))
end

lib.DesignWidth = 1920
lib.DesignHeight = 1080

-- Smallest font in design units (14.7 px at 1280x800, the Steam Deck).
lib.MinFontSize = 22

-- Families GMod ships: Roboto has Cyrillic with extended = true. Fira Sans Condensed / Fira Sans were chosen, but
-- their files wait for D4 (licence); then only these two names change, plus resource.AddFile.
---@type PW.UIFontFamilies
lib.FontFamilies = lib.FontFamilies or { heading = "Roboto", body = "Roboto" }

-- Named steps in design units (note 16 Q6: display 64, H1 44, H2 32, body 26, small 22).
---@type PW.UIFontStep[]
lib.FontSteps = {
    { id = "title", family = "heading", size = 64, weight = 700 },
    { id = "h1", family = "heading", size = 44, weight = 700 },
    { id = "h2", family = "heading", size = 32, weight = 700 },
    { id = "body", family = "body", size = 26, weight = 500 },
    { id = "small", family = "body", size = 22, weight = 500 },
    { id = "hint", family = "body", size = 22, weight = 400 }
}

-- Engine limit of surface.CreateFont: size 4..255 px; font names 31 characters.
local minPixels, maxPixels = 4, 255

---Name of the engine font of a ladder step ("PW_UI_h1"; at most 31 characters).
---@param id string
---@return string
function lib.FontName(id)
    return "PW_UI_" .. id
end

---Uniform scale of a resolution: the smaller axis over the 1920x1080 design size. Reuses PW.HUD._Scale when the
---hud module is present (one implementation); a local formula otherwise, so ui_kit does not need hud.
---@param width number
---@param height number
---@return number
function lib.ScaleFor(width, height)
    local hud = rawget(PW, "HUD") --[[@as PW.HudLib?]]
    if hud ~= nil and hud._Scale ~= nil then
        local _, _, scale = hud._Scale(width, height)
        return scale
    end
    return math.min(width / lib.DesignWidth, height / lib.DesignHeight)
end

---Pixel size of a design-unit size at a scale, clamped to what the engine accepts.
---@param design number
---@param scale number
---@return integer
function lib.FontPixels(design, scale)
    return math.Clamp(math.floor(design * scale + 0.5), minPixels, maxPixels)
end

---surface.CreateFont data of one ladder step at a scale.
---@param step PW.UIFontStep
---@param scale number
---@return PW.UIFontData
function lib.FontData(step, scale)
    return {
        name = lib.FontName(step.id), font = lib.FontFamilies[step.family], size = lib.FontPixels(step.size, scale),
        weight = step.weight, extended = true, antialias = true
    }
end

---The whole ladder at a resolution, in the order of FontSteps.
---@param width number
---@param height number
---@return PW.UIFontData[]
function lib.FontLadder(width, height)
    local scale = lib.ScaleFor(width, height)
    ---@type PW.UIFontData[]
    local out = {}
    for index, step in ipairs(lib.FontSteps) do out[index] = lib.FontData(step, scale) end
    return out
end

-- The style table: filled in place, so widgets holding a reference see a reload. Old field names stay as aliases
-- of the tokens (widgets of the v0 kit read them).
local style = (lib.Style or {}) --[[@as PW.UIStyle]]
lib.Style = style
local fields = style --[[@as table<string, any>]]
for name, entry in pairs(palette) do fields[name] = colourOf(entry[1], entry[2]) end
style.bg = style.bg_panel
style.hover = style.bg_hover
style.textMuted = style.text_muted
style.fontTitle = lib.FontName("h2")
style.fontBody = lib.FontName("body")
style.pad = 8
