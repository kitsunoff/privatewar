-- "Adrenaline" (T-4.4; 05-loadout.md d.8 sample event perk). Each kill heals the owner over a short time, up to the
-- maximum health. The heal runs on an instance timer, so it stops when the owner dies.
PERK.Name = "Adrenaline"
PERK.Description = "Each kill restores 40 health over 2 seconds."
PERK.Group = 3
PERK.HealPerTick = 5
PERK.TickInterval = 0.25
PERK.Ticks = 8

---@param owner Player
function PERK:OnKill(owner)
    self:Timer(self.TickInterval, self.Ticks, function(perk)
        if not IsValid(owner) or not owner:Alive() then return end
        owner:SetHealth(math.min(owner:GetMaxHealth(), owner:Health() + perk.HealPerTick))
    end)
end
