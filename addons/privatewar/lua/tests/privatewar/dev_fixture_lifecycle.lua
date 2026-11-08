-- Exercise the native fixture's real cleanup callback with GLuaTest's separate case/group state contract.
-- No player is allocated: the stand-in records only the cleanup's owned Kick, never gameplay behavior.
---@param owned boolean
---@param replace fun(tbl: table, key: any): GLuaTest_Stub
---@return integer
local function cleanFixture(owned, replace)
    local fixture = include("tests/privatewar/hardpoint_bot_smoke.lua") --[[@as GLuaTest_TestGroup]]
    local groupState = {}
    if fixture.beforeAll ~= nil then fixture.beforeAll(groupState) end
    local caseState = setmetatable({}, { __index = groupState })
    local kicks = 0
    local bot = { Kick = function() kicks = kicks + 1 end }
    local valid = IsValid
    replace(_G, "IsValid").with(function(value) return value == bot or valid(value) end)
    -- These are the fields assigned by the native case after its allocation succeeds.
    caseState.bot, caseState.owned = bot, owned
    if fixture.afterEach ~= nil then fixture.afterEach(caseState) end
    if fixture.afterAll ~= nil then fixture.afterAll(groupState) end
    return kicks
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
        }
    }
}
