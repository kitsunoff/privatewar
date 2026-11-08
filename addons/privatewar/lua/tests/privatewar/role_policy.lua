-- Generic owner revocation and admission, mandatory even without the optional Infection source.
local listener = "PW_Test_RolePolicy"

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected implemented role policy API")
    return value
end

---@return Player, table<string, any>
local function actor()
    local d = { stripped = {} --[[@as table<string, boolean>]], ammo = {} --[[@as table<string, integer>]],
        cooked = 10, given = 0 }
    local grenade = { IsValid = function() return true end,
        SetDTFloat = function(_, _, value) d.cooked = value end } --[[@as Weapon]]
    return { IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return false end, Alive = function() return true end,
        EntIndex = function() return 1 end, GetPos = function() return Vector() end,
        EyePos = function() return Vector() end, GetAimVector = function() return Vector(1, 0, 0) end,
        GetVelocity = function() return Vector() end, EyeAngles = function() return Angle() end,
        GetWeapon = function() return grenade end, HasWeapon = function() return false end,
        Give = function() d.given = d.given + 1 end,
        StripWeapon = function(_, class) d.stripped[class] = true end,
        SetAmmo = function(_, n, ammo) d.ammo[ammo] = n end,
        GetNW2Bool = function() return false end } --[[@as Player]], d
end

