-- Dev-only client probe for scripts/deck/cp1.sh (checkpoint CP-1, TASKS.md). Never shipped (T-10.2).
-- The dev bridge runs it on the listen host's client ("client pw_cp1_probe <tag>"); the client prints to the same
-- console log as the server. Lines start with "[PW] cp1 " and are key=value:
--   pw_cp1_probe <tag>   phase as the client sees it (NW2 globals), the lobby screen (open, and filled = it got
--                        the server's pw_lobby_state and built its content) and the base team chooser
--   PW_PhaseChanged      one "client-phase" line per phase the client applied

---@param tag string?
---@return string
local function tagOf(tag)
    if tag == nil or tag == "" then return "-" end
    return tag
end

---@return string
local function nw2Fields()
    return string.format("phase=%s seq=%d end=%.2f now=%.2f map=%s", GetGlobal2String("pw_phase", "?"),
        GetGlobal2Int("pw_phase_seq", -1), GetGlobal2Float("pw_phase_end", -2), CurTime(), game.GetMap())
end

---@param panel any
---@return boolean
local function shown(panel)
    return panel ~= nil and IsValid(panel) and panel:IsVisible()
end

---@return string open "open" or "closed"
---@return string filled "yes" when the screen got its state from the server and built its content
local function lobbyState()
    local lobby = PW ~= nil and rawget(PW, "Lobby") or nil
    local view = lobby ~= nil and rawget(lobby, "_View") or nil
    if view == nil or not shown(view.frame) then return "closed", "no" end
    local filled = view.state ~= nil and shown(view.content)
    return "open", filled and "yes" or "no"
end

---Titles of the visible top-level frames (spaces replaced, so the line stays key=value).
---@return string[] titles
---@return boolean teamChooser a visible frame looks like the base team chooser ("Pick Team")
local function frames()
    ---@type string[]
    local titles = {}
    local teamChooser = false
    local children = vgui.GetWorldPanel():GetChildren() --[[@as Panel[] ]]
    for _, child in ipairs(children) do
        ---@type any
        local getTitle = (child --[[@as table]])["GetTitle"]
        if child:IsVisible() and isfunction(getTitle) then
            local title = tostring(getTitle(child))
            titles[#titles + 1] = string.gsub(title, "%s+", "_")
            if string.find(string.lower(title), "team", 1, true) then teamChooser = true end
        end
    end
    return titles, teamChooser
end

concommand.Add("pw_cp1_probe", function(_, _, args)
    local titles, teamTitle = frames()
    local gm = GAMEMODE or GM
    local teamFrame = gm ~= nil and shown(rawget(gm, "TeamSelectFrame"))
    local open, filled = lobbyState()
    print(string.format("[PW] cp1 probe tag=%s %s lobby=%s filled=%s teampicker=%s frames=%s", tagOf(args[1]),
        nw2Fields(), open, filled, (teamFrame or teamTitle) and "open" or "closed",
        #titles > 0 and table.concat(titles, ",") or "none"))
end, nil, "Private War dev (CP-1): print the client's phase and screen state in one line")

hook.Add("PW_PhaseChanged", "pw_cp1", function(phase, endsAt, seq)
    print(string.format("[PW] cp1 client-phase phase=%s seq=%d end=%.2f now=%.2f", tostring(phase), seq, endsAt,
        CurTime()))
end)
