-- Bots commander: pure hunt slots (T-5.11; 07-bots.md d.9). At most Config.huntMax bots hunt one human at a time;
-- the budget of each human (1..huntMax) is re-rolled every rerollMin..rerollMax seconds. A hunter that makes no
-- progress (closer by huntProgress units, or a contact with the human in the last huntContact seconds) for huntStall
-- seconds is replaced by the closest free bot and is not picked for that human again for huntStall seconds.
-- Candidates: enemies of the human (another team, or no team in FFA) without an order; one human per bot.
--
-- Decisions of the lane agent (to confirm):
--   6. huntStall 20 s, huntProgress 150 units, huntContact 3 s; a bot with an order never hunts (objective play wins).
--   7. "Closest" uses the true positions: the commander only picks who hunts; the hunter itself goes to its own
--      contact memory and hot spots (no wallhack is handed to the bot).

local lib = PW.BotCommander --[[@as PW.BotCommanderLib]]

---@class PW.CommanderHuntCfg
---@field max integer
---@field stall number
---@field progress number
---@field contact number
---@field rerollMin number
---@field rerollMax number
---@field random fun(): number

---@param opts PW.CommanderHuntOpts
---@return PW.CommanderHuntCfg
local function config(opts)
    local c = lib.Config
    return { max = opts.max or c.huntMax, stall = opts.stall or c.huntStall, progress = opts.progress or c.huntProgress,
        contact = opts.contact or c.huntContact, rerollMin = opts.rerollMin or c.rerollMin,
        rerollMax = opts.rerollMax or c.rerollMax, random = opts.random or math.random }
end

function lib.NewHuntState()
    return { humans = {} }
end

---@param bot PW.CommanderBot
---@param human PW.CommanderHuman
---@return boolean
local function enemy(bot, human)
    return bot.team == nil or human.team == nil or bot.team ~= human.team
end

---@param hs PW.CommanderHuntHuman
---@param now number
---@param cfg PW.CommanderHuntCfg
local function reroll(hs, now, cfg)
    if now < hs.rerollAt then return end
    hs.budget = math.Clamp(1 + math.floor(cfg.random() * cfg.max), 1, math.max(cfg.max, 1))
    hs.rerollAt = now + cfg.rerollMin + (cfg.rerollMax - cfg.rerollMin) * cfg.random()
end

---Updates the progress of every hunter and drops the gone, the busy and the stalled ones.
---@param hs PW.CommanderHuntHuman
---@param human PW.CommanderHuman
---@param byId table<integer, PW.CommanderBot>
---@param now number
---@param cfg PW.CommanderHuntCfg
local function prune(hs, human, byId, now, cfg)
    for id, hunter in pairs(hs.hunters) do
        local bot = byId[id]
        if bot == nil or bot.busy or not enemy(bot, human) then
            hs.hunters[id] = nil
        else
            local dist = bot.pos:Distance(human.pos)
            local seenAt = bot.seen ~= nil and bot.seen[human.id] or nil
            if (seenAt ~= nil and now - seenAt <= cfg.contact) or dist <= hunter.best - cfg.progress then
                hunter.progressAt, hunter.best = now, dist
            end
            if now - hunter.progressAt >= cfg.stall then
                hs.hunters[id] = nil
                hs.cooldown[id] = now + cfg.stall
            end
        end
    end
end

---Drops the hunters above the budget, the longest without progress first.
---@param hs PW.CommanderHuntHuman
local function trim(hs)
    ---@type integer[]
    local ids = {}
    for id in pairs(hs.hunters) do ids[#ids + 1] = id end
    if #ids <= hs.budget then return end
    table.sort(ids, function(a, b)
        local pa, pb = hs.hunters[a].progressAt, hs.hunters[b].progressAt
        if pa ~= pb then return pa < pb end
        return a > b
    end)
    for i = 1, #ids - hs.budget do hs.hunters[ids[i]] = nil end
end

---@param hs PW.CommanderHuntHuman
---@return integer
local function count(hs)
    local n = 0
    for _ in pairs(hs.hunters) do n = n + 1 end
    return n
end

---Gives the free slots of one human to the closest free bots.
---@param hs PW.CommanderHuntHuman
---@param human PW.CommanderHuman
---@param bots PW.CommanderBot[]
---@param taken table<integer, integer>
---@param now number
local function fillSlots(hs, human, bots, taken, now)
    local need = hs.budget - count(hs)
    if need <= 0 then return end
    ---@type { bot: PW.CommanderBot, dist: number }[]
    local free = {}
    for _, bot in ipairs(bots) do
        local cool = hs.cooldown[bot.id]
        if taken[bot.id] == nil and not bot.busy and enemy(bot, human) and (cool == nil or now >= cool) then
            free[#free + 1] = { bot = bot, dist = bot.pos:Distance(human.pos) }
        end
    end
    table.sort(free, function(a, b)
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.bot.id < b.bot.id
    end)
    for i = 1, math.min(need, #free) do
        local entry = free[i]
        hs.hunters[entry.bot.id] = { since = now, progressAt = now, best = entry.dist }
        taken[entry.bot.id] = human.id
    end
end

---@param list { id: integer }[]
---@return { id: integer }[]
local function byIdOrder(list)
    ---@type { id: integer }[]
    local out = {}
    for i, item in ipairs(list) do out[i] = item end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function lib.Hunt(state, humans, bots, now, opts)
    local cfg = config(opts or {})
    local list = byIdOrder(bots) --[[@as PW.CommanderBot[] ]]
    local people = byIdOrder(humans) --[[@as PW.CommanderHuman[] ]]
    ---@type table<integer, PW.CommanderBot>
    local byId = {}
    for _, bot in ipairs(list) do byId[bot.id] = bot end
    ---@type table<integer, integer>
    local taken = {}
    ---@type table<integer, PW.CommanderHuntHuman>
    local next_ = {}
    for _, human in ipairs(people) do
        local hs = state.humans[human.id] or { budget = 0, rerollAt = -math.huge, hunters = {}, cooldown = {} }
        next_[human.id] = hs
        reroll(hs, now, cfg)
        prune(hs, human, byId, now, cfg)
        trim(hs)
        for id in pairs(hs.hunters) do taken[id] = human.id end
    end
    for _, human in ipairs(people) do fillSlots(next_[human.id], human, list, taken, now) end
    state.humans = next_
    return taken
end
