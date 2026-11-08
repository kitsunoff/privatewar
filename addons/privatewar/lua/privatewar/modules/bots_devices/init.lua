-- At most one new registry candidate per managed bot per scheduled pass; never a global entity search.
local lib = PW.BotDevices --[[@as PW.BotDevicesLib]]
local module = MODULE
---@type table<Player, PW.BotDeviceState>
local states = setmetatable({}, { __mode = "k" })
---@type table<Player, string>
local registered = setmetatable({}, { __mode = "k" })
---@type table<Player, PW.BotIntent>
local inputs = setmetatable({}, { __mode = "k" })
---@type table<Player, PW.DeviceAimControl>
local controls = setmetatable({}, { __mode = "k" })
---@type PW.BotContact[]
local noContacts = {}

function lib.OwnInput(bot, intent) inputs[bot] = intent end

function lib.ReleaseInput(bot)
    local intent = inputs[bot]
    if intent ~= nil then intent.buttons = bit.band(intent.buttons or 0, bit.bnot(bit.bor(IN_ATTACK, IN_RELOAD))) end
    inputs[bot] = nil
    controls[bot] = nil
end

function lib.Invalidate(record)
    for bot, state in pairs(states) do
        state.first[record.entity] = nil
        if state.contact ~= nil and state.contact.device == record then
            state.contact = nil
            lib.ReleaseInput(bot)
        end
    end
end

---@param bot Player
---@param record PW.SupportDevice
---@param fov number
---@return boolean
local function sees(bot, record, fov)
    if record.retired or record.constructing or not IsValid(record.entity) or not IsValid(record.owner)
        or not PW.IsEnemy(bot, record.owner) or not lib.CanObserve(bot, CurTime()) then return false end
    local eye, point = bot:EyePos(), record.entity:WorldSpaceCenter()
    if not lib.Perceivable(eye, bot:GetAimVector(), point, 1800, fov, true) then return false end
    local tr = util.TraceLine({ start = eye, endpos = point, filter = bot, mask = MASK_VISIBLE })
    return tr.Fraction >= 0.99 or tr.Entity == record.entity
end

function lib.Step(bot)
    local board = PW.Bot ~= nil and PW.Bot.Get ~= nil and PW.Bot.Get(bot) or nil
    local devices = PW.Devices
    if not module:IsValid() or board == nil or not bot:Alive() or devices == nil then states[bot] = nil return end
    local state = states[bot]
    if state == nil then state = { first = {}, index = 0 } states[bot] = state end
    local now = CurTime()
    local difficulty = board.difficulty
    local fov = difficulty ~= nil and tonumber(difficulty.fov) or 110
    local delay = difficulty ~= nil and tonumber(difficulty.reaction_mean) or 0.45
    local held = state.contact
    if held ~= nil then
        held.visible = sees(bot, held.device, fov or 110)
        if held.visible then
            held.position, held.seen = held.device.entity:WorldSpaceCenter(), now
        else state.contact = nil end
    end
    local records = devices.List()
    if #records == 0 then state.contact, state.first = nil, {} return end
    state.index = state.index % #records + 1
    local record = records[state.index]
    local visible = sees(bot, record, fov or 110)
    if not visible then state.first[record.entity] = nil return end
    state.first[record.entity] = state.first[record.entity] or now
    if lib.Recognized(state.first[record.entity], now, delay or 0.45, true) then
        state.contact = { device = record, position = record.entity:WorldSpaceCenter(), seen = now,
            recognized = now, visible = true }
    end
    for entity in pairs(state.first) do if not IsValid(entity) then state.first[entity] = nil end end
end

function lib.Contact(bot)
    local state = states[bot]
    local contact = state ~= nil and state.contact or nil
    if not module:IsValid() or not bot:Alive() or contact == nil or not IsValid(contact.device.entity)
        or contact.device.retired
        or not contact.visible or CurTime() - contact.seen > 0.3
        or not lib.CanObserve(bot, CurTime()) or not PW.IsEnemy(bot, contact.device.owner) then return nil end
    return contact
end

---@param bot Player
function MODULE:ScanBot(bot) lib.Step(bot) end

---@param bot Player
---@param board PW.BotBoard
---@param contact PW.BotDeviceContact
---@param now number
---@return PW.DeviceAimControl
local function controlFor(bot, board, contact, now)
    local cached = controls[bot]
    if cached ~= nil and cached.difficulty == board.difficulty then return cached end
    local aim = assert(PW.BotAim)
    local params, eye = aim.ParamsFor(board.difficulty), bot:EyeAngles()
    local control = {
        difficulty = board.difficulty, params = params, state = aim.NewState(eye.p, eye.y, params, now),
        view = Angle(eye.p, eye.y, 0), trace = { start = bot:EyePos(), endpos = contact.position,
            filter = bot, mask = MASK_SHOT },
        input = { now = now, dt = 0, eye = bot:EyePos(), point = contact.position, radius = 8, canFire = false }
    }
    controls[bot] = control
    return control
