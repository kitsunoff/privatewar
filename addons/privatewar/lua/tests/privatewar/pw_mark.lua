-- T-2.10 pw_mark (TASKS.md, "Mandatory test cases" T-2.10; 03-mapdata.md d.2, d.5; docs/api/map.md "pw_mark").
-- Pure cases: the formatter, the parser and the round trip into map-data entries (spawn through PW.Map._CleanSpawns,
-- dom flags through dom ValidateMapData). The privilege case runs the command logic with one pool bot whose usergroup
-- is switched between calls; the output goes to a capturing sink, never to a console.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.MapMarkLib
local function lib()
    return must(PW.MapMark)
end

---@param state table<string, any>
---@param group string
---@return Player
local function bot(state, group)
    local pool = state.pool --[[@as table<string, Player>]]
    local ply = pool.bot
    if ply == nil or not IsValid(ply) then
        ply = player.CreateNextBot("PW mark test")
        assert(IsValid(ply), "could not create a bot: needs a listen server with free slots")
        pool.bot = ply
    end
    ply:SetUserGroup(group)
    return ply
end

---@param line string
---@return PW.MapMarkEntry
local function parsed(line)
    local entry, reason = lib().Parse(line)
    assert(entry ~= nil, "line did not parse: " .. tostring(reason) .. ": " .. line)
    return entry
end

