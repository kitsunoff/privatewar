-- Review regressions first. Engine RED/GREEN is unobserved without authorized game access.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil) return value end
---@return PW.SNDLib
local function snd() return must(PW.SND) end
---@return PW.MapLib
local function map() return must(PW.Map) end
---@param x number
---@param y number
---@param name? string
---@return PW.SNDTarget
local function target(x, y, name)
    return { mins = Vector(x, y, 0), maxs = Vector(x + 16, y + 16, 128), name = name or "" }
end
---@return PW.SNDDeriveInput
local function facts()
    return { targets = { target(0, 0, "left"), target(40, 0, "right") },
        points = { Vector(8, 8, 0), Vector(48, 8, 0) },
        spawns = { [1] = { { pos = Vector(-200, 0, 0), yaw = 0 } },
            [2] = { { pos = Vector(200, 0, 0), yaw = 0 } } },
        safe = function() return true end, mutual = function() return true end }
end

---@param state table<string, any>
---@param makeStub fun(object: table, key: string): table<string, any>
local function setup(state, makeStub)
    -- Helpers do not inherit a case's injected GLuaTest environment.
    makeStub(map(), "Get").with(function() return state.mapEntry end)
    makeStub(game, "GetMap").with(function() return "de_pw_review_fixture" end)
    makeStub(_G, "SetGlobal2String").with(function() end)
    makeStub(_G, "SetGlobal2Bool").with(function() end)
    makeStub(map(), "IsNavReady").with(function() return state.navReady ~= false and not PW._Map.navPaused end)
end

