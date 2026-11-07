-- Flash grenade (T-4.5, T-11.4; 05-loadout.md d.11 and its 2026-11-07 revision). The item gives the grenade SWEP
-- weapon_pw_flash (Weapon; the count is its ammo) and does not cook: its fuse starts on release. OnUse is the
-- release: PW.Throw with a short fuse; at the end a bang and a flare (stock HL2 sound and effect) and every living
-- player who sees it is blinded by distance and by how directly they look at it (PW.Throwables.FlashAt: a white
-- screen on the client, PW_Blinded for everyone). No damage. The HL2 frag model, tinted pale blue so it reads apart
-- from the frag; nothing vendored.
EQUIPMENT.Name = "Flash"
EQUIPMENT.Category = "tactical"
EQUIPMENT.Count = 1
EQUIPMENT.Weapon = "weapon_pw_flash"
EQUIPMENT.Cook = false
EQUIPMENT.Fuse = 1.5
EQUIPMENT.Model = "models/weapons/w_grenade.mdl"

local tint = Color(170, 210, 255)

---@param ent Entity
local function burst(ent)
    local pos = ent:GetPos() + Vector(0, 0, 4)
    local data = EffectData()
    data:SetOrigin(pos)
    util.Effect("cball_explode", data, true, true)
    ent:EmitSound("weapons/explode4.wav", 95, 140)
    local throwables = rawget(PW, "Throwables") --[[@as PW.ThrowablesLib?]]
    if throwables ~= nil and throwables.FlashAt ~= nil then throwables.FlashAt(pos, ent) end
end

---@param owner Player
---@param use PW.EquipmentUse?
---@return boolean
function EQUIPMENT:OnUse(owner, use)
    local throwables = rawget(PW, "Throwables") --[[@as PW.ThrowablesLib?]]
    local equipment = rawget(PW, "Equipment") --[[@as PW.EquipmentLib?]]
    if throwables == nil or throwables.Throw == nil or equipment == nil then return false end
    local opts = equipment._ThrowOptions(self.Fuse, self.Cook == true, use)
    opts.model, opts.color = self.Model, tint
    opts.detonate = function(grenade) burst(grenade) end
    return throwables.Throw(owner, throwables.EntityClass, opts) ~= nil
end
