-- Weapon stat modifiers module (T-3.5; 04-weapons.md d.6; docs/api/adapter.md "Stat modifiers"). Shared. The
-- multipliers live on the player as NW2 floats plus a revision counter written last; adapters read them through
-- PW.GetStatMod. A Think hook (PW.HookFor) compares the owner's revision with what each weapon was refreshed for
-- and calls the adapter's RefreshStatMods once per revision per weapon, on the server for every player and on the
-- client for LocalPlayer() (client-predicted base code needs the client side). Bookkeeping is pure (_Sweep);
-- the engine calls are in the thin glue at the end.
--
-- Decisions of the lane agent:
--   1. Hosted here, not in weapons_core: a separate module owns the NW2 names and the loop. API namespace
--      PW.StatMods (PW.Weapons is the registry); PW.SetStatMods / PW.GetStatMod are the documented aliases.
--   2. Mechanism: a Think hook, not an NW2 proxy. A player whose revision is 0 and who was never swept costs one
--      NW2 read per tick; no table is allocated on the idle path. On the client a swept player costs one
--      GetWeapons per tick, so weapons picked up later (or taken over by another owner) are refreshed too. On the
--      server (every player) the weapons are read only after the revision changed or the engine's WeaponEquip
--      reported a new weapon for that player (T-10.4: GetWeapons for every player every tick was the largest
--      allocation of the server in the load test).
--   3. InstallStatMods runs once per weapon instance, right before its first RefreshStatMods (a weapon of a
--      player with no modifiers is never touched).
--   4. A weapon first seen under revision 0 needs no refresh; one whose owner changed is refreshed again.
--   5. A value that is not a positive finite number is stored as 1.0.

MODULE.Name = "Weapon stat modifiers"

local lib = (rawget(PW, "StatMods") or {}) --[[@as PW.StatModsLib]]
PW.StatMods = lib

lib._Keys = { "reload_time", "draw_time", "ads_time", "sprint_to_fire", "recoil", "spread" }
lib._RevisionKey = "pw_sm_rev"

local maxRevision = 2 ^ 30

---@param stat string
---@return string
function lib._Key(stat)
    return "pw_sm_" .. stat
end

---@param value any
---@return number
local function clean(value)
    if isnumber(value) and value > 0 and value < math.huge then return value --[[@as number]] end
    return 1
end

---@param mods table<string, number>?
---@return table<string, number>
function lib._Normalize(mods)
    local given = mods or {}
    ---@type table<string, number>
    local full = {}
    for _, stat in ipairs(lib._Keys) do
        full[stat] = clean(given[stat])
    end
    return full
end

---@param rev integer
---@return integer
function lib._NextRevision(rev)
    if rev >= maxRevision then return 1 end
    return rev + 1
end

---@param seen table<any, PW.StatModSeen>
---@param owner any
---@param revision integer
---@param weapons any[]
---@return PW.StatModWork[]?
function lib._Sweep(seen, owner, revision, weapons)
    ---@type PW.StatModWork[]?
    local work = nil
    for _, weapon in ipairs(weapons) do
        local entry = seen[weapon]
        if entry == nil and revision == 0 then
            seen[weapon] = { owner = owner, revision = 0 }
        elseif entry == nil or entry.owner ~= owner or entry.revision ~= revision then
            work = work or {}
            work[#work + 1] = { weapon = weapon, install = entry == nil or entry.installed ~= true }
            seen[weapon] = { owner = owner, revision = revision, installed = true }
        end
    end
    return work
end

---@param ply Player?
---@param key string
---@return number
function lib.GetStatMod(ply, key)
    if not IsValid(ply) or not (ply --[[@as Player]]):IsPlayer() then return 1 end
    return (ply --[[@as Player]]):GetNW2Float(lib._Key(key), 1)
end
PW.GetStatMod = lib.GetStatMod

if SERVER then
    ---@param ply Player
    ---@param mods table<string, number>?
    function lib.SetStatMods(ply, mods)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        for stat, value in pairs(lib._Normalize(mods)) do
            ply:SetNW2Float(lib._Key(stat), value)
        end
        -- Written last: a reader that sees the new revision sees every value.
        ply:SetNW2Int(lib._RevisionKey, lib._NextRevision(ply:GetNW2Int(lib._RevisionKey, 0)))
    end
    PW.SetStatMods = lib.SetStatMods
end

-- Thin glue.

---@type table<any, PW.StatModSeen>
local seen = setmetatable({}, { __mode = "k" })
---@type table<any, boolean>
local swept = setmetatable({}, { __mode = "k" })

-- Server: the revision of the last sweep per player, and the players that equipped a weapon since (decision 2).
---@type table<any, integer>
local sweptRevision = setmetatable({}, { __mode = "k" })
---@type table<any, boolean>
local equipped = setmetatable({}, { __mode = "k" })

---@param ply Player
local function tickPlayer(ply)
    local revision = ply:GetNW2Int(lib._RevisionKey, 0)
    if revision == 0 and not swept[ply] then return end
    if SERVER then
        if sweptRevision[ply] == revision and not equipped[ply] then return end
        sweptRevision[ply], equipped[ply] = revision, nil
    end
    swept[ply] = true
    local work = lib._Sweep(seen, ply, revision, ply:GetWeapons())
    if work == nil then return end
    for _, item in ipairs(work) do
        if IsValid(item.weapon) then
            if item.install then PW.Adapters.CallFor(item.weapon, "InstallStatMods", item.weapon) end
            PW.Adapters.CallFor(item.weapon, "RefreshStatMods", item.weapon)
        end
    end
end

---@type fun(): (fun(): integer?, Player?)
local players = player.Iterator

function lib._Tick()
    if SERVER then
        for _, ply in players() do
            tickPlayer(ply --[[@as Player]])
        end
    else
        local ply = LocalPlayer()
        if IsValid(ply) then tickPlayer(ply) end
    end
end

PW.HookFor(MODULE, "Think", lib._Tick)

if SERVER then
    PW.HookFor(MODULE, "WeaponEquip", function(_, _, owner)
        if IsValid(owner) then equipped[owner] = true end
    end)
end
