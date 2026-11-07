-- T-2.11 map list (TASKS.md, "Mandatory test cases" T-2.11; 03-mapdata.md d.9; docs/api/map.md "Map list").
-- Pure cases run over plain lists of map names and set values. The settings are read through PW.Setting in the
-- last cases (defaults of the module's settings); the file.Find wrapper is covered by one in-game smoke case.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.MapListLib
local function lib()
    return must(PW.MapList)
end

---@param installed string[]
---@param over? table
---@return string[]
local function filter(installed, over)
    over = over or {}
    return lib().Filter({
        installed = installed,
        data = over.data or {},
        prefixes = over.prefixes or {},
        whitelist = over.whitelist or {}
    })
end

return {
    groupName = "PW map list",
    cases = {
        {
            name = "the list is the union of data maps, prefixes and whitelist",
            func = function()
                local installed = { "gm_construct", "de_dust2", "my_arena", "rp_town", "cs_office", "gm_flatgrass" }
                local list = filter(installed, {
                    data = { my_arena = true },
                    prefixes = { "de_", "cs_" },
                    whitelist = { "gm_construct" }
                })
                expect(list).to.deepEqual({ "cs_office", "de_dust2", "gm_construct", "my_arena" })
            end
        },
        {
            name = "union: each source alone adds its maps; a map in two sources is listed once",
            func = function()
                local installed = { "a_one", "de_two", "b_three" }
                expect(filter(installed, { data = { a_one = true } })).to.deepEqual({ "a_one" })
                expect(filter(installed, { prefixes = { "de_" } })).to.deepEqual({ "de_two" })
                expect(filter(installed, { whitelist = { "b_three" } })).to.deepEqual({ "b_three" })
                expect(filter(installed, { data = { de_two = true }, prefixes = { "de_" }, whitelist = { "de_two" } }))
                    .to.deepEqual({ "de_two" })
            end
        },
        {
            name = "sources accept lists and lookups; maps that are not installed are not listed",
            func = function()
                local installed = { "de_dust2" }
                expect(filter(installed, { prefixes = { de_ = true }, whitelist = { "gm_missing" } }))
                    .to.deepEqual({ "de_dust2" })
                expect(filter(installed, { data = { missing_map = true } })).to.deepEqual({})
                expect(filter({}, { prefixes = { "de_" } })).to.deepEqual({})
            end
        },
        {
            name = "junk patterns are always excluded, even whitelisted, prefixed or with a data file",
            func = function()
                local junk = { "background01", "d1_trainstation_01", "d2_coast_03", "d3_citadel_02", "ep1_c17_00",
                    "ep2_outland_01", "credits", "test_hardware", "intro" }
                local ok = filter(junk, {
                    data = { d1_trainstation_01 = true, ep1_c17_00 = true },
                    prefixes = { "background", "d2_", "d3_", "test_", "ep2_" },
                    whitelist = junk
                })
                expect(ok).to.deepEqual({})
                expect(lib().IsJunk("BACKGROUND05")).to.beTrue()
                expect(lib().IsJunk("de_dust2")).to.beFalse()
                expect(lib().IsJunk("gm_construct")).to.beFalse()
            end
        },
        {
            name = "junk matches whole prefixes: d1_ is junk, d10_ and a map named like a junk word inside is not",
            func = function()
                expect(lib().IsJunk("d1_town")).to.beTrue()
                expect(lib().IsJunk("ep2_a")).to.beTrue()
                expect(lib().IsJunk("ep3_a")).to.beFalse()
                expect(lib().IsJunk("de_background")).to.beFalse()
                expect(lib().IsJunk("de_test_arena")).to.beFalse()
            end
        },
        {
            name = "names are matched case-insensitively and listed in their installed spelling",
            func = function()
                expect(filter({ "DE_Dust2", "DM_Lockdown" }, { prefixes = { "de_" }, whitelist = { "dm_lockdown" } }))
                    .to.deepEqual({ "DE_Dust2", "DM_Lockdown" })
                expect(filter({ "My-Arena.v2" }, { data = { my_arena_v2 = true } })).to.deepEqual({ "My-Arena.v2" })
            end
        },
        {
            name = "empty prefixes in the setting match nothing",
            func = function()
                expect(filter({ "de_dust2", "x" }, { prefixes = { "" } })).to.deepEqual({})
            end
        },
        {
            name = "file listing: names without .bsp, unique and sorted, other files ignored",
            func = function()
                expect(lib()._NamesFromFiles({ "b.bsp", "a.bsp", "a.bsp", "c.nav", "d.bsp.bz2", ".bsp" }))
                    .to.deepEqual({ "a", "b" })
            end
        },
        {
            name = "settings: server-scope set settings with the documented defaults",
            func = function()
                local prefixes = PW.Setting("maplist.prefixes") --[[@as table<string, true>]]
                for _, prefix in ipairs(lib().DefaultPrefixes) do expect(prefixes[prefix]).to.beTrue() end
                expect(prefixes.de_).to.beTrue()
                expect(prefixes.cs_).to.beTrue()
                expect(prefixes.dm_).to.beTrue()
                expect(PW.Setting("maplist.whitelist")).to.deepEqual({})
                ---@type table<string, true>
                local owners = {}
                for _, group in ipairs(PW.Settings.GetGroups("server")) do owners[group.owner] = true end
                expect(owners.maplist).to.beTrue()
            end
        },
        {
            name = "engine: GetList is a subset of GetInstalled, junk-free; the current map is installed",
            func = function()
                local installed = must(lib()._Installed)()
                local all = must(lib().GetInstalled)()
                local list = must(lib().GetList)()
                ---@type table<string, true>
                local lookup = {}
                for _, name in ipairs(all) do lookup[name] = true end
                for _, name in ipairs(list) do
                    expect(lookup[name]).to.beTrue()
                    expect(lib().IsJunk(name)).to.beFalse()
                end
                expect(#all <= #installed).to.beTrue()
                local current = game.GetMap()
                expect(table.HasValue(installed, current)).to.beTrue()
            end
        }
    }
}
