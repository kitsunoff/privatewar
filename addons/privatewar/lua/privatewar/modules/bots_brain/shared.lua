-- Bots brain (T-5.9; 07-bots.md d.4, d.5). Pure dual-utility selection over plain data: the rank bucket decides,
-- then a weighted-random pick among the near-best of that bucket (screen), with a commitment bonus and a minimum run
-- time for the running behaviour. The per-bot state, the Action stack and the ctx are in sh_stack.lua; the scheduler
-- glue is in init.lua.
--
-- Decisions of the lane agent (to confirm):
--   1. Buckets (orchestrator decision): survival 40 > combat 30 > objective 20 > roam 10. Rank returns a bucket name
--      or a number (07 d.5 shows numbers: 20 is objective, 10 is roam); nil, false or <= 0 means "not a candidate".
--   2. Screen and bonus: defaults 0.7 and 1.15 (notes/14 "regular"); a bot's difficulty entity overrides them with
--      decision_screen and commitment_bonus. The bonus multiplies the running behaviour's weight.
--   3. No re-roll while the running behaviour is the best of the best bucket after its bonus (or inside its MinRun
--      and not outranked): the weighted-random pick happens only when something beats it, so near-equal options do
--      not flip at 10 Hz.
--   4. Interval (07 d.4): default 1 s, minimum 0.1 s; Rank and Weight are cached between evaluations.

MODULE.Name = "Bots brain"

local lib = (rawget(PW, "BotBrain") or {}) --[[@as PW.BotBrainLib]]
PW.BotBrain = lib

lib.Buckets = { survival = 40, combat = 30, objective = 20, roam = 10 }
-- screen and bonus: the fallback of a board without a difficulty (the regular tier's values; a test keeps them equal)
lib.Defaults = { screen = 0.7, bonus = 1.15, interval = 1, minInterval = 0.1, maxDepth = 4 }
PW.BotProfiles.Reads("difficulty", "brain", { "decision_screen", "commitment_bonus" })

local epsilon = 1e-9

---@param rank any
---@return number?
function lib.RankValue(rank)
    if isstring(rank) then return lib.Buckets[rank] end
    if isnumber(rank) and rank > 0 then return rank end
    return nil
end

---@param def PW.BotBehavior
---@return number
function lib.IntervalOf(def)
    local interval = def.Interval
    if not isnumber(interval) then return lib.Defaults.interval end
    return math.max(interval --[[@as number]], lib.Defaults.minInterval)
end

---@param rank number
---@return string
local function bucketName(rank)
    for name, value in pairs(lib.Buckets) do
        if value == rank then return name end
    end
    return tostring(rank)
end

---The best rank and the best weight inside it.
---@param options PW.BotCandidateScore[]
---@return number top, number best
local function bestOf(options)
    local top, best = -math.huge, 0
    for _, c in ipairs(options) do
        if c.rank > top then top, best = c.rank, c.weight
        elseif c.rank == top and c.weight > best then best = c.weight end
    end
    return top, best
end

---@param cands PW.BotCandidateScore[]
---@param screen number
---@return PW.BotCandidateScore[]
function lib.Screen(cands, screen)
    local top, best = bestOf(cands)
    ---@type PW.BotCandidateScore[]
    local out = {}
    local floor = screen * best - epsilon
    for _, c in ipairs(cands) do
        if c.rank == top and c.weight > 0 and c.weight >= floor then out[#out + 1] = c end
    end
    return out
end

---@param options PW.BotCandidateScore[]
---@param random fun(): number
---@return PW.BotCandidateScore?
function lib.Pick(options, random)
    local total = 0
    for _, c in ipairs(options) do total = total + c.weight end
    if #options == 0 or total <= 0 then return nil end
    ---@type number
    local roll = random() * total
    for _, c in ipairs(options) do
        roll = roll - c.weight
        if roll < 0 then return c end
    end
    return options[#options]
end

---The candidates with the running behaviour's entry replaced by its boosted score.
---@param cands PW.BotCandidateScore[]
---@param cur PW.BotCurrentScore?
---@param bonus number
---@return PW.BotCandidateScore[] options, PW.BotCandidateScore? boosted
local function withCommitment(cands, cur, bonus)
    ---@type PW.BotCandidateScore[]
    local options = {}
    for _, c in ipairs(cands) do
        if cur == nil or c.id ~= cur.id then options[#options + 1] = c end
    end
    if cur == nil then return options, nil end
    local boosted = { id = cur.id, rank = cur.rank, weight = cur.weight * bonus }
    options[#options + 1] = boosted
    return options, boosted
end

---@param cands PW.BotCandidateScore[]
---@param cur PW.BotCurrentScore?
---@param opts PW.BotChooseOpts
---@return string?, string
function lib.Choose(cands, cur, opts)
    local options, boosted = withCommitment(cands, cur, opts.bonus)
    if #options == 0 then return nil, "no candidate" end
    local top, best = bestOf(options)
    if cur ~= nil and boosted ~= nil and cur.rank >= top then
        if cur.locked then return cur.id, "min run" end
        if boosted.weight >= best - epsilon then return cur.id, "committed" end
    end
    local screened = lib.Screen(options, opts.screen)
    local pick = lib.Pick(screened, opts.random)
    if pick == nil then return nil, "no candidate" end
    return pick.id, string.format("%s w=%.2f, 1 of %d near-best", bucketName(pick.rank), pick.weight, #screened)
end

---@param kind "continue"|"change"|"suspend"|"done"
---@param id string?
---@param reason string?
---@return PW.BotTransition
local function transition(kind, id, reason)
    return { kind = kind, id = id, reason = reason }
end

local keepRunning = transition("continue")

function lib.Continue() return keepRunning end
function lib.ChangeTo(id, reason) return transition("change", id, reason or ("change to " .. tostring(id))) end
function lib.SuspendFor(id, reason) return transition("suspend", id, reason or ("suspend for " .. tostring(id))) end
function lib.Done(reason) return transition("done", nil, reason or "done") end

if SERVER then AddCSLuaFile("privatewar/modules/bots_brain/sh_stack.lua") end
include("privatewar/modules/bots_brain/sh_stack.lua")
