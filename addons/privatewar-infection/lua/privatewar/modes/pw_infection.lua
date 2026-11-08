-- Separate optional mode. Inherits the only round loop; owns only its roles and result transform.
MODE.Name = "Infection"
MODE.Short = "INF"
MODE.Description = "Survive the infected. Personal round wins decide the match."
MODE.Base = "round_base"
MODE.Teams = 2
MODE.TeamPolicy = "managed"
MODE.BotQuotaPolicy = "rounds"
MODE.SwapSidesEvery = 0
MODE.Settings = {
    rounds = { type = "int", default = 3, min = 1, max = 20, label = "Total rounds" },
    roundtime = { type = "int", default = 120, min = 120, max = 120, label = "Round time (s)" }
}

local lib = PW.Infection --[[@as PW.InfectionLib]]
local rules = PW.InfectionRules --[[@as PW.InfectionRulesLib]]
local allowed = { pw_infection_pursuit = true, hunt = true, search = true, retaliate = true, idle = true }

function MODE:Start()
    if lib == nil or lib.Start == nil then
        assert(PW.Match).Abort("Infection requires its installed rules module")
        return
    end
    if not lib.Start(self --[[@as PW.RoundBase]]) then return end
    self.RoundLimit = tonumber(self:Setting("rounds")) or 3
    assert(self.BaseClass).Start(self)
end

function MODE:PrepareRound(round)
    lib.Prepare(round)
end

function MODE:Think()
    if lib.State == nil then
        assert(PW.Match).Abort("Infection rules became unavailable")
        return
    end
    assert(self.BaseClass).Think(self)
end

function MODE:PW_RoundStart()
    local s = lib.State
    if s == nil or s.current == nil then return end
    s.playing, s.current.deadline = true, CurTime() + 120
    lib.Publish()
end

function MODE:RoundWinner()
    local s = lib.State
    if s == nil or s.current == nil then return nil end
    local winner = rules.Winner(s.current, CurTime())
    if winner ~= nil then s.playing = false end
    return winner ~= nil and (winner == "survivor" and 1 or 2) or nil
end

function MODE:PW_RoundEnd() lib.EndRound() end
function MODE:FinalizeRounds() return lib.Result() end
function MODE:PW_PlayerSpawned(ply) lib.Spawned(ply) end
function MODE:PW_PlayerKilled(victim, attacker) lib.Death(victim, attacker) end
function MODE:PW_RespawnDelay() return 3 end
function MODE:PW_CanJoinInProgress() return false end
function MODE:PW_ScoreValue() return 0 end -- built-in events derive XP/currency from the resolved points

function MODE:PW_CanTakeDamage(victim, attacker, damage)
    return lib.Damage(victim, attacker, damage)
end

---@param phase PW.PhaseName
function MODE:PW_PhaseChange(phase)
    -- The old active mode hears leaving POSTMATCH too, even if its module was disabled for the next match.
    if SERVER and (phase == "LOBBY" or phase == "PREMATCH") then SetGlobal2Bool("pw_infection_results", false) end
end

function MODE:PW_CanRespawn(ply)
    local s = lib.State
    return s ~= nil and s.playing and lib.Role(ply) == "infected"
end

function MODE:PW_SelectLateTeam(ply)
    local role = lib.Role(ply)
    return role ~= nil and (role == "infected" and 2 or 1) or false
end

function MODE:PW_IsEnemy(a, b)
    if a == b or not IsValid(a) or not IsValid(b) or not a:IsPlayer() or not b:IsPlayer() then return false end
    local mine, theirs = lib.Role(a), lib.Role(b)
    return mine ~= nil and theirs ~= nil and mine ~= theirs
end

function MODE:PW_CanChangeTeam(ply, _, to)
    local role = lib.Role(ply)
    return role ~= nil and to == (role == "infected" and 2 or 1)
end

function MODE:PW_PlayerLoadout(ply)
    if lib.Role(ply) == "infected" then return { melee = "weapon_fists" } end
    if lib.Role(ply) == nil then return {} end
end

function MODE:PW_PlayerOverrides(ply)
    if lib.Role(ply) == "infected" then
        return { maxHealth = 400, spawnHealth = 400, walkSpeedMult = 1.15, runSpeedMult = 1.15 }
    end
end

function MODE:PW_PlayerModelOverride(ply)
    if lib.State ~= nil and lib.State.zombie and lib.Role(ply) == "infected" then
        return "models/player/zombie_classic.mdl"
    end
end

function MODE:PW_CanUseLoadoutKind(ply)
    if lib.Role(ply) ~= "survivor" then return false end
end

function MODE:PW_CanRunBotBehavior(ply, id)
    if lib.State == nil or not lib.State.playing or lib.Role(ply) == nil then return false end
    if lib.Role(ply) == "infected" then return allowed[id] == true end
    if id == "pw_infection_pursuit" or id == "melee" or id == "fight" or id == "retaliate"
        or id == "take_cover" or id == "reload_cover" then return false end
end

function MODE:PW_CanRunBotInput(ply)
    return lib.State ~= nil and lib.State.playing and lib.Role(ply) ~= nil
end

function MODE:Cleanup()
    if lib ~= nil and lib.Clear ~= nil then lib.Clear() end
    assert(self.BaseClass).Cleanup(self)
end
