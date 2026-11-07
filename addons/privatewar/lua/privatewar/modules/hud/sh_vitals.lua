-- T-11.11: UI-only fractions, local-player visibility and bottom-corner layout. No gameplay limits are changed.
local lib = PW.HUD --[[@as PW.HudLib]]

---@param value number?
---@return boolean
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function lib._HealthFraction(health, maximum)
    if not finite(health) or not finite(maximum) or maximum <= 0 then return 0 end
    return math.Clamp(health / maximum, 0, 1)
end

function lib._ArmorSegments(armor, out)
    local value = finite(armor) and math.Clamp(armor, 0, 150) or 0
    for i = 1, 3 do out[i] = math.Clamp((value - (i - 1) * 50) / 50, 0, 1) end
    for i = 4, #out do out[i] = nil end
    return out
end

function lib._PlayerVisible(phase, valid, alive, spectating)
    return phase == "LIVE" and valid and alive and not spectating
end

function lib._PlayerLayout(width, height, out)
    local s = math.min(width / 1920, height / 1080)
    local bottom = height - 64 * s
    out.left, out.bottom, out.width = 40 * s, bottom, 300 * s
    out.nameY, out.nameHeight = bottom - 66 * s, 22 * s
    out.armorY, out.armorHeight, out.armorGap = bottom - 34 * s, 8 * s, 6 * s
    out.healthY, out.healthHeight = bottom - 16 * s, 16 * s
    out.weaponRight, out.weaponWidth = width - 40 * s, 360 * s
    out.weaponX = out.weaponRight - out.weaponWidth
    out.weaponNameY, out.weaponAmmoY = bottom - 66 * s, bottom - 32 * s
    return out
end

-- UTF-8-aware fitting runs only when the source, width or font scale changes, never for unchanged labels.
function lib._FitText(text, width, measure)
    text = string.gsub(text, "[%c]", " ")
    if width <= 0 then return "" end
    if measure(text) <= width then return text end
    local suffix = "..."
    if measure(suffix) > width then return "" end
    local count = utf8.len(text) or 0
    local low, high, best = 0, count, ""
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local candidate = utf8.sub(text, 1, middle) .. suffix
        if measure(candidate) <= width then
            best, low = candidate, middle + 1
        else
            high = middle - 1
        end
    end
    return best
end

local nativePanels = {
    CHudHealth = "vitals", CHudBattery = "vitals", CHudAmmo = "weapon", CHudSecondaryAmmo = "weapon"
}

function lib._NativeHidden(name, registry, phase, active)
    local id = nativePanels[name]
    if not active or registry == nil or phase ~= "LIVE" or id == nil then return false end
    local element = registry.Get(id) --[[@as PW.HudElement?]]
    if element == nil or not element:IsValid() or not element._HudPainted then return false end
    if element.ShouldDraw ~= nil and not PW.Call(element, "ShouldDraw") then return false end
    return element:IsValid()
end