return {
    groupName = "PW pw_mark",
    beforeAll = function(state)
        state.pool = {}
    end,
    afterAll = function(state)
        local ply = (state.pool --[[@as table<string, Player>]]).bot
        if ply ~= nil and IsValid(ply) then ply:Kick("PW pw_mark test finished") end
    end,
    cases = {
        {
            name = "the spawn line is one Lua entry and parses back into a valid map-data spawn",
            func = function()
                local line = lib().Format("spawn", Vector(100.5, -200, 64.25), 90)
                expect(line).to.equal("{ pos = Vector(100.5, -200, 64.25), yaw = 90 }")
                local entry = parsed(line)
                expect(entry.kind).to.equal("spawn")
                expect(entry.pos).to.equal(Vector(100.5, -200, 64.25))
                expect(entry.yaw).to.equal(90)
                local spawns, total = must(PW.Map)._CleanSpawns({ [1] = { { pos = entry.pos, yaw = entry.yaw } } })
                expect(total).to.equal(1)
                expect(spawns[1][1].pos).to.equal(Vector(100.5, -200, 64.25))
                expect(spawns[1][1].yaw).to.equal(90)
            end
        },
        {
            name = "the dom line is a bare Vector, and two parsed flags pass the dom ValidateMapData",
            func = function()
                local a = lib().Format("dom", Vector(1, 2, 3), 45)
                expect(a).to.equal("Vector(1, 2, 3)")
                local b = lib().Format("dom", Vector(-10.5, 20, 0), 270)
                local one = parsed(a)
                local two = parsed(b)
                expect(one.kind).to.equal("dom")
                local mode = must(PW.Modes.Get("dom")) --[[@as PW.DomMode]]
                expect(mode:ValidateMapData({ flags = { A = one.pos } })).to.beFalse()
                local ok, reason = mode:ValidateMapData({ flags = { A = one.pos, B = two.pos } })
                expect(ok).to.beTrue()
                expect(reason).to.beNil()
                expect(two.pos).to.equal(Vector(-10.5, 20, 0))
            end
        },
        {
            name = "numbers are rounded to two decimals, the yaw is normalised, nothing prints in exponent form",
            func = function()
                local line = lib().Format("spawn", Vector(1 / 3, 1e-9, 12345.678), 450.04)
                expect(line).to.equal("{ pos = Vector(0.33, 0, 12345.68), yaw = 90 }")
                expect(lib().Format("spawn", Vector(0, 0, 0), -90)).to.equal("{ pos = Vector(0, 0, 0), yaw = -90 }")
                expect(lib().Format("spawn", Vector(0, 0, 0), 180)).to.equal("{ pos = Vector(0, 0, 0), yaw = -180 }")
            end
        },
        {
            name = "the parser rejects text that is not a pw_mark line",
            func = function()
                expect(lib().Parse("")).to.beNil()
                expect(lib().Parse("Vector(1, 2)")).to.beNil()
                expect(lib().Parse("{ pos = Vector(1, 2, 3) }")).to.beNil()
                expect(lib().Parse("os.exit()")).to.beNil()
                expect(lib().Parse("{ pos = Vector(1, 2, x), yaw = 1 }")).to.beNil()
            end
        },
        {
            name = "arguments: spawn takes an optional team, dom needs a letter, anything else is refused",
            func = function()
                local spawn = must(lib().ParseArgs({ "spawn" }))
                expect(spawn.kind).to.equal("spawn")
                expect(spawn.team).to.equal(1)
                expect(must(lib().ParseArgs({ "spawn", "2" })).team).to.equal(2)
                expect(must(lib().ParseArgs({ "dom", "b" })).letter).to.equal("B")
                expect(lib().ParseArgs({ "dom" })).to.beNil()
                expect(lib().ParseArgs({ "dom", "AB" })).to.beNil()
                expect(lib().ParseArgs({ "spawn", "x" })).to.beNil()
                expect(lib().ParseArgs({ "spawn", "-1" })).to.beNil()
                expect(lib().ParseArgs({ "nope" })).to.beNil()
                expect(lib().ParseArgs({})).to.beNil()
                expect(must(lib().ParseArgs({ "header" })).kind).to.equal("header")
            end
        },
        {
            name = "the output names the target slot above the line; the header names the file and MAP.Name",
            func = function()
                local out = must(lib()._Build({ kind = "spawn", team = 2 }, Vector(1, 2, 3), 10, "de_dust2"))
                expect(out[1]).to.equal("-- MAP.Spawns[2]")
                expect(out[2]).to.equal("{ pos = Vector(1, 2, 3), yaw = 10 }")
                local flag = must(lib()._Build({ kind = "dom", letter = "C" }, Vector(1, 2, 3), 10, "de_dust2"))
                expect(flag[1]).to.equal("-- MAP.Modes.dom.flags.C")
                expect(flag[2]).to.equal("Vector(1, 2, 3)")
                local header = must(lib()._Build({ kind = "header" }, Vector(0, 0, 0), 0, "Cs-Office.v2"))
                expect(header[1]).to.equal("-- lua/privatewar/maps/cs_office_v2.lua")
                expect(header[2]).to.equal("MAP.Name = \"Cs-Office.v2\"")
            end
        },
        {
            name = "the command requires the privilege: a bot without it is refused and prints nothing",
            func = function(state)
                ---@type string[]
                local lines = {}
                local function sink(_, line) lines[#lines + 1] = line end
                local user = bot(state, "user")
                expect(lib()._Command(user, { "spawn", "1" }, sink)).to.beFalse()
                expect(#lines).to.equal(0)
                local admin = bot(state, "superadmin")
                expect(lib()._Command(admin, { "spawn", "1" }, sink)).to.beTrue()
                expect(#lines).to.equal(2)
                local entry = parsed(lines[2])
                expect(entry.kind).to.equal("spawn")
                expect(lib().Privilege).to.equal("pw.map.mark")
            end
        },
        {
            name = "the shipped gm_construct data passes dom ValidateMapData and Domination fits the map",
            func = function()
                local mode = must(PW.Modes.Get("dom")) --[[@as PW.DomMode]]
                local entry = must(must(PW.Maps).Get("gm_construct")) --[[@as PW.MapEntry]]
                local data = must(must(entry.Modes).dom)
                expect(mode:ValidateMapData(data)).to.beTrue()
                expect(must(PW.Map).ModeFits(mode, "gm_construct")).to.beTrue()
            end
        },
        {
            name = "the server console has no position and is refused; a bad subcommand prints usage",
            func = function(state)
                ---@type string[]
                local lines = {}
                local function sink(_, line) lines[#lines + 1] = line end
                expect(lib()._Command(nil, { "spawn" }, sink)).to.beFalse()
                local admin = bot(state, "superadmin")
                expect(lib()._Command(admin, { "bogus" }, sink)).to.beFalse()
                expect(#lines).to.equal(1)
                expect(string.find(lines[1], "usage", 1, true) ~= nil).to.beTrue()
            end
        }
    }
}
