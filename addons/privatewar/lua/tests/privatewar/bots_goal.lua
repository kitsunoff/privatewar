-- T-5.6 goal API, goal wrapper, path follower and stuck ladder (TASKS.md, "Mandatory test cases" T-5.6;
-- 07-bots.md d.6; docs/api/bots-blackboard.md "Goal API"). The rules are pure functions over plain data
-- (PW.BotGoal: arbitration, blacklist, stuck ladder, waypoint advance, look-ahead, door step), so most cases run them
-- directly with a fake clock. One real bot (beforeAll, kicked in afterAll) checks the glue: the priority rule and the
-- blacklist through SetGoal with a stubbed path service, and the smoke scenario: on gm_construct the bot walks to a
-- goal about 20 m (790 units) away. The bots manager is idle during GLuaTest (T-5.1), so the bot has no blackboard of
-- its own: the cases stub PW.BotGoal.BoardOf with a board whose intent is also the bot's scripted intent.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotGoalLib
local function lib()
    return must(PW.BotGoal)
end

---A test blackboard for bot; with fakeNavmesh every point projects onto itself (the path service is stubbed too).
---GLuaTest's stub exists only inside a case, so the case passes it in.
---@param stubber fun(tbl: table, key: string): any
---@param bot Player
---@param fakeNavmesh? boolean
---@return PW.BotBoard
local function testBoard(stubber, bot, fakeNavmesh)
    ---@type PW.BotBoard
    local board = { bot = bot, intent = { buttons = 0 } }
    must(PW.BotInput).SetScripted(bot, board.intent)
    stubber(lib(), "BoardOf").with(function(ply) return ply == bot and board or nil end)
    if fakeNavmesh then stubber(lib(), "Project").with(function(point) return point end) end
    return board
end

---A path handle that never finishes (the bot stays put).
---@param from any
---@param to any
---@return PW.NavHandle
local function pendingHandle(from, to)
    return { status = "queued", partial = false, cached = false, iterations = 0, slices = 0, done = false,
        from = from, to = to }
end

