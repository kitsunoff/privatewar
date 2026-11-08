-- Addon-owned match roster and role application. Never reads a foreign private store.
local lib = PW.Infection --[[@as PW.InfectionLib]]
local rules = PW.InfectionRules --[[@as PW.InfectionRulesLib]]
local zombie = "models/player/zombie_classic.mdl"

---@param ply Player
---@param names string[]
---@return boolean
local function hasSequence(ply, names)
    for _, name in ipairs(names) do
        if ply:LookupSequence(name) >= 0 then return true end
    end
    return false
end

local idleSequences = { "idle_all_01", "idle_all", "idle" }
local moveSequences = { "walk_all", "walk_all_01", "walk", "run_all", "run_all_01", "run" }

---@param s PW.InfectionState
local function restoreOperators(s)
    for _, actor in pairs(s.actors) do
        if IsValid(actor) and lib.Role(actor) == "infected" then assert(PW.Operators).Refresh(actor) end
    end
end

---@param ply Player
local function restorePlayer(ply)
    if not IsValid(ply) then return end
    if PW.PlayerOverrides ~= nil then PW.PlayerOverrides.Release(ply) end
    if PW.Operators ~= nil and PW.Operators.Refresh ~= nil then PW.Operators.Refresh(ply) end
end

function lib.Identity(ply)
    return ply:IsBot() and ("bot:" .. ply:UserID()) or ("human:" .. ply:SteamID64())
end

function lib.Active()
    local state = lib.State
    return state ~= nil and PW.ActiveMode == state.mode and PW.Match ~= nil and PW.Match.GetPhase() == "LIVE"
end

function lib.Role(ply)
    local s = lib.State
    if s == nil or s.current == nil then return nil end
    local id = s.identities[ply]
    local row = id ~= nil and s.actors[id] == ply and s.current.players[id] or nil
    return row ~= nil and row.present and row.role or nil
end

---@param ply Player
local function revoke(ply)
    if PW.Perks ~= nil and PW.Perks.Revoke ~= nil then PW.Perks.Revoke(ply) end
    if PW.Equipment ~= nil and PW.Equipment.Revoke ~= nil then PW.Equipment.Revoke(ply) end
    if PW.Streaks ~= nil and PW.Streaks.Revoke ~= nil then PW.Streaks.Revoke(ply) end
end

function lib.Start(mode)
    for _, id in ipairs({ "pw_infection_rules", "teams", "loadout", "operators", "player_overrides",
        "match_rules", "lobby" }) do
        local owner = PW.Modules.Get(id)
        if owner == nil or not owner:IsValid() then
            assert(PW.Match).Abort("Infection requires the enabled " .. id .. " module")
            return false
        end
    end
    if weapons.GetStored("weapon_fists") == nil then
        assert(PW.Match).Abort("Infection requires Garry's Mod's built-in weapon_fists")
        return false
    end
    lib.State = { mode = mode, completed = {}, actors = {}, identities = setmetatable({}, { __mode = "k" }),
        lives = setmetatable({}, { __mode = "k" }), history = {}, userIds = {}, metadata = {}, deathBaselines = {},
        infections = {}, round = 0,
        playing = false, credited = false, zombie = true }
    SetGlobal2Bool("pw_infection_results", false)
    lib.ResetResults()
    return true
end

