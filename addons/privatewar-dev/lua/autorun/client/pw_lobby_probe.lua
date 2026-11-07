-- Dev-only client probe for the lobby screen (scripts/deck/snap.sh). Never shipped (T-10.2).
-- "client pw_dev_lobby_probe <tag>" prints one key=value line to the console log (the listen host's client shares
-- it with the server): the phase the client sees and the one it applied (PW._PhaseView), the lobby view
-- (PW.Lobby._View: open, waiting, state), whether the kit's root is open, how many PWRoot panels exist and are
-- visible (an orphan root left by a reload shows here), and whether the lobby_ui and ui_kit modules are valid.
-- "client pw_dev_lobby_open <tag>" opens the lobby only if it is closed (PW.Lobby.Open does nothing when the root is
-- open or the phase is not LOBBY), then prints the probe line. Use it before a screenshot instead of pw_lobby: in
-- LOBBY the lobby is already open, and pw_lobby (the player's F1 command) toggles, so it closes it.

---@param tag string?
---@return string
local function tagOf(tag)
    if tag == nil or tag == "" then return "-" end
    return tag
end

---@param id string
---@return string
local function moduleField(id)
    local modules = PW ~= nil and rawget(PW, "Modules") or nil
    local entry = modules ~= nil and modules.Get(id) or nil
    if entry == nil then return "missing" end
    return entry:IsValid() and "valid" or "invalid"
end

---@return integer total
---@return integer visible
local function roots()
    local total, visible = 0, 0
    for _, child in ipairs(vgui.GetWorldPanel():GetChildren() --[[@as Panel[] ]]) do
        if child:GetName() == "PWRoot" then
            total = total + 1
            if child:IsVisible() then visible = visible + 1 end
        end
    end
    return total, visible
end

---@param tag string?
local function probe(tag)
    local lobby = PW ~= nil and rawget(PW, "Lobby") or nil
    local view = lobby ~= nil and rawget(lobby, "_View") or {}
    local applied = PW ~= nil and rawget(PW, "_PhaseView") or {}
    local ui = PW ~= nil and rawget(PW, "UI") or nil
    local rootOpen = ui ~= nil and ui.RootOpen ~= nil and ui.RootOpen()
    local total, visible = roots()
    print(string.format("[PW] lobbyprobe tag=%s phase=%s seq=%d applied=%s/%s view.open=%s waiting=%s state=%s "
        .. "root=%s roots=%d/%d lobby_ui=%s ui_kit=%s", tagOf(tag), GetGlobal2String("pw_phase", "?"),
        GetGlobal2Int("pw_phase_seq", -1), tostring(applied.phase), tostring(applied.seq), tostring(view.open),
        tostring(view.waiting), tostring(view.state ~= nil), tostring(rootOpen), visible, total,
        moduleField("lobby_ui"), moduleField("ui_kit")))
end

concommand.Add("pw_dev_lobby_probe", function(_, _, args) probe(args[1]) end, nil,
    "Private War dev: print the client's phase and lobby screen state in one line")

concommand.Add("pw_dev_lobby_open", function(_, _, args)
    local lobby = PW ~= nil and rawget(PW, "Lobby") or nil --[[@as PW.LobbyLib?]]
    if lobby ~= nil and lobby.Open ~= nil then lobby.Open() end
    timer.Simple(0.5, function() probe(args[1] or "open") end)
end, nil, "Private War dev: open the lobby if it is closed (never closes it), then print the probe line")

hook.Add("PW_PhaseChanged", "pw_lobby_probe", function(phase, _, seq)
    print(string.format("[PW] lobbyprobe client-phase phase=%s seq=%s", tostring(phase), tostring(seq)))
end)
