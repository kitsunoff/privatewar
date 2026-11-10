-- ARC9 discovery records contain scalar fields only; callers still own independent mutable views.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

return {
    groupName = "PW ARC9 flat discovery copies",
    skip = function() return PW.Arc9 == nil or ARC9 == nil end,
    cases = {
        {
            name = "Flat discovery: warm slot and option views do not invoke recursive table.Copy per record",
            func = function()
                local adapter = must(PW.WeaponAdapters.Get("arc9")) --[[@as PW.Adapter]]
                local entry = must(PW._Arc9BotLoadouts).entries[1]
                local class = entry.loadout.primary --[[@as string]]
                local slots = PW.Adapters.Call(adapter, "GetSlots", class) --[[@as PW.Slot[] ]]
                local chosen = must(slots[1])
                local options = PW.Adapters.Call(adapter, "GetOptions", class, chosen.id) --[[@as PW.Option[] ]]
                local beforeName = chosen.name
                local beforeOption = must(options[1]).name
                local recursive, calls = table.Copy, 0
                stub(table, "Copy").with(function(...)
                    calls = calls + 1
                    return recursive(...)
                end)
                local copiedSlots = PW.Adapters.Call(adapter, "GetSlots", class) --[[@as PW.Slot[] ]]
                local copiedOptions = PW.Adapters.Call(adapter, "GetOptions", class, chosen.id) --[[@as PW.Option[] ]]
                local recursiveCalls = calls
                expect(recursiveCalls).to.equal(0)
                expect(copiedSlots == slots).to.beFalse()
                expect(copiedSlots[1] == slots[1]).to.beFalse()
                expect(copiedOptions[1] == options[1]).to.beFalse()
                copiedSlots[1].name = "caller changed slot"
                copiedOptions[1].name = "caller changed option"
                table.remove(copiedOptions)
                local againSlots = PW.Adapters.Call(adapter, "GetSlots", class) --[[@as PW.Slot[] ]]
                local againOptions = PW.Adapters.Call(adapter, "GetOptions", class, chosen.id) --[[@as PW.Option[] ]]
                expect(againSlots[1].name).to.equal(beforeName)
                expect(againOptions[1].name).to.equal(beforeOption)
                expect(#againOptions).to.equal(#options)
                for _, record in ipairs(copiedSlots) do
                    local fields = record --[[@as table<string, any>]]
                    for _, value in pairs(fields) do expect(istable(value)).to.beFalse() end
                end
                for _, record in ipairs(options) do
                    local fields = record --[[@as table<string, any>]]
                    for _, value in pairs(fields) do expect(istable(value)).to.beFalse() end
                end
            end
        }
    }
}
