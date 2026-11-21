MODULE.Name = "Weekly challenges"

PW.Challenges = (rawget(PW, "Challenges") or {}) --[[@as PW.ChallengesLib]]

if SERVER then AddCSLuaFile("privatewar/modules/challenges/sh_rotation.lua") end
include("privatewar/modules/challenges/sh_rotation.lua")