---@param reason string
---@param makeStub fun(object: table, key: string): table<string, any>
---@param check fun(value: any): table<string, any>
local function invalidation(reason, makeStub, check)
    local lib, data = snd(), must(snd().Derive((function()
        local input = facts()
        input.targets[2] = target(1000, 0, "right")
        input.points[2] = Vector(1008, 8, 0)
        return input
    end)()))
    local mode = setmetatable({ ClassName = "snd", IsValid = function() return true end,
        _SNDMap = data, _SND = lib.NewRound(data, {}, 0, 1) }, { __index = must(PW.Modes.Get("snd")) })
    local previous = mode._SND
    rawset(PW, "ActiveMode", mode)
    local clears, aborts = 0, 0
    makeStub(player, "GetAll").with(function() return {} end)
    makeStub(_G, "SetGlobal2Int").with(function() end)
    makeStub(_G, "SetGlobal2Float").with(function() end)
    makeStub(lib, "Publish").with(function(value) if value == nil then clears = clears + 1 end end)
    makeStub(must(PW.Match), "Abort").with(function(message)
        aborts = aborts + 1
        check(#message > 0).to.beTrue()
        return true
    end)
    makeStub(PW, "Notify").with(function(event, message, cause)
        if event == "PW_MapDataInvalidated" then
            PW.Call(must(PW.Modules.Get("snd")), event, message, cause)
        end
    end)
    map().SetGeneratedModeData("snd", data)
    check(map().GetModeData("snd")).to.equal(data)
    if reason == "reload" then
        PW.Call(must(PW.Modules.Get("mapdata")), "PW_RegistriesLoaded")
    else
        local owner = must(PW.Modules.Get("mapdata"))
        makeStub(map(), "_Refresh").with(function() return {} end)
        must(must(owner._EngineHooks).PostCleanupMap)(owner)
    end
    check(PW._Map.generated).to.beNil()
    check(map().GetModeReadiness("snd")).to.equal("pending")
    if reason == "reload" then
        check(mode._SND).to.equal(previous)
        check(mode._SNDMap).to.equal(data)
        check(clears + aborts).to.equal(0)
    else
        check(mode._SND).to.beNil()
        check(mode._SNDMap).to.beNil()
        check(mode._Rounds).to.beNil()
        check(clears).to.equal(1)
        check(aborts).to.equal(1)
    end
end

return { groupName = "PW SND automatic layout review regressions",
    beforeEach = function(state)
        state.mapStore, state.active, state.sndStore = PW._Map, PW.ActiveMode, PW._SND
        rawset(PW, "ActiveMode", nil)
        PW._Map = map()._NewStore()
        PW._SND = { generation = 1, serial = 0, nextSnapshot = 0 }
    end,
    afterEach = function(state)
        PW._Map = state.mapStore --[[@as PW.MapStore]]
        PW._SND = state.sndStore --[[@as PW.SNDStore]]
        rawset(PW, "ActiveMode", state.active)
    end,
    cases = {
        { name = "SND review: a single unnamed target adjacent to a named group rejects", func = function()
            expect(snd().GroupTargets({ target(0, 0, "named"), target(32, 0), target(1000, 0, "other") }))
                .to.beNil()
        end },
        { name = "SND review: AABB proximity uses Euclidean three-axis gaps including diagonal 100 100",
            func = function()
            local groups = snd().GroupTargets({ target(0, 0), target(116, 116) })
            expect(#must(groups)).to.equal(2)
            expect(snd().GroupTargets({ target(0, 0), target(116, 0) })).to.beNil()
            local raised = target(0, 0)
            raised.mins.z, raised.maxs.z = 257, 385
            expect(#must(snd().GroupTargets({ target(0, 0), raised }))).to.equal(2)
        end },
        { name = "SND review: generated plant cylinders must not intersect or touch", func = function()
            local data, reason = snd().Derive(facts())
            expect(data).to.beNil()
            expect(#must(reason) > 0).to.beTrue()
            local input = facts()
            input.targets[2] = target(64, 0, "right")
            input.points[2] = Vector(72, 8, 0)
            expect(snd().Derive(input)).to.beNil()
        end },
        { name = "SND review: A B order follows union AABB center rather than the first brush", func = function()
            local group = { target(-1000, 0, "wide"), target(2000, 0, "wide"), target(0, 0, "middle") }
            local groups = must(snd().GroupTargets(group))
            expect(groups[1][1].name).to.equal("middle")
            groups = must(snd().GroupTargets({ group[3], group[2], group[1] }))
            expect(groups[1][1].name).to.equal("middle")
        end },
        { name = "SND review: map cleanup invalidates runtime rounds generated data and public snapshots",
            func = function(state) setup(state, stub) invalidation("map cleanup", stub, expect) end },
        { name = "SND review: pw_reload invalidates next-match data but preserves the active round",
            func = function(state) setup(state, stub) invalidation("reload", stub, expect) end },
        { name = "SND review: nav data alone cannot certify entities before InitPostEntity", func = function()
            PW._Map.nav = { loaded = true, areas = {}, samples = {}, eligible = 0, costMs = 0 }
            expect(map().IsNavReady()).to.beFalse()
            PW._Map.entitiesReady = true
            expect(map().IsNavReady()).to.beTrue()
            PW._Map.navPaused = true
            expect(map().IsNavReady()).to.beFalse()
        end },
        { name = "SND review: first reload upgrades a legacy completed nav cache without reusing its handles",
            func = function()
            PW._Map.nav = { loaded = true, areas = {}, samples = {}, eligible = 0, costMs = 0 }
            stub(_G, "SetGlobal2String").with(function() end)
            stub(_G, "SetGlobal2Bool").with(function() end)
            PW.Call(must(PW.Modules.Get("mapdata")), "PW_RegistriesLoaded")
            expect(PW._Map.entitiesReady).to.beTrue()
            expect(PW._Map.nav).to.beNil()
            expect(map().IsNavReady()).to.beFalse()
        end },
        { name = "SND review: reload rebuilds once only after current entities and nav become ready",
            func = function(state)
            setup(state, stub)
            local attempts = 0
            stub(snd(), "PrepareMap").with(function() attempts = attempts + 1 end)
            state.navReady = false
            snd()._ReadinessThink()
            expect(attempts).to.equal(0)
            state.navReady = true
            snd()._ReadinessThink()
            snd()._ReadinessThink()
            expect(attempts).to.equal(1)
            PW.Call(must(PW.Modules.Get("mapdata")), "PW_RegistriesLoaded")
            snd()._ReadinessThink()
            snd()._ReadinessThink()
            expect(attempts).to.equal(2)
        end },
        { name = "SND review: failed explicit detection is not automatically retried but explicit retry is allowed",
            func = function(state)
            setup(state, stub)
            local attempts = 0
            stub(snd(), "Detect").with(function()
                attempts = attempts + 1
                return nil, "Fixture source rejected"
            end)
            expect(snd().PrepareMap("snd")).to.beNil()
            snd()._ReadinessThink()
            expect(attempts).to.equal(1)
            expect(map().GetModeReadiness("snd")).to.equal("rejected")
            expect(snd().PrepareMap("snd")).to.beNil()
            expect(attempts).to.equal(2)
        end },
        { name = "SND review: nav generation is pending and preserves legacy samples and detected pools",
            func = function(state)
            setup(state, stub)
            local samples = { { pos = Vector(1, 2, 3), yaw = 0 } }
            local detected = { [1] = samples }
            PW._Map.detected = detected
            PW._Map.nav = { loaded = true, areas = {}, samples = samples, eligible = 1, costMs = 0 }
            map().SetModeReadiness("snd", "ready", nil, "generated")
            map().PauseNav(true)
            expect(map().GetModeReadiness("snd")).to.equal("pending")
            expect(map().GetModeData("snd")).to.beNil()
            expect(must(map().GetNavSamples)()).to.equal(samples)
            expect(must(map().GetDetectedSpawns)()).to.equal(detected)
        end },
        { name = "SND review: inherited generated readiness cannot survive rejection of its shared source",
            func = function(state)
            setup(state, stub)
            local base = must(PW.Modes.Get("snd"))
            local child = setmetatable({ ClassName = "pw_review_child", BaseClass = base,
                IsValid = function() return true end }, { __index = base })
            local get = PW.Modes.Get
            stub(PW.Modes, "Get").with(function(id)
                if id == "pw_review_child" then return child end
                return get(id)
            end)
            map().SetModeReadiness("snd", "ready", nil, "generated")
            map().SetModeReadiness("pw_review_child", "ready", nil, "generated")
            expect(map().GetModeReadiness("pw_review_child")).to.equal("ready")
            map().SetGeneratedModeData("snd", nil)
            map().SetModeReadiness("snd", "rejected", "No safe site")
            expect(map().GetModeReadiness("pw_review_child")).to.equal("rejected")
            expect(map().ModeFits(child, game.GetMap())).to.beFalse()
            expect(map().GetModeData("pw_review_child")).to.beNil()
        end },
        { name = "SND review: a candidate callback cannot broaden unrelated round or objective modes",
            func = function(state)
            setup(state, stub)
            local unrelated = { ClassName = "snd_impostor", BaseClass = must(PW.Modes.Get("round_base")),
                MapData = true, MapCandidate = function() return true end }
            local ok, _, source = map().ModeFits(unrelated, "de_pw_review_fixture")
            expect(ok).to.beFalse()
            expect(source).to.beNil()
            unrelated.ClassName, unrelated.BaseClass = "pw_review_snd_child", must(PW.Modes.Get("snd"))
            expect(map().ModeFits(unrelated, "cs_pw_review_fixture")).to.beFalse()
            expect(map().ModeFits(unrelated, "de_pw_review_fixture")).to.beTrue()
        end },
        { name = "SND review: current readiness and ModeFits distinguish pending ready rejected and sources",
            func = function(state)
            setup(state, stub)
            local mode = must(PW.Modes.Get("snd"))
            expect(map().GetModeReadiness("snd")).to.equal("pending")
            local ok, _, source = map().ModeFits(mode, game.GetMap())
            expect(ok).to.beTrue()
            expect(source).to.equal("provisional")
            map().SetModeReadiness("snd", "rejected", "No safe plant points")
            local readiness, reason = map().GetModeReadiness("snd")
            expect(readiness).to.equal("rejected")
            expect(reason).to.equal("No safe plant points")
            expect(map().ModeFits(mode, game.GetMap())).to.beFalse()
            local input = facts()
            input.targets[2], input.points[2] = target(1000, 0, "right"), Vector(1008, 8, 0)
            local data = must(snd().Derive(input))
            map().SetGeneratedModeData("snd", data)
            expect(map().GetModeData("snd")).to.equal(data)
            ok, _, source = map().ModeFits(mode, game.GetMap())
            expect(ok).to.beTrue()
            expect(source).to.equal("generated")
            expect(map().GetModeReadiness("snd")).to.equal("ready")
            local unloaded, _, classification = map().ModeFits(mode, "de_other_review_fixture")
            expect(unloaded).to.beTrue()
            expect(classification).to.equal("provisional")
            state.mapEntry = { Modes = { snd = data } }
            local authored, _, authoredSource = map().ModeFits(mode, game.GetMap())
            expect(authored).to.beTrue()
            expect(authoredSource).to.equal("authored")
            state.mapEntry = { Modes = { snd = false } }
            local invalid, _, rejectedSource = map().ModeFits(mode, game.GetMap())
            expect(invalid).to.beFalse()
            expect(rejectedSource).to.beNil()
        end }
    }
}
