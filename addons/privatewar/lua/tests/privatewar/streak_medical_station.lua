-- K3: one recipient-level arbitration, with no engine effects in the pure reducer.

---@return PW.SupportStreaksLib
local function rules()
    return assert(PW.SupportStreaks, "support streak rules are not loaded")
end

---@param distance number
---@param visible boolean
---@param alive? boolean
---@param allowed? boolean
---@return boolean
local function eligible(distance, visible, alive, allowed)
    return rules().SupportEligible({ owner = 1, recipient = 2, teams = true, allied = true,
        alive = alive ~= false, allowed = allowed ~= false, distance = distance, radius = 180, visible = visible })
end

return {
    groupName = "PW support medical station",
    cases = {
        {
            name = "Medical: damage range and LOS interrupt eligibility",
            func = function()
                local lib = rules()
                expect(lib.HealAmount(50, 100, 10, 14.999, 1, { 5 })).to.equal(0)
                expect(lib.HealAmount(50, 100, 10, 15, 1, { 5 })).to.equal(5)
                expect(lib.HealAmount(50, 100, 15, 15, 1, { 5 })).to.equal(0)
                expect(eligible(180, true)).to.beTrue()
                expect(eligible(180.01, true)).to.beFalse()
                expect(eligible(10, false)).to.beFalse()
            end
        },
        {
            name = "Medical: overlapping stations do not multiply approved healing",
            func = function()
                local heal = rules().HealAmount
                expect(heal(50, 100, 0, 10, 1, { 5 })).to.equal(5)
                expect(heal(50, 100, 0, 10, 1, { 5, 5, 5, 5, 5, 5, 5, 5 })).to.equal(5)
                expect(heal(50, 100, 0, 10, 1, { 2, 5, 3 })).to.equal(5)
                expect(heal(50, 100, 0, 10, 0.2, { 5, 5 })).to.equal(1)
                expect(heal(50, 100, 0, 10, 1, {})).to.equal(0)
            end
        },
        {
            name = "Medical: health never exceeds maximum including temporary role health",
            func = function()
                local heal = rules().HealAmount
                expect(heal(98, 100, 0, 10, 1, { 5 })).to.equal(2)
                expect(heal(100, 100, 0, 10, 1, { 5 })).to.equal(0)
                expect(heal(110, 100, 0, 10, 1, { 5 })).to.equal(0)
                expect(heal(198, 200, 0, 10, 1, { 5 })).to.equal(2)
            end
        },
        {
            name = "Medical: dead or role-forbidden recipients never receive a station benefit",
            func = function()
                expect(eligible(10, true, false, true)).to.beFalse()
                expect(eligible(10, true, true, false)).to.beFalse()
                expect(rules().HealAmount(0, 100, 0, 10, 1, { 5 })).to.equal(0)
            end
        },
        {
            name = "Medical: elapsed hitches cannot backfill more than one observed second",
            func = function()
                expect(rules().HealAmount(50, 100, 0, 30, 30, { 5 })).to.equal(5)
                expect(rules().HealAmount(50, 100, 0, 10, -1, { 5 })).to.equal(0)
            end
        },
        {
            name = "Medical: nonfinite values and invalid rates cannot create health",
            func = function()
                local heal = rules().HealAmount
                expect(heal(50, math.huge, 0, 10, 1, { 5 })).to.equal(0)
                expect(heal(50, 100, 0, math.huge, 1, { 5 })).to.equal(0)
                expect(heal(50, 100, 0, 10, 0 / 0, { 5 })).to.equal(0)
                expect(heal(50, 100, 0 / 0, 10, 1, { 5 })).to.equal(0)
                expect(heal(50, 100, 0, 10, 1, { -5, 0 })).to.equal(0)
                expect(heal(50, 100, 0, 10, 1, { math.huge, 0 / 0 })).to.equal(0)
            end
        },
        {
            name = "Medical: registered content has approved cost initial unlock and lifetime",
            func = function()
                local def = assert(assert(PW.Registries.streaks).Get("medical_station"), "medical_station is missing")
                expect({ def.Kills, def.Score, def.Unlock, def.Duration }).to.deepEqual({ 5, 500, 1, 30 })
                expect(isfunction(def.Prepare)).to.beTrue()
                expect(isfunction(def.OnUnequip)).to.beTrue()
            end
        }
    }
}
