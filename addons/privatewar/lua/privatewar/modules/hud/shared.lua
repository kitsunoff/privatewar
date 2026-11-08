-- HUD module (T-6.1; 09-hud.md d.3: one HUDPaint iterating the HUDELEMENT registry, every element call through
-- PW.Call). Shared and pure: which elements are visible in which phase and in which order, the design-unit scale,
-- and the paint loop over a registry (the loop calls only Draw/ShouldDraw, so the server-side test runner covers
-- it). The engine part (HUDPaint, scaling, fonts, hidden HL2 elements) is cl_init.lua.
--
-- Performance (09 "Performance budget"): the ordered list is rebuilt only when the phase, the registry or an
-- element's validity changed; a frame allocates nothing here.

MODULE.Name = "HUD"

local lib = (rawget(PW, "HUD") or {}) --[[@as PW.HudLib]]
PW.HUD = lib

-- Pure rules of the match status element (U-8): sh_status.lua.
if SERVER then AddCSLuaFile("privatewar/modules/hud/sh_status.lua") end
include("privatewar/modules/hud/sh_status.lua")

-- Pure rules of the radar (T-6.6): sh_radar.lua.
if SERVER then AddCSLuaFile("privatewar/modules/hud/sh_radar.lua") end
include("privatewar/modules/hud/sh_radar.lua")

-- Pure rules of the score bars of the match status (T-11.5): sh_scorebars.lua. After sh_radar.lua: the layout sits
-- under the radar and reads PW.HUD.Radar.
if SERVER then AddCSLuaFile("privatewar/modules/hud/sh_scorebars.lua") end
include("privatewar/modules/hud/sh_scorebars.lua")

-- Pure rules of the score popups and medals (T-6.4): sh_popups.lua.
if SERVER then AddCSLuaFile("privatewar/modules/hud/sh_popups.lua") end
include("privatewar/modules/hud/sh_popups.lua")

-- Pure rules of the killstreak squares and bar (T-4.6 HUD): sh_streaks.lua.
if SERVER then AddCSLuaFile("privatewar/modules/hud/sh_streaks.lua") end
include("privatewar/modules/hud/sh_streaks.lua")

-- Pure rules of the bottom XP bar and the level-up detection: sh_xpbar.lua.
if SERVER then AddCSLuaFile("privatewar/modules/hud/sh_xpbar.lua") end
include("privatewar/modules/hud/sh_xpbar.lua")

-- User-approved player HUD (T-11.11; 09-hud.md revision 2026-11-08), pure presentation only.
if SERVER then
    AddCSLuaFile("privatewar/modules/hud/sh_vitals.lua")
    AddCSLuaFile("privatewar/modules/hud/sh_weapon.lua")
end
include("privatewar/modules/hud/sh_vitals.lua")
include("privatewar/modules/hud/sh_weapon.lua")

lib.DesignWidth = 1920
lib.DesignHeight = 1080

-- Order of an element that does not set one.
local defaultOrder = 100

---@param element PW.HudElement
---@return number
local function orderOf(element)
    return element.Order or defaultOrder
end

---@param first PW.HudElement
---@param second PW.HudElement
---@return boolean
local function before(first, second)
    local a, b = orderOf(first), orderOf(second)
    if a ~= b then return a < b end
    return tostring(first.ClassName) < tostring(second.ClassName)
end

---@param element PW.HudElement
---@param phase PW.PhaseName
---@return boolean
local function inPhase(element, phase)
    local phases = element.Phases
    if phases == nil then return true end
    for i = 1, #phases do
        if phases[i] == phase then return true end
    end
    return false
end

---Inserts the element into out[1..count] keeping the order; allocates nothing.
---@param out PW.HudElement[]
---@param count integer
---@param element PW.HudElement
local function insert(out, count, element)
    local at = count + 1
    while at > 1 and before(element, out[at - 1] --[[@as PW.HudElement]]) do
        out[at] = out[at - 1]
        at = at - 1
    end
    out[at] = element
end

function lib._Select(elements, phase, flags, out)
    local count = 0
    if flags == nil or not flags.hidden then
        for i = 1, #elements do
            local element = elements[i] --[[@as PW.HudElement]]
            if inPhase(element, phase) then
                insert(out, count, element)
                count = count + 1
            end
        end
    end
    for i = count + 1, #out do out[i] = nil end
    return count
end

function lib._Scale(width, height)
    local sx, sy = width / lib.DesignWidth, height / lib.DesignHeight
    return sx, sy, math.min(sx, sy)
end

function lib._NewState()
    return { list = {}, count = 0, dirty = true }
end

---@param state PW.HudState
---@param registry PW.Registry
---@param phase PW.PhaseName
---@param flags? PW.HudFlags
local function refresh(state, registry, phase, flags)
    state.registry, state.phase, state.dirty = registry, phase, false
    state.count = lib._Select(registry.GetEnabledList() --[[@as PW.HudElement[] ]], phase, flags, state.list)
end

function lib._Paint(state, registry, phase, flags)
    if flags ~= nil and flags.hidden then return end
    if state.dirty or state.registry ~= registry or state.phase ~= phase then
        refresh(state, registry, phase, flags)
    end
    local list = state.list
    for i = 1, state.count do
        local element = list[i] --[[@as PW.HudElement]]
        element._HudPainted = false
        local visible = element:IsValid() and (element.ShouldDraw == nil or PW.Call(element, "ShouldDraw"))
        if visible then
            PW.Call(element, "Draw")
            element._HudPainted = element:IsValid()
        end
        -- Disabled before this frame or by an error just now: leave the cached list at the next frame.
        if not element:IsValid() then state.dirty = true end
    end
end
