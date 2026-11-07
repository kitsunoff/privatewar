-- Hardpoint's pure rules are shared so presentation and server decisions use the same geometry.
MODULE.Name = "Hardpoint"
PW.Hardpoint = PW.Hardpoint or {}
if SERVER then
    AddCSLuaFile("sh_geometry.lua")
    AddCSLuaFile("sh_state.lua")
    AddCSLuaFile("sh_presentation.lua")
end
include("sh_geometry.lua")
include("sh_state.lua")
include("sh_presentation.lua")
