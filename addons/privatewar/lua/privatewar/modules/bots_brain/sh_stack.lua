-- Bots brain: per-bot state, the Action stack and the ctx (T-5.9; 07-bots.md d.5). Pure over plain data: the
-- behaviours, the bot and the blackboard come in an env, behaviour methods are called through PW.Call.
--
-- Decisions of the lane agent (to confirm):
--   5. Methods run on the shared definition (PW.Call disables it on error); per-run data is ctx.state, a table of
--      the frame, set only during OnStart, Update, OnEnd, OnSuspend and OnResume.
--   6. The selector switches the top: to a behaviour already suspended in the stack it pops down to it (OnEnd above,
--      OnResume); to a higher bucket it suspends the top (OnSuspend) and pushes; otherwise it replaces the top
--      (OnEnd, OnStart). The new top runs Update in the same tick. Depth is capped at 4: the bottom frame ends.
--   7. Transitions from Update: Continue; ChangeTo(id) replaces the top; SuspendFor(id) pushes over it; Done pops it
--      and resumes the frame below. A frame entered by a transition inherits the rank and weight of the frame that
--      started it while its own Rank does not make it a candidate. Its first Update is on the next tick. An unknown
--      id is ignored (the frame keeps running). Update returning no transition (an error included) is Done.
--   8. A frame that ends forgets its cached evaluation (re-evaluated next tick) and starts its Cooldown.
--   9. Sight nudge: an enemy that becomes visible (a visible contact that was not visible on the previous tick) drops
--      every cached evaluation, so the behaviours re-rank in this tick instead of after their interval (an
--      event wake-up on top of the 07 d.4 intervals). Losing sight is no event: the intervals handle it.

local lib = PW.BotBrain --[[@as PW.BotBrainLib]]

local epsilon = 1e-9

---@type table<string, function>
local ctxMethods = {}
local ctxMeta = { __index = ctxMethods }

---@param self PW.BotBrainCtx
function ctxMethods.Intent(self)
    local board = self.board
    local intent = board.intent
    if intent == nil then
        intent = { buttons = 0 }
        board.intent = intent
    end
    return intent
end

---@param self PW.BotBrainCtx
---@param point Vector
---@param radius number
---@param priority string
function ctxMethods.SetGoal(self, point, radius, priority)
    local fn = self._api.setGoal or (rawget(PW, "Bot") or {}).SetGoal
    if fn == nil then return false, nil end
    return fn(self.bot, point, radius, priority)
end

---@param self PW.BotBrainCtx
function ctxMethods.ClearGoal(self)
    local fn = self._api.clearGoal or (rawget(PW, "Bot") or {}).ClearGoal
    if fn ~= nil then fn(self.bot) end
end

---@param self PW.BotBrainCtx
function ctxMethods.GoalStatus(self)
    local goal = self.board.goal
    return goal ~= nil and goal.status or nil
end

---@param self PW.BotBrainCtx
---@param ent Entity?
function ctxMethods.SetTarget(self, ent)
    self.board.target = ent
    self.target = ent
    self:Intent().target = ent
end

---@param self PW.BotBrainCtx
---@param ent any
function ctxMethods.Contact(self, ent)
    return self.memory[ent]
end

---@param self PW.BotBrainCtx
---@param ent any
function ctxMethods.SearchPlan(self, ent)
    local fn = self._api.searchPlan or (rawget(PW, "Bot") or {}).GetSearchPlan
    if fn == nil then return nil end
    return fn(self.bot, ent)
end

local noApi = {}
local empty = {}

---@return PW.BotBrainState
function lib.NewState()
    local ctx = setmetatable({ contacts = empty, memory = empty, now = 0, _api = noApi }, ctxMeta)
    return { stack = {}, evals = {}, cooldowns = {}, sighted = {}, ctx = ctx --[[@as PW.BotBrainCtx]] }
end

---Remembers the visible contacts; drops the cached evaluations when one of them was not visible before (decision 9).
---@param state PW.BotBrainState
---@param contacts PW.BotContact[]
local function nudgeOnSight(state, contacts)
    local before = state.sighted or {}
    ---@type table<any, true>
    local now = {}
    local fresh = false
    for _, c in ipairs(contacts) do
        if c.visible then
            now[c.ent] = true
            fresh = fresh or before[c.ent] == nil
        end
    end
    state.sighted = now
    if fresh then state.evals = {} end
end

---@param state PW.BotBrainState
---@return string[]
function lib.StackIds(state)
    ---@type string[]
    local ids = {}
    for i, frame in ipairs(state.stack) do ids[i] = frame.id end
    return ids
end

