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
                .. " and native fists damage twice via usercmd",
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
                -- Fixture only: stationary durable opponent, normal stock fists for the unmodified seed.
                target:SetHealth(1000)
                target:StripWeapons()
                place(seed, must(a), must(b))
                place(target, must(b), must(a))
                must(PW.BotInput).SetScripted(target, { buttons = 0, view = target:EyeAngles() })
                PW._BotsManager.boards[seed] = board(seed)
                local started, initial = CurTime(), seed:GetPos()
                local hits, attackTicks, releaseTicks, movementTicks = 0, 0, 0, 0
                local pursued, native = false, false
                hook.Add("SetupMove", smoke, function(ply, move)
                    if ply ~= seed then return end
                    if bit.band(move:GetButtons(), IN_ATTACK) ~= 0 then attackTicks = attackTicks + 1
                    elseif attackTicks > 0 then releaseTicks = releaseTicks + 1 end
                    if math.abs(move:GetForwardSpeed()) > 0 then movementTicks = movementTicks + 1 end
                end)
                hook.Add("PostEntityTakeDamage", smoke, function(victim, dmg, took)
                    if victim ~= target or dmg:GetAttacker() ~= seed or not took then return end
                    local wep = seed:GetActiveWeapon()
                    native = IsValid(wep) and wep:GetClass() == "weapon_fists"
                    if native and dmg:GetDamage() > 0 then hits = hits + 1 end
                end)
                hook.Add("Tick", smoke, function()
                    local current = must(PW.Bot).Get(seed)
                    if current ~= nil and current.behavior ~= nil
                        and current.behavior.id == "pw_infection_pursuit" then pursued = true end
                    local expired = CurTime() - started >= 24
                    if hits < 2 and not expired then return end
                    hook.Remove("Tick", smoke)
                    hook.Remove("SetupMove", smoke)
                    hook.Remove("PostEntityTakeDamage", smoke)
                    print(string.format("[PW] Infection melee: hits=%d attack=%d release=%d move=%d"
                        .. " travel=%.1f pursuit=%s", hits, attackTicks, releaseTicks, movementTicks,
                        seed:GetPos():Distance(initial), tostring(pursued)))
                    expect(pursued).to.beTrue()
                    expect(movementTicks > 0).to.beTrue()
                    expect(seed:GetPos():Distance(initial) > 200).to.beTrue()
                    expect(attackTicks > 0 and releaseTicks > 0).to.beTrue()
                    expect(native and hits >= 2).to.beTrue()
                    done()
                end)
            end
        }
    }
}
