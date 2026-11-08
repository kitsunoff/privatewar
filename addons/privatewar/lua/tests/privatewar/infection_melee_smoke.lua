-- Installed addon smoke: ordinary perception -> brain -> navigation/aim -> sole CUserCmd writer -> native fists.
-- SetPos is fixture placement only, before measurement; no scripted attack, forced target or injected damage.
local smoke = "PW.InfectionMeleeSmoke"

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
---@return boolean
local function clearPair(a, b)
    local distance = a:Distance2D(b)
    if distance < 400 or distance > 700 or math.abs(a.z - b.z) >= 12 then return false end
    local eye = Vector(0, 0, 64)
    local trace = util.TraceHull({ start = a + eye, endpos = b + eye, mask = MASK_SOLID_BRUSHONLY,
        mins = Vector(-16, -16, -32), maxs = Vector(16, 16, 8) })
    return not trace.Hit
end

---@return Vector?, Vector?
local function spots()
    local areas = navmesh.GetAllNavAreas() --[[@as CNavArea[] ]]
    for i, area in ipairs(areas) do
        local a = area:GetCenter() + Vector(0, 0, 2)
        for j = i + 1, #areas do
            local b = areas[j]:GetCenter() + Vector(0, 0, 2)
            if clearPair(a, b) then return a, b end
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
    end,
    cases = {
        {
            name = "Infection real melee: legal sight pursuit moves into reach"
                .. " and FIRST native hit converts alive without respawn via usercmd",
            skip = absent,
            async = true,
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
                    done()
                end)
            end
        }
    }
}
