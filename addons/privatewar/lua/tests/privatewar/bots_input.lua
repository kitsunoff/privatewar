-- T-5.2 bot input writer (TASKS.md, "Mandatory test cases" T-5.2; 07-bots.md d.2, d.3; notes/08 section 6;
-- docs/api/adapter.md "Bot input rules"; docs/api/bots-blackboard.md "Intent"). The intent -> CUserCmd translation
-- is pure (PW.BotInput.Translate over plain data and a per-bot state table), so most cases run it over simulated
-- ticks. One real bot (beforeAll, kicked in afterAll) checks the engine glue: a scripted forward intent moves it.
-- The bots manager stays idle for the whole GLuaTest run (T-5.1), so this bot has no blackboard and is driven only
-- by the scripted intent of this group.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotInputLib
local function lib()
    return must(PW.BotInput)
end

local tick = 1 / 66

---@param over? table<string, any>
---@return PW.InputRules
local function rules(over)
    ---@type table<string, any>
    local result = {
        releaseBetweenShots = true, reloadTap = false, reloadTapMax = 0.3, forbidWithAttack = IN_USE,
        forbidWithReload = IN_USE, noSprintWhileFiring = true, sprintToFire = 0.25, reselectEveryTick = true
    }
    for key, value in pairs(over or {}) do result[key] = value end
    return result --[[@as PW.InputRules]]
end

---TFA values of docs/api/adapter.md "Bot input rules" (notes/08 section 6.4).
---@return PW.InputRules
local function tfaRules()
    return rules({ reloadTap = true, reloadTapMax = 0.3, forbidWithAttack = IN_USE, forbidWithReload = IN_USE })
end

---@param buttons integer
---@param mask integer
---@return boolean
local function has(buttons, mask)
    return bit.band(buttons, mask) ~= 0
end

---Runs ticks of one intent and returns the commands.
---@param intent PW.BotIntent?
---@param inputRules PW.InputRules
---@param count integer
---@param facts? table<string, any>
---@return PW.BotCmd[]
local function run(intent, inputRules, count, facts)
    local state = lib().NewState()
    ---@type PW.BotCmd[]
    local out = {}
    for i = 1, count do
        ---@type PW.BotInputFacts
        local f = { now = 100 + (i - 1) * tick, eye = Angle(0, 0, 0) }
        for key, value in pairs(facts or {}) do (f --[[@as table<string, any>]])[key] = value end
        out[i] = lib().Translate(intent, inputRules, state, f)
    end
    return out
end

---A free yaw for a forward walk: of the four axis yaws at least 45 degrees away from the current view (so the
---view check proves a turn), the one with the longest clear hull trace.
---@param bot Player
---@return number
local function freeYaw(bot)
    local best, bestFraction = 0, -1
    for _, yaw in ipairs({ 0, 90, 180, 270 }) do
        local dir = Angle(0, yaw, 0):Forward()
        local tr = util.TraceHull({
            start = bot:GetPos() + Vector(0, 0, 4), endpos = bot:GetPos() + Vector(0, 0, 4) + dir * 300,
            mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 64), filter = bot
        })
        local turns = math.abs(math.AngleDifference(bot:EyeAngles().y, yaw)) >= 45
        if turns and tr.Fraction > bestFraction then best, bestFraction = yaw, tr.Fraction end
    end
    return best
end

