-- HUD module, client (T-6.1; 09-hud.md d.1, d.3). The single HUDPaint over the hud registry (the paint loop is
-- shared.lua: _Paint), design-unit scaling for 1920x1080, cached fonts and the HUDShouldDraw list. Visual style is
-- the ui lane's: elements read PW.UI.Style when ui_kit is on.

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.HudModuleClient : PW.Module
local module = MODULE --[[@as PW.HudModuleClient]]

local lib = PW.HUD --[[@as PW.HudLib]]

-- Additional legacy hide list stays empty. T-11.11 replaces only health/battery and primary/secondary ammo,
-- conditionally on a healthy, visible replacement; crosshair, killfeed and Tab stay native.
lib.Hidden = lib.Hidden or {}

local hudVar = CreateClientConVar("pw_hud", "1", true, false, "Draw the Private War HUD overlay (0 hides it)", 0, 1)

local scaleX, scaleY, scaleS = 1, 1, 1
local lastW, lastH = 0, 0

---@class PW.HudFontSpec
---@field size number design units
---@field weight number

---@type table<string, PW.HudFontSpec>
local fontSpecs = {}

---@param id string
---@param spec PW.HudFontSpec
local function createFont(id, spec)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    surface.CreateFont("PW_HUD_" .. id, {
        font = ui ~= nil and ui.FontFamilies.body or "Roboto",
        size = math.max(1, math.floor(spec.size * scaleS + 0.5)), weight = spec.weight,
        antialias = true, extended = true
    })
end

function lib.Refresh()
    local width, height = ScrW(), ScrH()
    if width == lastW and height == lastH then return false end
    lastW, lastH = width, height
    scaleX, scaleY, scaleS = lib._Scale(width, height)
    for id, spec in pairs(fontSpecs) do createFont(id, spec) end
    return true
end

function lib.X(value) return value * scaleX end

function lib.Y(value) return value * scaleY end

function lib.S(value) return value * scaleS end

function lib.Font(id, size, weight)
    if fontSpecs[id] == nil then
        lib.Refresh()
        local spec = { size = size, weight = weight or 500 }
        fontSpecs[id] = spec
        createFont(id, spec)
    end
    return "PW_HUD_" .. id
end

---@type PW.HudState
local state = lib._NewState()

-- One flags table for every frame: no allocation in HUDPaint.
---@type PW.HudFlags
local flags = {}

PW.HookFor(module, "HUDPaint", function()
    local registry = PW.Hud
    if registry == nil then return end
    lib.Refresh()
    flags.hidden = not hudVar:GetBool()
    lib._Paint(state, registry, PW.Phase.GetPhase(), flags)
end)

PW.HookFor(module, "HUDShouldDraw", function(_, name)
    if not hudVar:GetBool() then return end
    if lib._NativeHidden(name, PW.Hud, PW.Phase.GetPhase(), true) or lib.Hidden[name] then return false end
end)

function lib.PlayerVisible()
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end
    local jip = rawget(PW, "Jip") --[[@as PW.JipLib?]]
    local observing = ply:GetObserverMode() ~= OBS_MODE_NONE or ply:Team() == TEAM_SPECTATOR
        or (jip ~= nil and ply:GetNW2Bool(jip.NetBool, false))
    return lib._PlayerVisible(PW.Phase.GetPhase(), true, ply:Alive(), observing)
end

-- Adapter calls can allocate internally. Collect outside HUDPaint; the element verifies player/weapon identity
-- again before drawing, so a switch, death or spectator transition can never show the previous owner's values.
---@type PW.HudWeaponModel
local weaponState = { name = "", text = "" }
lib.WeaponState = weaponState

PW.HookFor(module, "Think", function()
    local ply = LocalPlayer()
    local wep = IsValid(ply) and ply:GetActiveWeapon() or nil
    if not lib.PlayerVisible() or not IsValid(wep) then
        lib._WeaponModel(false, "", nil, nil, nil, weaponState)
        weaponState.player, weaponState.weapon = nil, nil
        return
    end
    local active = wep --[[@as Weapon]]
    local adapters = rawget(PW, "Adapters") --[[@as PW.AdaptersLib?]]
    local clip, ammo = active:Clip1(), active:GetPrimaryAmmoType()
    ---@type string?
    local adapterName
    if adapters ~= nil then
        clip = adapters.CallFor(active, "GetClip", active)
        ammo = adapters.CallFor(active, "GetAmmoType", active)
        adapterName = adapters.CallFor(active, "GetDisplayName", active)
    end
    local name = lib._WeaponName(adapterName, active:GetPrintName(), active:GetClass(), language.GetPhrase)
    local reserve = type(ammo) == "number" and ammo >= 0 and ply:GetAmmoCount(ammo) or nil
    lib._WeaponModel(true, name, clip, ammo, reserve, weaponState)
    weaponState.player, weaponState.weapon = ply, active
end)
