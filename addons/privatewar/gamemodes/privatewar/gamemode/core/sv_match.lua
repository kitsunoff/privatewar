-- Phase machine (T-1.12, 00-core.md d.1-d.5; 02-modes.md d.7). Server only; the rules are in sh_phase.lua.
-- PW.Match._SetPhase is the only function that changes the phase and the only path that writes the phase NW2
-- globals (T-1.13, 00-core.md d.10: end -> phase -> seq, from server InitPostEntity on). The core
-- calls MODE:Start on entering LIVE, MODE:Cleanup on leaving it and MODE:Think every tick during LIVE, all through
-- PW.Call, and fires PW_MatchStart / PW_MatchEnd. The clock, the player list and the settings are injectable,
-- so tests drive time by calling PW.Match._Tick.

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

local durationVars = {
    prematch = CreateConVar("pw_prematch_timeout", "60", { FCVAR_ARCHIVE },
        "Private War: seconds PREMATCH waits for players before the countdown", 0),
    countdown = CreateConVar("pw_countdown", "10", { FCVAR_ARCHIVE }, "Private War: PREMATCH countdown in seconds", 0),
    postmatch = CreateConVar("pw_postmatch_time", "15", { FCVAR_ARCHIVE }, "Private War: POSTMATCH duration in seconds",
        0),
    vote = CreateConVar("pw_vote_time", "15", { FCVAR_ARCHIVE }, "Private War: VOTE duration in seconds", 0)
}
local afterMatchVar = CreateConVar("pw_aftermatch", "lobby", { FCVAR_ARCHIVE },
    "Private War: after a match go back to the \"lobby\" or continue the \"rotation\" with a vote")

local match = (rawget(PW, "Match") or {}) --[[@as PW.MatchLib]]
PW.Match = match

---@return PW.PhaseSettings
function match._ReadSettings()
    return {
        prematch = durationVars.prematch:GetFloat(),
        countdown = durationVars.countdown:GetFloat(),
        postmatch = durationVars.postmatch:GetFloat(),
        vote = durationVars.vote:GetFloat(),
        afterMatch = PW.Phase._AfterMatch(afterMatchVar:GetString())
    }
end

