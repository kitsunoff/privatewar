-- Optional fight movement: pure planning, exact ownership and the real input writer contract.
local function movement() return assert(PW.BotCombatMovement) end

---@param over table<string, any>?
---@return PW.CombatMoveInput
local function facts(over)
    local f = { now = 10, target = "enemy", visible = true, grounded = true, nav = false,
        speed = 400, left = true, right = true, sliding = false }
    for key, value in pairs(over or {}) do f[key] = value end
    return f --[[@as PW.CombatMoveInput]]
end

return {
    groupName = "PW optional combat movement",
    cases = {
        {
            name = "Short strafe: independent direction rolls and bounded 0.3 to 0.6 second legs",
            func = function()
                local lib = movement()
                local a = lib.Plan(facts(), nil, 0, 0)
                local b = lib.Plan(facts(), nil, 1, 1)
                expect(a.side).to.equal(-1)
                expect(b.side).to.equal(1)
                expect(math.abs(a.untilAt - 10.3) < 0.00001).to.beTrue()
                expect(math.abs(b.untilAt - 10.6) < 0.00001).to.beTrue()
                local repeatSide = lib.Plan(facts({ now = 11 }), a, 0, 0.5)
                expect(repeatSide.side).to.equal(-1)
            end
        },
        {
            name = "Safety: wall or edge flips to the safe side; both blocked stands without inventing a goal",
            func = function()
                local lib = movement()
                expect(lib.Plan(facts({ left = false }), nil, 0, 0).side).to.equal(1)
                expect(lib.Plan(facts({ right = false }), nil, 1, 0).side).to.equal(-1)
                local blocked = lib.Plan(facts({ left = false, right = false }), nil, 0, 0)
                expect(blocked.side).to.equal(0)
                expect(blocked.drive).to.beNil()
                expect((blocked --[[@as table<string, any>]]).goal).to.beNil()
            end
        },
        {
            name = "Lifecycle: target loss replacement death airborne and nav ownership never continue direct drive",
            func = function()
                local lib = movement()
                local previous = lib.Plan(facts(), nil, 0, 0)
                for _, over in ipairs({ { visible = false }, { grounded = false }, { nav = true } }) do
                    expect(lib.Plan(facts(over), previous, 0, 0).drive).to.beNil()
                end
                local changed = lib.Plan(facts({ target = "other" }), previous, 1, 0)
                expect(changed.side).to.equal(1)
                expect(changed.target).to.equal("other")
            end
        },
        {
            name = "CUserCmd: left and right are lateral only; nav move wins and aim fire remain independent",
            func = function()
                local input = assert(PW.BotInput)
                for _, roll in ipairs({ 0, 1 }) do
                    local plan = movement().Plan(facts(), nil, roll, 0)
                    local intent = { buttons = IN_ATTACK, drive = plan.drive, view = Angle(0, 25, 0) }
                    local out = input.Translate(intent, nil, input.NewState(), { now = 10, eye = Angle() })
                    expect(out.forward).to.equal(0)
                    expect(out.side).to.equal(plan.side * 400)
                    expect(out.angles.y).to.equal(25)
                    expect(bit.band(out.buttons, IN_ATTACK) ~= 0).to.beTrue()
                    expect(bit.band(out.buttons, IN_SPEED)).to.equal(0)
                    intent.move = Vector(100, 20, 0)
                    out = input.Translate(intent, nil, input.NewState(), { now = 10, eye = Angle() })
                    expect(out.forward).to.equal(100)
                    expect(out.side).to.equal(20)
                end
            end
        },
        {
            name = "Hull and ground: right is negative world Y; walls ledges slopes fail closed within eight traces",
            func = function()
                local safe = assert(movement().Safe)
                local bot = { GetPos = function() return Vector() end,
                    EyeAngles = function() return Angle() end,
                    GetHull = function() return Vector(-16, -16, 0), Vector(16, 16, 72) end } --[[@as Player]]
                local count, wall, ground, slope = 0, false, true, 1
                local endY = 0
                stub(util, "TraceHull").with(function(data)
                    local trace = data --[[@as {endpos: Vector}]]
                    count, endY = count + 1, trace.endpos.y
                    return { Fraction = wall and 0.5 or 1, StartSolid = false, AllSolid = false }
                end)
                stub(util, "TraceLine").with(function()
                    count = count + 1
                    return { Hit = ground, StartSolid = false, HitNormal = Vector(0, 0, slope) }
                end)
                expect(safe(bot, 1, 64)).to.beTrue()
                expect(endY < 0).to.beTrue()
                expect(safe(bot, -1, 64)).to.beTrue()
                expect(endY > 0).to.beTrue()
                expect(count <= 8).to.beTrue()
                wall = true
                expect(safe(bot, 1, 64)).to.beFalse()
                wall, ground = false, false
                expect(safe(bot, 1, 64)).to.beFalse()
                ground, slope = true, 0.5
                expect(safe(bot, 1, 64)).to.beFalse()
            end
        },
        {
            name = "Verified slide: keep launch side; a blocked launch side stops instead of steering",
            func = function()
                local lib = movement()
                local old = lib.Plan(facts(), nil, 0, 0)
                old.slideAt, old.untilAt = 10, 10.75
                local held = lib.Plan(facts({ now = 10.5, sliding = true }), old, 1, 0)
                expect(held.side).to.equal(-1)
                expect(held.slideAt).to.equal(10)
                expect(held.untilAt).to.equal(10.75)
                local stopped = lib.Plan(facts({ now = 10.5, sliding = true, left = false }), old, 1, 0)
                expect(stopped.side).to.equal(0)
                expect(stopped.slideAt).to.beNil()
                expect(lib.Plan(facts({ sliding = true }), nil, 1, 0).drive).to.beNil()
            end
        },
        {
            name = "Slide corridor: supported full travel is required; oversized requests fail closed before tracing",
            func = function()
                local safe = assert(movement().Safe)
                local bot = { GetPos = function() return Vector() end,
                    EyeAngles = function() return Angle() end,
                    GetHull = function() return Vector(-16, -16, 0), Vector(16, 16, 72) end } --[[@as Player]]
                local count = 0
                stub(util, "TraceHull").with(function() count = count + 1 return { Fraction = 1 } end)
                stub(util, "TraceLine").with(function(data)
                    local trace = data --[[@as {start: Vector}]]
                    count = count + 1
                    return { Hit = trace.start.y > -200, HitNormal = Vector(0, 0, 1) }
                end)
                expect(safe(bot, 1, 384)).to.beFalse()
                expect(count <= 17).to.beTrue()
                count = 0
                expect(safe(bot, 1, 513)).to.beFalse()
                expect(count).to.equal(0)
            end
        },
        {
            name = "Dodge proposal: addon recent hit speed corridor chance and shared cooldown; no speculative writes",
            func = function()
                local def = assert(assert(PW.Registries.modules).Get("bots_combat_movement"))
                local target = { IsPlayer = function() return false end } --[[@as Entity]]
                local speed, yaw = 200, 0
                local bot = { Alive = function() return true end, OnGround = function() return true end,
                    IsPlayer = function() return true end,
                    GetMoveType = function() return MOVETYPE_WALK end, WaterLevel = function() return 0 end,
                    GetRunSpeed = function() return 320 end, GetVelocity = function() return Vector(0, speed, 0) end,
                    EyeAngles = function() return Angle(0, yaw, 0) end,
                    Crouching = function() return false end } --[[@as Player]]
                local valid = IsValid
                stub(_G, "IsValid").with(function(value) return value == bot or value == target or valid(value) end)
                local entity = isentity
                stub(_G, "isentity").with(function(value) return value == bot or entity(value) end)
                local tactics = assert(PW.BotTactics)
                stub(tactics, "Random").returns(0)
                local available, clear = true, true
                stub(assert(PW.BotQuickSlide), "Available").with(function() return available end)
                stub(movement(), "Safe").with(function(_, _, distance) return distance <= 96 or clear end)
                local frame = {}
                local board = { bot = bot, _behaviorOwner = frame, intent = { buttons = IN_ATTACK },
                    tactics = { at = 10, pos = Vector(), health = 100, maxHealth = 100, clip = 30,
                        capacity = 30, reserve = 90, reloading = false, lethal = 0, hurtAt = 9.8,
                        profile = tactics.ProfileFor(nil, nil, "veteran"), speed = 200, runSpeed = 320 } }
                local ctx = assert(PW.BotBrain).NewState().ctx
                ctx.bot, ctx.board, ctx.state, ctx.now = bot, board, frame, 10
                local contact = { ent = target, visible = true, pos = Vector(400, 0, 0), vel = Vector(),
                    time = 10, source = "sight" }
                ---@return PW.CombatMovePlan
                local function plan()
                    return assert(PW.Call(def, "Plan", bot, ctx, nil, contact)) --[[@as PW.CombatMovePlan]]
                end
                local launch = plan()
                expect(launch.slideAt).to.equal(10)
                expect(board.intent.slideAt).to.beNil()
                expect(tactics.Marked(board, "tactics.slide", 10)).to.beFalse()
                available = false
                expect(plan().slideAt).to.beNil()
                available, yaw = true, 180
                expect(plan().slideAt).to.beNil()
                yaw, clear = 0, false
                expect(plan().slideAt).to.beNil()
                clear, speed = true, 100
                expect(plan().slideAt).to.beNil()
                speed, board.tactics.hurtAt = 200, 9
                expect(plan().slideAt).to.beNil()
                board.tactics.hurtAt = 9.8
                tactics.CommitSlide(ctx)
                expect(board.intent.slideAt).to.equal(10)
                expect(plan().slideAt).to.beNil()
                local roam = { point = Vector(100, 0, 0), radius = 16, priority = "hunt",
                    status = "moving", since = 9 } --[[@as PW.BotGoal]]
                ctx.board.goal, ctx:Intent().move = roam, Vector(100, 0, 0)
                local acquire = plan()
                expect(acquire.releaseGoal).to.equal(roam)
                expect(acquire.drive ~= nil).to.beTrue()
                expect(ctx.board.goal).to.equal(roam)
            end
        },
        {
            name = "Dodge trajectory: off-axis wall and edge reject launch despite a clear lateral corridor",
            func = function()
                local def = assert(assert(PW.Registries.modules).Get("bots_combat_movement"))
                local target = { IsPlayer = function() return false end } --[[@as Entity]]
                local velocity = Vector(50, 194, 0)
                local bot = { Alive = function() return true end, OnGround = function() return true end,
                    IsPlayer = function() return true end, GetPos = function() return Vector() end,
                    GetMoveType = function() return MOVETYPE_WALK end, WaterLevel = function() return 0 end,
                    GetRunSpeed = function() return 320 end, GetVelocity = function() return velocity * 1 end,
                    EyeAngles = function() return Angle() end, Crouching = function() return false end,
                    GetHull = function() return Vector(-16, -16, 0), Vector(16, 16, 72) end } --[[@as Player]]
                local valid, entity = IsValid, isentity
                stub(_G, "IsValid").with(function(value) return value == bot or value == target or valid(value) end)
                stub(_G, "isentity").with(function(value) return value == bot or entity(value) end)
                local tactics = assert(PW.BotTactics)
                stub(tactics, "Random").returns(0)
                stub(assert(PW.BotQuickSlide), "Available").returns(true)
                stub(assert(PW.BotQuickSlide), "Duration").returns(0.75)
                local obstacle, count = "none", 0
                stub(util, "TraceHull").with(function(data)
                    local trace = data --[[@as {endpos: Vector}]]
                    count = count + 1
                    return { Fraction = obstacle == "wall" and trace.endpos.x > 80 and 0.5 or 1 }
                end)
                stub(util, "TraceLine").with(function(data)
                    local trace = data --[[@as {start: Vector}]]
                    count = count + 1
                    return { Hit = obstacle ~= "edge" or trace.start.x <= 40, HitNormal = Vector(0, 0, 1) }
                end)
                local frame = {}
                local ctx = assert(PW.BotBrain).NewState().ctx
                ctx.bot, ctx.state, ctx.now = bot, frame, 10
                ctx.board = { bot = bot, _behaviorOwner = frame, intent = { buttons = 0 },
                    tactics = { at = 10, pos = Vector(), health = 100, maxHealth = 100, clip = 30,
                        capacity = 30, reserve = 90, reloading = false, lethal = 0, hurtAt = 9.8,
                        profile = tactics.ProfileFor(nil, nil, "veteran"), speed = 200, runSpeed = 320 } }
                local contact = { ent = target, visible = true, pos = Vector(400, 0, 0), vel = Vector(),
                    time = 10, source = "sight" } --[[@as PW.BotContact]]
                ---@return PW.CombatMovePlan
                local function plan()
                    return assert(PW.Call(def, "Plan", bot, ctx, nil, contact)) --[[@as PW.CombatMovePlan]]
                end
                expect(velocity:GetNormalized():Dot(Vector(0, 1, 0)) > 0.95).to.beTrue()
                expect(plan().slideAt).to.equal(10)
                expect(count <= 25).to.beTrue()
                for _, kind in ipairs({ "wall", "edge" }) do
                    obstacle = kind
                    expect(assert(movement().Safe)(bot, -1, 392)).to.beTrue()
                    expect(assert(movement().Safe)(bot, -1, 392, velocity:GetNormalized())).to.beFalse()
                    count = 0
                    local rejected = plan()
                    expect(rejected.drive ~= nil).to.beTrue()
                    expect(rejected.slideAt).to.beNil()
                    expect(count <= 25).to.beTrue()
                end
            end
        },
        {
            name = "Ownership: cleanup removes only the exact drive and slide request written by this visit",
            func = function()
                local lib = movement()
                local plan = lib.Plan(facts(), nil, 0, 0)
                plan.slideAt = 10
                local intent = { buttons = IN_ATTACK, drive = plan.drive, slideAt = 10, sprint = true }
                lib.Release(intent, plan)
                expect(intent.drive).to.beNil()
                expect(intent.slideAt).to.beNil()
                expect(intent.sprint).to.beTrue()
                expect(intent.buttons).to.equal(IN_ATTACK)
                local other = Vector(0, 123, 0)
                intent.drive, intent.slideAt = other, 11
                lib.Release(intent, plan)
                expect(rawequal(intent.drive, other)).to.beTrue()
                expect(intent.slideAt).to.equal(11)
            end
        }
    }
}
