-- Three real teammates, ordinary LIVE engine spawns and public board injection only.
-- This controls a subsystem scenario, not production spawn fairness or an opposing-team combat checkpoint.
local timerName, hookName = "PW.HardpointTeamSmoke", "PW.HardpointTeamInput"

---@class PW.HardpointTeamProbe
---@field bot Player
---@field board PW.BotBoard
---@field origin Vector
---@field commands integer
---@field first number
---@field second number
---@field entered? number
---@field visit integer

---@param probes PW.HardpointTeamProbe[]
---@param state PW.HardpointState
---@param now number
---@return integer
local function sample(probes, state, now)
    local completed = 0
    for _, probe in ipairs(probes) do
        local bot = probe.bot
        assert(IsValid(bot) and bot:Alive(), "a team smoke participant departed or died")
        local inside = assert(PW.Hardpoint).Inside(state.layout.zones[state.index], bot:GetPos())
        if probe.visit ~= state.visit then probe.entered, probe.visit = nil, state.visit end
        probe.entered = inside and (probe.entered or now) or nil
        local held = probe.entered ~= nil and now - probe.entered or 0
        if state.visit == 1 then probe.first = math.max(probe.first, held)
        elseif state.visit == 2 then probe.second = math.max(probe.second, held) end
        if probe.first >= 2 and probe.second >= 2 and probe.commands > 0
            and probe.origin:Distance2D(bot:GetPos()) > 64 then completed = completed + 1 end
    end
    return completed
end

return {
    groupName = "PW Hardpoint team normal-input smoke",
    afterAll = function(test)
        timer.Remove(timerName)
        hook.Remove("SetupMove", hookName)
        if test.mode ~= nil then
            assert(PW.Hardpoint).Cleanup(test.mode)
            PW.ActiveMode = test.originalMode
        end
        for _, probe in ipairs(test.probes or {} --[[@as PW.HardpointTeamProbe[] ]]) do
            if IsValid(probe.bot) then
                assert(PW.Bot).ClearGoal(probe.bot)
                probe.bot:Kick("Hardpoint team smoke complete")
            end
        end
    end,
    cases = {
        {
            name = "Hardpoint team: multiple real bots approach hold and rotate through normal CUserCmd",
            async = true,
            timeout = 75,
            func = function(test)
                assert(game.GetMap() == "gm_construct", "team smoke needs authored gm_construct")
                local hp, api = assert(PW.Hardpoint), assert(PW.Bot)
                local mode = assert(PW.Modes.Get("hardpoint")) --[[@as PW.HardpointMode]]
                test.mode, test.originalMode = mode, PW.ActiveMode
                stub(assert(PW.Match), "GetPhase").with(function() return "LIVE" end)
                PW.ActiveMode = mode
                local originalSetting, originalGet = mode.Setting, api.Get
                stub(mode, "Setting").with(function(self, key)
                    if key == "zonetime" then return 20 end
                    return originalSetting(self, key)
                end)
                stub(hp, "Send").with(function() end)
                ---@type PW.HardpointTeamProbe[]
                local probes = {}
                test.probes = probes
                stub(api, "Get").with(function(ply)
                    for _, probe in ipairs(probes) do if ply == probe.bot then return probe.board end end
                    return originalGet(ply)
                end)
                for index = 1, 3 do
                    local bot = player.CreateNextBot("PW HP teammate " .. index)
                    assert(IsValid(bot), "team smoke requires three free player slots")
                    local board = { bot = bot, team = 1, intent = { buttons = 0 } }
                    local probe = { bot = bot, board = board, origin = Vector(), commands = 0,
                        first = 0, second = 0, visit = 1 }
                    probes[#probes + 1] = probe
                    bot:SetTeam(1)
                    assert(PW.MatchRules).Spawn(bot)
                    assert(bot:Alive() and bot:GetObserverMode() == OBS_MODE_NONE, "team participant not playable")
                    probe.origin = bot:GetPos()
                end
                hp.Start(mode)
                local runtime = assert(mode._Hardpoint)
                local started, previousVisit, nextReport = CurTime(), runtime.state.visit, CurTime() + 5
                hook.Add("SetupMove", hookName, function(ply, _, cmd)
                    if math.abs(cmd:GetForwardMove()) + math.abs(cmd:GetSideMove()) == 0 then return end
                    for _, probe in ipairs(probes) do
                        if ply == probe.bot then probe.commands = probe.commands + 1 end
                    end
                end)
                timer.Create(timerName, 0.1, 0, function()
                    local ok, count = pcall(function()
                        hp.Think(mode)
                        local state = runtime.state
                        if previousVisit ~= state.visit then
                            for _, probe in ipairs(probes) do
                                local order = probe.board.order
                                assert(order == nil or order.objective.revision ~= previousVisit,
                                    "old team order survived rotation invalidation")
                            end
                            previousVisit = state.visit
                        end
                        if CurTime() >= nextReport then
                            nextReport = CurTime() + 5
                            for _, probe in ipairs(probes) do
                                print(string.format("[PW] HP_TEAM_PROGRESS %s visit %d hold %.1f/%.1f cmds %d pos %s",
                                    probe.bot:Nick(), state.visit, probe.first, probe.second, probe.commands,
                                    tostring(probe.bot:GetPos())))
                            end
                        end
                        return sample(probes, state, CurTime())
                    end)
                    if ok and count < 2 and CurTime() - started < 65 then return end
                    timer.Remove(timerName)
                    print("[PW] HP_TEAM_RESULT completed=" .. tostring(count) .. " ok=" .. tostring(ok))
                    expect(ok).to.beTrue()
                    expect(count >= 2).to.beTrue()
                    expect(runtime.state.scores[1] >= 2).to.beTrue()
                    done()
                end)
            end
        }
    }
}
