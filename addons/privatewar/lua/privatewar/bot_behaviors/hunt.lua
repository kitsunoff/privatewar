-- Built-in behaviour: hunt (T-5.10; 07-bots.md d.13). Roam bucket. Goes to hot spots: enemies the bot heard or lost
-- (its contact memory, no wallhack) and the places where teammates died recently. With no hot spot it roams the map
-- like a player would: navmesh points away from where it just was and away from teammates, and after arriving it
-- sometimes stops for a moment and looks around. Hunt slots (at most 1-2 bots on one human, 07 d.9): the commander
-- (T-5.11) writes board.hunt; without a slot the bot skips the humans' contacts and the death spots
-- (PW.BotCommander.HuntView). Without the commander every bot may hunt.
-- Weight: a hot spot 0.3 + 0.5 * its score (freshness x closeness); roaming 0.25.
BEHAVIOR.Interval = 1

local pauseChance, maxChecked = 0.35, 8

---@return PW.BotObjectivesLib
local function lib()
    return PW.BotObjectives --[[@as PW.BotObjectivesLib]]
end

---@param ctx PW.BotBrainCtx
---@return PW.BotHotSpot?, number
local function hotSpot(ctx)
    local facts = lib().Facts(ctx)
    local memory, deaths = ctx.memory, facts.deaths
    local commander = rawget(PW, "BotCommander") --[[@as PW.BotCommanderLib?]]
    if commander ~= nil then memory, deaths = commander.HuntView(ctx.board, memory, deaths) end
    local spots = lib().HotSpots(memory, deaths, ctx.now)
    return lib().PickHotSpot(spots, facts.pos, ctx.checked, ctx.now)
end

---@param ctx PW.BotBrainCtx
---@param random fun(): number
---@return Vector?
local function roamPoint(ctx, random)
    local facts = lib().Facts(ctx)
    return lib().PickRoamPoint(facts.pos, facts.candidates, ctx.recent or {}, facts.mates, random)
end

local function one()
    return 1
end

---@param _ Player
---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    if PW.BotObjectives == nil then return false end
    if hotSpot(ctx) ~= nil or roamPoint(ctx, one) ~= nil then return "roam" end
    return false
end

---@param _ Player
---@param ctx PW.BotBrainCtx
---@return number
function BEHAVIOR:Weight(_, ctx)
    local spot, score = hotSpot(ctx)
    if spot ~= nil then return 0.3 + 0.5 * math.min(score, 1) end
    return 0.25
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnStart(_, ctx)
    ctx:ClearGoal()
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    lib().LookAt(ctx, nil)
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnSuspend(_, ctx)
    lib().LookAt(ctx, nil)
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnResume(_, ctx)
    local st = (ctx.state or {}) --[[@as table<string, any>]]
    st.point, st.pauseUntil = nil, nil
end

---A travel leg: a sprint by the personality's mobility when it is long (T-11.6).
---@param ctx PW.BotBrainCtx
---@param point Vector
local function travel(ctx, point)
    local tactics = rawget(PW, "BotTactics") --[[@as PW.BotTacticsLib?]]
    if tactics ~= nil then tactics.Travel(ctx, point) end
end

---Picks where to go next: the best hot spot, else a roam point.
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
local function goNext(ctx, st)
    local spot = hotSpot(ctx)
    local random = function() return lib().Random(ctx) end
    if spot ~= nil then
        st.kind, st.point = "spot", spot.pos
        ctx:SetGoal(spot.pos, 96, "hunt")
        travel(ctx, spot.pos)
        return
    end
    local point = roamPoint(ctx, random)
    st.kind, st.point = "roam", point
    if point ~= nil then
        ctx:SetGoal(point, 128, "hunt")
        travel(ctx, point)
    end
end

---Arrived: remember the place, then either pause and look around or go on.
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
local function arrive(ctx, st)
    local point = st.point --[[@as Vector]]
    ctx.recent = lib().Remember(ctx.recent or {}, point)
    if st.kind == "spot" then
        local checked = ctx.checked or {}
        checked[#checked + 1] = { pos = point, time = ctx.now }
        while #checked > maxChecked do table.remove(checked, 1) end
        ctx.checked = checked
    end
    if lib().Random(ctx) < pauseChance then
        ctx:Intent().sprint = nil
        st.pauseUntil = ctx.now + 1.5 + 2.5 * lib().Random(ctx)
        local yaw = lib().Random(ctx) * math.pi * 2
        local pos = lib().Facts(ctx).pos
        lib().LookAt(ctx, pos + Vector(math.cos(yaw) * 500, math.sin(yaw) * 500, 60))
        return
    end
    goNext(ctx, st)
end

---A fresher hot spot than the one the bot walks to (or any while it roams) takes over.
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@return boolean
local function better(ctx, st)
    local spot = hotSpot(ctx)
    if spot == nil then return false end
    return st.kind ~= "spot" or (st.point --[[@as Vector]]):Distance(spot.pos) > 200
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local st = (ctx.state or {}) --[[@as table<string, any>]]
    if st.pauseUntil ~= nil then
        if ctx.now < st.pauseUntil then return PW.BotBrain.Continue() end
        st.pauseUntil, st.point = nil, nil
        lib().LookAt(ctx, nil)
    end
    local status = ctx:GoalStatus()
    if st.point == nil or status == nil or status == "failed" or status == "unreachable" or better(ctx, st) then
        goNext(ctx, st)
    elseif status == "arrived" then
        arrive(ctx, st)
    end
    if st.point == nil then return PW.BotBrain.Done("nowhere to hunt") end
    return PW.BotBrain.Continue()
end
