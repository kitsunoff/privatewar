-- At most one new registry candidate per managed bot per scheduled pass; never a global entity search.
local lib = PW.BotDevices --[[@as PW.BotDevicesLib]]
local module = MODULE
---@type table<Player, PW.BotDeviceState>
local states = setmetatable({}, { __mode = "k" })
---@type table<Player, string>
local registered = setmetatable({}, { __mode = "k" })

---@param bot Player
---@param record PW.SupportDevice
---@param fov number
---@return boolean
local function sees(bot, record, fov)
    if not IsValid(record.entity) or not IsValid(record.owner)
        or not PW.IsEnemy(bot, record.owner) then return false end
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
        or not contact.visible or CurTime() - contact.seen > 0.3
        or not PW.IsEnemy(bot, contact.device.owner) then return nil end
    return contact
end

function MODULE:ScanBot(bot) lib.Step(bot) end

PW.HookFor(module, "Think", function()
    local scheduler = PW.BotScheduler
    if scheduler == nil then return end
    for _, bot in ipairs(player.GetBots()) do
        local board = PW.Bot ~= nil and PW.Bot.Get ~= nil and PW.Bot.Get(bot) or nil
        if board ~= nil and bot:Alive() and registered[bot] == nil then
            local id = "devices:" .. bot:UserID()
            registered[bot] = id
            scheduler.Register(id, function() PW.Call(module, "ScanBot", bot) end, { period = 0.1 })
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
    for bot, id in pairs(registered) do
        PW.BotScheduler.Unregister(id)
        registered[bot], states[bot] = nil, nil
    end
end

function MODULE:PW_MatchEnd() clear() end
function MODULE:PW_RoundPreparing() clear() end
function MODULE:PW_PlayerTeamChanged() clear() end
hook.Add("PW_EntityDisabled", "PW.BotDevices", function(kind, _, definition)
    if kind == "modules" and definition == module then clear() end
end)
