MODULE.Name = "Weekly challenges"
MODULE.Settings = {
    perweek = { scope = "server", type = "int", default = 5, min = 1, max = 12, label = "Weekly challenges" },
    bonusneeded = { scope = "server", type = "int", default = 4, min = 0, max = 12,
        label = "Weekly bonus completions" },
    seed = { scope = "server", type = "int", default = 0, min = 0, max = 2147483646, label = "Weekly challenge seed" }
}

PW.Challenges = (rawget(PW, "Challenges") or {}) --[[@as PW.ChallengesLib]]
PW.Challenges._MaxInstanceId = 40
PW.Challenges.ProgressInterval = 1

if SERVER then
    AddCSLuaFile("privatewar/modules/challenges/sh_rotation.lua")
    AddCSLuaFile("privatewar/modules/challenges/sh_filters.lua")
    AddCSLuaFile("privatewar/modules/challenges/sh_template.lua")
    AddCSLuaFile("privatewar/modules/challenges/sh_events.lua")
    AddCSLuaFile("privatewar/modules/challenges/sh_progress.lua")
    AddCSLuaFile("privatewar/modules/challenges/sh_storage.lua")
    AddCSLuaFile("privatewar/modules/challenges/sh_wire.lua")
end
include("privatewar/modules/challenges/sh_rotation.lua")
include("privatewar/modules/challenges/sh_filters.lua")
include("privatewar/modules/challenges/sh_template.lua")
include("privatewar/modules/challenges/sh_events.lua")
include("privatewar/modules/challenges/sh_progress.lua")
include("privatewar/modules/challenges/sh_storage.lua")
include("privatewar/modules/challenges/sh_wire.lua")
