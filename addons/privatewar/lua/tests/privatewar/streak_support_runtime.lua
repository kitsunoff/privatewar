-- Real stock entities, ammo/health mutation and native input combat. Fixture placement is not a gameplay teleport.
local key = "PW.SupportRuntimeTest"
---@type Player[]
local actors = {}
---@type PW.StreaksStore?
local previous
---@type PW.SupportDevice[]
local retired = {}

---@return PW.DevicesLib
local function devices() return assert(PW.Devices) end

---@return PW.StreaksLib
local function streaks() return assert(PW.Streaks) end

---@param index integer
---@return Player
local function actor(index)
    if actors[index] ~= nil and IsValid(actors[index]) then return actors[index] end
    local bot = player.CreateNextBot("PW support fixture " .. index)
    assert(IsValid(bot), "a listen server with two free player slots is required")
    actors[index] = bot
    return bot
end

---@param bot Player
---@param point Vector
local function place(bot, point)
    bot:SetTeam(assert(PW.MatchRules).FreeTeam)
    if not bot:Alive() then bot:Spawn() end
    bot:UnSpectate()
    bot:SetMoveType(MOVETYPE_WALK)
    bot:SetPos(point + Vector(0, 0, 2))
    bot:SetEyeAngles(Angle())
    bot:GodEnable()
end

---@return Player, PW.DevicePlacement
local function fixture()
    local owner = actor(1)
    for _, area in ipairs(navmesh.GetAllNavAreas() --[[@as CNavArea[] ]]) do
        if area:GetSizeX() >= 600 and area:GetSizeY() >= 160 then
            place(owner, area:GetCenter())
            local plan = devices().Prepare(owner, "ground_sensor")
            if plan ~= nil and devices().Prepare(owner, "ammo_cache") ~= nil
                and devices().Prepare(owner, "medical_station") ~= nil then return owner, plan end
        end
    end
    error("no clear broad walkable stock-device fixture was found")
end

---@param owner Player
---@param kind PW.SupportDeviceKind
---@return PW.SupportDevice
local function deploy(owner, kind)
    assert(streaks().Give)(owner, kind)
    local accepted = assert(streaks().Use)(owner, kind)
    if not accepted then
        local _, reason = devices().Prepare(owner, kind)
        print("[PW] support deployment refusal: " .. kind .. " reason=" .. tostring(reason)
            .. " enabled=" .. tostring(devices().Enabled(kind)) .. " alive=" .. tostring(owner:Alive()))
    end
    assert(accepted, "deployment refused: " .. kind)
    for _, record in ipairs(devices().List()) do
        if record.owner == owner and record.kind == kind then return record end
    end
    error("successful deployment created no owned resource")
end

