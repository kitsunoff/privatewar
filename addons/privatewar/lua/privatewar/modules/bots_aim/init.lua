-- Bots aim, server glue (T-5.8). Thin wrappers around the pure controller in shared.lua and sh_step.lua: every server
-- tick (07 d.3: aim every tick) each bot with a target gets one aim step; the result goes into the intent the input
-- writer uses (PW.BotInput.IntentFor: the scripted one, else the blackboard's): `view` and the IN_ATTACK bit of
-- `buttons`. The aim owns those two fields only while it has a target.
--
-- Decisions of the lane agent (to confirm):
--   7. The target is, in order: the dev or test override (SetTarget, pw_bot_aim), intent.target, board.target. An
--      entity target is aimed only while perception knows it (a contact in board.contacts): visible contacts at their
--      live body part, remembered ones at the contact position without fire (no wallhack, 07 d.2). An override target
--      perception does not know (dev command, tests) is aimed at directly and may be fired at: it is a debug tool for
--      the aim, not for perception. A Vector target is a look-at point, never fired at.
--   8. The aim runs in the Tick hook at engine.TickInterval(); StartCommand of the same or the next tick sends it.
--   9. Recoil: the view kick is Player:GetViewPunchAngles(); when the adapter's GetRecoil says affectsBotAim, the kick
--      of the shots fired so far (rpm, at most Config.maxKickShots) is added to it.
--  10. A bot driven by nothing (no blackboard, no scripted intent) gets a scripted intent from the aim when it is
--      given an override target; the aim drops it again on clear. A managed bot without an intent table gets one.
--  11. On release (no target, target dead or unknown, bot dead) the aim clears IN_ATTACK once and forgets its state;
--      the view stays where it was.

local lib = PW.BotAim --[[@as PW.BotAimLib]]
local cfg = lib.Config

PW.Privilege(lib.Privilege, "superadmin")

local weak = { __mode = "k" }
PW._BotAim = PW._BotAim or {
    override = setmetatable({}, weak), states = setmetatable({}, weak), targets = setmetatable({}, weak),
    owned = setmetatable({}, weak), tiers = setmetatable({}, weak)
}
local store = PW._BotAim --[[@as PW.BotAimStore]]
store.tiers = store.tiers or setmetatable({}, weak) -- a store from before a reload may lack it
---@type table<Weapon, { fire: PW.FireInfo?, recoil: PW.Recoil?, category: string? }>
local weaponInfo = setmetatable({}, weak)

local band, bor, bnot = bit.band, bit.bor, bit.bnot
local zero = Vector(0, 0, 0)

---@param bot Player
---@return PW.BotBoard?
local function boardOf(bot)
    local botLib = rawget(PW, "Bot") --[[@as PW.BotLib?]]
    return botLib ~= nil and botLib.Get ~= nil and botLib.Get(bot) or nil
end

---@param a Player
---@param b Entity
---@return boolean
local function isEnemy(a, b)
    if not (IsValid(b) and b:IsPlayer()) then return false end
    local fn = rawget(PW, "IsEnemy") --[[@as (fun(a: any, b: any): boolean)?]]
    if fn ~= nil then return fn(a, b) == true end
    return a ~= b and a:Team() ~= (b --[[@as Player]]):Team()
end

---@param wep Weapon
local function infoOf(wep)
    local info = weaponInfo[wep]
    if info ~= nil then return info end
    local weapons = rawget(PW, "Weapons") --[[@as PW.Registry?]]
    local entry = weapons ~= nil and weapons.Get(wep:GetClass()) or nil
    info = {
        fire = PW.Adapters.CallFor(wep, "GetFireInfo", wep) --[[@as PW.FireInfo?]],
        recoil = PW.Adapters.CallFor(wep, "GetRecoil", wep) --[[@as PW.Recoil?]],
        category = entry ~= nil and (entry --[[@as table<string, any>]]).Category or nil
    }
    weaponInfo[wep] = info
    return info
end

---@param bot Player
---@return { fire: PW.FireInfo?, recoil: PW.Recoil?, category: string? }
local function activeInfo(bot)
    local wep = bot:GetActiveWeapon()
    if not IsValid(wep) then return {} end
    return infoOf(wep)
end

-- The params of each bot, rebuilt only when its difficulty copy, its tier or the tier entity changes (T-10.4: the
-- aim runs every tick for every bot, and ParamsFor builds a new table).
---@type table<Player, { difficulty: table?, tier: string?, base: table, params: PW.BotAimParams }>
local paramsCache = setmetatable({}, weak)

---@param bot Player
---@param board PW.BotBoard?
---@return PW.BotAimParams
local function paramsOf(bot, board)
    local forced = store.tiers[bot]
    ---@type table?, string?
    local difficulty, tier = nil, forced
    if forced == nil then
        local setting = PW.Setting("bots.difficulty")
        difficulty, tier = board ~= nil and board.difficulty or nil, isstring(setting) and setting or nil
    end
    local base = PW.BotProfiles.Tier(tier)
    local cached = paramsCache[bot]
    if cached ~= nil and cached.difficulty == difficulty and cached.tier == tier and cached.base == base then
        return cached.params
    end
    local params = lib.ParamsFor(difficulty, tier)
    paramsCache[bot] = { difficulty = difficulty, tier = tier, base = base, params = params }
    return params
end
lib._ParamsOf = paramsOf

---@param bot Player
---@param board PW.BotBoard?
---@return any target, boolean override
local function targetOf(bot, board)
    local forced = store.override[bot]
    if forced ~= nil then return forced, true end
    if board == nil then return nil, false end
    local intent = board.intent
    return (intent ~= nil and intent.target) or board.target, false
end

---@param target Player|Entity
---@param part "head"|"chest"
---@return Vector
local function partOf(target, part)
    if part == "head" then
        local bone = target:LookupBone("ValveBiped.Bip01_Head1")
        local pos = bone ~= nil and target:GetBonePosition(bone) or nil
        return pos or target:EyePos()
    end
    return target:GetPos() + Vector(0, 0, target:OBBMaxs().z * cfg.chestHeight)
end

---What the bot knows of its target: point, velocity, whether it may fire. nil when it knows nothing.
---@param board PW.BotBoard?
---@param target any
---@param forced boolean
---@param part "head"|"chest"
---@return { pos: Vector, vel: Vector, canFire: boolean }?
local function knowledge(board, target, forced, part)
    if isvector(target) then return { pos = target, vel = zero, canFire = false } end
    local ent = target --[[@as Entity]]
    if not IsValid(ent) or (ent:IsPlayer() and not (ent --[[@as Player]]):Alive()) then return nil end
    ---@type PW.BotContact?
    local contact = nil
    ---@type PW.BotContact[]
    local contacts = board ~= nil and board.contacts or {}
    for _, c in ipairs(contacts) do
        if c.ent == ent then contact = c break end
    end
    if contact == nil and not forced then return nil end
    if contact ~= nil and not contact.visible then
        return { pos = contact.pos, vel = contact.vel, canFire = false }
    end
    return { pos = partOf(ent, part), vel = ent:GetVelocity(), canFire = true }
end

---The intent the aim writes into; nil when there is none to write.
---@param bot Player
---@param board PW.BotBoard?
---@param create boolean
---@return PW.BotIntent?
local function intentOf(bot, board, create)
    local input = rawget(PW, "BotInput") --[[@as PW.BotInputLib?]]
    local intent = input ~= nil and input.IntentFor ~= nil and input.IntentFor(bot) or nil
    if intent ~= nil or not create then return intent end
    ---@type PW.BotIntent
    local fresh = { buttons = 0 }
    if board ~= nil then
        board.intent = fresh
    elseif input ~= nil and input.SetScripted ~= nil then
        input.SetScripted(bot, fresh)
        store.owned[bot] = fresh
    else
        return nil
    end
    return fresh
end

---@param bot Player
local function release(bot)
    if store.states[bot] ~= nil then
        local intent = intentOf(bot, boardOf(bot), false)
        if intent ~= nil then intent.buttons = band(intent.buttons or 0, bnot(IN_ATTACK)) end
    end
    store.states[bot], store.targets[bot] = nil, nil
end

---@param bot Player
---@param s PW.BotAimState
---@param recoil PW.Recoil?
---@param rpm number?
---@param now number
---@return number, number
local function kickOf(bot, s, recoil, rpm, now)
    local punch = bot:GetViewPunchAngles()
    local kickP = punch.p
    if recoil ~= nil and recoil.affectsBotAim and s.firingSince ~= nil and rpm ~= nil and rpm > 0 then
        local shots = math.min(math.floor((now - s.firingSince) * rpm / 60) + 1, cfg.maxKickShots)
        kickP = kickP - recoil.pitch * shots
    end
    return kickP, punch.y
end

---@param bot Player
---@param target any
---@param point Vector the aimed point
---@return fun(): boolean
local function lineOfFire(bot, target, point)
    return function()
        local start = bot:EyePos()
        local tr = util.TraceLine({ start = start, endpos = lib.FireRayEnd(start, point), filter = bot,
            mask = MASK_SHOT })
        local hit = { fraction = tr.Fraction, ent = tr.Entity, world = tr.HitWorld }
        return lib.FireClear(hit, target, function(ent) return isEnemy(bot, ent --[[@as Entity]]) end)
    end
end

---@param bot Player
---@param board PW.BotBoard?
---@param s PW.BotAimState
local function writeOut(bot, board, s)
    local intent = intentOf(bot, board, true)
    if intent ~= nil then
        intent.view = Angle(s.p, s.y, 0)
        intent.viewTarget, intent.viewSpeed = nil, nil -- the aim owns the view: no walking-view stepping
        local buttons = intent.buttons or 0
        intent.buttons = s.fire and bor(buttons, IN_ATTACK) or band(buttons, bnot(IN_ATTACK))
    end
    if board ~= nil then
        local debugInfo = (board.debug or {}) --[[@as table<string, any>]]
        board.debug = debugInfo
        local aim = (debugInfo.aim or {}) --[[@as table<string, any>]]
        debugInfo.aim = aim
        aim.focus, aim.err, aim.tolerance, aim.fire, aim.part = s.focus, s.err, s.tolerance, s.fire, s.part
        aim.blockedSince = s.blockedSince
    end
end

---One aim tick of a bot.
---@param bot Player
---@param now number
---@param dt number
local function aimBot(bot, now, dt)
    local board = boardOf(bot)
    local target, forced = targetOf(bot, board)
    if target == nil or not bot:Alive() then return release(bot) end
    local params, info = paramsOf(bot, board), activeInfo(bot)
    local s = store.states[bot]
    if s == nil then
        local eye = bot:EyeAngles()
        s = lib.NewState(eye.p, eye.y, params, now)
        store.states[bot] = s
    end
    if store.targets[bot] ~= target then
        lib.Acquire(s, params, now, info.category)
        store.targets[bot] = target
    end
    local known = knowledge(board, target, forced, s.part)
    if known == nil then return release(bot) end
    local eye = bot:EyePos()
    local fire = info.fire
    local point = lib.Lead({ pos = known.pos, vel = known.vel, ownVel = bot:GetVelocity(), eye = eye,
        projectileSpeed = fire ~= nil and fire.projectileSpeed or nil }, params)
    local kickP, kickY = kickOf(bot, s, info.recoil, fire ~= nil and fire.rpm or nil, now)
    lib.Step(s, { now = now, dt = dt, eye = eye, point = point, radius = lib.FireHalfSize(info.category),
        canFire = known.canFire, kickP = kickP, kickY = kickY,
        lineOfFire = lineOfFire(bot, target, point) }, params)
    writeOut(bot, board, s)
end

PW.HookFor(MODULE, "Tick", function()
    local now, dt = CurTime(), engine.TickInterval()
    for _, bot in ipairs(player.GetBots()) do
        if store.override[bot] ~= nil or store.states[bot] ~= nil or boardOf(bot) ~= nil then aimBot(bot, now, dt) end
    end
end)

function lib.SetTarget(bot, target, tier)
    store.override[bot] = target
    store.tiers[bot] = target ~= nil and tier or nil
    if target ~= nil then return end
    release(bot)
    local owned = store.owned[bot]
    local input = rawget(PW, "BotInput") --[[@as PW.BotInputLib?]]
    if owned ~= nil and input ~= nil and input.IntentFor ~= nil and input.SetScripted ~= nil
        and input.IntentFor(bot) == owned then
        input.SetScripted(bot, nil)
    end
    store.owned[bot] = nil
end

function lib.GetState(bot)
    return store.states[bot]
end

function lib.OwnsView(bot)
    return store.states[bot] ~= nil
end

local function clearAll()
    for bot in pairs(store.states) do
        if boardOf(bot) ~= nil then lib.SetTarget(bot, nil) end
    end
    for bot in pairs(store.override) do
        if boardOf(bot) ~= nil then lib.SetTarget(bot, nil) end
    end
end

function MODULE:PW_PlayerTeamChanged() clearAll() end
function MODULE:PW_RoundPrepared() clearAll() end

include("privatewar/modules/bots_aim/sv_command.lua")
