-- Match rules module, server glue (T-2.2). Thin wrappers around the pure rules in shared.lua. Only during LIVE:
--   DoPlayerDeath -> the notification PW_PlayerKilled(victim, attacker, dmg); the mode scores there (ScoreKill).
--   PlayerDeathThink -> a dead player respawns once the delay PW_RespawnDelay(ply) (asked on the first dead tick)
--     has passed and PW_CanRespawn(ply) is not false; the base think (respawn on a key press) is blocked.
--   Tick -> the same death think for every dead bot: the engine runs no PlayerDeathThink for a dead player bot.
--   PlayerSelectSpawn -> the question PW_SelectSpawn(ply): an entity is used as the spawn point, a { pos, yaw }
--     table is applied when the player spawns, nil keeps the base gamemode's choice.
--   PlayerSpawn -> FFA players join lib.FreeTeam before GM:PlayerSpawn, which would make them spectators.
--   PW_MatchStart -> every player spawns for the match (FFA players in the free team first).
-- Kill counts are reset when PREMATCH turns into LIVE and when the lobby returns, like the score module's.

local lib = PW.MatchRules --[[@as PW.MatchRulesLib]]

---@param mode table?
---@return integer
local function teamCount(mode)
    if mode == nil then return 0 end
    local count = (mode --[[@as table<string, any>]]).Teams --[[@as any]]
    if not isnumber(count) or count < 0 then return 0 end
    return math.floor(count --[[@as number]])
end

---@return boolean
local function live()
    local match = PW.Match
    return match ~= nil and match.GetPhase() == "LIVE"
end

---Every player in join order (UserID), so standings with equal scores are deterministic.
---@return Player[]
local function sortedPlayers()
    local list = player.GetAll()
    table.sort(list, function(a, b) return a:UserID() < b:UserID() end)
    return list
end

---@param attacker Player
---@param victim Player
---@return boolean
local function isEnemy(attacker, victim)
    local check = PW.IsEnemy
    if check ~= nil then return check(attacker, victim) end
    return attacker ~= victim
end

---@param attacker Player
---@param dmg CTakeDamageInfo
---@return Weapon?
local function weaponOf(attacker, dmg)
    local inflictor = dmg:GetInflictor()
    if IsValid(inflictor) and inflictor:IsWeapon() then return inflictor --[[@as Weapon]] end
    local active = attacker:GetActiveWeapon()
    if IsValid(active) then return active end
    return nil
end

---@param store PW.MatchRulesStore
local function reset(store)
    for ply in pairs(store.kills) do
        if IsValid(ply) then (ply --[[@as Player]]):SetNW2Int(lib._KillsKey, 0) end
    end
    for index in pairs(store.teamKills) do SetGlobal2Int(lib._TeamKillsKey .. index, 0) end
    store.kills, store.teamKills, store.respawnAt, store.points = {}, {}, {}, {}
end

function lib.ScoreKill(victim, attacker, dmg)
    local isPlayer = IsValid(attacker) and attacker:IsPlayer()
    local killer = attacker --[[@as Player]]
    local events = lib._KillEvents({
        suicide = attacker == victim,
        player = isPlayer,
        enemy = isPlayer and isEnemy(killer, victim),
        headshot = victim:LastHitGroup() == HITGROUP_HEAD
    })
    if #events == 0 then return end
    local n = teamCount(PW.ActiveMode)
    local current = killer:Team()
    ---@type integer?
    local index = nil
    if current >= 1 and current <= n then index = current end
    local kills, teamKills = lib._Tally(PW._MatchRules, killer, index)
    killer:SetNW2Int(lib._KillsKey, kills)
    if index ~= nil then SetGlobal2Int(lib._TeamKillsKey .. index, teamKills or 0) end
    local score = PW.Score
    if score == nil then return end
    local weapon = weaponOf(killer, dmg)
    for _, id in ipairs(events) do score.Award(killer, id, { weapon = weapon }) end
end

---@type Player[]
local noPlayers = {}

function lib.Check(mode, now, players)
    local started = mode._StartedAt
    if not isnumber(started) then return nil end
    local n = teamCount(mode)
    -- Team standings come from the team kills: the sorted player list (FFA only) is not built every tick (T-10.4).
    local list = players or (n == 0 and sortedPlayers() or noPlayers)
    return lib._Evaluate({
        standings = lib._Standings(n, PW._MatchRules, list),
        teams = n > 0,
        scorelimit = tonumber(mode:Setting("scorelimit")) or 0,
        timelimit = tonumber(mode:Setting("timelimit")) or 0,
        elapsed = now - started
    })
