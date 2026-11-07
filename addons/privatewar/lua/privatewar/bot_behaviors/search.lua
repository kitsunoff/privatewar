-- Built-in behaviour: search (T-5.10; 07-bots.md d.7, d.13, bucket combat). Lost the enemy: walk the 5 search
-- points of perception (last seen, ahead, left, right, far ahead) with a short look-around pause at each. The first
-- leg looks at the last known position (the aim holds the remembered contact and never fires at it); later legs
-- look where the bot walks. A fight heard (gunfire, explosion) is third_party's, not a search.
BEHAVIOR.Interval = 0.5
BEHAVIOR.MinRun = 1
BEHAVIOR.Cooldown = 2

local pause, giveUp, pending = 0.6, 20, 1

---@return PW.BotTacticsLib?
local function tactics()
    return rawget(PW, "BotTactics")
end

---@param c PW.BotContact
---@return boolean
local function lostSighting(c)
    local lib = tactics()
    return lib ~= nil and not lib.FightSounds[c.source]
end

---@param ctx PW.BotBrainCtx
---@return PW.BotContact?
local function lost(ctx)
    local lib = tactics()
    if lib == nil or lib.Visible(ctx) ~= nil then return nil end
    return lib.Lost(ctx, lib.Config.searchMemory, lostSighting)
end

---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    return lost(ctx) ~= nil and "combat" or false
end

---@param ctx PW.BotBrainCtx
---@return number
function BEHAVIOR:Weight(_, ctx)
    local lib = tactics()
    local c = lost(ctx)
    if lib == nil or c == nil then return 0 end
    return 0.3 + 0.4 * math.Clamp(1 - lib.Age(ctx, c) / lib.Config.searchMemory, 0, 1)
end

---@param ctx PW.BotBrainCtx
---@param st table<string, any>
local function goNext(ctx, st)
    st.index = st.index + 1
    local point = st.plan[st.index] --[[@as Vector?]]
    if point == nil then return end
    st.goalAt, st.pauseUntil = ctx.now, nil
    ctx:SetGoal(point, 96, "tactical")
end

---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@return boolean
local function legDone(ctx, st)
    local status = ctx:GoalStatus()
    if status == nil then return ctx.now - st.goalAt >= pending end
    return status ~= "moving"
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local lib = tactics()
    if lib == nil then return PW.BotBrain.Done("no tactics") end
    if lib.Visible(ctx) ~= nil then return PW.BotBrain.Done("found") end
    local st = ctx.state --[[@as table<string, any>]]
    if st.plan == nil then
        local c = lost(ctx)
        if c == nil then return PW.BotBrain.Done("nothing to search") end
        st.plan, st.index, st.since = ctx:SearchPlan(c.ent) or { c.pos }, 0, ctx.now
        ctx:SetTarget(c.ent)
        goNext(ctx, st)
        return PW.BotBrain.Continue()
    end
    if ctx.now - st.since > giveUp then return PW.BotBrain.Done("search timed out") end
    if not legDone(ctx, st) then return PW.BotBrain.Continue() end
    if st.pauseUntil == nil then
        st.pauseUntil = ctx.now + pause
        if st.index == 1 then ctx:SetTarget(nil) end
    elseif ctx.now >= st.pauseUntil then
        if st.index >= #st.plan then return PW.BotBrain.Done("searched") end
        goNext(ctx, st)
    end
    return PW.BotBrain.Continue()
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    ctx:ClearGoal()
    ctx:SetTarget(nil)
end
