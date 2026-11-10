-- Bots tactics, server glue (T-5.10). Thin wrappers around the pure helpers in shared.lua:
--   Facts: one scheduler tick per managed bot (period 0.2 s, id "tactics:<UserID>") writes board.tactics: health,
--     the magazine through the weapon adapter (GetClip, IsReloading, GetAmmoType), the last damage from an enemy,
--     lethal equipment left (PW.Equipment.Count when the equipment module exists, else 0) and the profile.
--   Cover search: while a threat is known, at most once per Config.coverEvery seconds per bot, one job in the global
--     FIFO of the scheduler (07 d.3: expensive jobs). It samples navmesh hiding spots and area centres near the bot
--     (navmesh.Find), scores them without traces, then traces the best few against the threat (at most 12 traces).
--   Damage: PostEntityTakeDamage remembers the time and the attacker of the last damage from an enemy (07 d.7).

local lib = PW.BotTactics --[[@as PW.BotTacticsLib]]
local cfg = lib.Config

local tickPeriod, syncEvery, coverEvery = 0.2, 1, 1.5
local maxCandidates, tracedCandidates, maxTraces = 40, 8, 12
local crouchEye, standEye, threatEye, stepHeight = 30, 62, 56, 120

local weak = { __mode = "k" }
PW._BotTactics = rawget(PW, "_BotTactics") or {
    hurt = setmetatable({}, weak), registered = setmetatable({}, weak), pending = setmetatable({}, weak)
}
local store = PW._BotTactics --[[@as PW.BotTacticsStore]]

local botLib = (rawget(PW, "Bot") or {}) --[[@as PW.BotLib]]
PW.Bot = botLib

---@param bot Player
---@return PW.BotBoard?
local function boardOf(bot)
    return botLib.Get ~= nil and botLib.Get(bot) or nil
end

-- These events invalidate relationships for every managed bot, even when the changed actor is human.
-- A queued callback retains its old token and cannot consume or overwrite a newer request.
local function resetOwned()
    store.hurt, store.pending = setmetatable({}, weak), setmetatable({}, weak)
    for _, bot in ipairs(player.GetBots()) do
        local board = boardOf(bot)
        if board ~= nil then board.tactics = nil end
    end
end

function MODULE:PW_PlayerTeamChanging() resetOwned() end
function MODULE:PW_PlayerTeamChanged() resetOwned() end
function MODULE:PW_RoundPreparing() resetOwned() end
function MODULE:PW_RoundPrepared() resetOwned() end
function MODULE:PW_MatchEnd() resetOwned() end

---@param bot Player
---@param f PW.BotCombatFacts
local function weaponFacts(bot, f)
    f.clip, f.capacity, f.reserve, f.reloading = -1, 0, 0, false
    local wep = bot:GetActiveWeapon()
    local adapters = rawget(PW, "Adapters") --[[@as PW.AdaptersLib?]]
    if not IsValid(wep) or adapters == nil then return end
    local clip = { adapters.CallFor(wep, "GetClip", wep) }
    f.clip, f.capacity = tonumber(clip[1]) or -1, tonumber(clip[2]) or 0
    f.reloading = adapters.CallFor(wep, "IsReloading", wep) == true
    local ammoType = tonumber(adapters.CallFor(wep, "GetAmmoType", wep))
    f.reserve = ammoType ~= nil and ammoType >= 0 and bot:GetAmmoCount(ammoType) or 0
end

local meleeHold = { melee = true, melee2 = true, knife = true, fist = true }

---The kind of a weapon: the catalogue's Kind (the adapters fill it), else melee by its hold type (T-11.6).
---@param wep Weapon
---@return string?
local function kindOf(wep)
    local registry = rawget(PW, "Weapons") --[[@as PW.Registry?]]
    local entry = registry ~= nil and registry.Get(wep:GetClass()) --[[@as table<string, any>?]] or nil
    if entry ~= nil and isstring(entry.Kind) then return entry.Kind end
    local hold = isfunction(wep.GetHoldType) and wep:GetHoldType() or nil
    return meleeHold[hold] and "melee" or nil
