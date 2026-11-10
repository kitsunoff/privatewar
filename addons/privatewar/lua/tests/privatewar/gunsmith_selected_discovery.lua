-- A saved build only needs offered-option sets for the addresses it actually contains. The legacy empty
-- discovery request still enumerates every slot; no actor permission or validation result is reused.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@return PW.Adapter
local function fixtureAdapter()
    return { ClassName = "selected_fixture", IsAvailable = function() return true end,
        Claims = function() return true end, ListWeapons = function() return {} end }
end

return {
    groupName = "PW selected-build option discovery",
    cases = {
        {
            name = "Selected build: scan only requested slots; fresh builds and adapter removal are re-evaluated",
            func = function()
                local loadout = must(PW.Loadout)
                local available = true
                local adapter = fixtureAdapter()
                ---@type string[]
                local queries = {}
                stub(PW.Adapters, "For").with(function() return available and adapter or nil end)
                stub(PW.Adapters, "Call").with(function(_, method, _, slot)
                    if method == "GetSlots" then
                        return { { id = "optic", cosmetic = false }, { id = "muzzle", cosmetic = false },
                            { id = "camo", cosmetic = true } }
                    end
                    if method == "GetOptions" then
                        local id = slot --[[@as string]]
                        queries[#queries + 1] = id
                        return { { id = id .. "_option", cosmetic = id == "camo" } }
                    end
                end)
                local offered = loadout._AdapterOptions("fixture", { optic = "optic_option", camo = "camo_option" })
                expect(queries).to.deepEqual({ "optic", "camo" })
                expect(offered.optic.optic_option).to.beTrue()
                expect(offered.camo.camo_option).to.beTrue()
                expect(offered.muzzle).to.beNil()
                queries = {}
                local changed = loadout._AdapterOptions("fixture", { muzzle = "muzzle_option" })
                expect(changed.muzzle.muzzle_option).to.beTrue()
                expect(queries).to.deepEqual({ "muzzle" })
                available = false
                expect(next(loadout._AdapterOptions("fixture", { optic = "optic_option" }))).to.beNil()
            end
        },
        {
            name = "Save legality: unsupported addresses/options rejected and adapter static validation still runs",
            func = function()
                local loadout = must(PW.Loadout)
                local adapter = fixtureAdapter()
                local static = 0
                stub(PW.Adapters, "For").with(function() return adapter end)
                stub(PW.Adapters, "Call").with(function(_, method, _, value)
                    if method == "GetSlots" then return { { id = "optic", cosmetic = false } } end
                    if method == "GetOptions" then return { { id = "allowed", cosmetic = false } } end
                    if method == "Validate" then
                        static = static + 1
                        return value, {}
                    end
                end)
                local ctx = loadout._GunsmithContext({ lookup = function() return {} end,
                    budget = 10, maxattachments = 5 })
                local clean, rejected = loadout._ValidateBuild("fixture", {},
                    { optic = "allowed", unknown = "allowed" }, ctx)
                expect(clean).to.deepEqual({ optic = "allowed" })
                expect(#rejected).to.equal(1)
                expect(rejected[1].slot).to.equal("unknown")
                expect(static).to.equal(1)
                clean, rejected = loadout._ValidateBuild("fixture", {}, { optic = "unavailable" }, ctx)
                expect(next(clean)).to.beNil()
                expect(#rejected).to.equal(1)
            end
        },
        {
            name = "Compatibility: empty discovery requests retain all offered slots and their independent sets",
            func = function()
                local adapter = fixtureAdapter()
                local queries = 0
                stub(PW.Adapters, "For").with(function() return adapter end)
                stub(PW.Adapters, "Call").with(function(_, method, _, slot)
                    if method == "GetSlots" then return { { id = "optic" }, { id = "muzzle" } } end
                    if method == "GetOptions" then
                        queries = queries + 1
                        return slot == "optic" and { { id = "reddot" } } or {}
                    end
                end)
                local offered = must(PW.Loadout)._AdapterOptions("fixture", {})
                expect(offered).to.deepEqual({ optic = { reddot = true }, muzzle = {} })
                expect(queries).to.equal(2)
            end
        }
    }
}
