-- Opt-in, read-only resource observations for causal scoped GLuaTest runs. Never shipped.
-- Public hooks only: no runner patches, player removal, quota changes or altered test scheduling.
local enabled = CreateConVar("pw_test_resources", "0", nil, "Observe scoped GLuaTest player resources", 0, 1)
local key = "PW.TestResources"
local commands, phases, results = 0, 0, 0
---@type GLuaTest_TestGroup?
local previousGroup

---@param event string
local function snapshot(event)
    local players = player.GetAll()
    ---@type string[]
    local slots = {}
    for _, ply in ipairs(players) do
        slots[#slots + 1] = string.format("%d:%d:%s:%s", ply:EntIndex(), ply:UserID(),
            ply:IsBot() and "bot" or "human", ply:Nick())
    end
    ---@type string
    local phase = PW ~= nil and PW.Match ~= nil and PW.Match.GetPhase() or "?"
    print(string.format("[PW] testresources %s tick=%d now=%.3f phase=%s occupied=%d/%d"
        .. " hostcmd=%d phases=%d results=%d [%s]",
        event, engine.TickCount(), CurTime(), phase, #players, game.MaxPlayers(), commands, phases, results,
        table.concat(slots, " | ")))
end

local function removeObservers()
    hook.Remove("GLuaTest_CanRunTestCase", key)
    hook.Remove("GLuaTest_LogTestResult", key)
    hook.Remove("PlayerDisconnected", key)
    hook.Remove("StartCommand", key)
    hook.Remove("PW_PhaseChange", key)
    hook.Remove("GLuaTest_Finished", key)
end

hook.Add("GLuaTest_StartedTestRun", key, function()
    removeObservers()
    if not enabled:GetBool() then return end
    commands, phases, results, previousGroup = 0, 0, 0, nil
    snapshot("start bots.fill=" .. tostring(PW ~= nil and PW.Setting("bots.fill") or "?"))
    hook.Add("GLuaTest_CanRunTestCase", key, function(group, case)
        if previousGroup == group then return end
        previousGroup = group
        snapshot("before " .. tostring(group.groupName) .. " / " .. tostring(case.name))
    end)
    hook.Add("GLuaTest_LogTestResult", key, function() results = results + 1 end)
    hook.Add("PlayerDisconnected", key, function(ply) snapshot("disconnect " .. ply:Nick()) end)
    hook.Add("StartCommand", key, function(ply, cmd)
        if ply:IsListenServerHost() and not cmd:IsForced() then commands = commands + 1 end
    end)
    hook.Add("PW_PhaseChange", key, function() phases = phases + 1 end)
    hook.Add("GLuaTest_Finished", key, function()
        snapshot("finished")
        removeObservers()
    end)
end)
