-- Hitmarker, client (T-6.3). Keeps the marker that hud/hitmarker.lua draws: the kind and the time it started. A new
-- message replaces the running marker (the fade restarts). The server already merged the hits of a tick.

local lib = PW.Hitmarker --[[@as PW.HitmarkerLib]]

function lib._Show(kind, now)
    local current = lib.Current
    current.kind, current.at = kind, now
end

net.Receive("pw_hitmarker", function()
    local kind = lib._Decode(net.ReadUInt(2))
    if kind ~= nil then (lib._Show --[[@as fun(kind: PW.HitKind, now: number)]])(kind, CurTime()) end
end)
