PERK.Name = "Continuity"
PERK.Group = 3
PERK.Cost = 1
PERK.Unlock = 1
PERK.Description = "Keep earned streak progress through death. No discounts, repeated thresholds or extra chaining."

function PERK:OnEquip(owner)
    self:Hook("PW_StreaksPersist", function(_, ply)
        if ply == owner then return true end
    end)
end
