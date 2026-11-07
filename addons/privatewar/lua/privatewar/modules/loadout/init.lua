-- Loadout module, server glue (T-4.1). During LIVE the engine hook PlayerLoadout (called by the base GM:PlayerSpawn)
-- is answered here: the player's weapons are replaced by the resolved loadout and the hook returns true, so the base
-- gamemode's own PlayerLoadout never runs. Outside LIVE the hook answers nothing and the base behaviour stays.

local lib = PW.Loadout --[[@as PW.LoadoutLib]]

include("privatewar/modules/loadout/sv_gunsmith.lua")
include("privatewar/modules/loadout/sv_classes.lua")

---Gives the items of one weapons slot; the first weapon given carries the slot's build (T-4.8).
---@param ply Player
---@param items string[]
---@param given string[]
---@param entities Weapon[]
---@return Weapon?
local function giveSlot(ply, items, given, entities)
    ---@type Weapon?
    local first
    for index, class in ipairs(items) do
        local wep = PW.WeaponAmmo.Give(ply, class)
        if wep ~= nil then
            given[#given + 1], entities[#entities + 1] = class, wep
            if index == 1 then first = wep end
        end
    end
    return first
end

function lib.Give(ply, loadout)
    ply:StripWeapons()
    ply:RemoveAllAmmo()
    ---@type string[]
    local given = {}
    ---@type Weapon[]
    local entities = {}
    ---@type table<string, Weapon>
    local firsts = {}
    local store = PW._Loadout
    for _, id in ipairs(store.order) do
        local slot = store.slots[id]
        local items = slot.kind == "weapons" and loadout[id] ~= nil and lib._Items(loadout[id]) or nil
        if items ~= nil then firsts[id] = giveSlot(ply, items, given, entities) end
    end
    lib._GunsmithOnGive(ply, loadout, firsts)
    lib._PrepareForBot(ply, entities)
    if given[1] ~= nil then ply:SelectWeapon(given[1]) end
    -- T-4.4: other slot kinds (perks) apply the new loadout here, on spawn and when a mode gives a new loadout.
    PW.Notify("PW_LoadoutGiven", ply, loadout)
    return given
end

-- T-4.3: the wildcards a player has equipped (ply -> ids); their Stats reach PW.Stat through PW.Perks.StatSource.
---@type table<any, string[]>
PW._Wildcards = PW._Wildcards or setmetatable({}, { __mode = "k" })

function lib._EquipWildcards(ply, loadout, lookup)
    local ids = lib._Items(loadout[lib.WildcardSlot]) or {}
    ---@type string[]
    local equipped = {}
    for _, id in ipairs(ids) do
        if lookup("wildcards", id) ~= nil then equipped[#equipped + 1] = id end
    end
    PW._Wildcards[ply] = #equipped > 0 and equipped or nil
end

---@param ply any
---@return table<string, number>[]
local function wildcardStats(ply)
    local ids = PW._Wildcards[ply]
    if ids == nil then return {} end
    return lib._WildcardStats(ids, lib._RegistryLookup)
end

-- The perks module may load after this one: register on load and again when every registry is loaded.
local function registerStatSource()
    local perks = rawget(PW, "Perks") --[[@as PW.PerksLib?]]
    if perks ~= nil then perks.StatSource("wildcards", wildcardStats) end
end

registerStatSource()

function MODULE:PW_RegistriesLoaded()
    registerStatSource()
end

function MODULE:PW_LoadoutGiven(ply, loadout)
    if not istable(loadout) then return end
    lib._EquipWildcards(ply, loadout, lib._RegistryLookup)
    local perks = rawget(PW, "Perks") --[[@as PW.PerksLib?]]
    -- The perks module recomputes on the same notification; do it again in case it ran first.
    if perks ~= nil and perks._Recompute ~= nil then perks._Recompute(ply) end
end

function lib._OnPlayerLoadout(ply)
    local match = PW.Match
    if match == nil or match.GetPhase() ~= "LIVE" then return nil end
    local loadout = lib.Resolve(ply)
    lib.Give(ply, loadout)
    return true
end

PW.HookFor(MODULE, "PlayerLoadout", function(_, ply)
    return lib._OnPlayerLoadout(ply)
end)
