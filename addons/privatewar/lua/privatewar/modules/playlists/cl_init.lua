-- Playlists module, client (T-2.6; 08-lobby.md d.2). Holds the list the server sent (pw_playlist_list) and sends the
-- host's pick and start requests; the lobby screen (lobby_ui/cl_init.lua) draws it and refreshes through
-- PW.Playlist.OnChange. The client decides nothing: the server checks privilege, phase and the id again. The
-- file checks its module with IsValid(module) only (MODULE has no IsValid while the file runs).

local module = MODULE

local lib = PW.Playlist --[[@as PW.PlaylistLib]]

---@type PW.PlaylistListState?
local state = nil

function lib.GetState()
    return state
end

function lib.Request()
    net.Start("pw_playlist_request")
    net.SendToServer()
end

function lib.SendPick(id)
    net.Start("pw_playlist_pick")
    net.WriteString(id)
    net.SendToServer()
end

function lib.SendStart(id)
    net.Start("pw_playlist_start")
    net.WriteString(id)
    net.SendToServer()
end

net.Receive("pw_playlist_list", function()
    if not IsValid(module) then return end
    local ok, incoming = pcall(lib._Decode,
        { uint = net.ReadUInt, string = net.ReadString, bool = net.ReadBool, number = net.ReadDouble })
    if not ok or incoming == nil or not lib._Newer(state, incoming) then return end
    state = incoming
    if lib.OnChange ~= nil then lib.OnChange() end
end)

net.Receive("pw_playlist_error", function()
    local reason = net.ReadString()
    if IsValid(module) and #reason <= 256 then notification.AddLegacy(reason, NOTIFY_ERROR, 6) end
end)
