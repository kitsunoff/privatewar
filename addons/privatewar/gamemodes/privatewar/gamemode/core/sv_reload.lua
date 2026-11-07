-- The pw_reload command (T-1.15, 01-extensibility.md d.12; 00-core.md d.7). Server only. The host and superadmins
-- (privilege "pw.reload") and the server console reload the server (PW.Reload.Run), then the server tells every
-- client to reload with the pw_reload message (server -> client, no payload). Re-running this file replaces the
-- command, the privilege and the network string instead of adding new ones.

local reload = PW.Reload

reload.Privilege = "pw.reload"
PW.Privilege(reload.Privilege, "superadmin")

util.AddNetworkString("pw_reload")

function reload._Command(ply)
    local store = PW._Reload
    local fromPlayer = IsValid(ply)
    if fromPlayer and not PW.Can(ply --[[@as Player]], reload.Privilege) then
        store.log(string.format("pw_reload denied for %s", tostring((ply --[[@as Player]]):Nick())))
        return false
    end
    local who = fromPlayer and tostring((ply --[[@as Player]]):Nick()) or "the server console"
    if not reload.Run("pw_reload by " .. who) then return false end
    store.broadcast()
    return true
end

concommand.Add("pw_reload", function(ply) reload._Command(ply) end, nil,
    "Private War: rescan every kind folder on the server and all clients (new definitions apply at the next match)")
