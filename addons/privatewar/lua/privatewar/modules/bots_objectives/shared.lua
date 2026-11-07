-- Bots objectives (T-5.10; 07-bots.md d.13, d.14): shared helpers of the objective and roam behaviours (objective,
-- use_streak, hunt, camp). The facts a behaviour needs besides the ctx (position, team, mode, objectives, teammates,
-- roam candidates) come from one accessor, cached per brain tick; tests inject them through ctx._api.facts. Everything
-- else is pure over plain data. Roam, hot spots and camp spots: sh_roam.lua. Engine gatherer: init.lua.
--
-- Decisions of the lane agent (to confirm):
--   1. Until the commander (T-5.11) writes board.order, a bot picks an objective locally: MODE:BotObjectives(team)
--      when the mode defines it, else a fallback derived here from the Domination flags (dom only) and the Kill
--      Confirmed tags (kc only), with the d.14 rules. Mode filtering lives in Derive, not in BEHAVIOR.Modes: d.13 has
--      one `objective` behaviour for every mode that has objectives.
--   2. Fallback weights: capture 0.6 (+0.2 the middle flag), ours under capture 0.9, defend 0.3 (want 1); collect
--      0.6, deny 0.5 (want 1). Crowding: an objective with `want` or more teammates near it scores x0.35; the current
--      one is sticky (x1.3) so bots do not dither between flags.
--   3. The personality type is read as board.personality.type ("stationary" runs camp); order compliance as
--      board.difficulty.teamwork (a board without a difficulty reads the regular tier). Both are
--      declared for the T-5.12 field test.

MODULE.Name = "Bots objectives"

local lib = (rawget(PW, "BotObjectives") or {}) --[[@as PW.BotObjectivesLib]]
PW.BotObjectives = lib

lib.Falloff = 1200
lib.Recent = 4
lib.DeathMemory = 45
lib._Deaths = lib._Deaths or {}

PW.BotProfiles.Reads("difficulty", "objectives", { "teamwork" })
PW.BotProfiles.Reads("personality", "objectives", { "type" })

local flagRadius, tagRadius = 160, 24
local crowdFactor, stickyFactor = 0.35, 1.3

---@type PW.BotFacts
local noFacts = { pos = Vector(0, 0, 0), objectives = {}, mates = {}, deaths = {}, candidates = {},
    stationary = false, teamwork = 1 }

function lib.Facts(ctx)
    if ctx.facts ~= nil and ctx.factsAt == ctx.now then return ctx.facts end
    local api = ctx._api or {}
    local source = api.facts or lib.Gather
    local facts = source ~= nil and source(ctx) or noFacts
    ctx.facts, ctx.factsAt = facts, ctx.now
    return facts
end

function lib.Random(ctx)
    local api = ctx._api or {}
    if api.random ~= nil then return api.random() end
    return math.random()
end

function lib.Closeness(dist)
    return 1 / (1 + math.max(dist, 0) / lib.Falloff)
end

---@param action string
---@param id string
---@param pos Vector
---@param radius number
---@param weight number
---@param want integer
---@return PW.BotObjective
local function objective(action, id, pos, radius, weight, want)
    return { id = id, pos = pos, radius = radius, action = action, weight = weight, want = want }
end

