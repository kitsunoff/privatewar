local lib = PW.Infection --[[@as PW.InfectionLib]]
local presentation = PW.InfectionPresentation --[[@as PW.InfectionPresentationLib]]
local reader = { uint = net.ReadUInt, bool = net.ReadBool, float = net.ReadFloat }
local resultReader = { uint = net.ReadUInt, bool = net.ReadBool, float = net.ReadFloat, string = net.ReadString }

net.Receive("pw_infection_state", function()
    local incoming = presentation.Decode(reader)
    local accepted = presentation.Accept(lib.View, incoming)
    if accepted ~= nil then lib.View = accepted end
end)

net.Receive("pw_infection_results", function()
    local assembly, terminal = presentation.ResultChunk(lib.Assembly, presentation.DecodeResults(resultReader))
    if assembly ~= nil then lib.Assembly = assembly end
    if terminal == nil then return end
    lib.Terminal = terminal
    PW.Notify("PW_PostmatchDataChanged")
end)
