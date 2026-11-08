-- Bots goal API, server glue (T-5.6). Thin wrappers around the pure rules in shared.lua and sh_follow.lua:
--   SetGoal (PW.Bot.SetGoal and bot:SetGoal): arbitration, navmesh projection (an area within 256 units), the
--     blacklist, then a path request through PW.BotNav.RequestPath. The goal lives on the blackboard (`goal`, `path`).
--   Follower: one scheduler tick per bot with an active goal (period 0.1 s; the follower state table is the id). It
--     writes intent.move (relative to the current eye yaw), intent.viewTarget (the view toward a point 160 units
--     ahead) with intent.viewSpeed (the difficulty's turn_max_speed, 07 d.15) and its own IN_* bits in
--     intent.buttons (stuck rungs, +use on doors); the bits it added last tick are removed first. Not while the brain
--     has a target: then the aim owns the view (it writes intent.view and clears viewTarget). bots_input turns the
--     view toward viewTarget every tick by at most viewSpeed * tick interval, so the 10 Hz follower gives a smooth
--     view; a snap of 170 degrees in one tick turned bots away from an enemy before perception could see it
--     (lua/tests/privatewar/bots_engagement.lua). On a ladder the follower writes intent.view itself.
--   Doors: a trace 72 units along the look direction; a door is used once, the bot waits 0.75 s, uses it again after
--     1.5 s. Ladders: the navmesh graph of bots_nav has no ladder links, so paths never plan over a ladder; if the
--     bot is on one (MOVETYPE_LADDER) it looks up or down toward the next waypoint and walks forward.
--   pw_bot_goto: the dev command, in sv_command.lua.

local lib = PW.BotGoal --[[@as PW.BotGoalLib]]
local band, bor, bnot = bit.band, bit.bor, bit.bnot

PW.Privilege(lib.Privilege, "superadmin")

PW._BotGoal = PW._BotGoal or { states = setmetatable({}, { __mode = "k" }) }

local reach, lookAhead, projectRange, period = 32, 160, 256, 0.1
local maxAttempts, blacklistTtl, doorProbe, eyeHeight, requestTimeout = 4, 30, 72, 64, 5
local terminal = { arrived = true, failed = true, unreachable = true }

function lib.BoardOf(bot)
    local botLib = rawget(PW, "Bot") --[[@as PW.BotLib?]]
    if botLib == nil or botLib.Get == nil then return nil end
    return botLib.Get(bot)
end

function lib.Project(point)
    local area = navmesh.GetNearestNavArea(point, false, projectRange, false, true)
    if area == nil then return nil end
    return area:GetClosestPointOnArea(point) or area:GetCenter()
end

---@param bot Player
---@return PW.BotGoalState
local function stateFor(bot)
    local states = PW._BotGoal.states
    local st = states[bot]
    if st == nil then
        st = { bot = bot, stuck = lib.NewStuck(), door = {}, blacklist = lib.NewBlacklist(blacklistTtl),
            attempts = 0, retryAt = 0, requestedAt = 0, added = 0, registered = false, repathed = false }
        states[bot] = st
    end
    return st
end

---Writes the legs channel: move, view (nil keeps it), the walking view target (nil clears it; bots_input turns the
---view toward it every tick) and this module's own button bits.
---@param board PW.BotBoard
---@param st PW.BotGoalState
---@param move Vector?
---@param view Angle?
---@param buttons integer
---@param target Angle?
---@param speed number?
local function writeLegs(board, st, move, view, buttons, target, speed)
    local intent = board.intent
    if intent == nil then
        intent = { buttons = 0 }
        board.intent = intent
    end
    local base = band(intent.buttons or 0, bnot(st.added))
    st.added = band(buttons, bnot(base))
    intent.buttons = bor(base, buttons)
    intent.move = move
    if view ~= nil then intent.view = view end
    intent.viewTarget, intent.viewSpeed = target, target ~= nil and speed or nil
end

---@param st PW.BotGoalState
local function cancelPath(st)
    st.token = nil
    local handle = st.handle
    st.handle = nil
    local nav = rawget(PW, "BotNav") --[[@as PW.BotNavLib?]]
    if handle ~= nil and nav ~= nil and nav.Cancel ~= nil then nav.Cancel(handle) end
end

---@param st PW.BotGoalState
local function unregister(st)
    if not st.registered then return end
    st.registered = false
    PW.BotScheduler.Unregister(st)
end

---Ends the goal with a status; stops the legs and the tick.
---@param st PW.BotGoalState
---@param board PW.BotBoard
---@param status PW.BotGoalStatus
---@param reason? string
---@param blacklist? boolean
local function finish(st, board, status, reason, blacklist)
    local goal = board.goal
    if goal ~= nil then
        goal.status, goal.reason = status, reason
        if blacklist then st.blacklist.Add(lib.PointKey(goal.projected or goal.point)) end
    end
    cancelPath(st)
    board.path = nil
    writeLegs(board, st, nil, nil, 0)
    unregister(st)
end

---The waypoints of a finished path handle.
---@param handle PW.NavHandle
---@param final Vector
---@return Vector[]
local function waypoints(handle, final)
    local ids = handle.path or {}
    ---@type PW.BotGoalStep[]
    local steps = {}
    for i = 2, #ids do
        local prev, area = navmesh.GetNavAreaByID(ids[i - 1]), navmesh.GetNavAreaByID(ids[i])
        if prev ~= nil and area ~= nil then
            steps[#steps + 1] = { entry = area:GetClosestPointOnArea(prev:GetCenter()), center = area:GetCenter() }
        end
    end
    if handle.partial then
        local last = navmesh.GetNavAreaByID(ids[#ids] or -1)
        final = last ~= nil and last:GetCenter() or final
    end
    return lib.Waypoints(steps, final)
end

---@param st PW.BotGoalState
---@param token table
---@param handle PW.NavHandle
local function onPath(st, token, handle)
    if st.token ~= token or handle.status == "cancelled" then return end
    st.handle, st.token = nil, nil
    local board = IsValid(st.bot) and lib.BoardOf(st.bot) or nil
    local goal = board ~= nil and board.goal or nil
    if board == nil or goal == nil or terminal[goal.status] then return end
    if handle.status == "unreachable" then
        finish(st, board, "unreachable", "no path", true)
        return
    end
    local points = waypoints(handle, goal.projected or goal.point)
    board.path = { points = points, index = 1, partial = handle.partial }
    if st.repathed then
        lib.StuckRestartWindow(st.stuck, lib.Remaining(points, 1, st.bot:GetPos()))
    else
        lib.StuckReset(st.stuck)
    end
end

---@param st PW.BotGoalState
---@param board PW.BotBoard
---@param goal PW.BotGoal
---@param now number
local function requestPath(st, board, goal, now)
    local nav = rawget(PW, "BotNav") --[[@as PW.BotNavLib?]]
    if nav == nil or nav.RequestPath == nil or (nav.Service ~= nil and nav.Service() == nil) then
        finish(st, board, "failed", "no navmesh")
        return
    end
    if st.attempts >= maxAttempts then
        finish(st, board, "unreachable", "retries", true)
        return
    end
    st.attempts = st.attempts + 1
    goal.repaths = st.attempts - 1
    local token = {}
    st.token, st.requestedAt = token, now
    local handle = nav.RequestPath(st.bot:GetPos(), goal.projected or goal.point,
        function(h) onPath(st, token, h) end)
    if handle == nil then
        st.token = nil
        st.retryAt = now + lib.RetryDelay(st.attempts + 1)
    elseif not handle.done then
        st.handle = handle
    end
end

---@param st PW.BotGoalState
---@param board PW.BotBoard
---@param now number
local function repath(st, board, now)
    cancelPath(st)
    board.path = nil
    st.retryAt = now + lib.RetryDelay(st.attempts + 1)
end

---The difficulty's turn speed in degrees per second (the tier of bots.difficulty when the board has none).
---@param board PW.BotBoard
---@return number
local function turnSpeed(board)
    local tier = PW.Setting("bots.difficulty")
    local picked = PW.BotProfiles.Pick({ "turn_max_speed" }, board.difficulty, isstring(tier) and tier or nil)
    return tonumber(picked.turn_max_speed) or 360
end

---View angles from the eyes toward a ground point (at eye height above it): the target the walking view turns to.
---@param st PW.BotGoalState
---@param point Vector
---@return Angle
local function viewTargetToward(st, point)
    local ang = (point + Vector(0, 0, eyeHeight) - st.bot:EyePos()):Angle()
    return Angle(math.NormalizeAngle(ang.p), ang.y, 0)
end

---Whether a door is within doorProbe units of the eyes, toward a ground point.
---@param bot Player
---@param toward Vector
---@return boolean
local function doorAhead(bot, toward)
    local eye = bot:EyePos()
    local dir = toward - eye
    dir.z = 0
    if dir:IsZero() then return false end
    dir:Normalize()
    local tr = util.TraceLine({ start = eye, endpos = eye + dir * doorProbe, filter = bot })
    local ent = tr.Entity --[[@as Entity?]]
    if ent == nil or not IsValid(ent) then return false end
    return lib.IsDoorClass(ent:GetClass())
end

---The move of a stuck rung: its forward and side scales are along and across the direction to the target.
---@param f number move toward the target, forward part
---@param s number move toward the target, side part
---@param input PW.BotStuckInput
---@param speed number
---@return Vector
local function stuckMove(f, s, input, speed)
    local uf, us = f / speed, s / speed
    local a, b = input.forward, input.side
    return Vector((a * uf - b * us) * speed, (a * us + b * uf) * speed, 0)
end

---Buttons, move, view (ladder only) and walking view target of one follower tick; both are nil when the aim owns the
---view.
---@param st PW.BotGoalState
---@param path PW.BotPath
---@param pos Vector
---@param now number
---@return integer buttons
---@return Vector move
---@return Angle? view
---@return Angle? target
local function legsFor(st, path, pos, now)
    local bot = st.bot
    local target = path.points[path.index]
    local look = lib.LookAhead(path.points, path.index, pos, lookAhead)
    ---@type Angle?
    local view, viewTarget = nil, nil
    if bot:GetMoveType() == MOVETYPE_LADDER then
        view = lib.LadderView(pos, target)
    elseif lib.FollowerOwnsView(rawget(PW, "BotAim") --[[@as PW.BotAimLib?]], bot) then
        viewTarget = viewTargetToward(st, look)
    end
    local yaw = (view or bot:EyeAngles()).y
    local speed = bot:GetRunSpeed()
    local f, s = lib.MoveFor(pos, target, yaw, speed)
    local move, buttons = Vector(f, s, 0), 0
    local stuck = st.stuck
    local input = lib.StuckInput(lib.StuckLadder[stuck.level], now - stuck.levelSince, stuck.side)
    if input ~= nil then move, buttons = stuckMove(f, s, input, speed), input.buttons end
    local door = lib.DoorStep(st.door, now, doorAhead(bot, look))
    if door == "use" then
        buttons = bor(buttons, IN_USE)
    elseif door == "wait" then
        move = Vector(0, 0, 0)
    end
    return buttons, move, view, viewTarget
end

---@param st PW.BotGoalState
---@param board PW.BotBoard
---@param goal PW.BotGoal
---@param path PW.BotPath
---@param now number
local function follow(st, board, goal, path, now)
    local pos = st.bot:GetPos()
    path.index = lib.Advance(path.points, path.index, pos, reach)
    if path.index > #path.points then
        if not path.partial then
            path.index = #path.points
        else
            repath(st, board, now)
            return
        end
    end
    local action = lib.StuckStep(st.stuck, lib.Remaining(path.points, path.index, pos), now)
    if action == nil then st.repathed = false end
    if action == "give_up" then
        finish(st, board, "failed", "stuck", true)
        return
    end
    if action == "repath" and not st.repathed then
        st.repathed = true
        repath(st, board, now)
        return
    end
    local buttons, move, view, viewTarget = legsFor(st, path, pos, now)
    writeLegs(board, st, move, view, buttons, viewTarget, turnSpeed(board))
    goal.status = "moving"
end

---One follower tick of a bot (the scheduler calls it with the state as the id).
---@param st PW.BotGoalState
---@param now number
local function tick(st, now)
    local bot = st.bot
    local board = IsValid(bot) and lib.BoardOf(bot) or nil
    local goal = board ~= nil and board.goal or nil
    if board == nil or goal == nil or terminal[goal.status] then
        if board ~= nil then writeLegs(board, st, nil, nil, 0) end
        unregister(st)
        return
    end
    if not bot:Alive() then return finish(st, board, "failed", "died") end
    if lib.Arrived(bot:GetPos(), goal.projected or goal.point, goal.radius) then
        return finish(st, board, "arrived")
    end
    local path = board.path
    if path ~= nil then return follow(st, board, goal, path, now) end
    writeLegs(board, st, nil, nil, 0)
    if st.token ~= nil and now - st.requestedAt > requestTimeout then cancelPath(st) end
    if st.token == nil and now >= st.retryAt then requestPath(st, board, goal, now) end
end

---@param st PW.BotGoalState
local function register(st)
    if st.registered then return end
    st.registered = true
    -- The scheduler passes its own clock (SysTime); goal timing uses CurTime like the rest of the goal state.
    PW.BotScheduler.Register(st, function() tick(st, CurTime()) end, { period = period })
end

---A refused request for a blacklisted point: an active goal stays, a finished one is replaced by the refusal.
---@param board PW.BotBoard
---@param point Vector
---@param radius number
---@param priority PW.BotGoalPriority
---@param projected Vector?
---@return boolean, string
local function refuse(board, point, radius, priority, projected)
    local goal = board.goal
    if goal == nil or terminal[goal.status] then
        board.goal = { point = point, radius = radius, priority = priority, status = "unreachable", since = CurTime(),
            projected = projected, reason = "blacklisted" }
    end
    return false, "unreachable"
end

---@param st PW.BotGoalState
---@param board PW.BotBoard
---@param goal PW.BotGoal
local function start(st, board, goal)
    cancelPath(st)
    board.goal, board.path = goal, nil
    st.attempts, st.retryAt, st.repathed, st.door = 0, 0, false, {}
    lib.StuckReset(st.stuck)
    local projected = goal.projected
    if projected == nil then return finish(st, board, "unreachable", "off navmesh", true) end
    if lib.Arrived(st.bot:GetPos(), projected, goal.radius) then return finish(st, board, "arrived") end
    register(st)
    requestPath(st, board, goal, CurTime())
end

function lib.SetGoal(bot, point, radius, priority)
    assert(lib.PriorityValue(priority) ~= nil, "bots_goal: unknown priority " .. tostring(priority))
    local board = IsValid(bot) and lib.BoardOf(bot) or nil
    if board == nil then return false, nil end
    local current = board.goal
    local verdict = lib.Arbitrate(current, point, radius, priority)
    if current ~= nil and verdict == "reject" then return false, current.status end
    if current ~= nil and verdict == "same" then return true, current.status end
    local st = stateFor(bot)
    local projected = lib.Project(point)
    if st.blacklist.Has(lib.PointKey(projected or point)) then
        return refuse(board, point, radius, priority, projected)
    end
    ---@type PW.BotGoal
    local goal = { point = point, radius = radius, priority = priority, status = "moving", since = CurTime(),
        projected = projected, repaths = 0 }
    start(st, board, goal)
    return true, goal.status
end

function lib.ClearGoal(bot)
    local st = PW._BotGoal.states[bot]
    if st ~= nil then
        cancelPath(st)
        unregister(st)
    end
    local board = lib.BoardOf(bot)
    if board == nil then return end
    if st ~= nil then writeLegs(board, st, nil, nil, 0) end
    board.goal, board.path = nil, nil
end

function lib._Drop(bot)
    lib.ClearGoal(bot)
    PW._BotGoal.states[bot] = nil
end

local function clearAll()
    for bot in pairs(PW._BotGoal.states) do lib._Drop(bot) end
end

function MODULE:PW_PlayerTeamChanged() clearAll() end
function MODULE:PW_RoundPrepared() clearAll() end
function MODULE:PW_MatchEnd() clearAll() end

local botLib = (rawget(PW, "Bot") or {}) --[[@as PW.BotLib]]
PW.Bot = botLib
botLib.SetGoal = lib.SetGoal
botLib.ClearGoal = lib.ClearGoal

local playerMeta = FindMetaTable("Player") --[[@as table<string, any>]]
---@param self Player
---@param point Vector
---@param radius number
---@param priority PW.BotGoalPriority
---@return boolean, string?
playerMeta.SetGoal = function(self, point, radius, priority)
    return lib.SetGoal(self, point, radius, priority)
end

PW.HookFor(MODULE, "PlayerDeath", function(_, victim)
    local st = IsValid(victim) and PW._BotGoal.states[victim] or nil
    if st == nil then return end
    local board = lib.BoardOf(victim)
    local goal = board ~= nil and board.goal or nil
    if board ~= nil and goal ~= nil and not terminal[goal.status] then finish(st, board, "failed", "died") end
end)

PW.HookFor(MODULE, "PlayerDisconnected", function(_, ply)
    if PW._BotGoal.states[ply] ~= nil then lib._Drop(ply) end
end)

include("privatewar/modules/bots_goal/sv_command.lua")
