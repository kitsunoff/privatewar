-- Installed addon smoke: ordinary perception -> brain -> navigation/aim -> sole CUserCmd writer -> native fists.
-- SetPos is fixture placement only, before measurement; no scripted attack, forced target or injected damage.
local smoke = "PW.InfectionMeleeSmoke"
local resources = include("privatewar_fixtures/resource_lifecycle.lua") --[[@as PW.TestFixtureResources]]
local survivorFixture = include("privatewar_fixtures/infection_survivor.lua") --[[@as PW.TestInfectionSurvivor]]

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "installed Infection smoke dependency is missing")
    return value
end

---@return boolean
local function absent() return not file.Exists("privatewar/types/pw_infection.lua", "LUA") end

---@param a Vector
---@param b Vector
---@param min? number
---@param max? number
---@return boolean
local function clearPair(a, b, min, max)
    local distance = a:Distance2D(b)
    if distance < (min or 400) or distance > (max or 700) or math.abs(a.z - b.z) >= 12 then return false end
    local eye = Vector(0, 0, 64)
    local trace = util.TraceHull({ start = a + eye, endpos = b + eye, mask = MASK_SOLID_BRUSHONLY,
        mins = Vector(-16, -16, -32), maxs = Vector(16, 16, 8) })
    return not trace.Hit
end

---Fixture geometry only: choose an open, supported retreat lane instead of a roof edge with no legal exit.
---@param a Vector
---@param b Vector
---@return boolean
local function escapeLane(a, b)
    local away = b - a
    away.z = 0
    away:Normalize()
    local finish = b + away * 384
    local up = Vector(0, 0, 2)
    if util.TraceHull({ start = b + up, endpos = finish + up, mask = MASK_SOLID_BRUSHONLY,
        mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 64) }).Hit then return false end
    for step = 1, 4 do
        local point = b + away * (step * 96)
        if navmesh.GetNavArea(point + Vector(0, 0, 16), 96) == nil then return false end
        local ground = util.TraceLine({ start = point + Vector(0, 0, 16),
            endpos = point - Vector(0, 0, 32), mask = MASK_SOLID_BRUSHONLY })
        if not ground.Hit or ground.HitNormal.z < 0.7 then return false end
    end
    return true
end

---@return Vector?, Vector?
---@param min? number
---@param max? number
---@param retreat? boolean
local function spots(min, max, retreat)
    local areas = navmesh.GetAllNavAreas() --[[@as CNavArea[] ]]
    for i, area in ipairs(areas) do
        local a = area:GetCenter() + Vector(0, 0, 2)
        for j = i + 1, #areas do
            local b = areas[j]:GetCenter() + Vector(0, 0, 2)
            if clearPair(a, b, min, max) and (not retreat or escapeLane(a, b)) then return a, b end
        end
    end
    return nil, nil
end

---@param bot Player
---@return PW.BotBoard
local function board(bot)
    local profiles = must(PW.BotProfiles)
    return { bot = bot, team = bot:Team(), difficulty = profiles.Snapshot(profiles.Tier("regular")),
        contacts = {}, memory = {}, intent = { buttons = 0 } }
end

---@param mode PW.InfectionMode
---@param bots Player[]
local function begin(mode, bots)
    mode:Start()
    assert(must(PW.Infection).State ~= nil, "Infection failed to start")
    for _, bot in ipairs(bots) do must(PW.MatchRules).Spawn(bot) end
    mode:Think()
end

---@param bot Player
---@param point Vector
---@param toward Vector
local function place(bot, point, toward)
    bot:GodDisable()
    bot:SetPos(point)
    bot:SetEyeAngles(Angle(0, (toward - point):Angle().y, 0))
end

