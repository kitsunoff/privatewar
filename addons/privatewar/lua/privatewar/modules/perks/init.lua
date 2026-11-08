-- Perks module, server glue (T-4.4). Per-player state: the equipped perk ids and one PW.Instance per perk, plus the
-- cached multipliers PW.Stat reads. PW_LoadoutGiven (spawn in LIVE, or a mode giving a new loadout) ends the old
-- instances, equips the loadout's perks and recomputes once; death, disconnect and the end of the match end them.
-- Kill and damage events reach the perk instances of the owner only. Engine calls are fields of the store, so the
-- tests drive everything with fakes.

local lib = PW.Perks --[[@as PW.PerksLib]]

include("privatewar/modules/perks/sv_effects.lua")

---@param id string
---@return PW.Perk?
local function defaultLookup(id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries.perks or nil
    if registry == nil then return nil end
    local def = registry.Get(id)
    if def == nil or not def:IsValid() then return nil end
    return def --[[@as PW.Perk]]
end

---@param ply any
---@param mods table<string, number>
local function defaultSend(ply, mods)
    local set = rawget(PW, "SetStatMods") --[[@as fun(ply: Player, mods: table<string, number>?)?]]
    if set ~= nil then set(ply, mods) end
end

---@param ent any
---@return boolean
local function defaultIsPlayer(ent)
    return IsValid(ent) and ent:IsPlayer()
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        players = setmetatable({}, { __mode = "k" }),
        stats = setmetatable({}, { __mode = "k" }),
        sent = setmetatable({}, { __mode = "k" }),
        lookup = opts.lookup or defaultLookup,
        send = opts.send or defaultSend,
        isPlayer = opts.isPlayer or defaultIsPlayer
    }
end

PW._Perks = PW._Perks or lib._NewStore()

---@return PW.PerksStore
local function store()
    return PW._Perks --[[@as PW.PerksStore]]
end

---@return boolean
local function active()
    local owner = PW.Modules ~= nil and PW.Modules.Get("perks") or nil
    return owner ~= nil and owner:IsValid()
end

local weaponKeys = { "reload_time", "draw_time", "ads_time", "sprint_to_fire", "recoil", "spread" }

---@return string[]
local function statKeys()
    local statMods = rawget(PW, "StatMods") --[[@as PW.StatModsLib?]]
    if statMods ~= nil and statMods._Keys ~= nil then return statMods._Keys end
    return weaponKeys
end

---@param a table<string, number>?
---@param b table<string, number>
---@return boolean
local function sameMods(a, b)
    if a == nil then return next(b) == nil end
    for key, value in pairs(a) do
        if b[key] ~= value then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

