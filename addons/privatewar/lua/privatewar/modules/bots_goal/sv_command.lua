-- Bots goal, the dev command (T-5.6; included by init.lua). pw_bot_goto <bot name|*> here | <x> <y> <z> | clear |
-- status, then [radius] [priority]: sends bots to a point through the public goal API. Privilege pw.bots.debug
-- (default superadmin); the server console (and the Deck bridge) may always use it. status also draws the remaining
-- path for 5 s with debugoverlay (visible to the listen server host with developer 1).

local lib = PW.BotGoal --[[@as PW.BotGoalLib]]

---@param line string
local function printLine(line)
    print("[PW] " .. line)
end

---@param bot Player
---@return string
local function describe(bot)
    local board = lib.BoardOf(bot)
    if board == nil then return "not a managed bot" end
    local goal, path = board.goal, board.path
    if goal == nil then return "no goal" end
    local where = ""
    if path ~= nil then
        where = string.format(", waypoint %d/%d%s", path.index, #path.points, path.partial and " (partial)" or "")
    end
    return string.format("%s to %s (%s, radius %g)%s%s", goal.status, tostring(goal.point), goal.priority,
        goal.radius, goal.reason ~= nil and (", reason " .. goal.reason) or "", where)
end

---Draws the remaining path for 5 s (debugoverlay: visible to the listen server host with developer 1).
---@param bot Player
local function drawPath(bot)
    local board = lib.BoardOf(bot)
    local path = board ~= nil and board.path or nil
    if path == nil then return end
    local from = bot:GetPos()
    for i = path.index, #path.points do
        debugoverlay.Line(from, path.points[i], 5, Color(0, 255, 0), true)
        from = path.points[i]
    end
end

---@param bot Player
---@param parsed PW.BotGotoArgs
---@param point Vector?
---@return string
local function applyGoto(bot, parsed, point)
    if parsed.mode == "clear" then
        lib.ClearGoal(bot)
        return "cleared"
    end
    if parsed.mode == "status" then
        drawPath(bot)
        return describe(bot)
    end
    if point == nil or lib.BoardOf(bot) == nil then return "not a managed bot" end
    local accepted, status = lib.SetGoal(bot, point, parsed.radius, parsed.priority)
    return string.format("%s, %s", accepted and "accepted" or "refused", tostring(status))
end

---@param nick string
---@param pattern string
---@return boolean
local function nameMatches(nick, pattern)
    if pattern == "*" then return true end
    return string.find(string.lower(nick), string.lower(pattern), 1, true) ~= nil
end

function lib._Command(ply, args, out)
    out = out or printLine
    if ply ~= nil and IsValid(ply) and not PW.Can(ply, lib.Privilege) then
        out(string.format("pw_bot_goto denied for %s", ply:Nick()))
        return 0
    end
    local parsed, err = lib.ParseGotoArgs(args)
    if parsed == nil then
        out(err or "usage: pw_bot_goto <bot name|*> here|<x> <y> <z>|clear|status [radius] [priority]")
        return 0
    end
    local point = parsed.point
    if parsed.mode == "here" then
        if ply == nil then
            out("pw_bot_goto here needs a player; from the console give x y z")
            return 0
        end
        point = ply:GetEyeTrace().HitPos
    end
    local count = 0
    for _, bot in ipairs(player.GetBots()) do
        if nameMatches(bot:Nick(), parsed.pattern) then
            count = count + 1
            out(string.format("pw_bot_goto: %s %s", bot:Nick(), applyGoto(bot, parsed, point)))
        end
    end
    if count == 0 then out(string.format("pw_bot_goto: no bot matches %q", parsed.pattern)) end
    return count
end

concommand.Add("pw_bot_goto", function(ply, _, args) lib._Command(IsValid(ply) and ply or nil, args) end, nil,
    "Private War: send bots to a point (<bot name|*> here | <x> <y> <z> | clear | status, then [radius]"
        .. " [hunt|guard|objective|tactical|critical]); needs pw.bots.debug")
