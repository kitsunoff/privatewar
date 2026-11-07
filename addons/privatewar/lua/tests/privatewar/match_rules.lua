-- T-2.2 kill -> score -> respawn glue and FFA spawning (module match_rules; 02-modes.md d.6, d.7; 06-progression.md
-- d.3). Pure cases over plain data; glue cases call the module's hook functions with player stand-ins (tables with
-- the methods the glue reads) and PW.Match.GetPhase stubbed, so no bot is created and no real player dies. The last
-- case is the in-game smoke: a real TDM match on the current map with shortened phase ConVars, restored after.
-- Every case restores the stores, PW.ActiveMode, PW.Match.GetPhase and its hooks.

local listenerId = "PW_Test_MatchRules"
local hookNames = { "PW_PlayerKilled", "PW_CanRespawn", "PW_RespawnDelay", "PW_SelectSpawn", "PW_ScoreEvent",
    "PW_MatchEnd" }
local phaseConVars = { "pw_prematch_timeout", "pw_countdown", "pw_postmatch_time", "pw_aftermatch" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.MatchRulesLib
local function rules()
    return must(PW.MatchRules)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@return PW.Module
local function module()
    return must(must(PW.Modules).Get("match_rules")) --[[@as PW.Module]]
end

---Calls one engine hook the module added through PW.HookFor.
---@param name string
---@param ... any
---@return any
local function engineHook(name, ...)
    local entity = module()
    local fn = must(must(entity._EngineHooks)[name])
    return fn(entity, ...)
end

---A player stand-in with the methods the glue and the score module read.
---@param team integer
---@param opts? table<string, any>
---@return Player
local function fakePlayer(team, opts)
    opts = opts or {}
    ---@type table<string, integer>
    local published = {}
    ---@type table<string, any>
    local fake = { team = team, spawns = 0, published = published, hitGroup = opts.hitGroup or HITGROUP_CHEST }
    fake.IsValid = function() return true end
    fake.IsPlayer = function() return true end
    fake.Team = function(self) return self.team end
    fake.SetTeam = function(self, value) self.team = value end
    fake.LastHitGroup = function(self) return self.hitGroup end
    fake.GetActiveWeapon = function() return NULL end
    ---@param _ any
    ---@param key string
    ---@param value integer
    fake.SetNW2Int = function(_, key, value) published[key] = value end
    fake.Spawn = function(self) self.spawns = self.spawns + 1 end
    fake.SetPos = function(self, pos) self.pos = pos end
    fake.SetEyeAngles = function(self, ang) self.ang = ang end
    return fake --[[@as Player]]
end

---A CTakeDamageInfo stand-in: only GetInflictor is read.
---@return CTakeDamageInfo
local function fakeDamage()
    return { GetInflictor = function() return NULL end } --[[@as CTakeDamageInfo]]
end

---@param state table<string, any>
---@param phase string
local function setPhase(state, phase)
    state.phase = phase
end

---@param value any
---@return table<string, any>
local function fields(value)
    return value --[[@as table<string, any>]]
end

return {
    groupName = "PW match rules",
    beforeEach = function(state)
        state.store = PW._MatchRules
        state.scoreStore = PW._Score
        state.activeMode = PW.ActiveMode
        state.getPhase = match().GetPhase
        state.phase = "LIVE"
        PW._MatchRules = rules()._NewStore()
        PW._Score = must(PW.Score)._NewStore()
        match().GetPhase = function() return state.phase end
        PW.ActiveMode = PW.Modes.Get("tdm")
    end,
    afterEach = function(state)
        for _, name in ipairs(hookNames) do hook.Remove(name, listenerId) end
        match().GetPhase = state.getPhase --[[@as fun(): PW.PhaseName]]
        PW._MatchRules = state.store
        PW._Score = state.scoreStore
        PW.ActiveMode = state.activeMode
    end,
    cases = {
        {
            name = "Kill events (pure): enemy kill scores kill, a headshot adds headshot; others score nothing",
            func = function()
                local kill = rules()._KillEvents
                expect(kill({ suicide = false, player = true, enemy = true, headshot = false }))
                    .to.deepEqual({ "kill" })
                expect(kill({ suicide = false, player = true, enemy = true, headshot = true }))
                    .to.deepEqual({ "kill", "headshot" })
                expect(kill({ suicide = false, player = true, enemy = false, headshot = true })).to.deepEqual({})
                expect(kill({ suicide = true, player = true, enemy = false, headshot = false })).to.deepEqual({})
                expect(kill({ suicide = false, player = false, enemy = false, headshot = false })).to.deepEqual({})
            end
        },
        {
            name = "Respawn timing and spawn answers (pure)",
            func = function()
                expect(rules()._RespawnDue(10, nil)).to.beFalse()
                expect(rules()._RespawnDue(10, 10.5)).to.beFalse()
                expect(rules()._RespawnDue(10, 10)).to.beTrue()
                expect(rules()._SpawnTarget({ pos = Vector(1, 2, 3), yaw = 90 })).to.equal("point")
                expect(rules()._SpawnTarget(must(player.GetHumans()[1]))).to.equal("entity")
                expect(rules()._SpawnTarget(NULL)).to.beNil()
                expect(rules()._SpawnTarget({ yaw = 90 })).to.beNil()
                expect(rules()._SpawnTarget("spawn")).to.beNil()
                expect(rules()._SpawnTarget(nil)).to.beNil()
            end
        },
        {
            name = "A death during LIVE fires PW_PlayerKilled; TDM awards kill and headshot and counts the team kill",
            func = function()
                local victim = fakePlayer(2, { hitGroup = HITGROUP_HEAD })
                local attacker = fakePlayer(1)
                local dmg = fakeDamage()
                ---@type table[]
                local killed = {}
                hook.Add("PW_PlayerKilled", listenerId, function(...) killed[#killed + 1] = { ... } end)
                ---@type string[]
                local events = {}
                hook.Add("PW_ScoreEvent", listenerId, function(_, id) events[#events + 1] = id end)
                -- the medals module (T-4.11) also listens: take first blood out of this case
                must(PW._Medals).state.firstBlood = true

                engineHook("DoPlayerDeath", victim, attacker, dmg)

                expect(#killed).to.equal(1)
                expect(killed[1][1]).to.equal(victim)
                expect(killed[1][2]).to.equal(attacker)
                expect(killed[1][3]).to.equal(dmg)
                expect(events).to.deepEqual({ "kill", "headshot" })
                expect(must(PW.Score).Get(attacker)).to.equal(150)
                expect(rules().GetKills(attacker)).to.equal(1)
                expect(rules().GetTeamKills(1)).to.equal(1)
                expect(rules().GetTeamKills(2)).to.equal(0)
                expect(fields(attacker).published[rules()._KillsKey]).to.equal(1)
            end
        },
        {
            name = "Team kills, suicides and world deaths score nothing; outside LIVE nothing fires",
            func = function(state)
                local victim, mate = fakePlayer(1), fakePlayer(1)
                ---@type table[]
                local killed = {}
                hook.Add("PW_PlayerKilled", listenerId, function(...) killed[#killed + 1] = { ... } end)
                engineHook("DoPlayerDeath", victim, mate, fakeDamage())
                engineHook("DoPlayerDeath", victim, victim, fakeDamage())
                engineHook("DoPlayerDeath", victim, game.GetWorld(), fakeDamage())
                expect(#killed).to.equal(3)
                expect(must(PW.Score).Get(mate)).to.equal(0)
                expect(must(PW.Score).Get(victim)).to.equal(0)
                expect(rules().GetTeamKills(1)).to.equal(0)
                setPhase(state, "POSTMATCH")
                engineHook("DoPlayerDeath", victim, fakePlayer(2), fakeDamage())
                expect(#killed).to.equal(3)
            end
        },
        {
            name = "FFA: every other player is an enemy; kills count for the player only",
            func = function()
                PW.ActiveMode = PW.Modes.Get("ffa")
                local free = rules().FreeTeam
                local victim, attacker = fakePlayer(free), fakePlayer(free)
                engineHook("DoPlayerDeath", victim, attacker, fakeDamage())
                expect(rules().GetKills(attacker)).to.equal(1)
                expect(must(PW.Score).Get(attacker)).to.equal(100)
                expect(rules().GetTeamKills(free)).to.equal(0)
            end
        },
        {
            name = "Respawn: after PW_RespawnDelay and only while PW_CanRespawn allows it; the base think is blocked",
            func = function(state)
                local ply = fakePlayer(1)
                hook.Add("PW_RespawnDelay", listenerId, function() return 0 end)
                local allowed = false
                hook.Add("PW_CanRespawn", listenerId, function() return allowed end)
                expect(engineHook("PlayerDeathThink", ply)).to.beTrue()
                expect(fields(ply).spawns).to.equal(0)
                allowed = true
                expect(engineHook("PlayerDeathThink", ply)).to.beTrue()
                expect(fields(ply).spawns).to.equal(1)
                -- A long delay: the first think sets the time, later thinks wait for it.
                hook.Remove("PW_RespawnDelay", listenerId)
                hook.Add("PW_RespawnDelay", listenerId, function() return 30 end)
                local slow = fakePlayer(1)
                engineHook("PlayerDeathThink", slow)
                expect(PW._MatchRules.respawnAt[slow]).to.equal(CurTime() + 30)
                engineHook("PlayerDeathThink", slow)
                expect(fields(slow).spawns).to.equal(0)
                -- Outside LIVE the base gamemode decides.
                setPhase(state, "LOBBY")
                expect(engineHook("PlayerDeathThink", fakePlayer(1))).to.beNil()
            end
        },
        {
            name = "Respawn defaults come from the mode: TDM allows it after its respawn delay",
            func = function()
                local ply = fakePlayer(1)
                engineHook("PlayerDeathThink", ply)
                local tdm = must(PW.Modes.Get("tdm"))
                expect(PW._MatchRules.respawnAt[ply]).to.equal(CurTime() + tdm:Setting("respawndelay"))
            end
        },
        {
            name = "FFA spawning: a teamless player joins the free team on spawn during LIVE; TDM is left alone",
            func = function(state)
                PW.ActiveMode = PW.Modes.Get("ffa")
                local ply = fakePlayer(TEAM_UNASSIGNED)
                PW._MatchRules.respawnAt[ply] = 5
                engineHook("PlayerSpawn", ply)
                expect(ply:Team()).to.equal(rules().FreeTeam)
                expect(PW._MatchRules.respawnAt[ply]).to.beNil()
                local spectator = fakePlayer(TEAM_SPECTATOR)
                engineHook("PlayerSpawn", spectator)
                expect(spectator:Team()).to.equal(rules().FreeTeam)
                expect(rules().FreeTeam ~= TEAM_SPECTATOR and rules().FreeTeam ~= TEAM_UNASSIGNED).to.beTrue()
                expect(team.Valid(rules().FreeTeam)).to.beTrue()
                PW.ActiveMode = PW.Modes.Get("tdm")
                local tdmPlayer = fakePlayer(TEAM_UNASSIGNED)
                engineHook("PlayerSpawn", tdmPlayer)
                expect(tdmPlayer:Team()).notTo.equal(rules().FreeTeam)
                setPhase(state, "LOBBY")
                PW.ActiveMode = PW.Modes.Get("ffa")
                local lobbyPlayer = fakePlayer(TEAM_UNASSIGNED)
                engineHook("PlayerSpawn", lobbyPlayer)
                expect(lobbyPlayer:Team()).to.equal(TEAM_UNASSIGNED)
            end
        },
        {
            name = "PW_SelectSpawn: an entity answer is returned, a data point is applied on spawn, nil keeps the base",
            func = function()
                local host = must(player.GetHumans()[1])
                local ply = fakePlayer(1)
                expect(engineHook("PlayerSelectSpawn", ply)).to.beNil()
                hook.Add("PW_SelectSpawn", listenerId, function() return host end)
                expect(engineHook("PlayerSelectSpawn", ply)).to.equal(host)
                hook.Remove("PW_SelectSpawn", listenerId)
                hook.Add("PW_SelectSpawn", listenerId, function() return { pos = Vector(10, 20, 30), yaw = 90 } end)
                expect(engineHook("PlayerSelectSpawn", ply)).to.beNil()
                engineHook("PlayerSpawn", ply)
                expect(fields(ply).pos).to.equal(Vector(10, 20, 30))
                expect(fields(ply).ang).to.equal(Angle(0, 90, 0))
                expect(PW._MatchRules.points[ply]).to.beNil()
            end
        },
        {
            name = "Kill counts reset when PREMATCH turns into LIVE and when the lobby returns",
            func = function()
                local ply = fakePlayer(1)
                rules()._Tally(PW._MatchRules, ply, 1)
                local entity = module()
                must(entity.PW_PhaseChange)(entity, "POSTMATCH", "LIVE", 0)
                expect(rules().GetKills(ply)).to.equal(1)
                must(entity.PW_PhaseChange)(entity, "LIVE", "PREMATCH", 0)
                expect(rules().GetKills(ply)).to.equal(0)
                expect(rules().GetTeamKills(1)).to.equal(0)
                rules()._Tally(PW._MatchRules, ply, 1)
                must(entity.PW_PhaseChange)(entity, "LOBBY", "POSTMATCH", 0)
                expect(rules().GetKills(ply)).to.equal(0)
            end
        },
        {
            name = "In-game smoke: a TDM match on the current map reaches LIVE and finishes at the score limit",
            async = true,
            timeout = 15,
            func = function(state)
                -- The real machine: undo the GetPhase stub and the swapped stores of beforeEach.
                match().GetPhase = state.getPhase --[[@as fun(): PW.PhaseName]]
                PW._MatchRules = state.store
                PW._Score = state.scoreStore
                ---@type table<string, string>
                local saved = {}
                for _, name in ipairs(phaseConVars) do saved[name] = must(GetConVar(name)):GetString() end
                local function restore()
                    for name, value in pairs(saved) do must(GetConVar(name)):SetString(value) end
                end
                must(GetConVar("pw_prematch_timeout")):SetString("0")
                must(GetConVar("pw_countdown")):SetString("0")
                must(GetConVar("pw_postmatch_time")):SetString("0.5")
                must(GetConVar("pw_aftermatch")):SetString("lobby")
                ---@type any[]
                local ended = {}
                hook.Add("PW_MatchEnd", listenerId, function(result) ended[#ended + 1] = result end)
                expect(match().GetPhase()).to.equal("LOBBY")
                local tdm = must(PW.Modes.Get("tdm"))
                expect(match().Start(tdm)).to.beTrue()
                local function waitFor(phase, deadline, after)
                    if match().GetPhase() == phase then return after() end
                    if CurTime() > deadline then
                        restore()
                        if match().GetPhase() ~= "LOBBY" then match().Abort("match_rules smoke timed out") end
                        error("phase " .. phase .. " not reached, still " .. match().GetPhase())
                    end
                    timer.Simple(0.1, function() waitFor(phase, deadline, after) end)
                end
                waitFor("LIVE", CurTime() + 5, function()
                    expect(PW.ActiveMode).to.equal(tdm)
                    expect(tdm._StartedAt).to.exist()
                    PW._MatchRules.teamKills[1] = tdm:Setting("scorelimit")
                    waitFor("LOBBY", CurTime() + 5, function()
                        restore()
                        expect(#ended).to.equal(1)
                        local result = ended[1] --[[@as PW.MatchResult]]
                        expect(result.reason).to.equal("scorelimit")
                        expect(result.winner).to.equal(1)
                        done()
                    end)
                end)
            end
        }
    }
}
