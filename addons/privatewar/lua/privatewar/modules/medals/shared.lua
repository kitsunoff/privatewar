-- Medals module (T-4.11; 06-progression.md d.3). Medals are score events with Medal = true (no medals kind); the
-- detectors live here as pure functions over plain kill and damage facts, and the server glue (init.lua) feeds them
-- from PW_PlayerKilled and PostEntityTakeDamage. Each medal earned is counted per player, awarded through
-- PW.Score.Award under its own event id, announced with the notification PW_Medal(ply, medalId) and sent to the
-- owner (a human) as "pw_medal" (one string); the popups are T-6.4.
--
-- Medals (id = score event id, see lua/privatewar/score_events/):
--   first_blood  the first enemy kill of the match
--   double_kill  second kill of a chain; triple_kill: third kill of a chain. A chain continues while each kill is
--                at most Window seconds after the previous one
--   revenge      killing the enemy who killed you last (once per death)
--   streak5      every fifth kill without dying (5, 10, 15, ...)
--   saviour      killing an enemy who damaged a teammate of yours at most SaviourWindow seconds before the kill
--
-- Decisions of the lane agent: Window 4 s, SaviourWindow 5 s, streak5 repeats at every multiple of 5; teamkills,
-- suicides and world deaths earn nothing and use up no first blood, but the victim's streak and chain still reset
-- on death; a bot is counted and awarded like a human but gets no message.

MODULE.Name = "Medals"

local lib = (rawget(PW, "Medals") or {}) --[[@as PW.MedalsLib]]
PW.Medals = lib

lib.Ids = { "first_blood", "revenge", "saviour", "double_kill", "triple_kill", "streak5" }
lib.Window = 4
lib.SaviourWindow = 5
lib.StreakStep = 5
lib.Last = lib.Last or { id = nil, at = 0 }

local maxDamageRecords = 256

function lib._NewState()
    return { firstBlood = false, chains = {}, streaks = {}, lastKiller = {}, damage = {} }
end

function lib._Reset(state)
    state.firstBlood = false
    state.chains, state.streaks, state.lastKiller, state.damage = {}, {}, {}, {}
end

function lib._OnDamage(state, rec)
    ---@type PW.MedalsDamage[]
    local kept = {}
    for _, old in ipairs(state.damage) do
        if rec.time - old.time <= lib.SaviourWindow then kept[#kept + 1] = old end
    end
    if #kept >= maxDamageRecords then table.remove(kept, 1) end
    kept[#kept + 1] = rec
    state.damage = kept
end

---A damage to a teammate of the killer by the victim, recent enough.
---@param state PW.MedalsState
---@param ev PW.MedalsKill
---@param isAlly PW.MedalsAllyFn
---@return boolean
local function saviour(state, ev, isAlly)
    for _, rec in ipairs(state.damage) do
        local age = ev.time - rec.time
        if rec.attacker == ev.victim and rec.victim ~= ev.attacker and age >= 0 and age <= lib.SaviourWindow
            and isAlly(rec.victim, ev.attacker) then
            return true
        end
    end
    return false
end

---Advances the chain of the killer; returns the multi-kill medal of this kill, if any.
---@param state PW.MedalsState
---@param killer any
---@param time number
---@return string?
local function multiKill(state, killer, time)
    local chain = state.chains[killer]
    if chain == nil or time - chain.last > lib.Window then chain = { count = 0, last = time } end
    chain.count, chain.last = chain.count + 1, time
    state.chains[killer] = chain
    if chain.count == 2 then return "double_kill" end
    if chain.count == 3 then return "triple_kill" end
    return nil
end

function lib._OnKill(state, ev, isAlly)
    local victim, killer = ev.victim, ev.attacker
    state.streaks[victim], state.chains[victim] = nil, nil
    if not ev.enemy or killer == nil or killer == victim then return {} end
    ---@type string[]
    local ids = {}
    if not state.firstBlood then
        state.firstBlood = true
        ids[#ids + 1] = "first_blood"
    end
    if state.lastKiller[killer] == victim then
        state.lastKiller[killer] = nil
        ids[#ids + 1] = "revenge"
    end
    if saviour(state, ev, isAlly) then ids[#ids + 1] = "saviour" end
    local multi = multiKill(state, killer, ev.time)
    if multi ~= nil then ids[#ids + 1] = multi end
    local streak = (state.streaks[killer] or 0) + 1
    state.streaks[killer] = streak
    if streak % lib.StreakStep == 0 then ids[#ids + 1] = "streak5" end
    state.lastKiller[victim] = killer
    return ids
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        state = lib._NewState(),
        counts = {},
        isAlly = opts.isAlly or function() return false end,
        award = opts.award or function() return false end,
        notify = opts.notify or function() end,
        send = opts.send or function() end
    }
end

---@param ply any
---@return boolean
local function isBot(ply)
    return ply.IsBot ~= nil and ply:IsBot() == true
end

function lib._Kill(store, ev)
    local ply = ev.attacker
    for _, id in ipairs(lib._OnKill(store.state, ev, store.isAlly)) do
        local counts = store.counts[ply] or {}
        store.counts[ply] = counts
        counts[id] = (counts[id] or 0) + 1
        store.award(ply, id)
        store.notify("PW_Medal", ply, id)
        if not isBot(ply) then store.send(ply, id) end
    end
end

function lib._Counts(store, ply)
    ---@type table<string, integer>
    local copy = {}
    for id, count in pairs(store.counts[ply] or {}) do copy[id] = count end
    return copy
end

function lib._ResetStore(store)
    lib._Reset(store.state)
    store.counts = {}
end

function lib.Get(ply)
    if SERVER then return lib._Counts(PW._Medals, ply) end
    return {}
end
