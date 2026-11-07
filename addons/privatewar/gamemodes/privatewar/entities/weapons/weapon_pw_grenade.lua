-- Base of the grenade SWEPs (T-11.4; 05-loadout.md d.11 revision 2026-11-07: grenades are inventory items). Not
-- spawnable and never given itself: weapon_pw_frag and weapon_pw_flash derive from it. The count of the equipment
-- slot is this SWEP's ammo (one ammo type per grenade, added by the equipment module).
--
-- Holding attack pulls the pin and, for an item that cooks (EQUIPMENT.Cook), runs the fuse in hand up to
-- PW.Equipment.CookCap; reaching the cap sets the grenade off in hand. Releasing attack throws: on the server the
-- equipment module's _Release calls the item's OnUse (PW.Throw and the item's detonation), takes one ammo and,
-- after the last grenade, returns to the previous weapon. The rules are pure (modules/equipment/sh_grenades.lua);
-- this file only reads input and plays animations. Bots never cook: they throw through PW.Equipment.Use.
-- Dying while cooking drops the live grenade at the body (the equipment module's death hook reads PWCookStart).
-- Stock HL2 models and animations only.

SWEP.PrintName = "Grenade"
SWEP.Author = "Private War"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.PWGrenade = true
SWEP.PWSlot = "lethal"
SWEP.Slot = 4
SWEP.SlotPos = 0
SWEP.Weight = 1
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = true
SWEP.HoldType = "grenade"
SWEP.ViewModel = "models/weapons/c_grenade.mdl"
SWEP.WorldModel = "models/weapons/w_grenade.mdl"
SWEP.UseHands = true
SWEP.ViewModelFOV = 54
SWEP.DrawAmmo = true
SWEP.DrawCrosshair = true
SWEP.Primary = { ClipSize = -1, DefaultClip = 0, Automatic = true, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

-- Data table float 0: CurTime when the pin was pulled, 0 when idle (predicted on the owner's client).
local cookIndex = 0
-- Seconds from the throw animation to the next grenade in hand.
local redrawDelay = 0.5

---@return PW.EquipmentLib?
local function equipment()
    return rawget(PW, "Equipment")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

---The owner when it is a player, else nil.
---@return Player?
function SWEP:PWOwner()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return nil end
    return owner --[[@as Player]]
end

---Grenades left (the owner's ammo of this SWEP's type).
---@return integer
function SWEP:PWAmmo()
    local owner = self:PWOwner()
    if owner == nil then return 0 end
    return owner:GetAmmoCount(self.Primary.Ammo)
end

---Whether the item in this SWEP's slot cooks.
---@return boolean
function SWEP:PWCooks()
    local lib, owner = equipment(), self:PWOwner()
    if lib == nil or owner == nil then return false end
    local id = lib.Item(owner, self.PWSlot)
    local def = id ~= nil and lib._Lookup(id) or nil
    return def ~= nil and def.Cook == true
end

---CurTime when the pin was pulled, 0 when idle.
---@return number
function SWEP:PWCookStart()
    return self:GetDTFloat(cookIndex)
end

function SWEP:Deploy()
    self:SetDTFloat(cookIndex, 0)
    self.PWRedrawAt = nil
    self:SendWeaponAnim(ACT_VM_DRAW)
    return true
end

function SWEP:Holster()
    self:SetDTFloat(cookIndex, 0)
    self.PWRedrawAt = nil
    return true
end

function SWEP:PrimaryAttack()
    local owner = self:PWOwner()
    if owner == nil or owner:IsBot() or self:GetDTFloat(cookIndex) > 0 or self:PWAmmo() < 1 then return end
    self:SetDTFloat(cookIndex, CurTime())
    self:SendWeaponAnim(ACT_VM_PULLBACK_HIGH)
end

function SWEP:SecondaryAttack() end

function SWEP:Reload() end

---Throws (released or overcooked): the animation here, the projectile and the ammo on the server.
---@param owner Player
---@param lib PW.EquipmentLib
---@param cooked number
---@param drop boolean
function SWEP:PWThrow(owner, lib, cooked, drop)
    self:SetDTFloat(cookIndex, 0)
    self:SendWeaponAnim(ACT_VM_THROW)
    owner:DoAttackEvent()
    self:SetNextPrimaryFire(CurTime() + lib.Cooldown)
    self.PWRedrawAt = CurTime() + redrawDelay
    if SERVER and lib._Release ~= nil then lib._Release(owner, self, { cooked = cooked, drop = drop }) end
end

function SWEP:Think()
    local redraw = self.PWRedrawAt
    if redraw ~= nil and CurTime() >= redraw then
        self.PWRedrawAt = nil
        if self:PWAmmo() > 0 then self:SendWeaponAnim(ACT_VM_DRAW) end
    end
    local start = self:GetDTFloat(cookIndex)
    local owner, lib = self:PWOwner(), equipment()
    if start <= 0 or owner == nil or lib == nil then return end
    local state, cooked = lib._CookState(start, CurTime(), owner:KeyDown(IN_ATTACK), self:PWCooks(), lib.CookCap)
    if state == "throw" or state == "overcook" then self:PWThrow(owner, lib, cooked, state == "overcook") end
end
