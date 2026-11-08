-- Primary ammo presentation. A negative clip means no magazine, NOT an empty magazine. No ammo type means name only.
local lib = PW.HUD --[[@as PW.HudLib]]

---@param value number?
---@return boolean
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function lib._WeaponModel(valid, name, clip, ammoType, reserve, out)
    local display = valid and name or ""
    local hasAmmo = valid and finite(ammoType) and ammoType >= 0
    local magazine = hasAmmo and finite(clip) and clip >= 0 and math.floor(clip) or nil
    local spare = hasAmmo and (finite(reserve) and math.max(0, math.floor(reserve)) or 0) or nil
    if out.name == display and out.clip == magazine and out.reserve == spare then return out end
    out.name, out.clip, out.reserve = display, magazine, spare
    out.text = spare ~= nil and ((magazine ~= nil and tostring(magazine) or "-") .. " / " .. spare) or ""
    return out
end

function lib._WeaponReady(state, player, weapon, visible)
    return visible and player ~= nil and weapon ~= nil and state.player == player and state.weapon == weapon
end

function lib._WeaponName(adapterName, engineName, class, localize)
    local name = adapterName
    if type(name) ~= "string" or name == "" or name == class then name = engineName end
    if name == "" then name = class end
    return localize(name)
end