function lib.Prepare(round)
    local s = assert(lib.State)
    s.playing = false
    ---@type table<string, Player>
    local actors = {}
    ---@type PW.InfectionParticipant[]
    local roster = {}
    local list = player.GetAll()
    table.sort(list, function(a, b) return a:UserID() < b:UserID() end)
    for _, ply in ipairs(list) do
        local manager = PW.BotsManager
        local leaving = manager ~= nil and manager.IsLeaving ~= nil and manager.IsLeaving(ply)
        if IsValid(ply) and not leaving then
            local id = lib.Identity(ply)
            actors[id], s.history[id], s.identities[ply] = ply, ply, id
            s.userIds[id] = ply:UserID()
            lib.CaptureResultMetadata(ply)
            roster[#roster + 1] = { id = id, bot = ply:IsBot(), life = (s.lives[ply] or 0) + 1 }
        end
    end
    local seed = rules.PickSeed(roster, s.previous, math.random)
    local current, reason = rules.NewRound(roster, seed or "", CurTime() + 120)
    if current == nil then assert(PW.Match).Abort(reason or "Infection cannot prepare a round") return end
    s.current, s.actors, s.previous, s.round, s.credited = current, actors, seed, round, false
    for id, ply in pairs(actors) do
        assert(PW.PlayerOverrides).Release(ply)
        assert(PW.Jip).Admit(ply)
        local desired = current.players[id].role == "infected" and 2 or 1
        local team = ply:Team()
        if team < 1 or team > 2 then
            assert(PW.Teams).PlaceLate(ply)
        else
            local ok, note = assert(PW.Teams).Transition(ply, desired, "round_prepare")
            if not ok then error("Infection role preparation failed: " .. tostring(note)) end
        end
        if ply:Team() ~= desired then error("Infection role placement was refused") end
        if desired == 2 then revoke(ply) end
    end
end

function lib.ValidateModel(ply)
    local s = assert(lib.State)
    if s.zombie and ply:GetModel() == zombie
        and (not hasSequence(ply, idleSequences) or not hasSequence(ply, moveSequences)) then
        s.zombie = false
        print("[PW] infection: zombie player animations unavailable; using ordinary operators")
        restoreOperators(s)
    end
end

function lib.Spawned(ply)
    local s = lib.State
    if s == nil or s.current == nil or lib.Role(ply) == nil then return end
    s.lives[ply] = (s.lives[ply] or 0) + 1
    local entry = s.current.players[assert(s.identities[ply])]
    entry.life, entry.alive, entry.deadLife = s.lives[ply], true, nil
    if entry.role == "infected" then
        revoke(ply)
        -- Validate installed PLAYER animations after the sole operators owner applied the model.
        lib.ValidateModel(ply)
    end
    lib.Publish()
end

function lib.Death(victim, _)
    local s = lib.State
    if s == nil or s.current == nil or not s.playing or lib.Role(victim) == nil then return end
    local id = assert(s.identities[victim])
    if rules.Death(s.current, id, s.lives[victim] or s.current.players[id].life, CurTime()) then
        local ok, note = assert(PW.Teams).Transition(victim, 2, "role_change")
        if not ok then error("Infection conversion failed: " .. tostring(note)) end
        revoke(victim)
        assert(PW.PlayerOverrides).Refresh(victim)
        assert(PW.Operators).Refresh(victim)
    end
    if s.current.winner ~= nil then s.playing = false end
    lib.Publish()
end

function lib.Disconnect(ply)
    local s = lib.State
    if s == nil or s.current == nil then return end
    local id = s.identities[ply]
    if id == nil or s.actors[id] ~= ply then return end
    lib.CaptureResultMetadata(ply)
    rules.Disconnect(s.current, id, CurTime())
    if s.current.winner ~= nil then s.playing = false end
    lib.Publish()
end

function lib.EndRound()
    local s = lib.State
    if s == nil or s.current == nil or s.credited then return end
    s.playing, s.credited = false, true
    s.completed[#s.completed + 1] = s.current
    for _, ply in pairs(s.actors) do
        if IsValid(ply) then
            if PW.Equipment ~= nil and PW.Equipment.Revoke ~= nil then PW.Equipment.Revoke(ply) end
            if PW.Streaks ~= nil and PW.Streaks.EndEffects ~= nil then PW.Streaks.EndEffects(ply) end
        end
    end
    lib.Publish()
end

function lib.Result()
    local s = assert(lib.State)
    local summary = rules.Summary(s.completed)
    lib.PublishResults(summary)
    ---@type PW.Standing[]
    local standings = {}
    for _, row in ipairs(summary.standings) do
        local actor = s.history[row.id]
        standings[#standings + 1] = { id = IsValid(actor) and actor or s.userIds[row.id], score = row.score }
    end
    ---@type Player|integer|nil
    local winner
    if summary.winner ~= nil then
        ---@type Player?
        local actor = s.history[summary.winner]
        winner = IsValid(actor) and actor or s.userIds[summary.winner]
    end
    SetGlobal2Bool("pw_infection_results", true)
    return { reason = summary.reason, teams = false, draw = summary.draw, winner = winner, standings = standings }
end

function lib.Clear()
    local s = lib.State
    lib.State = nil -- remove every provider before asking the owning modules to restore ordinary state
    if s ~= nil then
        for _, ply in pairs(s.history) do
            if IsValid(ply) then
                revoke(ply)
                restorePlayer(ply)
            end
        end
    end
    lib.Publish()
end
