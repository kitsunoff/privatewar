-- Exercise the native fixture's real cleanup callback with GLuaTest's separate case/group state contract.
-- No player is allocated: the stand-in records only the cleanup's owned Kick, never gameplay behavior.
---@param owned boolean
---@param replace fun(tbl: table, key: any): GLuaTest_Stub
---@param path? string
---@return integer
---@return boolean restoredMode
local function cleanFixture(owned, replace, path)
    ---@type GLuaTest_TestGroup
    local fixture = include("tests/privatewar/" .. (path or "hardpoint_bot_smoke") .. ".lua")
    local groupState = {}
    if fixture.beforeAll ~= nil then fixture.beforeAll(groupState) end
    ---@type GLuaTest_TestState
    local caseState = setmetatable({}, { __index = groupState })
    local kicks = 0
    local bot = { Kick = function() kicks = kicks + 1 end, SetTeam = function() end }
    local valid = IsValid
    replace(_G, "IsValid").with(function(value) return value == bot or valid(value) end)
    -- These are the fields assigned by the native case after its allocation succeeds.
    caseState.bot, caseState.owned = bot, owned
    caseState.probes = owned and { { bot = bot } } or {}
    local previousMode = PW.ActiveMode
    caseState.mode, caseState.originalMode, caseState.originalTeam = {}, previousMode, 1
    PW.ActiveMode = caseState.mode
    local ok, reason = pcall(function()
        if fixture.afterEach ~= nil then fixture.afterEach(caseState) end
        if fixture.afterAll ~= nil then fixture.afterAll(groupState) end
    end)
    local restored = PW.ActiveMode == previousMode
    PW.ActiveMode = previousMode -- A failing cleanup contract must not leak this test's own stand-in mode.
    assert(ok, reason)
    return kicks, restored
end

return {
    groupName = "PW native fixture lifecycle",
    cases = {
        {
            name = "Hardpoint fixture: case-owned bot is kicked by its actual cleanup despite separate group state",
            func = function()
                expect(cleanFixture(true, stub)).to.equal(1)
            end
        },
        {
            name = "Hardpoint fixture: cleanup never kicks an unowned player",
            func = function()
                expect(cleanFixture(false, stub)).to.equal(0)
            end
        },
        {
            name = "Hardpoint fixture: failed setup restores the prior active mode from case state",
            func = function()
                local _, restored = cleanFixture(true, stub)
                expect(restored).to.beTrue()
            end
        },
        {
            name = "Hardpoint team fixture: case-owned probes reach actual cleanup despite separate group state",
            func = function()
                expect(cleanFixture(true, stub, "hardpoint_team_smoke")).to.equal(1)
            end
        },
        {
            name = "Hardpoint team fixture: empty ownership never kicks an unrelated player",
            func = function()
                expect(cleanFixture(false, stub, "hardpoint_team_smoke")).to.equal(0)
            end
        },
        {
            name = "Hardpoint team fixture: failed setup restores the prior active mode from case state",
            func = function()
                local _, restored = cleanFixture(true, stub, "hardpoint_team_smoke")
                expect(restored).to.beTrue()
            end
        }
    }
}
