-- Spawns module (T-2.9; 03-mapdata.md d.7; docs/api/map.md). Owns PW.Spawns: the scoring spawn picker behind the
-- question PW_SelectSpawn and spawn protection. Shared: the API, the gameplay values and the pure rules (plain data
-- in, plain data out): the candidate pool, the random sample, the score of a candidate and the choice of the best
-- free candidate over an injected probe. Server glue (player positions, hull and line of sight traces, engine
-- hooks): init.lua.

MODULE.Name = "Spawns"
MODULE.Settings = {
    protection = { type = "float", default = 0, min = 0, max = 5, scope = "match", label = "Spawn protection (s)" }
}

local lib = (rawget(PW, "Spawns") or {}) --[[@as PW.SpawnsLib]]
PW.Spawns = lib

lib._ProtectKey = "pw_spawn_protect"

-- Gameplay values, reported for confirmation (T-2.9).
lib.Weights = {
    distCap = 3000,
    los = 5000,
    losFacing = 2000,
    facingCos = 0.5,
    mateRadius = 1000,
    mate = 300,
    mateMax = 3,
    recent = 2500,
    recentWindow = 10,
    jitter = 200,
    eyeHeight = 64
}

lib.Budget = {
    sample = 8,
    maxEnemies = 16,
    maxTraces = 64,
    maxMs = 5
}

---@return PW.SpawnsStore
function lib._NewStore()
    return { used = {}, spawned = {}, protect = {} }
end

PW._Spawns = PW._Spawns or lib._NewStore()

---@param pos Vector
---@return string
function lib._Key(pos)
    return string.format("%.0f %.0f %.0f", pos.x, pos.y, pos.z)
end

---@param out PW.SpawnCandidate[]
---@param list PW.MapSpawn[]?
local function addPoints(out, list)
    for _, point in ipairs(list or {}) do
        out[#out + 1] = { pos = point.pos, yaw = point.yaw or 0, key = lib._Key(point.pos) }
    end
end

function lib._Pool(spawns, team, all)
    ---@type PW.SpawnCandidate[]
    local out = {}
    local own = spawns[team]
    if all or own == nil or #own == 0 then
        for _, list in pairs(spawns) do addPoints(out, list) end
        return out
    end
    addPoints(out, own)
    local any = PW.Map ~= nil and PW.Map.AnyTeam or 0
    if any ~= team then addPoints(out, spawns[any]) end
    return out
end

function lib._Sample(list, n, rand)
    ---@type PW.SpawnCandidate[]
    local copy = {}
    for i, c in ipairs(list) do copy[i] = c end
    local count = math.min(n, #copy)
    for i = 1, count do
        local j = rand(i, #copy)
        copy[i], copy[j] = copy[j], copy[i]
    end
    ---@type PW.SpawnCandidate[]
    local out = {}
    for i = 1, count do out[i] = copy[i] end
    return out
end

---@param pos Vector
---@param actors PW.SpawnActor[]
---@return number
local function nearest(pos, actors)
    local best = math.huge
    for _, a in ipairs(actors) do
        local d = pos:Distance(a.pos)
        if d < best then best = d end
    end
    return best
end

---@param target Vector
---@param enemies PW.SpawnActor[]
---@param cos number
---@return boolean
local function anyFacing(target, enemies, cos)
    for _, e in ipairs(enemies) do
        if e.dir ~= nil then
            local eye = e.eye or (e.pos + Vector(0, 0, 64))
            local to = target - eye
            local len = to:Length()
            if len > 0 and e.dir:Dot(to) / len >= cos then return true end
        end
    end
    return false
end

---@param pos Vector
---@param mates PW.SpawnActor[]
---@param w PW.SpawnWeights
---@return number
local function mateBonus(pos, mates, w)
    local count = 0
    for _, m in ipairs(mates) do
        if pos:Distance(m.pos) <= w.mateRadius then count = count + 1 end
    end
    return math.min(count, w.mateMax) * w.mate
end

---@param pos Vector
---@param enemies PW.SpawnActor[]
---@param w PW.SpawnWeights
---@return number
local function losPenalty(pos, enemies, w)
    local target = pos + Vector(0, 0, w.eyeHeight)
    if anyFacing(target, enemies, w.facingCos) then return w.los + w.losFacing end
    return w.los
end

function lib._Score(c, ctx)
    ---@type PW.SpawnWeights
    local w = ctx.weights or lib.Weights
    ---@type number
    local score = math.min(nearest(c.pos, ctx.enemies), w.distCap)
    if c.visible then score = score - losPenalty(c.pos, ctx.enemies, w) end
    if ctx.teamBonus then score = score + mateBonus(c.pos, ctx.mates, w) end
    local last = ctx.used[c.key]
    if last ~= nil then
        local age = ctx.now - last
        if age < w.recentWindow then score = score - w.recent * (1 - math.max(age, 0) / w.recentWindow) end
    end
    return score + (c.jitter or 0)
end

function lib._Choose(cands, ctx, probe)
    ---@type { c: PW.SpawnCandidate, base: number }[]
    local rows = {}
    for i, c in ipairs(cands) do
        c.visible = false
        rows[i] = { c = c, base = lib._Score(c, ctx) }
    end
    table.sort(rows, function(a, b) return a.base > b.base end)
    ---@type PW.SpawnCandidate?
    local best = nil
    local bestScore = -math.huge
    for _, row in ipairs(rows) do
        if best ~= nil and row.base <= bestScore then break end
        if probe.clear(row.c) then
            row.c.visible = probe.sees(row.c)
            local score = row.c.visible and lib._Score(row.c, ctx) or row.base
            if best == nil or score > bestScore then best, bestScore = row.c, score end
        end
    end
    return best
end

function lib._ProtectUntil(now, seconds)
    if seconds <= 0 then return nil end
    return now + seconds
end

function lib._Protected(untilTime, now)
    return untilTime ~= nil and now < untilTime
end

function lib._ProtectionTime()
    return tonumber(PW.Setting("spawns.protection")) or 0
end

function lib.ProtectedUntil(ply)
    return ply:GetNW2Float(lib._ProtectKey, 0)
end
