-- Domination flags, client (T-2.4). The UI part of the feature: every networked flag is drawn as a glow and its
-- letter above the flag position, in the owner team's colour (white while nobody holds it). The full HUD element is
-- T-6.5. Flags reach the client through TRANSMIT_ALWAYS; the client keeps its own list (entity Initialize /
-- OnRemove), so drawing never searches the entity list. Colours, the font, the material and the draw position and
-- angle are cached; the per-frame loop allocates nothing.

local lib = PW.DomFlags --[[@as PW.DomFlagsLib]]

local glow = Material("sprites/light_glow02_add")
local neutral = Color(235, 235, 235)
local lift, size, scale = 96, 48, 0.25
local font = "PW_DomFlagLetter"

surface.CreateFont(font, { font = "Roboto", size = 96, weight = 800, antialias = true })

local drawPos = Vector(0, 0, 0)
local drawAng = Angle(0, 0, 0)

function lib._Init(flag)
    lib._Forget(flag)
    lib._Flags[#lib._Flags + 1] = flag
end

---@param owner integer
---@return Color
local function colorFor(owner)
    if owner <= 0 then return neutral end
    return team.GetColor(owner)
end

PW.HookFor(MODULE, "PostDrawTranslucentRenderables", function(_, depth, skybox)
    if depth or skybox or #lib._Flags == 0 then return end
    local yaw = EyeAngles().y
    drawAng:SetUnpacked(0, yaw - 90, 90)
    for _, flag in ipairs(lib._Flags) do
        if IsValid(flag) then
            local color = colorFor(flag:GetOwnerTeam())
            drawPos:Set(flag:GetPos())
            drawPos.z = drawPos.z + lift
            render.SetMaterial(glow)
            render.DrawSprite(drawPos, size, size, color)
            cam.Start3D2D(drawPos, drawAng, scale)
            draw.SimpleText(flag:GetLetter(), font, 0, 0, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end
end)
