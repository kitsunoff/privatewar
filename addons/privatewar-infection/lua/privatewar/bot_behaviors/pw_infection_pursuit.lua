BEHAVIOR.Modes = { "pw_infection" }
BEHAVIOR.Interval = 0.1
BEHAVIOR.MinRun = 0

local ai = PW.InfectionAI --[[@as PW.InfectionAILib]]
local lib = PW.Infection --[[@as PW.InfectionLib]]

---@param bot Player
---@param ctx PW.BotBrainCtx
function BEHAVIOR:Rank(bot, ctx)
    return lib.Role(bot) == "infected" and ai.Contact(ctx.contacts) ~= nil and "combat" or false
end

function BEHAVIOR:Weight() return 2 end

---@param bot Player
---@param ctx PW.BotBrainCtx
function BEHAVIOR:Update(bot, ctx)
    local contact = ai.Contact(ctx.contacts)
    if contact == nil or lib.Role(bot) ~= "infected" then return assert(PW.BotBrain).Done("contact lost") end
    local plan = ai.Plan(bot:GetPos(), contact, bot:GetWalkSpeed())
    local intent = ctx:Intent()
    intent.weapon, intent.stance, intent.sprint = "weapon_fists", "stand", plan.sprint
    if plan.point ~= nil then
        ctx:SetTarget(nil)
        intent.drive = nil
        ctx:SetGoal(plan.point, 32, "tactical")
    else
        ctx:ClearGoal()
        ctx:SetTarget(plan.target)
        intent.drive = Vector(plan.forward, 0, 0)
    end
    return assert(PW.BotBrain).Continue()
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    ctx:SetTarget(nil)
    ctx:ClearGoal()
    local intent = ctx:Intent()
    intent.drive, intent.sprint, intent.weapon = nil, nil, nil
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnSuspend(bot, ctx) self:OnEnd(bot, ctx) end