function lib.DomObjectives(flags, team)
    ---@type PW.BotObjective[]
    local out = {}
    local middle = #flags % 2 == 1 and (#flags + 1) / 2 or nil
    for index, flag in ipairs(flags) do
        local id = "flag_" .. flag.letter
        local sign = team == 1 and 1 or -1
        if team ~= nil and flag.owner == team and flag.value * sign < 95 then
            out[#out + 1] = objective("capture", id, flag.pos, flagRadius, 0.9, 2)
        elseif team ~= nil and flag.owner == team then
            out[#out + 1] = objective("defend", id, flag.pos, flagRadius, 0.3, 1)
        else
            out[#out + 1] = objective("capture", id, flag.pos, flagRadius, index == middle and 0.8 or 0.6, 2)
        end
    end
    return out
end

function lib.KCObjectives(tags, team)
    ---@type PW.BotObjective[]
    local out = {}
    for _, tag in ipairs(tags) do
        local own = team ~= nil and tag.team == team
        out[#out + 1] = objective(own and "deny" or "collect", tag.id, tag.pos, tagRadius, own and 0.5 or 0.6, 1)
    end
    return out
end

function lib.Derive(mode, own, flags, tags, team)
    if own ~= nil then return own end
    if mode == "dom" then return lib.DomObjectives(flags, team) end
    if mode == "kc" then return lib.KCObjectives(tags, team) end
    return {}
end

function lib.CountNear(points, pos, dist)
    local n, limit = 0, dist * dist
    for _, p in ipairs(points) do
        if p:DistToSqr(pos) <= limit then n = n + 1 end
    end
    return n
end

---@param obj PW.BotObjective
---@param pos Vector
---@param mates Vector[]
---@param currentId string?
---@return number
local function scoreOf(obj, pos, mates, currentId)
    local score = obj.weight * lib.Closeness(pos:Distance(obj.pos))
    local near = lib.CountNear(mates, obj.pos, math.max(obj.radius * 2.5, 400))
    if near >= math.max(obj.want, 1) then score = score * crowdFactor end
    if obj.id == currentId then score = score * stickyFactor end
    return score
end

function lib.PickObjective(objectives, pos, mates, currentId)
    ---@type PW.BotObjective?
    local best, bestScore = nil, 0
    for _, obj in ipairs(objectives) do
        local score = scoreOf(obj, pos, mates, currentId)
        if score > bestScore then best, bestScore = obj, score end
    end
    return best, bestScore
end

function lib.Resolve(ctx, facts, currentId)
    local order = ctx.order
    if order ~= nil and istable(order.objective) then
        local obj = order.objective --[[@as PW.BotObjective]]
        if isvector(obj.pos) then
            ---@type PW.BotObjective
            local copy = { id = tostring(obj.id), pos = obj.pos, radius = tonumber(obj.radius) or flagRadius,
                action = order.type or obj.action, weight = tonumber(obj.weight) or 0.5, want = obj.want or 1 }
            return copy, copy.weight, true
        end
    end
    local best, score = lib.PickObjective(facts.objectives, facts.pos, facts.mates, currentId)
    return best, score, false
end

function lib.PointIn(center, radius, random)
    local angle, dist = random() * math.pi * 2, math.sqrt(random()) * radius
    return center + Vector(math.cos(angle) * dist, math.sin(angle) * dist, 0)
end

function lib.Remember(list, pos)
    list[#list + 1] = pos
    while #list > lib.Recent do table.remove(list, 1) end
    return list
end

function lib.LookAt(ctx, point)
    if point == nil then
        if isvector(ctx.board.target) then ctx:SetTarget(nil) end
        return
    end
    ctx:SetTarget(point --[[@as any]])
end

function lib.ReadyStreak(bot)
    local streaks = rawget(PW, "Streaks") --[[@as PW.StreaksLib?]]
    if streaks == nil or streaks.Ready == nil then return nil end
    local id = streaks.Ready(bot)
    if id == nil then return nil end
    return { id = id }
end

function lib.UseStreak(ctx, id)
    local api = ctx._api or {}
    if api.useStreak ~= nil then return api.useStreak(ctx.bot, id) end
    local streaks = rawget(PW, "Streaks") --[[@as PW.StreaksLib?]]
    if streaks == nil or streaks.Use == nil or ctx.bot == nil then return false end
    return streaks.Use(ctx.bot, id)
end

if SERVER then AddCSLuaFile("privatewar/modules/bots_objectives/sh_roam.lua") end
include("privatewar/modules/bots_objectives/sh_roam.lua")
