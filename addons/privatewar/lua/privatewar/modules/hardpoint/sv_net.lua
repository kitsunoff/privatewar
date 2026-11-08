local hp = assert(PW.Hardpoint)
local module = MODULE
util.AddNetworkString("pw_hp_state")

function hp.Send(snapshot, recipient)
    net.Start("pw_hp_state")
    hp.WriteSnapshot(snapshot)
    if recipient ~= nil then net.Send(recipient) else net.Broadcast() end
end

assert(PW.Net).Receive("pw_hp_request", {
    who = "any", phases = { "LIVE" }, rate = 2, maxLen = 0, owner = module
}, function(ply, length)
    if length ~= 0 then return end
    local mode = PW.ActiveMode --[[@as PW.HardpointMode?]]
    local runtime = mode ~= nil and mode.ClassName == "hardpoint" and mode._Hardpoint or nil
    if runtime ~= nil then hp.Send(hp.PublicSnapshot(runtime.state, runtime.revision), ply) end
end)
