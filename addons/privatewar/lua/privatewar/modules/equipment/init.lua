-- Equipment module, server glue (T-4.5, T-11.4). Per-player state: for each equipment slot the item id, the uses
-- left, the item's instance for this life (PW.Instance), the item's grenade SWEP class and the time of the last use.
-- Spawn in LIVE equips the resolved loadout with full counts; once the loadout's weapons are given
-- (PW_LoadoutGiven, a tick later so perks are equipped) every slot's grenade SWEP is given with ammo = count.
-- Death, disconnect and the end of the match empty it; a grenade being cooked at death is dropped first. A use (the
-- grenade SWEP's release through _Release, or a bot through Use) calls OnUse on the instance through PW.Call. Engine
-- calls are fields of the store, so the tests drive the rules with fakes; the SWEP parts are sv_grenades.lua.

local lib = PW.Equipment --[[@as PW.EquipmentLib]]

include("privatewar/modules/equipment/sv_grenades.lua")

---@param ply Player
---@return PW.Loadout
local function defaultResolve(ply)
    local loadout = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
    if loadout == nil then return {} end
    return (loadout.Resolve(ply))
end

---@param ply Player
---@param slot string
---@param id string
---@param count integer
local function defaultPublish(ply, slot, id, count)
    if not IsValid(ply) then return end
    ply:SetNW2String(lib._ItemKey(slot), id)
    ply:SetNW2Int(lib._CountKey(slot), count)
    local class = lib._ItemWeapon(id)
    local ammo = class ~= nil and lib._AmmoOf(class) or nil
    if ammo ~= nil then ply:SetAmmo(count, ammo) end
end

---@return string
local function defaultPhase()
    local match = rawget(PW, "Match") --[[@as PW.MatchLib?]]
    if match == nil then return "LOBBY" end
    return match.GetPhase()
end

---@param ply Player
---@return boolean
local function defaultAlive(ply)
    return IsValid(ply) and ply:Alive()
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        players = setmetatable({}, { __mode = "k" }),
        previous = setmetatable({}, { __mode = "k" }),
        lookup = opts.lookup or lib._Lookup,
        resolve = opts.resolve or defaultResolve,
        publish = opts.publish or defaultPublish,
        clock = opts.clock or CurTime,
        phase = opts.phase or defaultPhase,
        alive = opts.alive or defaultAlive,
        afterThrow = opts.afterThrow or lib._AfterThrow
    }
end

PW._Equipment = PW._Equipment or lib._NewStore()

---@return PW.EquipmentStore
local function store()
    return PW._Equipment --[[@as PW.EquipmentStore]]
end

---@param s PW.EquipmentStore
---@param ply Player
local function endAll(s, ply)
    local slots = s.players[ply]
    if slots == nil then return end
    s.players[ply] = nil
    for slot, entry in pairs(slots) do
        entry.instance:Remove()
        s.publish(ply, slot, "", 0)
    end
end

function lib._Clear(ply)
    endAll(store(), ply)
end

---The first item id of a loadout value (a slot may hold a list).
---@param value any
---@return string?
local function firstItem(value)
    if isstring(value) then return value --[[@as string]] end
    if istable(value) and isstring(value[1]) then return value[1] --[[@as string]] end
    return nil
end

function lib._Equip(ply)
    local s = store()
    endAll(s, ply)
    local loadout = s.resolve(ply)
    ---@type table<string, PW.EquipmentEntry>
    local slots = {}
    for _, slot in ipairs(lib.Slots) do
        local id = firstItem(loadout[slot])
        local def = id ~= nil and s.lookup(id) or nil
        if id ~= nil and def ~= nil then
            local entry = { id = id, count = lib._Refill(def), instance = PW.Instance(def, ply), last = -math.huge,
                weapon = lib._WeaponOf(def) }
            slots[slot] = entry
            s.publish(ply, slot, id, entry.count)
        end
    end
    s.players[ply] = slots
end

function lib._OnSpawn(ply)
    if store().phase() ~= "LIVE" then return false end
    lib._Equip(ply)
    return true
end

function lib.Count(ply, slot)
    local slots = store().players[ply]
    local entry = slots ~= nil and slots[slot] or nil
    if entry == nil then return 0 end
    return entry.count
end

function lib.Item(ply, slot)
    local slots = store().players[ply]
    local entry = slots ~= nil and slots[slot] or nil
    if entry == nil then return nil end
    return entry.id
end

---The slot's entry when the player may use it now (LIVE, alive, equipped), else nil.
---@param ply Player
---@param slot string
---@return PW.EquipmentEntry?
function lib._UsableEntry(ply, slot)
    local s = store()
    if s.phase() ~= "LIVE" or not s.alive(ply) then return nil end
    if s.players[ply] == nil then lib._Equip(ply) end
    return (s.players[ply] or {})[slot]
end

---Uses an entry: the use rule, OnUse with the options, the count and the cooldown. Returns whether it was used.
---@param ply Player
---@param slot string
---@param entry PW.EquipmentEntry
---@param opts PW.EquipmentUse?
---@return boolean
function lib._Spend(ply, slot, entry, opts)
    local s = store()
    local now = s.clock()
    if not lib._CanUse(entry, now, lib.Cooldown) then return false end
    if PW.Call(entry.instance, "OnUse", ply, opts) == false then return false end
    entry.count = entry.count - 1
    entry.last = now
    s.publish(ply, slot, entry.id, entry.count)
    return true
end

function lib.Use(ply, slot, opts)
    local entry = lib._UsableEntry(ply, slot)
    if entry == nil then return false end
    if entry.weapon ~= nil then return lib._BotThrow(ply, slot, entry, opts) end
    return lib._Spend(ply, slot, entry, opts)
end

function lib._Release(ply, wep, opts)
    local slot = (wep --[[@as table]]).PWSlot --[[@as string?]]
    if slot == nil then return false end
    local entry = lib._UsableEntry(ply, slot)
    if entry == nil or entry.weapon ~= wep:GetClass() then return false end
    local use = opts or {}
    use.weapon = wep
    if not lib._Spend(ply, slot, entry, use) then return false end
    store().afterThrow(ply, slot, entry.count)
    return true
end

function MODULE:PW_MatchEnd()
    for ply in pairs(store().players) do lib._Clear(ply) end
end

function MODULE:PW_LoadoutGiven(ply)
    -- A tick later: perks and wildcards are equipped on the same notification and may answer PW_EquipmentCount.
    timer.Simple(0, function()
        if IsValid(ply) and ply:Alive() and store().phase() == "LIVE" then lib._GiveWeapons(ply) end
    end)
end

PW.HookFor(MODULE, "PlayerSwitchWeapon", function(_, ply, old, new)
    lib._Remember(ply, old, new)
end)

PW.HookFor(MODULE, "PlayerSpawn", function(_, ply)
    lib._OnSpawn(ply)
end)

-- Before PostPlayerDeath ends the instances and while the dying player still holds the grenade SWEP.
PW.HookFor(MODULE, "DoPlayerDeath", function(_, ply)
    lib._DropOnDeath(ply)
end)

PW.HookFor(MODULE, "PostPlayerDeath", function(_, ply)
    lib._Clear(ply)
end)

PW.HookFor(MODULE, "PlayerDisconnected", function(_, ply)
    lib._Clear(ply)
end)
