-- Match flow in the lobby (Phase 11 match flow fixes; 08-lobby.md d.3; 00-core.md d.9; 10-frontend.md d.1). Pure and
-- shared: which screen a phase shows, the START button during the start countdown (PREMATCH) and while a map change
-- is announced, and the map change popup. The client glue is cl_init.lua (refresh) and cl_flow.lua (the popup).
--   PREMATCH keeps the lobby open: the START button counts down ("STARTING 5...") in accent ink on a dark fill,
--   instead of the former "Match starts in N" HUD message.
--   An announced map change (PW.Phase.GetMapChange) shows "MAP CHANGE 5..." on the button and the popup with the
--   map, the mode and the seconds left.

local lib = (rawget(PW, "Lobby") or {}) --[[@as PW.LobbyLib]]
PW.Lobby = lib

local ellipsis = "\226\128\166"

lib.FlowText = {
    starting = "STARTING %d" .. ellipsis,
    startingReason = "The match is starting",
    changing = "MAP CHANGE %d" .. ellipsis,
    changingReason = "The map is changing",
    popupTitle = "MAP CHANGE",
    popupIn = "Loading in %d" .. ellipsis
}

-- The countdown look of the START button: PW.UI.Style tokens.
lib.CountdownColours = { fill = "bg_raised", ink = "accent", outline = "accent" }

---@type table<string, PW.LobbyScreen>
local screens = { LOBBY = "lobby", PREMATCH = "lobby", POSTMATCH = "postmatch", VOTE = "vote" }

function lib._ScreenFor(phase)
    return screens[phase]
end

function lib._ShouldShow(phase, active, kit)
    return lib._ScreenFor(phase) == "lobby" and active and kit
end

---@param endsAt? number
---@param now number
---@return integer?
local function seconds(endsAt, now)
    if endsAt == nil or endsAt < 0 then return nil end
    return math.max(0, math.ceil(endsAt - now))
end

function lib._StartButton(facts)
    local text = lib.FlowText
    local change = seconds(facts.changeAt, facts.now)
    if change ~= nil then
        return { label = string.format(text.changing, change), reason = text.changingReason, seconds = change }
    end
    if facts.phase ~= "PREMATCH" then return nil end
    local left = seconds(facts.phaseEnd, facts.now) or 0
    return { label = string.format(text.starting, left), reason = text.startingReason, seconds = left }
end

function lib._ApplyFlow(start, facts)
    if facts == nil then return start end
    local over = lib._StartButton(facts)
    if over == nil then return start end
    start.label, start.title, start.text = over.label, over.label, over.reason
    start.locked, start.reason, start.countdown = true, over.reason, true
    return start
end

function lib._MapTitle(map, name)
    if isstring(name) and name ~= "" and name ~= map then return string.upper(name --[[@as string]]) end
    local rest = string.match(map, "^%a%a?%a?%a?_(.+)$") or map
    local spaced = string.gsub(rest, "_", " ")
    return string.upper(spaced)
end

function lib._MapChangePopup(facts)
    local left = seconds(facts.changeAt, facts.now)
    if left == nil then return nil end
    return {
        title = lib.FlowText.popupTitle, map = lib._MapTitle(facts.map, facts.mapName),
        mode = string.upper(facts.modeName or ""), seconds = left,
        line = string.format(lib.FlowText.popupIn, left)
    }
end
