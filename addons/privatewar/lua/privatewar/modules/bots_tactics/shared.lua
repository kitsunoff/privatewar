-- Bots tactics (T-5.10, survival and combat behaviours; 07-bots.md d.8, d.10, d.13, d.15). A sub-module of `bots`.
-- Pure helpers over plain data for the behaviours fight, take_cover, reload_cover, retaliate, search, third_party and
-- throw_equipment: the facts of a bot (blackboard field `tactics`), contact queries, the cover scoring, flank and
-- strafe points. The engine glue (facts tick, damage hook, budgeted cover search, equipment) is in init.lua.
--
-- Decisions of the lane agent (to confirm):
--   1. The behaviours read the facts from board.tactics, written by this module at 5 Hz; tests put fixture facts
--      there. The field is new on the blackboard (docs/api/bots-blackboard.md needs a row: writer bots_tactics).
--   2. The profile numbers come from the data files (T-5.12): strafe_chance of the difficulty, the other six fields
--      of the personality (ProfileFields). DefaultProfile is only the fallback of a field a board lacks.
--   3. Cover: candidates are navmesh hiding spots and area centres within Config.coverRadius, a cheap score first
--      (near the bot, not toward the threat, not too close to it), then traces for the best few. A cover is a point
--      hidden from the threat when crouched; its peek is the same point when standing sees the threat, else the
--      nearest open candidate within Config.peekRadius.
--   4. Contact sources gunfire and explosion are "a fight heard" (third_party); every other lost contact is searched.
--   5. A running fight keeps its target for Config.fightGrace seconds after the last sighting before it ends "lost
--      sight": a bot that turned or strafed out of view for a moment re-acquires instead of searching and
--      re-hesitating (measured in lua/tests/privatewar/bots_engagement.lua).

MODULE.Name = "Bots tactics"

local lib = (rawget(PW, "BotTactics") or {}) --[[@as PW.BotTacticsLib]]
PW.BotTactics = lib

lib.Config = {
    threatMemory = 8, -- s: a contact this fresh is a threat for reload_cover
    coverThreatAge = 4, -- s: a contact this fresh is a threat for take_cover
    coverFresh = 3, -- s: a cover older than this is not used
    coverThreatSlack = 300, -- units: the threat moved farther than this from where the cover was searched
    coverRadius = 700, -- units: candidates within this distance of the bot
    coverMinThreat = 250, -- units: candidates closer than this to the threat are rejected
    peekRadius = 250, -- units: a peek point for a cover that has no stand-up peek
    peekStep = 80, -- units: the side step out of a cover whose search found no peek point (T-11.6)
    combatCoverRange = 500, -- units: a healthy bot fights from cover only from farther than this
    lowHealth = 0.5, -- share: below it the bot is under pressure
    pressureWindow = 2.5, -- s: damage this recent puts the bot under pressure
    hurtWindow = 1.5, -- s: retaliate after damage this recent
    lowAmmo = 0.25, -- share of the magazine: reload in cover when a threat is known
    calmAmmo = 0.5, -- share of the magazine: reload when no threat is known
    searchMemory = 12, -- s: lost contacts this fresh are searched (07 d.7 memory)
    fightSoundAge = 6, -- s: a fight heard this recently draws a third party
    fightSoundRange = 3000, -- units
    throwAge = 4, -- s: a seen enemy lost this recently is a grenade target
    throwMin = 300, -- units
    throwMax = 1800, -- units
    blockedFlank = 0.4, -- s: settled but blocked this long, reposition (07 d.8)
    fightGrace = 1 -- s: fight holds its target through a sight gap this short (a turn, a strafe behind a post)
}

lib.DefaultProfile = {
    strafe = 0.5, crouch = 0.25, aggression = 0.5, engageRange = 2000, coverChance = 0.5, flankRadius = 450,
    thirdPartyDelay = 1, mobility = 0.6, slide = 0.2
}