return {
    groupName = "PW generic role policy",
    beforeEach = function(state)
        state.perks, state.equipment, state.streaks = PW._Perks, PW._Equipment, PW._Streaks
        state.mode, state.jip, state.instances = PW.ActiveMode, PW._Jip, must(PW.Streaks)._Instances
        state.reveal = PW._Reveal
        state.throwables = PW._Throwables
        state.manager = PW._BotsManager
        state.ended = 0
        PW.ActiveMode = nil
        must(PW.Streaks)._Instances = {}
    end,
    afterEach = function(state)
        hook.Remove("PW_CanUseLoadoutKind", listener)
        hook.Remove("PW_CanJoinInProgress", listener)
        for instance in pairs(must(PW.Streaks)._Instances) do instance:Remove() end
        if PW._Equipment ~= state.equipment then
            for ply in pairs(must(PW._Equipment).players) do must(must(PW.Equipment)._Clear)(ply) end
        end
        PW._Perks, PW._Equipment, PW._Streaks = state.perks, state.equipment, state.streaks
        PW.ActiveMode, PW._Jip, must(PW.Streaks)._Instances = state.mode, state.jip, state.instances
        PW._Reveal = state.reveal
        PW._Throwables = state.throwables
        PW._BotsManager = state.manager
        if state.wildcards ~= nil then PW._Wildcards = state.wildcards end
    end,
    cases = {
        {
            name = "Revocation: equipment owner forwards projectile cleanup even when held equipment was already spent",
            func = function()
                local lib, ply = must(PW.Equipment), actor()
                ---@type Player[]
                local revoked = {}
                PW._Equipment = must(lib._NewStore)({ publish = function() end })
                stub(must(PW.Throwables), "Revoke").with(function(owner) revoked[#revoked + 1] = owner end)
                must(lib.Revoke)(ply)
                expect(revoked).to.deepEqual({ ply })
            end
        },
        {
            name = "Role restriction: loadout owner releases forbidden cached wildcards on a team transition",
            func = function(state)
                local lib, ply = must(PW.Loadout), actor()
                state.wildcards = PW._Wildcards
                PW._Wildcards = {}
                must(lib._EquipWildcards)(ply, { wildcard = "role_fixture" }, function() return {} end)
                expect(PW._Wildcards[ply]).to.exist()
                hook.Add("PW_CanUseLoadoutKind", listener, function(_, kind)
                    if kind == "wildcards" then return false end
                end)
                PW.Notify("PW_PlayerTeamChanged", ply, 1, 2, "role_change")
                expect(PW._Wildcards[ply]).to.beNil()
            end
        },
        {
            name = "Revocation: projectile owner removes only its grenades and an old fuse cannot detonate after reset",
            func = function()
                local lib, ply, other = must(PW.Throwables), actor(), actor()
                local valid, exploded = true, 0
                local ent = { IsValid = function() return valid end, SetPos = function() end,
                    SetAngles = function() end, SetOwner = function() end, Spawn = function() end,
                    GetOwner = function() return ply end, GetPhysicsObject = function() return NULL end,
                    Remove = function() valid = false end } --[[@as Entity]]
                local unrelated = { IsValid = function() return true end,
                    GetOwner = function() return other end, Remove = function() error("wrong owner") end }
                ---@type fun()?
                local fuse
                PW._Throwables = { live = { [unrelated] = true } }
                stub(ents, "Create").with(function() return ent end)
                stub(util, "TraceLine").with(function() return { Hit = false } end)
                stub(_G.timer, "Simple").with(function(_, callback) fuse = callback end)
                expect(must(lib.Throw)(ply, "prop_physics", { fuse = 1,
                    detonate = function() exploded = exploded + 1 end })).to.equal(ent)
                must(lib.Revoke)(ply)
                expect(valid).to.beFalse()
                expect(must(PW._Throwables).live[unrelated]).to.beTrue()
                valid = true -- even an adversarial stand-in cannot make the old generation live again
                local oldFuse = must(fuse)
                oldFuse()
                expect(exploded).to.equal(0)
                expect(must(PW._Throwables).live[ent]).to.beNil()
                expect(must(lib.Throw)(ply, "prop_physics", { fuse = 1,
                    detonate = function() exploded = exploded + 1 end })).to.equal(ent)
                local generation = must(PW._Throwables).live[ent]
                oldFuse() -- reusing the same stand-in must not detonate or remove a new live generation
                expect(exploded).to.equal(0)
                expect(must(PW._Throwables).live[ent]).to.equal(generation)
                must(fuse)()
                expect(exploded).to.equal(1)
            end
        },
        {
            name = "Quota admission: only the manager owner reports pending departures before next-round rosters",
            func = function()
                local lib, ply = must(PW.BotsManager), actor()
                PW._BotsManager = must(lib._NewStore)()
                expect(must(lib.IsLeaving)(ply)).to.beFalse()
                PW._BotsManager.kicking[ply] = true
                expect(must(lib.IsLeaving)(ply)).to.beTrue()
            end
        },
        {
            name = "Revocation: ending one owner removes its jam and radar pulse but replays another owner's pulse",
            func = function()
                local lib, owner, other, viewer, target = must(PW.Streaks), actor(), actor(), actor(), actor()
                local sent, resets = 0, 0
                PW._Reveal = must(lib._NewRevealStore)({ clock = function() return 10 end,
                    isEnemy = function() return true end, players = function() return { viewer } end,
                    members = function() return { viewer } end, stimulus = function() end,
                    send = function() sent = sent + 1 end, jamSend = function() end,
                    reset = function() resets = resets + 1 end })
                must(PW.Reveal)(viewer, { target }, 5, owner)
                must(PW.Reveal)(viewer, { target }, 5, other)
                expect(sent).to.equal(2)
                must(lib.Jam)(owner, 20)
                must(lib.EndEffects)(owner)
                expect(must(PW._Reveal).jams).to.deepEqual({})
                expect(resets).to.equal(1)
                expect(sent).to.equal(3) -- only the still-active other source was replayed
            end
        },
        {
            name = "Quota: managed midround joins never create or kick; preparation reconciles waiting humans once",
            func = function()
                local lib = must(PW.BotsManager)
                local host, waiting, bot = actor(), actor(), actor()
                local created, kicked = 0, 0
                local entries = { { ent = host, team = 1, bot = false, id = 1 },
                    { ent = waiting, team = TEAM_SPECTATOR, bot = false, id = 2, spectating = true },
                    { ent = bot, team = 2, bot = true, id = 3 } }
                PW._BotsManager = must(lib._NewStore)({ players = function() return entries end,
                    create = function() created = created + 1 return NULL end,
                    kick = function() kicked = kicked + 1 end, phase = function() return "LIVE" end,
                    fill = function() return 2 end, maxPlayers = function() return 12 end,
                    teams = function() return 2 end, singlePlayer = function() return false end,
                    generating = function() return false end })
                PW.ActiveMode = { TeamPolicy = "managed", Teams = 2 }
                expect({ must(lib._Step)(PW._BotsManager) }).to.deepEqual({ 0, 0 })
                expect({ must(lib._OnHumanJoined)(PW._BotsManager) }).to.deepEqual({ 0, 0 })
                expect({ created, kicked }).to.deepEqual({ 0, 0 })
                PW.Call(must(PW.Modules.Get("bots_manager")), "PW_RoundPreparing", 2, false)
                expect({ created, kicked }).to.deepEqual({ 0, 1 })
                must(lib._Step)(PW._BotsManager)
                expect(kicked).to.equal(1)
            end
        },
        {
            name = "Revocation: perks end only owner instances, recompute stats and reject denied re-equip",
            func = function()
                local ended = 0
                local lib, ply, other = must(PW.Perks), actor(), actor()
                local def = { ClassName = "test_role_perk", Name = "Role test", Group = 1,
                    Stats = { reload_time = 0.5 }, OnUnequip = function() ended = ended + 1 end }
                PW._Perks = must(lib._NewStore)({ lookup = function() return def end, send = function() end })
                lib.Refresh(ply, { perk1 = "test_role_perk" })
                lib.Refresh(other, { perk1 = "test_role_perk" })
                expect(#lib.Get(ply)).to.equal(1)
                must(lib.Revoke)(ply)
                expect(ended).to.equal(1)
                expect(lib.Get(ply)).to.deepEqual({})
                expect(#lib.Get(other)).to.equal(1)
                hook.Add("PW_CanUseLoadoutKind", listener, function(who, kind)
                    if who == ply and kind == "perks" then return false end
                end)
                lib.Refresh(ply, { perk1 = "test_role_perk" })
                expect(lib.Get(ply)).to.deepEqual({})
                must(lib.Revoke)(other)
            end
        },
        {
            name = "Revocation: equipment clears cooking SWEP ammo inventory and refuses lazy re-equip or use",
            func = function()
                local ended = 0
                local lib = must(PW.Equipment)
                local ply, d = actor()
                local def = { ClassName = "test_role_grenade", Name = "Role grenade", Count = 1,
                    Weapon = "weapon_pw_frag", OnUse = function() return true end,
                    OnUnequip = function() ended = ended + 1 end }
                PW._Equipment = must(lib._NewStore)({ lookup = function() return def end,
                    resolve = function() return { lethal = "test_role_grenade" } end,
                    publish = function() end, phase = function() return "LIVE" end })
                must(lib._OnSpawn)(ply)
                expect(lib.Count(ply, "lethal")).to.equal(1)
                must(lib.Revoke)(ply)
                expect(ended).to.equal(1)
                expect(lib.Item(ply, "lethal")).to.beNil()
                expect(d.stripped.weapon_pw_frag).to.beTrue()
                expect(d.cooked).to.equal(0)
                hook.Add("PW_CanUseLoadoutKind", listener, function() return false end)
                expect(must(lib.Use)(ply, "lethal")).to.beFalse()
                expect(lib.Count(ply, "lethal")).to.equal(0)
                must(lib._GiveWeapons)(ply)
                expect(d.given).to.equal(0)
            end
        },
        {
            name = "Revocation: delayed equipment grants cannot cross revoke and replacement generation",
            async = true,
            timeout = 2,
            func = function()
                local lib, ply = must(PW.Equipment), actor()
                PW._Equipment = must(lib._NewStore)({ lookup = function() return nil end,
                    resolve = function() return {} end, publish = function() end,
                    phase = function() return "LIVE" end })
                must(lib._OnSpawn)(ply)
                local grants = 0
                stub(lib, "_GiveWeapons").with(function() grants = grants + 1 end)
                PW.Call(must(PW.Modules.Get("equipment")), "PW_LoadoutGiven", ply, {})
                must(lib.Revoke)(ply)
                must(lib._OnSpawn)(ply) -- a new life before the old zero-delay callback
                timer.Simple(0.05, function()
                    expect(grants).to.equal(0)
                    done()
                end)
            end
        },
        {
            name = "Revocation: streak owner effects end but unrelated effects and unused inventory survive EndEffects",
            func = function()
                local ended = 0
                local lib, ply, other = must(PW.Streaks), actor(), actor()
                local def = { ClassName = "test_role_streak", Name = "Role streak", Kills = 1, Duration = 30,
                    OnUnequip = function() ended = ended + 1 end }
                PW._Streaks = must(lib._NewStore)({ lookup = function() return def end,
                    phase = function() return "LIVE" end, publish = function() end })
                expect(must(lib.Give)(ply, "test_role_streak")).to.beTrue()
                expect(must(lib.Use)(ply, "test_role_streak")).to.beTrue()
                must(lib.Give)(ply, "test_role_streak")
                must(lib.Give)(other, "test_role_streak")
                must(lib.Use)(other, "test_role_streak")
                must(lib.EndEffects)(ply)
                expect(ended).to.equal(1)
                expect(lib.Inventory(ply)).to.deepEqual({ "test_role_streak" })
                must(lib.Revoke)(ply)
                expect(lib.Inventory(ply)).to.deepEqual({})
                expect(lib.Progress(ply)).to.equal(0)
                expect(lib.Set(ply)).to.deepEqual({})
                hook.Add("PW_CanUseLoadoutKind", listener, function(who, kind)
                    if who == ply and kind == "streaks" then return false end
                end)
                expect(must(lib.Give)(ply, "test_role_streak")).to.beFalse()
                expect(must(lib._OnScore)(ply, "kill", 100)).to.deepEqual({})
                expect(must(lib.Use)(ply, "test_role_streak")).to.beFalse()
                expect(ended).to.equal(1)
            end
        },
        {
            name = "Admission: mode holds humans and bots, explicit admit cancels deferred park without spawning",
            func = function()
                local lib, ply = must(PW.Jip), actor()
                local parks, unparked, deferred = 0, 0, function() end
                PW._Jip = must(lib._NewStore)({ phase = function() return "LIVE" end,
                    enabled = function() return true end, isHuman = function() return false end,
                    park = function() parks = parks + 1 end, unpark = function() unparked = unparked + 1 end,
                    mark = function() end, defer = function(fn) deferred = fn end })
                hook.Add("PW_CanJoinInProgress", listener, function() return false end)
                expect(must(lib._OnJoin)(PW._Jip, ply)).to.equal("spectate")
                expect(must(lib._CanRespawn)(PW._Jip, ply)).to.beFalse()
                must(lib._OnSpawn)(PW._Jip, ply)
                expect(must(lib.Admit)(ply)).to.beTrue()
                deferred()
                expect({ parks, unparked }).to.deepEqual({ 0, 1 })
                expect(must(lib.Admit)(ply)).to.beFalse()
                expect(must(lib._CanRespawn)(PW._Jip, ply)).to.beTrue()
            end
        }
    }
}
