-- Progression, server glue (T-4.9; 06-progression.md d.1). The session state of every human player (total XP and XP
-- per weapon class, the shape T-4.10 stores), the listener of PW_ScoreEvent, the NW2 publication for the HUD and the
-- server views of the unlock checks. Storage and transfer (10 s deltas, join upload, levels for the client, match
-- summary) are sv_storage.lua. Engine edges (settings, NW2, notifications, net senders, the classes refresh) are
-- fields of the store, so the tests drive everything with fakes.
--
-- Notifications (no return value): PW_ProgressionXP(ply, xp, weaponClass?), PW_ProgressionLevelUp(ply, level,
-- oldLevel), PW_ProgressionWeaponLevelUp(ply, weaponClass, level, oldLevel).

local lib = PW.Progression --[[@as PW.ProgressionLib]]

include("privatewar/modules/progression/sv_storage.lua")
include("privatewar/modules/progression/sv_wallet.lua")

---@param ply Player
---@param level integer
---@param into integer
---@param need integer
local function defaultPublish(ply, level, into, need)
    ply:SetNW2Int(lib._KeyLevel, level)
    ply:SetNW2Int(lib._KeyInto, into)
    ply:SetNW2Int(lib._KeyNeed, need)
end

---@param eventId string
---@return boolean
local function defaultIsMedal(eventId)
    local event = lib._RegistryLookup("score_events", eventId)
    return event ~= nil and event.Medal == true
end

---The medals of this match from the medals module (T-4.11), nil when it is not loaded or not enabled.
---@param ply Player
---@return table<string, integer>?
local function defaultMedalsOf(ply)
    local medals = rawget(PW, "Medals") --[[@as PW.MedalsLib?]]
    if medals == nil or not isfunction(medals.Get) or rawget(PW, "_Medals") == nil then return nil end
    return medals.Get(ply)
end

local function noop() end

---@return table
local function weakKeys()
    return setmetatable({}, { __mode = "k" })
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        players = weakKeys(), pending = weakKeys(), batches = weakKeys(), matches = weakKeys(), uploaded = weakKeys(),
        read = opts.read or function(id) return PW.Setting(id) end,
        publish = opts.publish or defaultPublish,
        notify = opts.notify or function(name, ...) PW.Notify(name, ...) end,
        sendDelta = opts.sendDelta or noop, sendLevels = opts.sendLevels or noop,
        sendSummary = opts.sendSummary or noop, refresh = opts.refresh or noop,
        isMedal = opts.isMedal or defaultIsMedal, medalsOf = opts.medalsOf or defaultMedalsOf,
        ownedActive = opts.ownedActive or function() return lib._OwnedActive() end
    }
end

do -- a reload keeps the sessions and the batching, the functions are new
    local previous = rawget(PW, "_Progression") --[[@as PW.ProgressionStore?]]
    local store = lib._NewStore(lib._LiveEdges())
    if previous ~= nil then
        store.players = previous.players
        store.pending = previous.pending or store.pending
        store.batches = previous.batches or store.batches
        store.matches = previous.matches or store.matches
        store.uploaded = previous.uploaded or store.uploaded
        store.nextFlush = previous.nextFlush
    end
    PW._Progression = store
end

---@param store PW.ProgressionStore
---@param ply Player
---@return PW.ProgressionState
local function stateOf(store, ply)
    local state = store.players[ply]
    if state == nil then
        state = { xp = 0, weapons = {}, currency = 0, owned = {} }
        store.players[ply] = state
    end
    -- A session kept across a reload may predate the wallet fields.
    state.currency = state.currency or 0
    state.owned = state.owned or {}
    return state
end

lib._StateOf = stateOf

---@param store PW.ProgressionStore
---@param ply Player
local function publishLevel(store, ply)
    local level, into, need = lib._PlayerLevel(lib._Params(store.read), stateOf(store, ply).xp)
    store.publish(ply, level, into, need)
end

function lib._Level(store, ply)
    local level = lib._PlayerLevel(lib._Params(store.read), stateOf(store, ply).xp)
    return level
end

function lib._WeaponLevelOf(store, ply, weaponClass)
    local level = lib._WeaponLevel(lib._Params(store.read), stateOf(store, ply).weapons[weaponClass] or 0)
    return level
end

function lib._GetState(store, ply)
    return table.Copy(stateOf(store, ply)) --[[@as PW.ProgressionState]]
end

---@param value any
---@return number
local function sane(value)
    if not isnumber(value) then return 0 end
    local number = value --[[@as number]]
    if number ~= number or number < 0 or number == math.huge then return 0 end
    return math.floor(number)
end

