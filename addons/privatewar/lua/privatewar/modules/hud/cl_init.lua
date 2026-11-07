-- HUD module, client (T-6.1; 09-hud.md d.1, d.3). The single HUDPaint over the hud registry (the paint loop is
-- shared.lua: _Paint), design-unit scaling for 1920x1080, cached fonts and the HUDShouldDraw list. Visual style is
-- the ui lane's (D1 is open): elements read PW.UI.Style when ui_kit is on.

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.HudModuleClient : PW.Module
local module = MODULE --[[@as PW.HudModuleClient]]

local lib = PW.HUD --[[@as PW.HudLib]]

-- HL2 HUD elements to hide (HUDShouldDraw names). Empty: 09 d.1 keeps the vanilla health, ammo, crosshair and
-- killfeed, and the overlay only adds to them.
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
    surface.CreateFont("PW_HUD_" .. id, {
        font = "Roboto", size = math.max(1, math.floor(spec.size * scaleS + 0.5)), weight = spec.weight,
        antialias = true
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
    if lib.Hidden[name] then return false end
end)
