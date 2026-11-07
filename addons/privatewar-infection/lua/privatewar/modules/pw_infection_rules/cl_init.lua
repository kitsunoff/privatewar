local lib = PW.Infection --[[@as PW.InfectionLib]]
local presentation = PW.InfectionPresentation --[[@as PW.InfectionPresentationLib]]
local reader = { uint = net.ReadUInt, bool = net.ReadBool, float = net.ReadFloat }

net.Receive("pw_infection_state", function()
    local incoming = presentation.Decode(reader)
    local accepted = presentation.Accept(lib.View, incoming)
    if accepted ~= nil then lib.View = accepted end
end)