lib.FightSounds = { gunfire = true, gunfire_suppressed = true, explosion = true }

---Profile key to the data field that carries it: the strafe and slide chances are difficulty fields, the rest are
---personality fields (T-5.12, T-11.6). The data files win; DefaultProfile is the fallback of a field a board lacks.
lib.ProfileFields = {
    strafe = "strafe_chance", crouch = "crouch_chance", aggression = "aggression", engageRange = "engage_range",
    coverChance = "cover_chance", flankRadius = "flank_radius", thirdPartyDelay = "third_party_delay",
    mobility = "mobility", slide = "slide_chance"
}

---Profile keys read from the difficulty; every other key is read from the personality.
local difficultyKeys = { strafe = true, slide = true }

local profiles = PW.BotProfiles
profiles.Reads("difficulty", "tactics", { "strafe_chance", "slide_chance" })
profiles.Reads("personality", "tactics", { "crouch_chance", "aggression", "engage_range", "cover_chance",
    "flank_radius", "third_party_delay", "mobility" })

---@param entity table?
---@param field string
---@return number?
local function numberOf(entity, field)
    local v = entity ~= nil and (entity --[[@as table<string, any>]])[field] or nil
    return isnumber(v) and v or nil
end

function lib.ProfileFor(personality, difficulty, tier)
    ---@type table<string, number>
    local p = {}
    ---@type table<string, any>
    local tierData = tier ~= nil and profiles.TierExists(tier) and profiles.Tier(tier) or {}
    for key, v in pairs(lib.DefaultProfile --[[@as table<string, number>]]) do
        local field = lib.ProfileFields[key]
        if difficultyKeys[key] then
            p[key] = numberOf(difficulty, field) or numberOf(tierData, field) or v
        else
            p[key] = numberOf(personality, field) or v
        end
    end
    return p --[[@as PW.BotProfile]]
end

local origin = Vector(0, 0, 0)

---@type PW.BotCombatFacts
local emptyFacts = { at = 0, pos = origin, health = 100, maxHealth = 100, clip = -1, capacity = 0, reserve = 0,
    reloading = false, lethal = 0, profile = lib.ProfileFor() }

function lib.FactsOf(ctx)
    local board = ctx.board
    return board ~= nil and board.tactics or emptyFacts
end

function lib.HealthFrac(f)
    if f.maxHealth <= 0 then return 1 end
    return math.Clamp(f.health / f.maxHealth, 0, 1)
end

function lib.AmmoLow(f, share)
    if f.capacity <= 0 or f.clip < 0 or f.reserve <= 0 or f.clip >= f.capacity then return false end
    return f.clip <= math.floor(f.capacity * share)
end

function lib.Age(ctx, contact)
    return ctx.now - contact.time
end

function lib.Visible(ctx)
    local pos = lib.FactsOf(ctx).pos
    ---@type PW.BotContact?
    local best = nil
    local bestDist = math.huge
    for _, c in ipairs(ctx.contacts) do
        if c.visible then
            local d = pos:DistToSqr(c.pos)
            if d < bestDist then best, bestDist = c, d end
        end
    end
    return best
end

function lib.Lost(ctx, maxAge, filter)
    ---@type PW.BotContact?
    local best = nil
    for _, c in ipairs(ctx.contacts) do
        local fits = not c.visible and lib.Age(ctx, c) <= maxAge and (filter == nil or filter(c))
        if fits and (best == nil or c.time > best.time) then best = c end
    end
    return best
end

function lib.Threat(ctx, maxAge)
    return lib.Visible(ctx) or lib.Lost(ctx, maxAge)
end

function lib.Hurt(ctx, seconds)
    local at = lib.FactsOf(ctx).hurtAt
    return at ~= nil and ctx.now - at <= seconds
end

function lib.CoverFor(ctx, threatPos)
    local cover = lib.FactsOf(ctx).cover
    if cover == nil or ctx.now - cover.at > lib.Config.coverFresh then return nil end
    if cover.threatPos:Distance(threatPos) > lib.Config.coverThreatSlack then return nil end
    return cover
