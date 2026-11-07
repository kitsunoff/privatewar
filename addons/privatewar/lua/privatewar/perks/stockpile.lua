PERK.Name = "Stockpile"
PERK.Group = 1
PERK.Cost = 1
PERK.Unlock = 1
PERK.Description = "Start each life with one extra lethal and tactical use. No midlife refill."

function PERK:OnEquip(owner)
    if PW.Equipment == nil then return end
    PW.Equipment.CountSource(owner, "perk_stockpile", function(_, slot)
        return (slot == "lethal" or slot == "tactical") and 1 or 0
    end)
end

function PERK:OnUnequip(owner)
    if PW.Equipment ~= nil then PW.Equipment.CountSource(owner, "perk_stockpile", nil) end
end
