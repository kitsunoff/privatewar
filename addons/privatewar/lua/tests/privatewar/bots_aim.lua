-- T-5.8 aim controller (TASKS.md, "Mandatory test cases" T-5.8; 07-bots.md d.8, d.15; docs/api/bots-blackboard.md).
-- The controller is pure (PW.BotAim over plain numbers and a per-bot state table), so most cases run it over
-- simulated ticks with an injected random source. One real bot (beforeAll, kicked in afterAll) checks the engine
-- glue: aimed at a fixed point, its view converges within a bounded number of ticks. The bots manager stays idle for
-- the whole GLuaTest run (T-5.1), so this bot has no blackboard: the aim writes into a scripted intent.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotAimLib
local function lib()
    return must(PW.BotAim)
end

local tick = 1 / 66
local tiers = { "recruit", "regular", "hardened", "veteran" }

---A random source that always returns the same value (0: no aim error direction, no headshot roll miss).
---@param value number
---@return fun(): number
local function fixed(value)
    return function() return value end
end

---@param tier string
---@param over? table<string, any>
---@return PW.BotAimParams
local function params(tier, over)
    local out = lib().ParamsFor(nil, tier)
    for key, value in pairs(over or {}) do (out --[[@as table<string, any>]])[key] = value end
    return out
end

---Angular distance in degrees between two (pitch, yaw) pairs.
---@return number
local function angDist(p1, y1, p2, y2)
    local dp, dy = math.AngleDifference(p1, p2), math.AngleDifference(y1, y2)
    return math.sqrt(dp * dp + dy * dy)
end

local eye = Vector(0, 0, 64)

---A point at distance dist from eye in the direction (pitch, yaw).
---@return Vector
local function pointAt(pitch, yaw, dist)
    return eye + Angle(pitch, yaw, 0):Forward() * dist
end

---@param bot Player
---@return number yaw with free space in front of the bot (the most open of 8 directions)
local function freeYaw(bot)
    local best, bestFrac = 0, -1
    for i = 0, 7 do
        local yaw = i * 45
        local start = bot:EyePos()
        local tr = util.TraceLine({ start = start, endpos = start + Angle(0, yaw, 0):Forward() * 400, filter = bot })
        if tr.Fraction > bestFrac then best, bestFrac = yaw, tr.Fraction end
    end
    return best
end

