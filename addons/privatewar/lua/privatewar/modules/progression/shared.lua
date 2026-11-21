-- Progression (T-4.9; 06-progression.md d.1, d.2, d.4). Layers of the MVP: player level (XP from score events),
-- weapon level (XP of the weapon of an event) and unlockall. Shared: the settings, the API table, the unlock checks
-- of both realms and the pure rules (sh_curves.lua: curves; sh_unlocks.lua: unlock rules; sh_storage.lua: file,
-- deltas, wire); the server session state is init.lua, storage and transfer sv_storage.lua (T-4.10) and the client
-- file cl_init.lua. The wallet (currency, purchases; sh_wallet.lua, sv_wallet.lua) is T-4.12, the economy module
-- (modules/economy/) sells and rotates.
--
-- Settings (server scope; the coefficients let a host speed progression up without unlockall):
--   unlockall, maxlevel, xpbase, xpexp, maxweaponlevel, weaponxpbase, weaponxpexp, xpscale, autounlock.
-- To the owner (HUD): NW2 Int on the player, "pw_level", "pw_xpin" (XP into the level) and "pw_xpneed" (XP for the
-- next level, 0 at the cap). The storage messages (pw_progression_*) are listed in sv_storage.lua.
--
-- Decisions of the lane agent:
--   1. An entity without Unlock is open from the start; no kind has a hidden default level.
--   2. Weapon XP of an event equals the player XP of that event (after progression.xpscale).
--   3. Bots earn nothing (their sessions would only cost memory).
--   4. The XP keeps counting past the level cap; the bar stays full.

MODULE.Name = "Progression"

MODULE.Settings = {
    unlockall = { scope = "server", type = "bool", default = false, label = "Unlock everything (XP still counts)" },
    maxlevel = { scope = "server", type = "int", default = 55, min = 1, max = 1000, label = "Max player level" },
    xpbase = { scope = "server", type = "float", default = 1000, min = 1, max = 1000000,
        label = "Player XP to next level: base" },
    xpexp = { scope = "server", type = "float", default = 1.2, min = 0, max = 4, label = "Player XP curve exponent" },
    maxweaponlevel = { scope = "server", type = "int", default = 30, min = 1, max = 1000, label = "Max weapon level" },
    weaponxpbase = { scope = "server", type = "float", default = 500, min = 1, max = 1000000,
        label = "Weapon XP to next level: base" },
    weaponxpexp = { scope = "server", type = "float", default = 1.1, min = 0, max = 4,
        label = "Weapon XP curve exponent" },
    xpscale = { scope = "server", type = "float", default = 1, min = 0, max = 100, label = "XP multiplier" },
    -- T-11.7: read by the module autounlock (06 d.2 revision); off = no automatic levels, attachments by count.
    autounlock = { scope = "server", type = "bool", default = true,
        label = "Unlock levels from weapon stats (next map)" }
}

local lib = (rawget(PW, "Progression") or {}) --[[@as PW.ProgressionLib]]
PW.Progression = lib
local unlocks = (rawget(PW, "Unlocks") or {}) --[[@as PW.UnlocksLib]]
PW.Unlocks = unlocks

if SERVER then
    AddCSLuaFile("privatewar/modules/progression/cl_entitlements.lua")
    AddCSLuaFile("privatewar/modules/progression/sh_curves.lua")
    AddCSLuaFile("privatewar/modules/progression/sh_unlock_spec.lua")
    AddCSLuaFile("privatewar/modules/progression/sh_entitlements.lua")
    AddCSLuaFile("privatewar/modules/progression/sh_unlocks.lua")
    AddCSLuaFile("privatewar/modules/progression/sh_wallet.lua")
    AddCSLuaFile("privatewar/modules/progression/sh_storage.lua")
end
include("privatewar/modules/progression/sh_curves.lua")
include("privatewar/modules/progression/sh_wallet.lua")
include("privatewar/modules/progression/sh_unlock_spec.lua")
include("privatewar/modules/progression/sh_unlocks.lua")
include("privatewar/modules/progression/sh_entitlements.lua")
include("privatewar/modules/progression/sh_storage.lua")

---Whether purchases count right now: only while the economy module is active (06 d.6).
---@return boolean
function lib._OwnedActive()
    local economy = rawget(PW, "Economy") --[[@as PW.EconomyLib?]]
    return economy ~= nil and economy._Active()
end

---The unlock view of a player: the server state, or on a client the levels the server sent the local player.
---@param ply Player
---@return PW.ProgressionView
local function viewOf(ply)
    if SERVER then return lib._ViewOf(PW._Progression, ply, lib._RegistryLookup) end
    return lib._LocalView()
end

function unlocks._BindPolicy(view, ply)
    view.override = function(kind, id)
        local answer = PW.Ask("PW_UnlockOverride", ply, kind, id)
        if type(answer) == "boolean" then return answer end
        return nil
    end
    view.hint = function(kind, id) return unlocks._CheckHint(PW.Ask("PW_UnlockHint", kind, id)) end
    return view
end

function unlocks.IsUnlocked(ply, kind, id)
    return unlocks._Decide(viewOf(ply), kind, id)
end

function unlocks.Requirement(ply, kind, id)
    return unlocks._Requirement(viewOf(ply), kind, id)
end

function unlocks.IsEntitled(ply, kind, id)
    if type(kind) ~= "string" or type(id) ~= "string" then return false end
    local key = unlocks._EntitlementKey(unlocks.KeyOf(lib._OwnedKey(kind, id)))
    if key == nil then return false end
    local view = viewOf(ply)
    return (view.granted ~= nil and view.granted(key)) or (view.owned ~= nil and view.owned(key))
