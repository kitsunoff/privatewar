-- Bots aim, the dev command (T-5.8; included by init.lua). pw_bot_aim <bot name|*> <player name|me> [tier] | clear |
-- status: aims bots at a player (CP-5c checks), optionally with the aim of another tier, clears the override, or
-- prints the aim state. Privilege pw.bots.debug, default superadmin; the server console (and the Deck bridge) may
-- always use it. "me" is the calling player.

local lib = PW.BotAim --[[@as PW.BotAimLib]]

---@param line string
local function printLine(line)
    print("[PW] " .. line)
end

---@param nick string
---@param pattern string
---@return boolean
local function matches(nick, pattern)
    if pattern == "*" then return true end
    return string.find(string.lower(nick), string.lower(pattern), 1, true) ~= nil
end

---@param pattern string
---@return Player[]
local function findBots(pattern)
    ---@type Player[]
    local found = {}
    for _, bot in ipairs(player.GetBots()) do
        if matches(bot:Nick(), pattern) then found[#found + 1] = bot end
    end
    return found
end

---@param ply Player?
---@param pattern string
---@return Player?
local function findTarget(ply, pattern)
    if string.lower(pattern) == "me" then return ply end
    for _, other in ipairs(player.GetAll()) do
        if pattern ~= "*" and matches(other:Nick(), pattern) then return other end
    end
    return nil
end

---@param bot Player
---@return string
local function status(bot)
    local s = (lib.GetState --[[@as fun(bot: Player): PW.BotAimState?]])(bot)
    if s == nil then return string.format("pw_bot_aim: %s has no target", bot:Nick()) end
    return string.format("pw_bot_aim: %s part=%s focus=%.2f err=%.2f tol=%.2f fire=%s blocked=%s", bot:Nick(),
        s.part, s.focus, s.err, s.tolerance, tostring(s.fire), tostring(s.blockedSince ~= nil))
end

function lib._Command(ply, args, out)
    out = out or printLine
    if ply ~= nil and IsValid(ply) and not PW.Can(ply, lib.Privilege) then
        out(string.format("pw_bot_aim denied for %s", ply:Nick()))
        return 0
    end
    local parsed, err = lib.ParseArgs(args)
    if parsed == nil then
        out(err or "")
        return 0
    end
    local target = nil
    if parsed.action == "target" then
        target = findTarget(ply, parsed.target or "")
        if target == nil then
            out(string.format("pw_bot_aim: no player matches %q", parsed.target or ""))
            return 0
        end
    end
    local bots = findBots(parsed.bots)
    local setTarget = lib.SetTarget --[[@as fun(bot: Player, target: Entity|Vector|nil, tier?: string)]]
    for _, bot in ipairs(bots) do
        if parsed.action == "status" then
            out(status(bot))
        elseif target ~= bot then
            setTarget(bot, target, parsed.tier)
            out(string.format("pw_bot_aim: %s -> %s%s", bot:Nick(), target ~= nil and target:Nick() or "cleared",
                parsed.tier ~= nil and (" as " .. parsed.tier) or ""))
        end
    end
    if #bots == 0 then out(string.format("pw_bot_aim: no bot matches %q", parsed.bots)) end
    return #bots
end

concommand.Add("pw_bot_aim", function(ply, _, args) lib._Command(IsValid(ply) and ply or nil, args) end, nil,
    "Private War: aim bots at a player (<bot name|*> <player name|me> [tier] | clear | status); needs pw.bots.debug")
