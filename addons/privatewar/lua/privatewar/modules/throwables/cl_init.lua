-- Throwables module, client (T-4.5). A blind ("pw_blind") paints the screen white: held, then fading
-- (PW.Throwables._BlindAlpha). It is drawn in RenderScreenspaceEffects, not as a HUD element, so turning the
-- overlay off (pw_hud 0) does not remove it. A frame allocates nothing.

local lib = PW.Throwables --[[@as PW.ThrowablesLib]]

lib.Blinded = lib.Blinded or { strength = 0, at = 0 }

net.Receive("pw_blind", function()
    local blinded = lib.Blinded --[[@as { strength: number, at: number }]]
    blinded.strength = lib._DecodeStrength(net.ReadUInt(8))
    blinded.at = CurTime()
end)

PW.HookFor(MODULE, "RenderScreenspaceEffects", function()
    local blinded = lib.Blinded --[[@as { strength: number, at: number }]]
    if blinded.strength <= 0 then return end
    local alpha = lib._BlindAlpha(CurTime() - blinded.at, blinded.strength)
    if alpha <= 0 then
        blinded.strength = 0
        LocalPlayer():SetDSP(0, false)
        return
    end
    cam.Start2D()
    surface.SetDrawColor(255, 255, 255, 255 * alpha)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    cam.End2D()
end)