end

function lib.PreScore(cand, botPos, threatPos)
    local cfg = lib.Config
    local d = botPos:Distance(cand.pos)
    local t = cand.pos:Distance(threatPos)
    if d > cfg.coverRadius or t < cfg.coverMinThreat then return nil end
    local toward = math.max(botPos:Distance(threatPos) - t, 0)
    return 1 - 0.6 * d / cfg.coverRadius - 0.5 * toward / cfg.coverRadius + (cand.spot and 0.15 or 0)
end

---The nearest open candidate within the peek radius of a cover point.
---@param cands PW.BotCoverCandidate[]
---@param pos Vector
---@return Vector?
local function peekNear(cands, pos)
    ---@type Vector?
    local best = nil
    local bestDist = lib.Config.peekRadius
    for _, c in ipairs(cands) do
        local d = c.pos:Distance(pos)
        if c.open and d <= bestDist then best, bestDist = c.pos, d end
    end
    return best
end

---A step sideways out of a cover, across the line to the threat (T-11.6): the peek of a cover without a traced one.
---@param pos Vector
---@param threatPos Vector
---@return Vector
local function sideStep(pos, threatPos)
    return lib.StrafePoint(pos, threatPos, 1, lib.Config.peekStep)
end

function lib.PickCover(cands, threatPos, now)
    ---@type PW.BotCover?
    local best = nil
    for _, c in ipairs(cands) do
        if c.hidden and c.pre ~= nil then
            local peek = c.standOpen and c.pos or peekNear(cands, c.pos)
            local score = c.pre + (c.standOpen and 0.3 or 0) + (peek ~= nil and 0.15 or 0)
            if best == nil or score > best.score then
                best = { pos = c.pos, peek = peek or sideStep(c.pos, threatPos), standPeek = c.standOpen == true,
                    threatPos = threatPos, at = now, score = score, guessed = peek == nil or nil }
            end
        end
    end
    return best
end

---The flat unit direction from a to b and its right-hand side (Source: yaw 0 looks along +x, right is -y).
---@param a Vector
---@param b Vector
---@return Vector forward, Vector right
local function axes(a, b)
    local dir = b - a
    dir.z = 0
    if dir:IsZero() then dir = Vector(1, 0, 0) end
    dir:Normalize()
    return dir, Vector(dir.y, -dir.x, 0)
end

function lib.FlankPoint(from, to, side, radius)
    local _, right = axes(from, to)
    return from + (to - from) * 0.6 + right * (side * radius)
end

function lib.StrafePoint(pos, threatPos, side, dist)
    local _, right = axes(pos, threatPos)
    return pos + right * (side * dist)
end

function lib.SetButton(intent, mask, on)
    local buttons = intent.buttons or 0
    intent.buttons = on and bit.bor(buttons, mask) or bit.band(buttons, bit.bnot(mask))
end

---@type table<table, table<string, number>>
local marks = setmetatable({}, { __mode = "k" })

function lib.Mark(board, key, untilTime)
    local list = marks[board]
    if list == nil then
        list = {}
        marks[board] = list
    end
    list[key] = untilTime
end

function lib.Marked(board, key, now)
    local list = marks[board]
    local at = list ~= nil and list[key] or nil
    return at ~= nil and now < at
end

function lib.Random()
    return math.random()
end

function lib.UseEquipment(ctx, slot)
    local injected = ctx._api.useEquipment
    if injected ~= nil then return injected(ctx.bot, slot) == true end
    local equipment = rawget(PW, "Equipment") --[[@as table<string, any>?]]
    local use = equipment ~= nil and equipment.Use or nil
    if not isfunction(use) then return false end
    return use(ctx.bot, slot) ~= false
end

local movesFile = "privatewar/modules/bots_tactics/sh_moves.lua"
if SERVER then AddCSLuaFile(movesFile) end
include(movesFile)