function lib._SetState(store, ply, state)
    local source = istable(state) and state or {}
    ---@type table<string, number>
    local weapons = {}
    local list = istable(source.weapons) and source.weapons or {}
    for class, xp in pairs(list --[[@as table<any, any>]]) do
        if isstring(class) and sane(xp) > 0 then weapons[class] = sane(xp) end
    end
    store.players[ply] = {
        xp = sane(source.xp), weapons = weapons,
        currency = lib._CheckXP(source.currency, lib.MaxCurrency) or 0,
        owned = lib._CheckOwned(source.owned, lib.MaxOwned)
    }
    publishLevel(store, ply)
end

---@param store PW.ProgressionStore
---@param ply Player
---@param weaponClass string
---@param amount number
---@param params PW.ProgressionParams
---@return boolean levelled the weapon level grew
local function addWeapon(store, ply, weaponClass, amount, params)
    local weapons = stateOf(store, ply).weapons
    local before = lib._WeaponLevel(params, weapons[weaponClass] or 0)
    weapons[weaponClass] = (weapons[weaponClass] or 0) + amount
    local after = lib._WeaponLevel(params, weapons[weaponClass])
    if after > before then store.notify("PW_ProgressionWeaponLevelUp", ply, weaponClass, after, before) end
    return after > before
end

---Adds scaled XP to the player and, with a class, to the weapon. The gain joins the next delta and this match's
---record; a level change resends the levels and re-checks the classes (T-4.10).
---@param store PW.ProgressionStore
---@param ply Player
---@param amount number
---@param weaponClass string?
local function gain(store, ply, amount, weaponClass)
    local params = lib._Params(store.read)
    local scaled = math.floor(sane(amount) * params.xpScale)
    if scaled <= 0 then return end
    lib._Track(store, ply, scaled, weaponClass)
    local state = stateOf(store, ply)
    local before = lib._PlayerLevel(params, state.xp)
    state.xp = state.xp + scaled
    store.notify("PW_ProgressionXP", ply, scaled, weaponClass)
    local after = lib._PlayerLevel(params, state.xp)
    if after > before then store.notify("PW_ProgressionLevelUp", ply, after, before) end
    local weaponUp = weaponClass ~= nil and addWeapon(store, ply, weaponClass, scaled, params)
    publishLevel(store, ply)
    if after > before or weaponUp then lib._LevelsChanged(store, ply) end
end

---The class of a valid weapon entity, nil otherwise.
---@param weapon Weapon?
---@return string?
local function classOf(weapon)
    if weapon == nil or not IsValid(weapon) then return nil end
    local class = weapon:GetClass()
    if isstring(class) and class ~= "" then return class end
    return nil
end

function lib._OnScoreEvent(store, ply, eventId, _, xp, weapon)
    -- Only a real Player earns: other score receivers (stand-ins without IsBot) are ignored.
    if not IsValid(ply) or not isfunction(ply.IsBot) or ply:IsBot() then return end
    if isstring(eventId) and store.isMedal(eventId) then lib._CountMedal(store, ply, eventId) end
    gain(store, ply, xp, classOf(weapon))
end

function lib.GetState(ply)
    return lib._GetState(PW._Progression, ply)
end

function lib.SetState(ply, state)
    lib._SetState(PW._Progression, ply, state)
end

function lib.AddXP(ply, amount, weaponClass)
    gain(PW._Progression, ply, amount, weaponClass)
end

-- Unlock checks (the public IsUnlocked, LockedOptions, AttachmentLimit and GetWeaponLevel are in shared.lua) --------

function lib._ViewOf(store, ply, lookup)
    local params = lib._Params(store.read)
    local cap = store.read("loadout.maxattachments")
    local owned = nil
    if store.ownedActive() then
        owned = function(key) return lib._GetOwned(store, ply)[key] == true end
    end
    return {
        level = lib._Level(store, ply),
        weaponLevel = function(weaponId) return lib._WeaponLevelOf(store, ply, weaponId) end,
        lookup = lookup, unlockAll = params.unlockAll, maxAttachments = isnumber(cap) and cap --[[@as number]] or 5,
        owned = owned
    }
end

-- Hooks --------------------------------------------------------------------------------------------------------------

---@param ply Player
---@param eventId string
---@param points number
---@param xp number
---@param weapon Weapon?
function MODULE:PW_ScoreEvent(ply, eventId, points, xp, weapon)
    lib._OnScoreEvent(PW._Progression, ply, eventId, points, xp, weapon)
end

PW.HookFor(MODULE, "PlayerInitialSpawn", function(_, ply)
    local player = ply --[[@as Player]]
    if IsValid(player) and not player:IsBot() then publishLevel(PW._Progression, player) end
end)
