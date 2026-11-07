-- "Perk 1 Greed" (T-4.3; 05-loadout.md d.5): two perks from group 1.
WILDCARD.Name = "Perk 1 Greed"
WILDCARD.Description = "Take two perks from the first perk group."

---@param slots table<string, PW.LoadoutSlot>
function WILDCARD:ModifySlots(slots)
    local slot = slots.perk1
    if slot == nil then return end
    slot.count = (slot.count or 1) + 1
end
