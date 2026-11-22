local module = MODULE
local lib = PW.Stims --[[@as PW.StimsLib]]

net.Receive("pw_stim_used", function(bits)
    if bits ~= 8 or not IsValid(module) then return end
    local id = lib._WireItems[net.ReadUInt(8)]
    if id ~= nil then PW.Notify("PW_StimInjected", id) end
end)
