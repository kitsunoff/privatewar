-- Dev-only GLuaTest reporter for scripts/deck/test.sh: writes a one-line summary of every test run to
-- data/privatewar_dev/test_result.txt and prints it with the [PW] tag. Never shipped to the Workshop.
-- Test hygiene: every test that starts a real match must end it. A run that leaves the real machine outside LOBBY
-- counts one more failure ("leaked=<phase>") and the match is aborted back to LOBBY, so the lobby opens again and
-- the next screenshot or checkpoint starts from LOBBY. The pure summary is PW._DevTestReport.Summarize (tested in
-- lua/tests/privatewar/ui_lobby_open.lua).

---@type string
local resultFile = "privatewar_dev/test_result.txt"

---Counts results by outcome; a phase other than LOBBY after the run is one more failure.
---@param results { success?: boolean, skipped?: boolean }[]
---@param phase? string the real phase after the run, nil without the gamemode
---@return string summary "passed=N failed=N skipped=N" plus " leaked=<phase>" when the run left a match running
local function summarize(results, phase)
    ---@type table<"passed"|"failed"|"skipped", integer>
    local counts = { passed = 0, failed = 0, skipped = 0 }
    for _, result in ipairs(results) do
        ---@type "passed"|"failed"|"skipped"
        local outcome = result.skipped and "skipped" or (result.success and "passed" or "failed")
        counts[outcome] = counts[outcome] + 1
    end
    local leaked = phase ~= nil and phase ~= "LOBBY"
    if leaked then counts.failed = counts.failed + 1 end
    local summary = string.format("passed=%d failed=%d skipped=%d", counts.passed, counts.failed, counts.skipped)
    if leaked then summary = summary .. " leaked=" .. phase end
    return summary
end

---The real phase after the run; a match a test left running is aborted back to LOBBY.
---@return string?
local function settlePhase()
    local match = PW ~= nil and rawget(PW, "Match") or nil --[[@as PW.MatchLib?]]
    if match == nil then return nil end
    local phase = match.GetPhase()
    if phase ~= "LOBBY" then
        print("[PW] tests left the real match in " .. phase .. ": a test that starts a match must end it")
        match.Abort("a test left the match in " .. phase)
    end
    return phase
end

-- Autorun files run before the gamemode: PW exists from Initialize on.
hook.Add("Initialize", "PW_TestReport", function()
    if PW ~= nil then rawset(PW, "_DevTestReport", { Summarize = summarize }) end
end)

hook.Add("GLuaTest_Finished", "PW_TestReport", function(_, results)
    local summary = summarize(results, settlePhase())
    file.CreateDir("privatewar_dev")
    file.Write(resultFile, summary)
    print("[PW] tests finished: " .. summary)
end)
