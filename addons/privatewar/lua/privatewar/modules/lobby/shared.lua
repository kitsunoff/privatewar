-- Lobby rules, join in progress (T-8.4; 08-lobby.md d.4). The module is named `lobby` so that its setting has the id
-- the design gives it, lobby.joininprogress (the lobby screens are the module lobby_ui). Shared and pure: the
-- decision for one join. The server glue is init.lua.
--
-- Setting lobby.joininprogress (scope server, bool, default on): a human joining during LIVE plays (the teams module
-- places the player in the smaller team, the bots manager kicks a bot) or, when off, spectates until the next match.
-- The spectating state is the NW2 bool PW.Jip.NetBool of the player; the HUD element `spectating` shows the notice.
-- The module also unspawns every player when a match returns to the lobby (_Unspawns, init.lua _OnLobby).

MODULE.Name = "Lobby"

MODULE.Settings = {
    joininprogress = { scope = "server", type = "bool", default = true, label = "Join in progress" }
}

local lib = (rawget(PW, "Jip") or {}) --[[@as PW.JipLib]]
PW.Jip = lib

lib.NetBool = "pw_spectating"
lib.Notice = "Spectating \226\128\148 you join next match"

---@type table<PW.PhaseName, true>
local releasing = { LOBBY = true, PREMATCH = true }

function lib._Decide(facts)
    if facts.phase ~= "LIVE" then return "normal" end
    if facts.human and not facts.enabled then return "spectate" end
    return "play"
end

function lib._ReleasesOn(phase)
    return releasing[phase] == true
end

-- Post-match lobby (08-lobby.md d.3: players are not spawned during LOBBY). The first lobby gets this from the base
-- gamemode: a player without a team spawns as a spectator. Coming back from a match, every player (bots included)
-- is put back into that state: no team, spawned again, so the base gamemode makes a spectator without a model or
-- weapons.
function lib._Unspawns(phase, oldPhase)
    return phase == "LOBBY" and oldPhase ~= nil and oldPhase ~= "LOBBY"
end
