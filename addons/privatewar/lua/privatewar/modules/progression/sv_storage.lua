-- Progression storage, server (T-4.10; 06-progression.md d.5). The server stores nobody's progression between
-- sessions: the client uploads its file on join, the server sanity-checks it (forgery is accepted, sizes are bounded)
-- and from then on sends the owner only what changed. Included by init.lua.
--
--   1. Join upload (pw_progression_upload, client -> server, accepted once per connection): _CheckState, then
--      SetState; the levels go back to the client and the classes are re-checked.
--   2. Every gain joins the player's pending delta; every FlushInterval (10 s) and on every phase change the pending
--      deltas leave as pw_progression_delta with a batch id (a random session per connection, seq + 1), never empty.
--   3. pw_progression_levels (player level, weapon levels above 1, unlockall, the attachment cap) after the upload,
--      on every level change and on entering PREMATCH, so client-side IsUnlocked answers like the server.
--   4. A match record per player from PW_MatchStart: XP gained, level at the first gain, weapon levels at their
--      first gain. Medals come from PW.Medals.Get (T-4.11) when the medals module is loaded, else from the score
--      events with Medal = true counted here. At POSTMATCH the deltas are flushed and every player gets
--      pw_progression_summary.
--   5. A level change (player or weapon) calls the loadout's RefreshClasses, so the selected class is re-checked at
--      once (T-4.9 lane decision 4).

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.ProgressionModuleStorage : PW.Module
local module = MODULE --[[@as PW.ProgressionModuleStorage]]

local lib = PW.Progression --[[@as PW.ProgressionLib]]

---@param store PW.ProgressionStore
---@param ply Player
---@return PW.ProgressionMatch
local function matchOf(store, ply)
    local record = store.matches[ply]
    if record == nil then
        record = { xp = 0, levelBefore = lib._Level(store, ply), weapons = {}, medals = {} }
        store.matches[ply] = record
    end
    return record
end

function lib._PendingOf(store, ply)
    local pending = store.pending[ply]
    if pending == nil then
        pending = { xp = 0, weapons = {}, earned = 0, spent = 0, owned = {} }
        store.pending[ply] = pending
    end
    return pending
end

function lib._Track(store, ply, xp, weaponClass)
    local pending = lib._PendingOf(store, ply)
    local record = matchOf(store, ply)
    pending.xp = pending.xp + xp
    record.xp = record.xp + xp
    if weaponClass == nil then return end
    pending.weapons[weaponClass] = (pending.weapons[weaponClass] or 0) + xp
    if record.weapons[weaponClass] == nil then
        record.weapons[weaponClass] = lib._WeaponLevelOf(store, ply, weaponClass)
    end
end

function lib._CountMedal(store, ply, eventId)
    local medals = matchOf(store, ply).medals
    medals[eventId] = (medals[eventId] or 0) + 1
end

function lib._LevelsOf(store, ply)
    local view = lib._ViewOf(store, ply, lib._RegistryLookup)
    ---@type table<string, integer>
    local weapons = {}
    for class in pairs(lib._GetState(store, ply).weapons) do
        local level = view.weaponLevel(class)
        if level > 1 then weapons[class] = level end
    end
    return { level = view.level, weapons = weapons, unlockAll = view.unlockAll, maxAttachments = view.maxAttachments }
end

function lib._LevelsChanged(store, ply)
    store.sendLevels(ply, lib._LevelsOf(store, ply))
    store.refresh(ply)
end

-- Deltas -------------------------------------------------------------------------------------------------------------

function lib._Flush(store, ply)
    local pending = store.pending[ply]
    if pending == nil then return nil end
    store.pending[ply] = nil
    local batch = store.batches[ply]
    if batch == nil then
        batch = { session = math.random(1, 2 ^ 31 - 1), seq = 0 }
        store.batches[ply] = batch
    end
    batch.seq = batch.seq + 1
    ---@type PW.ProgressionDelta
    local delta = { session = batch.session, seq = batch.seq, xp = pending.xp, weapons = pending.weapons,
        earned = pending.earned, spent = pending.spent, owned = pending.owned }
    store.sendDelta(ply, delta)
    return delta
end

