PERK.Name = "Ghost"
PERK.Group = 3
PERK.Cost = 1
PERK.Unlock = 1
PERK.Description = "Hide from deliberate radar reveals, not sight, sound, damage awareness or existing contacts."

function PERK:OnEquip(owner)
    self:Hook("PW_CanReveal", function(_, _, target)
        if target == owner then return false end
    end)
end
