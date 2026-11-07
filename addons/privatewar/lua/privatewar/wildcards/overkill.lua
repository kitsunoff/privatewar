-- "Overkill" (T-4.3; 05-loadout.md d.5): a second primary weapon instead of a secondary.
WILDCARD.Name = "Overkill"
WILDCARD.Description = "Carry a second primary weapon in the secondary slot."

---@param slots table<string, PW.LoadoutSlot>
function WILDCARD:ModifySlots(slots)
    local secondary, primary = slots.secondary, slots.primary
    if secondary == nil or primary == nil then return end
    -- A slot without a filter accepts any weapon already.
    local own, extra = secondary.filter, primary.filter
    if own == nil or extra == nil then return end
    local filter = table.Copy(own) --[[@as string[] ]]
    for _, entry in ipairs(extra) do
        if not table.HasValue(filter, entry) then filter[#filter + 1] = entry end
    end
    secondary.filter = filter
end