return {
    groupName = "PW bots input",
    beforeAll = function(state)
        -- In LOBBY a new teamless player is a fixed spectator (GM.TeamBased): give it the FFA team and spawn it.
        local bot = player.CreateNextBot("PW input test") --[[@as Player?]]
        state.bot = bot
        if bot ~= nil and IsValid(bot) then
            bot:SetTeam(must(PW.MatchRules).FreeTeam)
            bot:Spawn()
        end
    end,
    afterAll = function(state)
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then
            lib().SetScripted(bot, nil)
            bot:Kick("PW bots input test finished")
        end
    end,
    cases = {
        {
            name = "Mandatory (T-5.2): a scripted intent produces the expected CUserCmd buttons and move values",
            func = function()
                local intent = {
                    buttons = bit.bor(IN_JUMP, IN_SPEED), move = Vector(200, -150, 0), stance = "crouch",
                    view = Angle(10, 90, 0)
                }
                local cmd = run(intent --[[@as PW.BotIntent]], rules(), 1)[1]
                expect(cmd.forward).to.equal(200)
                expect(cmd.side).to.equal(-150)
                expect(cmd.up).to.equal(0)
                expect(cmd.buttons).to.equal(bit.bor(IN_JUMP, IN_SPEED, IN_DUCK, IN_FORWARD, IN_MOVELEFT))
                expect(cmd.angles).to.equal(Angle(10, 90, 0))
                expect(cmd.weapon).to.beNil()
                local back = run({ buttons = 0, move = Vector(-100, 50, 0) }, rules(), 1)[1]
                expect(back.buttons).to.equal(bit.bor(IN_BACK, IN_MOVERIGHT))
                expect(back.forward).to.equal(-100)
                expect(back.side).to.equal(50)
            end
        },
        {
            name = "Mandatory (T-5.2): a scripted intent: attack and plain reload are held, sprint is dropped to fire",
            func = function()
                local auto = rules({ releaseBetweenShots = false })
                for _, cmd in ipairs(run({ buttons = IN_ATTACK }, auto, 5)) do
                    expect(cmd.buttons).to.equal(IN_ATTACK)
                end
                for _, cmd in ipairs(run({ buttons = IN_RELOAD }, rules(), 30)) do
                    expect(cmd.buttons).to.equal(IN_RELOAD)
                end
                local sprintFire = run({ buttons = bit.bor(IN_ATTACK, IN_SPEED), move = Vector(200, 0, 0) }, auto, 2)
                expect(has(sprintFire[1].buttons, IN_SPEED)).to.beFalse()
                expect(has(sprintFire[1].buttons, IN_ATTACK)).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.2): a bot with no intent stands still",
            func = function()
                local cmd = run(nil, rules(), 1, { eye = Angle(5, 45, 0) })[1]
                expect(cmd.buttons).to.equal(0)
                expect(cmd.forward).to.equal(0)
                expect(cmd.side).to.equal(0)
                expect(cmd.up).to.equal(0)
                expect(cmd.angles).to.equal(Angle(5, 45, 0))
                expect(cmd.weapon).to.beNil()
                local empty = run({ buttons = 0 }, rules(), 1, { eye = Angle(1, 2, 0) })[1]
                expect(empty.buttons).to.equal(0)
                expect(empty.forward).to.equal(0)
                expect(empty.angles).to.equal(Angle(1, 2, 0))
            end
        },
        {
            name = "Mandatory (T-5.2): adapter rules: IN_ATTACK is released for a tick between semi-auto shots",
            func = function()
                local cmds = run({ buttons = IN_ATTACK }, rules({ releaseBetweenShots = true }), 6)
                for i, cmd in ipairs(cmds) do
                    expect(has(cmd.buttons, IN_ATTACK)).to.equal(i % 2 == 1)
                end
                -- ADS (IN_ATTACK2) is held, not released
                for _, cmd in ipairs(run({ buttons = bit.bor(IN_ATTACK, IN_ATTACK2) }, rules(), 4)) do
                    expect(has(cmd.buttons, IN_ATTACK2)).to.beTrue()
                end
            end
        },
        {
            name = "Mandatory (T-5.2): adapter rules: the TFA reload tap presses IN_RELOAD shorter than reloadTapMax",
            func = function()
                local tfa = tfaRules()
                local cmds = run({ buttons = IN_RELOAD }, tfa, 60)
                expect(has(cmds[1].buttons, IN_RELOAD)).to.beTrue()
                local pressed = 0
                local released = false
                for _, cmd in ipairs(cmds) do
                    if has(cmd.buttons, IN_RELOAD) then
                        expect(released).to.beFalse() -- one press, never a second one while the intent holds
                        pressed = pressed + 1
                    else
                        released = true
                    end
                end
                expect(released).to.beTrue()
                expect(pressed * tick < tfa.reloadTapMax).to.beTrue()
                -- releasing the intent and pressing again taps again
                local state = lib().NewState()
                local function at(i, buttons)
                    return lib().Translate({ buttons = buttons }, tfa, state, { now = i * tick, eye = Angle() })
                end
                expect(has(at(1, IN_RELOAD).buttons, IN_RELOAD)).to.beTrue()
                expect(has(at(40, IN_RELOAD).buttons, IN_RELOAD)).to.beFalse()
                expect(has(at(41, 0).buttons, IN_RELOAD)).to.beFalse()
                expect(has(at(42, IN_RELOAD).buttons, IN_RELOAD)).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.2): adapter rules: no IN_USE together with attack, ADS or reload",
            func = function()
                for _, cmd in ipairs(run({ buttons = bit.bor(IN_USE, IN_ATTACK) }, rules(), 6)) do
                    expect(has(cmd.buttons, IN_USE)).to.beFalse() -- also on the release ticks of a semi weapon
                end
                local ads = run({ buttons = bit.bor(IN_USE, IN_ATTACK2) }, tfaRules(), 1)[1]
                expect(ads.buttons).to.equal(IN_ATTACK2)
                local reload = run({ buttons = bit.bor(IN_USE, IN_RELOAD) }, tfaRules(), 1)[1]
                expect(reload.buttons).to.equal(IN_RELOAD)
                local arc9 = rules({ forbidWithReload = bit.bor(IN_USE, IN_WALK) })
                local walkReload = run({ buttons = bit.bor(IN_WALK, IN_RELOAD) }, arc9, 1)[1]
                expect(walkReload.buttons).to.equal(IN_RELOAD)
                local useOnly = run({ buttons = IN_USE }, rules(), 1)[1]
                expect(useOnly.buttons).to.equal(IN_USE)
            end
        },
        {
            name = "Adapter rules: after a sprint, attack waits sprintToFire; without noSprintWhileFiring it does not",
            func = function()
                local state = lib().NewState()
                local auto = rules({ releaseBetweenShots = false, sprintToFire = 0.25 })
                local function at(now, buttons)
                    return lib().Translate({ buttons = buttons, move = Vector(200, 0, 0) }, auto, state,
                        { now = now, eye = Angle() })
                end
                expect(has(at(10, IN_SPEED).buttons, IN_SPEED)).to.beTrue()
                local first = at(10.1, bit.bor(IN_SPEED, IN_ATTACK)).buttons
                expect(has(first, IN_SPEED)).to.beFalse()
                expect(has(first, IN_ATTACK)).to.beFalse()
                expect(has(at(10.3, bit.bor(IN_SPEED, IN_ATTACK)).buttons, IN_ATTACK)).to.beTrue()
                local free = run({ buttons = bit.bor(IN_SPEED, IN_ATTACK) },
                    rules({ noSprintWhileFiring = false, releaseBetweenShots = false }), 1)[1]
                expect(free.buttons).to.equal(bit.bor(IN_SPEED, IN_ATTACK))
            end
        },
        {
            name = "Weapon select: kept every tick until active, or once when reselectEveryTick is false",
            func = function()
                local intent = { buttons = 0, weapon = "weapon_smg1" }
                for _, cmd in ipairs(run(intent, rules(), 3, { active = "weapon_pistol" })) do
                    expect(cmd.weapon).to.equal("weapon_smg1")
                end
                local once = run(intent, rules({ reselectEveryTick = false }), 3, { active = "weapon_pistol" })
                expect(once[1].weapon).to.equal("weapon_smg1")
                expect(once[2].weapon).to.beNil()
                expect(once[3].weapon).to.beNil()
                expect(run(intent, rules(), 1, { active = "weapon_smg1" })[1].weapon).to.beNil()
            end
        },
        {
            name = "Rules: missing fields of an adapter's answer fall back to the defaults",
            func = function()
                local filled = lib()._Rules({ reloadTap = true })
                expect(filled.reloadTap).to.beTrue()
                expect(filled.releaseBetweenShots).to.beTrue()
                expect(filled.forbidWithAttack).to.equal(IN_USE)
                expect(lib()._Rules(nil).reselectEveryTick).to.beTrue()
            end
        },
        {
            name = "Glue: the rules come from PW.Adapters.CallFor(weapon, \"GetInputRules\", weapon)",
            func = function()
                local fake = { IsValid = function() return true end }
                ---@type any[]
                local seen = {}
                stub(PW.Adapters, "CallFor").with(function(wep, method, arg)
                    seen = { wep, method, arg }
                    return { reloadTap = true }
                end)
                local got = lib()._RulesFor(fake --[[@as Weapon]])
                expect(seen[1]).to.equal(fake)
                expect(seen[2]).to.equal("GetInputRules")
                expect(seen[3]).to.equal(fake)
                expect(got.reloadTap).to.beTrue()
                expect(got.forbidWithAttack).to.equal(IN_USE)
                expect(lib()._RulesFor(nil).reloadTap).to.beFalse()
            end
        },
        {
            name = "Walking view: each tick steps toward viewTarget by at most viewSpeed * dt and converges",
            func = function()
                local speed = 360 -- degrees per second ('regular' turn_max_speed)
                local maxStep = speed * tick
                local state = lib().NewState()
                local intent = { buttons = 0, viewTarget = Angle(30, 170, 0), viewSpeed = speed }
                local eye = Angle(0, -170, 0) -- the target is 20 degrees away across the seam
                local ticks, maxSeen = 0, 0
                while ticks < 400 do
                    local out = lib().Translate(intent, nil, state, { now = ticks * tick, eye = eye, dt = tick })
                    local dp = math.abs(math.AngleDifference(out.angles.p, eye.p))
                    local dy = math.abs(math.AngleDifference(out.angles.y, eye.y))
                    maxSeen = math.max(maxSeen, dp, dy)
                    eye = out.angles
                    ticks = ticks + 1
                    if math.abs(math.AngleDifference(eye.y, 170)) < 1e-6 and math.abs(eye.p - 30) < 1e-6 then break end
                end
                expect(maxSeen <= maxStep + 1e-6).to.beTrue()
                expect(maxSeen > 0).to.beTrue()
                expect(math.abs(math.AngleDifference(eye.y, 170)) < 1e-6).to.beTrue()
                expect(math.abs(eye.p - 30) < 1e-6).to.beTrue()
                -- Pitch (30 degrees) is the slow axis; yaw takes the short way across the seam.
                expect(ticks <= math.ceil(30 / maxStep) + 1).to.beTrue()
            end
        },
        {
            name = "Walking view: aim-owned intent.view is written as is; without dt the target is ignored",
            func = function()
                local state = lib().NewState()
                local eye = Angle(0, 0, 0)
                local aimed = lib().Translate({ buttons = 0, view = Angle(12, 100, 0) }, nil, state,
                    { now = 0, eye = eye, dt = tick })
                expect(aimed.angles).to.equal(Angle(12, 100, 0))
                local noDt = lib().Translate({ buttons = 0, view = Angle(1, 2, 0), viewTarget = Angle(50, 50, 0),
                    viewSpeed = 360 }, nil, state, { now = 0, eye = eye })
                expect(noDt.angles).to.equal(Angle(1, 2, 0))
            end
        },
        {
            name = "Dev command: fields parse into an intent; clear, stop and bad fields",
            func = function()
                local parsed = must(lib().ParseArgs({ "forward=200", "side=-50", "yaw=90", "pitch=5", "attack",
                    "reload", "crouch", "sprint", "jump", "weapon=weapon_smg1" }))
                local intent = must(parsed.intent)
                expect(must(intent.move).x).to.equal(200)
                expect(must(intent.move).y).to.equal(-50)
                expect(intent.view).to.equal(Angle(5, 90, 0))
                expect(intent.buttons).to.equal(bit.bor(IN_ATTACK, IN_RELOAD, IN_SPEED, IN_JUMP))
                expect(intent.stance).to.equal("crouch")
                expect(intent.weapon).to.equal("weapon_smg1")
                expect(must(lib().ParseArgs({ "clear" })).clear).to.beTrue()
                local stop = must(must(lib().ParseArgs({ "stop" })).intent)
                expect(stop.buttons).to.equal(0)
                expect(stop.move).to.beNil()
                local bad, err = lib().ParseArgs({ "forward=fast" })
                expect(bad).to.beNil()
                expect(err).to.beA("string")
                local none, usage = lib().ParseArgs({})
                expect(none).to.beNil()
                expect(usage).to.beA("string")
                expect(lib().ParseArgs({ "dance" })).to.beNil()
            end
        },
        {
            name = "Dev command: bot names match case-insensitively by substring, * matches every bot",
            func = function()
                expect(lib()._NameMatches("Bot 3", "bot 3")).to.beTrue()
                expect(lib()._NameMatches("Bot 3", "3")).to.beTrue()
                expect(lib()._NameMatches("Bot 3", "*")).to.beTrue()
                expect(lib()._NameMatches("Bot 3", "Bot 4")).to.beFalse()
                expect(lib()._NameMatches("a.b", ".")).to.beTrue()
                expect(lib()._NameMatches("ab", ".")).to.beFalse()
            end
        },
        {
            name = "Mandatory (T-5.2), in game: a scripted forward intent moves a real bot and turns its view",
            async = true,
            timeout = 8,
            func = function(state)
                local bot = must(state.bot) --[[@as Player]]
                expect(bot).to.beValid()
                timer.Simple(0.5, function()
                    local yaw = freeYaw(bot)
                    local start = bot:GetPos()
                    lib().SetScripted(bot, { buttons = 0, move = Vector(400, 0, 0), view = Angle(0, yaw, 0) })
                    timer.Simple(1.5, function()
                        local moved = (bot:GetPos() - start):Dot(Angle(0, yaw, 0):Forward())
                        lib().SetScripted(bot, nil)
                        expect(moved > 30).to.beTrue()
                        expect(math.abs(math.AngleDifference(bot:EyeAngles().y, yaw)) < 1).to.beTrue()
                        done()
                    end)
                end)
            end
        }
    }
}
