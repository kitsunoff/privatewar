-- The credited killer sees the victim's card above the XP strip (09-hud.md d.2).
HUDELEMENT.Order = 20
HUDELEMENT.Phases = { "LIVE" }

function HUDELEMENT:Draw()
    local cards = PW.CallingCards
    if cards ~= nil and cards._DrawBanner ~= nil then cards._DrawBanner() end
end