---@param record PW.SupportDevice
local function removed(record)
    assert(not IsValid(record.entity) or record.entity:IsMarkedForDeletion(), "owned entity was not retired")
    assert(not record.instance:IsValid(), "activation survived cleanup")
    assert(assert(streaks()._Instances)[record.instance] == nil, "streak owner retained ended activation")
    for name in pairs(record.instance._Timers) do assert(not timer.Exists(name), "instance timer survived cleanup") end
    for _, live in ipairs(devices().List()) do assert(live ~= record, "device registry retained removed resource") end
    retired[#retired + 1] = record
end

---@param complete fun()
local function finish(complete)
    timer.Simple(0.05, function()
        for _, record in ipairs(retired) do
            assert(not IsValid(record.entity), "owned entity survived engine deletion")
        end
        complete()
    end)
end

---@param now number
---@param dt? number
local function maintain(now, dt)
    PW.Call(assert(PW.Modules.GetStored("support_devices")), "Maintain", now, dt or 0.25)
end

local cases = {
    {
        name = "Devices engine: all three visible stock models have physical collision and one hundred health",
        async = true,
        func = function()
            local owner = fixture()
            for _, kind in ipairs({ "ammo_cache", "medical_station", "ground_sensor" }) do
                local record = deploy(owner, kind --[[@as PW.SupportDeviceKind]])
                expect(util.IsValidModel(assert(record.entity:GetModel()))).to.beTrue()
                expect(IsValid(record.entity:GetPhysicsObject())).to.beTrue()
                expect(record.entity:GetSolid()).to.equal(SOLID_VPHYSICS)
                expect(record.entity:Health()).to.equal(100)
                expect(record.ends > CurTime()).to.beTrue()
                devices().Remove(record)
                removed(record)
            end
            finish(done)
        end
    },
    {
        name = "Devices engine: occupied footprint and duplicate kind refuse without spending inventory",
        async = true,
        func = function()
            local owner, plan = fixture()
            local obstacle = ents.Create("prop_physics")
            obstacle:SetModel("models/props_c17/oildrum001.mdl")
            obstacle:SetPos(plan.position + Vector(0, 0, 5))
            obstacle:Spawn()
            assert(streaks().Give)(owner, "ammo_cache")
            local accepted = assert(streaks().Use)(owner, "ammo_cache")
            obstacle:Remove()
            expect(accepted).to.beFalse()
            expect(streaks().Inventory(owner)).to.deepEqual({ "ammo_cache" })
            finish(done)
            expect(assert(streaks().Use)(owner, "ammo_cache")).to.beTrue()
            assert(streaks().Give)(owner, "ammo_cache")
            expect(assert(streaks().Use)(owner, "ammo_cache")).to.beFalse()
            expect(streaks().Inventory(owner)).to.deepEqual({ "ammo_cache" })
        end
    },
    {
        name = "Devices engine: absolute expiry removes entity activation and every instance timer",
        async = true,
        func = function()
            local record = deploy(fixture(), "ground_sensor")
            maintain(record.ends)
            removed(record)
            finish(done)
        end
    },
    {
        name = "Devices engine: death retains allegiance; relationship and disconnect notifications clean resources",
        async = true,
        func = function()
            local owner = fixture()
            local record = deploy(owner, "ground_sensor")
            owner:GodDisable()
            owner:KillSilent()
            maintain(CurTime())
            expect(IsValid(record.entity)).to.beTrue()
            PW.Notify("PW_PlayerTeamChanged", owner, 1, 2, "role_change")
            removed(record)
            place(owner, owner:GetPos())
            record = deploy(owner, "ground_sensor")
            hook.Run("PlayerDisconnected", owner)
            removed(record)
            finish(done)
        end
    },
    {
        name = "Devices engine: round match map and exact-definition disable cleanup retain unused ordinary inventory",
        async = true,
        func = function()
            local owner = fixture()
            local record = deploy(owner, "ammo_cache")
            assert(streaks().Give)(owner, "medical_station")
            PW.Call(assert(PW.Modules.GetStored("streaks")), "PW_RoundPreparing")
            removed(record)
            expect(streaks().Inventory(owner)).to.deepEqual({ "medical_station" })
            finish(done)
            record = deploy(owner, "ground_sensor")
            PW.Notify("PW_EntityDisabled", "streaks", "ground_sensor", record.instance._Definition, "test cleanup")
            removed(record)
            record = deploy(owner, "ground_sensor")
            hook.Run("PreCleanupMap")
            removed(record)
            record = deploy(owner, "ground_sensor")
            PW.Call(assert(PW.Modules.GetStored("support_devices")), "PW_MatchEnd")
            removed(record)
            expect(streaks().Inventory(owner)).to.deepEqual({ "medical_station" })
        end
    },
    {
        name = "Devices disable: exact resolved module cleanup removes resources but not unused inventory",
        async = true,
        func = function()
            local owner = fixture()
            local record = deploy(owner, "ammo_cache")
            assert(streaks().Give)(owner, "medical_station")
            PW.Notify("PW_EntityDisabled", "modules", "support_devices", assert(PW.Modules.Get("teams")), "foreign")
            expect(record.instance:IsValid()).to.beTrue()
            PW.Notify("PW_EntityDisabled", "modules", "support_devices",
                assert(PW.Modules.Get("support_devices")), "test cleanup")
            removed(record)
            expect(streaks().Inventory(owner)).to.deepEqual({ "medical_station" })
            finish(done)
        end
    },
    {
        name = "Device input disable: exact resolved perception module cleanup releases only its owned buttons",
        func = function()
            local bot = actor(1)
            local input = { buttons = bit.bor(IN_ATTACK, IN_RELOAD, IN_DUCK) }
            assert(PW.BotDevices).OwnInput(bot, input)
            PW.Notify("PW_EntityDisabled", "modules", "bots_devices", assert(PW.Modules.Get("teams")), "foreign")
            expect(bit.band(input.buttons, IN_ATTACK) ~= 0).to.beTrue()
            PW.Notify("PW_EntityDisabled", "modules", "bots_devices",
                assert(PW.Modules.Get("bots_devices")), "test cleanup")
            expect(input.buttons).to.equal(IN_DUCK)
        end
    },
    {
        name = "Devices engine: friendly damage is ignored and world destruction awards no support score",
        async = true,
        func = function()
            local owner = fixture()
            local record = deploy(owner, "ground_sensor")
            local awards = 0
            hook.Add("PW_ScoreEvent", key, function() awards = awards + 1 end)
            record.entity:TakeDamage(200, owner, owner)
            expect(record.entity:Health()).to.equal(100)
            record.entity:TakeDamage(200, game.GetWorld(), game.GetWorld())
            removed(record)
            expect(awards).to.equal(0)
            finish(done)
        end
    },
    {
        name = "Cache engine: ordinary reserve refills without clips grenades launchers spawn Give or reward events",
        func = function()
            local owner = fixture()
            owner:StripWeapons()
            local pistol = assert(owner:Give("weapon_pistol"))
            owner:Give("weapon_pw_frag")
            owner:Give("weapon_rpg")
            owner:SetAmmo(0, "Pistol")
            owner:SetAmmo(1, "pw_frag")
            owner:SetAmmo(0, "RPG_Round")
            pistol:SetClip1(3)
            local record = deploy(owner, "ammo_cache")
            local awards = 0
            hook.Add("PW_ScoreEvent", key, function() awards = awards + 1 end)
            stub(assert(PW.WeaponAmmo), "Give").with(function() error("cache called spawn Give") end)
            maintain(CurTime())
            expect(owner:GetAmmoCount("Pistol")).to.equal(18)
            expect(owner:GetAmmoCount("pw_frag")).to.equal(1)
            expect(owner:GetAmmoCount("RPG_Round")).to.equal(0)
            expect(pistol:Clip1()).to.equal(3)
            expect(record.charges).to.equal(9)
            expect(awards).to.equal(0)
            record.pulse = 0
            maintain(CurTime() + 1)
            expect(owner:GetAmmoCount("Pistol")).to.equal(18)
            expect(record.charges).to.equal(9)
        end
    },
    {
        name = "Cache engine: full reserves consume no receipt and capped shared ammo adds only one magazine",
        func = function()
            local owner = fixture()
            owner:StripWeapons()
            local pistol = assert(owner:Give("weapon_pistol"))
            owner:SetAmmo(54, "Pistol")
            -- Weapon creation precedes the final scene placement, just as a settled native loadout does.
            fixture()
            local record = deploy(owner, "ammo_cache")
            maintain(CurTime())
            expect(record.charges).to.equal(10)
            expect(assert(record.receipts)[owner]).to.beNil()
            owner:SetAmmo(50, "Pistol")
            local plan = assert(PW.WeaponAmmo).Resupply(owner, { pistol, pistol }, { fraction = 1, maxMagazines = 3 })
            expect(plan[pistol:GetPrimaryAmmoType()]).to.equal(4)
            expect(owner:GetAmmoCount("Pistol")).to.equal(54)
        end
    },
    {
        name = "Medical engine: four quarter-second steps heal exactly five integer health without overlap farming",
        func = function()
            local owner = fixture()
            deploy(owner, "medical_station")
            owner:SetMaxHealth(100)
            owner:SetHealth(50)
            devices()._Damaged[owner] = CurTime() - 6
            local awards, now = 0, CurTime()
            hook.Add("PW_ScoreEvent", key, function() awards = awards + 1 end)
            for i = 1, 4 do maintain(now + i * 0.25, 0.25) end
            expect(owner:Health()).to.equal(55)
            expect(awards).to.equal(0)
        end
    },
    {
        name = "Cache engine: ten total allied receipts exhaust one shared charge pool without further supply",
        func = function()
            local owner = fixture()
            local ally = actor(2)
            owner:StripWeapons()
            owner:Give("weapon_pistol")
            fixture()
            place(ally, owner:GetPos() + Vector(0, 64, 0))
            ally:StripWeapons()
            ally:Give("weapon_pistol")
            stub(assert(PW.Teams), "GetActive").returns({ 1, 2 })
            hook.Add("PW_IsEnemy", key, function(a, b)
                if (a == owner or a == ally) and (b == owner or b == ally) then return false end
            end)
            local record = deploy(owner, "ammo_cache")
            local now = CurTime()
            for i = 0, 4 do
                owner:SetAmmo(0, "Pistol")
                ally:SetAmmo(0, "Pistol")
                maintain(now + i * 6, 1)
            end
            expect(record.charges).to.equal(0)
            owner:SetAmmo(0, "Pistol")
            ally:SetAmmo(0, "Pistol")
            maintain(now + 30, 1)
            expect(owner:GetAmmoCount("Pistol")).to.equal(0)
            expect(ally:GetAmmoCount("Pistol")).to.equal(0)
        end
    },
    {
        name = "Medical engine: two allied physical stations still apply only the maximum five HP rate",
        func = function()
            local owner = fixture()
            deploy(owner, "medical_station")
            local ally = actor(2)
            place(ally, owner:GetPos() + Vector(0, 64, 0))
            deploy(ally, "medical_station")
            stub(assert(PW.Teams), "GetActive").returns({ 1, 2 })
            hook.Add("PW_IsEnemy", key, function(a, b)
                if (a == owner or a == ally) and (b == owner or b == ally) then return false end
            end)
            owner:SetMaxHealth(100)
            owner:SetHealth(50)
            devices()._Damaged[owner] = CurTime() - 6
            maintain(CurTime(), 1)
            expect(owner:Health()).to.equal(55)
        end
    },
    {
        name = "Medical engine: fresh damage interrupts healing and role prohibition prevents recipient benefit",
        func = function()
            local owner = fixture()
            deploy(owner, "medical_station")
            owner:SetMaxHealth(100)
            owner:SetHealth(50)
            devices()._Damaged[owner] = CurTime()
            maintain(CurTime() + 4, 1)
            expect(owner:Health()).to.equal(50)
            hook.Add("PW_CanUseLoadoutKind", key, function(ply) if ply == owner then return false end end)
            maintain(CurTime() + 6, 1)
            expect(owner:Health()).to.equal(50)
            expect(#devices().List()).to.equal(0)
        end
    }
}

return {
    groupName = "PW support engine resources",
    beforeEach = function()
        previous = PW._Streaks
        retired = {}
        devices().Clear()
        PW._Streaks = assert(streaks()._NewStore)({
            lookup = function(id) return assert(PW.Registries.streaks).Get(id) --[[@as PW.Streak?]] end,
            phase = function() return "LIVE" end,
            alive = function(ply) return ply:Alive() end,
            publish = function() end
        })
    end,
    afterEach = function()
        hook.Remove("PW_ScoreEvent", key)
        hook.Remove("PW_IsEnemy", key)
        hook.Remove("PW_CanUseLoadoutKind", key)
        devices().Clear()
        for _, bot in ipairs(actors) do assert(PW.BotDevices).ReleaseInput(bot) end
        PW._Streaks = previous
    end,
    afterAll = function()
        for _, bot in ipairs(actors) do if IsValid(bot) then bot:Kick("support resource fixtures complete") end end
    end,
    cases = cases
}
