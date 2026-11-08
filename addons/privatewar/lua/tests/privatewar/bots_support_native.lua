-- Native counterplay smoke: normal brain, real device perception, CUserCmd writer and unmodified stock bullets.
-- Only the public board accessor supplies the fixture board; no foreign stores or scripted/aim overrides are used.
local key = "PW.SupportNativeTest"
---@type Player[]
local actors = {}
---@type PW.StreaksStore?
local previous
local modeId = "pwt_support_native"
local matchStarted = false
---@type number?
local previousFill
---@type table<string, string>
local previousVars = {}
---@type PW.BotObjective[]
local guardObjectives = {}
---@type PW.Mode?
local previousMode

---@return PW.Mode
local function sceneMode()
    return { Name = "Support native fixture", Base = "ffa", Teams = 0,
        -- The device-only scene has exactly two participants; ordinary FFA remains unchanged outside this mode.
        PW_IsEnemy = function(_, a, b)
            return a ~= b and ((a == actors[1] and b == actors[2]) or (a == actors[2] and b == actors[1]))
        end,
        PW_CanTakeDamage = function(_, target)
            if target ~= actors[1] and target ~= actors[2] then return false end
        end,
        -- A deployed owner's ordinary FFA respawn would introduce a second, living combat target.
        PW_CanRespawn = function(_, ply) if ply == actors[1] then return false end end,
        BotObjectives = function() return guardObjectives end }