---The stat tables of every source for a player: perks, registered sources (sorted by id), the active mode.
---@param s PW.PerksStore
---@param ply any
---@return table<string, number>[][]
local function sourceLists(s, ply)
    ---@type table<string, number>[]
    local perkStats = {}
    for _, id in ipairs((s.players[ply] or { ids = {} }).ids) do
        local def = s.lookup(id)
        if def ~= nil and istable(def.Stats) then perkStats[#perkStats + 1] = def.Stats end
    end
    local lists = { perkStats }
    local ids = table.GetKeys(PW._PerkSources) --[[@as string[] ]]
    table.sort(ids)
    for _, id in ipairs(ids) do
        local source = PW._PerkSources[id]
        local ok, result = pcall(source, ply)
        if ok and istable(result) then lists[#lists + 1] = result --[[@as table<string, number>[] ]] end
    end
    local mode = rawget(PW, "ActiveMode") --[[@as table?]]
    if mode ~= nil and istable(mode.Stats) then lists[#lists + 1] = { mode.Stats } end
    return lists
end

---@param s PW.PerksStore
---@param ply any
---@param mods table<string, number>
local function sendMods(s, ply, mods)
    if sameMods(s.sent[ply], mods) then return end
    s.sent[ply] = mods
    s.send(ply, mods)
end

function lib._Recompute(ply)
    if not active() then return lib._Clear(ply) end
    local s = store()
    local stats = lib._Multiply(sourceLists(s, ply))
    s.stats[ply] = stats
    sendMods(s, ply, lib._WeaponMods(stats, statKeys()))
    lib._PublishEffects(ply, s.players[ply])
end

---@param s PW.PerksStore
---@param ply any
local function endPerks(s, ply)
    local entry = s.players[ply]
    if entry == nil then return end
    s.players[ply] = nil
    for _, instance in ipairs(entry.instances) do instance:Remove() end
end

function lib._Clear(ply)
    local s = store()
    endPerks(s, ply)
    s.stats[ply] = nil
    sendMods(s, ply, {})
    s.sent[ply] = nil
    lib._PublishEffects(ply, nil)
end

function lib.Revoke(ply)
    lib._Clear(ply)
end

function lib.Refresh(ply, loadout)
    if not active() then return lib.Revoke(ply) end
    if PW.Ask("PW_CanUseLoadoutKind", ply, "perks") == false then return lib.Revoke(ply) end
    local s = store()
    endPerks(s, ply)
    local loadoutStore = rawget(PW, "_Loadout") --[[@as PW.LoadoutStore?]]
    local order = loadoutStore ~= nil and loadoutStore.order or lib.Slots
    local slots = loadoutStore ~= nil and loadoutStore.slots or {}
    ---@type PW.PerksEntry
    local entry = { ids = {}, instances = {} }
    for _, id in ipairs(lib._PerkIds(order, slots, loadout)) do
        local def = s.lookup(id)
        if def ~= nil then
            local instance = PW.Instance(def, ply)
            if instance:IsValid() then
                entry.ids[#entry.ids + 1] = id
                entry.instances[#entry.instances + 1] = instance
            end
        end
    end
    s.players[ply] = entry
    lib._Recompute(ply)
end

function lib.Get(ply)
    local entry = store().players[ply]
    if entry == nil then return {} end
    return table.Copy(entry.ids)
end

---@param targets PW.PerkTarget[]
---@param dmg CTakeDamageInfo?
local function dispatch(targets, dmg)
    local s = store()
    for _, target in ipairs(targets) do
        local entry = s.players[target.owner]
        for _, instance in ipairs(entry ~= nil and entry.instances or {}) do
            PW.Call(instance, target.method, target.owner, target.other, dmg)
        end
    end
end

function lib._OnLoadoutGiven(ply, loadout)
    if not istable(loadout) then return end
    lib.Refresh(ply, loadout)
end

function lib._OnKilled(victim, attacker, dmg)
    dispatch(lib._Targets("kill", victim, attacker, store().isPlayer), dmg)
end

function lib._OnDamaged(victim, attacker, dmg)
    dispatch(lib._Targets("damage", victim, attacker, store().isPlayer), dmg)
end

function lib._OnDeath(ply)
    local streaks = rawget(PW, "Streaks") --[[@as PW.StreaksLib?]]
    if streaks ~= nil and streaks.SnapshotDeath ~= nil then streaks.SnapshotDeath(ply) end
    lib._Clear(ply)
end

function MODULE:PW_LoadoutGiven(ply, loadout)
    lib._OnLoadoutGiven(ply, loadout)
end

function MODULE:PW_PlayerKilled(victim, attacker, dmg)
    lib._OnKilled(victim, attacker, dmg)
end

function MODULE:PW_MatchEnd()
    for ply in pairs(store().players) do lib._Clear(ply) end
end

PW.HookFor(MODULE, "PostEntityTakeDamage", function(_, ent, dmg, took)
    if not took or not store().isPlayer(ent) then return end
    lib._OnDamaged(ent, dmg:GetAttacker(), dmg)
end)

PW.HookFor(MODULE, "PostPlayerDeath", function(_, ply)
    lib._OnDeath(ply)
end)

PW.HookFor(MODULE, "PlayerDisconnected", function(_, ply)
    lib._Clear(ply)
end)