return {
    groupName = "PW Infection native melee smoke",
    beforeEach = function(state)
        state.mode = PW.ActiveMode
        state.infection = PW.Infection ~= nil and PW.Infection.State or nil
        state.bots = {} --[[@as Player[] ]]
    end,
    afterEach = function(state)
        hook.Remove("Tick", smoke)
        hook.Remove("SetupMove", smoke)
        hook.Remove("PostEntityTakeDamage", smoke)
        hook.Remove("PW_CanTakeDamage", smoke)
        hook.Remove("PlayerSpawn", smoke)
        hook.Remove("PlayerDeath", smoke)
        local bots = state.bots --[[@as Player[] ]]
        if PW.ActiveMode ~= state.mode and PW.ActiveMode ~= nil then PW.Call(PW.ActiveMode, "Cleanup") end
        for _, bot in ipairs(bots) do
            if IsValid(bot) then
                must(PW.BotInput).SetScripted(bot, nil)
                PW._BotsManager.boards[bot] = nil
                bot:Kick("Infection melee smoke complete")
            end
        end
        PW.ActiveMode = state.mode
        if PW.Infection ~= nil then PW.Infection.State = state.infection end
        local deadline, remaining = CurTime() + 5, false
        repeat
            resources.Yield(timer.Simple)
            remaining = false
            for _, bot in ipairs(bots) do if IsValid(bot) then remaining = true end end
        until not remaining or CurTime() >= deadline
        assert(not remaining, "Infection smoke owned players did not disconnect")
    end,
    cases = {
        {
            name = "Infection real melee: legal sight pursuit moves into reach"
                .. " and FIRST native hit converts alive without respawn via usercmd",
            skip = absent,
            coroutine = true,
            timeout = 30,
            func = function(state)
                expect(game.GetMap()).to.equal("gm_construct")
                local a, b = spots()
                expect(a).to.exist()
                expect(b).to.exist()
                local bots = state.bots --[[@as Player[] ]]
                for _, name in ipairs({ "PW Infection seed", "PW Infection target" }) do
                    local bot = player.CreateNextBot(name) --[[@as Player?]]
                    expect(IsValid(bot)).to.beTrue()
                    bots[#bots + 1] = must(bot)
                end
                local mode = setmetatable({ IsValid = function() return true end, Setting = function(_, key)
                    return key == "rounds" and 1 or (key == "intermission" and 5 or 120)
                end }, { __index = must(PW.Modes.Get("pw_infection")) }) --[[@as PW.InfectionMode]]
                PW.ActiveMode = mode
                stub(player, "GetAll").with(function() return bots end)
                stub(must(PW.Match), "GetPhase").with(function() return "LIVE" end)
                begin(mode, bots)
                local seed = must(PW.Infection).Role(bots[1]) == "infected" and bots[1] or bots[2]
                local target = seed == bots[1] and bots[2] or bots[1]
                -- The former two-damage-hit premise is superseded by the approved first-contact revision.
                -- Fixture only: stationary ordinary-health opponent, normal stock fists for the unmodified seed.
                target:SetHealth(100)
                target:StripWeapons()
                place(seed, must(a), must(b))
                place(target, must(b), must(a))
                must(PW.BotInput).SetScripted(target, { buttons = 0, view = target:EyeAngles() })
                PW._BotsManager.boards[seed] = board(seed)
                local started, initial = CurTime(), seed:GetPos()
                local hits, attackTicks, releaseTicks, movementTicks = 0, 0, 0, 0
                local spawns, deaths = 0, 0
                local contactPos, contactVelocity, contactView = Vector(), Vector(), Angle()
                local pursued, native = false, false
                local finished = false
                hook.Add("PlayerSpawn", smoke, function(ply) if ply == target then spawns = spawns + 1 end end)
                hook.Add("PlayerDeath", smoke, function(ply) if ply == target then deaths = deaths + 1 end end)
                hook.Add("SetupMove", smoke, function(ply, move)
                    if ply ~= seed then return end
                    if bit.band(move:GetButtons(), IN_ATTACK) ~= 0 then attackTicks = attackTicks + 1
                    elseif attackTicks > 0 then releaseTicks = releaseTicks + 1 end
                    if math.abs(move:GetForwardSpeed()) > 0 then movementTicks = movementTicks + 1 end
                end)
                -- Notification-only observer before the mode's public veto. Cancelled hits need not apply damage.
                hook.Add("PW_CanTakeDamage", smoke, function(victim, attacker, dmg)
                    ---@cast dmg CTakeDamageInfo
                    if victim ~= target or attacker ~= seed then return end
                    local wep = dmg:GetInflictor()
                    native = IsValid(wep) and wep:IsWeapon() and wep:GetClass() == "weapon_fists"
                        and wep:GetOwner() == seed and seed:GetActiveWeapon() == wep
                    if native and dmg:GetDamage() > 0 then
                        hits = hits + 1
                        if hits == 1 then
                            contactPos, contactVelocity, contactView = target:GetPos(), target:GetVelocity(),
                                target:EyeAngles()
                        end
                    end
                end)
                hook.Add("Tick", smoke, function()
                    local current = must(PW.Bot).Get(seed)
                    if current ~= nil and current.behavior ~= nil
                        and current.behavior.id == "pw_infection_pursuit" then pursued = true end
                    local expired = CurTime() - started >= 24
                    if hits < 1 and not expired then return end
                    hook.Remove("Tick", smoke)
                    hook.Remove("SetupMove", smoke)
                    hook.Remove("PostEntityTakeDamage", smoke)
                    hook.Remove("PW_CanTakeDamage", smoke)
                    hook.Remove("PlayerSpawn", smoke)
                    hook.Remove("PlayerDeath", smoke)
                    finished = true
                end)
                while not finished do resources.Yield(timer.Simple) end
                print(string.format("[PW] Infection melee: hits=%d attack=%d release=%d move=%d"
                    .. " travel=%.1f pursuit=%s", hits, attackTicks, releaseTicks, movementTicks,
                    seed:GetPos():Distance(initial), tostring(pursued)))
                expect(pursued).to.beTrue()
                expect(movementTicks > 0).to.beTrue()
                expect(seed:GetPos():Distance(initial) > 200).to.beTrue()
                expect(attackTicks > 0 and releaseTicks > 0).to.beTrue()
                expect(native).to.beTrue()
                expect(hits).to.equal(1)
                expect(must(PW.Infection).Role(target)).to.equal("infected")
                expect(target:Alive()).to.beTrue()
                expect(target:Health()).to.equal(400)
                expect({ spawns, deaths }).to.deepEqual({ 0, 0 })
                expect(target:GetPos():Distance(contactPos) < 1).to.beTrue()
                expect(target:GetVelocity():Distance(contactVelocity) < 1).to.beTrue()
                expect(target:EyeAngles()).to.equal(contactView)
            end
        },
        {
            name = "Infection real survivor: perceived infected triggers distance gain"
                .. " and native gunfire while retreating",
            skip = absent,
            coroutine = true,
            timeout = 30,
            func = function(state)
                expect(game.GetMap()).to.equal("gm_construct")
                local a, b = spots(220, 300, true)
                expect(a).to.exist()
                expect(b).to.exist()
                local bots = state.bots --[[@as Player[] ]]
                for _, name in ipairs({ "PW Infection pressure", "PW Infection survivor" }) do
                    local bot = player.CreateNextBot(name) --[[@as Player?]]
                    expect(IsValid(bot)).to.beTrue()
                    bots[#bots + 1] = must(bot)
                    must(PW.Loadout).SetClass(must(bot), { primary = "weapon_smg1", melee = "weapon_crowbar" })
                end
                local mode = setmetatable({ IsValid = function() return true end, Setting = function(_, key)
                    return key == "rounds" and 1 or (key == "intermission" and 5 or 120)
                end }, { __index = must(PW.Modes.Get("pw_infection")) }) --[[@as PW.InfectionMode]]
                PW.ActiveMode = mode
                stub(player, "GetAll").with(function() return bots end)
                stub(must(PW.Match), "GetPhase").with(function() return "LIVE" end)
                begin(mode, bots)
                local seed = must(PW.Infection).Role(bots[1]) == "infected" and bots[1] or bots[2]
                local survivor = seed == bots[1] and bots[2] or bots[1]
                place(seed, must(a), must(b))
                place(survivor, must(b), must(a))
                -- Stationary opponent is fixture setup; the measured survivor gets no scripted input or forced target.
                must(PW.BotInput).SetScripted(seed, { buttons = 0, view = seed:EyeAngles() })
                PW._BotsManager.boards[survivor] = board(survivor)
                -- Setup only: a cold brain may hunt out of the close-range lane before its first scheduled sight.
                -- Release neutral setup input only after genuine perception; all measured input stays autonomous.
                survivorFixture.Acquire(survivor, seed, function() resources.Yield(timer.Simple) end)
                expect(clearPair(seed:GetPos(), survivor:GetPos(), 220, 300)).to.beTrue()
                expect(must(PW.BotInput).IntentFor(survivor)).to.equal(must(must(PW.Bot).Get(survivor)).intent)
                local started, initial = CurTime(), seed:GetPos():Distance(survivor:GetPos())
                local origin = survivor:GetPos()
                local away = (origin - seed:GetPos()):GetNormalized()
                local farthest, movement, attacks, hits, movingShots = initial, 0, 0, 0, 0
                local retreat = 0
                local escaped, melee = false, false
                local nextSample = started
                local finished = false
                hook.Add("SetupMove", smoke, function(ply, move)
                    if ply ~= survivor then return end
                    local moving = math.abs(move:GetForwardSpeed()) + math.abs(move:GetSideSpeed()) > 1
                    if moving then movement = movement + 1 end
                    if bit.band(move:GetButtons(), IN_ATTACK) ~= 0 then
                        attacks = attacks + 1
                        if moving then movingShots = movingShots + 1 end
                    end
                    local wep = survivor:GetActiveWeapon()
                    if IsValid(wep) and wep:GetClass() ~= "weapon_smg1" then melee = true end
                end)
                hook.Add("PostEntityTakeDamage", smoke, function(victim, damage, took)
                    if victim == seed and damage:GetAttacker() == survivor and took then hits = hits + 1 end
                end)
                hook.Add("Tick", smoke, function()
                    local current = must(PW.Bot).Get(survivor)
                    if current ~= nil and CurTime() >= nextSample then
                        nextSample = CurTime() + 1
                        local intent = current.intent or { buttons = 0 }
                        local seen = 0
                        for _, c in ipairs(current.contacts or {}) do if c.visible then seen = seen + 1 end end
                        print(string.format("[PW] Infection escape sample: t=%.1f dist=%.1f speed=%.1f"
                            .. " action=%s seen=%d target=%s sprint=%s goal=%s", CurTime() - started,
                            seed:GetPos():Distance(survivor:GetPos()), survivor:GetVelocity():Length2D(),
                            current.behavior ~= nil and current.behavior.id or "none", seen,
                            tostring(current.target ~= nil), tostring(intent.sprint),
                            current.goal ~= nil and current.goal.status or "none"))
                    end
                    if current ~= nil and current.behavior ~= nil
                        and current.behavior.id == "pw_infection_escape" then escaped = true end
                    farthest = math.max(farthest, seed:GetPos():Distance(survivor:GetPos()))
                    retreat = math.max(retreat, (survivor:GetPos() - origin):Dot(away))
                    if not (hits > 0 and movingShots > 0 and retreat >= 100)
                        and CurTime() - started < 24 then return end
                    hook.Remove("Tick", smoke)
                    hook.Remove("SetupMove", smoke)
                    hook.Remove("PostEntityTakeDamage", smoke)
                    finished = true
                end)
                while not finished do resources.Yield(timer.Simple) end
                print(string.format("[PW] Infection escape: initial=%.1f farthest=%.1f move=%d attack=%d"
                    .. " movingShots=%d hits=%d retreat=%.1f escape=%s melee=%s", initial, farthest, movement,
                    attacks, movingShots, hits, retreat, tostring(escaped), tostring(melee)))
                expect(escaped).to.beTrue()
                expect(movement > 0 and attacks > 0 and movingShots > 0 and hits > 0).to.beTrue()
                expect(farthest >= initial + 100).to.beTrue()
                expect(retreat >= 100).to.beTrue() -- opponent knockback alone is not survivor movement evidence
                expect(melee).to.beFalse()
                expect(must(PW.Infection).Role(survivor)).to.equal("survivor")
                expect(survivor:Alive()).to.beTrue()
            end
        }
    }
}
