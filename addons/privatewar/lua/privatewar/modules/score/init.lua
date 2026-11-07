-- Score module, server glue (T-2.1; 06-progression.md d.3). Award resolves the event, asks PW_ScoreValue, adds the
-- match score (player, and the team in a team mode), then notifies:
--   1. the score is added and published (NW2);
--   2. PW_ScoreEvent(ply, eventId, points, xp, weapon): progression, streaks, HUD popups, medals, the announcer;
--   3. PW_ScoreChanged(ply, score, delta, team, teamScore): consumers of the resulting score (score limit checks).
-- Scores are reset when PREMATCH turns into LIVE (before MODE:Start) and cleared when the lobby returns; they stay
-- readable in POSTMATCH. Both hooks are notifications: listeners must not return a value (01-extensibility.md d.9).

local lib = PW.Score --[[@as PW.ScoreLib]]

util.AddNetworkString("pw_score_popup")

---Wire value of points: UInt(16).
---@param points number
---@return integer
function lib._PopupPoints(points)
    return math.Clamp(math.floor(points + 0.5), 0, 65535)
end

---@param ply Player
---@param id string
---@param points integer
local function defaultPopup(ply, id, points)
    net.Start("pw_score_popup")
    net.WriteString(id)
    net.WriteUInt(points, 16)
    net.Send(ply)
end

---Tells the owner of an award about it (T-6.4 popups): one message to that human only; bots have no screen.
function lib._NotifyOwner(store, ply, id, points)
    if store.popup == nil or points <= 0 or not IsValid(ply) or ply:IsBot() then return false end
    store.popup(ply, id, lib._PopupPoints(points))
    return true
end

PW._Score.popup = defaultPopup

---The team index a player scores for: the player's team in a team mode, nil in FFA or outside teams 1..N.
---@param ply Player
---@return integer?
local function scoringTeam(ply)
    local teams = PW.Teams
    if teams == nil then return nil end
    local team = ply:Team()
    if team >= 1 and team <= #teams.GetActive() then return team end
    return nil
end

---@param ply Player
---@param score integer
---@param team integer?
---@param teamScore integer?
local function publish(ply, score, team, teamScore)
    ply:SetNW2Int(lib._PlayerKey, score)
    if team ~= nil then SetGlobal2Int(lib._TeamKey .. team, teamScore or 0) end
end

---@type PW.ScoreAwardFn
function lib._Award(store, registry, ply, eventId, opts)
    local event = isstring(eventId) and registry ~= nil and registry.Get(eventId) or nil
    if event == nil or not event:IsValid() then
        store.log("score: unknown or disabled event " .. tostring(eventId))
        return false
    end
    if not IsValid(ply) then
        store.log("score: event " .. eventId .. " awarded to an invalid player")
        return false
    end
    local scoreEvent = event --[[@as PW.ScoreEvent]]
    local weapon = opts ~= nil and opts.weapon or nil
    local points, xp = lib._Resolve(scoreEvent, PW.Ask("PW_ScoreValue", ply, eventId, scoreEvent.Points))
    local team = scoringTeam(ply)
    local score, teamScore = lib._Add(store, ply, team, points)
    publish(ply, score, team, teamScore)
    lib._NotifyOwner(store, ply, eventId, points)
    PW.Notify("PW_ScoreEvent", ply, eventId, points, xp, weapon)
    PW.Notify("PW_ScoreChanged", ply, score, points, team, teamScore)
    return true, points, xp
end

---@param store PW.ScoreStore
function lib._Reset(store)
    for ply in pairs(store.players) do
        store.players[ply] = 0
        if IsValid(ply) then ply:SetNW2Int(lib._PlayerKey, 0) end
    end
    for team in pairs(store.teams) do
        store.teams[team] = 0
        SetGlobal2Int(lib._TeamKey .. team, 0)
    end
end

---@param ply Player
---@param eventId string
---@param opts? PW.ScoreOpts
---@return boolean, number?, number?
function lib.Award(ply, eventId, opts)
    local registries = PW.Registries
    return lib._Award(PW._Score, registries ~= nil and registries.score_events or nil, ply, eventId, opts)
end

---@param phase PW.PhaseName
---@param oldPhase PW.PhaseName
function MODULE:PW_PhaseChange(phase, oldPhase)
    if (phase == "LIVE" and oldPhase == "PREMATCH") or phase == "LOBBY" then lib._Reset(PW._Score) end
end
