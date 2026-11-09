-- Real perception -> utility fight -> optional planner -> sole StartCommand writer; no aim or scripted override.
local key, modeId = "PW.CombatMovementNative", "pwt_combat_movement_native"
local resources = include("privatewar_fixtures/resource_lifecycle.lua") --[[@as PW.TestFixtureResources]]
---@type Player[]
local actors = {}
---@type table<string, string>
local saved = {}
local started = false
---@type number?
local fill

---@param bot Player
---@param pos Vector
---@param yaw number
local function place(bot, pos, yaw)
    bot:SetTeam(assert(PW.MatchRules).FreeTeam)
    bot:Spawn()
    bot:UnSpectate()
    bot:SetMoveType(MOVETYPE_WALK)
    bot:SetPos(pos)
    bot:SetEyeAngles(Angle(0, yaw, 0))
    bot:GodEnable()
    bot:StripWeapons()
    bot:Give("weapon_smg1")
    bot:SelectWeapon("weapon_smg1")
    bot:SetAmmo(300, "SMG1")
end

return {
    groupName = "PW combat movement native",
    afterEach = function()
        hook.Remove("SetupMove", key)
        if started then assert(PW.Match).Abort("combat movement smoke complete") started = false end
        for _, bot in ipairs(actors) do
            PW._BotsManager.boards[bot] = nil
            if IsValid(bot) then bot:Kick("combat movement smoke complete") end
        end
        actors = {}
        assert(PW.Modes).Register({ Name = "Combat movement native", Base = "ffa", Abstract = true }, modeId)
        if fill ~= nil then assert(PW.Settings.Set("bots.fill", fill)) fill = nil end
        for name, value in pairs(saved) do assert(GetConVar(name)):SetString(value) end
        saved = {}
    end,
    cases = {
        {
            name = "Native gm_construct: recognized opponent normal fight both lateral directions and moving fire",
            async = true,
            coroutine = true,
            timeout = 25,
            func = function()
                expect(game.GetMap()).to.equal("gm_construct")
                local match = assert(PW.Match)
                expect(match.GetPhase()).to.equal("LOBBY")
                fill = tonumber(PW.Setting("bots.fill"))
                assert(PW.Settings.Set("bots.fill", 0))
                for _, name in ipairs({ "pw_prematch_timeout", "pw_countdown" }) do
                    local convar = assert(GetConVar(name))
                    saved[name] = convar:GetString()
                    convar:SetString("0")
                end
                assert(PW.Modes).Register({ Name = "Combat movement native", Base = "ffa", Teams = 0,
                    PW_IsEnemy = function(_, a, b)
                        return (a == actors[1] and b == actors[2]) or (a == actors[2] and b == actors[1])
                    end, PW_CanTakeDamage = function() return false end }, modeId)
                assert(match.Start(assert(assert(PW.Modes).Get(modeId))))
                started = true
                while match.GetPhase() ~= "LIVE" do resources.Yield(timer.Simple) end
                local module = assert(assert(PW.Registries.modules).Get("bots_combat_movement"))
                expect(assert(module.IsValid)(module)).to.beTrue()
                ---@type CNavArea?
                local area
                for _, candidate in ipairs(navmesh.GetAllNavAreas() --[[@as CNavArea[] ]]) do
                    if candidate:GetSizeX() >= 1000 and candidate:GetSizeY() >= 1000 then area = candidate break end
                end
                local origin = assert(area, "native combat smoke needs broad ground"):GetCenter() + Vector(0, 0, 4)
                for i = 1, 2 do
                    local bot = player.CreateNextBot("PW combat movement " .. i)
                    assert(IsValid(bot), "native combat movement needs two free slots")
                    actors[i] = bot
                    place(bot, origin + Vector((i - 1) * 400 - 200, 0, 0), (i - 1) * 180)
                end
                local bot = actors[1]
                local profiles = assert(PW.BotProfiles)
                PW._BotsManager.boards[bot] = { bot = bot, contacts = {}, memory = {}, intent = { buttons = 0 },
                    difficulty = profiles.Snapshot(profiles.Tier("veteran")),
                    personality = profiles.Snapshot(assert(assert(PW.BotPersonalities).Get("run_and_gun"))) }
                local left, right, firing, distance, commands = 0, 0, 0, 0, 0
                local initial = bot:GetPos()
                hook.Add("SetupMove", key, function(ply, _, cmd)
                    if ply ~= bot then return end
                    local b = assert(assert(PW.Bot).Get(bot))
                    if b.behavior == nil or b.behavior.id ~= "fight" or b.intent == nil then return end
                    local brain = PW._BotBrain.states[bot]
                    local top = brain ~= nil and brain.stack[#brain.stack] or nil
                    local plan = top ~= nil and top.state.combatMove or nil
                    if plan == nil or not rawequal(plan.drive, b.intent.drive) then return end
                    if b.intent.drive == nil or cmd:GetForwardMove() ~= 0 then return end
                    local side = cmd:GetSideMove()
                    if side < 0 then left = left + 1 elseif side > 0 then right = right + 1 else return end
                    commands = commands + 1
                    if bit.band(cmd:GetButtons(), IN_ATTACK) ~= 0 then firing = firing + 1 end
                    distance = math.max(distance, initial:Distance2D(bot:GetPos()))
                end)
                local untilAt = CurTime() + 15
                while CurTime() < untilAt and not (left > 3 and right > 3 and firing > 0 and distance > 20) do
                    resources.Yield(timer.Simple)
                end
                print(string.format("[PW] combat movement native: left=%d right=%d fire=%d distance=%.1f commands=%d",
                    left, right, firing, distance, commands))
                local b = assert(assert(PW.Bot).Get(bot))
                print("[PW] combat movement native state:", b.behavior and b.behavior.id, #(b.contacts or {}),
                    bot:GetPos(), bot:OnGround(), bot:GetMoveType(), bot:GetObserverMode(),
                    assert(PW.Registries.modules)._DisabledReason("bots_combat_movement"))
                expect(match.GetPhase()).to.equal("LIVE")
                expect(left > 3 and right > 3).to.beTrue()
                expect(firing > 0).to.beTrue()
                expect(distance > 20).to.beTrue()
                expect(bot:GetMoveType()).to.equal(MOVETYPE_WALK)
                done()
            end
        }
    }
}
