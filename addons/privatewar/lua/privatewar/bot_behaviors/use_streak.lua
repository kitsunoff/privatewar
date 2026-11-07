-- Built-in behaviour: use_streak (T-5.10; 07-bots.md d.13). Objective bucket. Activates a killstreak when the facts
-- carry a ready streak whose STREAK:BotShouldUse agreed (PW.BotObjectives.ReadyStreak, wired to PW.Streaks.Ready by
-- T-4.6; activation through PW.Streaks.Use). Weight 0.9: a ready streak is used before the objective goes on.
-- The first Update activates it, the second ends the behaviour; a cooldown keeps it from firing twice.
BEHAVIOR.Interval = 0.5
BEHAVIOR.Cooldown = 3

---@param ctx PW.BotBrainCtx
---@return PW.BotReadyStreak?
local function ready(ctx)
    local lib = PW.BotObjectives
    if lib == nil then return nil end
    return lib.Facts(ctx).streak
end

---@param _ Player
---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    return ready(ctx) ~= nil and "objective" or false
end

---@param _ Player
---@param ctx PW.BotBrainCtx
---@return number
function BEHAVIOR:Weight(_, ctx)
    return ready(ctx) ~= nil and 0.9 or 0
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local st = ctx.state or {}
    if st.used ~= nil then return PW.BotBrain.Done(st.used and "streak used" or "streak refused") end
    local streak = ready(ctx)
    if streak == nil then return PW.BotBrain.Done("no streak") end
    st.used = (PW.BotObjectives --[[@as PW.BotObjectivesLib]]).UseStreak(ctx, streak.id)
    return PW.BotBrain.Continue()
end