end

---The class of a melee weapon the bot carries (its loadout melee slot), nil without one.
---@param bot Player
---@return string?
local function meleeOf(bot)
    for _, wep in ipairs(bot:GetWeapons()) do
        if IsValid(wep) and kindOf(wep) == "melee" then return wep:GetClass() end
    end
    return nil
end

---Movement facts (T-11.6): speed, run speed, ground, crouch, the active weapon and the melee weapon.
---@param bot Player
---@param f PW.BotCombatFacts
local function moveFacts(bot, f)
    f.speed, f.runSpeed = bot:GetVelocity():Length2D(), bot:GetRunSpeed()
    f.onGround, f.crouching = bot:OnGround(), bot:Crouching()
    local wep = bot:GetActiveWeapon()
    f.active = IsValid(wep) and wep:GetClass() or nil
    f.melee = meleeOf(bot)
end

---@param bot Player
---@return integer
local function lethalCount(bot)
    local equipment = rawget(PW, "Equipment") --[[@as table<string, any>?]]
    local count = equipment ~= nil and equipment.Count or nil
    if not isfunction(count) then return 0 end
    return tonumber(count(bot, "lethal")) or 0
end

---@param board PW.BotBoard
---@return PW.BotProfile
local function profileOf(board)
    local tier = PW.Setting("bots.difficulty")
    return lib.ProfileFor(board.personality, board.difficulty, isstring(tier) and tier or nil)
end

function lib.Refresh(bot, board)
    local f = board.tactics
    if f == nil then
        f = { at = 0, pos = bot:GetPos(), health = 0, maxHealth = 0, clip = -1, capacity = 0, reserve = 0,
            reloading = false, lethal = 0, profile = lib.DefaultProfile }
        board.tactics = f
    end
    f.at, f.pos = CurTime(), bot:GetPos()
    f.health, f.maxHealth = bot:Health(), bot:GetMaxHealth()
    weaponFacts(bot, f)
    moveFacts(bot, f)
    local hurt = store.hurt[bot]
    f.hurtAt, f.attacker = hurt and hurt.at or nil, hurt and hurt.attacker or nil
    f.lethal = lethalCount(bot)
    f.profile = profileOf(board)
end

---Whether nothing solid is between two points (players do not count).
---@param from Vector
---@param to Vector
---@return boolean
local function clear(from, to)
    local tr = util.TraceLine({ start = from, endpos = to, mask = MASK_SHOT,
        filter = function(ent) return not (ent --[[@as Entity]]):IsPlayer() end })
    return tr.Fraction >= 0.99
end

