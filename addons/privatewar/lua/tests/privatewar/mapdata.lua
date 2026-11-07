-- T-2.7 map data (TASKS.md, "Mandatory test cases" T-2.7; 03-mapdata.md d.2, d.3, d.6; docs/api/map.md).
-- Pure cases run over plain data: the entity class -> team mapping (CS:S, HL2DM, TF2, generic starts), grouping,
-- the map id rule, the spawn layers and the Base chain walk. GetModeData runs against test registries swapped in
-- for PW.Modes and PW.Maps. In-game cases read the real spawn entities of the loaded map (gm_construct in the test
-- run) and create one temporary info_player_teamspawn; afterEach restores the registries and removes the entity.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.MapLib
local function lib()
    return must(PW.Map)
end

---@param class string
---@param teamNum? integer
---@return PW.SpawnRecord
local function record(class, teamNum)
    return { class = class, pos = Vector(1, 2, 3), yaw = 90, teamNum = teamNum }
end

---@param spawns PW.MapSpawns
---@param team integer
---@return integer
local function count(spawns, team)
    local list = spawns[team]
    if list == nil then return 0 end
    return #list
end

---A test registry of the given kind; afterEach releases it.
---@param state table<string, any>
---@param kind string
---@return PW.Registry
local function registry(state, kind)
    local reg = PW.Registry.New(kind, { log = function() end })
    local list = state.registries --[[@as PW.Registry[] ]]
    list[#list + 1] = reg
    return reg
end

---Swaps PW.Modes and PW.Maps for test registries: modes dom, hardcore_dom (Base dom), tdm; one map entry for the
---current map with modes. afterEach puts the real ones back.
---@param state table<string, any>
---@param modes table<string, any>
---@return PW.Registry maps
local function useTestRegistries(state, modes)
    local modeReg = registry(state, "modes")
    modeReg.Register({ Name = "Domination", Teams = 2 }, "dom")
    modeReg.Register({ Base = "dom", Name = "Hardcore Domination" }, "hardcore_dom")
    modeReg.Register({ Base = "hardcore_dom", Name = "Hardcore Domination Night" }, "hardcore_dom_night")
    modeReg.Register({ Name = "TDM", Teams = 2 }, "tdm")
    modeReg.ResolveAll()
    local mapReg = registry(state, "maps")
    mapReg.Register({ Modes = modes }, lib().Id(game.GetMap()))
    mapReg.ResolveAll()
    rawset(PW, "Modes", modeReg)
    rawset(PW, "Maps", mapReg)
    return mapReg
end

---Loads lua/privatewar_fixtures/examples/ with only the gamemode's real maps kind declared (its kinds/ and
---modules/ folders are hidden), so the example map file registers against the real declaration. afterEach
---releases the registries. Kept here, not in kind_examples.lua, so map lane changes never touch that shared file.
---@param state table<string, any>
---@return PW.LoadContext
local function loadMapsExample(state)
    local engine = PW.Loader._EngineFs
    local root = "privatewar_fixtures/examples"
    local kindFile = root .. "/kinds/maps.lua"
    local context = PW.Loader.LoadRoot(root, {
        log = function() end,
        fs = {
            find = function(pattern)
                if pattern == root .. "/kinds/*" then return { "maps.lua" }, {} end
                if pattern == root .. "/modules/*" then return {}, {} end
                return engine.find(pattern)
            end,
            exists = function(path) return path == kindFile or engine.exists(path) end,
            run = function(path) return engine.run(path == kindFile and "privatewar/kinds/maps.lua" or path) end,
            send = function() end
        }
    })
    local list = state.registries --[[@as PW.Registry[] ]]
    for _, reg in pairs(context.registries) do list[#list + 1] = reg end
    return context
end

return {
    groupName = "PW map data",
    beforeEach = function(state)
        state.registries = {}
        state.modes = rawget(PW, "Modes")
        state.maps = rawget(PW, "Maps")
    end,
    afterEach = function(state)
        rawset(PW, "Modes", state.modes)
        rawset(PW, "Maps", state.maps)
        for _, reg in ipairs(state.registries --[[@as PW.Registry[] ]]) do reg._Release() end
        local ent = state.entity --[[@as Entity?]]
        if ent ~= nil and IsValid(ent) then ent:Remove() end
    end,
    cases = {
        {
            name = "maps: the example map data registers against the real maps kind (T-2.7)",
            func = function(state)
                local context = loadMapsExample(state)
                local map = must(must(context.registries.maps).Get("example_map")) --[[@as PW.MapEntry]]
                expect(must(must(must(map.Spawns)[1])[1]).yaw).to.equal(90)
                expect(must(must(map.Modes).dom).flags.B).to.equal(Vector(500, 0, 0))
            end
        },
        {
            name = "CS:S: info_player_terrorist is team 1, info_player_counterterrorist is team 2",
            func = function()
                expect(lib()._SpawnTeam("info_player_terrorist")).to.equal(1)
                expect(lib()._SpawnTeam("info_player_counterterrorist")).to.equal(2)
            end
        },
        {
            name = "HL2DM: info_player_combine is team 1, info_player_rebel team 2, info_player_deathmatch any team",
            func = function()
                expect(lib()._SpawnTeam("info_player_combine")).to.equal(1)
                expect(lib()._SpawnTeam("info_player_rebel")).to.equal(2)
                expect(lib()._SpawnTeam("info_player_deathmatch")).to.equal(lib().AnyTeam)
                expect(lib().AnyTeam).to.equal(0)
            end
        },
        {
            name = "TF2: info_player_teamspawn TeamNum 2 (RED) is team 1, 3 (BLU) team 2, anything else any team",
            func = function()
                expect(lib()._SpawnTeam("info_player_teamspawn", 2)).to.equal(1)
                expect(lib()._SpawnTeam("info_player_teamspawn", 3)).to.equal(2)
                expect(lib()._SpawnTeam("info_player_teamspawn", 0)).to.equal(0)
                expect(lib()._SpawnTeam("info_player_teamspawn", 1)).to.equal(0)
                expect(lib()._SpawnTeam("info_player_teamspawn", 7)).to.equal(0)
                expect(lib()._SpawnTeam("info_player_teamspawn")).to.equal(0)
            end
        },
        {
            name = "Generic starts (info_player_start, gmod_player_start) are any team and generic; others are not",
            func = function()
                local team, generic = lib()._SpawnTeam("info_player_start")
                expect(team).to.equal(0)
                expect(generic).to.beTrue()
                team, generic = lib()._SpawnTeam("gmod_player_start")
                expect(team).to.equal(0)
                expect(generic).to.beTrue()
                local _, csGeneric = lib()._SpawnTeam("info_player_terrorist")
                expect(csGeneric).to.beFalse()
            end
        },
        {
            name = "A class that is not a spawn class maps to no team",
            func = function()
                expect(lib()._SpawnTeam("prop_physics")).to.beNil()
                expect(lib()._SpawnTeam("info_player_teamspawn_x")).to.beNil()
            end
        },
        {
            name = "Grouping: team spawns by team; generic starts dropped when other spawn classes exist",
            func = function()
                local spawns = lib()._GroupSpawns({
                    record("info_player_terrorist"), record("info_player_terrorist"),
                    record("info_player_counterterrorist"), record("info_player_start"), record("prop_physics")
                })
                expect(count(spawns, 1)).to.equal(2)
                expect(count(spawns, 2)).to.equal(1)
                expect(count(spawns, 0)).to.equal(0)
                local point = must(must(spawns[1])[1])
                expect(point.pos).to.equal(Vector(1, 2, 3))
                expect(point.yaw).to.equal(90)
            end
        },
        {
            name = "Grouping: a map with generic starts only gets them as any-team spawns",
            func = function()
                local spawns = lib()._GroupSpawns({ record("info_player_start"), record("gmod_player_start") })
                expect(count(spawns, 0)).to.equal(2)
                expect(lib()._GroupSpawns({ record("info_player_deathmatch"), record("info_player_start") })[0])
                    .to.exist()
                expect(count(lib()._GroupSpawns({ record("info_player_deathmatch"), record("info_player_start") }), 0))
                    .to.equal(1)
            end
        },
        {
            name = "Map data file id: lowercase, characters outside [a-z0-9_] become _",
            func = function()
                expect(lib().Id("de_dust2")).to.equal("de_dust2")
                expect(lib().Id("cs-office.v2")).to.equal("cs_office_v2")
                expect(lib().Id("GM_Construct")).to.equal("gm_construct")
                expect(lib().Id("de dust (b)")).to.equal("de_dust__b_")
            end
        },
        {
            name = "Spawn layers: valid map file spawns replace the detected ones; empty or invalid fall back",
            func = function()
                local detected = lib()._GroupSpawns({ record("info_player_start") })
                local file = { [1] = { { pos = Vector(5, 5, 5), yaw = 180 } }, [2] = { { pos = Vector(6, 6, 6) } } }
                local layered = lib()._Layer(file, detected)
                expect(count(layered, 1)).to.equal(1)
                expect(count(layered, 2)).to.equal(1)
                expect(count(layered, 0)).to.equal(0)
                expect(must(must(layered[2])[1]).yaw).to.equal(0)
                expect(lib()._Layer(nil, detected)).to.equal(detected)
                expect(lib()._Layer({}, detected)).to.equal(detected)
                expect(lib()._Layer({ [1] = { { pos = "x" } }, x = {} }, detected)).to.equal(detected)
            end
        },
        {
            name = "Base chain (pure): the mode id, then each resolved BaseClass; a mode without a table is its id",
            func = function()
                local dom = { ClassName = "dom" }
                local hardcore = { ClassName = "hardcore_dom", BaseClass = dom }
                expect(lib()._ModeChain(hardcore, "hardcore_dom")).to.deepEqual({ "hardcore_dom", "dom" })
                expect(lib()._ModeChain(nil, "custom")).to.deepEqual({ "custom" })
                local domData = { flags = 1 }
                expect(lib()._FindModeData({ dom = domData }, { "hardcore_dom", "dom" })).to.equal(domData)
                expect(lib()._FindModeData({ dom = "bad" }, { "hardcore_dom", "dom" })).to.beNil()
                expect(lib()._FindModeData(nil, { "dom" })).to.beNil()
            end
        },
        {
            name = "GetModeData walks the Base chain: hardcore_dom without an entry gets MAP.Modes.dom",
            func = function(state)
                local domData = { flags = { A = Vector(1, 0, 0), B = Vector(2, 0, 0) } }
                useTestRegistries(state, { dom = domData })
                expect(lib().GetModeData("dom")).to.equal(domData)
                expect(lib().GetModeData("hardcore_dom")).to.equal(domData)
                expect(lib().GetModeData("hardcore_dom_night")).to.equal(domData)
                expect(lib().GetModeData("tdm")).to.beNil()
                expect(lib().GetModeData("unknown")).to.beNil()
            end
        },
        {
            name = "GetModeData: the mode's own entry wins over its base's",
            func = function(state)
                local own = { flags = { A = Vector(9, 0, 0) } }
                useTestRegistries(state, { dom = { flags = {} }, hardcore_dom = own })
                expect(lib().GetModeData("hardcore_dom")).to.equal(own)
                expect(lib().GetModeData("hardcore_dom_night")).to.equal(own)
            end
        },
        {
            name = "GetModeData: nil without a map data file or when the map entry is disabled",
            func = function(state)
                local maps = useTestRegistries(state, { dom = { flags = {} } })
                local id = lib().Id(game.GetMap())
                expect(lib().Get()).to.exist()
                maps._Disable(id, "test")
                expect(lib().Get()).to.beNil()
                expect(lib().GetModeData("dom")).to.beNil()
                rawset(PW, "Maps", registry(state, "maps"))
                expect(lib().GetModeData("dom")).to.beNil()
                rawset(PW, "Maps", nil)
                expect(lib().GetModeData("dom")).to.beNil()
            end
        },
        {
            name = "In-game: on gm_construct the detector finds the info_player_start points",
            func = function()
                local detected = must(lib()._Detect)()
                local starts = #ents.FindByClass("info_player_start")
                if game.GetMap() == "gm_construct" then expect(starts >= 1).to.beTrue() end
                expect(count(detected, 0)).to.equal(starts)
                expect(count(must(lib().GetSpawns)(), 0)).to.equal(starts)
            end
        },
        {
            name = "In-game: the spawn cache is filled at map load (InitPostEntity)",
            func = function()
                expect(PW._Map.detected).to.exist()
                expect(PW._Map.reason).to.equal("InitPostEntity")
                expect(must(lib().GetDetectedSpawns)()).to.equal(PW._Map.detected)
            end
        },
        {
            name = "In-game: an info_player_teamspawn with TeamNum 3 is detected as team 2",
            func = function(state)
                local ent = ents.Create("info_player_teamspawn")
                state.entity = ent
                ent:SetKeyValue("TeamNum", "3")
                ent:SetPos(Vector(10, 20, 30))
                ent:SetAngles(Angle(0, 45, 0))
                ent:Spawn()
                local spawns = must(lib()._Detect)()
                local list = must(spawns[2])
                expect(#list).to.equal(1)
                expect(must(list[1]).pos).to.equal(Vector(10, 20, 30))
                expect(math.Round(must(list[1]).yaw)).to.equal(45)
                expect(count(spawns, 0)).to.equal(0)
            end
        }
    }
}
