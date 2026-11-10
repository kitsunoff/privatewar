-- Bots loadouts (T-5.13; 05-loadout.md d.14, 07-bots.md d.10). A sub-module of `bots`: every bot gets a class from a
-- pool when it spawns in LIVE. Shared: the pure rules over plain data (the pool, the weights, the weighted pick, the
-- re-pick rule, the players' classes taken from a class state). Server glue (settings, registries, hooks): init.lua.
--
-- The pool (05 d.14): the setting bots.classes names the sources, "preset" (the classes/ kind) and "players" (the
-- custom classes of the humans who joined this session, kept after they leave until the map changes). Every class
-- passes the check of the current match settings (budget, bans, PW_ValidateLoadout), never progression: a player's
-- class was already checked against that player's unlocks when it was taken (it is the repaired, available class
-- of the player's class state).
--
-- Decisions of the lane agent (to confirm):
--   1. Weights: a personality field class_weights maps the category of a class's primary weapon to a weight (an
--      unlisted category weighs 1, 0 removes it). CQB prefers shotguns and SMGs, run-and-gun SMGs, camper snipers
--      and LMGs. Every class weighs the same otherwise: a source is not weighted as a whole.
--   2. Re-pick: a bot keeps its class across lives; on each respawn it picks again with the chance of the setting
--      bots.classrepick (default 0.25), and always when it has no class or its class left the pool. A new match
--      starts with a fresh pick.
--   3. Players' classes enter the pool under the key "<SteamID64>:<n>" (ref "player:<key>"); presets keep their
--      class ref "preset:<id>". The pool is sorted presets first (registry order), then players by key, so a roll
--      gives the same class every time.
--   4. When every weight is 0 the pick falls back to an even draw: a bot always gets a class while the pool has one.
--   5. An empty pool (both sources off, or nothing valid) leaves the bot without a class: the default loadout.

MODULE.Name = "Bots loadouts"

local lib = (rawget(PW, "BotLoadouts") or {}) --[[@as PW.BotLoadoutsLib]]
PW.BotLoadouts = lib

lib.WeightsField = "class_weights"

PW.BotProfiles.Reads("personality", "loadouts", { lib.WeightsField })

---@param roll number
---@return number
local function clamp01(roll)
    return math.min(math.max(roll, 0), 0.999999)
end

---@param value (string|string[])?
---@return string?
local function firstItem(value)
    if istable(value) then return (value --[[@as string[] ]])[1] end
    if isstring(value) then return value --[[@as string]] end
    return nil
end

function lib.Sources(value)
    if not istable(value) then return { preset = true, players = true } end
    local set = value --[[@as table<string, boolean>]]
    return { preset = set.preset == true, players = set.players == true }
end

---@param list PW.BotPlayerClass[]
---@return PW.BotPlayerClass[]
local function sortedByKey(list)
    ---@type PW.BotPlayerClass[]
    local copy = {}
    for i, item in ipairs(list) do copy[i] = item end
    table.sort(copy, function(a, b) return a.key < b.key end)
    return copy
end

function lib.BuildPool(input)
    local sources = input.sources
    ---@type PW.BotClassEntry[]
    local pool = {}
    if sources.preset then
        for _, preset in ipairs(input.presets) do
            if input.check(preset.loadout) then
                pool[#pool + 1] = { ref = "preset:" .. preset.id, source = "preset", name = preset.name,
                    loadout = preset.loadout }
            end
        end
    end
    if sources.players then
        for _, class in ipairs(sortedByKey(input.players)) do
            if input.check(class.loadout) then
                pool[#pool + 1] = { ref = "player:" .. class.key, source = "players", name = class.name,
                    loadout = class.loadout }
            end
        end
    end
    return pool
end

function lib.Weight(entry, weights, categoryOf)
    if weights == nil then return 1 end
    local primary = firstItem(entry.loadout.primary)
    local category = entry.category or (primary ~= nil and categoryOf(primary) or nil)
    local weight = category ~= nil and weights[category] or nil
    if not isnumber(weight) then return 1 end
    return math.max(0, weight --[[@as number]])
end

function lib.AppendCandidates(pool, candidates, check)
    for _, entry in ipairs(candidates) do
        -- Providers never lend their cached data to validation hooks or the live spawn repair path.
        local copy = table.Copy(entry) --[[@as PW.BotClassEntry]]
        if check(copy.loadout) then pool[#pool + 1] = copy end
    end
end

---@param pool PW.BotClassEntry[]
---@param weightOf fun(entry: PW.BotClassEntry): number
---@param roll number
---@return PW.BotClassEntry?
local function draw(pool, weightOf, roll)
    ---@type number
    local total = 0
    for _, entry in ipairs(pool) do total = total + weightOf(entry) end
    if total <= 0 then return nil end
    ---@type number
    local point = clamp01(roll) * total
    for _, entry in ipairs(pool) do
        local weight = weightOf(entry)
        if weight > 0 then
            point = point - weight
            if point < 0 then return entry end
        end
    end
    return pool[#pool]
end

function lib.Pick(pool, weights, roll, categoryOf)
    if #pool == 0 then return nil end
    local picked = draw(pool, function(entry) return lib.Weight(entry, weights, categoryOf) end, roll)
    if picked ~= nil then return picked end
    return draw(pool, function() return 1 end, roll)
end

function lib.WeightsOf(board)
    local personality = board.personality --[[@as table<string, any>?]]
    local weights = personality ~= nil and personality[lib.WeightsField] or nil
    if not istable(weights) then return nil end
    return weights --[[@as table<string, number>]]
end

function lib.Find(pool, ref)
    if ref == nil then return nil end
    for _, entry in ipairs(pool) do
        if entry.ref == ref then return entry end
    end
    return nil
end

function lib.ShouldRepick(current, pool, chance, roll)
    if lib.Find(pool, current) == nil then return true end
    return roll < chance
end

function lib._HarvestEntries(owner, state)
    ---@type PW.BotPlayerClass[]
    local out = {}
    for _, entry in ipairs(state.entries) do
        local index = string.match(entry.ref, "^custom:(%d+)$")
        if index ~= nil and entry.available then
            out[#out + 1] = { key = owner .. ":" .. index, name = entry.name, loadout = entry.loadout }
        end
    end
    return out
end
