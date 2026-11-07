-- Medals, server glue (T-4.11). Feeds the pure detectors (shared.lua) from PW_PlayerKilled (fired by match_rules
-- during LIVE only) and PostEntityTakeDamage, and resets everything when the match goes LIVE and when the lobby
-- returns. The counts stay readable in POSTMATCH (T-4.10 reads PW.Medals.Get for the summary).

local lib = PW.Medals --[[@as PW.MedalsLib]]

util.AddNetworkString("pw_medal")

---@param ply Player
---@param id string
local function defaultSend(ply, id)
    net.Start("pw_medal")
    net.WriteString(id)
    net.Send(ply)
end

---@param a Player
---@param b Player
---@return boolean
local function defaultIsAlly(a, b)
    return a ~= b and not PW.IsEnemy(a, b)
end

---@param ply Player
---@param id string
---@return boolean
local function defaultAward(ply, id)
    local ok = PW.Score.Award(ply, id)
    return ok
end

do -- a reload keeps the match state, the functions are new
    local previous = rawget(PW, "_Medals") --[[@as PW.MedalsStore?]]
    local store = lib._NewStore({
        isAlly = defaultIsAlly,
        award = defaultAward,
        notify = function(name, ply, id) PW.Notify(name, ply, id) end,
        send = defaultSend
    })
    if previous ~= nil then store.state, store.counts = previous.state, previous.counts end
    PW._Medals = store
end

---@param ent any
---@return boolean
local function isPlayer(ent)
    return IsValid(ent) and ent:IsPlayer()
end

---@return boolean
local function live()
    local match = PW.Match
    return match ~= nil and match.GetPhase() == "LIVE"
end

---@param phase PW.PhaseName
---@param oldPhase PW.PhaseName
function MODULE:PW_PhaseChange(phase, oldPhase)
    if (phase == "LIVE" and oldPhase == "PREMATCH") or phase == "LOBBY" then lib._ResetStore(PW._Medals) end
end

---@param victim Player
---@param attacker Entity
function MODULE:PW_PlayerKilled(victim, attacker)
    if not isPlayer(victim) then return end
    local killer = isPlayer(attacker) and attacker --[[@as Player]] or nil
    local enemy = killer ~= nil and killer ~= victim and PW.IsEnemy(killer, victim)
    lib._Kill(PW._Medals, { time = CurTime(), attacker = killer, victim = victim, enemy = enemy })
end

PW.HookFor(MODULE, "PostEntityTakeDamage", function(_, victimArg, dmgArg, took)
    if not took or not live() then return end
    local victim = victimArg --[[@as Entity]]
    local attacker = (dmgArg --[[@as CTakeDamageInfo]]):GetAttacker()
    if not isPlayer(victim) or not isPlayer(attacker) or attacker == victim then return end
    if not PW.IsEnemy(attacker --[[@as Player]], victim --[[@as Player]]) then return end
    lib._OnDamage(PW._Medals.state, { attacker = attacker, victim = victim, time = CurTime() })
end)
