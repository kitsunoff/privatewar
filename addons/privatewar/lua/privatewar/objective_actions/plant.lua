-- An ordinary held-use input; the mode alone validates progress and decides the outcome.
---@param _ Player
---@param ctx PW.BotBrainCtx
---@param target PW.BotObjective
---@return PW.BotTransition
function OBJECTIVEACTION:Update(_, ctx, target)
    local lib, brain, commander = assert(PW.BotObjectives), assert(PW.BotBrain), PW.BotCommander
    local intent = ctx:Intent()
    intent.buttons = bit.band(intent.buttons or 0, bit.bnot(IN_USE))
    if commander == nil or not IsValid(ctx.bot) or not ctx.bot:Alive() then
        return brain.Done("interaction unavailable")
    end
    local goal = ctx.board.goal
    if goal ~= nil and not lib.ValidateGoal(ctx, target) then
        return brain.Done("projected outside interaction zone")
    end
    if not commander.Inside(target, lib.Facts(ctx).pos) then
        ctx:SetGoal(target.pos, math.min(target.radius * 0.25, 16), "objective")
        lib.ValidateGoal(ctx, target)
        return brain.Continue()
    end
    ctx:ClearGoal()
    lib.LookAt(ctx, target.pos + Vector(0, 0, 16))
    intent.sprint, intent.drive = false, nil
    intent.buttons = bit.bor(intent.buttons or 0, IN_USE)
    return brain.Continue()
end
