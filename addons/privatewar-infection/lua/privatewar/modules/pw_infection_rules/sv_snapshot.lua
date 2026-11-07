-- Only public round counts, own role/wins and informational conversion count. No positions or roster secrets.
local lib = PW.Infection --[[@as PW.InfectionLib]]
local presentation = PW.InfectionPresentation --[[@as PW.InfectionPresentationLib]]
local writer = { uint = net.WriteUInt, bool = net.WriteBool, float = net.WriteFloat }
util.AddNetworkString("pw_infection_state")

function lib.Snapshot(ply)
    local s = lib.State
    if s == nil or s.current == nil then return nil end
    local survivors, infected = 0, 0
    for _, entry in pairs(s.current.players) do
        if entry.present then
            if entry.role == "survivor" then survivors = survivors + 1 else infected = infected + 1 end
        end
    end
    local id, wins = lib.Identity(ply), 0 -- reading own history does not admit a reconnect to the current roster
    for _, round in ipairs(s.completed) do
        local entry = round.players[id]
        if entry ~= nil and entry.won then wins = wins + 1 end
    end
    return { revision = lib.Revision, active = true, round = s.round, survivors = survivors, infected = infected,
        deadline = s.current.deadline, role = lib.Role(ply) or "waiting", personalWins = wins,
        intermission = not s.playing, infections = math.min(s.infections[id] or 0, 65535) }
end

function lib.Publish()
    lib.Revision = lib.Revision + 1
    local s = lib.State
    if s ~= nil then
        for _, ply in pairs(s.history) do
            if IsValid(ply) then
                local snapshot = lib.Snapshot(ply)
                ply:SetNW2Int("pw_infection_wins", snapshot ~= nil and snapshot.personalWins or 0)
                ply:SetNW2Int("pw_infection_count", snapshot ~= nil and (snapshot.infections or 0) or 0)
            end
        end
    end
    for _, ply in ipairs(player.GetHumans()) do
        local snapshot = lib.Snapshot(ply)
        net.Start("pw_infection_state")
        assert(presentation.Encode(writer, snapshot or { revision = lib.Revision, active = false }))
        net.Send(ply)
    end
end
