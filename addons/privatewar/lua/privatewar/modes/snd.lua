-- Search and Destroy (02-modes.md d.8). The generic base owns the round loop; SND owns one round's facts only.
MODE.Name = "Search and Destroy"
MODE.Short = "S&D"
MODE.Description = "Plant or defuse one bomb. One life per round."
MODE.Base = "round_base"
MODE.Teams = 2
MODE.TeamPolicy = "managed"
MODE.BotQuotaPolicy = "rounds"
MODE.MapData = true
MODE.RoundsToWin = 6
MODE.SwapSidesEvery = 3

---@return PW.SNDLib
local function lib() return assert(PW.SND) end
---@return PW.RoundBase
local function base() return assert(PW.Modes.GetStored("round_base")) --[[@as PW.RoundBase]] end

---@param data any
---@return boolean, string?
function MODE:ValidateMapData(data) return lib().Validate(data) end

---@param self PW.SNDMode
---@return boolean
local function playing(self)
    return self._SND ~= nil and self._SND.phase ~= "resolved" and self._Rounds ~= nil
        and self._Rounds.phase == "round"
end

function MODE:Start()
    local lobby = assert(PW.Modules.Get("lobby"), "S&D needs the spectator policy owner")
    assert(lobby:IsValid() and assert(PW.Jip).RefreshSpectator ~= nil, "S&D needs the spectator policy owner")
    local data = assert(PW.Map).GetModeData(self.ClassName)
    local valid, reason = lib().Validate(data)
    if not valid then error(reason or "invalid S&D map") end
    lib().Activate(data --[[@as PW.SNDMapData]])
    base().Start(self)
end

