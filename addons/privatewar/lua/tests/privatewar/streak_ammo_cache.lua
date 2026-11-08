-- K2: receipt policy; ordinary ammo mutation remains the separately owned ammo-service dependency.

---@return PW.SupportStreaksLib
local function rules()
    return assert(PW.SupportStreaks, "support streak rules are not loaded")
end

---@param owner any
---@param recipient any
---@param teams boolean
---@param allied boolean
---@param alive boolean
---@param allowed boolean
---@param distance number
---@param radius number
---@param visible boolean
---@return boolean
local function eligible(owner, recipient, teams, allied, alive, allowed, distance, radius, visible)
    return rules().SupportEligible({ owner = owner, recipient = recipient, teams = teams, allied = allied,
        alive = alive, allowed = allowed, distance = distance, radius = radius, visible = visible })
end

return {
    groupName = "PW support ammunition cache",
    cases = {
        {
            name = "Cache: only eligible nearby allies receive supply",
            func = function()
                local owner, ally = {}, {}
                expect(eligible(owner, ally, true, true, true, true, 160, 160, true)).to.beTrue()
                expect(eligible(owner, ally, true, true, true, true, 160.01, 160, true)).to.beFalse()
                expect(eligible(owner, ally, true, false, true, true, 10, 160, true)).to.beFalse()
                expect(eligible(owner, ally, true, true, true, true, 10, 160, false)).to.beFalse()
                expect(eligible(owner, ally, true, true, false, true, 10, 160, true)).to.beFalse()
                expect(eligible(owner, ally, true, true, true, false, 10, 160, true)).to.beFalse()
            end
        },
        {
            name = "Cache: free-for-all receipt is owner-only even without a relationship provider",
            func = function()
                local owner = {}
                expect(eligible(owner, owner, false, false, true, true, 0, 160, true)).to.beTrue()
                expect(eligible(owner, {}, false, true, true, true, 0, 160, true)).to.beFalse()
                expect(eligible(owner, owner, false, true, false, true, 0, 160, true)).to.beFalse()
                expect(eligible(owner, owner, false, true, true, false, 0, 160, true)).to.beFalse()
            end
        },
        {
            name = "Cache: recipient cooldown is five seconds including its exact boundary",
            func = function()
                local ready = rules().ReceiptReady
                expect(ready(10, nil, 0)).to.beTrue()
                expect(ready(9, 10, 14.999)).to.beFalse()
                expect(ready(9, 10, 15)).to.beTrue()
                expect(ready(9, 10, 16)).to.beTrue()
                expect(ready(9, 10, 9)).to.beFalse()
            end
        },
        {
            name = "Cache: zero receipts and nonfinite clocks never grant another receipt",
            func = function()
                local ready = rules().ReceiptReady
                expect(ready(0, nil, 15)).to.beFalse()
                expect(ready(-1, nil, 15)).to.beFalse()
                expect(ready(10, nil, math.huge)).to.beFalse()
                expect(ready(10, 0 / 0, 15)).to.beFalse()
            end
        },
        {
            name = "Cache: nonfinite or negative distance never passes receipt eligibility",
            func = function()
                local owner = {}
                for _, distance in ipairs({ -1, math.huge, 0 / 0 }) do
                    expect(eligible(owner, owner, false, true, true, true, distance, 160, true)).to.beFalse()
                end
            end
        },
        {
            name = "Cache: registered content has approved cost initial unlock and absolute lifetime",
            func = function()
                local def = assert(assert(PW.Registries.streaks).Get("ammo_cache"), "ammo_cache is missing")
                expect({ def.Kills, def.Score, def.Unlock, def.Duration }).to.deepEqual({ 4, 400, 1, 45 })
                expect(isfunction(def.Prepare)).to.beTrue()
                expect(isfunction(def.OnUnequip)).to.beTrue()
            end
        }
    }
}
