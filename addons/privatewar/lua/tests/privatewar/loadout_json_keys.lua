-- classes.json read back by util.JSONToTable: digit-only object keys (the ARC9 and MW Base attachment slot names "2",
-- "3") come back as numbers and must still survive the reader (05-loadout.md d.12).

---@return PW.LoadoutLib
local function loadout()
    local lib = PW.Loadout
    assert(lib ~= nil, "PW.Loadout is not loaded")
    return lib
end

return {
    groupName = "PW loadout classes.json numeric keys",
    cases = {
        {
            name = "A build keyed by digit-only slot names survives the real JSON read",
            func = function()
                local text = [[{"version":1,"classes":[{"name":"Digits","loadout":{"primary":"mw_gun",
                    "builds":{"primary":{"2":"mw_optic","3":false}}}}]}]]
                local decoded = util.JSONToTable(text)
                expect(decoded).to.exist()
                local parsed = loadout()._ClassesFromJson(decoded, 5)
                expect(parsed).to.deepEqual({
                    {
                        name = "Digits",
                        loadout = { primary = "mw_gun", builds = { primary = { ["2"] = "mw_optic", ["3"] = false } } }
                    }
                })
            end
        }
    }
}
