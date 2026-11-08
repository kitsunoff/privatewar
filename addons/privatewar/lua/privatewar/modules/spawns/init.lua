-- Spawns module, server glue (T-2.9; 03-mapdata.md d.7). Thin wrappers around the pure rules in shared.lua:
--   PW_SelectSpawn (module listener, LIVE only, real players only) -> PW.Spawns.Pick: a { pos, yaw } answer that
--     match_rules applies when the player spawns; nil keeps the base gamemode's choice.
--   Pick reads the living players once (player.GetAll, no ents.Find*), draws Budget.sample candidates, and probes
--     them best first: one hull trace each, then line of sight traces from the nearest enemies, at most
--     Budget.maxTraces per pick (past it a candidate counts as seen).
--   PlayerSpawn during LIVE -> the player has spawned in this match; spawn protection for the spawns.protection
--     setting (0 = none). EntityTakeDamage blocks damage while it lasts; KeyPress IN_ATTACK (the player fires)
--     ends it. The end time is published as NW2 for a HUD.
-- The engine hooks go through PW.HookFor, so they run only while the module is enabled (01-extensibility.md d.16).

local lib = PW.Spawns --[[@as PW.SpawnsLib]]

local hullMins, hullMaxs = Vector(-16, -16, 0), Vector(16, 16, 72)
local hullLift = Vector(0, 0, 8)

function lib._HullClear(pos, filter)
    local start = pos + hullLift
    local tr = util.TraceHull({ start = start, endpos = start, mins = hullMins, maxs = hullMaxs,
        mask = MASK_PLAYERSOLID, filter = filter })
    return not tr.StartSolid
end

---@return boolean
local function live()
    local match = PW.Match
    return match ~= nil and match.GetPhase() == "LIVE"
end

---@return integer
local function teamCount()
    local mode = PW.ActiveMode
    if mode == nil then return 0 end
    local count = (mode --[[@as table<string, any>]]).Teams --[[@as any]]
    if not isnumber(count) or count < 0 then return 0 end
    return math.floor(count --[[@as number]])
end

---@param a Player
---@param b Player
---@return boolean
local function isEnemy(a, b)
    local check = PW.IsEnemy
    if check ~= nil then return check(a, b) end
    return a ~= b
end

---@param ply Player
---@return PW.SpawnActor
local function actorOf(ply)
    return { pos = ply:GetPos(), eye = ply:EyePos(), dir = ply:GetAimVector() }
end

