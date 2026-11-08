-- Native counterplay smoke: normal brain, real device perception, CUserCmd writer and unmodified stock bullets.
-- Only the public board accessor supplies the fixture board; no foreign stores or scripted/aim overrides are used.
local key = "PW.SupportNativeTest"
---@type Player[]
local actors = {}
---@type PW.StreaksStore?
local previous

---@return PW.DevicesLib
local function devices() return assert(PW.Devices) end

---@param bot Player
---@param point Vector
local function place(bot, point)
    bot:SetTeam(assert(PW.MatchRules).FreeTeam)
    if not bot:Alive() then bot:Spawn() end
    bot:UnSpectate()
    bot:SetMoveType(MOVETYPE_WALK)
    bot:SetPos(point + Vector(0, 0, 2))
    bot:SetEyeAngles(Angle())
end

---@return Player, PW.SupportDevice
local function fixture()
    local owner = player.CreateNextBot("PW native device owner")
    assert(IsValid(owner), "device smoke needs a free listen-server slot")
    actors[#actors + 1] = owner
    for _, area in ipairs(navmesh.GetAllNavAreas() --[[@as CNavArea[] ]]) do
        if area:GetSizeX() >= 600 and area:GetSizeY() >= 160 then
            place(owner, area:GetCenter())
            if devices().Prepare(owner, "ground_sensor") ~= nil then
                assert(assert(PW.Streaks).Give)(owner, "ground_sensor")
                assert(assert(assert(PW.Streaks).Use)(owner, "ground_sensor"))
                return owner, assert(devices().List()[1])
            end
        end
    end
    error("no broad native-device scene with legal stock placement")
end

return {
    groupName = "PW support native device counterplay",
    beforeEach = function()
        previous = PW._Streaks
        devices().Clear()
        PW._Streaks = assert(assert(PW.Streaks)._NewStore)({
            lookup = function(id) return assert(PW.Registries.streaks).Get(id) --[[@as PW.Streak?]] end,
            phase = function() return "LIVE" end,
            alive = function(ply) return ply:Alive() end,
            publish = function() end
        })
    end,
    afterEach = function()
        hook.Remove("Tick", key)
        hook.Remove("SetupMove", key)
        hook.Remove("EntityFireBullets", key)
        devices().Clear()
        PW._Streaks = previous
        for _, bot in ipairs(actors) do if IsValid(bot) then bot:Kick("native support smoke complete") end end
        actors = {}
    end,
    cases = {
        {
            name = "Device native smoke: legal sight precedes normal usercmd bullets that destroy an enemy sensor",
            async = true,
            timeout = 30,
            func = function()
                local owner, record = fixture()
                local origin = owner:GetPos()
                owner:GodDisable()
                owner:KillSilent()
                expect(IsValid(record.entity)).to.beTrue()
                local bot = player.CreateNextBot("PW native device attacker")
                assert(IsValid(bot), "native device smoke needs a second free slot")
                actors[#actors + 1] = bot
                -- The owner's corpse is behind the device, not between the attacker and its sight line.
                place(bot, origin + Vector(256, 0, 0))
                bot:GodEnable()
                bot:StripWeapons()
                bot:Give("weapon_smg1")
                bot:SetAmmo(225, "SMG1")
                bot:SelectWeapon("weapon_smg1")
                bot:SetEyeAngles((record.entity:WorldSpaceCenter() - bot:EyePos()):Angle())
                local profiles = assert(PW.BotProfiles)
                ---@type PW.BotBoard
                local board = { bot = bot, contacts = {}, memory = {}, intent = { buttons = 0 },
                    difficulty = profiles.Snapshot(profiles.Tier("regular")) }
                board.order = { id = "support_fixture_guard", type = "hold", priority = 1, since = CurTime(),
                    objective = { id = "support_fixture_guard", pos = bot:GetPos(), radius = 8,
                        action = "hold", weight = 1, want = 1 } }
                local bots = assert(PW.Bot)
                local original = assert(bots.Get)
                stub(bots, "Get").with(function(who) if who == bot then return board end return original(who) end)
                local shots, commands, recognized, premature = 0, 0, false, false
                local started, sampled = CurTime(), 0
                hook.Add("SetupMove", key, function(who, _, cmd)
                    if who == bot and bit.band(cmd:GetButtons(), IN_ATTACK) ~= 0 then commands = commands + 1 end
                end)
                hook.Add("EntityFireBullets", key, function(who)
                    if who == bot then
                        shots = shots + 1
                        if assert(PW.BotDevices).Contact(bot) == nil then premature = true end
                    end
                end)
                hook.Add("Tick", key, function()
                    if assert(PW.BotDevices).Contact(bot) ~= nil then recognized = true end
                    if IsValid(record.entity) and CurTime() >= sampled then
                        sampled = CurTime() + 2
                        local eye, point = bot:EyePos(), record.entity:WorldSpaceCenter()
                        local tr = util.TraceLine({ start = eye, endpos = point, filter = bot, mask = MASK_VISIBLE })
                        local fov = assert(PW.BotDevices).Perceivable(eye, bot:GetAimVector(), point, 1800, 110, true)
                        print(string.format("[PW] support probe: phase=%s enemy=%s fov=%s los=%s distance=%.1f",
                            tostring(PW.BotScheduler.GetPhase("devices:" .. bot:UserID())),
                            tostring(PW.IsEnemy(bot, owner)), tostring(fov),
                            tostring(tr.Entity == record.entity or tr.Fraction >= 0.99), eye:Distance(point)))
                    end
                    if IsValid(record.entity) and CurTime() - started < 23 then return end
                    hook.Remove("Tick", key)
                    print(string.format("[PW] support native: sight=%s bullets=%d commands=%d destroyed=%s behavior=%s",
                        tostring(recognized), shots, commands, tostring(not IsValid(record.entity)),
                        board.behavior ~= nil and board.behavior.id or "none"))
                    expect(recognized).to.beTrue()
                    expect(shots > 0).to.beTrue()
                    expect(commands > 0).to.beTrue()
                    expect(premature).to.beFalse()
                    expect(IsValid(record.entity)).to.beFalse()
                    done()
                end)
            end
        }
    }
}
