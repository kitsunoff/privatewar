-- Existing weapons and ordinary primary reserve only; never the spawn Give path.
local lib = PW.WeaponAmmo --[[@as PW.WeaponAmmoLib]]

---@param wep Weapon
---@param owner Player
---@return boolean
local function owned(wep, owner)
    return IsValid(wep) and wep:IsWeapon() and wep:GetOwner() == owner
end

---@param ammo integer
---@return boolean
local function ordinary(ammo)
    if ammo < 0 then return false end
    local name = game.GetAmmoName(ammo)
    if name == nil then return false end
    local equipment = rawget(PW, "Equipment") --[[@as PW.EquipmentLib?]]
    for _, excluded in ipairs(equipment ~= nil and equipment.AmmoTypes or { "pw_frag", "pw_flash" }) do
        if string.lower(name) == string.lower(excluded) then return false end
    end
    return true
end

function lib.Resupply(ply, weapons, opts)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return {} end
    local options = opts or {}
    ---@type PW.ResupplyEntry[]
    local entries = {}
    for i, wep in ipairs(weapons) do
        if i > 64 then break end
        if owned(wep, ply) and (wep --[[@as table]]).PWGrenade ~= true then
            local ammo = PW.Adapters.CallFor(wep, "GetAmmoType", wep)
            local capacity = select(2, PW.Adapters.CallFor(wep, "GetClip", wep))
            if isnumber(ammo) and ordinary(ammo) and isnumber(capacity) then
                entries[#entries + 1] = { ammo = ammo, capacity = capacity, reserve = ply:GetAmmoCount(ammo) }
            end
        end
    end
    local plan = lib._ResupplyPlan(entries, options.fraction or 1, options.maxMagazines or 3)
    for ammo, amount in pairs(plan) do ply:SetAmmo(ply:GetAmmoCount(ammo) + amount, ammo) end
    return plan
end

function lib.DamageWeapon(owner, dmg)
    if not IsValid(owner) or not owner:IsPlayer() or dmg == nil then return nil, false end
    local inflictor = dmg:GetInflictor()
    local weapon = inflictor ~= owner and IsValid(inflictor) and inflictor:IsWeapon()
    local direct = isfunction(dmg.IsDamageType)
        and dmg:IsDamageType(bit.bor(DMG_BULLET, DMG_BUCKSHOT, DMG_CLUB, DMG_SLASH))
        and not dmg:IsDamageType(bit.bor(DMG_BLAST, DMG_BURN, DMG_FALL))
    local active = direct and inflictor == owner and owner:GetActiveWeapon() or nil
    local kind, eligible = lib._DamageSource({
        weapon = weapon, owned = weapon and owned(inflictor --[[@as Weapon]], owner),
        grenade = weapon and (inflictor --[[@as table]]).PWGrenade == true,
        playerInflictor = inflictor == owner, active = active ~= nil and owned(active, owner), direct = direct
    })
    if kind == "weapon" then return inflictor --[[@as Weapon]], eligible end
    if kind == "active" then return active, eligible end
    return nil, false
end