---@return PW.ReadyEntry[]
local function connectedPlayers()
    ---@type PW.ReadyEntry[]
    local list = {}
    for _, ply in ipairs(player.GetAll()) do list[#list + 1] = { key = ply, bot = ply:IsBot() } end
    return list
end

local globalSetters = { pw_phase_end = SetGlobal2Float, pw_phase = SetGlobal2String, pw_phase_seq = SetGlobal2Int }

---@param key string
---@param value any
local function writeGlobal(key, value)
    globalSetters[key](key, value)
end

---@param opts? PW.MatchStoreOptions
---@return PW.MatchStore
function match._NewStore(opts)
    opts = opts or {}
    return {
        phase = "LOBBY", endsAt = -1, countdown = false, ready = {}, loaded = setmetatable({}, { __mode = "k" }),
        modeStarted = false, matchStarted = false,
        busy = false, queue = {}, seq = 0, networked = false,
        write = opts.write or writeGlobal,
        log = opts.log or defaultLog,
        clock = opts.clock or CurTime,
        players = opts.players or connectedPlayers,
        settings = opts.settings or match._ReadSettings
    }
end

PW._Match = PW._Match or match._NewStore()

---The three NW2 globals of 00-core.md d.10, always end -> phase -> seq; nothing before server InitPostEntity.
---@param store PW.MatchStore
local function publish(store)
    if not store.networked then return end
    local keys = PW.Phase._Keys
    store.write(keys.ends, store.endsAt)
    store.write(keys.phase, store.phase)
    store.write(keys.seq, store.seq)
end

function match._Publish()
    local store = PW._Match
    store.networked = true
    publish(store)
end

---Runs request now, or right after the phase change in progress (a mode calling Finish from MODE:Start).
---@param request fun(store: PW.MatchStore): boolean
---@return boolean
local function defer(request)
    local store = PW._Match
    if not store.busy then return request(store) end
    store.queue[#store.queue + 1] = request
    return true
end

---Leaving LIVE: MODE:Cleanup, then PW_MatchEnd, each only when its counterpart ran.
---@param store PW.MatchStore
---@param from string
local function exitPhase(store, from)
    if from ~= "LIVE" then return end
    if store.modeStarted then
        store.modeStarted = false
        if store.mode ~= nil then PW.Call(store.mode, "Cleanup") end
    end
    if store.matchStarted then
        store.matchStarted = false
        PW.Notify("PW_MatchEnd", store.result)
    end
end

---@param store PW.MatchStore
---@param from string
---@param to string
local function enterPhase(store, from, to)
    if to == "LOBBY" then
        store.mode = nil
        store.ready = {}
        PW.ActiveMode = nil
        local endMatch = PW.Settings._EndMatch
        if endMatch ~= nil then endMatch() end
    elseif to == "PREMATCH" and from ~= "PREMATCH" then
        store.ready = {}
        for ply in pairs(store.loaded) do store.ready[ply] = true end
        store.result = nil
        PW.ActiveMode = store.mode
    elseif to == "LIVE" then
        store.modeStarted = true
        if store.mode ~= nil then PW.Call(store.mode, "Start") end
        store.matchStarted = true
        PW.Notify("PW_MatchStart")
    end
end

---@param store PW.MatchStore
---@param from string
---@param to string
---@param duration? number
---@param countdown? boolean
local function transition(store, from, to, duration, countdown)
    exitPhase(store, from)
    store.endsAt = (duration ~= nil and duration >= 0) and store.clock() + duration or -1
    store.phase = to --[[@as PW.PhaseName]]
    store.countdown = countdown == true
    store.seq = store.seq + 1
    -- A new match reads the enable ConVars (01-extensibility.md d.11), then takes the match settings snapshot of
    -- its mode and the enabled modules (d.17), before anyone hears of PREMATCH.
    if to == "PREMATCH" and from ~= "PREMATCH" then
        if PW.Enable ~= nil then PW.Enable._NewMatch() end
        local newMatch = PW.Settings._NewMatch
        if newMatch ~= nil then newMatch(store.mode) end
    end
    publish(store)
    -- A map change announced but not yet run belongs to the phase that asked for it (00-core.md d.9).
    local changer = PW.MapChange
    if changer ~= nil and changer._Cancel ~= nil then changer._Cancel("the phase changed to " .. to) end
    PW.Notify("PW_PhaseChange", to, from, store.endsAt)
    enterPhase(store, from, to)
end

---@param phase string
---@param duration? number
---@param countdown? boolean
---@return boolean
function match._SetPhase(phase, duration, countdown)
    local store = PW._Match
    local from = store.phase
    if store.busy or not PW.Phase.CanTransition(from, phase) then
        store.log(string.format("phase transition %s -> %s rejected", from, tostring(phase)))
        return false
    end
    store.busy = true
    local ok, err = pcall(transition, store, from, phase, duration, countdown)
    store.busy = false
    if not ok then store.log(string.format("phase transition %s -> %s: %s", from, phase, tostring(err))) end
    while #store.queue > 0 do table.remove(store.queue, 1)(store) end
    return true
end

function match._Definition(mode, registries)
    local own = rawget(mode, "_Registry") --[[@as PW.Registry?]]
    if own == nil then return mode end
    if not own._Released() then return own.Get(mode.ClassName) or mode end
    local current = registries[own.Kind]
    if current == nil then return nil end
    return current.Get(mode.ClassName)
end

---A rotation waits in VOTE for the new map, without a timer so the next tick does not start it again; if the
---pending file could not be written it returns to the lobby.
---@param store PW.MatchStore
---@param changer PW.MapChangeLib
---@param mode table
---@param map string
---@return boolean
local function changeLevel(store, changer, mode, map)
    local begun = changer.Schedule(mode, map)
    if store.phase ~= "VOTE" then return begun end
    store.endsAt = -1
    if not begun then match.Abort("map change to " .. map .. " failed: the pending file could not be written") end
    return begun
end

---The one way into PREMATCH for a new match (LOBBY start, VOTE rotation). A re-registered or reloaded mode
---(pw_reload, 01-extensibility.md d.12) takes effect here; a mode that a reload removed is not started (one log
---line; a rotation goes back to the lobby).
---Another target map (00-core.md d.9): PW.MapChange persists the match and runs changelevel instead; the new map
---enters PREMATCH from the pending file. The guard refuses any start while a map change is in progress.
---@param store PW.MatchStore
---@param mode table
---@param duration number
---@param map? string
---@return boolean
local function beginMatch(store, mode, duration, map)
    local resolved = match._Definition(mode, PW.Registries or {})
    if resolved == nil then
        local reason = string.format("mode %s is no longer registered (reloaded)", tostring(mode.ClassName))
        store.log("match start ignored: " .. reason)
        if store.phase ~= "LOBBY" then match.Abort(reason) end
        return false
    end
    local changer = PW.MapChange
    if changer ~= nil then
        local step = changer._Decide(PW._MapChange.map(), map, changer.IsChanging())
        if step == "busy" then
            store.log("match start ignored: a map change is in progress")
            return false
        elseif step == "changelevel" then
            return changeLevel(store, changer, resolved --[[@as table]], map --[[@as string]])
        end
    end
    store.mode = resolved
    return match._SetPhase("PREMATCH", duration)
end

---@param mode table
---@param map? string
---@return boolean
function match.Start(mode, map)
    local store = PW._Match
    if store.phase ~= "LOBBY" or store.busy then
        store.log(string.format("match start ignored: phase is %s", store.phase))
        return false
    end
    if not istable(mode) or not isstring(mode.ClassName) then
        store.log("match start ignored: the mode is not a registered entity")
        return false
    end
    if map ~= nil and not isstring(map) then
        store.log("match start ignored: the map is not a string")
        return false
    end
    store.abortReason = nil
    return beginMatch(store, mode, store.settings().prematch, map)
end

---VOTE -> PREMATCH: the next match is the answer of the question hook PW_NextMatch(mode) (the vote module), a table
---{ mode = <mode entity>, map = <string?> }; without a valid answer the same mode repeats on this map.
---@param store PW.MatchStore
---@param duration number
---@return boolean
local function nextMatch(store, duration)
    local answer = PW.Ask("PW_NextMatch", store.mode)
    if istable(answer) and istable(answer.mode) and isstring(answer.mode.ClassName)
        and (answer.map == nil or isstring(answer.map)) then
        return beginMatch(store, answer.mode, duration, answer.map)
    end
    if answer ~= nil then store.log("PW_NextMatch answer ignored: not { mode = <mode>, map = <string?> }") end
    return beginMatch(store, store.mode --[[@as table]], duration)
end

---@return boolean
function match.EndVote()
    return defer(function(store)
        if store.phase ~= "VOTE" or store.mode == nil or store.endsAt < 0 then return false end
        return nextMatch(store, store.settings().prematch)
    end)
end

---@param result? any
---@return boolean
function match.Finish(result)
    return defer(function(store)
        if store.phase == "LIVE" then store.result = result end
        return match._SetPhase("POSTMATCH", store.settings().postmatch)
    end)
end

---@param reason string
---@return boolean
function match.Abort(reason)
    local store = PW._Match
    store.abortReason = tostring(reason)
    store.log("match aborted: " .. store.abortReason)
    return defer(function(current)
        if current.phase == "LOBBY" then return false end
        return match._SetPhase("LOBBY")
    end)
end

---@param ply any
---@param ready? boolean
function match.SetReady(ply, ready)
    PW._Match.ready[ply] = ready ~= false or nil
end

---@param ply any
function match._SetLoaded(ply)
    local store = PW._Match
    store.loaded[ply] = true
    store.ready[ply] = true
end

function match.GetPhase()
    return PW._Match.phase
end

function match.GetPhaseEnd()
    return PW._Match.endsAt
end

function match.GetAbortReason()
    return PW._Match.abortReason
end

function match._Tick()
    local store = PW._Match
    if store.busy then return end
    local allReady = store.phase == "PREMATCH" and PW.Phase._AllReady(store.players(), store.ready)
    local step = PW.Phase._Next(store, store.clock(), allReady, store.settings())
    if step ~= nil and step.begin and store.mode ~= nil then
        nextMatch(store, step.duration)
    elseif step ~= nil then
        match._SetPhase(step.phase, step.duration, step.countdown)
    end
    if store.phase == "LIVE" and store.mode ~= nil then PW.Call(store.mode, "Think") end
end

PW.Privilege("pw.match.abort", "superadmin")

---@param ply any
---@param args string[]
---@return boolean
function match._AbortCommand(ply, args)
    local fromPlayer = IsValid(ply)
    if fromPlayer and not PW.Can(ply, "pw.match.abort") then
        PW._Match.log(string.format("pw_abort denied for %s", tostring(ply:Nick())))
        return false
    end
    local text = table.concat(args, " ")
    if text == "" then
        text = "aborted by " .. (fromPlayer and tostring(ply:Nick()) or "the server console")
    end
    match.Abort(text)
    return true
end

concommand.Add("pw_abort", function(ply, _, args) match._AbortCommand(ply, args) end, nil,
    "Private War: abort the match and return to the lobby (optional reason)")

hook.Add("Think", "PW.Match", function() match._Tick() end)
hook.Add("PlayerDisconnected", "PW.Match", function(ply)
    PW._Match.loaded[ply] = nil
    PW._Match.ready[ply] = nil
end)
-- NW2 values set before InitPostEntity may not reach clients (notes/10 R4): a phase set earlier (the initial LOBBY,
-- or a transition made while the map loads) is counted in seq and published here.
hook.Add("InitPostEntity", "PW.Match", function() match._Publish() end)
