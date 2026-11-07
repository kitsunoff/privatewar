-- Real installed mode/common-round glue over deterministic actor/engine boundaries. No fake registration.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "installed Infection lifecycle is missing")
    return value
end

---@return boolean
local function absent() return not file.Exists("privatewar/types/pw_infection.lua", "LUA") end

---@class PW.InfectionActorFixture
---@field team integer
---@field hp number
---@field max number
---@field walk number
---@field run number
---@field jump number
---@field alive boolean
---@field model string
---@field spawns integer
---@field resolved? PW.Loadout
---@field observer integer
---@field observing Entity

---@param id integer
---@param isBot boolean
---@return Player, PW.InfectionActorFixture
local function actor(id, isBot)
    ---@type PW.InfectionActorFixture
    local d = { team = id % 2 + 1, hp = 100, max = 100, walk = 200, run = 400, jump = 200,
        alive = true, model = "models/player/kleiner.mdl", spawns = 0, observer = OBS_MODE_NONE, observing = NULL }
    return { IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return isBot end, UserID = function() return id end,
        SteamID64 = function() return "76561198000000" .. id end, Nick = function() return "actor" .. id end,
        Team = function() return d.team end, SetTeam = function(_, n) d.team = n end,
        Alive = function() return d.alive end, Health = function() return d.hp end,
        GetObserverMode = function() return d.observer end, GetObserverTarget = function() return d.observing end,
        Spectate = function(_, mode) d.observer = mode end,
        SpectateEntity = function(_, target) d.observing = target end,
        UnSpectate = function() d.observer, d.observing = OBS_MODE_NONE, NULL end,
        Deaths = function() return 0 end,
        SetHealth = function(_, n) d.hp = n end, GetMaxHealth = function() return d.max end,
        SetMaxHealth = function(_, n) d.max = n end,
        GetWalkSpeed = function() return d.walk end, SetWalkSpeed = function(_, n) d.walk = n end,
        GetRunSpeed = function() return d.run end, SetRunSpeed = function(_, n) d.run = n end,
        GetJumpPower = function() return d.jump end,
        GetInfo = function(_, key) return key == "cl_playermodel" and "kleiner" or "1 1 1" end,
        GetModel = function() return d.model end, SetModel = function(_, path) d.model = path end,
        SetPlayerColor = function() end, LookupSequence = function() return 0 end,
        GetNW2Bool = function() return false end, SetNW2Int = function() end,
        GetWeapon = function() return NULL end, StripWeapon = function() end,
        SetAmmo = function() end } --[[@as Player]], d
end

---@class PW.InfectionLifecycleFixture
---@field mode PW.InfectionMode
---@field players Player[]
---@field data table<Player, PW.InfectionActorFixture>
---@field now number
---@field results PW.MatchResult[]
---@field aborts string[]
---@field stubs { Restore: fun(self: table) }[]

