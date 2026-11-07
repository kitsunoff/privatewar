-- Equipment module, server glue of the grenade SWEPs (T-11.4; 05-loadout.md d.11 revision 2026-11-07). Gives each
-- slot's grenade SWEP with ammo = count, remembers the weapon held before a grenade, returns to it after the last
-- grenade, runs the bot path (select the grenade, throw, switch back) and drops a grenade being cooked when its owner
-- dies (66.3, user decision 2026-11-07). The rules are sh_grenades.lua.

local lib = PW.Equipment --[[@as PW.EquipmentLib]]

---@return PW.EquipmentStore
local function store()
    return PW._Equipment --[[@as PW.EquipmentStore]]
end

---@param wep Entity?
---@return boolean
local function isGrenade(wep)
    return wep ~= nil and IsValid(wep) and (wep --[[@as table]]).PWGrenade == true
end

function lib._Remember(ply, old, new)
    if not isGrenade(new) or isGrenade(old) or old == nil or not IsValid(old) then return end
    store().previous[ply] = old:GetClass()
end

function lib._GiveWeapons(ply)
    if PW.Ask("PW_CanUseLoadoutKind", ply, "equipment") == false then return end
    local s = store()
    local slots = s.players[ply]
    if slots == nil or not IsValid(ply) then return end
    for slot, entry in pairs(slots) do
        local class = entry.weapon
        if class ~= nil then
            if not entry.armed then
                entry.armed = true
                entry.count = lib._CountFor(entry.count, PW.Ask("PW_EquipmentCount", ply, slot, entry.id, entry.count))
            end
            if not ply:HasWeapon(class) then ply:Give(class, true) end
            s.publish(ply, slot, entry.id, entry.count)
        end
    end
end

function lib._ReturnTo(ply)
    if not IsValid(ply) or not ply:Alive() then return nil end
    ---@type string[]
    local owned = {}
    ---@type table<string, boolean>
    local grenades = {}
    for _, wep in ipairs(ply:GetWeapons()) do
        local class = wep:GetClass()
        owned[#owned + 1] = class
        if isGrenade(wep) then grenades[class] = true end
    end
    ---@type string[]
    local candidates = {}
    candidates[#candidates + 1] = store().previous[ply]
    local before = ply:GetPreviousWeapon()
    if IsValid(before) and (before --[[@as Entity]]):IsWeapon() then
        candidates[#candidates + 1] = (before --[[@as Weapon]]):GetClass()
    end
    local class = lib._ReturnWeapon(candidates, owned, grenades)
    if class ~= nil then ply:SelectWeapon(class) end
    return class
end

---Switches back when the player still holds an empty grenade of the slot (and is alive).
---@param ply Player
---@param slot string
local function returnIfEmpty(ply, slot)
    if not IsValid(ply) or not ply:Alive() then return end
    local active = ply:GetActiveWeapon()
    if not isGrenade(active) or (active --[[@as table]]).PWSlot ~= slot then return end
    if lib._ShouldSwitchBack(lib.Count(ply, slot)) then lib._ReturnTo(ply) end
end

function lib._AfterThrow(ply, slot, count)
    if not lib._ShouldSwitchBack(count) then return end
    local s, generation = store(), store().players[ply]
    timer.Simple(lib.SwitchDelay, function()
        if store() == s and generation ~= nil and s.players[ply] == generation then returnIfEmpty(ply, slot) end
    end)
end

function lib._BotThrow(ply, slot, entry, opts)
    local class = entry.weapon --[[@as string]]
    if not ply:HasWeapon(class) then lib._GiveWeapons(ply) end
    local wep = ply:GetWeapon(class)
    if not IsValid(wep) then return false end
    local active = ply:GetActiveWeapon()
    if IsValid(active) and not isGrenade(active) then store().previous[ply] = active:GetClass() end
    ply:SelectWeapon(class)
    local use = opts or {}
    use.weapon = wep
    local thrown = lib._Spend(ply, slot, entry, use)
    local s, generation = store(), store().players[ply]
    timer.Simple(thrown and lib.BotHold or 0, function()
        if store() == s and generation ~= nil and s.players[ply] == generation
            and IsValid(ply) and isGrenade(ply:GetActiveWeapon()) then lib._ReturnTo(ply) end
    end)
    return thrown
end

function lib._Inflictor(owner, wep, class, fallback)
    if wep ~= nil and IsValid(wep) and wep:GetOwner() == owner then return wep end
    if class ~= nil and IsValid(owner) and owner:IsPlayer() then
        local held = (owner --[[@as Player]]):GetWeapon(class)
        if IsValid(held) then return held end
    end
    return fallback
end

function lib._DropOnDeath(ply)
    local wep = IsValid(ply) and ply:GetActiveWeapon() or nil
    if not isGrenade(wep) then return false end
    local grenade = wep --[[@as Weapon]]
    local s = store()
    local slots = s.players[ply]
    local entry = slots ~= nil and slots[(grenade --[[@as table]]).PWSlot] or nil
    if entry == nil or entry.weapon ~= grenade:GetClass() then return false end
    local def = s.lookup(entry.id)
    local start = (grenade --[[@as table]]):PWCookStart() --[[@as number]]
    local cooked = lib._DeathDrop(start, s.clock(), def ~= nil and def.Cook == true, lib.CookCap)
    if cooked == nil then return false end
    grenade:SetDTFloat(0, 0)
    return PW.Call(entry.instance, "OnUse", ply, { cooked = cooked, death = true, weapon = grenade }) ~= false
end
