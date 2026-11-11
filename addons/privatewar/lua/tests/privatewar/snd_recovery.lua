-- Recovery regressions: reload keeps the pinned match; next-match readiness and explicit retry are separate.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil) return value end
---@return PW.SNDLib
local function snd() return must(PW.SND) end
---@return PW.MapLib
local function map() return must(PW.Map) end
---@return PW.SNDMapData
local function layout()
    return { bomb = Vector(-200, 0, 0), spawns = {
        [1] = { { pos = Vector(-200, 0, 0), yaw = 0 } },
        [2] = { { pos = Vector(1500, 0, 0), yaw = 180 } }
    }, sites = {
        { id = "A", pos = Vector(0, 0, 0), approach = Vector(0, 0, 0), radius = 64, above = 72, below = 16 },
        { id = "B", pos = Vector(1000, 0, 0), approach = Vector(1000, 0, 0), radius = 64, above = 72, below = 16 }
    } }
end

return { groupName = "PW SND reload and explicit recovery",
    beforeEach = function(state)
        state.mapStore, state.sndStore, state.active = PW._Map, PW._SND, PW.ActiveMode
        PW._Map = map()._NewStore()
        PW._SND = { generation = 1, serial = 1, nextSnapshot = 0 }
        rawset(PW, "ActiveMode", nil)
    end,
    afterEach = function(state)
        PW._Map = state.mapStore --[[@as PW.MapStore]]
        PW._SND = state.sndStore --[[@as PW.SNDStore]]
        rawset(PW, "ActiveMode", state.active)
    end,
    cases = {
        { name = "SND recovery: LIVE reload keeps roster deadline interaction rounds and snapshots pinned",
            func = function()
            local data = layout()
            local round = snd().NewRound(data, {
                { id = "attacker", userId = 1, team = 1, alive = true, pos = Vector(0, 0, 0),
                    use = true, clear = true, generation = 1 },
                { id = "defender", userId = 2, team = 2, alive = true, pos = Vector(1000, 0, 0),
                    use = false, clear = true, generation = 1 }
            }, 0, 1, "attacker")
            round.roster.attacker.spawned = true
            round.pos = Vector(0, 0, 0)
            round.interaction = { id = "attacker", userId = 1, generation = 1, action = "plant", site = "A", at = 0 }
            local rounds = { n = 2, phase = "round" }
            local mode = setmetatable({ ClassName = "snd", IsValid = function() return true end,
                _SND = round, _Rounds = rounds, _SNDMap = data }, { __index = must(PW.Modes.Get("snd")) })
            rawset(PW, "ActiveMode", mode)
            local nav = { loaded = true, areas = {}, samples = {}, eligible = 0, costMs = 0 }
            PW._Map.nav = nav
            local cleanups, aborts, publications, prepares = 0, 0, 0, 0
            stub(mode, "Cleanup").with(function() cleanups = cleanups + 1 end)
            stub(must(PW.Match), "Abort").with(function() aborts = aborts + 1 end)
            stub(must(PW.Match), "GetPhase").with(function() return "LIVE" end)
            stub(snd(), "Publish").with(function() publications = publications + 1 end)
            stub(snd(), "PrepareMap").with(function() prepares = prepares + 1 end)
            stub(map(), "IsNavReady").with(function() return true end)
            stub(_G, "SetGlobal2String").with(function() end)
            stub(_G, "SetGlobal2Bool").with(function() end)
            stub(PW, "Notify").with(function(event, ...)
                if event == "PW_MapDataInvalidated" then PW.Call(must(PW.Modules.Get("snd")), event, ...) end
            end)
            map().SetGeneratedModeData("snd", data)
            PW.Call(must(PW.Modules.Get("mapdata")), "PW_RegistriesLoaded")
            snd()._ReadinessThink()
            expect(mode._SND).to.equal(round)
            expect(mode._Rounds).to.equal(rounds)
            expect(mode._SNDMap).to.equal(data)
            expect(round.deadline).to.equal(120)
            expect(must(round.interaction).id).to.equal("attacker")
            expect(round.carrier).to.equal("attacker")
            expect(round.roster.attacker.spawned).to.beTrue()
            expect(PW._SND.generation).to.equal(1)
            expect(PW._SND.serial).to.equal(1)
            expect(PW._Map.generated).to.beNil()
            expect(PW._Map.nav).to.equal(nav)
            expect(cleanups + aborts + publications + prepares).to.equal(0)
        end },
        { name = "SND recovery: the next round after reload uses the match map without consulting new generated data",
            func = function()
            local data = layout()
            local mode = setmetatable({ _SNDMap = data, ClassName = "snd", IsValid = function() return true end },
                { __index = must(PW.Modes.Get("snd")) })
            stub(map(), "GetModeData").with(function() error("must not read next-match geometry") end)
            stub(snd(), "Roster").with(function() return {} end)
            stub(snd(), "AdmitRoster").with(function() end)
            stub(snd(), "Physical").with(function() end)
            stub(snd(), "Publish").with(function() end)
            mode:PrepareRound(2, false)
            expect(must(mode._SND).map).to.equal(data)
        end },
        { name = "SND recovery: rejected candidates retain their exact reason and allow only explicit retry",
            func = function()
            stub(map(), "Get").with(function() return nil end)
            stub(map(), "IsNavReady").with(function() return true end)
            stub(game, "GetMap").with(function() return "de_pw_recovery_fixture" end)
            stub(must(PW.Match), "GetPhase").with(function() return "LOBBY" end)
            local detections = 0
            stub(snd(), "Detect").with(function() detections = detections + 1 return layout() end)
            stub(snd(), "Activate").with(function() end)
            map().SetModeReadiness("snd", "rejected", "No safe bomb target")
            local status = map().GetModeAvailability("snd")
            expect(status.fits).to.beFalse()
            expect(status.reason).to.equal("No safe bomb target")
            expect(status.canRetry).to.beTrue()
            expect(map().GetModeAvailability("snd").reason).to.equal("No safe bomb target")
            expect(detections).to.equal(0)
            expect(snd().RetryMap("snd") ~= nil).to.beTrue()
            expect(detections).to.equal(1)
            expect(map().GetModeAvailability("snd").fits).to.beTrue()
        end },
        { name = "SND recovery: malformed authored data is not retryable through generated fallback", func = function()
            stub(map(), "Get").with(function() return { Modes = { snd = false } } end)
            stub(map(), "IsNavReady").with(function() return true end)
            stub(game, "GetMap").with(function() return "de_pw_recovery_fixture" end)
            stub(must(PW.Match), "GetPhase").with(function() return "LOBBY" end)
            local detections = 0
            stub(snd(), "Detect").with(function() detections = detections + 1 return layout() end)
            local status = map().GetModeAvailability("snd")
            expect(status.fits).to.beFalse()
            expect(status.canRetry).to.beFalse()
            expect(snd().RetryMap("snd")).to.beNil()
            expect(detections).to.equal(0)
        end },
        { name = "SND recovery: an explicit retry cannot replace geometry during LIVE", func = function()
            stub(must(PW.Match), "GetPhase").with(function() return "LIVE" end)
            local prepares = 0
            stub(snd(), "PrepareMap").with(function() prepares = prepares + 1 return layout() end)
            expect(snd().RetryMap("snd")).to.beNil()
            expect(prepares).to.equal(0)
        end },
        { name = "SND recovery: retry metadata never broadens Domination or Hardpoint map eligibility",
            func = function()
            stub(map(), "Get").with(function() return nil end)
            stub(game, "GetMap").with(function() return "de_pw_recovery_fixture" end)
            for _, id in ipairs({ "dom", "hardpoint" }) do
                local status = map().GetModeAvailability(id)
                expect(status.fits).to.beFalse()
                expect(status.canRetry).to.beFalse()
                expect(#must(status.reason) > 0).to.beTrue()
            end
        end }
    }
}