---Hiding spots and area centres near the bot with their cheap score, best first.
---@param pos Vector
---@param threatPos Vector
---@return PW.BotCoverCandidate[]
local function candidates(pos, threatPos)
    ---@type PW.BotCoverCandidate[]
    local list = {}
    ---@param point Vector
    ---@param spot boolean
    local function add(point, spot)
        ---@type PW.BotCoverCandidate
        local cand = { pos = point, spot = spot }
        cand.pre = lib.PreScore(cand, pos, threatPos)
        if cand.pre ~= nil then list[#list + 1] = cand end
    end
    local areas = navmesh.Find(pos, cfg.coverRadius, stepHeight, stepHeight) --[[@as CNavArea[] ]]
    for _, area in ipairs(areas) do
        if #list >= maxCandidates then break end
        for _, spot in ipairs(area:GetHidingSpots() --[[@as Vector[] ]]) do add(spot, true) end
        add(area:GetCenter(), false)
    end
    table.sort(list, function(a, b) return (a.pre or 0) > (b.pre or 0) end)
    return list
end

---The cover search of one bot against a threat position (one FIFO job; at most maxTraces traces).
---@param pos Vector
---@param threatPos Vector
---@return PW.BotCover?
local function searchCover(pos, threatPos)
    local eye = threatPos + Vector(0, 0, threatEye)
    ---@type PW.BotCoverCandidate[]
    local traced = {}
    ---@type integer
    local traces = 0
    for i, cand in ipairs(candidates(pos, threatPos)) do
        if i > tracedCandidates or traces + 2 > maxTraces then break end
        local hidden = not clear(cand.pos + Vector(0, 0, crouchEye), eye)
        cand.hidden, cand.open = hidden, not hidden
        if hidden then cand.standOpen = clear(cand.pos + Vector(0, 0, standEye), eye) end
        traces = traces + (hidden and 2 or 1)
        traced[#traced + 1] = cand
    end
    return lib.PickCover(traced, threatPos, CurTime())
end

---Queues a cover search when a threat is known and the cover is missing or old.
---@param bot Player
---@param board PW.BotBoard
---@param f PW.BotCombatFacts
function lib._QueueCover(bot, board, f)
    local scheduler = rawget(PW, "BotScheduler") --[[@as PW.BotSchedulerLib?]]
    if scheduler == nil or store.pending[bot] or PW.Ask("PW_CanSearchBotCover", bot) == false then return end
    ---@type PW.BotContact?
    local threat = nil
    for _, c in ipairs(board.contacts or {}) do
        if c.visible or CurTime() - c.time <= cfg.threatMemory then
            threat = c
            break
        end
    end
    if threat == nil then return end
    local cover = f.cover
    local moved = cover ~= nil and cover.threatPos:Distance(threat.pos) > cfg.coverThreatSlack / 2
    if cover ~= nil and CurTime() - cover.at < coverEvery and not moved then return end
    local token = {}
    store.pending[bot] = token
    local threatPos = threat.pos
    scheduler.Enqueue(function()
        if store.pending[bot] ~= token then return end
        store.pending[bot] = nil
        if not IsValid(bot) or not bot:Alive() then return end
        local current = boardOf(bot)
        local facts = current ~= nil and current.tactics or nil
        if current == board and facts == f and PW.Ask("PW_CanSearchBotCover", bot) ~= false then
            f.cover = searchCover(bot:GetPos(), threatPos)
        end
    end)
end

---@param bot Player
---@param board PW.BotBoard
local function tickBot(bot, board)
    if not bot:Alive() then
        store.hurt[bot] = nil
        if board.tactics ~= nil then board.tactics.cover = nil end
        return
    end
    lib.Refresh(bot, board)
    lib._QueueCover(bot, board, board.tactics --[[@as PW.BotCombatFacts]])
end

---@param bot Player
local function register(bot)
    local scheduler = rawget(PW, "BotScheduler") --[[@as PW.BotSchedulerLib?]]
    if scheduler == nil then return end
    local id = "tactics:" .. bot:UserID()
    store.registered[bot] = id
    scheduler.Register(id, function()
        local board = IsValid(bot) and boardOf(bot) or nil
        if board == nil then
            scheduler.Unregister(id)
            store.registered[bot], store.hurt[bot], store.pending[bot] = nil, nil, nil
            return
        end
        tickBot(bot, board)
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
        if ply:IsBot() and store.registered[ply] == nil and boardOf(ply) ~= nil then register(ply) end
    end
end)

PW.HookFor(MODULE, "PostEntityTakeDamage", function(_, victimArg, dmgArg, took)
    local victim = victimArg --[[@as Entity]]
    if not took or not IsValid(victim) or not victim:IsPlayer() then return end
    local bot = victim --[[@as Player]]
    if not bot:IsBot() or boardOf(bot) == nil then return end
    local attacker = (dmgArg --[[@as CTakeDamageInfo]]):GetAttacker()
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    if not PW.IsEnemy(bot, attacker --[[@as Player]]) then return end
    store.hurt[bot] = { at = CurTime(), attacker = attacker }
end)