function lib._FlushAll(store)
    ---@type Player[]
    local players = {}
    for ply in pairs(store.pending) do players[#players + 1] = ply end
    for _, ply in ipairs(players) do lib._Flush(store, ply) end
end

function lib._Tick(store, now)
    if store.nextFlush == nil then
        store.nextFlush = now + lib.FlushInterval
        return
    end
    if now < store.nextFlush then return end
    store.nextFlush = now + lib.FlushInterval
    lib._FlushAll(store)
end

-- Upload, match, summary ---------------------------------------------------------------------------------------------

function lib._OnUpload(store, ply, raw)
    if store.uploaded[ply] then return false end
    store.uploaded[ply] = true
    lib._SetState(store, ply, lib._CheckState(raw, lib.MaxWeapons))
    lib._LevelsChanged(store, ply)
    return true
end

function lib._BeginMatch(store)
    for ply in pairs(store.matches) do store.matches[ply] = nil end
end

---@param tbl table<string, any>
---@return string[]
local function sortedKeys(tbl)
    ---@type string[]
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function lib._Summary(store, ply)
    local level = lib._Level(store, ply)
    ---@type PW.ProgressionSummary
    local summary = { xp = 0, levelBefore = level, levelAfter = level, weapons = {}, medals = {} }
    local record = store.matches[ply]
    -- The medals module (T-4.11) is the source when present; otherwise the Medal events this module counted.
    local medals = store.medalsOf(ply) or (record ~= nil and record.medals or {})
    for _, id in ipairs(sortedKeys(medals)) do
        summary.medals[#summary.medals + 1] = { id = id, count = medals[id] }
    end
    if record == nil then return summary end
    summary.xp, summary.levelBefore = record.xp, record.levelBefore
    for _, class in ipairs(sortedKeys(record.weapons)) do
        local before, after = record.weapons[class], lib._WeaponLevelOf(store, ply, class)
        if after > before then
            summary.weapons[#summary.weapons + 1] = { class = class, before = before, after = after }
        end
    end
    return summary
end

function lib._OnPostmatch(store)
    lib._FlushAll(store)
    ---@type table<Player, boolean>
    local players = {}
    for ply in pairs(store.matches) do players[ply] = true end
    for ply in pairs(store.uploaded) do players[ply] = true end
    for ply in pairs(players) do
        if IsValid(ply) then store.sendSummary(ply, lib._Summary(store, ply)) end
    end
end

-- Engine edges -------------------------------------------------------------------------------------------------------

local netDelta, netLevels, netSummary = "pw_progression_delta", "pw_progression_levels", "pw_progression_summary"
util.AddNetworkString(netDelta)
util.AddNetworkString(netLevels)
util.AddNetworkString(netSummary)

---@generic T
---@param name string
---@param encode fun(data: T, writer: PW.ProgressionWriter)
---@return fun(ply: Player, data: T)
local function sender(name, encode)
    return function(ply, data)
        if not IsValid(ply) then return end
        net.Start(name)
        encode(data, lib._NetWriter())
        net.Send(ply)
    end
end

---@param ply Player
local function refreshClasses(ply)
    local loadout = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
    if loadout == nil or not isfunction(loadout.RefreshClasses) or rawget(PW, "_LoadoutClasses") == nil then return end
    if IsValid(ply) then loadout.RefreshClasses(ply) end
end

function lib._LiveEdges()
    return {
        sendDelta = sender(netDelta, lib._EncodeDelta),
        sendLevels = sender(netLevels, lib._EncodeLevels),
        sendSummary = sender(netSummary, lib._EncodeSummary),
        refresh = refreshClasses
    }
end

PW.Net.Receive("pw_progression_upload", { who = "any", rate = 0.5, maxLen = lib.UploadMaxBytes, owner = module },
    function(ply) lib._OnUpload(PW._Progression, ply, lib._DecodeState(lib._NetReader())) end)

-- Hooks --------------------------------------------------------------------------------------------------------------

function module:PW_MatchStart()
    lib._BeginMatch(PW._Progression)
end

---@param phase PW.PhaseName
function module:PW_PhaseChange(phase)
    local store = PW._Progression --[[@as PW.ProgressionStore]]
    if phase == "POSTMATCH" then
        lib._OnPostmatch(store)
        return
    end
    lib._FlushAll(store)
    if phase ~= "PREMATCH" then return end
    -- The match settings snapshot (unlockall, loadout.maxattachments) is taken on entering PREMATCH: the levels go
    -- out again one frame later, while the module is still enabled.
    timer.Simple(0, function()
        if not IsValid(module) then return end
        for ply in pairs(store.uploaded) do
            if IsValid(ply) then store.sendLevels(ply, lib._LevelsOf(store, ply)) end
        end
    end)
end

PW.HookFor(module, "Tick", function()
    lib._Tick(PW._Progression, CurTime())
end)
