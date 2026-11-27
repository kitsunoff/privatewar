-- Playlist setup is a local, read-only review. Only the explicit Start action sends a start request.
SCREEN.Tab = "play"
SCREEN.Title = "Playlist setup"
---@type PW.UIHintEntry[]
local hints = { { action = "accept", label = "Start playlist" }, { action = "back", label = "Back" } }
SCREEN.Hints = hints

---@class PWPlaylistSetupView : Panel
---@field playlist string
---@field info PWInfoCard
---@field start PWButton
---@field action PW.LobbyAction
---@field framed boolean

---@return PW.LobbyLib
local function lobby()
    return PW.Lobby --[[@as PW.LobbyLib]]
end

---@param view PWPlaylistSetupView
local function refresh(view)
    local lib = lobby()
    local model = lib._PlaylistSetup(lib.Input(), view.playlist)
    ---@type { [1]: string, [2]: string }[]
    local rows = { { "Mode and map", "Picked by the playlist" } }
    if model.fill ~= nil then rows[#rows + 1] = { "Bots fill", tostring(model.fill) } end
    if model.timer ~= nil then rows[#rows + 1] = { "Schedule", model.timer } end
    view.info:SetTitle(model.name)
    view.info:SetText(model.description)
    view.info:SetRows(rows)
    view.info:SetWarning(model.warning)
    view.action = model.start
    view.start:SetText(model.start.label or "START PLAYLIST")
    view.start:SetLocked(model.start.locked, model.start.reason)
    view.start:SetVariant(model.start.countdown and "countdown" or "primary")
    view.framed = false
    view:InvalidateLayout(true)
end

---@param view PWPlaylistSetupView
---@param w number
---@param h number
local function layout(view, w, h)
    local px = PW.UI.Draw.Px
    local width = math.max(0, math.min(w - px(48), px(640)))
    local x, y = math.floor((w - width) / 2), px(24)
    local buttonH, gap = px(64), px(20)
    local infoH = math.max(0, math.min(view.info:WantedHeight(width), h - y - gap - buttonH))
    view.info:SetPos(x, y)
    view.info:SetSize(width, infoH)
    view.start:SetPos(x, y + infoH + gap)
    view.start:SetSize(width, buttonH)
end

function SCREEN:Build(ctx)
    local lib = lobby()
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWPlaylistSetupView]]
    view:Dock(FILL)
    view.playlist = lib.PlaylistSetupId()
    view.info = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.start = vgui.Create("PWButton", view) --[[@as PWButton]]
    PW.UI.Focusable(view.start, "playlist_setup", "start_playlist")
    view.start.DoClick = function()
        local start = lib._PlaylistSetup(lib.Input(), view.playlist).start
        if not start.locked and start.request ~= nil then lib.SendStart(start.request) end
    end
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.Think = function()
        if view.framed then return end
        view.framed = true
        lib.SetFrame(view.action.reason, hints)
    end
    view.PWRefresh = function() refresh(view) end
    refresh(view)
    return view
end
