-- Bots debug overlay, server glue (T-5.4; 07-bots.md d.11). The ConVar pw_bot_debug (default 0), the privilege
-- pw.bots.debug (shared with pw_bot_aim and pw_bot_goto), and a Think hook that gives the pure sender (shared.lua:
-- Step) the engine: the bots, their blackboards, the scheduler counters and net.Send to the privileged clients.
-- pw_bot_debug is a server ConVar: only the server console, rcon and the listen-server host can change it.

local lib = PW.BotDebug --[[@as PW.BotDebugLib]]

PW.Privilege(lib.Privilege, "superadmin")
util.AddNetworkString(lib.Message)

local debugVar = CreateConVar("pw_bot_debug", "0", { FCVAR_DONTRECORD },
    "Private War: send the bot debug overlay data to clients with pw.bots.debug (1 on, 0 off)", 0, 1)

function lib.Enabled()
    return debugVar:GetBool()
end

---@param recipients Player[]
---@param snapshot PW.BotDebugSnapshot
local function send(recipients, snapshot)
    net.Start(lib.Message)
    lib.Encode(snapshot, { uint = net.WriteUInt, int = net.WriteInt, string = net.WriteString, bool = net.WriteBool })
    net.Send(recipients)
end

---@param ent Entity
---@return string
local function nameOf(ent)
    if ent:IsPlayer() then return (ent --[[@as Player]]):Nick() end
    return ent:GetClass()
end

---@return PW.BotLib?
local function botLib()
    local found = rawget(PW, "Bot") --[[@as PW.BotLib?]]
    if found == nil or found.Get == nil then return nil end
    return found
end

---@return Player[]
local function managedBots()
    ---@type Player[]
    local out = {}
    local api = botLib()
    if api == nil then return out end
    for _, bot in ipairs(player.GetBots()) do
        if api.Get(bot) ~= nil then out[#out + 1] = bot end
    end
    return out
end

---@type PW.BotDebugDeps
local deps = {
    enabled = lib.Enabled,
    players = player.GetHumans,
    can = function(ply) return PW.Can(ply, lib.Privilege) end,
    bots = managedBots,
    boardOf = function(bot)
        local api = botLib()
        return api ~= nil and api.Get(bot) or nil
    end,
    nameOf = nameOf,
    counters = function()
        local scheduler = rawget(PW, "BotScheduler") --[[@as PW.BotSchedulerLib?]]
        return scheduler ~= nil and scheduler.Default.GetCounters() or nil
    end,
    send = send
}

lib._State = lib._State or { nextAt = 0 }

PW.HookFor(MODULE, "Think", function()
    lib.Step(lib._State, SysTime(), deps)
end)
