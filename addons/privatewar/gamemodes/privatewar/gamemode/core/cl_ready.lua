-- Client loaded handshake (T-1.14, 00-core.md d.9). From client InitPostEntity the client sends pw_client_ready
-- every 2 s until the server answers pw_client_ready_ack: a lost message is resent (garrysmod-issues #5081). The
-- Lua state resets on changelevel, so the handshake runs again on every map. Server side: sv_mapchange.lua.

local timerName = "PW.ClientReady"
local retryEvery = 2

local function sendReady()
    net.Start("pw_client_ready")
    net.SendToServer()
end

net.Receive("pw_client_ready_ack", function()
    timer.Remove(timerName)
end)

hook.Add("InitPostEntity", "PW.ClientReady", function()
    timer.Create(timerName, retryEvery, 0, sendReady)
    sendReady()
end)
