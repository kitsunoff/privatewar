-- The runner owns cleanup, independently of handler validity and optional handler cleanup success.
local lib = assert(PW.BotObjectives)

local fields = { "drive", "sprint", "stance" }

---@param ctx PW.BotBrainCtx
---@param visit PW.ObjectiveVisit
---@return boolean
local function owns(ctx, visit)
    return rawequal(ctx.board._behaviorOwner, visit.owner) and rawequal(ctx.board.intent, visit.intent)
end

---@param ctx PW.BotBrainCtx
---@param visit PW.ObjectiveVisit
---@param afterCall? boolean
local function capture(ctx, visit, afterCall)
    if not owns(ctx, visit) then return end
    local intent = visit.intent --[[@as table<string, any>]]
    for _, field in ipairs(fields) do
        if visit.owned[field] or not rawequal(intent[field], visit.baseline[field]) then
            visit.owned[field], visit.values[field] = true, intent[field]
        end
    end
    local use = bit.band(intent.buttons or 0, IN_USE) ~= 0
    if visit.owned.use or use ~= visit.baseline.use then visit.owned.use, visit.values.use = true, use end
    -- Injected contexts may supply their own goal/target methods instead of the brain's recording methods.
    if afterCall and visit.goal == nil and not rawequal(ctx.board.goal, visit.initialGoal) then
        visit.goal = ctx.board.goal
    end
    if afterCall and visit.look == nil and isvector(ctx.board.target)
        and not rawequal(ctx.board.target, visit.initialLook) then
        visit.look = ctx.board.target --[[@as Vector]]
    end
end

---@param ctx PW.BotBrainCtx
---@param visit PW.ObjectiveVisit
local function release(ctx, visit)
    if not owns(ctx, visit) then return end
    local intent = visit.intent --[[@as table<string, any>]]
    if visit.owned.use and visit.values.use then
        intent.buttons = bit.band(intent.buttons or 0, bit.bnot(IN_USE))
    end
    for _, field in ipairs(fields) do
        if visit.owned[field] and rawequal(intent[field], visit.values[field]) then
            intent[field] = field == "stance" and "stand" or nil
        end
    end
    local look = visit.look
    if look ~= nil then
        if rawequal(ctx.board.target, look) then ctx.board.target = nil end
        if rawequal(ctx.target, look) then ctx.target = nil end
        if rawequal(intent.target, look) then intent.target = nil end
    end
    if visit.goal ~= nil and rawequal(ctx.board.goal, visit.goal) then ctx:ClearGoal() end
end

---@param ctx PW.BotBrainCtx
---@param target PW.BotObjective
---@param state PW.ObjectiveFrameState
---@param handler PW.ObjectiveAction
---@return PW.ObjectiveVisit
local function newVisit(ctx, target, state, handler)
    local intent = ctx:Intent()
    ctx.board._behaviorOwner = state
    return { handler = handler, target = target, state = {}, owner = state, intent = intent,
        id = target.id, action = target.action, revision = target.revision,
        initialGoal = ctx.board.goal, initialLook = ctx.board.target, values = {}, owned = {},
        baseline = { drive = intent.drive, sprint = intent.sprint, stance = intent.stance,
            use = bit.band(intent.buttons or 0, IN_USE) ~= 0 } }
end

function lib.EndAction(ctx)
    local st = ctx.state --[[@as PW.ObjectiveFrameState?]]
    if st == nil then return end
    local visit = st ~= nil and st.visit or nil
    if visit == nil or visit.ending then return end
    visit.ending = true -- recursive EndAction is a no-op; context setters can still record cleanup writes
    capture(ctx, visit)
    release(ctx, visit) -- release before a callback can hand control to another frame or reset the board
    PW.Call(visit.handler, "OnEnd", ctx.bot, ctx, visit.target, visit.state)
    capture(ctx, visit, true)
    release(ctx, visit) -- a failed callback cannot retain outputs, but cannot erase a newer owner's outputs either
    if st.visit == visit then st.visit = nil end
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

---@param ctx PW.BotBrainCtx
---@param action string
---@param reason string
local function abortRequired(ctx, action, reason)
    if not SERVER or PW._Match.dependencies == nil or not lib.Facts(ctx).authoritative then return end
    assert(PW.Match).Abort(string.format("mode dependency failed: objective action %q %s", action, reason))
end

---@param ctx PW.BotBrainCtx
---@param target PW.BotObjective
---@return boolean
local function declared(ctx, target)
    if not SERVER or PW._Match.dependencies == nil or not lib.Facts(ctx).authoritative then return true end
    local ids = PW._Match.dependencies.objective_actions
    if ids ~= nil and ids[target.action] ~= nil then return true end
    lib.EndAction(ctx)
    abortRequired(ctx, target.action, "was not declared in mode dependencies")
    return false
end

function lib.RunAction(ctx, target)
    local st = ctx.state --[[@as PW.ObjectiveFrameState?]]
    local mode = PW.ActiveMode
    if st == nil then return assert(PW.BotBrain).Done("objective state unavailable") end
    if st.visit ~= nil and st.visit.ending then return assert(PW.BotBrain).Done("objective visit closing") end
    if not eligible(ctx, target) then
        lib.EndAction(ctx)
        return assert(PW.BotBrain).Done("objective ineligible")
    end
    if not declared(ctx, target) then return assert(PW.BotBrain).Done("undeclared objective action") end
    local handler = definition(ctx, target)
    if not available(handler) then
        lib.EndAction(ctx)
        abortRequired(ctx, target.action, "unavailable")
        return assert(PW.BotBrain).Done("objective action unavailable")
    end
    ---@cast handler PW.ObjectiveAction
    local hadVisit = st.visit ~= nil
    if st.visit ~= nil and not same(st.visit, target) then lib.EndAction(ctx) end
    if PW.ActiveMode ~= mode then return assert(PW.BotBrain).Done("mode ended during action cleanup") end
    if hadVisit and ctx.board._behaviorOwner ~= st then
        lib.EndAction(ctx)
        return assert(PW.BotBrain).Done("objective output ownership changed")
    end
    local fresh = st.visit == nil
    if fresh then
        st.visit = newVisit(ctx, target, st, handler)
    end
    local visit = st.visit --[[@as PW.ObjectiveVisit]]
    st.id, st.revision, st.action = target.id, target.revision, target.action
    visit.target = target
    if fresh then PW.Call(handler, "OnStart", ctx.bot, ctx, target, visit.state) end
    local result = available(handler) and st.visit == visit and owns(ctx, visit)
        and PW.Call(handler, "Update", ctx.bot, ctx, target, visit.state) or nil
    if st.visit == visit then capture(ctx, visit, true) end
    if available(handler) and st.visit == visit and owns(ctx, visit) and (not istable(result)
        or (result.kind ~= "continue" and result.kind ~= "done")) then
        local registry = handler._Registry
        if registry ~= nil then registry._Disable(handler.ClassName, "invalid objective action transition") end
    end
    if not istable(result) or not isstring(result.kind) or not available(handler) or st.visit ~= visit
        or not owns(ctx, visit) then
        lib.EndAction(ctx)
        return assert(PW.BotBrain).Done("objective action failed")
    end
    if result.kind ~= "continue" then lib.EndAction(ctx) end
    return result
end
