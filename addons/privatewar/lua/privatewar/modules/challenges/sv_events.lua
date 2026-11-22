-- Only authoritative hooks enter this normalizer; addon event reporting is a separate seam.
local lib = assert(PW.Challenges)
local module = MODULE

---@class PW.ChallengeBefore
---@field progress PW.ChallengeProgress
---@field saved integer[]

---@param server PW.ChallengeServer
---@param connection PW.ChallengeConnection
---@param before table<string, PW.ChallengeBefore>
---@param id string
local function remember(server, connection, before, id)
    if before[id] ~= nil then return end
    local view = lib._ReadProgress(server.plan, connection.progress, id)
    if view == nil then return end
    ---@type integer[]
    local saved = {}
    for slot, counter in ipairs(connection.progress.items[id].counters) do saved[slot] = math.floor(counter.best) end
    before[id] = { progress = view, saved = saved }
end

---@param server PW.ChallengeServer
---@param ply Player
---@param connection PW.ChallengeConnection
---@param before table<string, PW.ChallengeBefore>
local function markDifferences(server, ply, connection, before)
    for id, old in pairs(before) do
        local view = lib._ReadProgress(server.plan, connection.progress, id)
        if view == nil then continue end
        for slot, value in ipairs(view.values) do
            if value ~= old.progress.values[slot] then
                connection.dirty[id] = true
                PW.Notify("PW_ChallengeProgress", ply, id, slot, value, view.targets[slot])
            end
            local best = connection.progress.items[id].counters[slot].best
            if math.floor(best) ~= old.saved[slot] then connection.persist = true end
        end
        if view.done ~= old.progress.done then connection.dirty[id], connection.persist = true, true end
    end
end

function lib._ChallengeBoundary(server, ply, boundary)
    local connection = server.players[ply]
    if connection == nil then return end
    ---@type table<string, PW.ChallengeBefore>
    local before = {}
    for id in pairs(server.plan.entries) do remember(server, connection, before, id) end
    lib._ResetProgress(server.plan, connection.progress, boundary)
    markDifferences(server, ply, connection, before)
end

function lib._ChallengeEvent(server, ply, kind, facts)
    local match = server.match
    if match == nil or server.deps.phase() ~= "LIVE" or not lib._ChallengeHuman(server, ply) then return end
    local routes = server.plan.byType[kind]
    local connection = lib._ChallengeConnection(server, ply)
    local now = server.deps.clock()
    if connection.presentAt == nil and lib._ChallengeParticipant(server, ply) then connection.presentAt = now end
    if routes == nil then return end
    ---@type PW.ChallengeEvent
    local ev = { type = kind, player = ply, value = 1, mode = match.mode, modeBase = match.modeBase,
        playlist = match.playlist, match = server.serial, week = server.week.index, time = now }
    for key, value in pairs(facts or {}) do rawset(ev, key, value) end

    ---@type table<string, PW.ChallengeBefore>
    local before = {}
    for _, objective in ipairs(routes.increments) do remember(server, connection, before, objective.id) end
    for _, rule in ipairs(routes.resets) do remember(server, connection, before, rule.objective.id) end
    local result = lib._AdvanceProgress(server.plan, connection.progress, ev)
    markDifferences(server, ply, connection, before)
    for _, id in ipairs(result.completed) do PW.Notify("PW_ChallengeCompleted", ply, id, server.week.label) end
    if result.bonus then
        connection.persist = true
        PW.Notify("PW_ChallengeBonus", ply, server.week.label)
    end
    if #result.completed > 0 or result.bonus then
        lib._FlushChallengeProgress(server, ply, true)
        lib._FlushChallengeDelta(server, ply)
    end
end

local objectives = { dom_capture = "capture", kc_confirm = "confirm", kc_deny = "deny",
    snd_plant = "plant", snd_defuse = "defuse" }
local killFields = { "victim", "victimBot", "headshot", "distance", "ads", "crouch", "airborne", "explosive",
    "streakKill", "streak" }

---@param server PW.ChallengeServer
---@param class string
---@return { category: string?, kind: PW.WeaponKind? }
local function weaponFacts(server, class)
    local cached = server.weaponFacts[class]
    if cached == nil then
        local entry = PW.Weapons ~= nil and PW.Weapons.Get(class) or nil
        local weapon = entry --[[@as PW.Weapon?]]
        cached = { category = weapon ~= nil and weapon.Category or nil, kind = weapon ~= nil and weapon.Kind or nil }
        server.weaponFacts[class] = cached
    end
    return cached