---Runs the stuck ladder on a bot that gets no nearer its goal (the remaining path length stays 500), one check every
---0.1 s; returns the actions in order of first appearance.
---@param seconds number
---@return string[]
local function stationaryLadder(seconds)
    local state = lib().NewStuck()
    ---@type string[]
    local order = {}
    local last = nil
    for t = 0, seconds, 0.1 do
        local action = lib().StuckStep(state, 500, 100 + t)
        if action ~= nil and action ~= last then order[#order + 1] = action end
        last = action
    end
    return order
end

---A navmesh area about distance units away from pos on roughly the same height (nil when there is none).
---@param pos Vector
---@param distance number
---@return Vector?
local function areaAt(pos, distance)
    local best, bestError = nil, math.huge
    for _, area in ipairs(navmesh.GetAllNavAreas() --[[@as CNavArea[] ]]) do
        local center = area:GetCenter()
        local err = math.abs(center:Distance2D(pos) - distance)
        local big = area:GetSizeX() >= 48 and area:GetSizeY() >= 48
        if big and math.abs(center.z - pos.z) < 48 and err < bestError then best, bestError = center, err end
    end
    if bestError > 150 then return nil end
    return best
end

---One line of the smoke progress: the goal, the path, the follower and the bot.
---@param bot Player
---@param board PW.BotBoard
---@return string
local function smokeReport(bot, board)
    local goal, path = board.goal, board.path
    local st = PW._BotGoal.states[bot]
    local move = board.intent ~= nil and board.intent.move or nil
    return string.format("status %s, path %s, attempts %s, pending %s, stuck %s, pos %s, move %s, alive %s",
        goal ~= nil and goal.status or "none",
        path ~= nil and string.format("%d/%d%s", path.index, #path.points, path.partial and " partial" or "") or "none",
        st ~= nil and tostring(st.attempts) or "-", st ~= nil and tostring(st.token ~= nil) or "-",
        st ~= nil and tostring(st.stuck.level) or "-", tostring(bot:GetPos()), tostring(move), tostring(bot:Alive()))
end

return {
    groupName = "PW bots goal",
    beforeAll = function(state)
        -- In LOBBY a new teamless player is a fixed spectator (GM.TeamBased): give it the FFA team and spawn it.
        local bot = player.CreateNextBot("PW goal test") --[[@as Player?]]
        state.bot = bot
        if bot ~= nil and IsValid(bot) then
            bot:SetTeam(must(PW.MatchRules).FreeTeam)
            bot:Spawn()
        end
    end,
    afterAll = function(state)
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then
            lib()._Drop(bot)
            must(PW.BotInput).SetScripted(bot, nil)
            bot:Kick("PW bots goal test finished")
        end
    end,
    cases = {
        {
            name = "Mandatory (T-5.6): a higher priority goal overrides a lower one (pure arbitration)",
            func = function()
                local a, b = Vector(0, 0, 0), Vector(500, 0, 0)
                ---@type PW.BotGoal
                local current = { point = a, radius = 64, priority = "guard", status = "moving", since = 0 }
                expect(lib().Arbitrate(current, b, 64, "objective")).to.equal("new")
                expect(lib().Arbitrate(current, b, 64, "critical")).to.equal("new")
                expect(lib().Arbitrate(current, b, 64, "hunt")).to.equal("reject")
                expect(lib().Arbitrate(current, b, 64, "guard")).to.equal("new")
                expect(lib().Arbitrate(current, a + Vector(8, 0, 0), 64, "guard")).to.equal("same")
                expect(lib().Arbitrate(nil, b, 64, "hunt")).to.equal("new")
                current.status = "arrived"
                expect(lib().Arbitrate(current, b, 64, "hunt")).to.equal("new")
                expect(lib().PriorityValue("hunt") < lib().PriorityValue("guard")).to.beTrue()
                expect(lib().PriorityValue("objective") < lib().PriorityValue("tactical")).to.beTrue()
                expect(lib().PriorityValue("tactical") < lib().PriorityValue("critical")).to.beTrue()
                expect(lib().PriorityValue("nonsense")).to.beNil()
            end
        },
        {
            name = "Mandatory (T-5.6), glue: SetGoal on a bot keeps the higher priority goal and rejects a lower one",
            func = function(state)
                local bot = must(state.bot) --[[@as Player]]
                expect(bot).to.beValid()
                local board = testBoard(stub, bot, true)
                stub(must(PW.BotNav), "RequestPath").with(pendingHandle)
                stub(must(PW.BotNav), "Cancel")
                local origin = bot:GetPos()
                local accepted = lib().SetGoal(bot, origin + Vector(600, 0, 0), 64, "guard")
                expect(accepted).to.beTrue()
                expect(must(board.goal).priority).to.equal("guard")
                accepted = lib().SetGoal(bot, origin + Vector(0, 600, 0), 64, "objective")
                expect(accepted).to.beTrue()
                expect(must(board.goal).priority).to.equal("objective")
                expect(must(board.goal).status).to.equal("moving")
                accepted = lib().SetGoal(bot, origin + Vector(-600, 0, 0), 64, "hunt")
                expect(accepted).to.beFalse()
                expect(must(board.goal).priority).to.equal("objective")
                lib()._Drop(bot)
                expect(board.goal).to.beNil()
            end
        },
        {
            name = "Mandatory (T-5.6): an unreachable goal is blacklisted (pure blacklist with a fake clock)",
            func = function()
                local now = 100
                local list = lib().NewBlacklist(30, function() return now end)
                local key = lib().PointKey(Vector(130, 10, 0))
                expect(list.Has(key)).to.beFalse()
                list.Add(key)
                expect(list.Has(key)).to.beTrue()
                expect(list.Has(lib().PointKey(Vector(140, 20, 5)))).to.beTrue()
                expect(list.Has(lib().PointKey(Vector(600, 0, 0)))).to.beFalse()
                now = 131
                expect(list.Has(key)).to.beFalse()
                expect(list.Count()).to.equal(0)
            end
        },
        {
            name = "Mandatory (T-5.6), glue: a goal the path service proves unreachable is blacklisted for the bot",
            func = function(state)
                local bot = must(state.bot) --[[@as Player]]
                expect(bot).to.beValid()
                local board = testBoard(stub, bot, true)
                local requests = 0
                stub(must(PW.BotNav), "RequestPath").with(function(from, to, callback)
                    requests = requests + 1
                    local handle = pendingHandle(from, to)
                    handle.status, handle.done = "unreachable", true
                    if callback ~= nil then callback(handle) end
                    return handle
                end)
                stub(must(PW.BotNav), "Cancel")
                local point = bot:GetPos() + Vector(400, 0, 0)
                lib().SetGoal(bot, point, 64, "objective")
                expect(must(board.goal).status).to.equal("unreachable")
                expect(requests).to.equal(1)
                local accepted, status = lib().SetGoal(bot, point, 64, "critical")
                expect(accepted).to.beFalse()
                expect(status).to.equal("unreachable")
                expect(must(board.goal).reason).to.equal("blacklisted")
                expect(requests).to.equal(1)
                lib()._Drop(bot)
            end
        },
        {
            name = "Mandatory (T-5.6): the stuck ladder escalates in order (jump to give up)",
            func = function()
                expect(stationaryLadder(8)).to.deepEqual({ "jump", "crouch", "back_off", "side_step", "repath",
                    "give_up" })
                expect(lib().StuckLadder).to.deepEqual({ "jump", "crouch", "back_off", "side_step", "repath",
                    "give_up" })
            end
        },
        {
            name = "Stuck ladder: progress toward the goal over the window resets it; none escalates once per window",
            func = function()
                local s = lib().NewStuck()
                expect(lib().StuckStep(s, 1000, 0)).to.beNil()
                expect(lib().StuckStep(s, 995, 0.5)).to.beNil()
                expect(lib().StuckStep(s, 995, 1.0)).to.equal("jump")
                expect(lib().StuckStep(s, 994, 1.5)).to.equal("jump")
                expect(lib().StuckStep(s, 994, 2.0)).to.equal("crouch")
                expect(lib().StuckStep(s, 800, 3.0)).to.beNil()
                expect(s.level).to.equal(0)
                lib().StuckStep(s, 800, 4.0)
                lib().StuckReset(s)
                expect(lib().StuckStep(s, 800, 4.5)).to.beNil()
            end
        },
        {
            name = "Stuck ladder: moving away from the goal (backing off, side steps) is no progress",
            func = function()
                local s = lib().NewStuck()
                lib().StuckStep(s, 600, 0)
                expect(lib().StuckStep(s, 600, 1)).to.equal("jump")
                expect(lib().StuckStep(s, 600, 2)).to.equal("crouch")
                expect(lib().StuckStep(s, 600, 3)).to.equal("back_off")
                expect(lib().StuckStep(s, 700, 4)).to.equal("side_step")
                expect(lib().StuckStep(s, 690, 5)).to.equal("repath")
                lib().StuckRestartWindow(s, 900)
                expect(lib().StuckStep(s, 900, 5.5)).to.equal("repath")
                expect(lib().StuckStep(s, 890, 6)).to.equal("give_up")
                local r = lib().Remaining({ Vector(100, 0, 0), Vector(100, 100, 0) }, 1, Vector(0, 0, 0))
                expect(math.abs(r - 200) < 0.01).to.beTrue()
                expect(lib().Remaining({ Vector(100, 0, 0) }, 2, Vector(0, 0, 0))).to.equal(0)
            end
        },
        {
            name = "Stuck input: each rung has its own move and buttons; the side alternates",
            func = function()
                local jump = must(lib().StuckInput("jump", 0, 1))
                expect(bit.band(jump.buttons, IN_JUMP) ~= 0).to.beTrue()
                local late = must(lib().StuckInput("jump", 0.5, 1))
                expect(bit.band(late.buttons, IN_DUCK) ~= 0).to.beTrue()
                expect(bit.band(must(lib().StuckInput("crouch", 0, 1)).buttons, IN_DUCK) ~= 0).to.beTrue()
                expect(must(lib().StuckInput("back_off", 0, 1)).forward < 0).to.beTrue()
                expect(must(lib().StuckInput("side_step", 0, -1)).side).to.equal(-1)
                expect(lib().StuckInput("repath", 0, 1)).to.beNil()
                local s = lib().NewStuck()
                for t = 0, 4.5, 0.1 do lib().StuckStep(s, 500, t) end
                expect(s.side).to.equal(-1)
            end
        },
        {
            name = "Follower: waypoints are passed within reach and when the bot is already nearer the next one",
            func = function()
                local points = { Vector(100, 0, 0), Vector(200, 0, 0), Vector(200, 200, 0) }
                expect(lib().Advance(points, 1, Vector(0, 0, 0), 24)).to.equal(1)
                expect(lib().Advance(points, 1, Vector(90, 0, 0), 24)).to.equal(2)
                expect(lib().Advance(points, 1, Vector(150, 0, 0), 24)).to.equal(2)
                expect(lib().Advance(points, 2, Vector(200, 190, 0), 24)).to.equal(4)
                expect(lib().Advance(points, 1, Vector(100, 0, 200), 24)).to.equal(1)
            end
        },
        {
            name = "Follower: the look-ahead point lies the given distance along the path",
            func = function()
                local points = { Vector(100, 0, 0), Vector(100, 100, 0) }
                local p = lib().LookAhead(points, 1, Vector(0, 0, 0), 150)
                expect(p:Distance(Vector(100, 50, 0)) < 0.01).to.beTrue()
                local near = lib().LookAhead(points, 1, Vector(0, 0, 0), 40)
                expect(near:Distance(Vector(40, 0, 0)) < 0.01).to.beTrue()
                local far = lib().LookAhead(points, 1, Vector(0, 0, 0), 1000)
                expect(far:Distance(Vector(100, 100, 0)) < 0.01).to.beTrue()
            end
        },
        {
            name = "Follower: the move toward a point is relative to the view yaw",
            func = function()
                local f, s = lib().MoveFor(Vector(0, 0, 0), Vector(100, 0, 0), 0, 400)
                expect(math.abs(f - 400) < 0.01 and math.abs(s) < 0.01).to.beTrue()
                f, s = lib().MoveFor(Vector(0, 0, 0), Vector(0, 100, 0), 0, 400)
                expect(math.abs(f) < 0.01 and math.abs(s + 400) < 0.01).to.beTrue()
                f, s = lib().MoveFor(Vector(0, 0, 0), Vector(0, 100, 0), 90, 400)
                expect(math.abs(f - 400) < 0.01 and math.abs(s) < 0.01).to.beTrue()
                expect(lib().Arrived(Vector(0, 0, 0), Vector(50, 0, 10), 64)).to.beTrue()
                expect(lib().Arrived(Vector(0, 0, 0), Vector(80, 0, 0), 64)).to.beFalse()
                expect(lib().Arrived(Vector(0, 0, 0), Vector(10, 0, 200), 64)).to.beFalse()
            end
        },
        {
            name = "View: the follower writes the view only while the aim does not own it",
            func = function()
                local owns = { aimed = true }
                local aim = { OwnsView = function(bot) return owns[bot] == true end }
                expect(lib().FollowerOwnsView(nil, "aimed")).to.beTrue()
                expect(lib().FollowerOwnsView({}, "aimed")).to.beTrue()
                expect(lib().FollowerOwnsView(aim, "aimed")).to.beFalse()
                expect(lib().FollowerOwnsView(aim, "free")).to.beTrue()
            end
        },
        {
            name = "Doors: use once, wait for it to open, use again after the cooldown; nothing without a door",
            func = function()
                local d = {}
                expect(lib().DoorStep(d, 10, false)).to.beNil()
                expect(lib().DoorStep(d, 10, true)).to.equal("use")
                expect(lib().DoorStep(d, 10.3, true)).to.equal("wait")
                expect(lib().DoorStep(d, 11, true)).to.beNil()
                expect(lib().DoorStep(d, 11.6, true)).to.equal("use")
                expect(lib().IsDoorClass("prop_door_rotating")).to.beTrue()
                expect(lib().IsDoorClass("func_door")).to.beTrue()
                expect(lib().IsDoorClass("prop_physics")).to.beFalse()
            end
        },
        {
            name = "Goal wrapper: retry backoff grows and is capped; waypoints enter each area toward its centre",
            func = function()
                expect(lib().RetryDelay(1)).to.equal(0)
                expect(lib().RetryDelay(2) < lib().RetryDelay(3)).to.beTrue()
                expect(lib().RetryDelay(50)).to.equal(lib().RetryDelay(20))
                local points = lib().Waypoints({
                    { entry = Vector(100, 0, 0), center = Vector(200, 0, 0) },
                    { entry = Vector(300, 5, 0), center = Vector(305, 5, 0) }
                }, Vector(400, 0, 0))
                expect(#points).to.equal(3)
                expect(points[1]:Distance(Vector(116, 0, 0)) < 0.01).to.beTrue()
                expect(points[2]:Distance(Vector(305, 5, 0)) < 0.01).to.beTrue()
                expect(points[3]).to.equal(Vector(400, 0, 0))
            end
        },
        {
            name = "Dev command: pw_bot_goto arguments parse; bad input returns the usage",
            func = function()
                local here = must(lib().ParseGotoArgs({ "Bot", "here" }))
                expect(here.pattern).to.equal("Bot")
                expect(here.mode).to.equal("here")
                expect(here.priority).to.equal("critical")
                local point = must(lib().ParseGotoArgs({ "*", "10", "20", "-30", "96", "guard" }))
                expect(point.mode).to.equal("point")
                expect(point.point).to.equal(Vector(10, 20, -30))
                expect(point.radius).to.equal(96)
                expect(point.priority).to.equal("guard")
                expect(must(lib().ParseGotoArgs({ "*", "clear" })).mode).to.equal("clear")
                expect(must(lib().ParseGotoArgs({ "*", "status" })).mode).to.equal("status")
                local bad, usage = lib().ParseGotoArgs({ "*", "10", "x", "5" })
                expect(bad).to.beNil()
                expect(isstring(usage)).to.beTrue()
                expect(lib().ParseGotoArgs({ "*", "here", "64", "boss" })).to.beNil()
                expect(lib().ParseGotoArgs({})).to.beNil()
            end
        },
        {
            name = "Mandatory (T-5.6), smoke on gm_construct: a real bot reaches a goal about 20 m away",
            async = true,
            timeout = 45,
            func = function(state)
                local bot = must(state.bot) --[[@as Player]]
                expect(bot).to.beValid()
                if game.GetMap() ~= "gm_construct" then
                    print("[PW] bots goal smoke skipped: map is " .. game.GetMap())
                    done()
                    return
                end
                local board = testBoard(stub, bot)
                timer.Simple(0.5, function()
                    local start = bot:GetPos()
                    local target = must(areaAt(start, 790))
                    local started = CurTime()
                    lib().SetGoal(bot, target, 64, "critical")
                    local name = "PW.BotGoalSmoke"
                    local nextReport = started + 5
                    timer.Create(name, 0.25, 0, function()
                        local goal = board.goal
                        local status = goal ~= nil and goal.status or "none"
                        local late = CurTime() - started > 40
                        if CurTime() >= nextReport or late then
                            nextReport = CurTime() + 5
                            print("[PW] bots goal smoke progress: " .. smokeReport(bot, board))
                        end
                        if status == "moving" and not late then return end
                        timer.Remove(name)
                        print(string.format("[PW] bots goal smoke: %s from %s to %s (%.0f units) in %.1f s, %s",
                            status, tostring(start), tostring(target), start:Distance(target), CurTime() - started,
                            goal ~= nil and tostring(goal.reason) or "-"))
                        lib()._Drop(bot)
                        expect(status).to.equal("arrived")
                        expect(bot:GetPos():Distance2D(target) <= 96).to.beTrue()
                        done()
                    end)
                end)
            end
        }
    }
}
