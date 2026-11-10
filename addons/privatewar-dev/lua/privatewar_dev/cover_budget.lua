-- Explicitly included, passive dev capture. No wrappers, extra traces or AI writes.
-- Queue timestamps are frame-sampled estimates; jobs born and retired between samples are unobserved.
---@class PWDev.CoverBudgetProbe
---@field Start fun(tag: string, seconds: number)
---@field Stop fun(): string?
local probe = {}
local key = "PW.Dev.CoverBudget"
---@class PWDev.CoverBotSample
---@field commands integer
---@field zeroCommandSeconds number
---@field zeroVelocitySeconds number
---@field behaviors table<string, integer>
---@field initial number[]
---@field firstMelee? number
---@class PWDev.CoverRun
---@field tag string
---@field map string
---@field started number
---@field wallStarted number
---@field deadline number
---@field bots table<string, PWDev.CoverBotSample>
---@field jobs {kind: string, wait: number}[]
---@field pending? table<integer, {kind: string, at: number}>
---@field maxQueued number
---@field navStart PW.NavCounters
---@field navEnd? PW.NavCounters
---@field schedulerStart PW.BotSchedulerCounters
---@field schedulerEnd? PW.BotSchedulerCounters
---@field elapsed? number
---@field wallElapsed? number
---@type PWDev.CoverRun?
local run

---@param job function
---@return string
local function kind(job)
    local info = debug.getinfo(job, "S")
    local source = info ~= nil and info.short_src or ""
    if source:find("bots_tactics", 1, true) then return "cover" end
    if source:find("bots_nav", 1, true) then return "path" end
    return "other"
end

---@param current PWDev.CoverRun
local function sampleQueue(current)
    local state = PW._BotSchedulerState
    local pending = assert(current.pending)
    for index, entry in pairs(pending) do
        if index < state.jobHead then
            current.jobs[#current.jobs + 1] = { kind = entry.kind, wait = SysTime() - entry.at }
            pending[index] = nil
        end
    end
    for index = state.jobHead, state.jobTail do
        if pending[index] == nil then
            pending[index] = { kind = kind(state.jobs[index]), at = SysTime() }
        end
    end
    current.maxQueued = math.max(current.maxQueued, state.jobTail - state.jobHead + 1)
end

function probe.Stop()
    local current = run
    if current == nil then return nil end
    sampleQueue(current)
    run = nil
    hook.Remove("Think", key)
    hook.Remove("SetupMove", key)
    hook.Remove("PW_CanTakeDamage", key)
    local service = assert(PW.BotNav.Service())
    current.navEnd, current.schedulerEnd = service.GetCounters(), assert(PW.BotScheduler).GetCounters()
    current.elapsed, current.wallElapsed = CurTime() - current.started, SysTime() - current.wallStarted
    current.pending = nil
    local path = "privatewar_dev/cover_budget_" .. current.tag .. ".json"
    file.CreateDir("privatewar_dev")
    file.Write(path, assert(util.TableToJSON(current)))
    print("[PW] coverbudget stopped " .. path)
    return path
end

---@param bot Player
---@param move CMoveData
local function sampleMove(bot, move)
    local current = run
    if current == nil or not bot:Alive() or PW.Infection.Role(bot) ~= "infected" or not bot:IsBot() then return end
    local row = current.bots[tostring(bot:UserID())]
    if row == nil then return end -- only the initially measured cohort
    row.commands = row.commands + 1
    if math.abs(move:GetForwardSpeed()) + math.abs(move:GetSideSpeed()) <= 1 then
        row.zeroCommandSeconds = row.zeroCommandSeconds + engine.TickInterval()
    end
    if bot:GetVelocity():Length2D() <= 1 then
        row.zeroVelocitySeconds = row.zeroVelocitySeconds + engine.TickInterval()
    end
    local board = assert(PW.Bot).Get(bot)
    local behavior = board ~= nil and board.behavior ~= nil and board.behavior.id or "none"
    row.behaviors[behavior] = (row.behaviors[behavior] or 0) + 1
end

function probe.Start(tag, seconds)
    assert(run == nil and tag:match("^[%w_-]+$") ~= nil)
    local service = assert(PW.BotNav.Service())
    ---@type PWDev.CoverRun
    local current = { tag = tag, map = game.GetMap(), started = CurTime(), wallStarted = SysTime(),
        deadline = CurTime() + math.Clamp(seconds, 1, 30), bots = {}, jobs = {}, pending = {}, maxQueued = 0,
        navStart = service.GetCounters(), schedulerStart = assert(PW.BotScheduler).GetCounters() }
    for _, bot in ipairs(player.GetBots()) do
        if PW.Infection.Role(bot) == "infected" then
            current.bots[tostring(bot:UserID())] = { commands = 0, zeroCommandSeconds = 0,
                zeroVelocitySeconds = 0, behaviors = {}, initial = { bot:GetPos():Unpack() } }
        end
    end
    run = current
    hook.Add("SetupMove", key, sampleMove)
    hook.Add("PW_CanTakeDamage", key, function(victim, attacker, damage)
        ---@cast damage CTakeDamageInfo
        if run ~= current or not IsValid(victim) or not victim:IsPlayer()
            or PW.Infection.Role(victim) ~= "survivor" then return end
        if not IsValid(attacker) or not attacker:IsPlayer() then return end
        local row = current.bots[tostring(attacker:UserID())]
        if row == nil or row.firstMelee ~= nil then return end
        local wep = damage:GetInflictor()
        if IsValid(wep) and wep:IsWeapon() and wep:GetClass() == "weapon_fists"
            and wep:GetOwner() == attacker and attacker:GetActiveWeapon() == wep
            and PW.Infection.Role(attacker) == "infected" and damage:GetDamage() > 0 then
            row.firstMelee = CurTime() - current.started
        end
    end)
    hook.Add("Think", key, function()
        sampleQueue(current)
        if CurTime() >= current.deadline then probe.Stop() end
    end)
    print("[PW] coverbudget started " .. tag)
end

return probe
