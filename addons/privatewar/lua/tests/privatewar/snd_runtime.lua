-- Runtime registration/policy contracts, kept independent of the actual running match.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil, "expected S&D runtime") return value end
---@return PW.SNDMode
local function mode() return must(PW.Modes.Get("snd")) --[[@as PW.SNDMode]] end

return { groupName = "PW SND runtime policy",
    beforeEach = function(state) state.throwables = PW._Throwables end,
    afterEach = function(state) PW._Throwables = state.throwables end,
    cases = {
    { name = "SND runtime: concrete round child registers with approved preset and authored-map validation",
        func = function()
            local snd = mode()
            expect(snd.Base).to.equal("round_base")
            expect(snd.Teams).to.equal(2)
            expect(snd.RoundsToWin).to.equal(6)
            expect(snd.SwapSidesEvery).to.equal(3)
            expect(snd.BotQuotaPolicy).to.equal("rounds")
            expect(snd.TeamPolicy).to.equal("managed")
            expect(snd.MapData).to.beTrue()
            local map = must(must(PW.Map).GetModeData("snd"))
            expect(snd:ValidateMapData(map)).to.beTrue()
        end },
    { name = "SND runtime: JIP is always deferred and no automatic death respawn is permitted", func = function()
        local snd = mode()
        expect(snd:PW_CanJoinInProgress()).to.beFalse()
        expect(snd:PW_CanRespawn()).to.beFalse()
    end },
    { name = "SND runtime: intermission disables combat bot behavior and loadout activation without new rewards",
        func = function()
            local snd = setmetatable({ _Rounds = { phase = "intermission" } }, { __index = mode() })
                --[[@as PW.SNDMode]]
            expect(snd:PW_CanTakeDamage()).to.beFalse()
            expect(snd:PW_CanRunBotBehavior()).to.beFalse()
            expect(snd:PW_CanUseLoadoutKind()).to.beFalse()
    end },
    { name = "SND runtime: match damage boundary delegates the mode veto and preserves ordinary default",
        func = function()
            local module = must(PW.Modules.Get("match_rules"))
            local handler = must(must(module._EngineHooks).EntityTakeDamage)
            stub(must(PW.Match), "GetPhase").with(function() return "LIVE" end)
            local blocked = true
            stub(PW, "Ask").with(function(name)
                expect(name).to.equal("PW_CanTakeDamage")
                if blocked then return false end
            end)
            local target = { IsPlayer = function() return true end }
            local damage = { GetAttacker = function() return NULL end }
            expect(handler(module, target, damage)).to.beTrue()
            blocked = false
            expect(handler(module, target, damage)).to.beNil()
        end },
    { name = "SND runtime: round boundary removes owned projectiles without detonating or changing streak inventory",
        func = function()
            local removed = 0
            local projectile = { IsValid = function() return removed == 0 end,
                Remove = function() removed = removed + 1 end }
            PW._Throwables = { live = { [projectile] = true } }
            local module = must(PW.Modules.Get("throwables"))
            PW.Call(module, "PW_RoundEnd", 1, 1, { 1, 0 })
            expect(removed).to.equal(1)
            expect(PW._Throwables.live).to.deepEqual({})
            PW.Call(module, "PW_RoundEnd", 1, 1, { 1, 0 })
            expect(removed).to.equal(1)
        end },
    { name = "SND runtime: every spawn uses the authored side pool rather than dynamic whole-map points",
        func = function()
            local pool = { [1] = { { pos = Vector(1, 2, 3), yaw = 0 } },
                [2] = { { pos = Vector(4, 5, 6), yaw = 180 } } }
            local snd = setmetatable({ _SND = { map = { spawns = pool } } }, { __index = mode() })
            local called = 0
            stub(must(PW.Spawns), "Pick").with(function(_, opts)
                called = called + 1
                expect(opts.spawns).to.equal(pool)
                expect(opts.first).to.beTrue()
                expect(opts.all).to.beFalse()
                return pool[1][1]
            end)
            expect(snd:PW_SelectSpawn(NULL)).to.equal(pool[1][1])
            expect(called).to.equal(1)
        end },
    { name = "SND runtime: round cleanup cancels owned active flash overlay and DSP without replaying an effect",
        func = function()
            PW._Throwables = { live = {} }
            local dsp = 0
            ---@type integer[]
            local strengths = {}
            local target = { IsValid = function() return true end, IsBot = function() return false end,
                SetDSP = function(_, value) dsp = value end }
            stub(net, "Start").with(function(name) expect(name).to.equal("pw_blind") end)
            stub(net, "WriteUInt").with(function(value) strengths[#strengths + 1] = value end)
            stub(net, "Send").with(function(ply) expect(ply).to.equal(target) end)
            stub(PW, "Notify").with(function() end)
            expect(must(must(PW.Throwables).Blind)(target --[[@as Player]], 1)).to.beTrue()
            expect(dsp).to.equal(35)
            local module = must(PW.Modules.Get("throwables"))
            PW.Call(module, "PW_RoundEnd", 1, 1, { 1, 0 })
            expect(dsp).to.equal(0)
            expect(strengths).to.deepEqual({ 255, 0 })
            PW.Call(module, "PW_RoundEnd", 1, 1, { 1, 0 })
            expect(strengths).to.deepEqual({ 255, 0 })
        end }
} }
