-- Step 11 draft: real weekly completion and phase edges, with real progression
-- and unlock APIs over disposable stores. Capacity and post-check refusal are
-- injected only where the public Grant contract crosses into entitlement code.

---@class PW.TestWeeklyRewardGrant
---@field count integer
---@field source string
---@field claim string?
---@field reason string?
---@field xp? number
---@field currency? number

---@class PW.TestWeeklyGrantOptions : PW.UnlockGrantOptions
---@field xp? number
---@field currency? number

---@class PW.TestWeeklyRewardFixture
---@field ply Player
---@field lib PW.ChallengesLib
---@field progression PW.ProgressionLib
---@field unlocks PW.UnlocksLib
---@field module PW.Module
---@field store PW.ProgressionStore
---@field reward PW.ChallengeReward
---@field bonus integer
---@field phase PW.PhaseName
---@field trace string[]
---@field deltas PW.ProgressionDelta[]
---@field grants PW.TestWeeklyRewardGrant[]
---@field logs string[]
---@field refusal string?
---@field granting? boolean

local index, id = 2967, "reward_fixture"
local locked = { kind = "perks", id = "pwtest_weekly_locked" }
local owned = { kind = "perks", id = "pwtest_weekly_owned" }
local missing = { kind = "perks", id = "pwtest_weekly_missing" }
local lockedKey, ownedKey = "perks:" .. locked.id, "perks:" .. owned.id

---@param userId integer
---@return Player
local function playerStub(userId)
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return false end, UserID = function() return userId end,
        SteamID64 = function() return "76561198000000000" end, Team = function() return 1 end,
        GetObserverMode = function() return OBS_MODE_NONE end, Alive = function() return true end
    } --[[@as Player]]
end