end

function unlocks.ListEntitled(ply)
    if SERVER then
        local state = lib._StateOf(PW._Progression, ply)
        return unlocks._ListEntitled(state.owned, state.grants)
    end
    local file = lib.GetLocalFile()
    return unlocks._ListEntitled(file ~= nil and file.owned or nil, unlocks._LocalFile().grants)
end

function unlocks.LockedOptions(ply, weaponId, build)
    return lib._LockedOptions(viewOf(ply), weaponId, build)
end

function unlocks.AttachmentLimit(ply, weaponId)
    local view = viewOf(ply)
    if view.unlockAll then return view.maxAttachments end
    return lib._AttachmentLimit(view.weaponLevel(weaponId), view.maxAttachments)
end

function lib.IsUnlocked(ply, kind, id)
    return ((PW.Unlocks --[[@as PW.UnlocksLib]]).IsUnlocked(ply, kind, id))
end

function lib.LockedOptions(ply, weaponId, build)
    return (PW.Unlocks --[[@as PW.UnlocksLib]]).LockedOptions(ply, weaponId, build)
end

function lib.AttachmentLimit(ply, weaponId)
    return (PW.Unlocks --[[@as PW.UnlocksLib]]).AttachmentLimit(ply, weaponId)
end

function lib._EntitledOptionOf(ply, weaponId, option)
    return lib._EntitledOption(viewOf(ply), weaponId, option)
end

---@param entity PW.Entity
---@param kind string
---@return table<string, any>
local function optionsOf(entity, kind)
    local field = kind == "camos" and "Camos" or "Attachments"
    local entries = (entity --[[@as table<string, any>]])[field]
    return istable(entries) and entries --[[@as table<string, any>]] or {}
end

---@param ids string[]
---@param view PW.ProgressionView
---@param weapon PW.Entity
---@param kind string
local function collectUnlockedOptions(ids, view, weapon, kind)
    for option in pairs(optionsOf(weapon, kind)) do
        if type(option) == "string" then
            local id = weapon.ClassName .. ":" .. option
            if unlocks._Decide(view, kind, id) then ids[#ids + 1] = id end
        end
    end
end

function unlocks.ListUnlocked(ply, kind)
    local view = viewOf(ply)
    ---@type string[]
    local ids = {}
    if kind == "attachments" or kind == "camos" then
        local weapons = PW.Registries.weapons
        for _, weapon in ipairs(weapons ~= nil and weapons.GetEnabledList() or {}) do
            collectUnlockedOptions(ids, view, weapon, kind)
        end
    else
        local registry = PW.Registries[kind]
        for _, definition in ipairs(registry ~= nil and registry.GetEnabledList() or {}) do
            if unlocks._Decide(view, kind, definition.ClassName) then ids[#ids + 1] = definition.ClassName end
        end
    end
    table.sort(ids)
    return ids
end

---@param out table<string, PW.UnlockItem>
---@param weapon PW.Entity
---@param kind string
---@param source string
local function collectOptions(out, weapon, kind, source)
    for id, definition in pairs(optionsOf(weapon, kind)) do
        if istable(definition) and definition.Hidden ~= true and unlocks._Spec(definition.Unlock).reward == source then
            local item = { kind = kind, id = id, weapon = weapon.ClassName }
            local key = unlocks.KeyOf(item)
            if key ~= nil then out[key] = item end
        end
    end
end

---@param out table<string, PW.UnlockItem>
---@param kind string
---@param definition PW.Entity
---@param source string
local function collectReward(out, kind, definition, source)
    if unlocks._Spec(definition.Unlock).reward == source then
        local item = { kind = kind, id = definition.ClassName }
        local key = unlocks._EntitlementKey(unlocks.KeyOf(item))
        if key ~= nil then out[key] = item end
    end
    if kind == "weapons" then
        collectOptions(out, definition, "attachments", source)
        collectOptions(out, definition, "camos", source)
    end
end

function unlocks.ListRewards(source)
    if unlocks._CheckSource(source) == nil then return {} end
    ---@type table<string, PW.UnlockItem>
    local byKey = {}
    for kind, registry in pairs(PW.Registries) do
        for _, definition in ipairs(registry.GetEnabledList()) do
            collectReward(byKey, kind, definition, source)
        end
    end
    local keys = table.GetKeys(byKey) --[[@as string[] ]]
    table.sort(keys)
    ---@type PW.UnlockItem[]
    local items = {}
    for index, key in ipairs(keys) do items[index] = byKey[key] end
    return items
end

function lib.GetWeaponLevel(ply, weaponClass)
    return viewOf(ply).weaponLevel(weaponClass)
end

function lib.MatchSummary(ply)
    if SERVER then return lib._Summary(PW._Progression, ply --[[@as Player]]) end
    return lib._LocalSummary()
end

local keyLevel, keyInto, keyNeed = "pw_level", "pw_xpin", "pw_xpneed"
local defaultNeed = 1000

function lib.GetLevel(ply)
    if SERVER then return PW.Progression._Level(PW._Progression, ply) end
    return ply:GetNW2Int(keyLevel, 1)
end

function lib.GetProgress(ply)
    return ply:GetNW2Int(keyInto, 0), ply:GetNW2Int(keyNeed, defaultNeed)
end

lib._KeyLevel, lib._KeyInto, lib._KeyNeed = keyLevel, keyInto, keyNeed
