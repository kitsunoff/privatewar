-- Step 10: exercise the real registered upload handler and the state-send boundary.

local channel = "pw_challenges_upload"

---@param userId integer
---@param bot? boolean
---@return Player
local function actor(userId, bot)
    return { IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return bot == true end, UserID = function() return userId end,
        Nick = function() return "fixture" end, SteamID64 = function() return "76561198000000001" end } --[[@as Player]]
end

---@param def PW.NetDef
---@param clock fun(): number
---@return PW.NetLib
local function isolatedNet(def, clock)
    local facade = assert(PW.Net)
    PW._Net = facade._NewStore({ clock = clock, phase = function() return "LOBBY" end, log = function() end })
    PW._Net.defs[channel] = def
    return facade
end

local function isolateServer()
    local live = assert(rawget(PW, "_ChallengeServer") --[[@as PW.ChallengeServer?]])
    local deps = table.Copy(live.deps) --[[@as PW.ChallengeServerDeps]]
    deps.isPlayer = function(ply) return IsValid(ply) and ply:IsPlayer() end
    deps.catalogue = function() return {} end
    deps.options = nil
    deps.schedule = function() end
    PW._ChallengeServer = assert(PW.Challenges)._NewServer(deps)
end

return {
    groupName = "PW challenges server",
    beforeEach = function(state)
        state.previousNet, state.previousServer = PW._Net, PW._ChallengeServer
        isolateServer()
    end,
    afterEach = function(state) PW._Net, PW._ChallengeServer = state.previousNet, state.previousServer end,
    cases = {
        {
            name = "Net: the upload is accepted once per connection and bounded",
            func = function()
                local module = PW.Modules.GetStored("challenges")
                local def = PW._Net.defs[channel]
                expect(def ~= nil).to.beTrue()
                assert(def ~= nil and module ~= nil)
                local challenges = assert(PW.Challenges)
                expect(rawequal(def.owner, module)).to.beTrue()
                expect(IsValid(module)).to.beTrue()
                expect(def.who).to.equal("any")
                expect(def.rate).to.equal(0.5)
                expect(def.maxLen).to.equal(challenges.UploadMaxBytes)
                expect(def.maxLen < 8192).to.beTrue()

                local owner, reconnect, bot = actor(11), actor(12), actor(13, true)
                local now, reads, count, broadcasts = 0, 0, 7, 0
                local facade = isolatedNet(def, function() return now end)
                ---@type string[]
                local starts = {}
                ---@type Player[]
                local sends = {}
                stub(net, "ReadUInt").with(function()
                    reads = reads + 1
                    return count
                end)
                stub(net, "Start").with(function(name) starts[#starts + 1] = name end)
                stub(net, "WriteUInt").with(function() end)
                stub(net, "Send").with(function(ply) sends[#sends + 1] = ply end)
                stub(net, "Broadcast").with(function() broadcasts = broadcasts + 1 end)

                def.handler(bot, 3)
                expect(reads).to.equal(0)
                expect(#starts).to.equal(0)
                expect({ facade._Dispatch(channel, def.maxLen * 8 + 1, owner) }).to.deepEqual({ false, "length" })
                expect(reads).to.equal(0)
                expect({ facade._Dispatch(channel, 3, owner) }).to.deepEqual({ false, "rate" })

                now = 2.1
                expect(facade._Dispatch(channel, 3, owner)).to.beTrue() -- Dispatch, not acceptance.
                expect(reads).to.equal(1)
                expect(#starts).to.equal(0) -- Forged count=7: reject without consuming the profile upload.
                now, count = 4.2, 0
                expect(facade._Dispatch(channel, 3, owner)).to.beTrue()
                expect(reads).to.equal(2)
                expect(starts).to.deepEqual({ "pw_challenges_state" })
                expect(rawequal(sends[1], owner)).to.beTrue()

                now = 6.3 -- Past the rate limiter: the receiver's once gate must defend independently.
                expect(facade._Dispatch(channel, 3, owner)).to.beTrue()
                expect(reads).to.equal(2)
                expect(#sends).to.equal(1)
                expect(facade._Dispatch(channel, 3, reconnect)).to.beTrue()
                expect(reads).to.equal(3)
                expect(#sends).to.equal(2)
                expect(rawequal(sends[2], reconnect)).to.beTrue()
                expect(broadcasts).to.equal(0)
            end
        },
        {
            name = "Net: the exact state payload cap is checked before starting an owner message",
            func = function()
                local def = PW._Net.defs[channel]
                expect(def ~= nil).to.beTrue()
                assert(def ~= nil)
                local facade = isolatedNet(def, function() return 0 end)
                local challenges = assert(PW.Challenges)
                local over, exact = actor(21), actor(22)
                local bits = 2049 * 8
                ---@type PW.ChallengeWireState[]
                local measured = {}
                ---@type string[]
                local order = {}
                ---@type Player[]
                local recipients = {}
                stub(net, "ReadUInt").returns(0)
                stub(challenges, "_StateBits").with(function(state)
                    measured[#measured + 1] = state
                    order[#order + 1] = "measure"
                    return bits
                end)
                stub(net, "Start").with(function(name) order[#order + 1] = name end)
                stub(net, "WriteUInt").with(function() end)
                stub(net, "Send").with(function(ply) recipients[#recipients + 1] = ply end)

                expect(facade._Dispatch(channel, 3, over)).to.beTrue()
                expect(order).to.deepEqual({ "measure" })
                expect(#recipients).to.equal(0)
                bits = 2048 * 8
                expect(facade._Dispatch(channel, 3, exact)).to.beTrue()
                expect(order).to.deepEqual({ "measure", "measure", "pw_challenges_state" })
                expect(#recipients).to.equal(1)
                expect(rawequal(recipients[1], exact)).to.beTrue()
                expect(measured[2].week.bonus.reward ~= nil).to.beTrue()
            end
        }
    }
}
