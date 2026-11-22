BEHAVIOR.Interval = 0.5
BEHAVIOR.MinRun = 0.3
BEHAVIOR.Cooldown = 6

---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    local tactics = PW.BotTactics
    if tactics == nil then return false end
    return tactics._StimWanted(tactics.FactsOf(ctx), tactics.Visible(ctx) ~= nil) and "survival" or false
end

---@return number
function BEHAVIOR:Weight()
    return 1
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local tactics = PW.BotTactics
    if tactics ~= nil and tactics.UseEquipment(ctx, "tactical") then return PW.BotBrain.Done("stim used") end
    return PW.BotBrain.Done("no stim")
end
