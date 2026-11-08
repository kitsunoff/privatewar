-- Transactional activation tests use the existing real instance owner and an isolated inventory store.

---@type PW.StreaksStore?
local previous
---@type Player
local owner = { IsValid = function() return true end } --[[@as Player]]
---@type table<string, any>
local state = {}

---@return PW.StreaksLib
local function streaks()
    return assert(PW.Streaks)
end

---@return PW.SupportStreaksLib
local function rules()
    return assert(PW.SupportStreaks, "support streak rules are not loaded")
end

---@return PW.DeploymentFacts
local function floor()
    return {
        origin = Vector(0, 0, 64), aim = Vector(1, 0, -1), position = Vector(64, 0, 0), normal = Vector(0, 0, 1),
        hit = true, world = true, sky = false, water = false, hullClear = true, exitClear = true,
        supported = true, visible = true
    }
end

---@return PW.DeviceLifetimeFacts
local function lifetime()
    return { now = 10, ends = 40, ownerValid = true, team = 1, currentTeam = 1, enabled = true, allowed = true }
end

---@param prepare fun(): table?
---@param equip? fun(self: PW.StreakInstance)
---@return PW.Streak
local function definition(prepare, equip)
    return {
        ClassName = "pwt_support_transaction", Name = "Support transaction", Kills = 1, Duration = 10,
        Prepare = prepare,
        OnEquip = function(self)
            state.equips = state.equips + 1
            state.activation = self.Activation
            if equip ~= nil then equip(self) end
        end,
        OnUnequip = function() state.ends = state.ends + 1 end
    } --[[@as PW.Streak]]
end

---@param def PW.Streak
local function install(def)
    PW._Streaks = assert(streaks()._NewStore)({
        lookup = function(id) if id == def.ClassName then return def end end,
        phase = function() return "LIVE" end,
        alive = function() return true end,
        publish = function() state.published = state.published + 1 end
    })
    assert(streaks().Give)(owner, def.ClassName)
    state.published = 0
end