end

---@param server PW.ChallengeServer
---@param ply Player
---@param weapon Weapon?
---@param ctx table<string, any>?
local function scoreKill(server, ply, weapon, ctx)
    local connection = lib._ChallengeConnection(server, ply)
    connection.lifeKills = connection.lifeKills + 1
    ---@type PW.ChallengeEventFacts
    local facts = {}
    if weapon ~= nil and IsValid(weapon) then
        local class = weapon:GetClass()
        local meta = weaponFacts(server, class)
        facts.weapon, facts.weaponCategory, facts.weaponKind = class, meta.category, meta.kind
        facts.attachments = connection.attachments[class]
    end
    if ctx ~= nil then
        for _, key in ipairs(killFields) do facts[key] = ctx[key] end
        facts.lifeKills = connection.lifeKills
        if connection.spawnedAt ~= nil then facts.aliveTime = server.deps.clock() - connection.spawnedAt end
    end
    lib._ChallengeEvent(server, ply, "kill", facts)
end

---@param ply Player
---@param id string
---@param points number
---@param _xp number
---@param weapon Weapon?
---@param ctx table<string, any>?
function module:PW_ScoreEvent(ply, id, points, _xp, weapon, ctx)
    local server = PW._ChallengeServer
    if server == nil or server.match == nil or server.deps.phase() ~= "LIVE"
        or not lib._ChallengeHuman(server, ply) then return end
    if id == "kill" then scoreKill(server, ply, weapon, ctx) end
    lib._ChallengeEvent(server, ply, "score", { scoreEvent = id, value = points })
    local objective = objectives[id]
    if objective ~= nil then lib._ChallengeEvent(server, ply, "objective", { objective = objective }) end
    local medals = PW.Medals
    if medals ~= nil and table.HasValue(medals.Ids, id) then
        lib._ChallengeEvent(server, ply, "medal", { medal = id })
    end
end

---@param server PW.ChallengeServer
---@param ply Player
---@param id any
---@param teams boolean
---@return boolean
local function standingId(server, ply, id, teams)
    if teams then return type(id) == "number" and id == ply:Team() end
    if type(id) == "number" then return id == ply:UserID() end
    return server.deps.isPlayer(id) and id == ply
end

---Core passes through mode-defined results. Missing facts stay absent rather than
---matching loss, non-draw or placement filters. A result still marks a played match.
---@param server PW.ChallengeServer
---@param ply Player
---@param result any
---@return PW.ChallengeEventFacts
local function matchFacts(server, ply, result)
    if type(result) ~= "table" then return {} end
    ---@cast result table<string, any>
    ---@type PW.ChallengeEventFacts
    local facts = {}
    if type(result.draw) == "boolean" then facts.draw = result.draw end
    if facts.draw == true then facts.won = false end
    local teams = result.teams
    if type(teams) ~= "boolean" then return facts end
    local winner = result.winner
    if facts.won == nil and (type(winner) == "number" or (not teams and server.deps.isPlayer(winner))) then
        facts.won = standingId(server, ply, winner, teams)
    end
    local standings = result.standings
    if type(standings) == "table" then
        for i, row in ipairs(standings --[[@as any[] ]]) do
            if type(row) == "table" and standingId(server, ply, rawget(row, "id"), teams) then
                facts.placement = i
                break
            end
        end
    end
    return facts
end

---@param server PW.ChallengeServer
---@param ply Player
---@param connection PW.ChallengeConnection
---@param result any
local function finishPlayer(server, ply, connection, result)
    local presentAt = connection.presentAt
    if presentAt == nil then return end
    if result ~= nil then lib._ChallengeEvent(server, ply, "match_end", matchFacts(server, ply, result)) end
    lib._ChallengeEvent(server, ply, "time_played", { value = math.max(0, server.deps.clock() - presentAt) })
    lib._ChallengeBoundary(server, ply, "match_end")
    connection.presentAt = nil
end

