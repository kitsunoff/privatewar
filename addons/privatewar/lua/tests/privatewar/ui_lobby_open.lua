-- The lobby opens by itself in LOBBY (08-lobby.md d.3; docs/api/ui.md "Lobby screens"). Regression for the lobby
-- that was not open on the Deck after a test run: the client opens the root when PW_PhaseChanged reports LOBBY and
-- PW.Lobby._ShouldShow holds, so the server state the client mirrors must allow it once the earlier test groups ran
-- (the real machine back in LOBBY, the NW2 phase global LOBBY, lobby_ui and ui_kit enabled). Test hygiene for the
-- whole run is the dev reporter's job (dev/privatewar_dev/.../pw_testreport.lua): a run that leaves the real match
-- outside LOBBY counts one failure, names the phase and aborts the match back to LOBBY.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@param id string
---@return boolean
local function moduleValid(id)
    local entry = PW.Modules.Get(id)
    return entry ~= nil and entry:IsValid()
end

---@return fun(results: table[], phase?: string): string
local function summarize()
    local report = must(rawget(PW, "_DevTestReport")) --[[@as table]]
    return must(report.Summarize) --[[@as fun(results: table[], phase?: string): string]]
end

local passed, failed, skipped = { success = true }, { success = false }, { skipped = true }

return {
    groupName = "PW lobby opens in LOBBY",
    cases = {
        {
            name = "The real state lets the lobby open: LOBBY on the machine and on NW2, lobby_ui and ui_kit enabled",
            func = function()
                local phase = must(PW.Match).GetPhase()
                expect(phase).to.equal("LOBBY")
                expect(PW.Phase.GetPhase()).to.equal("LOBBY")
                expect(moduleValid("lobby_ui")).to.beTrue()
                expect(moduleValid("ui_kit")).to.beTrue()
                expect(must(PW.Lobby)._ShouldShow(PW.Phase.GetPhase(), moduleValid("lobby_ui"),
                    moduleValid("ui_kit"))).to.beTrue()
            end
        },
        {
            name = "Reporter (pure): a run that ends in LOBBY is counted as GLuaTest counted it",
            func = function()
                expect(summarize()({ passed, passed, failed, skipped }, "LOBBY"))
                    .to.equal("passed=2 failed=1 skipped=1")
                expect(summarize()({ passed }, nil)).to.equal("passed=1 failed=0 skipped=0")
            end
        },
        {
            name = "Reporter (pure): a run that leaves the match outside LOBBY counts one failure and names the phase",
            func = function()
                expect(summarize()({ passed, passed }, "LIVE")).to.equal("passed=2 failed=1 skipped=0 leaked=LIVE")
                expect(summarize()({ passed, failed }, "VOTE")).to.equal("passed=1 failed=2 skipped=0 leaked=VOTE")
            end
        }
    }
}
