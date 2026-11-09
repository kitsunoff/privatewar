-- Shared entry point of the Private War gamemode (DESIGN.md).

GM.Name = "Private War"
GM.Author = "Private War contributors"
GM.TeamBased = true
-- No base team chooser: teams belong to the teams module, the lobby is our own screen. The base gamemode opens it
-- through gm_showteam (F2, and PlayerInitialSpawn when TeamBased) -> server GM:ShowTeam -> client GM:ShowTeam.
rawset(GM, "ShowTeam", function() end)

PW = PW or {}
PW.Version = "0.0.2"
PW.API = 1

include("core/sh_hooks.lua")
include("core/sh_registry.lua")
include("core/sh_call.lua")
include("core/sh_instance.lua")
include("core/sh_loader.lua")
include("core/sh_privileges.lua")
include("core/sh_settings.lua")
include("core/sh_settings_store.lua")
include("core/sh_phase.lua")
include("core/sh_reload.lua")
include("core/sh_weapon_phase.lua")
include("core/sh_enable.lua")
if SERVER then
    include("core/sv_enable.lua")
    include("core/sv_match.lua")
    include("core/sv_dependencies.lua")
    include("core/sv_net.lua")
    include("core/sv_settings.lua")
    include("core/sv_mapchange.lua")
    include("core/sv_reload.lua")
else
    include("core/cl_enable.lua")
    include("core/cl_phase.lua")
    include("core/cl_ready.lua")
end

PW.Loader.Boot()