end

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
        previousMode = PW.ActiveMode
        previous = PW._Streaks
        devices().Clear()
        PW._Streaks = assert(assert(PW.Streaks)._NewStore)({
            lookup = function(id) return assert(PW.Registries.streaks).Get(id) --[[@as PW.Streak?]] end,
            phase = function() return assert(PW.Match).GetPhase() end,
            alive = function(ply) return ply:Alive() end,
            publish = function() end
        })
    end,
    afterEach = function()
        timer.Remove(key .. ".live")
        hook.Remove("Tick", key)
        hook.Remove("SetupMove", key)
        hook.Remove("EntityFireBullets", key)
        devices().Clear()
        if matchStarted then
            assert(PW.Match).Abort("native support fixture complete")
            assert(PW.Modes).Register({ Name = "Support native fixture", Base = "ffa", Abstract = true }, modeId)
            matchStarted = false
        end
        if previousFill ~= nil then assert(PW.Settings.Set("bots.fill", previousFill)) previousFill = nil end
        for name, value in pairs(previousVars) do assert(GetConVar(name)):SetString(value) end
        previousVars, guardObjectives = {}, {}
        PW._Streaks = previous
        for _, bot in ipairs(actors) do if IsValid(bot) then bot:Kick("native support smoke complete") end end
        actors = {}
        PW.ActiveMode = previousMode
    end,
    cases = {
        {
            name = "Device native smoke: legal sight precedes normal usercmd bullets that destroy an enemy sensor",
            async = true,
            timeout = 30,
            func = function()
                local function smoke()
                    expect(assert(PW.Match).GetPhase()).to.equal("LIVE")
                    local owner, record = fixture()
                    local origin = owner:GetPos()
                    owner:GodDisable()
                    owner:KillSilent()
                    expect(record.owner).to.equal(owner)
                    expect(PW.Ask("PW_CanRespawn", owner)).to.beFalse()
                    expect(IsValid(record.entity)).to.beTrue()
                    local bot = player.CreateNextBot("PW native device attacker")
                    assert(IsValid(bot), "native device smoke needs a second free slot")
                    actors[#actors + 1] = bot
                    -- The owner's corpse is behind the device, not between the attacker and its sight line.
                    place(bot, origin + Vector(256, 0, 0))
                    expect(PW.IsEnemy(bot, owner)).to.beTrue()
                    for _, other in ipairs(player.GetAll()) do
                        if other ~= bot and other ~= owner then
                            expect(PW.IsEnemy(bot, other)).to.beFalse()
                            expect(PW.IsEnemy(other, bot)).to.beFalse()
                        end
                    end
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
                    guardObjectives[1] = assert(board.order).objective
                    local bots = assert(PW.Bot)
                    local original = assert(bots.Get)
                    stub(bots, "Get").with(function(who)
                        if who == bot then return board end return original(who)
                    end)
                    local shots, commands, recognized, premature = 0, 0, false, false
                    local playerContact = false
                    local started, sampled = CurTime(), 0
                    hook.Add("SetupMove", key, function(who, _, cmd)
                        if who == bot and bit.band(cmd:GetButtons(), IN_ATTACK) ~= 0 then commands = commands + 1 end
                    end)
                    hook.Add("EntityFireBullets", key, function(who)
                        if who ~= bot then return end
                        shots = shots + 1
                        local contact = assert(PW.BotDevices).Contact(bot)
                        if contact == nil or contact.device ~= record then
                            premature = true
                            print("[PW] support unrecognized shot: n=" .. shots .. " retired="
                                .. tostring(record.retired) .. " entity=" .. tostring(IsValid(record.entity)))
                        end
                    end)
                    hook.Add("Tick", key, function()
                        local contact = assert(PW.BotDevices).Contact(bot)
                        if contact ~= nil and contact.device == record then recognized = true end
                        if #(board.contacts or {}) > 0 then playerContact = true end
                        if IsValid(record.entity) and CurTime() >= sampled then
                            sampled = CurTime() + 2
                            local eye, point = bot:EyePos(), record.entity:WorldSpaceCenter()
                            local tr = util.TraceLine({ start = eye, endpos = point, filter = bot,
                                mask = MASK_VISIBLE })
                            local fov = assert(PW.BotDevices).Perceivable(eye, bot:GetAimVector(), point,
                                1800, 110, true)
                            print(string.format("[PW] support probe: phase=%s enemy=%s fov=%s los=%s distance=%.1f",
                                tostring(PW.BotScheduler.GetPhase("devices:" .. bot:UserID())),
                                tostring(PW.IsEnemy(bot, owner)), tostring(fov),
                                tostring(tr.Entity == record.entity or tr.Fraction >= 0.99), eye:Distance(point)))
                            print("[PW] support scene: bot=" .. tostring(bot:GetPos()) .. " device="
                                .. tostring(point) .. " target=" .. tostring(board.target)
                                .. " targetPos=" .. tostring(IsValid(board.target) and board.target:GetPos() or nil))
                            for _, known in ipairs(board.contacts or {}) do
                                print(string.format(
                                    "[PW] support player contact: entity=%s visible=%s source=%s pos=%s",
                                    tostring(known.ent), tostring(known.visible), known.source,
                                    tostring(known.pos)))
                            end
                            for _, human in ipairs(player.GetHumans()) do
                                print("[PW] support host relation: human=" .. tostring(human) .. " enemy="
                                    .. tostring(PW.IsEnemy(bot, human)) .. " pos=" .. tostring(human:GetPos()))
                            end
                        end
                        if IsValid(record.entity) and CurTime() - started < 23 then return end
                        hook.Remove("Tick", key)
                        print(string.format(
                            "[PW] support native: sight=%s bullets=%d commands=%d destroyed=%s behavior=%s"
                                .. " playerContact=%s ownerAlive=%s",
                            tostring(recognized), shots, commands, tostring(not IsValid(record.entity)),
                            board.behavior ~= nil and board.behavior.id or "none",
                            tostring(playerContact), tostring(owner:Alive())))
                        expect(recognized).to.beTrue()
                        expect(shots > 0).to.beTrue()
                        expect(commands > 0).to.beTrue()
                        expect(premature).to.beFalse()
                        expect(IsValid(record.entity)).to.beFalse()
                        expect(playerContact).to.beFalse()
                        expect(owner:Alive()).to.beFalse()
                        done()
                    end)
                end
                expect(assert(PW.Match).GetPhase()).to.equal("LOBBY")
                previousFill = PW.Setting("bots.fill")
                assert(PW.Settings.Set("bots.fill", 0))
                for _, name in ipairs({ "pw_prematch_timeout", "pw_countdown" }) do
                    local convar = assert(GetConVar(name))
                    previousVars[name] = convar:GetString()
                    convar:SetString("0")
                end
                assert(assert(PW.Modes).Register(sceneMode(), modeId))
                matchStarted = true
                assert(assert(PW.Match).Start(assert(assert(PW.Modes).Get(modeId))))
                local deadline = CurTime() + 5
                timer.Create(key .. ".live", 0.05, 0, function()
                    if assert(PW.Match).GetPhase() == "LIVE" then timer.Remove(key .. ".live") smoke()
                    elseif CurTime() >= deadline then error("native support fixture never entered LIVE") end
                end)
            end
        },
        {
            name = "Device native fixture: host is neutral, device owner is hostile, ordinary FFA is unchanged",
            func = function()
                local host = assert(player.GetHumans()[1], "native fixture requires a listen host")
                local function actor()
                    return { Team = function() return assert(PW.MatchRules).FreeTeam end } --[[@as Player]]
                end
                local owner, guard, outsider = actor(), actor(), actor()
                actors = { owner, guard }
                PW.ActiveMode = sceneMode()
                expect(PW.IsEnemy(guard, owner)).to.beTrue()
                expect(PW.IsEnemy(owner, guard)).to.beTrue()
                expect(PW.IsEnemy(guard, guard)).to.beFalse()
                expect(PW.Ask("PW_CanRespawn", owner)).to.beFalse()
                expect(PW.IsEnemy(guard, host)).to.beFalse()
                expect(PW.IsEnemy(host, guard)).to.beFalse()
                expect(PW.IsEnemy(guard, outsider)).to.beFalse()
                expect(PW.IsEnemy(outsider, guard)).to.beFalse()
                expect(PW.Ask("PW_CanTakeDamage", host)).to.beFalse()
                expect(PW.Ask("PW_CanRespawn", host) == false).to.beFalse()
                expect(PW.Ask("PW_CanRespawn", guard) == false).to.beFalse()
                PW.ActiveMode = assert(assert(PW.Modes).Get("ffa"))
                expect(PW.IsEnemy(guard, host)).to.beTrue()
                expect(PW.IsEnemy(host, guard)).to.beTrue()
                expect(PW.IsEnemy(guard, owner)).to.beTrue()
                expect(PW.IsEnemy(guard, guard)).to.beFalse()
                expect(PW.Ask("PW_CanRespawn", owner)).to.beTrue()
                expect(PW.Ask("PW_CanTakeDamage", host) == false).to.beFalse()
            end
        }
    }
}
