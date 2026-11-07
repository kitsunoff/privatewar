-- ARC9 performance profile (04-weapons.md d.7; DESIGN.md "Global rules" 7, optimisation first). Shared and pure:
-- the ConVar values of the deck profile per realm, the save and restore bookkeeping over PW.Arc9ConVarIO and the
-- crash-safe backup over PW.Arc9PerfBackup. The glue (init.lua on the server, cl_init.lua on the client) applies the
-- host's setting arc9.perf to the ConVars of its own realm and restores them on ShutDown, like the HUD swap.
--
-- Profiles: "deck" (default) sets PerfConVars[realm], saving the originals in the swap and in a backup file of the
-- realm (PerfBackupPath) when it is first applied; "off" restores the originals, deletes the backup and then leaves
-- ARC9 alone. ShutDown restores and deletes the backup. A backup that is still there when the mode starts again
-- means the last session ended without ShutDown (a crash): its originals are restored first (_RecoverPerf), then the
-- profile applies again, so the backup always holds the player's own values, never the deck ones. Same pattern as
-- the testgate ConVar backup of the dev addon (convars_backup.json).
--
-- Realms (checked against ARC9's ConVar table, sh_0_convar.lua): tpik_others, lod_distance, fx_rtvm, muzzle_others
-- and eject_fx are client ConVars (CreateClientConVar, archived); cheapscopes is an archived ConVar of each realm,
-- not replicated, read by the client's scope code, so the client sets its own; bullet_physics and ricochet are
-- archived replicated server ConVars. The precache ConVars (PrecacheConVars) are not part of the profile.

local lib = PW.Arc9

lib.PerfProfiles = { "deck", "off" }

lib.PerfConVars = {
    client = {
        arc9_tpik_others = "0",
        arc9_lod_distance = "0.4",
        arc9_cheapscopes = "1",
        arc9_fx_rtvm = "0",
        arc9_muzzle_others = "0",
        arc9_eject_fx = "0"
    },
    server = {
        arc9_bullet_physics = "0",
        arc9_ricochet = "0"
    }
}

---@type table<string, PW.Arc9PerfAction>
local actions = { deck = "apply", off = "restore" }

function lib._PerfAction(profile)
    return actions[profile] or "none"
end

function lib._PerfValues(profile, realm)
    if lib._PerfAction(profile) ~= "apply" then return {} end
    return table.Copy(lib.PerfConVars[realm]) --[[@as PW.Arc9ConVarValues]]
end

function lib.PerfBackupPath(realm)
    return "privatewar/arc9_perf_" .. realm .. ".json"
end

function lib._RestorePerf(swap, realm, io, backup)
    lib._SwapConVars(swap, lib.PerfConVars[realm], false, io)
    backup.remove()
end

function lib._ApplyPerf(swap, profile, realm, io, backup)
    local action = lib._PerfAction(profile)
    if action == "apply" and not swap.on then
        lib._SwapConVars(swap, lib._PerfValues(profile, realm), true, io)
        backup.write(swap.saved)
    elseif action == "restore" and swap.on then
        lib._RestorePerf(swap, realm, io, backup)
    end
end

-- Thin glue (both realms): the backup of a realm as a JSON file in that realm's data/ (PerfBackupPath).
function lib.PerfFileBackup(realm)
    local path = lib.PerfBackupPath(realm)
    return {
        read = function()
            if not file.Exists(path, "DATA") then return nil end
            local values = util.JSONToTable(file.Read(path, "DATA") or "")
            return istable(values) and values --[[@as table<string, string>]] or {}
        end,
        write = function(values)
            file.CreateDir("privatewar")
            file.Write(path, util.TableToJSON(values))
        end,
        remove = function()
            if file.Exists(path, "DATA") then file.Delete(path) end
        end
    }
end

-- Thin glue (both realms): ApplyPerf and RestorePerf of this realm, and a check every second so that a host change
-- in SETTINGS applies at once. The first apply of the session (ARC9 present) recovers a backup left by a crash.
function lib._InstallPerf(module, realm, io)
    local backup = lib.PerfFileBackup(realm)
    local recovered = false
    function lib.ApplyPerf(profile)
        if rawget(_G, "ARC9") == nil then return end
        if not recovered then
            recovered = true
            local count = lib._RecoverPerf(PW._Arc9.perf, realm, io, backup)
            if count > 0 then
                print(string.format("[PW] arc9: restored %d ARC9 %s settings left by a session without ShutDown",
                    count, realm))
            end
        end
        lib._ApplyPerf(PW._Arc9.perf, profile or tostring(PW.Setting("arc9.perf")), realm, io, backup)
    end
    function lib.RestorePerf()
        lib._RestorePerf(PW._Arc9.perf, realm, io, backup)
    end
    local nextCheck = 0
    PW.HookFor(module, "Think", function()
        local now = RealTime()
        if now < nextCheck then return end
        nextCheck = now + 1
        lib.ApplyPerf()
    end)
end

function lib._RecoverPerf(swap, realm, io, backup)
    if swap.on then return 0 end
    local values = backup.read()
    if values == nil then return 0 end
    local restored = 0
    for name in pairs(lib.PerfConVars[realm]) do
        local value = values[name]
        if isstring(value) and io.get(name) ~= nil then
            io.set(name, value)
            restored = restored + 1
        end
    end
    backup.remove()
    return restored
end
