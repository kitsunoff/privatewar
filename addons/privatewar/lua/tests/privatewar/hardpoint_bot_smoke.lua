-- Controlled subsystem smoke: real scheduler, commander, objective behavior, nav follower and CUserCmd input.
-- Public phase/board providers are scoped fixtures; no foreign private stores, damage or fabricated contacts.
---@return Player, boolean
local function acquireBot()
    -- Other groups kick their pool in afterAll; IsValid stays true until that queued kick completes.
    -- Reusing such a doomed entity is unsafe. This group creates exactly one bot and owns it throughout the case.
    local bot = player.CreateNextBot("PW Hardpoint smoke")
    assert(IsValid(bot), "Hardpoint smoke needs one free player slot")
    return bot, true
end

return {
    groupName = "PW Hardpoint real-input bot smoke",
    afterAll = function(state)
        timer.Remove("PW.HardpointHoldSmoke")
        hook.Remove("SetupMove", "PW.HardpointInputSmoke")
        local bot = state.bot --[[@as Player?]]
        if state.mode ~= nil then
            assert(PW.Hardpoint).Cleanup(state.mode)
            PW.ActiveMode = state.originalMode
            if bot ~= nil and IsValid(bot) then bot:SetTeam(state.originalTeam) end
        end
        if bot ~= nil and IsValid(bot) and state.owned then bot:Kick("Hardpoint smoke complete") end
    end,
    cases = {
        {
            name = "Hardpoint: bot holds then rotates through normal inputs",
            async = true,
            timeout = 75,
            func = function(testState)
                local hp = assert(PW.Hardpoint)
                local commander = assert(PW.BotCommander)
                assert(isfunction(rawget(commander, "InvalidateObjective")), "shared invalidation dependency absent")
                assert(isfunction(rawget(commander, "Sanitize")), "shared containment dependency absent")
                assert(game.GetMap() == "gm_construct", "Hardpoint smoke requires authored gm_construct")
                local mode = assert(PW.Modes.Get("hardpoint")) --[[@as PW.HardpointMode]]
                local originalMode = PW.ActiveMode
                testState.mode, testState.originalMode = mode, originalMode
                -- Establish LIVE before creation/spawn: outside LIVE the normal spawn selector returns nil.
                -- GLuaTest restores this public getter after the async case; the phase machine store is untouched.
                stub(assert(PW.Match), "GetPhase").with(function() return "LIVE" end)
                PW.ActiveMode = mode
                local bot, owned = acquireBot()
                testState.bot, testState.owned = bot, owned
                local originalTeam = bot:Team()
                testState.originalTeam = originalTeam
                local originalSetting = mode.Setting
                stub(mode, "Setting").with(function(self, key)
                    if key == "zonetime" then return 20 end
                    return originalSetting(self, key)
                end)
                ---@type PW.BotBoard
                local board = { bot = bot, team = 1, intent = { buttons = 0 } }
                local api = assert(PW.Bot)
                local originalGet = api.Get
                stub(api, "Get").with(function(ply) return ply == bot and board or originalGet(ply) end)
                stub(hp, "Send").with(function() end)
                bot:SetTeam(1)
                assert(PW.MatchRules).Spawn(bot) -- Initial setup only; asserted journeys use normal user commands.
                local nav = navmesh.GetNearestNavArea(bot:GetPos(), false, 128, false, true)
                print(string.format("[PW] HP_INPUT_SETUP phase %s alive %s observer %d held %s team %d pos %s nav %s",
                    assert(PW.Match).GetPhase(), tostring(bot:Alive()), bot:GetObserverMode(),
                    tostring(bot:GetNW2Bool(assert(PW.Jip).NetBool, false)), bot:Team(), tostring(bot:GetPos()),
                    IsValid(nav) and tostring(nav:GetID()) or "none"))
                expect(assert(PW.Match).GetPhase()).to.equal("LIVE")
                expect(bot:Alive()).to.beTrue()
                expect(bot:GetObserverMode()).to.equal(OBS_MODE_NONE)
                expect(bot:GetNW2Bool(assert(PW.Jip).NetBool, false)).to.beFalse()
                expect(bot:Team()).to.equal(1)
                hp.Start(mode)
                local runtime = assert(mode._Hardpoint)
                local start = bot:GetPos()
                local started, firstHeld, secondHeld = CurTime(), 0, 0
                local nextReport = started + 5
                local firstAt, secondAt, rotated = nil, nil, false
                local commands = 0
                local hookName, timerName = "PW.HardpointInputSmoke", "PW.HardpointHoldSmoke"
                hook.Add("SetupMove", hookName, function(ply, _, cmd)
                    if ply == bot and (math.abs(cmd:GetForwardMove()) > 0 or math.abs(cmd:GetSideMove()) > 0) then
                        commands = commands + 1
                    end
                end)
                local function advance()
                    assert(IsValid(bot), "Hardpoint smoke bot disconnected during the asserted journey")
                    local oldVisit, oldGoal = runtime.state.visit, board.goal
                    hp.Think(mode)
                    local state = runtime.state
                    if state.visit ~= oldVisit then
                        rotated = true
                        assert(board.order == nil or board.order.id ~= "hp_" .. state.generation .. "_" .. oldVisit,
                            "old commander hold survived invalidation")
                        assert(oldGoal == nil or board.goal ~= oldGoal, "old goal survived invalidation")
                    end
                    local now = CurTime()
                    if now >= nextReport then
                        nextReport = now + 5
                        print(string.format("[PW] HP_INPUT_PROGRESS visit %d pos %s order %s goal %s commands %d",
                            state.visit, tostring(bot:GetPos()), board.order ~= nil and board.order.id or "none",
                            board.goal ~= nil and board.goal.status or "none", commands))
                    end
                    local inside = hp.Inside(state.layout.zones[state.index], bot:GetPos()) and bot:Alive()
                    if state.visit == 1 then
                        firstAt = inside and (firstAt or now) or nil
                        firstHeld = math.max(firstHeld, firstAt ~= nil and now - firstAt or 0)
                    elseif state.visit == 2 then
                        secondAt = inside and (secondAt or now) or nil
                        secondHeld = math.max(secondHeld, secondAt ~= nil and now - secondAt or 0)
                    end
                    local complete = firstHeld >= 2 and secondHeld >= 2 and rotated
                    return complete, now - started >= 65
                end
                timer.Create(timerName, 0.1, 0, function()
                    local ok, complete, late = pcall(advance)
                    if ok and not complete and not late then return end
                    timer.Remove(timerName)
                    hook.Remove("SetupMove", hookName)
                    api.ClearGoal(bot)
                    hp.Cleanup(mode)
                    PW.ActiveMode = originalMode
                    if IsValid(bot) then bot:SetTeam(originalTeam) end
                    testState.mode = nil
                    local travel = IsValid(bot) and start:Distance2D(bot:GetPos()) or 0
                    print(string.format("[PW] HP_INPUT_SMOKE held %.1f/%.1f, commands %d, travel %.0f, visit %d",
                        firstHeld, secondHeld, commands, travel, runtime.state.visit))
                    if not ok then print("[PW] HP_INPUT_SMOKE error: " .. tostring(complete)) end
                    expect(ok).to.beTrue()
                    expect(complete).to.beTrue()
                    expect(commands > 0).to.beTrue()
                    expect(travel > 64).to.beTrue()
                    expect(runtime.state.scores[1] >= 2).to.beTrue()
                    done()
                end)
            end
        }
    }
}
