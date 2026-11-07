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
        PW._BotsManager = state.manager
    end,
    cases = {
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
            func = function(_, done)
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
