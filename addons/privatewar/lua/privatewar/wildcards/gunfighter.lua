-- "Gunfighter" (T-4.3; 05-loadout.md d.5): one more attachment on the primary weapon, and a little less recoil
-- through PW.Stat (the stat reaches the weapon when its adapter supports the key).
WILDCARD.Name = "Gunfighter"
WILDCARD.Description = "One more attachment on the primary weapon."
WILDCARD.Stats = { recoil = 0.95 }

---@param slots table<string, PW.LoadoutSlot>
function WILDCARD:ModifySlots(slots)
    local slot = slots.primary
    if slot == nil then return end
    slot.maxattachments = (slot.maxattachments or 0) + 1
end
