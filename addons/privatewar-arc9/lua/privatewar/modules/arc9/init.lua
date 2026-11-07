-- ARC9 integration module, server glue (T-3.6; 04-weapons.md d.2 and "Security"; 09-hud.md d.1). Session ConVars,
-- set once every base is mounted (PW_WeaponsLoaded):
--   the customization lock, through the adapter's SetCustomizationLocked(true);
--   ARC9's own HUD hidden (HudConVars; replicated, so it reaches every client).
--   ARC9's startup model precache on (PrecacheConVars; also at load, never restored);
--   the server part of the performance profile (sh_perf.lua, restored on ShutDown).
-- ARC9 archives its ConVars, so the values the gamemode replaced are restored on ShutDown (map change and quit): the
-- host's own ARC9 settings outside the gamemode stay as they were; the next map sets them again.
if not PW or PW.API ~= 1 then return end

local lib = PW.Arc9

---@type PW.Arc9ConVarIO
local io = {
    get = function(name)
        local convar = GetConVar(name)
        return convar ~= nil and convar:GetString() or nil
    end,
    set = function(name, value)
        RunConsoleCommand(name, value)
        local convar = GetConVar(name)
        if convar ~= nil then convar:SetString(value) end
    end
}

function lib.SetLocked(locked)
    lib._SwapConVars(PW._Arc9.lock, lib.LockConVars, locked == true, io)
end

function lib.SetHudHidden(hidden)
    lib._SwapConVars(PW._Arc9.hud, lib.HudConVars, hidden == true, io)
end

-- ARC9's startup precache (lib.PrecacheConVars): set when the module loads, before ARC9 reads them about 1 s into the
-- map; again once the weapons are loaded, in case ARC9 had not created them yet (then they work from the next map,
-- ARC9 archives them). Not restored on ShutDown, unlike the lock and the HUD: a precache only moves load time to the
-- map start, changes nothing in play, and must already be on for the next map's early read.
local function precacheOnStartup()
    for name, value in pairs(lib.PrecacheConVars) do
        local current = io.get(name)
        if current ~= nil and current ~= value then io.set(name, value) end
    end
end

precacheOnStartup()

-- 04-weapons.md d.7: the server part of the performance profile (sh_perf.lua).
lib._InstallPerf(MODULE, "server", io)

function MODULE:PW_WeaponsLoaded()
    local registry = rawget(PW, "WeaponAdapters") --[[@as PW.Registry?]]
    local adapter = registry ~= nil and registry.Get("arc9") or nil
    if adapter == nil or not adapter:IsValid() or rawget(_G, "ARC9") == nil then return end
    PW.Adapters.Call(adapter --[[@as PW.Adapter]], "SetCustomizationLocked", true)
    lib.SetHudHidden(true)
    precacheOnStartup()
    lib.ApplyPerf()
end

PW.HookFor(MODULE, "ShutDown", function()
    lib.SetLocked(false)
    lib.SetHudHidden(false)
    lib.RestorePerf()
end)