---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param now number
local function refreshCtx(state, env, now)
    local ctx, board = state.ctx, env.board
    ctx.bot, ctx.board, ctx.now, ctx._api = env.bot, board, now, env.api or noApi
    ctx.order, ctx.goal, ctx.target = board.order, board.goal, board.target
    ctx.contacts, ctx.memory = board.contacts or empty, board.memory or empty
    local top = state.stack[#state.stack]
    ctx.running = top and top.id or nil
end

---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param frame PW.BotFrame
---@param method string
---@return any
local function callFrame(state, env, frame, method)
    local ctx = state.ctx
    ctx.state = frame.state
    local result = PW.Call(frame.def, method, env.bot, ctx)
    ctx.state = nil
    return result
end

---@param def PW.BotBehavior
---@param mode string?
---@return boolean
local function inMode(def, mode)
    local modes = def.Modes
    if modes == nil then return true end
    for _, id in ipairs(modes) do
        if id == mode then return true end
    end
    return false
end

---A usable weight: a finite number above 0, else 0 (nothing returned after an error, nil, NaN, infinity).
---@param ... any
---@return number
local function weightOf(...)
    local w = select("#", ...) > 0 and (...) or nil
    if not isnumber(w) or w ~= w or w <= 0 or w == math.huge then return 0 end
    return w --[[@as number]]
end

---Evaluates the due behaviours (their interval passed) and returns the candidates and the defs by id.
---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param now number
---@return PW.BotCandidateScore[] cands, table<string, PW.BotBehavior> byId
local function evaluate(state, env, now)
    ---@type PW.BotCandidateScore[]
    local cands = {}
    ---@type table<string, PW.BotBehavior>
    local byId = {}
    for _, def in ipairs(env.behaviors) do
        local id = def.ClassName
        if inMode(def, env.mode) then
            byId[id] = def
            local ev = state.evals[id]
            if ev == nil or now + epsilon >= ev.at + lib.IntervalOf(def) then
                local rank = lib.RankValue(PW.Call(def, "Rank", env.bot, state.ctx))
                local weight = rank ~= nil and weightOf(PW.Call(def, "Weight", env.bot, state.ctx)) or 0
                ev = { at = now, rank = rank, weight = weight }
                state.evals[id] = ev
            end
            local ready = (state.cooldowns[id] or -math.huge) <= now
            if ready and ev.rank ~= nil and ev.weight > 0 then
                cands[#cands + 1] = { id = id, rank = ev.rank, weight = ev.weight }
            end
        end
    end
    return cands, byId
end

---The running behaviour's score: its evaluation, else (entered by a transition) the inherited one; nil when it is
---no longer a candidate.
---@param state PW.BotBrainState
---@param byId table<string, PW.BotBehavior>
---@param now number
---@return PW.BotCurrentScore?
local function currentScore(state, byId, now)
    local top = state.stack[#state.stack]
    if top == nil or byId[top.id] == nil then return nil end
    local ev = state.evals[top.id]
    local locked = now - top.since < (tonumber(top.def.MinRun) or 0)
    if ev ~= nil and ev.rank ~= nil and ev.weight > 0 then
        return { id = top.id, rank = ev.rank, weight = ev.weight, locked = locked }
    end
    if top.via == "transition" then return { id = top.id, rank = top.rank, weight = top.weight, locked = locked } end
    return nil
end

---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param now number
local function endTop(state, env, now)
    local stack = state.stack
    local frame = stack[#stack]
    callFrame(state, env, frame, "OnEnd")
    stack[#stack] = nil
    state.evals[frame.id] = nil
    local cooldown = tonumber(frame.def.Cooldown) or 0
    if cooldown > 0 then state.cooldowns[frame.id] = now + cooldown end
end

---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param def PW.BotBehavior
---@param score { rank: number, weight: number }
---@param via "select"|"transition"
---@param reason string
---@param now number
local function push(state, env, def, score, via, reason, now)
    local stack = state.stack
    if #stack >= lib.Defaults.maxDepth then
        local bottom = table.remove(stack, 1)
        callFrame(state, env, bottom, "OnEnd")
        state.evals[bottom.id] = nil
    end
    ---@type PW.BotFrame
    local frame = { id = def.ClassName, def = def, state = {}, since = now, rank = score.rank, weight = score.weight,
        via = via, reason = reason }
    stack[#stack + 1] = frame
    state.ctx.running = frame.id
    callFrame(state, env, frame, "OnStart")
end

---Pops to a suspended frame, or suspends the top for a higher bucket, or replaces the top.
---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param def PW.BotBehavior
---@param cur PW.BotCurrentScore?
---@param reason string
---@param now number
local function switchTo(state, env, def, cur, reason, now)
    local stack, id = state.stack, def.ClassName
    for i = #stack - 1, 1, -1 do
        if stack[i].id == id then
            while #stack > i do endTop(state, env, now) end
            stack[i].reason = reason
            state.ctx.running = id
            callFrame(state, env, stack[i], "OnResume")
            return
        end
    end
    local ev = state.evals[id]
    local score = { rank = ev and ev.rank or 0, weight = ev and ev.weight or 0 }
    local top = stack[#stack]
    if top ~= nil and (cur == nil or score.rank <= cur.rank) then
        endTop(state, env, now)
    elseif top ~= nil then
        callFrame(state, env, top, "OnSuspend")
    end
    push(state, env, def, score, "select", reason, now)
end

---Pops the top and resumes the frame below.
---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param now number
local function finishTop(state, env, now)
    endTop(state, env, now)
    local below = state.stack[#state.stack]
    state.ctx.running = below and below.id or nil
    if below ~= nil then callFrame(state, env, below, "OnResume") end
end

---Applies what Update returned.
---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param result any
---@param byId table<string, PW.BotBehavior>
---@param now number
local function apply(state, env, result, byId, now)
    local t = istable(result) and result --[[@as PW.BotTransition]] or lib.Done("no transition")
    local top = state.stack[#state.stack]
    if t.kind == "continue" then return end
    if t.kind == "done" or (t.kind ~= "change" and t.kind ~= "suspend") then
        finishTop(state, env, now)
        local below = state.stack[#state.stack]
        if below ~= nil then below.reason = "resumed: " .. tostring(t.reason) end
        return
    end
    local def = isstring(t.id) and byId[t.id] or nil
    if def == nil then
        top.reason = "unknown behaviour " .. tostring(t.id)
        return
    end
    local inherited = { rank = top.rank, weight = top.weight }
    if t.kind == "change" then
        endTop(state, env, now)
    else
        callFrame(state, env, top, "OnSuspend")
    end
    push(state, env, def, inherited, "transition", tostring(t.reason), now)
end

---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
local function writeDebug(state, env)
    local board = env.board
    local top = state.stack[#state.stack]
    if top == nil then
        board.behavior = nil
    else
        local current = board.behavior
        if current == nil or current.id ~= top.id or current.reason ~= top.reason then
            board.behavior = { id = top.id, reason = top.reason }
        end
    end
    local debugInfo = (board.debug or {}) --[[@as table<string, any>]]
    board.debug = debugInfo
    debugInfo.brain = { scores = state.evals, stack = lib.StackIds(state), reason = top and top.reason or "idle" }
end

---Selection: keeps, switches, or ends an ineligible top when nothing else is a candidate.
---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param now number
---@return table<string, PW.BotBehavior> byId
local function selectTop(state, env, now)
    local cands, byId = evaluate(state, env, now)
    local cur = currentScore(state, byId, now)
    local chosen, reason = lib.Choose(cands, cur, {
        screen = env.screen or lib.Defaults.screen, bonus = env.bonus or lib.Defaults.bonus, random = env.random
    })
    local top = state.stack[#state.stack]
    if chosen == nil then
        if top ~= nil and cur == nil then finishTop(state, env, now) end
    elseif top == nil or chosen ~= top.id then
        switchTo(state, env, byId[chosen], cur, reason, now)
    end
    return byId
end

---Decision 10 (T-11.6): the legs fields a behaviour owns (sprint, direct drive, slide) belong to the top frame; when
---another frame becomes the top they are cleared, so a sprint or a strafe never outlives the behaviour that set it.
---@param state PW.BotBrainState
---@param board PW.BotBoard
local function releaseLegs(state, board)
    local top = state.stack[#state.stack]
    local id = top and top.id or nil
    if id == state.legsOf then return end
    state.legsOf = id
    local intent = board.intent
    if intent ~= nil then intent.sprint, intent.drive, intent.slideAt = nil, nil, nil end
end

---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param now number
function lib.Think(state, env, now)
    refreshCtx(state, env, now)
    nudgeOnSight(state, state.ctx.contacts)
    local byId = selectTop(state, env, now)
    releaseLegs(state, env.board)
    local top = state.stack[#state.stack]
    if top ~= nil then apply(state, env, callFrame(state, env, top, "Update"), byId, now) end
    writeDebug(state, env)
end

---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@param now number
---@param reason string
function lib.Stop(state, env, now, reason)
    refreshCtx(state, env, now)
    while #state.stack > 0 do
        state.stack[#state.stack].reason = reason
        endTop(state, env, now)
    end
    state.ctx.running = nil
    writeDebug(state, env)
end