---The living players other than ply, split into enemies (at most Budget.maxEnemies) and teammates.
---@param ply Player
---@return PW.SpawnActor[] enemies
---@return PW.SpawnActor[] mates
local function gather(ply)
    ---@type PW.SpawnActor[]
    local enemies = {}
    ---@type PW.SpawnActor[]
    local mates = {}
    for _, other in ipairs(player.GetAll()) do
        if other ~= ply and other:Alive() and other:Team() ~= TEAM_SPECTATOR then
            if not isEnemy(ply, other) then
                mates[#mates + 1] = actorOf(other)
            elseif #enemies < lib.Budget.maxEnemies then
                enemies[#enemies + 1] = actorOf(other)
            end
        end
    end
    return enemies, mates
end

---@param enemies PW.SpawnActor[]
---@param pos Vector
---@return PW.SpawnActor[]
local function nearestFirst(enemies, pos)
    ---@type PW.SpawnActor[]
    local sorted = {}
    for i, e in ipairs(enemies) do sorted[i] = e end
    table.sort(sorted, function(a, b) return a.pos:DistToSqr(pos) < b.pos:DistToSqr(pos) end)
    return sorted
end

---@param ply Player
---@param enemies PW.SpawnActor[]
---@param stats PW.SpawnStats
---@return PW.SpawnProbe
local function makeProbe(ply, enemies, stats)
    local lift = Vector(0, 0, lib.Weights.eyeHeight)
    return {
        clear = function(c)
            stats.probed = stats.probed + 1
            stats.traces = stats.traces + 1
            return lib._HullClear(c.pos, ply)
        end,
        sees = function(c)
            ---@type Vector
            local target = c.pos + lift
            for _, e in ipairs(nearestFirst(enemies, c.pos)) do
                if stats.traces - stats.probed >= lib.Budget.maxTraces then return true end
                stats.traces = stats.traces + 1
                local tr = util.TraceLine({ start = e.eye or (e.pos + lift), endpos = target, mask = MASK_VISIBLE })
                if not tr.Hit then return true end
            end
            return false
        end
    }
end

---@param ply Player
---@param opts PW.SpawnPickOpts
---@return PW.SpawnCandidate[]
---@return PW.SpawnContext
local function prepare(ply, opts)
    local store = PW._Spawns
    local n = teamCount()
    local first = opts.first
    if first == nil then first = not store.spawned[ply] end
    local all = opts.all
    if all == nil then all = n == 0 or not first end
    local teamBonus = opts.teamBonus
    if teamBonus == nil then teamBonus = n > 0 end
    local pool = lib._Pool(opts.spawns or assert(PW.Map).GetSpawns(), ply:Team(), all)
    local cands = lib._Sample(pool, opts.sample or lib.Budget.sample, math.random)
    for _, c in ipairs(cands) do c.jitter = math.random() * lib.Weights.jitter end
    local enemies, mates = opts.enemies, opts.mates
    if enemies == nil or mates == nil then
        local e, m = gather(ply)
        enemies, mates = enemies or e, mates or m
    end
    return cands, { enemies = enemies, mates = mates, teamBonus = teamBonus, now = CurTime(), used = store.used }
end

function lib.Pick(ply, opts)
    local map = PW.Map
    if map == nil or map.GetSpawns == nil then return nil end
    local started = SysTime()
    local cands, ctx = prepare(ply, opts or {})
    ---@type PW.SpawnStats
    local stats = { candidates = #cands, probed = 0, traces = 0, ms = 0 }
    local best = lib._Choose(cands, ctx, makeProbe(ply, ctx.enemies, stats))
    stats.ms = (SysTime() - started) * 1000
    PW._Spawns.stats = stats
    if best == nil then return nil end
    PW._Spawns.used[best.key] = ctx.now
    return { pos = best.pos, yaw = best.yaw }
end

---@param ply any
---@return PW.SpawnPoint?
function MODULE:PW_SelectSpawn(ply)
    if not isentity(ply) or not IsValid(ply) or not (ply --[[@as Entity]]):IsPlayer() or not live() then
        return nil
    end
    local mode = PW.ActiveMode
    if mode ~= nil and isfunction(mode.PW_SelectSpawn) then return PW.Call(mode, "PW_SelectSpawn", ply) end
    return lib.Pick(ply --[[@as Player]])
end

---@param phase PW.PhaseName
---@param oldPhase PW.PhaseName
function MODULE:PW_PhaseChange(phase, oldPhase)
    if phase ~= "LOBBY" and not (phase == "LIVE" and oldPhase == "PREMATCH") then return end
    for ply in pairs(PW._Spawns.protect) do
        if IsValid(ply) then (ply --[[@as Player]]):SetNW2Float(lib._ProtectKey, 0) end
    end
    PW._Spawns = lib._NewStore()
end

PW.HookFor(MODULE, "PlayerSpawn", function(_, ply)
    if not live() then return end
    local store = PW._Spawns
    store.spawned[ply] = true
    local untilTime = lib._ProtectUntil(CurTime(), lib._ProtectionTime())
    store.protect[ply] = untilTime
    ply:SetNW2Float(lib._ProtectKey, untilTime or 0)
end)

PW.HookFor(MODULE, "EntityTakeDamage", function(_, target)
    local store = PW._Spawns
    local untilTime = store.protect[target]
    if untilTime == nil then return end
    if lib._Protected(untilTime, CurTime()) then return true end
    store.protect[target] = nil
end)

PW.HookFor(MODULE, "KeyPress", function(_, ply, key)
    if key ~= IN_ATTACK then return end
    local store = PW._Spawns
    if store.protect[ply] == nil then return end
    store.protect[ply] = nil
    ply:SetNW2Float(lib._ProtectKey, 0)
end)
