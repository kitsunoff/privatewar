HUDELEMENT.Order = 31
HUDELEMENT.Phases = { "LIVE" }

local hud = PW.HUD --[[@as PW.HudLib?]]
-- Always reserve the right-edge streak column and its input hints.
local right, bottom, lineHeight = 1660, 830, 30
local fallback = Color(255, 255, 255)

---@type string[]
local lines = {}
---@type PW.StimMarks
local marks = { speed = 0, heal = 0, armor = 0 }
local tenths, healing, armored = 0, false, false
---@type Player?
local owner

if CLIENT then
    PW.HookFor(HUDELEMENT, "Think", function()
        local stims = PW.Stims
        if stims == nil or hud == nil or hud.PlayerVisible == nil or not hud.PlayerVisible()
            or not IsValid(PW.Modules.Get("stims")) then
            owner = nil
            return
        end
        local ply = LocalPlayer()
        owner = ply
        marks.speed = ply:GetNW2Float("pw_stim_speed_until", 0)
        marks.heal = ply:GetNW2Float("pw_stim_heal_until", 0)
        marks.armor = ply:GetNW2Float("pw_stim_armor_until", 0)
        local now = CurTime()
        local speed = marks.speed > now and math.ceil((marks.speed - now) * 10) or 0
        local heal, armor = marks.heal > now, marks.armor > now
        if tenths == speed and healing == heal and armored == armor then return end
        tenths, healing, armored = speed, heal, armor
        lines = stims._EffectLines(now, marks)
    end)
end

function HUDELEMENT:Draw()
    if #lines == 0 or owner == nil or owner ~= LocalPlayer() or hud == nil or not hud.PlayerVisible() then return end
    local ui = PW.UI
    local tint = ui ~= nil and ui.Style.text or fallback
    local font = ui ~= nil and ui.FontName("small") or hud.Font("stim_effects", 22, 700)
    local x, size = hud.X(right), #lines
    for i = 1, size do
        draw.SimpleText(lines[i], font, x, hud.Y(bottom - (size - i) * lineHeight), tint,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
end