---@param _round integer
---@param _swapped boolean
function MODE:PrepareRound(_round, _swapped)
    local previous = self._SND --[[@as PW.SNDState?]]
    if previous ~= nil then lib().Invalidate(previous) end
    local data = assert(assert(PW.Map).GetModeData(self.ClassName)) --[[@as PW.SNDMapData]]
    local actors = lib().Roster()
    ---@type string[]
    local attackers = {}
    for _, actor in ipairs(actors) do if actor.team == 1 then attackers[#attackers + 1] = actor.id end end
    local carrier = #attackers > 0 and attackers[math.random(#attackers)] or nil
    self._SND = lib().NewRound(data, actors, CurTime(), lib().NextGeneration(), carrier)
    lib().AdmitRoster(self._SND)
    lib().Physical(self._SND)
    lib().Publish(self._SND, true)
end

function MODE:PW_RoundStart()
    local state, rounds = self._SND, self._Rounds
    if state == nil or rounds == nil then return end
    state.deadline = rounds.roundTime > 0 and rounds.at + rounds.roundTime or math.huge
    lib().Publish(state, true)
end

---@param _timedOut boolean
---@return integer|false|nil, boolean
function MODE:RoundWinner(_timedOut)
    local state = self._SND --[[@as PW.SNDState?]]
    if state == nil then return false, false end
    local phase, carrier = state.phase, state.carrier
    local winner, defer = lib().Step(state, CurTime(), lib().Actors(state))
    local changed = phase ~= state.phase or carrier ~= state.carrier
    if changed then
        lib().Invalidate(state)
        lib().Physical(state)
    end
    lib().Publish(state, changed)
    return winner, defer
end

---@param ply Player
function MODE:PW_PlayerSpawned(ply)
    local state = self._SND --[[@as PW.SNDState?]]
    if state == nil then return end
    local admitted = lib().Admit(state, lib().Identity(ply), ply:UserID())
    ply:SetNW2Bool("pw_snd_alive", admitted)
    if admitted then ply:Freeze(false) return end
    ply:StripWeapons()
    ply:Spectate(OBS_MODE_FIXED)
end

---@param ply Player
---@return integer|false
function MODE:PW_SelectLateTeam(ply)
    local state = self._SND --[[@as PW.SNDState?]]
    local member = state ~= nil and state.roster[lib().Identity(ply)] or nil
    if member == nil or member.userId ~= ply:UserID() or not member.connected or not member.alive then return false end
    return member.team
end

function MODE:PW_CanJoinInProgress() return false end
function MODE:PW_CanRespawn() return false end

---@param ply Player
---@return PW.SpectatorPolicy?
function MODE:PW_SpectatorPolicy(ply)
    local state = self._SND --[[@as PW.SNDState?]]
    if state == nil then return nil end
    local member = state.roster[lib().Identity(ply)]
    ---@type PW.SpectatorPolicy
    local policy = { restricted = true, eligible = {} }
    if member == nil or member.userId ~= ply:UserID() or not member.connected then return policy end
    if member.alive and ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE then return nil end
    for _, target in ipairs(player.GetAll()) do
        local other = state.roster[lib().Identity(target)]
        if target ~= ply and IsValid(target) and target:Alive() and other ~= nil and other.connected and other.alive
            and other.userId == target:UserID() and other.team == member.team and target:Team() == member.team then
            policy.eligible[target:UserID()] = true
        end
    end
    return policy
end

---@param ply Player
---@return PW.SpawnPoint?
function MODE:PW_SelectSpawn(ply)
    local state = self._SND --[[@as PW.SNDState?]]
    if state == nil then return nil end
    local spawns = assert(PW.Spawns)
    local point = assert(spawns.Pick)(ply, { first = true, all = false, spawns = state.map.spawns })
    if point == nil then error("S&D authored side has no hull-clear spawn") end
    return point
end

---@param victim? Player
---@param attacker? Entity
---@return boolean?
function MODE:PW_CanTakeDamage(victim, attacker)
    if not playing(self --[[@as PW.SNDMode]]) then return false end
    local state = self._SND --[[@as PW.SNDState]]
    if victim ~= nil then
        local member = state.roster[lib().Identity(victim)]
        if member == nil or not member.alive or member.userId ~= victim:UserID() then return false end
    end
    if attacker ~= nil and IsValid(attacker) and attacker:IsPlayer() then
        local shooter = attacker --[[@as Player]]
        local member = state.roster[lib().Identity(shooter)]
        if member == nil or not member.alive or member.userId ~= shooter:UserID() then return false end
    end
end

function MODE:PW_CanRunBotBehavior() return playing(self --[[@as PW.SNDMode]]) end

function MODE:PW_CanUseLoadoutKind()
    local rounds = self._Rounds --[[@as PW.RoundState?]]
    return rounds ~= nil and (rounds.phase == "starting" or rounds.phase == "round")
end

---@param victim Player
---@param attacker Entity
---@param dmg CTakeDamageInfo
function MODE:PW_PlayerKilled(victim, attacker, dmg)
    local state = self._SND --[[@as PW.SNDState?]]
    if state == nil then return end
    lib().Invalidate(state)
    local now = CurTime()
    local open = playing(self --[[@as PW.SNDMode]])
        and now < (state.phase == "planted" and state.fuse or state.deadline)
    local member = state.roster[lib().Identity(victim)]
    if open and member ~= nil and member.alive and member.userId == victim:UserID() then
        assert(PW.MatchRules).ScoreKill(victim, attacker, dmg)
    end
    lib().Death(state, lib().Identity(victim), victim:UserID(), lib().DropPoint(state, victim), now)
    victim:SetNW2Bool("pw_snd_alive", false)
    lib().Physical(state)
end

function MODE:PW_RoundEnd()
    local state = self._SND --[[@as PW.SNDState?]]
    if state ~= nil then lib().Invalidate(state) lib().Publish(state, true) end
    for _, ply in ipairs(player.GetAll()) do
        ply:Freeze(true)
        if PW.Equipment ~= nil and PW.Equipment.Revoke ~= nil then PW.Equipment.Revoke(ply) end
        if PW.Streaks ~= nil and PW.Streaks.EndEffects ~= nil then PW.Streaks.EndEffects(ply) end
    end
end

---@param team integer
---@return PW.BotObjective[]
function MODE:BotObjectives(team)
    local state = self._SND --[[@as PW.SNDState?]]
    return state ~= nil and lib().Objectives(state, team) or {}
end

function MODE:Cleanup()
    local state = self._SND --[[@as PW.SNDState?]]
    if state ~= nil then lib().Invalidate(state) end
    self._SND = nil
    for _, ply in ipairs(player.GetAll()) do ply:Freeze(false) ply:SetNW2Bool("pw_snd_alive", false) end
    lib().Clear()
    base().Cleanup(self)
end