end

---Publishes the HUD's NW2 globals: the score key and the score limit of the running mode and no result yet.
---@param scoreKey string
---@param limit integer
local function publishHud(scoreKey, limit)
    SetGlobal2String(lib._ScoreKeyKey, scoreKey)
    SetGlobal2Int(lib._LimitKey, limit)
    SetGlobal2Int(lib._ResultWinnerKey, 0)
    SetGlobal2Bool(lib._ResultDrawKey, false)
    SetGlobal2Int(lib._ResultTeamsKey, 0)
end

---@param phase PW.PhaseName
---@param oldPhase PW.PhaseName
function MODULE:PW_PhaseChange(phase, oldPhase)
    if (phase == "LIVE" and oldPhase == "PREMATCH") or phase == "LOBBY" then reset(PW._MatchRules) end
    if phase == "PREMATCH" or phase == "LOBBY" then publishHud(lib._TeamKillsKey, 0) end
end

---@param result PW.MatchResult?
function MODULE:PW_MatchEnd(result)
    if result == nil then return end
    local winner, draw, teams = lib._ResultFields(result)
    SetGlobal2Int(lib._ResultWinnerKey, winner)
    SetGlobal2Bool(lib._ResultDrawKey, draw)
    SetGlobal2Int(lib._ResultTeamsKey, teams)
end

function MODULE:PW_MatchStart()
    publishHud(lib._HudScoreKey(PW.ActiveMode), lib._HudScoreLimit(PW.ActiveMode))
    local free = teamCount(PW.ActiveMode) == 0
    for _, ply in ipairs(sortedPlayers()) do
        if free then ply:SetTeam(lib.FreeTeam) end
        ply:Spawn()
    end
end

PW.HookFor(MODULE, "DoPlayerDeath", function(_, victim, attacker, dmg)
    if not live() then return end
    PW.Notify("PW_PlayerKilled", victim, attacker, dmg)
end)

---The death think of one dead player in LIVE: sets the respawn time on the first call, respawns once it is due.
---@param ply Player
local function deathThink(ply)
    local store = PW._MatchRules
    local now = CurTime()
    if store.respawnAt[ply] == nil then
        local delay = PW.Ask("PW_RespawnDelay", ply)
        store.respawnAt[ply] = now + (isnumber(delay) and delay --[[@as number]] or lib._DefaultDelay)
    end
    if lib._RespawnDue(now, store.respawnAt[ply]) and PW.Ask("PW_CanRespawn", ply) ~= false then ply:Spawn() end
end

PW.HookFor(MODULE, "PlayerDeathThink", function(_, ply)
    if not live() then return end
    deathThink(ply)
    return true
end)

-- Verified on the Deck: the engine runs no command for a dead player bot (no StartCommand, no PlayerPostThink), so
-- PlayerDeathThink never comes for it. The tick drives the same death think for every dead bot.
PW.HookFor(MODULE, "Tick", function()
    if not live() then return end
    -- Read at call time, not cached in a local, so a test can stub player.Iterator.
    local players = player.Iterator --[[@as fun(): (fun(): integer?, Player?)]]
    for _, ply in players() do
        local bot = ply --[[@as Player]]
        if bot:IsBot() and not bot:Alive() then deathThink(bot) end
    end
end)

PW.HookFor(MODULE, "PlayerSelectSpawn", function(_, ply, transition)
    if transition or not live() then return end
    local answer = PW.Ask("PW_SelectSpawn", ply)
    local kind = lib._SpawnTarget(answer)
    if kind == "entity" then return answer end
    if kind == "point" then PW._MatchRules.points[ply] = answer --[[@as PW.SpawnPoint]] end
end)

PW.HookFor(MODULE, "PlayerSpawn", function(_, ply)
    if not live() then return end
    local store = PW._MatchRules
    store.respawnAt[ply] = nil
    if teamCount(PW.ActiveMode) == 0 and ply:Team() ~= lib.FreeTeam then ply:SetTeam(lib.FreeTeam) end
    local point = store.points[ply]
    if point == nil then return end
    store.points[ply] = nil
    ply:SetPos(point.pos)
    ply:SetEyeAngles(Angle(0, point.yaw or 0, 0))
end)
