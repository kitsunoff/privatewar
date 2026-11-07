-- Bots goal API (T-5.6; 07-bots.md d.6; docs/api/bots-blackboard.md "Goal API"). A sub-module of `bots` in the nav
-- sub-lane: SetGoal(point, radius, priority) with typed priorities, the goal wrapper (navmesh projection, same-goal
-- caching, retry backoff, a per-bot blacklist of unreachable goals, a status string), the path follower and the
-- stuck ladder. Shared: the pure rules over plain data (this file and sh_follow.lua). Server glue: init.lua.
--
-- Decisions of the lane agent (to be confirmed):
--   1. Module: `bots_goal`, not inside `bots_nav` (the contract names bots_nav as the writer of `goal` and `path`;
--      this module is the same sub-lane, split off so bots_nav stays the pure path service).
--   2. Equal priority: the newer request wins (a behaviour re-targets its own goal); a request for the same point
--      (within 32 units) and radius is "same" and keeps the running path (the wrapper's cache).
--   3. A finished goal (arrived, failed, unreachable) never blocks: any priority replaces it.
--   4. Statuses: moving, arrived, failed, unreachable (PW.BotGoalStatus). Unreachable: the path service proved it, the
--      point has no navmesh area within 256 units, a partial path ran out three times, or it is blacklisted. Failed:
--      the stuck ladder gave up (also blacklisted), the bot died, no navmesh, or the bot itself is off the navmesh.
--   5. Blacklist: per bot, 64-unit cells of the projected point, 30 s. A blacklisted request leaves an active goal
--      untouched and returns false, "unreachable".
--   6. Stuck ladder (07 d.6 order): jump, crouch, back off, side step, repath, then give up. One rung per 1 s window
--      in which the remaining path length dropped by less than 24 units; progress drops back to 0. Progress is
--      measured toward the goal, so the back-off and side-step rungs never count as progress. The brief's order
--      (jump, strafe, crouch) differs from the design; the design wins.

MODULE.Name = "Bots goal"

local lib = (rawget(PW, "BotGoal") or {}) --[[@as PW.BotGoalLib]]
PW.BotProfiles.Reads("difficulty", "goal", { "turn_max_speed" }) -- the walking view turns no faster (07 d.15)
PW.BotGoal = lib

lib.Privilege = "pw.bots.debug"
lib.Priorities = { hunt = 1, guard = 2, objective = 3, tactical = 4, critical = 5 }
lib.StuckLadder = { "jump", "crouch", "back_off", "side_step", "repath", "give_up" }

local samePoint = 32
local cell = 64
local terminal = { arrived = true, failed = true, unreachable = true }

function lib.PriorityValue(priority)
    return lib.Priorities[priority]
end

function lib.Arbitrate(current, point, radius, priority)
    if current == nil or terminal[current.status] then return "new" end
    local wanted, held = lib.PriorityValue(priority) or 0, lib.PriorityValue(current.priority) or 0
    if wanted < held then return "reject" end
    if wanted == held and current.radius == radius and current.point:Distance(point) <= samePoint then
        return "same"
    end
    return "new"
end

function lib.PointKey(point)
    return string.format("%d:%d:%d", math.floor(point.x / cell), math.floor(point.y / cell),
        math.floor(point.z / cell))
end

function lib.NewBlacklist(ttl, clock)
    clock = clock or CurTime
    ---@type table<string, number>
    local expires = {}
    local function has(key)
        local at = expires[key]
        if at == nil then return false end
        if clock() < at then return true end
        expires[key] = nil
        return false
    end
    return {
        Add = function(key) expires[key] = clock() + ttl end,
        Has = has,
        Clear = function() expires = {} end,
        Count = function()
            local n = 0
            for key in pairs(table.Copy(expires)) do
                if has(key) then n = n + 1 end
            end
            return n
        end
    }
end

function lib.NewStuck()
    return { level = 0, anchorTime = 0, levelSince = 0, side = 1 }
end

function lib.StuckReset(state)
    state.level = 0
    state.anchor = nil
end

local epsilon = 1e-6

function lib.StuckRestartWindow(state, remaining)
    state.anchor = remaining
end

function lib.StuckStep(state, remaining, now, opts)
    local window = opts ~= nil and opts.window or 1
    local minProgress = opts ~= nil and opts.minProgress or 24
    if state.anchor == nil then
        state.anchor, state.anchorTime = remaining, now
        return lib.StuckLadder[state.level]
    end
    if now - state.anchorTime + epsilon < window then return lib.StuckLadder[state.level] end
    local progress = state.anchor - remaining
    state.anchor, state.anchorTime = remaining, now
    if progress >= minProgress then
        state.level = 0
        return nil
    end
    if state.level < #lib.StuckLadder then
        state.level = state.level + 1
        state.levelSince = now
        if lib.StuckLadder[state.level] == "side_step" then state.side = -state.side end
    end
    return lib.StuckLadder[state.level]
end

local jumpPress = 0.2

function lib.StuckInput(action, since, side)
    if action == "jump" then
        return { buttons = since < jumpPress and IN_JUMP or IN_DUCK, forward = 1, side = 0 }
    elseif action == "crouch" then
        return { buttons = IN_DUCK, forward = 1, side = 0 }
    elseif action == "back_off" then
        return { buttons = 0, forward = -1, side = 0 }
    elseif action == "side_step" then
        return { buttons = 0, forward = 0.3, side = side }
    end
    return nil
end

local doorWait, doorCooldown = 0.75, 1.5

function lib.DoorStep(state, now, doorAhead)
    if not doorAhead then return nil end
    if state.usedAt == nil or now - state.usedAt >= doorCooldown then
        state.usedAt = now
        return "use"
    end
    if now - state.usedAt < doorWait then return "wait" end
    return nil
end

---@type table<string, true>
local doorClasses = { prop_door_rotating = true, func_door = true, func_door_rotating = true }

function lib.IsDoorClass(class)
    return doorClasses[class] == true
end

function lib.FollowerOwnsView(aim, bot)
    local owns = aim ~= nil and aim.OwnsView or nil
    return owns == nil or owns(bot) ~= true
end

local usage = "usage: pw_bot_goto <bot name|*> here|<x> <y> <z>|clear|status [radius] [hunt|guard|objective|tactical"
    .. "|critical]"

---Reads [radius] [priority] from args[first..].
---@param args string[]
---@param first integer
---@param out PW.BotGotoArgs
---@return boolean
local function readTail(args, first, out)
    for i = first, #args do
        local value = args[i]
        local number = tonumber(value)
        if number ~= nil and number > 0 and i == first then
            out.radius = number
        elseif lib.PriorityValue(value) ~= nil then
            out.priority = value --[[@as PW.BotGoalPriority]]
        else
            return false
        end
    end
    return #args - first < 2
end

function lib.ParseGotoArgs(args)
    local pattern, second = args[1], args[2]
    if pattern == nil or second == nil then return nil, usage end
    ---@type PW.BotGotoArgs
    local out = { pattern = pattern, mode = "here", radius = 64, priority = "critical" }
    if (second == "clear" or second == "status") and #args == 2 then
        out.mode = second
        return out
    end
    local first = 3
    if second ~= "here" then
        local x, y, z = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
        if x == nil or y == nil or z == nil then return nil, usage end
        out.mode, out.point, first = "point", Vector(x, y, z), 5
    end
    if not readTail(args, first, out) then return nil, usage end
    return out
end

local followFile = "privatewar/modules/bots_goal/sh_follow.lua"
if SERVER then AddCSLuaFile(followFile) end
include(followFile)
