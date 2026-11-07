-- Hardpoint's pure rules are shared so presentation and server decisions use the same geometry.
MODULE.Name = "Hardpoint"
PW.Hardpoint = PW.Hardpoint or {}
if SERVER then
    AddCSLuaFile("privatewar/modules/hardpoint/sh_geometry.lua")
    AddCSLuaFile("privatewar/modules/hardpoint/sh_state.lua")
    AddCSLuaFile("privatewar/modules/hardpoint/sh_presentation.lua")
    AddCSLuaFile("privatewar/modules/hardpoint/sh_wire.lua")
end
include("privatewar/modules/hardpoint/sh_geometry.lua")
include("privatewar/modules/hardpoint/sh_state.lua")
include("privatewar/modules/hardpoint/sh_presentation.lua")
include("privatewar/modules/hardpoint/sh_wire.lua")