---@param stubber fun(tbl: table, key: string): any
---@param rounds integer
---@param count? integer
---@return PW.InfectionLifecycleFixture
local function fixture(stubber, rounds, count)
    local source = must(PW.Modes.Get("pw_infection"))
    local mode = setmetatable({ IsValid = function() return true end, Setting = function(_, key)
        return key == "rounds" and rounds or (key == "intermission" and 1 or 120)
    end }, { __index = source }) --[[@as PW.InfectionMode]]
    ---@type PW.InfectionLifecycleFixture
    local f = { mode = mode, players = {}, data = {}, now = 100, results = {}, aborts = {}, stubs = {} }
    local function bind(tbl, key, callback)
        f.stubs[#f.stubs + 1] = stubber(tbl, key).with(callback)
    end
    for id = 1, count or 2 do
        local ply, data = actor(id, id > 1)
        f.players[#f.players + 1], f.data[ply] = ply, data
    end
    PW.ActiveMode = f.mode
    bind(player, "GetAll", function() return f.players end)
    bind(player, "GetHumans", function() return {} end) -- no fake entity is ever a net recipient
    bind(must(PW.Match), "GetPhase", function() return "LIVE" end)
    bind(must(PW.Match), "Abort", function(reason) f.aborts[#f.aborts + 1] = reason end)
    bind(must(PW.Match), "Finish", function(result) f.results[#f.results + 1] = result end)
    bind(_G, "CurTime", function() return f.now end)
    bind(math, "random", function() return 0 end)
    bind(must(PW.MatchRules), "Spawn", function(ply)
        local d = must(f.data[ply])
        assert(must(PW.Infection).Role(ply) ~= nil, "a playable spawn preceded its role")
        d.hp, d.max, d.walk, d.run, d.alive, d.spawns = 100, 100, 200, 400, true, d.spawns + 1
        d.resolved = must(PW.Loadout).Resolve(ply)
        must(must(PW.Operators).Refresh)(ply)
        PW.Notify("PW_PlayerSpawned", ply)
    end)
    return f
end

---@param f PW.InfectionLifecycleFixture
local function start(f)
    f.mode:Start()
    assert(#f.aborts == 0, table.concat(f.aborts, "; "))
    for _, ply in ipairs(f.players) do must(PW.MatchRules).Spawn(ply) end
    f.mode:Think()
end

local suite = {
    groupName = "PW Infection common lifecycle",
    beforeEach = function(state)
        state.mode, state.infection = PW.ActiveMode, PW.Infection ~= nil and PW.Infection.State or nil
        state.operators = PW._Operators
        local operators = must(PW.Operators)
        PW._Operators = must(operators._NewStore)({ stock = function()
            return { kleiner = "models/player/kleiner.mdl" }
        end, economy = function() return {} end, roll = function() return 0 end,
            teams = function() return 2 end, log = function() end })
    end,
    afterEach = function(state)
        local owned = PW.Infection ~= nil and PW.Infection.State or nil
        local mode = owned ~= nil and owned.mode or PW.ActiveMode
        if mode ~= nil and mode ~= state.mode then PW.Call(mode, "Cleanup") end
        if PW.Infection ~= nil then PW.Infection.State = state.infection end
        PW.ActiveMode = state.mode
        PW._Operators = state.operators
    end,
    cases = {
        {
            name = "Infection disable: actual owner disable clears roles stats and snapshots,"
                .. " unrelated disable does not",
            skip = absent,
            func = function()
                local f = fixture(stub, 3)
                start(f)
                local lib, saved = must(PW.Infection), must(PW.Infection).State
                local owners = { "medals", "pw_infection_rules" }
                ---@type table<string, string>
                local reasons = {}
                for _, id in ipairs(owners) do reasons[id] = PW.Modules._DisabledReason(id) end
                local ok, err = pcall(function()
                    PW.Modules._Disable("medals", "unrelated disable fixture")
                    expect(lib.State).to.equal(saved)
                    PW.Modules._Disable("pw_infection_rules", "addon owner disable fixture")
                    expect(lib.State).to.beNil()
                    expect(lib.Snapshot(f.players[1])).to.beNil()
                    for _, ply in ipairs(f.players) do
                        expect(lib.Role(ply)).to.beNil()
                        expect({ f.data[ply].max, f.data[ply].walk, f.data[ply].run })
                            .to.deepEqual({ 100, 200, 400 })
                    end
                    local revision = lib.Revision
                    PW.Modules._Disable("pw_infection_rules", "duplicate disable fixture")
                    expect(lib.Revision).to.equal(revision)
                end)
                for _, id in ipairs(owners) do
                    if reasons[id] ~= nil then PW.Modules._Disable(id, reasons[id]) else PW.Modules._Enable(id) end
                end
                if not ok then error(err) end
            end
        },
        {
            name = "Infection lifecycle: intermission ends active effects and live equipment"
                .. " without consuming unused streaks",
            skip = absent,
            func = function()
                local f = fixture(stub, 3)
                start(f)
                ---@type table<Player, boolean>
                local effects = {}
                ---@type table<Player, boolean>
                local equipment = {}
                local inventory = 0
                stub(must(PW.Streaks), "EndEffects").with(function(ply) effects[ply] = true end)
                stub(must(PW.Equipment), "Revoke").with(function(ply) equipment[ply] = true end)
                stub(must(PW.Streaks), "Revoke").with(function() inventory = inventory + 1 end)
                f.now = must(must(must(PW.Infection).State).current).deadline
                f.mode:Think()
                for _, ply in ipairs(f.players) do
                    expect(effects[ply]).to.beTrue()
                    expect(equipment[ply]).to.beTrue()
                    expect(f.mode.PW_CanRespawn(f.mode, ply)).to.beFalse()
                    expect(f.mode.PW_CanRunBotInput(f.mode, ply)).to.beFalse()
                end
                expect(inventory).to.equal(0)
                local revision = must(PW.Infection).Revision
                must(PW.Infection).EndRound()
                expect(must(PW.Infection).Revision).to.equal(revision)
            end
        },
        {
            name = "Infection lifecycle: disabled addon owner safely refuses start and ordinary modes remain available",
            skip = absent,
            func = function()
                local f = fixture(stub, 3)
                local owner = "pw_infection_rules"
                local reason = PW.Modules._DisabledReason(owner)
                PW.Modules._Disable(owner, "Infection lifecycle fixture")
                local ok, err = pcall(function()
                    f.mode:Start()
                    expect(#f.aborts).to.equal(1)
                    expect(must(PW.Infection).State).to.beNil()
                    expect(f.mode._Rounds).to.beNil()
                    for _, id in ipairs({ "tdm", "ffa", "dom", "kc" }) do
                        expect(must(PW.Modes.Get(id)):IsValid()).to.beTrue()
                    end
                end)
                if reason ~= nil then PW.Modules._Disable(owner, reason) else PW.Modules._Enable(owner) end
                if not ok then error(err) end
            end
        },
        {
            name = "Infection lifecycle: invalid zombie animation restores all infected ordinary operators"
                .. " and saved choices",
            skip = absent,
            func = function()
                local f = fixture(stub, 3, 3)
                start(f)
                local lib = must(PW.Infection)
                local seed, converted = f.players[1], f.players[2]
                f.data[converted].alive, f.data[converted].hp = false, 0
                lib.Death(converted, seed)
                stub(seed, "LookupSequence").with(function() return -1 end)
                lib.Spawned(seed)
                expect(must(lib.State).zombie).to.beFalse()
                for _, ply in ipairs({ seed, converted }) do
                    expect(f.data[ply].model == "models/player/zombie_classic.mdl").to.beFalse()
                    expect(f.mode.PW_PlayerModelOverride(f.mode, ply)).to.beNil()
                end
            end
        },
        {
            name = "Infection lifecycle: cleanup is idempotent leaves no role policies"
                .. " and new matches do not retain results",
            skip = absent,
            func = function()
                local f = fixture(stub, 1)
                start(f)
                local lib = must(PW.Infection)
                f.now = must(must(lib.State).current).deadline
                f.mode:Think()
                expect(GetGlobal2Bool("pw_infection_results", false)).to.beTrue()
                f.mode:Cleanup()
                f.mode:Cleanup()
                expect(lib.State).to.beNil()
                for _, ply in ipairs(f.players) do
                    expect(lib.Role(ply)).to.beNil()
                    expect(f.mode.PW_PlayerOverrides(f.mode, ply)).to.beNil()
                    expect(f.mode.PW_PlayerModelOverride(f.mode, ply)).to.beNil()
                end
                expect(lib.Snapshot(f.players[1])).to.beNil()
                f.mode.PW_PhaseChange(f.mode, "LOBBY")
                expect(GetGlobal2Bool("pw_infection_results", true)).to.beFalse()
                f.mode:Start()
                expect(GetGlobal2Bool("pw_infection_results", true)).to.beFalse()
                expect(must(lib.State).completed).to.deepEqual({})
                expect(must(lib.State).infections).to.deepEqual({})
            end
        },
        {
            name = "Infection lifecycle: reconnect sees own sealed wins but cannot inherit the previous entity's role",
            skip = absent,
            func = function()
                local f = fixture(stub, 3)
                start(f)
                local lib, survivor = must(PW.Infection), f.players[2]
                f.now = must(must(lib.State).current).deadline
                f.mode:Think()
                lib.Disconnect(survivor)
                local replacement = actor(2, true)
                expect(lib.Role(replacement)).to.beNil()
                local snapshot = must(lib.Snapshot(replacement))
                expect(snapshot.role).to.equal("waiting")
                expect(snapshot.personalWins).to.equal(1)
                expect(snapshot.infected).to.equal(1)
            end
        },
        {
            name = "Infection lifecycle: cleanup then TDM or FFA restores saved class and ordinary relationship policy",
            skip = absent,
            func = function()
                local f = fixture(stub, 1)
                local loadout = must(PW.Loadout)
                for _, ply in ipairs(f.players) do loadout.SetClass(ply, { primary = "weapon_smg1" }) end
                start(f)
                f.mode:Cleanup()
                for _, id in ipairs({ "tdm", "ffa" }) do
                    PW.ActiveMode = must(PW.Modes.Get(id))
                    for _, ply in ipairs(f.players) do
                        expect(loadout.Resolve(ply)).to.deepEqual({ primary = "weapon_smg1" })
                        expect(PW.Ask("PW_PlayerOverrides", ply)).to.beNil()
                        expect(PW.Ask("PW_PlayerModelOverride", ply)).to.beNil()
                        expect(PW.Ask("PW_CanUseLoadoutKind", ply, "equipment") == false).to.beFalse()
                    end
                    expect(must(PW.IsEnemy)(f.players[1], f.players[2])).to.beTrue()
                end
                PW.ActiveMode = f.mode
            end
        },
        {
            name = "Infection lifecycle: JIP and reconnect entities wait, next-round preparation admits them once",
            skip = absent,
            func = function()
                local f = fixture(stub, 3)
                start(f)
                local lib = must(PW.Infection)
                local old = f.players[1]
                lib.Disconnect(old)
                local reconnect, rd = actor(1, false)
                local newcomer, nd = actor(3, false)
                f.players[1], f.data[reconnect] = reconnect, rd
                f.players[3], f.data[newcomer] = newcomer, nd
                expect(lib.Role(reconnect)).to.beNil()
                expect(lib.Role(newcomer)).to.beNil()
                expect(f.mode.PW_CanRespawn(f.mode, reconnect)).to.beFalse()
                expect(f.mode.PW_PlayerLoadout(f.mode, reconnect)).to.deepEqual({})
                lib.Prepare(2)
                expect(lib.Role(reconnect)).to.exist()
                expect(lib.Role(newcomer)).to.exist()
                expect(lib.Role(old)).to.beNil()
                expect(rd.spawns).to.equal(0)
                expect(nd.spawns).to.equal(0)
            end
        },
        {
            name = "Infection lifecycle: pending quota departures are excluded"
                .. " without excluding ordinary unmanaged bots",
            skip = absent,
            func = function()
                local f = fixture(stub, 3, 3)
                local leaving = f.players[3]
                stub(must(PW.BotsManager), "IsLeaving").with(function(ply) return ply == leaving end)
                f.mode:Start()
                expect(must(PW.Infection).Role(leaving)).to.beNil()
                expect(must(PW.Infection).Role(f.players[2])).to.exist()
            end
        },
        {
            name = "Infection lifecycle: world suicide and exact deadline cannot fabricate"
                .. " infection credit or retro wins",
            skip = absent,
            func = function()
                local f = fixture(stub, 1, 3)
                start(f)
                local lib = must(PW.Infection)
                local seed, first, last = f.players[1], f.players[2], f.players[3]
                f.data[first].hp, f.data[first].alive = 0, false
                lib.Death(first, game.GetWorld())
                expect(must(lib.State).infections).to.deepEqual({})
                f.now = must(must(lib.State).current).deadline
                lib.Death(last, seed)
                expect(lib.Role(last)).to.equal("survivor")
                expect(must(lib.State).infections).to.deepEqual({})
                f.mode:Think()
                expect(#f.results).to.equal(1)
                expect(f.results[1].winner).to.equal(last)
                for _, row in ipairs(f.results[1].standings) do
                    if row.id == first then expect(row.score).to.equal(0) end
                end
            end
        },
        {
            name = "Infection lifecycle: 1 and 3 fixed rounds finish once through common loop, no extra spawn or swap",
            skip = absent,
            func = function()
                for _, total in ipairs({ 1, 3 }) do
                    local f = fixture(stub, total)
                    start(f)
                    for round = 1, total do
                        expect(must(must(PW.Infection).State).round).to.equal(round)
                        for _, ply in ipairs(f.players) do expect(f.data[ply].spawns).to.equal(round) end
                        f.now = must(must(must(PW.Infection).State).current).deadline
                        f.mode:Think()
                        if round < total then f.now = f.now + 1 f.mode:Think() end
                    end
                    expect(#f.results).to.equal(1)
                    expect(f.results[1].teams).to.beFalse()
                    f.now = f.now + 1000
                    f.mode:Think()
                    expect(#f.results).to.equal(1)
                    for _, ply in ipairs(f.players) do expect(f.data[ply].spawns).to.equal(total) end
                    f.mode:Cleanup()
                    for i = #f.stubs, 1, -1 do f.stubs[i]:Restore() end
                end
            end
        },
        {
            name = "Infection lifecycle: human and bot role stats match, fists replace only infected"
                .. " and classes survive",
            skip = absent,
            func = function()
                local f = fixture(stub, 3)
                local loadout = must(PW.Loadout)
                for _, ply in ipairs(f.players) do loadout.SetClass(ply, { primary = "weapon_smg1" }) end
                start(f)
                for round = 1, 2 do
                    if round == 2 then
                        must(PW.Infection).Prepare(round)
                        for _, ply in ipairs(f.players) do must(PW.MatchRules).Spawn(ply) end
                    end
                    for _, ply in ipairs(f.players) do
                        local d, role = f.data[ply], must(PW.Infection).Role(ply)
                        expect(d.jump).to.equal(200)
                        if role == "infected" then
                            expect(ply:IsBot()).to.equal(round == 2)
                            expect({ d.hp, d.max }).to.deepEqual({ 400, 400 })
                            expect(math.abs(d.walk - 230) < 1e-6 and math.abs(d.run - 460) < 1e-6).to.beTrue()
                            expect(d.resolved).to.deepEqual({ melee = "weapon_fists" })
                            d.hp = 250
                            must(PW.PlayerOverrides).Refresh(ply)
                            expect(d.hp).to.equal(250)
                        else
                            expect(d.resolved).to.deepEqual({ primary = "weapon_smg1" })
                        end
                    end
                end
                f.mode:Cleanup()
                for _, ply in ipairs(f.players) do
                    expect({ f.data[ply].max, f.data[ply].walk, f.data[ply].run }).to.deepEqual({ 100, 200, 400 })
                    expect(loadout.GetClass(ply)).to.deepEqual({ primary = "weapon_smg1" })
                end
            end
        },
        {
            name = "Infection lifecycle: conversion is once per life, pending infected respawn is not a disconnect win",
            skip = absent,
            func = function()
                local f = fixture(stub, 3, 3)
                start(f)
                local lib = must(PW.Infection)
                local seed, victim = f.players[1], f.players[2]
                local d = f.data[victim]
                d.alive, d.hp = false, 0
                lib.Death(victim, game.GetWorld())
                expect(lib.Role(victim)).to.equal("infected")
                expect(d.team).to.equal(2)
                expect(d.hp).to.equal(0)
                lib.Death(victim, seed)
                expect(must(lib.State).infections).to.deepEqual({})
                expect(f.mode:RoundWinner(false)).to.beNil()
                expect(f.mode.PW_CanRespawn(f.mode, victim)).to.beTrue()
                lib.Disconnect(seed)
                expect(f.mode:RoundWinner(false)).to.beNil() -- converted participant still holds infected presence
                lib.Disconnect(victim)
                expect(f.mode:RoundWinner(false)).to.equal(1)
            end
        },
        {
            name = "Infection lifecycle: missing required owner aborts safely without starting common rounds",
            skip = absent,
            func = function()
                local f = fixture(stub, 3)
                local original = PW.Modules.Get
                stub(PW.Modules, "Get").with(function(id)
                    if id == "player_overrides" then return nil end
                    return original(id)
                end)
                f.mode:Start()
                expect(#f.aborts).to.equal(1)
                expect(must(PW.Infection).State).to.beNil()
                expect(f.mode._Rounds).to.beNil()
                for _, ply in ipairs(f.players) do expect(f.data[ply].spawns).to.equal(0) end
            end
        }
    }
}

return suite
