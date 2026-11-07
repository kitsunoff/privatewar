local hp = assert(PW.Hardpoint)
local module = MODULE

net.Receive("pw_hp_state", function(length)
    if not IsValid(module) or length > 1024 then return end
    hp.ClientSnapshot = hp.AcceptSnapshot(hp.ClientSnapshot, hp.ReadSnapshot())
end)

---@param phase PW.PhaseName
function MODULE:PW_PhaseChanged(phase)
    if phase == "LIVE" then
        net.Start("pw_hp_request")
        net.SendToServer()
    elseif phase == "LOBBY" or phase == "PREMATCH" then
        if hp.ClientSnapshot ~= nil then hp.ClientSnapshot.active = false end
    end
end

local markerPos, markerAngle = Vector(), Angle()
local neutral, warning = Color(232, 237, 233), Color(255, 181, 71)
---@type table<string, Color>
local controls = { text = neutral, warning = warning,
    team_friendly = Color(79, 195, 247), team_enemy = Color(255, 77, 77) }
local glow = Material("sprites/light_glow02_add")
local font = ""
PW.HookFor(module, "PostDrawTranslucentRenderables", function(_, depth, skybox)
    local snapshot = hp.ClientSnapshot
    if depth or skybox or snapshot == nil or not snapshot.active or PW.Phase.GetPhase() ~= "LIVE" then return end
    if PW.HUD == nil then return end
    if font == "" then font = PW.HUD.Font("hp_marker", 32, 800) end
    markerPos:Set(snapshot.zone.pos)
    markerPos.z = markerPos.z + 80
    markerAngle:SetUnpacked(0, EyeAngles().y - 90, 90)
    local me = LocalPlayer()
    local token = hp.ControlToken(snapshot.control, snapshot.contested, IsValid(me) and me:Team() or 0)
    local palette = (PW.UI ~= nil and PW.UI.Style or controls) --[[@as table<string, Color>]]
    local color = palette[token] or neutral
    render.SetMaterial(glow)
    render.DrawSprite(markerPos, 36, 36, color)
    cam.Start3D2D(markerPos, markerAngle, 0.6)
    draw.SimpleText(snapshot.zone.id, font, 0, -40, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end)
