-- Built-in behaviour: idle (T-5.9). The fallback of the roam bucket with a low weight, so any real behaviour wins:
-- it releases the buttons and stands where the bot is (the goal follower keeps a goal another layer set).
BEHAVIOR.Interval = 1

---@return PW.BotRank
function BEHAVIOR:Rank()
    return "roam"
end

---@return number
function BEHAVIOR:Weight()
    return 0.01
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnStart(_, ctx)
    local intent = ctx:Intent()
    intent.buttons, intent.stance = 0, "stand"
end

---@return PW.BotTransition
function BEHAVIOR:Update()
    return PW.BotBrain.Continue()
end