return {
    groupName = "PW bots aim",
    beforeAll = function(state)
        -- In LOBBY a new teamless player is a fixed spectator (GM.TeamBased): give it the FFA team and spawn it.
        local bot = player.CreateNextBot("PW aim test") --[[@as Player?]]
        state.bot = bot
        if bot ~= nil and IsValid(bot) then
            bot:SetTeam(must(PW.MatchRules).FreeTeam)
            bot:Spawn()
        end
    end,
    afterAll = function(state)
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then
            must(lib().SetTarget)(bot, nil)
            must(PW.BotInput).SetScripted(bot, nil)
            bot:Kick("PW bots aim test finished")
        end
    end,
    cases = {
        {
            name = "Mandatory (T-5.8): the spring-damper converges without exceeding the acceleration clamp",
            func = function()
                for _, tier in ipairs(tiers) do
                    local p = params(tier)
                    for _, goal in ipairs({ { 0, 120 }, { 40, -90 }, { -30, 179 } }) do
                        local s = lib().NewState(0, -170, p, 0)
                        local maxAcc, maxSpeed = 0, 0
                        for _ = 1, 66 * 4 do
                            local vp, vy = s.vp, s.vy
                            lib().Spring(s, goal[1], goal[2], p, tick)
                            maxAcc = math.max(maxAcc, math.abs(s.vp - vp) / tick, math.abs(s.vy - vy) / tick)
                            maxSpeed = math.max(maxSpeed, math.abs(s.vp), math.abs(s.vy))
                        end
                        expect(maxAcc <= p.look_max_accel + 1e-6).to.beTrue()
                        expect(maxSpeed <= p.turn_max_speed + 1e-6).to.beTrue()
                        expect(angDist(s.p, s.y, goal[1], goal[2]) < 0.5).to.beTrue()
                    end
                end
            end
        },
        {
            name = "Spring: one axis reports the acceleration it used, clamped; yaw turns the short way round",
            func = function()
                local p = params("veteran")
                local _, vel, acc = lib().SpringAxis(0, 0, 90, 0, p, tick)
                expect(acc).to.equal(p.look_max_accel)
                expect(math.abs(vel - p.look_max_accel * tick) < 1e-9).to.beTrue()
                local pos = lib().SpringAxis(170, 0, -170, 0, p, tick)
                expect(pos > 170 or pos < -179).to.beTrue()
            end
        },
        {
            name = "Spring: a goal moving at a steady rate is tracked with a lag that shrinks with difficulty",
            func = function()
                local function lag(tier)
                    local p = params(tier)
                    local s = lib().NewState(0, 0, p, 0)
                    local goal, rate = 0, 30
                    for _ = 1, 66 * 3 do
                        goal = goal + rate * tick
                        lib().Spring(s, 0, goal, p, tick, 0, rate)
                    end
                    return math.abs(math.AngleDifference(goal, s.y))
                end
                expect(lag("veteran") < lag("regular")).to.beTrue()
                expect(lag("regular") < lag("recruit")).to.beTrue()
                expect(lag("veteran") < 1).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.8): the focus error shrinks while steady and resets on large moves",
            func = function()
                for _, tier in ipairs(tiers) do
                    local p = params(tier)
                    local s = lib().NewState(0, 0, p, 0)
                    expect(s.focus).to.equal(p.aim_focus_initial)
                    local last = s.focus
                    for i = 1, 66 do
                        lib().Focus(s, 0, p, tick)
                        expect(s.focus <= last).to.beTrue()
                        last = s.focus
                        if i == 66 then
                            local want = math.max(p.aim_focus_floor, p.aim_focus_initial * p.aim_focus_decay)
                            expect(math.abs(s.focus - want) < 0.01).to.beTrue()
                        end
                    end
                    for _ = 1, 66 * 20 do lib().Focus(s, 0, p, tick) end
                    expect(math.abs(s.focus - p.aim_focus_floor) < 1e-6).to.beTrue()
                    lib().Focus(s, p.aim_focus_reset_deg + 1, p, tick)
                    expect(s.focus).to.equal(p.aim_focus_initial)
                end
            end
        },
        {
            name = "Focus: a fast view or a moving goal holds the error; small moves add up to a reset",
            func = function()
                local p = params("regular")
                local s = lib().NewState(0, 0, p, 0)
                s.vy = 200
                lib().Focus(s, 0, p, tick)
                expect(s.focus).to.equal(p.aim_focus_initial)
                s.vy = 0
                for _ = 1, 66 do lib().Focus(s, 0, p, tick) end
                local shrunk = s.focus
                expect(shrunk < p.aim_focus_initial).to.beTrue()
                lib().Focus(s, 60 * tick, p, tick)
                expect(s.focus).to.equal(shrunk)
                for _ = 1, 66 do lib().Focus(s, 60 * tick, p, tick) end
                expect(s.focus).to.equal(p.aim_focus_initial)
            end
        },
        {
            name = "Mandatory (T-5.8): no fire before settle (flick, then fire only once the view holds on the target)",
            func = function()
                for _, tier in ipairs(tiers) do
                    local p = params(tier)
                    local s = lib().NewState(0, 0, p, 0)
                    lib().Acquire(s, p, 0, "smg", fixed(0))
                    local traces, firedAt = 0, nil
                    local point = pointAt(5, 90, 800)
                    for i = 1, 66 * 5 do
                        local now = i * tick
                        local wasSettled = s.settledSince
                        lib().Step(s, {
                            now = now, dt = tick, eye = eye, point = point, radius = 12, canFire = true,
                            lineOfFire = function() traces = traces + 1 return true end
                        }, p, fixed(0))
                        if s.fire then
                            expect(s.err <= s.tolerance).to.beTrue()
                            expect(wasSettled ~= nil).to.beTrue()
                            expect(now >= p.attack_delay).to.beTrue()
                            firedAt = firedAt or now
                        else
                            expect(firedAt == nil).to.beTrue()
                        end
                    end
                    expect(firedAt ~= nil).to.beTrue()
                    expect(traces > 0).to.beTrue()
                end
            end
        },
        {
            name = "Fire gate hysteresis: a settled view keeps firing within holdTolerance x tolerance, no further",
            func = function()
                local p = params("regular")
                local hold = lib().Config.holdTolerance
                expect(hold > 1 and hold <= 2.5).to.beTrue()
                local s = lib().NewState(0, 0, p, 0)
                lib().Acquire(s, p, 0, "smg", fixed(0))
                local input = { now = 0, dt = tick, eye = eye, point = pointAt(0, 0, 900), radius = 32,
                    canFire = true }
                ---Steps once with the view put off the goal by share x the current tolerance, at rest.
                ---@param share number
                local function stepOff(share)
                    s.p, s.vp, s.vy = s.goalP + share * s.tolerance, 0, 0
                    input.now = input.now + tick
                    lib().Step(s, input, p, fixed(0))
                end
                for i = 1, 66 do
                    input.now = i * tick
                    lib().Step(s, input, p, fixed(0))
                end
                expect(s.fire).to.beTrue()
                -- A wobble past the tolerance (the spring chasing the focus error) does not close a settled gate.
                stepOff(0.5 * (1 + hold))
                expect(s.err > s.tolerance).to.beTrue()
                expect(s.fire).to.beTrue()
                expect(s.settledSince ~= nil).to.beTrue()
                -- Past the hold band the view has left the target: the gate closes and the settle starts again.
                stepOff(hold + 0.5)
                expect(s.fire).to.beFalse()
                expect(s.settledSince).to.equal(nil)
                -- An unsettled view re-enters only within the tolerance itself.
                stepOff(0.5 * (1 + hold))
                expect(s.fire).to.beFalse()
                expect(s.settledSince).to.equal(nil)
            end
        },
        {
            name = "No aimbot: with the hold band a recruit's shots still miss more often than a veteran's",
            func = function()
                ---Share of the firing ticks over 4 s whose view ray passes within 16 units of the target at 800.
                ---@param tier string
                ---@return number
                local function hitShare(tier)
                    local p = params(tier)
                    local seed = 12345
                    local function roll()
                        seed = (seed * 1103515245 + 12345) % 2147483648
                        return seed / 2147483648
                    end
                    local s = lib().NewState(0, 30, p, 0)
                    lib().Acquire(s, p, 0, "smg", roll)
                    local fired, hits = 0, 0
                    for i = 1, 66 * 4 do
                        lib().Step(s, { now = i * tick, dt = tick, eye = eye, point = pointAt(0, 0, 800),
                            radius = 32, canFire = true }, p, roll)
                        if s.fire then
                            fired = fired + 1
                            local off = math.tan(math.rad(angDist(s.p, s.y, 0, 0))) * 800
                            if off < 16 then hits = hits + 1 end
                        end
                    end
                    expect(fired > 0).to.beTrue()
                    return hits / fired
                end
                local recruit, veteran = hitShare("recruit"), hitShare("veteran")
                expect(recruit < veteran).to.beTrue()
                expect(recruit < 0.5).to.beTrue()
            end
        },
        {
            name = "Focus: a switch between the remembered and the seen position is no target movement",
            func = function()
                local p = params("regular")
                local s = lib().NewState(0, 0, p, 0)
                lib().Acquire(s, p, 0, nil, fixed(0))
                local seen, remembered = pointAt(0, 0, 1000), pointAt(0, 8, 1000)
                local input = { now = 0, dt = tick, eye = eye, point = seen, radius = 32, canFire = true }
                ---@param point Vector
                ---@param canFire boolean
                local function stepTo(point, canFire)
                    input.now, input.point, input.canFire = input.now + tick, point, canFire
                    lib().Step(s, input, p, fixed(0))
                end
                for _ = 1, 66 * 2 do stepTo(seen, true) end
                local focus = s.focus
                expect(focus < p.aim_focus_initial / 2).to.beTrue()
                -- Sight lost (the stale remembered position, 8 degrees off) and regained: no reset, no drift.
                stepTo(remembered, false)
                stepTo(seen, true)
                expect(s.focus <= focus).to.beTrue()
                expect(s.drift < 1).to.beTrue()
                -- The same jumps while the knowledge stays the same are target movement: they reset the focus.
                stepTo(remembered, true)
                stepTo(seen, true)
                expect(s.focus).to.equal(p.aim_focus_initial)
            end
        },
        {
            name = "Line of fire: the trace runs from the eye through the aimed point, not along the wandering view",
            func = function()
                local point = pointAt(-3, 20, 700)
                local stop = lib().FireRayEnd(eye, point)
                local dir, want = (point - eye):GetNormalized(), 700 + lib().Config.traceSlack
                expect((stop - eye):GetNormalized():Distance(dir) < 1e-4).to.beTrue()
                expect(math.abs(stop:Distance(eye) - want) < 1e-3).to.beTrue()
            end
        },
        {
            name = "Fire gate: the attack delay holds the first shot; a point target or a lost contact never fires",
            func = function()
                local p = params("recruit")
                local point = pointAt(0, 0, 500)
                local s = lib().NewState(0, 0, p, 0)
                lib().Acquire(s, p, 0, nil, fixed(0))
                local input = { now = 0, dt = tick, eye = eye, point = point, radius = 12, canFire = true }
                for i = 1, 20 do
                    input.now = i * tick
                    lib().Step(s, input, p, fixed(0))
                    expect(s.fire).to.beFalse()
                end
                input.canFire = false
                for i = 1, 66 * 2 do
                    input.now = 1 + i * tick
                    lib().Step(s, input, p, fixed(0))
                    expect(s.fire).to.beFalse()
                end
                input.canFire = true
                lib().Step(s, input, p, fixed(0))
                expect(s.fire).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.8): the line-of-fire gate blocks firing at an occluded target",
            func = function()
                local target, mate, enemy = "target", "mate", "enemy"
                local function isEnemy(ent) return ent == target or ent == enemy end
                expect(lib().FireClear({ fraction = 0.4, world = true }, target, isEnemy)).to.beFalse()
                expect(lib().FireClear({ fraction = 0.6, ent = mate }, target, isEnemy)).to.beFalse()
                expect(lib().FireClear({ fraction = 0.6, ent = "prop" }, target, isEnemy)).to.beFalse()
                expect(lib().FireClear({ fraction = 0.9, ent = target }, target, isEnemy)).to.beTrue()
                expect(lib().FireClear({ fraction = 0.5, ent = enemy }, target, isEnemy)).to.beTrue()
                expect(lib().FireClear({ fraction = 1 }, target, isEnemy)).to.beTrue()
                local p = params("veteran")
                local s = lib().NewState(0, 0, p, 0)
                lib().Acquire(s, p, 0, nil, fixed(0))
                local point = pointAt(0, 0, 600)
                local traces = 0
                for i = 1, 66 do
                    lib().Step(s, {
                        now = 1 + i * tick, dt = tick, eye = eye, point = point, radius = 12, canFire = true,
                        lineOfFire = function()
                            traces = traces + 1
                            return lib().FireClear({ fraction = 0.3, world = true }, target, isEnemy)
                        end
                    }, p, fixed(0))
                    expect(s.fire).to.beFalse()
                end
                expect(traces > 0).to.beTrue()
                expect(s.blockedSince ~= nil).to.beTrue()
            end
        },
        {
            name = "Lead: hitscan aims at the target; a projectile leads by relative velocity, scaled by difficulty",
            func = function()
                local facts = {
                    pos = Vector(1000, 0, 64), vel = Vector(0, 200, 0), ownVel = Vector(0, 0, 0), eye = eye
                }
                expect(lib().Lead(facts, params("veteran"))).to.equal(facts.pos)
                facts.projectileSpeed = 1000
                expect(lib().Lead(facts, params("veteran")):Distance(Vector(1000, 200, 64)) < 1e-3).to.beTrue()
                expect(lib().Lead(facts, params("regular")):Distance(Vector(1000, 100, 64)) < 1e-3).to.beTrue()
                expect(lib().Lead(facts, params("recruit"))).to.equal(facts.pos)
                facts.ownVel = Vector(0, 200, 0)
                expect(lib().Lead(facts, params("veteran")):Distance(facts.pos) < 1e-3).to.beTrue()
            end
        },
        {
            name = "Headshots are gated by difficulty and weapon category",
            func = function()
                expect(lib().AimPart(params("recruit"), "ar", 0)).to.equal("chest")
                expect(lib().AimPart(params("regular"), "sniper", 0)).to.equal("chest")
                expect(lib().AimPart(params("hardened"), "ar", 0)).to.equal("head")
                expect(lib().AimPart(params("hardened"), "smg", 0)).to.equal("chest")
                expect(lib().AimPart(params("hardened"), nil, 0)).to.equal("chest")
                expect(lib().AimPart(params("veteran"), "smg", 0)).to.equal("head")
                expect(lib().AimPart(params("veteran"), "smg", 0.999)).to.equal("chest")
            end
        },
        {
            name = "Recoil gain: the bot pulls against the view kick by its difficulty's share",
            func = function()
                local last = 0
                for _, tier in ipairs(tiers) do
                    local p = params(tier)
                    local dp, dy = lib().RecoilOffset(-4, 2, p)
                    expect(math.abs(dp - 4 * p.recoil_comp_gain) < 1e-9).to.beTrue()
                    expect(math.abs(dy + 2 * p.recoil_comp_gain) < 1e-9).to.beTrue()
                    expect(dp > last).to.beTrue()
                    last = dp
                end
                local p = params("veteran")
                local s = lib().NewState(0, 0, p, 0)
                lib().Acquire(s, p, 0, nil, fixed(0))
                lib().Step(s, { now = 1, dt = tick, eye = eye, point = pointAt(0, 0, 500), radius = 12,
                    canFire = false, kickP = -4 }, p, fixed(0))
                expect(math.abs(s.goalP - 4 * p.recoil_comp_gain) < 1e-6).to.beTrue()
            end
        },
        {
            name = "Fire tolerance scales with the target's angular size, within bounds",
            func = function()
                local near, far = lib().Tolerance(12, 300), lib().Tolerance(12, 3000)
                expect(near > far).to.beTrue()
                expect(lib().Tolerance(5, 3000) <= far).to.beTrue()
                expect(lib().Tolerance(12, 1e6) >= lib().Config.minTolerance).to.beTrue()
                expect(lib().Tolerance(12, 1) <= lib().Config.maxTolerance).to.beTrue()
            end
        },
        {
            name = "Difficulty: tier defaults, unknown tier falls back to regular, entity fields win",
            func = function()
                expect(lib().ParamsFor(nil, "nope").aim_focus_initial).to.equal(params("regular").aim_focus_initial)
                expect(lib().ParamsFor(nil, nil).look_stiffness).to.equal(params("regular").look_stiffness)
                local custom = lib().ParamsFor({ aim_focus_initial = 3, headshot_allowed = "yes", junk = 1 }, "recruit")
                expect(custom.aim_focus_initial).to.equal(3)
                expect(custom.headshot_allowed).to.equal("yes")
                expect(custom.look_stiffness).to.equal(params("recruit").look_stiffness)
                ---@type number[]
                local initial = {}
                for i, tier in ipairs(tiers) do initial[i] = params(tier).aim_focus_initial end
                expect(initial[1] > initial[2] and initial[2] > initial[3] and initial[3] > initial[4]).to.beTrue()
            end
        },
        {
            name = "Dev command: pw_bot_aim arguments parse into target, clear and status",
            func = function()
                local parsed = must(lib().ParseArgs({ "*", "me" }))
                expect(parsed.bots).to.equal("*")
                expect(parsed.action).to.equal("target")
                expect(parsed.target).to.equal("me")
                expect(must(lib().ParseArgs({ "Bot", "clear" })).action).to.equal("clear")
                expect(must(lib().ParseArgs({ "Bot", "status" })).action).to.equal("status")
                local none, err = lib().ParseArgs({ "Bot" })
                expect(none).to.beNil()
                expect(isstring(err)).to.beTrue()
                expect(must(lib().ParseArgs({ "Bot", "Kit", "Veteran" })).tier).to.equal("veteran")
                expect(lib().ParseArgs({ "Bot", "Kit", "godlike" })).to.beNil()
                expect(lib().ParseArgs({ "Bot", "clear", "veteran" })).to.beNil()
            end
        },
        {
            name = "Mandatory (T-5.8), in game: a real bot aimed at a fixed point converges within 2 s",
            async = true,
            timeout = 8,
            func = function(state)
                local bot = must(state.bot) --[[@as Player]]
                expect(bot).to.beValid()
                ---@type PW.BotIntent
                local intent = { buttons = 0 }
                must(PW.BotInput).SetScripted(bot, intent)
                timer.Simple(0.3, function()
                    local yaw = math.NormalizeAngle(freeYaw(bot) + 90)
                    local point = bot:EyePos() + Angle(10, yaw, 0):Forward() * 600
                    -- Veteran: the smallest error, so the error offset that keeps wandering stays within a degree.
                    must(lib().SetTarget)(bot, point, "veteran")
                    timer.Simple(2, function()
                        local s = must(must(lib().GetState)(bot))
                        local owned = must(lib().OwnsView)(bot)
                        local fire = s.fire
                        local view = bot:EyeAngles()
                        local onState = angDist(view.p, view.y, s.p, s.y)
                        local onGoal = angDist(view.p, view.y, s.goalP, s.goalY)
                        local onPoint = angDist(view.p, view.y, 10, yaw)
                        must(lib().SetTarget)(bot, nil)
                        local released = not must(lib().OwnsView)(bot)
                        must(PW.BotInput).SetScripted(bot, nil)
                        -- The view is the controller's (the glue reaches the engine), it holds on the goal, and the
                        -- goal is within the focus error of the point.
                        expect(onState < 0.5).to.beTrue()
                        expect(onGoal < 1).to.beTrue()
                        expect(onPoint < s.focus + 1).to.beTrue()
                        expect(fire).to.beFalse()
                        expect(owned).to.beTrue()
                        expect(released).to.beTrue()
                        expect(bit.band(intent.buttons, IN_ATTACK)).to.equal(0)
                        done()
                    end)
                end)
            end
        }
    }
}