local cases = {
    {
        name = "Deployment: invalid floor hull or blocked exit spends no inventory",
        func = function()
            for _, key in ipairs({ "hit", "world", "hullClear", "exitClear", "supported", "visible" }) do
                local facts = floor()
                local raw = facts --[[@as table<string, any>]]
                raw[key] = false
                expect(rules().Placement(facts)).to.beFalse()
            end
            for _, key in ipairs({ "sky", "water" }) do
                local facts = floor()
                local raw = facts --[[@as table<string, any>]]
                raw[key] = true
                expect(rules().Placement(facts)).to.beFalse()
            end
            install(definition(function() return nil end))
            expect(assert(streaks().Use)(owner, "pwt_support_transaction")).to.beFalse()
            expect(streaks().Inventory(owner)).to.deepEqual({ "pwt_support_transaction" })
            expect({ state.equips, state.ends, state.published }).to.deepEqual({ 0, 0, 0 })
        end
    },
    {
        name = "Deployment: finite local supported floor accepts at twenty degrees but rejects steeper slopes",
        func = function()
            local facts = floor()
            expect(rules().Placement(facts)).to.beTrue()
            local angle = math.rad(20)
            facts.normal = Vector(math.sin(angle), 0, math.cos(angle))
            expect(rules().Placement(facts)).to.beTrue()
            angle = math.rad(20.01)
            facts.normal = Vector(math.sin(angle), 0, math.cos(angle))
            expect(rules().Placement(facts)).to.beFalse()
            facts.normal = Vector(0, 0, -1)
            expect(rules().Placement(facts)).to.beFalse()
        end
    },
    {
        name = "Deployment: nonfinite aim origin floor or normal and remote placements refuse",
        func = function()
            for _, key in ipairs({ "origin", "aim", "position", "normal" }) do
                local facts = floor()
                local raw = facts --[[@as table<string, any>]]
                raw[key] = Vector(math.huge, 0, 0)
                expect(rules().Placement(facts)).to.beFalse()
                raw[key] = Vector(0 / 0, 0, 0)
                expect(rules().Placement(facts)).to.beFalse()
            end
            local facts = floor()
            facts.position = Vector(5000, 0, 0)
            expect(rules().Placement(facts)).to.beFalse()
            facts = floor()
            facts.aim = Vector()
            expect(rules().Placement(facts)).to.beFalse()
        end
    },
    {
        name = "Deployment: one active per owner per kind and global eight-device cap refuse without replacement",
        func = function()
            local records = { { owner = owner, kind = "ammo_cache" } }
            expect(rules().Capacity(records, owner, "ammo_cache")).to.beFalse()
            expect(rules().Capacity(records, owner, "medical_station")).to.beTrue()
            expect(rules().Capacity(records, {}, "ammo_cache")).to.beTrue()
            for index = 2, 8 do records[index] = { owner = {}, kind = "ground_sensor" } end
            expect(rules().Capacity(records, {}, "medical_station")).to.beFalse()
            expect(#records).to.equal(8)
            expect(records[1].owner).to.equal(owner)
        end
    },
    {
        name = "Device lifetime: exact absolute expiry removes eligibility and late steps cannot extend duration",
        func = function()
            local facts = lifetime()
            expect(rules().EndReason(facts)).to.beNil()
            facts.now = facts.ends
            expect(rules().EndReason(facts)).to.equal("expired")
            facts.now = 1000
            expect(rules().EndReason(facts)).to.equal("expired")
            expect(facts.ends).to.equal(40)
        end
    },
    {
        name = "Device lifetime: disconnect team change content disable and role prohibition invalidate ownership",
        func = function()
            local facts = lifetime()
            facts.ownerValid = false
            expect(rules().EndReason(facts)).to.equal("owner")
            facts = lifetime()
            facts.currentTeam = 2
            expect(rules().EndReason(facts)).to.equal("relationship")
            facts = lifetime()
            facts.enabled = false
            expect(rules().EndReason(facts)).to.equal("disabled")
            facts = lifetime()
            facts.allowed = false
            expect(rules().EndReason(facts)).to.equal("forbidden")
        end
    },
    {
        name = "Device lifetime: unchanged allegiance persists independently of owner death and respawn",
        func = function()
            -- Life/health are deliberately absent from the lifetime contract.
            local facts = lifetime()
            for now = 10, 39 do
                facts.now = now
                expect(rules().EndReason(facts)).to.beNil()
            end
        end
    },
    {
        name = "Device lifetime: invalid clocks end effects rather than creating immortal devices",
        func = function()
            local facts = lifetime()
            facts.ends = math.huge
            expect(rules().EndReason(facts)).to.equal("invalid")
            facts = lifetime()
            facts.now = 0 / 0
            expect(rules().EndReason(facts)).to.equal("invalid")
        end
    },
    {
        name = "Device damage: hostile players and world may destroy but friendly and unknown attackers cannot",
        func = function()
            expect(rules().DamageAllowed(true, false)).to.beTrue()
            expect(rules().DamageAllowed(false, true)).to.beTrue()
            expect(rules().DamageAllowed(false, false)).to.beFalse()
        end
    },
    {
        name = "Deployment: accepted placement spends exactly once and supplies prepared data before OnEquip",
        func = function()
            local plan = { position = Vector(64, 0, 0) }
            install(definition(function() return plan end))
            expect(assert(streaks().Use)(owner, "pwt_support_transaction")).to.beTrue()
            expect(state.activation).to.equal(plan)
            expect(streaks().Inventory(owner)).to.deepEqual({})
            expect(assert(streaks().Use)(owner, "pwt_support_transaction")).to.beFalse()
            expect({ state.equips, state.published }).to.deepEqual({ 1, 1 })
        end
    },
    {
        name = "Deployment: failed entity creation rolls back activation without consuming or publishing inventory",
        func = function()
            install(definition(function() return {} end, function(self) self:Remove() end))
            expect(assert(streaks().Use)(owner, "pwt_support_transaction")).to.beFalse()
            expect(streaks().Inventory(owner)).to.deepEqual({ "pwt_support_transaction" })
            expect({ state.equips, state.ends, state.published }).to.deepEqual({ 1, 1, 0 })
            for inst in pairs(assert(streaks()._Instances)) do
                expect(inst.ClassName == "pwt_support_transaction" and inst:IsValid()).to.beFalse()
            end
        end
    },
    {
        name = "Deployment: recursive activation cannot spend another held copy during preparation",
        func = function()
            install(definition(function()
                state.nested = assert(streaks().Use)(owner, "pwt_support_transaction")
                return {}
            end))
            assert(streaks().Give)(owner, "pwt_support_transaction")
            state.published = 0
            expect(assert(streaks().Use)(owner, "pwt_support_transaction")).to.beTrue()
            expect(state.nested).to.beFalse()
            expect(streaks().Inventory(owner)).to.deepEqual({ "pwt_support_transaction" })
            expect({ state.equips, state.published }).to.deepEqual({ 1, 1 })
        end
    },
    {
        name = "Deployment: active cleanup preserves unused inventory across ordinary rounds and relationships",
        func = function()
            install(definition(function() return {} end))
            assert(streaks().Give)(owner, "pwt_support_transaction")
            assert(streaks().Use)(owner, "pwt_support_transaction")
            local module = assert(PW.Modules.GetStored("streaks"))
            PW.Call(module, "PW_RoundPreparing")
            expect(streaks().Inventory(owner)).to.deepEqual({ "pwt_support_transaction" })
            expect(state.ends).to.equal(1)
            PW.Call(module, "PW_PlayerTeamChanged", owner, 1, 2, "role_change")
            expect(streaks().Inventory(owner)).to.deepEqual({ "pwt_support_transaction" })
        end
    }
}

return {
    groupName = "PW support deployment",
    beforeEach = function()
        previous = PW._Streaks
        state = { equips = 0, ends = 0, published = 0 }
    end,
    afterEach = function()
        for inst in pairs(assert(streaks()._Instances)) do
            if inst.ClassName == "pwt_support_transaction" then
                inst:Remove()
                assert(streaks()._Instances)[inst] = nil
            end
        end
        PW._Streaks = previous
    end,
    cases = cases
}
