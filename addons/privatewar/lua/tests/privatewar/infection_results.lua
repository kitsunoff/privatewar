-- Authoritative terminal metadata has no engine entities/SteamIDs/positions and no dependency on live score/kills.
local listener = "PW.InfectionResultsTest"

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "installed Infection terminal integration is missing")
    return value
end

---@return boolean
local function absent() return not file.Exists("privatewar/types/pw_infection.lua", "LUA") end

---@param revision integer
---@param offset integer
---@param id integer
---@return PW.InfectionResultChunk
local function chunk(revision, offset, id)
    return { revision = revision, active = true, ownId = 7, total = 2, offset = offset,
        rows = { { id = id, name = "Player " .. id, wins = id == 7 and 0 or 1, infections = 0,
            kills = 0, deaths = 1, bot = id ~= 7 } } }
end

return {
    groupName = "PW Infection terminal snapshot integration",
    beforeEach = function(state)
        state.terminal = PW.Infection ~= nil and PW.Infection.Terminal or nil
    end,
    afterEach = function(state)
        hook.Remove("PW_PostmatchGathered", listener)
        if PW.Infection ~= nil then PW.Infection.Terminal = state.terminal end
    end,
    cases = {
        {
            name = "Infection results: only complete same-generation chunks publish;"
                .. " stale gaps duplicate ids fail closed",
            skip = absent,
            func = function()
                local lib = must(PW.InfectionPresentation)
                local assembly, terminal = lib.ResultChunk(nil, chunk(2, 0, 7))
                expect(assembly).to.exist()
                expect(terminal).to.beNil()
                expect(lib.ResultChunk(assembly, chunk(1, 1, 8))).to.beNil()
                expect(lib.ResultChunk(assembly, chunk(2, 1, 7))).to.beNil()
                expect(lib.ResultChunk(assembly, chunk(3, 1, 8))).to.beNil()
                local fresh, complete = lib.ResultChunk(assembly, chunk(2, 1, 8))
                expect(fresh).to.exist()
                expect(#must(complete).rows).to.equal(2)
                expect(must(complete).ownId).to.equal(7)
                expect(lib.ResultChunk(fresh, chunk(2, 1, 8))).to.beNil()
                local _, cleared = lib.ResultChunk(fresh,
                    { revision = 3, active = false, ownId = 0, rows = {} })
                expect(must(cleared).active).to.beFalse()
            end
        },
        {
            name = "Infection results wire: bounded codec preserves departed metadata"
                .. " and never serializes hidden fields",
            skip = absent,
            func = function()
                local lib = must(PW.InfectionPresentation)
                ---@type any[]
                local queue = {}
                local index = 0
                local writer = { uint = function(value) queue[#queue + 1] = value end,
                    bool = function(value) queue[#queue + 1] = value end,
                    string = function(value) queue[#queue + 1] = value end, float = function() error("no float") end }
                local function take() index = index + 1 return queue[index] end
                local reader = { uint = take, bool = take, string = take, float = take }
                local input = chunk(1, 0, 7)
                input.total = 1
                rawset(input.rows[1], "secret", Vector(1, 2, 3))
                expect(lib.EncodeResults(writer, input)).to.beTrue()
                local _, terminal = lib.ResultChunk(nil, lib.DecodeResults(reader))
                expect(#must(terminal).rows).to.equal(1)
                expect(rawget(must(terminal).rows[1], "secret")).to.beNil()
                queue, index = {}, 0
                input.rows[1].name = string.rep("x", 257)
                expect(lib.EncodeResults(writer, input)).to.beFalse()
                expect(#queue).to.equal(0)
            end
        },
        {
            name = "Infection postmatch: authoritative snapshot replaces kills ordering and includes departed rows",
            skip = absent,
            func = function()
                local lib = must(PW.InfectionPresentation)
                local pm = must(must(PW.UI).Postmatch)
                ---@type PW.UIPostmatchData
                local data = { result = pm.Result({ draw = false, winner = 7, teams = 0, ownTeam = 1, ownId = 7 }),
                    sections = {}, progression = false, steps = {}, medals = {}, weapons = {}, map = "fixture" }
                local terminal = { revision = 1, active = true, ownId = 7, rows = {
                    { id = 7, name = "Host", wins = 0, kills = 99, deaths = 0, infections = 99 },
                    { id = 8, name = "Departed seed", wins = 2, kills = 0, deaths = 0, bot = true } } }
                lib.ApplyPostmatch(data, terminal, 700) -- reconnect's current id cannot replace authoritative ownId
                expect(data.result.title).to.equal("DEFEAT")
                expect(data.result.placement).to.equal(2)
                expect(data.result.subtitle).to.equal("2ND OF 2")
                expect(data.scoreLabel).to.equal("ROUND WINS")
                expect(data.sections[1].rows[1].id).to.equal(8)
                expect(data.sections[1].rows[1].score).to.equal(2)
                expect(data.sections[1].rows[2].me).to.beTrue()
                expect(data.sections[1].rows[2].kills).to.equal(99)
                terminal.rows[1].wins = 2
                lib.ApplyPostmatch(data, terminal, 700)
                expect(data.result.title).to.equal("DRAW")
                expect(data.result.placement).to.equal(1)
                terminal.ownId = 0 -- genuinely new late viewer, not an admitted participant
                lib.ApplyPostmatch(data, terminal, 7)
                expect(data.result.title).to.equal("MATCH OVER")
                expect(data.result.placement).to.beNil()
            end
        },
        {
            name = "Infection postmatch hook: missing inactive or disabled owner leaves ordinary data unchanged",
            skip = absent,
            func = function()
                local lib, owner = must(PW.Infection), must(PW.Modules.Get("pw_infection_rules"))
                local data = { result = {}, sections = {} }
                stub(PW.Phase, "GetPhase").with(function() return "POSTMATCH" end)
                stub(_G, "GetGlobal2Bool").with(function() return true end)
                lib.Terminal = nil
                PW.Notify("PW_PostmatchGathered", data, 7)
                expect(data.result).to.deepEqual({})
                lib.Terminal = { revision = 1, active = false, ownId = 0, rows = {} }
                PW.Notify("PW_PostmatchGathered", data, 7)
                expect(data.result).to.deepEqual({})
                lib.Terminal = { revision = 2, active = true, ownId = 7,
                    rows = { { id = 7, name = "Host", wins = 1 } } }
                PW.Notify("PW_PostmatchGathered", data, 7)
                expect(data.result.title).to.equal("VICTORY")
                local reason = PW.Modules._DisabledReason(owner.ClassName)
                PW.Modules._Disable(owner.ClassName, "terminal fixture")
                local ok, err = pcall(function()
                    data.result = {}
                    PW.Notify("PW_PostmatchGathered", data, 7)
                    expect(data.result).to.deepEqual({})
                end)
                if reason ~= nil then PW.Modules._Disable(owner.ClassName, reason)
                else PW.Modules._Enable(owner.ClassName) end
                if not ok then error(err) end
            end
        }
    }
}
