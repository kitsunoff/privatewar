-- Frag grenade (T-4.5, T-11.4; 05-loadout.md d.11 and its 2026-11-07 revision). The item gives the grenade SWEP
-- weapon_pw_frag (Weapon; the count is its ammo) and cooks: holding attack runs the fuse in hand (Cook). OnUse is
-- the release: PW.Throw with the fuse less the cooked time; at the end a blast through util.BlastDamage (linear
-- falloff to the radius) with the stock HL2 explosion effect, a scorch decal and a screen shake. The thrower is the
-- attacker and the grenade SWEP the inflictor, so kills and weapon XP count for the grenade; the grenade still goes
-- off when the thrower died meanwhile. Stock HL2 model and effect; nothing vendored.
EQUIPMENT.Name = "Frag"
EQUIPMENT.Category = "lethal"
EQUIPMENT.Count = 1
EQUIPMENT.Weapon = "weapon_pw_frag"
EQUIPMENT.Cook = true
EQUIPMENT.Fuse = 3
EQUIPMENT.Damage = 150
EQUIPMENT.Radius = 350
EQUIPMENT.Model = "models/weapons/w_grenade.mdl"

---@param ent Entity
---@param owner Player
---@param inflictor Entity
---@param damage number
---@param radius number
local function explode(ent, owner, inflictor, damage, radius)
    local pos = ent:GetPos()
    local attacker = IsValid(owner) and owner or ent
    util.BlastDamage(inflictor, attacker, pos, radius, damage)
    local data = EffectData()
    data:SetOrigin(pos)
    util.Effect("Explosion", data, true, true)
    util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 32), ent)
    util.ScreenShake(pos, 5, 40, 0.8, radius * 1.5)
end

---@param owner Player
---@param use PW.EquipmentUse?
---@return boolean
function EQUIPMENT:OnUse(owner, use)
    local throwables = rawget(PW, "Throwables") --[[@as PW.ThrowablesLib?]]
    local equipment = rawget(PW, "Equipment") --[[@as PW.EquipmentLib?]]
    if throwables == nil or throwables.Throw == nil or equipment == nil then return false end
    local damage, radius, class = self.Damage, self.Radius, self.Weapon
    local wep = use ~= nil and use.weapon or nil
    local opts = equipment._ThrowOptions(self.Fuse, self.Cook == true, use)
    opts.model = self.Model
    opts.detonate = function(grenade, by)
        local inflictor = grenade
        if equipment._Inflictor ~= nil then inflictor = equipment._Inflictor(by, wep, class, grenade) end
        explode(grenade, by, inflictor, damage, radius)
    end
    return throwables.Throw(owner, throwables.EntityClass, opts) ~= nil
end
