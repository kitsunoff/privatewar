-- ARC9 integration module, client glue (09-hud.md d.1). The server hides ARC9's HUD for everyone through a
-- replicated ConVar (init.lua); the hints ARC9 draws without its HUD are a client ConVar, set here once the client
-- is in the game and restored on ShutDown (ARC9 archives it, so the player's own setting outside the gamemode stays).
-- The client part of the performance profile (sh_perf.lua) is applied and restored the same way.
if not PW or PW.API ~= 1 then return end

local lib = PW.Arc9

---@type PW.Arc9ConVarIO
local io = {
    get = function(name)
        local convar = GetConVar(name)
        return convar ~= nil and convar:GetString() or nil
    end,
    set = function(name, value) RunConsoleCommand(name, value) end
}

function lib.SetHudHidden(hidden)
    if rawget(_G, "ARC9") == nil then return end
    lib._SwapConVars(PW._Arc9.hud, lib.ClientHudConVars, hidden == true, io)
end

PW.HookFor(MODULE, "InitPostEntity", function()
    lib.SetHudHidden(true)
    lib.ApplyPerf()
end)

-- 04-weapons.md d.7: the client part of the performance profile (sh_perf.lua).
lib._InstallPerf(MODULE, "client", io)

-- A reload (pw_reload, auto-refresh) runs this file after InitPostEntity.
if IsValid(LocalPlayer()) then lib.SetHudHidden(true) end

PW.HookFor(MODULE, "ShutDown", function()
    lib.SetHudHidden(false)
    lib.RestorePerf()
end)
