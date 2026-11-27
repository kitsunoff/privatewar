-- Claim-bound Grant integration over isolated, real progression and unlock stores.

---@class PW.TestClaimBalanceOpts : PW.UnlockGrantOptions
---@field xp? number
---@field currency? number

local claim = "challenge:2026-W47:claim_balance"
local item = "perks:scavenger"

---@return Player
local function actor()
    return { IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return false end } --[[@as Player]]
end

---@param opts? PW.ProgressionStoreOpts
---@return PW.ProgressionLib, PW.UnlocksLib, PW.ProgressionStore, PW.ProgressionDelta[]
local function isolated(opts)
    local p, u = assert(PW.Progression), assert(PW.Unlocks)
    ---@type PW.ProgressionDelta[]
    local batches = {}
    opts = opts or {}
    opts.read = opts.read or function() return nil end
    opts.publish = opts.publish or function() end
    opts.notify = opts.notify or function() end
    opts.ownedActive = opts.ownedActive or function() return true end
    opts.sendDelta = function(_, delta) batches[#batches + 1] = delta end
    local store = p._NewStore(opts)
    PW._Progression = store
    return p, u, store, batches
end

---@param xp? number
---@param currency? number
---@return PW.TestClaimBalanceOpts
local function reward(xp, currency)
    return { source = "challenge", grant = claim, xp = xp, currency = currency }
end

return {
    groupName = "PW unlock claim balances",
    beforeEach = function(state) state.progression = PW._Progression end,
    afterEach = function(state) PW._Progression = state.progression end,
    cases = {
        {
            name = "Claim balance: invalid amounts or a missing claim cannot mutate balances or flush",
            func = function()
                local p, u, store, batches = isolated()
                local ply = actor()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                local invalid = { -1, math.huge, -math.huge, 0 / 0, "4", false }
                for _, amount in ipairs(invalid) do
                    local _, xpReason = u.Grant(ply, {}, reward(amount --[[@as number]], 3))
                    local _, currencyReason = u.Grant(ply, {}, reward(3, amount --[[@as number]]))
                    expect(xpReason ~= nil and currencyReason ~= nil).to.beTrue()
                end
                local missing = reward(4, 3)
                missing.grant = nil
                local _, missingReason = u.Grant(ply, {}, missing)
                expect(missingReason ~= nil).to.beTrue()
                local bad = reward(4, 3)
                bad.grant = "bad claim"
                expect({ u.Grant(ply, {}, bad) }).to.deepEqual({ 0, "badgrant" })
                expect(p.GetState(ply).xp).to.equal(0)
                expect(p.GetCurrency(ply)).to.equal(0)
                expect(store.pending[ply]).to.beNil()
                expect(u.HasClaim(ply, claim)).to.beFalse()
                expect(#batches).to.equal(0)
                expect({ u.Grant(ply, {}, reward(0, 0)) }).to.deepEqual({ 0 })
                expect(u.HasClaim(ply, claim)).to.beTrue()
            end
        },
        {
            name = "Claim balance: notready, unknown, toomany and full leave independent progression flushable",
            func = function()
                local p, u, store, batches = isolated()
                local ply = actor()
                p.AddXP(ply, 3)
                p.AddCurrency(ply, 5)
                local pending = assert(store.pending[ply])
                local opts = reward(40, 7)
                expect({ u.Grant(ply, { item }, opts) }).to.deepEqual({ 0, "notready" })
                ---@type table<string, boolean>
                local uploaded = {}
                for i = 1, u.MaxGrants do uploaded["perks:claim_balance_" .. i] = true end
                expect(u._OnUpload(store, ply, { grants = uploaded, claims = {} })).to.beTrue()
                local snapshot = p.GetState(ply)
                local missing = "perks:pwtest_claim_balance_missing"
                expect({ u.Grant(ply, { missing }, opts) }).to.deepEqual({ 0, "unknown" })
                ---@type string[]
                local tooMany = {}
                for i = 1, u.MaxGrantPerCall + 1 do tooMany[i] = item end
                expect({ u.Grant(ply, tooMany, opts) }).to.deepEqual({ 0, "toomany" })
                expect({ u.Grant(ply, { item }, opts) }).to.deepEqual({ 0, "full" })
                expect(p.GetState(ply)).to.deepEqual(snapshot)
                expect(rawequal(store.pending[ply], pending)).to.beTrue()
                expect(pending.xp).to.equal(3)
                expect(pending.earned).to.equal(5)
                expect(next(assert(pending.claims))).to.beNil()
                expect(#batches).to.equal(0)
                local independent = assert(p._Flush(store, ply))
                expect(independent.xp).to.equal(3)
                expect(independent.earned).to.equal(5)
                expect(next(assert(independent.claims))).to.beNil()
                expect(#batches).to.equal(1)
            end
        },
        {
            name = "Claim balance: a reentrant item check that claims first prevents a stale payout",
            func = function()
                local p, u, store, batches = isolated()
                local ply = actor()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                stub(u, "_Known").with(function()
                    expect({ u.Grant(ply, {}, { source = "challenge", grant = claim }) }).to.deepEqual({ 0 })
                    return true
                end)
                expect({ u.Grant(ply, { item }, reward(40, 7)) }).to.deepEqual({ 0, "claimed" })
                expect(#batches).to.equal(1)
                expect(batches[1].xp).to.equal(0)
                expect(batches[1].earned).to.equal(0)
                expect(u.HasClaim(ply, claim)).to.beTrue()
                expect(next(assert(p.GetState(ply).grants))).to.beNil()
                expect(store.pending[ply]).to.beNil()
            end
        },
        {
            name = "Claim balance: the first XP observer can flush only a complete claim batch",
            func = function()
                local ply = actor()
                local p, u, store, batches
                ---@type string[]
                local notes = {}
                p, u, store, batches = isolated({
                    read = function(key) if key == "progression.xpscale" then return 2 end end,
                    notify = function(name)
                        notes[#notes + 1] = name
                        if name ~= "PW_ProgressionXP" then return end
                        p._Flush(store, ply)
                        expect(u.HasClaim(ply, claim)).to.beTrue()
                        expect(p.GetCurrency(ply)).to.equal(7)
                        expect(p.GetState(ply).xp).to.equal(100000)
                        expect({ u.Grant(ply, {}, reward(50000, 7)) }).to.deepEqual({ 0, "claimed" })
                    end
                })
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                expect({ u.Grant(ply, { item }, reward(50000, 7)) }).to.deepEqual({ 1 })
                expect(notes).to.deepEqual({ "PW_ProgressionXP", "PW_ProgressionLevelUp", "PW_UnlockGranted" })
                expect(#batches).to.equal(1)
                local batch = batches[1]
                expect(batch.xp).to.equal(100000)
                expect(batch.earned).to.equal(7)
                expect(assert(batch.claims)[claim] ~= nil).to.beTrue()
                expect(assert(batch.granted)[item].grant).to.equal(claim)
                expect(store.pending[ply]).to.beNil()
                ---@type PW.ProgressionLocal
                local client = {}
                ---@type string[]
                local writes = {}
                ---@type PW.UnlockClientIO
                local io = {
                    writeUnlocks = function(file)
                        writes[#writes + 1] = "unlocks"
                        expect(u._HasClaim(file.claims, claim)).to.beTrue()
                        expect(client.file).to.beNil()
                    end,
                    writeProgression = function(file)
                        writes[#writes + 1] = "progression"
                        expect(u._HasClaim(assert(client.unlocks).claims, claim)).to.beTrue()
                        expect(file.xp).to.equal(100000)
                        expect(file.currency).to.equal(7)
                    end,
                    notify = function() end
                }
                expect(u._ClientDelta(client, batch, ply, io)).to.beTrue()
                expect(u._ClientDelta(client, batch, ply, io)).to.beFalse()
                expect(writes).to.deepEqual({ "unlocks", "progression" })
            end
        },
        {
            name = "Claim balance: a payout cannot escape bounded claim retention",
            func = function()
                local p, u, store, batches = isolated()
                local ply = actor()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                local at = 1000
                local claims = assert(store.players[ply].claims)
                for i = 1, u.MaxClaims do claims["a:earlier_" .. i] = at end
                stub(os, "time").returns(at)
                local snapshot = p.GetState(ply)
                local _, reason = u.Grant(ply, {}, reward(40, 7))
                expect(reason ~= nil).to.beTrue()
                expect(p.GetState(ply)).to.deepEqual(snapshot)
                expect(u.HasClaim(ply, claim)).to.beFalse()
                expect(store.pending[ply]).to.beNil()
                expect(#batches).to.equal(0)
            end
        },
        {
            name = "Claim balance: scaled XP beyond the delta limit refuses before staging the claim or payout",
            func = function()
                local p, u, store, batches = isolated({
                    read = function(key) if key == "progression.xpscale" then return 2 end end
                })
                local ply = actor()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                local snapshot = p.GetState(ply)
                local rawXP = math.floor(p.MaxDeltaXP / 2) + 1
                expect({ u.Grant(ply, { item }, reward(rawXP, 7)) }).to.deepEqual({ 0, "badreward" })
                expect(p.GetState(ply)).to.deepEqual(snapshot)
                expect(u.HasClaim(ply, claim)).to.beFalse()
                expect(store.pending[ply]).to.beNil()
                expect(store.matches[ply]).to.beNil()
                expect(#batches).to.equal(0)
            end
        },
        {
            name = "Claim balance: the economy gate observes the original state and skips currency only",
            func = function()
                local ply = actor()
                local queried = false
                local p, u, store, batches
                p, u, store, batches = isolated({
                    ownedActive = function()
                        queried = true
                        expect(u.HasClaim(ply, claim)).to.beFalse()
                        expect(p.GetState(ply).xp).to.equal(0)
                        expect(p.GetCurrency(ply)).to.equal(0)
                        expect(store.pending[ply]).to.beNil()
                        return false
                    end
                })
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                expect({ u.Grant(ply, {}, reward(40, 7)) }).to.deepEqual({ 0 })
                expect(queried).to.beTrue()
                expect(#batches).to.equal(1)
                expect(batches[1].xp).to.equal(40)
                expect(batches[1].earned).to.equal(0)
                expect(assert(batches[1].claims)[claim] ~= nil).to.beTrue()
            end
        }
    }
}
