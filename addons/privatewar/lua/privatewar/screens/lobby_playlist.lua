-- A separate route keeps playlist context across tab switches; Custom Game owns the shared layout.
SCREEN.Tab = "play"
SCREEN.Title = "Playlist setup"
SCREEN.Hints = { { action = "accept", label = "Start playlist" }, { action = "back", label = "Back" } }

function SCREEN:Build(ctx)
    local registry = PW.Registries.screens
    local custom = registry ~= nil and registry.Get("lobby_custom") or nil
    local getId = PW.Lobby and PW.Lobby.PlaylistSetupId
    if custom == nil or getId == nil then return nil end
    return PW.Call(custom, "Build", ctx, getId())
end
