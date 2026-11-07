-- Map change (T-1.14, 00-core.md d.9). Server only. PW.Match.Start(mode, map) asks PW.MapChange._Decide what to do
-- with the target map: the same map goes straight to PREMATCH; another one writes data/privatewar/pending_match.json
-- BEFORE changelevel, behind a guard that refuses a second start. The new map reads and deletes the file one tick
-- after server InitPostEntity and starts the match only when the file is valid (map, map change count + 1,
-- younger than 120 s, known version) and its mode exists; otherwise it stays in LOBBY. Still on the old map 10 s
-- after the command: back to the lobby state with an abort reason for the host. Clients report "loaded" with
-- pw_client_ready (resent by cl_ready.lua every 2 s until pw_client_ready_ack, garrysmod-issues #5081). The rules
-- are pure functions; file access, changelevel, the clocks and the ack are injectable store fields, so tests never
-- change the map. The file carries the match settings snapshot (T-1.5); the new map restores it as the pending
-- settings (invalid values dropped) before it starts the match, which takes the snapshot again. Team assignment
-- (T-1.16) is asked from the modules through the question hook PW_PendingTeams(mode); the new map hands it back in
-- PW_PendingMatchApplied.

-- Delayed change: PW.Match.Start asks lib.Schedule, which announces the target (NW2 globals of
-- PW.Phase._ChangeKeys: map, mode, end time) and runs _Begin pw_mapchange_delay seconds later (_Tick), so clients
-- show the map change popup and the START button counts down. The guard is busy from the announcement on; a phase
-- change cancels a change that has not run yet (a rotation aborted in VOTE).

local ackName = "pw_client_ready_ack"

local delayVar = CreateConVar("pw_mapchange_delay", "5", { FCVAR_ARCHIVE },
    "Private War: seconds the map change popup shows before changelevel", 0, 60)

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

local lib = (rawget(PW, "MapChange") or {}) --[[@as PW.MapChangeLib]]
PW.MapChange = lib

lib._Version = 1
lib._MaxAge = 120
lib._FailAfter = 10

---@param id string
---@return table?
local function resolveMode(id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local modes = registries ~= nil and registries.modes or nil
    if modes == nil then return nil end
    return modes.Get(id)
end

---@param map string
local function changelevel(map)
    RunConsoleCommand("changelevel", map)
end

---Publishes the announced change (map -> mode -> at); at < 0 clears it.
---@param map string
---@param mode string
---@param at number
local function announce(map, mode, at)
    local keys = PW.Phase._ChangeKeys
    SetGlobal2String(keys.map, map)
    SetGlobal2String(keys.mode, mode)
    SetGlobal2Float(keys.at, at)
end

---@return number
local function readDelay()
    return delayVar:GetFloat()
end

---@param ply Player
local function sendAck(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    net.Start(ackName)
    net.Send(ply)
end

---The bot target of the next match (T-5.1): asked from the bots manager when it is loaded, else the current bots.
---@param settings table<string, any>
---@return integer
local function botCount(settings)
    local manager = rawget(PW, "BotsManager") --[[@as PW.BotsManagerLib?]]
    if manager ~= nil and manager.PendingTarget ~= nil then return manager.PendingTarget(settings) end
    return #player.GetBots()
end

---@param opts? PW.MapChangeStoreOptions
---@return PW.MapChangeStore
function lib._NewStore(opts)
    opts = opts or {}
    return {
        path = opts.path or "privatewar/pending_match.json",
        log = opts.log or defaultLog,
        clock = opts.clock or CurTime,
        time = opts.time or os.time,
        map = opts.map or game.GetMap,
        mapChangeCount = opts.mapChangeCount or game.GetMapChangeCount,
        bots = opts.bots or botCount,
        resolveMode = opts.resolveMode or resolveMode,
        changelevel = opts.changelevel or changelevel,
        ack = opts.ack or sendAck,
        delay = opts.delay or readDelay,
        announce = opts.announce or announce
    }
end

PW._MapChange = PW._MapChange or lib._NewStore()
-- A store made by older code (pw_reload keeps it) gets the fields added since.
PW._MapChange.delay = PW._MapChange.delay or readDelay
PW._MapChange.announce = PW._MapChange.announce or announce

---@return boolean
function lib.IsChanging()
    local store = PW._MapChange
    return store.changing ~= nil or store.scheduled ~= nil
end

---@param current string
---@param target string?
---@param changing boolean
---@return PW.MapChangeStep
function lib._Decide(current, target, changing)
    if changing then return "busy" end
    if target == nil or target == current then return "prematch" end
    return "changelevel"
end

local fieldTypes = {
    map = "string", mode = "string", settings = "table", bots = "number", teams = "table", createdAt = "number",
    mapChangeCount = "number"
}

---@param pending any
---@param facts PW.PendingFacts
---@return boolean
---@return PW.PendingReason?
function lib._Validate(pending, facts)
    if pending == nil then return false, "missing" end
    if not istable(pending) or not isnumber(pending.v) then return false, "corrupt" end
    if pending.v ~= lib._Version then return false, "version" end
    for field, expected in pairs(fieldTypes) do
        if type(pending[field]) ~= expected then return false, "corrupt" end
    end
    if pending.map ~= facts.map then return false, "map" end
    if facts.mapChangeCount ~= pending.mapChangeCount + 1 then return false, "count" end
    local createdAt = pending.createdAt --[[@as number]]
    local age = facts.now - createdAt
    if age < 0 or age >= lib._MaxAge then return false, "age" end
    return true
end

---@param pending PW.PendingMatch
---@return string
function lib._Encode(pending)
    return util.TableToJSON(pending)
end

---@param text string
---@return table<string, any>?
function lib._Decode(text)
    local decoded = util.JSONToTable(text, false, true)
    if not istable(decoded) then return nil end
    return decoded --[[@as table<string, any>]]
end

---@param store PW.MapChangeStore
local function deleteFile(store)
    if file.Exists(store.path, "DATA") then file.Delete(store.path) end
end

---The match settings the new map restores as pending values (T-1.5): the would-be snapshot for mode.
---@param mode table
---@return table<string, any>
local function settingsFor(mode)
    local forFile = PW.Settings._ForFile
    if forFile == nil then return {} end
    return forFile(mode)
end

---Team by SteamID64 for the new map (T-1.16): the question hook PW_PendingTeams(mode), answered by the teams
---module; {} when nobody answers with a table.
---@param mode table
---@return table<string, integer>
local function teamsFor(mode)
    local answer = PW.Ask("PW_PendingTeams", mode)
    if not istable(answer) then return {} end
    return answer --[[@as table<string, integer>]]
end

---@param store PW.MapChangeStore
---@param mode table
---@param map string
---@return PW.PendingMatch
local function buildPending(store, mode, map)
    local settings = settingsFor(mode)
    return {
        v = lib._Version, map = map, mode = mode.ClassName --[[@as string]], settings = settings,
        bots = store.bots(settings), teams = teamsFor(mode), createdAt = store.time(),
        mapChangeCount = store.mapChangeCount()
    }
end

---@param mode table
---@param map string
---@return boolean
function lib._Begin(mode, map)
    local store = PW._MapChange
    local modeId = mode.ClassName --[[@as string]]
    local directory = string.match(store.path, "^(.*)/[^/]*$")
    if directory ~= nil then file.CreateDir(directory) end
    file.Write(store.path, lib._Encode(buildPending(store, mode, map)))
    if not file.Exists(store.path, "DATA") then
        store.log(string.format("map change to %s cancelled: could not write data/%s", map, store.path))
        return false
    end
    store.changing = { map = map, deadline = store.clock() + lib._FailAfter }
    store.log(string.format("changing map to %s for mode %s", map, modeId))
    store.changelevel(map)
    return true
end

---@param mode table
---@param map string
---@return boolean
function lib.Schedule(mode, map)
    local store = PW._MapChange
    local delay = store.delay()
    if delay <= 0 then return lib._Begin(mode, map) end
    local at = store.clock() + delay
    store.scheduled = { mode = mode, map = map, at = at }
    store.announce(map, tostring(mode.ClassName), at)
    store.log(string.format("map change to %s for mode %s in %g s", map, tostring(mode.ClassName), delay))
    return true
end

---@param reason string
---@return boolean
function lib._Cancel(reason)
    local store = PW._MapChange
    local scheduled = store.scheduled
    if scheduled == nil then return false end
    store.scheduled = nil
    store.announce("", "", -1)
    store.log(string.format("map change to %s cancelled: %s", scheduled.map, reason))
    return true
end

---Runs a scheduled change that is due. A change that cannot begin (the pending file) returns a match to the lobby.
---@param store PW.MapChangeStore
local function runScheduled(store)
    local scheduled = store.scheduled
    if scheduled == nil or store.clock() < scheduled.at then return end
    store.scheduled = nil
    if lib._Begin(scheduled.mode, scheduled.map) then return end
    store.announce("", "", -1)
    local match = PW.Match
    if match ~= nil and match.GetPhase() ~= "LOBBY" then
        match.Abort("map change to " .. scheduled.map .. " failed: the pending file could not be written")
    end
end

function lib._Tick()
    local store = PW._MapChange
    runScheduled(store)
    local target = store.changing
    if target == nil or store.clock() < target.deadline then return end
    store.changing = nil
    deleteFile(store)
    store.announce("", "", -1)
    local reason = string.format("map change to %s failed: still on %s after %g s", target.map, store.map(),
        lib._FailAfter)
    local match = PW.Match
    if match ~= nil then match.Abort(reason) else store.log(reason) end
end

---@return boolean
---@return PW.PendingReason?
function lib._Apply()
    local store = PW._MapChange
    local text = file.Read(store.path, "DATA")
    if text == nil then return false, "missing" end
    deleteFile(store)
    local pending = lib._Decode(text)
    ---@type PW.PendingFacts
    local facts = { map = store.map(), mapChangeCount = store.mapChangeCount(), now = store.time() }
    ---@type boolean, PW.PendingReason?
    local ok, reason = false, "corrupt"
    if pending ~= nil then ok, reason = lib._Validate(pending, facts) end
    if not ok or pending == nil then
        store.log(string.format("pending match rejected (%s), staying in LOBBY: file %s, this map %s %s at %s",
            tostring(reason), string.gsub(text, "%s+", " "), facts.map, tostring(facts.mapChangeCount),
            tostring(facts.now)))
        return false, reason
    end
    local valid = pending --[[@as PW.PendingMatch]]
    local mode = store.resolveMode(valid.mode)
    if mode == nil then
        store.log(string.format("pending match rejected: unknown mode %q, staying in LOBBY", valid.mode))
        return false, "mode"
    end
    local fromFile = PW.Settings._FromFile
    if fromFile ~= nil then fromFile(valid.settings) end
    local match = PW.Match
    if match == nil or not match.Start(mode) then return false, "start" end
    PW.Notify("PW_PendingMatchApplied", valid)
    return true
end

---@param ply Player
function lib._OnClientReady(ply)
    local match = PW.Match
    if match ~= nil then match._SetLoaded(ply) end
    PW._MapChange.ack(ply)
end

-- Any phase: a client finishes loading whenever it joins (LOBBY, a match in progress, after changelevel). The
-- client sends one empty message every 2 s, so rate 1 per second leaves room and still caps a flood; maxLen 8
-- bytes because the message carries no payload.
PW.Net.Receive("pw_client_ready", { who = "any", rate = 1, maxLen = 8 }, function(ply) lib._OnClientReady(ply) end)
util.AddNetworkString(ackName)

hook.Add("Think", "PW.MapChange", function() lib._Tick() end)
-- game.GetMapChangeCount() grows only after server InitPostEntity (measured on the Deck: still the old count in
-- Initialize and InitPostEntity, +1 from the first tick), so the file is checked one tick later.
hook.Add("InitPostEntity", "PW.MapChange", function() timer.Simple(0, function() lib._Apply() end) end)