---@param f PW.TestWeeklyRewardFixture
local function boot(f)
    local template = assert(f.lib._Compile(id, {
        Name = "Reward fixture", Description = "Complete one kill", Event = "kill", Target = 1, Rewards = f.reward
    }))
    local monday = f.lib.WeekBounds(index)
    local server = f.lib._NewServer({
        utc = function() return monday end, clock = function() return 0 end,
        phase = function() return f.phase end, players = function() return { f.ply } end,
        isPlayer = function(ply) return IsValid(ply) and ply:IsPlayer() end,
        catalogue = function() return { { template = template } } end,
        options = function() return { count = 1, bonusNeeded = f.bonus, bonusPool = {} } end,
        matchContext = function() return { mode = "ffa", modeBase = {}, playlist = "" } end,
        schedule = function() end, log = function(message) f.logs[#f.logs + 1] = message end,
        sendState = function() end, sendProgress = function() end, sendDelta = function() end
    })
    PW._ChallengeServer = server
    assert(#server.week.items == 1 and server.week.items[1].id == id, "reward fixture did not select its template")
end

---@param f PW.TestWeeklyRewardFixture
---@param stub fun(tbl: table, key: string): GLuaTest_Stub
local function observe(f, stub)
    local p, u = f.progression, f.unlocks
    local ready, has, describe, unlocked, grant = u.IsReady, u.HasClaim, u.Describe, u.IsUnlocked, u.Grant
    local xp, currency, balance = p.AddXP, p.AddCurrency, p.GetCurrency
    stub(u, "IsReady").with(function(ply)
        f.trace[#f.trace + 1] = "ready"
        return ready(ply)
    end)
    stub(u, "HasClaim").with(function(ply, key)
        f.trace[#f.trace + 1] = "claim"
        return has(ply, key)
    end)
    stub(u, "Describe").with(function(item)
        f.trace[#f.trace + 1] = "describe"
        return describe(item)
    end)
    stub(u, "IsUnlocked").with(function(ply, kind, itemId)
        f.trace[#f.trace + 1] = "unlocked"
        return unlocked(ply, kind, itemId)
    end)
    stub(p, "GetCurrency").with(function(ply)
        f.trace[#f.trace + 1] = "balance"
        return balance(ply)
    end)
    stub(p, "AddXP").with(function(ply, amount, weapon)
        f.trace[#f.trace + 1] = "xp"
        xp(ply, amount, weapon)
    end)
    stub(p, "AddCurrency").with(function(ply, amount)
        f.trace[#f.trace + 1] = "currency"
        currency(ply, amount)
    end)
    stub(u, "Grant").with(function(ply, items, opts)
        ---@cast opts PW.TestWeeklyGrantOptions
        f.trace[#f.trace + 1] = "grant"
        ---@type integer, string?
        local added, reason = 0, "toomany"
        if f.refusal ~= "toomany" or #items == 0 then
            f.granting = true
            added, reason = grant(ply, items, opts)
            f.granting = false
        end
        f.grants[#f.grants + 1] = { count = #items, source = opts.source, claim = opts.grant, reason = reason,
            xp = opts.xp, currency = opts.currency }
        return added, reason
    end)
end

---@param stub fun(tbl: table, key: string): GLuaTest_Stub
---@param reward? PW.ChallengeReward
---@param bonus? integer
---@param economy? boolean
---@return PW.TestWeeklyRewardFixture
local function fixture(stub, reward, bonus, economy)
    local lib, p, u = assert(PW.Challenges), assert(PW.Progression), assert(PW.Unlocks)
    ---@type PW.TestWeeklyRewardFixture
    local f
    local store = p._NewStore({
        read = function() return nil end, publish = function() end, notify = function() end,
        ownedActive = function() return economy ~= false end,
        sendDelta = function(owner, delta)
            assert(rawequal(owner, f.ply), "reward delta was sent to another player")
            f.trace[#f.trace + 1] = "flush"
            f.deltas[#f.deltas + 1] = delta
        end
    })
    f = { ply = playerStub(11), lib = lib, progression = p, unlocks = u, store = store,
        module = assert(PW.Modules.Get("challenges")), reward = reward or { xp = 40, currency = 7, items = { locked } },
        bonus = bonus or 0, phase = "LOBBY", trace = {}, deltas = {}, grants = {}, logs = {} }
    PW._Progression = store
    local economyLib = assert(PW.Economy)
    stub(economyLib, "_Active").with(function() return economy ~= false end)
    stub(p, "_RegistryLookup").with(function(kind, itemId)
        if f.granting and f.refusal == "unknown" then return nil end
        if kind == "perks" and (itemId == locked.id or itemId == owned.id) then
            return { ClassName = itemId, Name = itemId, Unlock = 99 } --[[@as PW.Entity]]
        end
        return nil
    end)
    boot(f)
    observe(f, stub)
    return f
end

---@param f PW.TestWeeklyRewardFixture
---@param claims? table<string, boolean>
---@param grants? table<string, boolean>
local function upload(f, claims, grants)
    assert(f.unlocks._OnUpload(f.store, f.ply, { grants = grants or {}, claims = claims or {} }))
end

---@param f PW.TestWeeklyRewardFixture
---@param suffix? string
---@return string
local function claimId(f, suffix)
    return "challenge:" .. f.lib.WeekLabel(index) .. ":" .. (suffix or id)
end

---@param f PW.TestWeeklyRewardFixture
local function complete(f)
    f.phase = "LIVE"
    PW.Call(f.module, "PW_MatchStart")
    PW.Call(f.module, "PW_ScoreEvent", f.ply, "kill", 100, 100)
end

---@param f PW.TestWeeklyRewardFixture
local function nextPhase(f)
    PW.Call(f.module, "PW_MatchEnd")
    f.phase = "POSTMATCH"
    PW.Call(f.module, "PW_PhaseChange", "POSTMATCH", "LIVE", 0)
end

---@param f PW.TestWeeklyRewardFixture
---@param reason "full"|"toomany"
---@param expect fun(subject: any): GLuaTest_Expect
local function claimOnlyRetry(f, reason, expect)
    if reason == "toomany" then
        -- The weekly compiler/wire bounds item lists below MaxGrantPerCall.
        -- Exercise defensive recovery by injecting this documented refusal.
        upload(f)
        f.refusal = reason
    else
        ---@type table<string, boolean>
        local grants = {}
        for i = 1, f.unlocks.MaxGrants do grants["perks:pwtest_weekly_full_" .. i] = true end
        upload(f, nil, grants)
    end
    complete(f)
    expect(#f.grants).to.equal(2)
    expect(f.grants[1]).to.deepEqual({
        count = 1, reason = reason, source = "challenge", claim = claimId(f), xp = 40, currency = 7
    })
    expect(f.grants[2]).to.deepEqual({ count = 0, source = "challenge", claim = claimId(f), xp = 40, currency = 18 })
    expect(#f.deltas).to.equal(1)
    local delta = assert(f.deltas[1])
    expect(delta.xp).to.equal(40)
    expect(delta.earned).to.equal(18)
    expect(next(assert(delta.granted))).to.beNil()
    expect(assert(delta.claims)[claimId(f)] ~= nil).to.beTrue()
    nextPhase(f)
    expect(#f.grants).to.equal(2)
    expect(#f.deltas).to.equal(1)
end

return {
    groupName = "PW challenges rewards",
    beforeEach = function(state)
        state.server, state.progression = PW._ChallengeServer, PW._Progression
        stub(PW, "Notify").with(function() end)
        stub(PW, "Ask").with(function() return nil end)
    end,
    afterEach = function(state)
        PW._ChallengeServer, PW._Progression = state.server, state.progression
    end,
    cases = {
        {
            name = "Rewards: completion queues XP, currency and items once with the claim id",
            func = function()
                local f = fixture(stub)
                upload(f)
                complete(f)
                expect(f.trace).to.deepEqual({
                    "ready", "claim", "describe", "unlocked", "grant", "flush"
                })
                expect(f.grants[1]).to.deepEqual({
                    count = 1, source = "challenge", claim = claimId(f), xp = 40, currency = 7
                })
                expect(assert(f.deltas[1].granted)[lockedKey].grant).to.equal(claimId(f))
                PW.Call(f.module, "PW_ScoreEvent", f.ply, "kill", 100, 100)
                nextPhase(f)
                expect(#f.grants).to.equal(1)
                expect(#f.deltas).to.equal(1)
            end
        },
        {
            name = "Rewards: readiness precedes claims, balance reads and all reward side effects",
            func = function()
                local f = fixture(stub)
                complete(f)
                expect(f.trace).to.deepEqual({ "ready" })
                expect(f.store.pending[f.ply]).to.beNil()
                expect(#f.deltas).to.equal(0)
                upload(f)
                nextPhase(f)
                expect(#f.deltas).to.equal(1)
                expect(assert(f.deltas[1].claims)[claimId(f)] ~= nil).to.beTrue()
            end
        },
        {
            name = "Rewards: an existing claim grants nothing across reconnect and module reload",
            func = function()
                local f = fixture(stub)
                upload(f)
                complete(f)
                local persisted = assert(f.deltas[1].claims)
                local key = claimId(f)
                expect(persisted[key] ~= nil).to.beTrue()
                -- Recreate weekly module state, keeping the entitlement ledger.
                boot(f)
                complete(f)
                expect(f.unlocks.HasClaim(f.ply, key)).to.beTrue()
                expect(#f.deltas).to.equal(1)
                expect(#f.grants).to.equal(1)
                -- A new player entity for the same SteamID, with only its uploaded claim.
                f.ply, f.trace = playerStub(12), {}
                upload(f, { [key] = true })
                complete(f)
                expect(f.trace).to.deepEqual({ "ready", "claim" })
                expect(#f.deltas).to.equal(1)
                expect(#f.grants).to.equal(1)
                expect(assert(assert(f.lib.GetProgress)(f.ply, id)).done).to.beTrue()
            end
        },
        {
            name = "Rewards: an owned or unresolved item pays duplicateCurrency",
            func = function()
                local reward = { xp = 40, currency = 7, duplicateCurrency = 11, items = { owned, missing, locked } }
                local f = fixture(stub, reward)
                upload(f, nil, { [ownedKey] = true })
                complete(f)
                expect(#f.grants).to.equal(1)
                expect(f.grants[1].count).to.equal(1)
                expect(f.deltas[1].earned).to.equal(29)
                local granted = assert(f.deltas[1].granted)
                expect(table.Count(granted)).to.equal(1)
                expect(granted[lockedKey].grant).to.equal(claimId(f))
            end
        },
        {
            name = "Rewards: economy disabled skips currency only",
            func = function()
                local reward = { xp = 40, currency = 7, duplicateCurrency = 11, items = { missing, locked } }
                local f = fixture(stub, reward, 0, false)
                upload(f)
                complete(f)
                expect(table.HasValue(f.trace, "currency")).to.beFalse()
                expect(f.deltas[1].xp).to.equal(40)
                expect(f.deltas[1].earned).to.equal(0)
                expect(assert(f.deltas[1].granted)[lockedKey].grant).to.equal(claimId(f))
            end
        },
        {
            name = "Rewards: the weekly bonus uses its own claim id and is granted once",
            func = function()
                local f = fixture(stub, nil, 1)
                upload(f)
                complete(f)
                expect(#f.grants).to.equal(2)
                expect(f.grants[1].claim).to.equal(claimId(f))
                expect(f.grants[2].claim).to.equal(claimId(f, "bonus"))
                expect(f.grants[2].count).to.equal(0)
                local reward = assert(PW._ChallengeServer).week.bonus.reward
                expect(f.deltas[2].xp).to.equal(reward.xp)
                expect(f.deltas[2].earned).to.equal(reward.currency)
                expect(assert(f.deltas[2].claims)[claimId(f, "bonus")] ~= nil).to.beTrue()
                boot(f)
                complete(f)
                nextPhase(f)
                expect(#f.grants).to.equal(2)
                expect(#f.deltas).to.equal(2)
            end
        },
        {
            name = "Rewards: a reward flushes the progression delta at once",
            func = function()
                local f = fixture(stub, { xp = 40, currency = 7 })
                upload(f)
                complete(f)
                expect(#f.deltas).to.equal(1)
                local delta = f.deltas[1]
                expect(delta.xp).to.equal(40)
                expect(delta.earned).to.equal(7)
                expect(assert(delta.claims)[claimId(f)] ~= nil).to.beTrue()
                expect(f.store.pending[f.ply]).to.beNil()
            end
        },
        {
            name = "Rewards: full entitlement set retries claim-only with one XP and currency payout",
            func = function()
                local reward = { xp = 40, currency = 7, duplicateCurrency = 11, items = { locked } }
                claimOnlyRetry(fixture(stub, reward), "full", expect)
            end
        },
        {
            name = "Rewards: toomany retries claim-only with one XP and currency payout",
            func = function()
                local reward = { xp = 40, currency = 7, duplicateCurrency = 11, items = { locked } }
                claimOnlyRetry(fixture(stub, reward), "toomany", expect)
            end
        },
        {
            name = "Rewards: XP batch pressure defers the original payout with items until a later phase",
            func = function()
                local reward = { xp = 40, currency = 7, duplicateCurrency = 11, items = { locked } }
                local f = fixture(stub, reward)
                upload(f)
                local p = f.progression
                local independentXP = p.MaxDeltaXP - 39
                p.AddXP(f.ply, independentXP) -- Both gains fit alone, but their total is one over.
                local state = p.GetState(f.ply)
                local pending = assert(f.store.pending[f.ply])

                complete(f)
                expect(#f.grants).to.equal(1) -- Not an item-capacity refusal: no claim-only retry.
                expect(f.grants[1]).to.deepEqual({
                    count = 1, source = "challenge", claim = claimId(f), xp = 40, currency = 7, reason = "balancefull"
                })
                expect(p.GetState(f.ply)).to.deepEqual(state)
                expect(f.unlocks.HasClaim(f.ply, claimId(f))).to.beFalse()
                expect(rawequal(f.store.pending[f.ply], pending)).to.beTrue()
                expect(pending.xp).to.equal(independentXP)
                expect(pending.earned).to.equal(0)
                expect(next(assert(pending.claims))).to.beNil()
                expect(#f.deltas).to.equal(0)

                local independent = assert(p._Flush(f.store, f.ply))
                expect(independent.xp).to.equal(independentXP)
                expect(independent.earned).to.equal(0)
                expect(next(assert(independent.claims))).to.beNil()
                expect(#f.deltas).to.equal(1)

                nextPhase(f)
                expect(#f.grants).to.equal(2)
                expect(f.grants[2]).to.deepEqual({
                    count = 1, source = "challenge", claim = claimId(f), xp = 40, currency = 7
                })
                expect(#f.deltas).to.equal(2)
                local paid = f.deltas[2]
                expect(paid.xp).to.equal(40)
                expect(paid.earned).to.equal(7)
                expect(assert(paid.claims)[claimId(f)] ~= nil).to.beTrue()
                expect(assert(paid.granted)[lockedKey].grant).to.equal(claimId(f))
            end
        },
        {
            name = "Rewards: an unexpected Grant refusal cannot leak rewards through the progression timer",
            func = function()
                local f = fixture(stub)
                upload(f)
                f.refusal = "unknown" -- Grant can re-resolve a key after Describe.
                f.progression.AddXP(f.ply, 3) -- unrelated gain must remain flushable
                complete(f)
                expect(#f.grants).to.equal(1)
                expect(f.grants[1].reason).to.equal("unknown")
                expect(f.grants[1].xp).to.equal(40)
                expect(f.grants[1].currency).to.equal(7)
                expect(#f.logs).to.equal(1)
                expect(#f.deltas).to.equal(0)
                expect(f.progression.GetState(f.ply).xp).to.equal(3)
                expect(f.progression.GetCurrency(f.ply)).to.equal(0)
                expect(assert(f.store.pending[f.ply]).xp).to.equal(3)
                expect(assert(f.store.pending[f.ply]).earned).to.equal(0)
                f.progression._Tick(f.store, 0)
                f.progression._Tick(f.store, f.progression.FlushInterval)
                expect(#f.deltas).to.equal(1)
                local unrelated = f.deltas[1]
                expect(unrelated.xp).to.equal(3)
                expect(unrelated.earned).to.equal(0)
                expect(next(assert(unrelated.claims))).to.beNil()
                expect(f.progression.GetCurrency(f.ply)).to.equal(0)
                f.refusal = nil
                nextPhase(f)
                expect(#f.grants).to.equal(2)
                expect(f.grants[2].count).to.equal(1)
                expect(#f.deltas).to.equal(2)
                expect(f.deltas[2].xp).to.equal(40)
                expect(f.deltas[2].earned).to.equal(7)
                expect(assert(f.deltas[2].claims)[claimId(f)] ~= nil).to.beTrue()
            end
        }
    }
}
