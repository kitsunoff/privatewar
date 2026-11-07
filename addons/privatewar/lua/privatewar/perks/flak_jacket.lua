-- "Flak Jacket" (T-4.4; 05-loadout.md d.8 sample custom-hook perk). The instance hooks EntityTakeDamage through
-- self:Hook and halves explosive damage to its owner (frags, the SMG grenade, RPG rockets, barrels). The hook ends
-- with the instance (death, loadout change, match end).
PERK.Name = "Flak Jacket"
PERK.Description = "Take half damage from explosions."
PERK.Group = 1
PERK.ExplosiveScale = 0.5

---@param owner Player
function PERK:OnEquip(owner)
    self:Hook("EntityTakeDamage", function(perk, target, dmg)
        if target == owner and dmg:IsExplosionDamage() then dmg:ScaleDamage(perk.ExplosiveScale) end
    end)
end
