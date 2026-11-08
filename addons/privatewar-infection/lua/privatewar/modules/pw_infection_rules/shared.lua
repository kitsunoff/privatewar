-- Optional addon-owned rules and presentation; no framework or asset dependency.
MODULE.Name = "Infection rules"
PW.Infection = (rawget(PW, "Infection") or { Revision = 0 }) --[[@as PW.InfectionLib]]
if SERVER then
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_rules.lua")
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_presentation.lua")
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_pursuit.lua")
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_results.lua")
end
include("privatewar/modules/pw_infection_rules/sh_rules.lua")
include("privatewar/modules/pw_infection_rules/sh_presentation.lua")
include("privatewar/modules/pw_infection_rules/sh_pursuit.lua")
include("privatewar/modules/pw_infection_rules/sh_results.lua")

---@param data PW.UIPostmatchData
---@param ownId integer
function MODULE:PW_PostmatchGathered(data, ownId)
    local terminal = assert(PW.Infection).Terminal
    if terminal == nil or not terminal.active or not GetGlobal2Bool("pw_infection_results", false)
        or PW.Phase.GetPhase() ~= "POSTMATCH" then return end
    assert(PW.InfectionPresentation).ApplyPostmatch(data, terminal, ownId)
end