end

---@param bot Player
---@param control PW.DeviceAimControl
---@param now number
local function recoil(bot, control, now)
    local weapon = bot:GetActiveWeapon()
    if control.weapon ~= weapon then
        control.weapon = weapon
        if IsValid(weapon) then
            control.recoil = PW.Adapters.CallFor(weapon, "GetRecoil", weapon)
            control.fire = PW.Adapters.CallFor(weapon, "GetFireInfo", weapon)
        else control.recoil, control.fire = nil, nil end
    end
    local punch, kick = bot:GetViewPunchAngles(), 0
    local r, fire = control.recoil, control.fire
    if r ~= nil and r.affectsBotAim and fire ~= nil and control.state.firingSince ~= nil then
        local shots = math.min(math.floor((now - control.state.firingSince) * fire.rpm / 60) + 1,
            assert(PW.BotAim).Config.maxKickShots)
        kick = r.pitch * shots
    end
    control.input.kickP, control.input.kickY = punch.p - kick, punch.y
end

---@param bot Player
---@param intent PW.BotIntent
---@param now number
---@param dt number
function MODULE:DriveInput(bot, intent, now, dt)
    intent.buttons = bit.band(intent.buttons or 0, bit.bnot(bit.bor(IN_ATTACK, IN_RELOAD)))
    local board = PW.Bot ~= nil and PW.Bot.Get ~= nil and PW.Bot.Get(bot) or nil
    local contact, aim = lib.Contact(bot), PW.BotAim
    if board == nil or contact == nil or aim == nil then return end
    for _, known in ipairs(board.contacts or noContacts) do
        if known.visible or now - known.time < 1 then return end
    end
    local control = controlFor(bot, board, contact, now)
    if control.device ~= contact.device then
        aim.Acquire(control.state, control.params, now, nil)
        control.device = contact.device
    end
    local eye = bot:EyePos()
    control.trace.start, control.trace.endpos = eye, contact.position
    local tr = util.TraceLine(control.trace)
    local clear = tr.Entity == contact.device.entity or tr.Fraction >= 0.99
    local weapon = bot:GetActiveWeapon()
    local clip = IsValid(weapon) and PW.Adapters.CallFor(weapon, "GetClip", weapon) or 0
    control.input.now, control.input.dt = now, math.min(dt, 0.1)
    control.input.eye, control.input.point = eye, contact.position
    control.input.canFire = clear and clip > 0
    recoil(bot, control, now)
    aim.Step(control.state, control.input, control.params)
    control.view.p, control.view.y, control.view.r = control.state.p, control.state.y, 0
    intent.view, intent.viewTarget, intent.viewSpeed = control.view, nil, nil
    if clip <= 0 then intent.buttons = bit.bor(intent.buttons, IN_RELOAD)
    elseif control.state.fire then intent.buttons = bit.bor(intent.buttons, IN_ATTACK) end
end

PW.HookFor(module, "Tick", function()
    local definition = PW.Modules.Get("bots_devices")
    if definition == nil then return end
    local now, dt = CurTime(), engine.TickInterval()
    for bot, intent in pairs(inputs) do
        if IsValid(bot) then PW.Call(definition, "DriveInput", bot, intent, now, dt)
        else lib.ReleaseInput(bot) end
    end
end)

---@param bot Player
local function scan(bot)
    local definition = PW.Modules.Get("bots_devices")
    if definition ~= nil then PW.Call(definition, "ScanBot", bot) end
end

PW.HookFor(module, "Think", function()
    local scheduler = PW.BotScheduler
    if scheduler == nil then return end
    for _, bot in ipairs(player.GetBots()) do
        local board = PW.Bot ~= nil and PW.Bot.Get ~= nil and PW.Bot.Get(bot) or nil
        if board ~= nil and bot:Alive() and registered[bot] == nil then
            local id = "devices:" .. bot:UserID()
            registered[bot] = id
            scheduler.Register(id, function() scan(bot) end, { period = 0.1 })
        end
    end
    for bot, id in pairs(registered) do
        if not IsValid(bot) or not bot:Alive() or PW.Bot == nil or PW.Bot.Get(bot) == nil then
            scheduler.Unregister(id)
            registered[bot], states[bot] = nil, nil
        end
    end
end)

local function clear()
    for bot in pairs(inputs) do lib.ReleaseInput(bot) end
    for bot, id in pairs(registered) do
        PW.BotScheduler.Unregister(id)
        registered[bot], states[bot] = nil, nil
    end
end

function MODULE:PW_MatchEnd() clear() end
function MODULE:PW_RoundPreparing() clear() end
function MODULE:PW_PlayerTeamChanged() clear() end
hook.Add("PW_EntityDisabled", "PW.BotDevices", function(kind, _, definition)
    if (kind == "modules" and definition == PW.Modules.Get("bots_devices"))
        or (kind == "bot_behaviors" and definition == PW.BotBehaviors.Get("attack_device")) then clear() end
end)
