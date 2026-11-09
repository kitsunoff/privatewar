-- The runner owns cleanup, independently of handler validity and optional handler cleanup success.
local lib = assert(PW.BotObjectives)

---@param ctx PW.BotBrainCtx
local function release(ctx)
    local intent = ctx:Intent()
    intent.buttons = bit.band(intent.buttons or 0, bit.bnot(IN_USE))
    intent.sprint, intent.drive, intent.stance = false, nil, "stand"
    lib.LookAt(ctx, nil)
    ctx:ClearGoal()
end

function lib.EndAction(ctx)
    local st = ctx.state --[[@as PW.ObjectiveFrameState?]]
    local visit = st ~= nil and st.visit or nil
    if visit == nil then return end
    st.visit = nil -- detach before a cleanup callback can fail and synchronously abort the match
    PW.Call(visit.handler, "OnEnd", ctx.bot, ctx, visit.target, visit.state)
    release(ctx)
end

function lib.ValidateGoal(ctx, target)
    local goal, commander = ctx.board.goal, PW.BotCommander
    if target.zone == nil or goal == nil then return true end
    if commander ~= nil and goal.projected ~= nil and commander.ArrivalFits(target, goal.projected, goal.radius) then
        return true
    end
    ctx:ClearGoal()
    return false
end

---@param handler PW.ObjectiveAction?
---@return boolean
local function available(handler)
    return handler ~= nil and handler:IsValid() and not PW._Call.failed[handler]
end

---@param ctx PW.BotBrainCtx
---@param target PW.BotObjective
---@return boolean
local function eligible(ctx, target)
    if isentity(ctx.bot) and not IsValid(ctx.bot) then return false end
    if IsValid(ctx.bot) and isfunction(ctx.bot.Alive) and not ctx.bot:Alive() then return false end
    local id = IsValid(ctx.bot) and ctx.bot:UserID() or 0
    local commander = PW.BotCommander
    if commander ~= nil then return commander.Eligible(target, id) end
    return target.eligible == nil and target.action ~= "plant" and target.action ~= "defuse"
end

---@param visit PW.ObjectiveVisit
---@param target PW.BotObjective
---@return boolean
local function same(visit, target)
    return visit.id == target.id and visit.action == target.action and visit.revision == target.revision
end

---@param ctx PW.BotBrainCtx
---@param target PW.BotObjective
---@return PW.ObjectiveAction?
local function definition(ctx, target)
    local st = ctx.state --[[@as PW.ObjectiveFrameState?]]
    if st ~= nil and st.visit ~= nil and same(st.visit, target) then return st.visit.handler end
    if SERVER and PW.Match ~= nil and PW._Match.dependencies ~= nil
        and PW._Match.dependencies.objective_actions ~= nil then
        return PW.Match.Dependency("objective_actions", target.action) --[[@as PW.ObjectiveAction?]]
    end
    local registry = rawget(PW, "ObjectiveActions") --[[@as PW.Registry?]]
    return registry ~= nil and registry.Get(target.action) --[[@as PW.ObjectiveAction?]] or nil
end

function lib.RunAction(ctx, target)
    local st = ctx.state --[[@as PW.ObjectiveFrameState?]]
    local mode = PW.ActiveMode
    if st == nil then return assert(PW.BotBrain).Done("objective state unavailable") end
    if not eligible(ctx, target) then
        lib.EndAction(ctx)
        return assert(PW.BotBrain).Done("objective ineligible")
    end
    local handler = definition(ctx, target)
    if not available(handler) then
        lib.EndAction(ctx)
        return assert(PW.BotBrain).Done("objective action unavailable")
    end
    ---@cast handler PW.ObjectiveAction
    if st.visit ~= nil and not same(st.visit, target) then lib.EndAction(ctx) end
    if PW.ActiveMode ~= mode then return assert(PW.BotBrain).Done("mode ended during action cleanup") end
    local fresh = st.visit == nil
    if fresh then
        st.visit = { handler = handler, target = target, state = {},
            id = target.id, action = target.action, revision = target.revision }
    end
    local visit = st.visit --[[@as PW.ObjectiveVisit]]
    st.id, st.revision, st.action = target.id, target.revision, target.action
    visit.target = target
    if fresh then PW.Call(handler, "OnStart", ctx.bot, ctx, target, visit.state) end
    local result = available(handler) and st.visit == visit
        and PW.Call(handler, "Update", ctx.bot, ctx, target, visit.state) or nil
    if available(handler) and st.visit == visit and (not istable(result)
        or (result.kind ~= "continue" and result.kind ~= "done")) then
        local registry = handler._Registry
        if registry ~= nil then registry._Disable(handler.ClassName, "invalid objective action transition") end
    end
    if not istable(result) or not isstring(result.kind) or not available(handler) or st.visit ~= visit then
        lib.EndAction(ctx)
        return assert(PW.BotBrain).Done("objective action failed")
    end
    if result.kind ~= "continue" then lib.EndAction(ctx) end
    return result
end
