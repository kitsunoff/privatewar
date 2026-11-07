-- Built-in behaviour: take_cover (T-5.10, T-11.6; 07-bots.md d.13 and its 2026-11-07 revision). A cover point paired
-- with a peek point (bots_tactics searches them against the threat): run to the cover (a sprint when it is farther
-- than Config.coverSprintMin, the aim released), then alternate hide (crouched) and peek (stand up, or step out to the
-- peek point, with a Quick Slide when the addon is there) while the aim shoots; a peek ends only between bursts (the
-- fire-phase gate) and at once when the bot is hit. Rank and weight: PW.BotTactics.CoverWanted (survival under fire,
-- low on health or outnumbered; combat when the enemy is far, by the personality's cover chance). fight hands over
-- to it by its cover chance (ChangeTo).
BEHAVIOR.Interval = 0.25
BEHAVIOR.MinRun = 1.5
local cooldown = 3
BEHAVIOR.Cooldown = cooldown

local moveTimeout, hideMin, hideSpread, peekMin, peekSpread, burstGrace, maxCycles, hitWindow =
    6, 0.8, 1.0, 1.2, 1.3, 1, 3, 0.3

-- Mark on the board while take_cover cools down (fight reads it before it hands over).
local coolMark = "take_cover.cooling"

---@return PW.BotTacticsLib?
local function tactics()
    return rawget(PW, "BotTactics")
end

---The number of enemies in sight.
---@param ctx PW.BotBrainCtx
---@return integer
local function visibleCount(ctx)
    local n = 0
    for _, c in ipairs(ctx.contacts) do
        if c.visible then n = n + 1 end
    end
    return n
end

---Rank and weight from the facts.
---@param ctx PW.BotBrainCtx
---@return PW.BotRank, number
local function assess(ctx)
    local lib = tactics()
    if lib == nil then return false, 0 end
    local threat = lib.Threat(ctx, lib.Config.coverThreatAge)
    if threat == nil then return false, 0 end
    local running = ctx.running == "take_cover"
    local cover = lib.CoverFor(ctx, threat.pos)
    local f = lib.FactsOf(ctx)
    return lib.CoverWanted({
        hasCover = running or (cover ~= nil and cover.peek ~= nil), health = lib.HealthFrac(f),
        hurt = lib.Hurt(ctx, lib.Config.pressureWindow), visibleCount = visibleCount(ctx), engaged = threat.visible,
        running = running, dist = f.pos:Distance(threat.pos), coverChance = f.profile.coverChance
    })
end

---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    return (assess(ctx))
end

---@param ctx PW.BotBrainCtx
---@return number
function BEHAVIOR:Weight(_, ctx)
    local _, weight = assess(ctx)
    return weight
end

---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@param point Vector
local function go(ctx, st, point)
    ctx:SetGoal(point, 24, "tactical")
    st.goalSet = true
end

---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
local function hide(lib, ctx, st)
    st.phase, st.phaseEnd = "hide", ctx.now + hideMin + lib.Random() * hideSpread
    ctx:Intent().stance = "crouch"
    local cover = st.cover --[[@as PW.BotCover]]
    if not cover.standPeek then go(ctx, st, cover.pos) end
end

---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
local function peek(lib, ctx, st)
    st.phase, st.phaseEnd, st.cycles = "peek", ctx.now + peekMin + lib.Random() * peekSpread, (st.cycles or 0) + 1
    ctx:Intent().stance = "stand"
    local cover = st.cover --[[@as PW.BotCover]]
    if cover.standPeek then return end
    local point = cover.peek --[[@as Vector]]
    go(ctx, st, point)
    lib.Slide(ctx, "peek", cover.pos:Distance(point))
end

---Whether the aim is firing now (a peek is not cut in the middle of a burst).
---@param ctx PW.BotBrainCtx
---@return boolean
local function firing(ctx)
    local debugInfo = ctx.board.debug --[[@as table<string, any>?]]
    local aim = debugInfo ~= nil and debugInfo.aim or nil
    return aim ~= nil and aim.fire == true
end

---In the cover: the aim takes the threat again, the sprint ends.
---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
local function arrive(lib, ctx, st)
    lib.Run(ctx, false)
    hide(lib, ctx, st)
end

---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@return PW.BotTransition
local function step(lib, ctx, st)
    if st.phase == "move" then
        local status = ctx:GoalStatus()
        if status == "arrived" then
            arrive(lib, ctx, st)
        elseif status == "failed" or status == "unreachable" then
            return PW.BotBrain.Done("cover unreachable")
        elseif ctx.now - st.since > moveTimeout then
            return PW.BotBrain.Done("cover too far")
        end
    elseif st.phase == "hide" and ctx.now >= st.phaseEnd then
        if st.cycles >= maxCycles then return PW.BotBrain.Done("cover cycles done") end
        peek(lib, ctx, st)
    elseif st.phase == "peek" then
        local hit = lib.Hurt(ctx, hitWindow)
        local over = ctx.now >= st.phaseEnd and not (firing(ctx) and ctx.now < st.phaseEnd + burstGrace)
        if hit or over then hide(lib, ctx, st) end
    end
    return PW.BotBrain.Continue()
end

---Starts the run to the cover: under pressure (the survival rank) and far, a sprint with the aim let go; else a walk
---with the aim on the threat (a healthy bot moving into cover keeps shooting).
---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@param cover PW.BotCover
local function start(lib, ctx, st, cover)
    st.cover, st.phase, st.since, st.cycles = cover, "move", ctx.now, 0
    ctx:Intent().stance = "stand"
    go(ctx, st, cover.pos)
    local far = lib.FactsOf(ctx).pos:Distance(cover.pos) > lib.Config.coverSprintMin
    st.sprint = far and assess(ctx) == "survival"
    lib.Run(ctx, st.sprint)
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local lib = tactics()
    if lib == nil then return PW.BotBrain.Done("no tactics") end
    local st = ctx.state --[[@as table<string, any>]]
    local threat = lib.Threat(ctx, lib.Config.coverThreatAge)
    if threat == nil then return PW.BotBrain.Done("threat gone") end
    if st.cover == nil then
        local cover = lib.CoverFor(ctx, threat.pos)
        if cover == nil or cover.peek == nil then return PW.BotBrain.Done("no cover") end
        start(lib, ctx, st, cover)
    end
    local running = st.phase == "move" and st.sprint
    if not running and ctx.target ~= threat.ent then ctx:SetTarget(threat.ent) end
    return step(lib, ctx, st)
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    local st = ctx.state --[[@as table<string, any>]]
    if st.goalSet then ctx:ClearGoal() end
    ctx:Intent().stance = "stand"
    local lib = tactics()
    if lib ~= nil then lib.Mark(ctx.board, coolMark, ctx.now + cooldown) end
end
