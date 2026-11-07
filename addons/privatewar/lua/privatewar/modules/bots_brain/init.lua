-- Bots brain, server glue (T-5.9). Registers every managed bot in the bot scheduler at 10 Hz under the id
-- "brain:<UserID>" and runs one brain tick (PW.BotBrain.Think) over the enabled behaviours of the bot_behaviors kind.
-- Also installs the transition constructors on PW.Bot (PW.Bot.Continue, ChangeTo, SuspendFor, Done).
--
-- Decisions of the lane agent (to confirm):
--   9. A dead bot ends its whole stack (OnEnd top first, reason "dead") and thinks again once it is alive. A bot
--      that is no longer managed ends its stack and unregisters.
--  10. decision_screen and commitment_bonus come from the bot's difficulty entity (the regular tier when
--      it has none; T-5.12), else the defaults. Randomness: math.random until the core has its own AI PRNG
--      (adapter.md rule 4).
--  11. Debug data (board.behavior, board.debug.brain) is written on every brain tick; the overlay ConVar is T-5.4.

local lib = PW.BotBrain --[[@as PW.BotBrainLib]]

local tickPeriod, syncEvery = 0.1, 1

PW._BotBrain = rawget(PW, "_BotBrain") or {
    states = setmetatable({}, { __mode = "k" }), registered = setmetatable({}, { __mode = "k" })
}
local store = PW._BotBrain

local botLib = (rawget(PW, "Bot") or {}) --[[@as PW.BotLib]]
PW.Bot = botLib
botLib.Continue, botLib.ChangeTo, botLib.SuspendFor, botLib.Done = lib.Continue, lib.ChangeTo, lib.SuspendFor,
    lib.Done

local function randomFn()
    return math.random()
end

---@type { at: number, list: PW.BotBehavior[] }
local cache = { at = -1, list = {} }

---The enabled behaviours, read once per server tick.
---@param now number
---@return PW.BotBehavior[]
local function behaviors(now)
    if cache.at == now then return cache.list end
    local registry = rawget(PW, "BotBehaviors") --[[@as PW.Registry?]]
    cache.at = now
    cache.list = registry ~= nil and registry.GetEnabledList() --[[@as PW.BotBehavior[] ]] or {}
    return cache.list
end

---@return string?
local function modeId()
    local mode = rawget(PW, "ActiveMode") --[[@as table<string, any>?]]
    return mode ~= nil and mode.ClassName or nil
end

---@param ply Player
---@param board PW.BotBoard
---@param now number
---@return PW.BotBrainEnv
local function envFor(ply, board, now)
    local picked = PW.BotProfiles.Pick({ "decision_screen", "commitment_bonus" }, board.difficulty)
    return {
        bot = ply, board = board, behaviors = behaviors(now), random = randomFn, mode = modeId(),
        screen = tonumber(picked.decision_screen), bonus = tonumber(picked.commitment_bonus)
    }
end

---@param ply Player
---@return PW.BotBrainState
local function stateOf(ply)
    local state = store.states[ply]
    if state == nil then
        state = lib.NewState()
        store.states[ply] = state
    end
    return state
end

---@param ply Player
---@param board PW.BotBoard
---@param now number
local function tickBot(ply, board, now)
    local state = stateOf(ply)
    local env = envFor(ply, board, now)
    if ply:Alive() then
        lib.Think(state, env, now)
    elseif #state.stack > 0 then
        lib.Stop(state, env, now, "dead")
    end
end

local function stopAll()
    local now = CurTime()
    for ply, state in pairs(store.states) do
        local board = botLib.Get(ply)
        if board ~= nil then lib.Stop(state, envFor(ply, board, now), now, "relationships changed") end
    end
end

local function clearAll()
    for ply in pairs(store.states) do
        store.states[ply] = lib.NewState()
        local board = botLib.Get(ply)
        if board ~= nil then board.target, board.behavior, board.intent = nil, nil, { buttons = 0 } end
    end
end

function MODULE:PW_PlayerTeamChanging() stopAll() end
function MODULE:PW_RoundPreparing() stopAll() end
function MODULE:PW_PlayerTeamChanged() clearAll() end
function MODULE:PW_RoundPrepared() clearAll() end

---@param ply Player
local function register(ply)
    local scheduler = rawget(PW, "BotScheduler") --[[@as PW.BotSchedulerLib?]]
    if scheduler == nil then return end
    local id = "brain:" .. ply:UserID()
    store.registered[ply] = id
    -- The scheduler passes its own clock (SysTime); the brain runs on CurTime like the contacts, the goal and the aim.
    scheduler.Register(id, function()
        local now = CurTime()
        local board = IsValid(ply) and botLib.Get(ply) or nil
        if board == nil then
            scheduler.Unregister(id)
            local state = store.states[ply]
            if state ~= nil then lib.Stop(state, envFor(ply, { bot = ply }, now), now, "unmanaged") end
            store.registered[ply], store.states[ply] = nil, nil
            return
        end
        tickBot(ply, board, now)
    end, { period = tickPeriod })
end

---@type fun(): (fun(): integer?, Player?)
local players = player.Iterator

local nextSync = 0

PW.HookFor(MODULE, "Think", function()
    local now = CurTime()
    if now < nextSync or botLib.Get == nil then return end
    nextSync = now + syncEvery
    for _, entry in players() do
        local ply = entry --[[@as Player]]
        if ply:IsBot() and store.registered[ply] == nil and botLib.Get(ply) ~= nil then register(ply) end
    end
end)
