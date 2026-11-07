-- Optional addon-owned rules and presentation; no framework or asset dependency.
MODULE.Name = "Infection rules"
PW.Infection = (rawget(PW, "Infection") or { Revision = 0 }) --[[@as PW.InfectionLib]]
if SERVER then
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_rules.lua")
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_presentation.lua")
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_pursuit.lua")
end
include("privatewar/modules/pw_infection_rules/sh_rules.lua")
include("privatewar/modules/pw_infection_rules/sh_presentation.lua")
include("privatewar/modules/pw_infection_rules/sh_pursuit.lua")
