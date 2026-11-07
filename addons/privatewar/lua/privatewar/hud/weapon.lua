-- T-11.11: only the active weapon's localized name and CLIP / RESERVE, bottom right below grenade equipment.
HUDELEMENT.Order = 26
HUDELEMENT.Phases = { "LIVE" }

local hud = PW.HUD --[[@as PW.HudLib]]
local nameFont, ammoFont = "", ""
if CLIENT and hud.Font ~= nil then
    nameFont, ammoFont = hud.Font("weapon_name", 22, 500), hud.Font("weapon_ammo", 32, 700)
end
local fallbackText = Color(232, 237, 233)
local layout = hud._PlayerLayout(1920, 1080, {})
local lastName, lastWidth, lastHeight, label = "", 0, 0, ""

---@param text string
---@return number
local function measure(text)
    local width = surface.GetTextSize(text)
    return width
end

function HUDELEMENT:ShouldDraw()
    local state = hud.WeaponState
    local ply = LocalPlayer()
    if not hud.PlayerVisible() or state == nil or not IsValid(state.weapon) then return false end
    return hud._WeaponReady(state, ply, ply:GetActiveWeapon(), true)
end

function HUDELEMENT:Draw()
    local state = hud.WeaponState --[[@as PW.HudWeaponModel]]
    local w, h = ScrW(), ScrH()
    hud._PlayerLayout(w, h, layout)
    if state.name ~= lastName or w ~= lastWidth or h ~= lastHeight then
        lastName, lastWidth, lastHeight = state.name, w, h
        surface.SetFont(nameFont)
        label = hud._FitText(state.name, layout.weaponWidth, measure)
    end
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    local tint = ui ~= nil and ui.Style.text or fallbackText
    draw.SimpleText(label, nameFont, layout.weaponRight, layout.weaponNameY, tint, TEXT_ALIGN_RIGHT)
    draw.SimpleText(state.text, ammoFont, layout.weaponRight, layout.weaponAmmoY, tint, TEXT_ALIGN_RIGHT)
end
