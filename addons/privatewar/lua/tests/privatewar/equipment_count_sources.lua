-- Preserve the legacy first-answer question, then apply owner-local sorted additive contributors once per life.

---@param name string
---@return fun(...: any): any
local function api(name)
    local fn = rawget(assert(PW.Equipment), name)
    assert(isfunction(fn), "equipment count composition API missing: " .. name)
    return fn
end

---@return Player, table<string, integer>
local function owner()
    ---@type table<string, integer>
    local ammo = {}
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        Alive = function() return true end, HasWeapon = function() return true end,
        SetAmmo = function(_, count, kind) ammo[kind] = count end
    } --[[@as Player]], ammo
end

return {
    groupName = "PW deterministic equipment count sources",
    beforeEach = function(state)
        state.equipment = PW._Equipment
    end,
    afterEach = function(state)
        hook.Remove("PW_EquipmentCount", "PW_Test_LegacyCountA")
        hook.Remove("PW_EquipmentCount", "PW_Test_LegacyCountB")
        PW._Equipment = state.equipment
    end,
    cases = {
        {
            name = "Stockpile: legacy first answer is preserved before sorted additive contributors exactly once",
            func = function()
                local compose = api("_ComposeCount")
                ---@type string[]
                local called = {}
                local sources = {
                    z = function() called[#called + 1] = "z" return 2 end,
                    a = function() called[#called + 1] = "a" return 1 end
                }
                expect(compose(1, 5, sources, owner(), "lethal", "frag")).to.equal(8)
                expect(called).to.deepEqual({ "a", "z" })
                expect(compose(1, nil, sources, owner(), "tactical", "flash")).to.equal(4)
                expect(compose(1, -2, sources, owner(), "lethal", "frag")).to.equal(3)
            end
        },
        {
            name = "Stockpile: invalid failing and fractional contributors cannot corrupt the legacy result",
            func = function()
                local sources = {
                    negative = function() return -1 end,
                    nan = function() return 0 / 0 end,
                    infinite = function() return math.huge end,
                    text = function() return "extra" end,
                    failing = function() error("test source") end,
                    valid = function() return 1.9 end
                }
                expect(api("_ComposeCount")(1, 4, sources, owner(), "lethal", "frag")).to.equal(5)
            end
        },
        {
            name = "Stockpile: conflicting legacy answers and new contributors use the actual winning legacy once",
            func = function()
                local ply = owner()
                hook.Add("PW_EquipmentCount", "PW_Test_LegacyCountA", function() return 4 end)
                hook.Add("PW_EquipmentCount", "PW_Test_LegacyCountB", function() return 7 end)
                local legacy = PW.Ask("PW_EquipmentCount", ply, "lethal", "frag", 1)
                expect(legacy == 4 or legacy == 7).to.beTrue()
                expect(api("_ComposeCount")(1, legacy, { stockpile = function() return 1 end,
                    wildcard = function() return 2 end }, ply, "lethal", "frag")).to.equal(legacy + 3)
            end
        },
        {
            name = "Stockpile: both slots cached count and ammo stay authoritative without midlife refill",
            func = function()
                local lib = assert(PW.Equipment)
                local ply, ammo = owner()
                PW._Equipment = lib._NewStore({
                    resolve = function() return { lethal = "frag", tactical = "flash" } end,
                    publish = function(_, slot, _, count) ammo[slot] = count end,
                    alive = function() return true end, phase = function() return "LIVE" end
                })
                api("CountSource")(ply, "stockpile", function(_, slot)
                    return (slot == "lethal" or slot == "tactical") and 1 or 0
                end)
                lib._Equip(ply)
                lib._GiveWeapons(ply)
                expect({ lib.Count(ply, "lethal"), lib.Count(ply, "tactical") }).to.deepEqual({ 2, 2 })
                local entry = assert(PW._Equipment).players[ply].lethal
                entry.count = 0
                lib._GiveWeapons(ply)
                expect(lib.Count(ply, "lethal")).to.equal(0)
                expect(ammo.lethal).to.equal(0)
                expect(ammo.tactical).to.equal(2)
                lib._Clear(ply)
                lib._Equip(ply)
                lib._GiveWeapons(ply)
                expect(lib.Count(ply, "lethal")).to.equal(2)
                api("CountSource")(ply, "stockpile", nil)
                lib._Clear(ply)
            end
        }
    }
}
