-- Tests first: game RED/GREEN requires the orchestrator's authorized engine run.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil) return value end
---@return PW.SNDLib
local function lib() return must(PW.SND) end
---@param x number
---@param name? string
---@return PW.SNDTarget
local function target(x, name)
    return { mins = Vector(x, 0, 0), maxs = Vector(x + 128, 128, 128), name = name or "" }
end
---@return PW.SNDDeriveInput
local function input()
    return { targets = { target(0), target(1000) }, spawns = {
        [1] = { { pos = Vector(-200, 0, 0), yaw = 90 } },
        [2] = { { pos = Vector(1500, 0, 0), yaw = 180 } }
    }, points = { Vector(64, 64, 0), Vector(1064, 64, 0) },
    safe = function() return true end, mutual = function() return true end }
end

return { groupName = "PW SND automatic de layouts",
    beforeEach = function(state)
        state.mapStore = PW._Map
        PW._Map = must(PW.Map)._NewStore()
    end,
    afterEach = function(state) PW._Map = state.mapStore --[[@as PW.MapStore]] end,
    cases = {
    { name = "SND auto: each preflight redetects and only publishes after successful activation", func = function()
        local map = must(PW.Map)
        local data = must(lib().Derive(input()))
        local detects, activates, publications = 0, 0, 0
        local blocked = false
        stub(game, "GetMap").with(function() return "de_pw_auto_fixture" end)
        stub(map, "Get").with(function() return nil end)
        stub(map, "GetModeData").with(function() return nil end)
        stub(map, "SetGeneratedModeData").with(function(_, value)
            if value ~= nil then publications = publications + 1 end
        end)
        stub(lib(), "Detect").with(function() detects = detects + 1 return data end)
        stub(lib(), "Activate").with(function()
            activates = activates + 1
            if blocked then error("fixture blocked approach") end
        end)
        expect(lib().PrepareMap("snd")).to.equal(data)
        expect(lib().PrepareMap("snd")).to.equal(data)
        expect(detects).to.equal(2)
        expect(activates).to.equal(2)
        expect(publications).to.equal(2)
        blocked = true
        local rejected, reason = lib().PrepareMap("snd")
        expect(rejected).to.beNil()
        expect(string.find(must(reason), "blocked approach", 1, true) ~= nil).to.beTrue()
        expect(publications).to.equal(2)
    end },
    { name = "SND auto: directed one-way routes never qualify as mutual reachability", func = function()
        local backwards = false
        ---@type table<string, any>, table<string, any>
        local a, b = {}, {}
        a.IsValid, b.IsValid = function() return true end, function() return true end
        a.GetID, b.GetID = function() return 1 end, function() return 2 end
        a.GetClosestPointOnArea = function(_, pos) return pos end
        b.GetClosestPointOnArea = a.GetClosestPointOnArea
        a.GetAdjacentAreas = function() return { b } end
        b.GetAdjacentAreas = function() return backwards and { a } or {} end
        stub(navmesh, "GetNearestNavArea").with(function(pos)
            return (pos --[[@as Vector]]).x == 0 and a or b
        end)
        expect(lib()._AutoMutual(Vector(0, 0, 0), Vector(1000, 0, 0))).to.beFalse()
        backwards = true
        expect(lib()._AutoMutual(Vector(0, 0, 0), Vector(1000, 0, 0))).to.beTrue()
    end },
    { name = "SND auto: malformed authored data blocks detection and provisional fit", func = function()
        local map = must(PW.Map)
        local detects = 0
        stub(map, "Get").with(function() return { Modes = { snd = false } } end)
        stub(map, "GetModeData").with(function() return nil end)
        stub(lib(), "Detect").with(function() detects = detects + 1 end)
        expect(lib().PrepareMap("snd")).to.beNil()
        expect(map.ModeFits(must(PW.Modes.Get("snd")), "de_pw_auto_fixture")).to.beFalse()
        expect(detects).to.equal(0)
    end },
    { name = "SND auto: provisional fit follows the SND Base chain without broadening objective modes",
        func = function()
        local map = must(PW.Map)
        stub(map, "Get").with(function() return nil end)
        local snd = must(PW.Modes.Get("snd"))
        local child = { ClassName = "pw_auto_child", BaseClass = snd, MapData = true,
            MapCandidate = snd.MapCandidate, ValidateMapData = snd.ValidateMapData }
        expect(map.ModeFits(child, "DE_pw_auto_fixture")).to.beTrue()
        expect(map.ModeFits(child, "cs_pw_auto_fixture")).to.beFalse()
        for _, id in ipairs({ "dom", "hardpoint" }) do
            expect(map.ModeFits(must(PW.Modes.Get(id)), "de_pw_auto_fixture")).to.beFalse()
        end
    end },
    { name = "SND auto: readiness missing nav and foreign target ownership fail without mutation", func = function()
        local map = must(PW.Map)
        local ready = false
        local areas = {} --[[@as CNavArea[] ]]
        stub(map, "IsNavReady").with(function() return ready end)
        stub(map, "GetNavAreas").with(function() return areas end)
        expect(lib().Detect()).to.beNil()
        ready = true
        local data, reason = lib().Detect()
        expect(data).to.beNil()
        expect(string.find(must(reason), "requires a navmesh", 1, true) ~= nil).to.beTrue()
        areas = { {} --[[@as CNavArea]] }
        local foreign = { t = { foreign = true } }
        stub(scripted_ents, "GetStored").with(function() return foreign end)
        data, reason = lib().Detect()
        expect(data).to.beNil()
        expect(string.find(must(reason), "another addon", 1, true) ~= nil).to.beTrue()
        expect(scripted_ents.GetStored("func_bomb_target")).to.equal(foreign)
    end },
    { name = "SND auto: per-site expensive probes stop at sixteen and dimension bounds remain finite", func = function()
        local facts = input()
        facts.points = {}
        for _ = 1, 20 do facts.points[#facts.points + 1] = Vector(64, 64, 0) end
        local probes = 0
        facts.safe = function(pos)
            if pos.x == 64 then probes = probes + 1 return false end
            return true
        end
        expect(lib().Derive(facts)).to.beNil()
        expect(probes).to.equal(16)
        facts = input()
        facts.targets[1].maxs = Vector(math.huge, 128, 128)
        expect(lib().Derive(facts)).to.beNil()
    end },
    { name = "SND auto: snapshots carry only public site ids and positions and labels follow actual ids",
        func = function()
        local data = must(lib().Derive(input()))
        data.sites[1].id, data.sites[2].id = "North", "South"
        local state = lib().NewRound(data, {}, 0, 1)
        local view = lib().Snapshot(state, 2, "defender", 0)
        local sites = must(view.sites)
        expect(sites[1].id).to.equal("North")
        expect(sites[1].pos).to.equal(data.sites[1].pos)
        expect(view.pos).to.beNil()
        local _, line = lib().HudText(view, 0)
        expect(line).to.equal("SITES North / South")
        sites[1].pos = Vector(0 / 0, 0, 0)
        expect(lib().PublicSites(sites)).to.beNil()
    end },
    { name = "SND auto: authored malformed entry blocks generated fallback throughout inheritance", func = function()
        local map = must(PW.Map)
        local generated = { snd = { generated = true } }
        local chain = { "hardcore_snd", "snd" }
        local data, authored = map._ResolveModeData({ snd = false }, generated, chain)
        expect(data).to.equal(false)
        expect(authored).to.beTrue()
        local curated = { authored = true }
        expect(map._ResolveModeData({ snd = curated }, generated, chain)).to.equal(curated)
        expect(map._ResolveModeData({}, generated, chain)).to.equal(generated.snd)
    end },
    { name = "SND auto: exactly two deterministic groups use names before AABB adjacency", func = function()
        local groups = must(lib().GroupTargets({ target(1000, "b"), target(0, "a"), target(128, "a") }))
        expect(#groups).to.equal(2)
        expect(groups[1][1].mins.x).to.equal(0)
        expect(#groups[1]).to.equal(2)
        expect(lib().GroupTargets({ target(0), target(256), target(1000) }) ~= nil).to.beTrue()
        expect(lib().GroupTargets({ target(0), target(257), target(1000) })).to.beNil()
        expect(lib().GroupTargets({ target(0, "a"), target(64, "b") })).to.beNil()
    end },
    { name = "SND auto: ambiguous unnamed bridges and invalid or disabled bounds fail closed", func = function()
        expect(lib().GroupTargets({ target(0, "a"), target(256), target(512, "b") })).to.beNil()
        local bad = target(0)
        bad.mins.x = 0 / 0
        expect(lib().GroupTargets({ bad, target(1000) })).to.beNil()
        local disabled = target(2000)
        disabled.disabled = true
        expect(#must(lib().GroupTargets({ target(0), target(1000), disabled }))).to.equal(2)
    end },
    { name = "SND auto: safe side pools bomb and bounded site search produce valid schema", func = function()
        local facts = input()
        facts.spawns[1][2] = { pos = Vector(-300, 0, 0), yaw = math.huge }
        facts.points = { Vector(32, 32, 0), Vector(64, 64, 0), Vector(1064, 64, 0) }
        facts.safe = function(pos) return pos.x ~= 32 end
        local data = must(lib().Derive(facts))
        expect(lib().Validate(data)).to.beTrue()
        expect(#data.spawns[1]).to.equal(1)
        expect(data.bomb).to.equal(facts.spawns[1][1].pos)
        expect(data.sites[1].id).to.equal("A")
        expect(data.sites[2].id).to.equal("B")
        expect(lib().Inside(data.sites[1], data.sites[1].approach)).to.beTrue()
    end },
    { name = "SND auto: missing safe side disconnected site and points outside real member bounds reject",
        func = function()
        local facts = input()
        facts.safe = function(pos) return pos.x >= 0 end
        expect(lib().Derive(facts)).to.beNil()
        facts = input()
        facts.mutual = function(_, pos) return pos.x ~= 1064 end
        expect(lib().Derive(facts)).to.beNil()
        facts = input()
        facts.targets = { target(0, "a"), target(500, "a"), target(1000, "b") }
        facts.points[1] = Vector(300, 64, 0)
        expect(lib().Derive(facts)).to.beNil()
    end },
    { name = "SND auto: candidate is specific to de maps and inherited by SND only", func = function()
        local mode = must(PW.Modes.Get("snd"))
        expect(PW.Call(mode, "MapCandidate", "DE_example")).to.beTrue()
        expect(PW.Call(mode, "MapCandidate", "cs_example")).to.beFalse()
        expect(PW.Call(mode, "MapCandidate", "background_de_example")).to.beFalse()
        expect(must(PW.Map).ModeFits(must(PW.Modes.Get("dom")), "de_pw_missing_data")).to.beFalse()
    end }
} }
