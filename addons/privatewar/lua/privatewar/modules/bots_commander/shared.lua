-- Bots commander (T-5.11; 07-bots.md d.9, d.14). A sub-module of `bots`. Once a second per team: the objectives of
-- MODE:BotObjectives(team) (else PW.BotObjectives.Derive), the assignment of the team's bots to them (board.order),
-- and the hunt slots of every human (board.hunt). Everything here is pure over plain data; the hunt slots are in
-- sh_hunt.lua, the engine glue in init.lua.
--
-- Assignment (Assign), in three passes over the bots sorted by id:
--   1. Active capture: a bot whose order is a capture (or hold) of an objective that still has that action and that
--      stands inside its radius keeps it, whatever the want or a better objective says (07 d.14 anti-dither).
--   2. Hold: any other order of an objective that still exists with the same action is kept for Config.hold seconds
--      after its `since`, while the objective has a free slot (want) and, for defend, the defender cap allows.
--   3. Fill: the free bots and the free slots are paired greedily by score = weight x closeness x factors (sticky for
--      the bot's current objective, a stationary personality likes defend); ties go to the smaller objective id, then
--      the smaller bot id. A bot that gets no slot has no order.
--   Defenders (action defend, every objective together) are at most floor(team size x Config.defendShare).
--
-- Decisions of the lane agent (to confirm):
--   1. Config.hold = 30 s (07 d.14: 30-45 s). A changed action (our flag is now ours: capture -> defend) or a gone
--      objective (a collected tag) frees the bot at once. Hysteresis after the hold: x1.25 for the current objective.
--   2. The defender cap counts every defend objective together and the team's managed bots (alive or dead); a team
--      of 2 bots has no defender. The cap applies in every mode (only Domination answers defend today).
--   3. Objectives with weight <= 0 or want <= 0 get nobody. Extra bots get no order: the objective behaviour's own pick
--      (T-5.10) or hunt drives them.
--   4. board.order adds `id` and `priority` (the objective's weight) to the contract's {objective, type, since}.
--   5. board.hunt = { target?, since } on every managed bot while the commander runs; the hunt behaviour reads it
--      through HuntView: a bot without a slot does not chase humans' contacts nor teammates' death spots (in solo
--      every death spot is the human's), it chases bot enemies and roams.

MODULE.Name = "Bots commander"

local lib = (rawget(PW, "BotCommander") or {}) --[[@as PW.BotCommanderLib]]
PW.BotCommander = lib

lib.Config = {
    interval = 1,
    hold = 30,
    defendShare = 1 / 3,
    sticky = 1.25,
    stationaryDefend = 1.5,
    falloff = 1200,
    huntMax = 2,
    huntStall = 20,
    huntProgress = 150,
    huntContact = 3,
    rerollMin = 30,
    rerollMax = 60
}

local active = { capture = true, hold = true }

function lib.Closeness(dist)
    return 1 / (1 + math.max(dist, 0) / lib.Config.falloff)
end

---@param bots PW.CommanderBot[]
---@return PW.CommanderBot[]
local function sorted(bots)
    ---@type PW.CommanderBot[]
    local list = {}
    for i, bot in ipairs(bots) do list[i] = bot end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

---@param obj PW.BotObjective
---@param since number
---@return PW.BotOrder
local function makeOrder(obj, since)
    return { objective = obj, type = obj.action, id = obj.id, priority = obj.weight, since = since }
end

---@class PW.CommanderPass
---@field byId table<string, PW.BotObjective>
---@field slots table<string, integer>
---@field defendLeft integer
---@field out table<integer, PW.BotOrder>
---@field orders table<integer, PW.BotOrder>

---@param objectives PW.BotObjective[]
---@param orders table<integer, PW.BotOrder>
---@param teamSize integer
---@param share number
---@return PW.CommanderPass
local function newPass(objectives, orders, teamSize, share)
    ---@type PW.CommanderPass
    local pass = { byId = {}, slots = {}, out = {}, orders = orders,
        defendLeft = math.floor(teamSize * share + 1e-9) }
    for _, obj in ipairs(objectives) do
        pass.byId[obj.id] = obj
        local want = (tonumber(obj.weight) or 0) > 0 and math.floor(tonumber(obj.want) or 0) or 0
        pass.slots[obj.id] = math.max(want, 0)
    end
    return pass
end

---The objective of a bot's current order when it still exists with the same action.
---@param pass PW.CommanderPass
---@param bot PW.CommanderBot
---@return PW.BotObjective?, PW.BotOrder?
local function current(pass, bot)
    local order = pass.orders[bot.id]
    if order == nil then return nil, nil end
    local obj = pass.byId[order.id]
    if obj == nil or obj.action ~= order.type then return nil, nil end
    return obj, order
end

---@param pass PW.CommanderPass
---@param bot PW.CommanderBot
---@param obj PW.BotObjective
---@param since number
local function give(pass, bot, obj, since)
    pass.out[bot.id] = makeOrder(obj, since)
    pass.slots[obj.id] = pass.slots[obj.id] - 1
    if obj.action == "defend" then pass.defendLeft = pass.defendLeft - 1 end
end

---@param pass PW.CommanderPass
---@param obj PW.BotObjective
---@return boolean
local function hasRoom(pass, obj)
    if pass.slots[obj.id] <= 0 then return false end
    return obj.action ~= "defend" or pass.defendLeft > 0
end

---Passes 1 and 2: active captures, then orders still inside their hold.
---@param pass PW.CommanderPass
---@param bots PW.CommanderBot[]
---@param now number
---@param hold number
local function keep(pass, bots, now, hold)
    for _, bot in ipairs(bots) do
        local obj, order = current(pass, bot)
        if obj ~= nil and order ~= nil and active[obj.action] and bot.pos:Distance(obj.pos) <= obj.radius then
            give(pass, bot, obj, order.since)
        end
    end
    for _, bot in ipairs(bots) do
        local obj, order = current(pass, bot)
        if pass.out[bot.id] == nil and obj ~= nil and order ~= nil and now - order.since < hold
            and hasRoom(pass, obj) then
            give(pass, bot, obj, order.since)
        end
    end
end

---@class PW.CommanderPair
---@field bot PW.CommanderBot
---@field obj PW.BotObjective
---@field score number

---@param pass PW.CommanderPass
---@param bot PW.CommanderBot
---@param obj PW.BotObjective
---@param opts PW.CommanderAssignOpts
---@return number
local function scoreOf(pass, bot, obj, opts)
    local score = obj.weight * lib.Closeness(bot.pos:Distance(obj.pos))
    local order = pass.orders[bot.id]
    if order ~= nil and order.id == obj.id then score = score * (opts.sticky or lib.Config.sticky) end
    if bot.stationary and obj.action == "defend" then
        score = score * (opts.stationaryDefend or lib.Config.stationaryDefend)
    end
    return score
end

---@param a PW.CommanderPair
---@param b PW.CommanderPair
---@return boolean
local function better(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.obj.id ~= b.obj.id then return a.obj.id < b.obj.id end
    return a.bot.id < b.bot.id
end

---The pairs of one free bot with every objective that has a free slot.
---@param list PW.CommanderPair[]
---@param pass PW.CommanderPass
---@param bot PW.CommanderBot
---@param objectives PW.BotObjective[]
---@param opts PW.CommanderAssignOpts
local function addPairs(list, pass, bot, objectives, opts)
    for _, obj in ipairs(objectives) do
        if pass.slots[obj.id] > 0 then
            list[#list + 1] = { bot = bot, obj = obj, score = scoreOf(pass, bot, obj, opts) }
        end
    end
end

---Pass 3: greedy fill of the free slots by the free bots.
---@param pass PW.CommanderPass
---@param bots PW.CommanderBot[]
---@param objectives PW.BotObjective[]
---@param now number
---@param opts PW.CommanderAssignOpts
local function fill(pass, bots, objectives, now, opts)
    ---@type PW.CommanderPair[]
    local pairs_ = {}
    for _, bot in ipairs(bots) do
        if pass.out[bot.id] == nil then addPairs(pairs_, pass, bot, objectives, opts) end
    end
    table.sort(pairs_, better)
    for _, pair in ipairs(pairs_) do
        local bot, obj = pair.bot, pair.obj
        if pass.out[bot.id] == nil and hasRoom(pass, obj) then
            local obj0, order = current(pass, bot)
            local since = (obj0 == obj and order ~= nil) and order.since or now
            give(pass, bot, obj, since)
        end
    end
end

function lib.Assign(bots, objectives, orders, now, opts)
    opts = opts or {}
    local list = sorted(bots)
    local pass = newPass(objectives, orders, opts.teamSize or #list, opts.defendShare or lib.Config.defendShare)
    keep(pass, list, now, opts.hold or lib.Config.hold)
    fill(pass, list, objectives, now, opts)
    return pass.out
end

function lib.IsHuman(ent)
    return IsValid(ent) and ent:IsPlayer() and not ent:IsBot()
end

function lib.HuntView(board, memory, deaths, isHuman)
    local slot = board.hunt
    if slot == nil then return memory, deaths end
    isHuman = isHuman or lib.IsHuman
    ---@type table<any, PW.BotContact>
    local view = {}
    for ent, contact in pairs(memory) do
        if ent == slot.target or not isHuman(ent) then view[ent] = contact end
    end
    if slot.target == nil then return view, {} end
    return view, deaths
end

if SERVER then AddCSLuaFile("privatewar/modules/bots_commander/sh_hunt.lua") end
include("privatewar/modules/bots_commander/sh_hunt.lua")
