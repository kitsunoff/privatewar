MODULE.Name = "Weekly challenges"

PW.Challenges = (rawget(PW, "Challenges") or {}) --[[@as PW.ChallengesLib]]

if SERVER then
    AddCSLuaFile("privatewar/modules/challenges/sh_rotation.lua")
    AddCSLuaFile("privatewar/modules/challenges/sh_filters.lua")
    AddCSLuaFile("privatewar/modules/challenges/sh_template.lua")
end
include("privatewar/modules/challenges/sh_rotation.lua")
include("privatewar/modules/challenges/sh_filters.lua")
include("privatewar/modules/challenges/sh_template.lua")