---@param result? any
function module:PW_MatchEnd(result)
    local server = PW._ChallengeServer
    if server == nil or server.match == nil then return end
    for ply, connection in pairs(server.players) do
        if lib._ChallengeHuman(server, ply) then finishPlayer(server, ply, connection, result) end
    end
    server.match, server.roundOpen = nil, false
end

function module:PW_RoundStart()
    local server = PW._ChallengeServer
    if server == nil or server.deps.phase() ~= "LIVE" then return end
    server.roundOpen = true
    if server.match == nil then return end
    for ply in pairs(server.players) do lib._ChallengeBoundary(server, ply, "round_start") end
end

---@param _round integer
---@param winner integer|false?
function module:PW_RoundEnd(_round, winner)
    local server = PW._ChallengeServer
    if server == nil or server.match == nil then return end
    for ply, connection in pairs(server.players) do
        if connection.presentAt ~= nil and lib._ChallengeHuman(server, ply) then
            lib._ChallengeEvent(server, ply, "round_end", { won = winner == ply:Team(), draw = not winner })
            lib._ChallengeBoundary(server, ply, "round_end")
        end
    end
    server.roundOpen = false
end

---@param server PW.ChallengeServer
---@param ply Player
---@param boundary PW.ChallengeProgressBoundary
local function resetLife(server, ply, boundary)
    local connection = lib._ChallengeConnection(server, ply)
    connection.lifeKills, connection.spawnedAt = 0, nil
    lib._ChallengeBoundary(server, ply, boundary)
end

---@param ply Player
function module:PW_PlayerSpawned(ply)
    local server = PW._ChallengeServer
    if server == nil or not lib._ChallengeParticipant(server, ply) then return end
    resetLife(server, ply, "spawn")
    local connection = lib._ChallengeConnection(server, ply)
    local now = server.deps.clock()
    connection.spawnedAt = now
    if server.match ~= nil and connection.presentAt == nil then connection.presentAt = now end
end

---@param ply Player
function module:PW_PlayerTeamChanged(ply)
    local server = PW._ChallengeServer
    if server ~= nil and lib._ChallengeHuman(server, ply) then resetLife(server, ply, "team_change") end
end

---@param victim Player
---@param attacker Entity
function module:PW_PlayerKilled(victim, attacker)
    local server = PW._ChallengeServer
    if server == nil or server.match == nil or not lib._ChallengeHuman(server, victim) then return end
    resetLife(server, victim, "death")
    lib._ChallengeEvent(server, victim, "death", { suicide = victim == attacker })
end

---@param loadout PW.Loadout
---@return table<string, table<string, boolean>>
local function attachments(loadout)
    ---@type table<string, table<string, boolean>>
    local result = {}
    local builds = loadout.builds --[[@as table<string, PW.Build>?]]
    for slot, build in pairs(builds or {}) do
        local weapon = loadout[slot]
        if type(weapon) ~= "string" then continue end
        ---@type table<string, boolean>
        local options = {}
        for _, option in pairs(build) do if type(option) == "string" then options[option] = true end end
        result[weapon] = options
    end
    return result
end

---@param ply Player
---@param loadout PW.Loadout
function module:PW_LoadoutGiven(ply, loadout)
    local server = PW._ChallengeServer
    if server ~= nil and lib._ChallengeHuman(server, ply) then
        lib._ChallengeConnection(server, ply).attachments = attachments(loadout)
    end
end

---@param ply Player
---@param id string
function module:PW_StreakEarned(ply, id)
    local server = PW._ChallengeServer
    if server ~= nil then lib._ChallengeEvent(server, ply, "streak_earned", { streak = id }) end
end

---@param ply Player
---@param id string
function module:PW_StreakActivated(ply, id)
    local server = PW._ChallengeServer
    if server ~= nil then lib._ChallengeEvent(server, ply, "streak_used", { streak = id }) end
end

PW.HookFor(module, "PlayerDisconnected", function(_, ply)
    local server = PW._ChallengeServer
    local connection = server ~= nil and server.players[ply] or nil
    if server == nil or connection == nil then return end
    if connection.presentAt ~= nil and lib._ChallengeHuman(server, ply) then
        finishPlayer(server, ply, connection, nil)
    end
    lib._FlushChallengeProgress(server, ply, true)
    lib._FlushChallengeDelta(server, ply)
    server.players[ply] = nil
end)
