-- T-2.5 Kill Confirmed (TASKS.md, "Mandatory test cases" T-2.5; 02-modes.md d.5, d.7; 01-extensibility.md d.17).
-- Pure cases over plain data (the verdict, the confirm tally, expiry, eviction, the win check). In-game cases spawn
-- the real tag entity at the host's position with the host as the victim and simulate pickups through the entity's
-- touch handler with player stand-ins (tables with IsValid, IsPlayer, Alive and Team); no bots are created.
-- PW.Score.Award and PW.Match.Finish are replaced by recorders, the mode's Setting is stubbed, PW.ActiveMode is set
-- to KC only inside a case. Every case removes its tags and restores what it replaced.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.KCMode
local function kc()
    return must(PW.Modes.Get("kc")) --[[@as PW.KCMode]]
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@return PW.KCTagsLib
local function tags()
    return must(PW.KCTags)
end

---@return Player
local function host()
    return must(player.GetHumans()[1])
end

---A player stand-in for the touch handler and the enemy check.
---@param team integer
---@param alive? boolean
---@param observer? integer observer mode (default OBS_MODE_NONE)
---@return Player
local function standIn(team, alive, observer)
    ---@type table<string, any>
    local fake = {}
    fake.IsValid = function() return true end
    fake.IsPlayer = function() return true end
    fake.Alive = function() return alive ~= false end
    fake.Team = function() return team end
    fake.GetObserverMode = function() return observer or OBS_MODE_NONE end
    return fake --[[@as Player]]
end

---A team index of KC (1 or 2) that differs from the host's team, so a stand-in in it is the host's enemy.
---@return integer
local function enemyTeam()
    if host():Team() == 1 then return 2 end
    return 1
end

---@param state table<string, any>
---@return table[]
local function awards(state)
    return state.awards --[[@as table[] ]]
end

---@param state table<string, any>
---@return PW.MatchResult[]
local function finished(state)
    return state.finished --[[@as PW.MatchResult[] ]]
end

---Stubs the mode's Setting (restored by afterEach).
---@param values table<string, number>
local function settings(values)
    rawset(kc(), "Setting", function(_, key) return values[key] end)
end

---Spawns a tag at the host with the host as the victim.
---@return PW.KCTag
local function tagAtHost()
    return must(tags().Spawn(host():GetPos(), host(), 0))
end

return {
    groupName = "PW mode Kill Confirmed",
    beforeEach = function(state)
        state.awards = {}
        state.finished = {}
        state.activeMode = PW.ActiveMode
        state.award = must(PW.Score).Award
        state.finish = match().Finish
        state.setting = rawget(kc(), "Setting")
        local list = awards(state)
        must(PW.Score).Award = function(ply, eventId)
            list[#list + 1] = { ply = ply, id = eventId }
            return true, 0, 0
        end
        local results = finished(state)
        match().Finish = function(result)
            results[#results + 1] = result
            return true
        end
        settings({ scorelimit = 65, timelimit = 600, taglifetime = 0 })
        kc()._Confirms = {}
    end,
    afterEach = function(state)
        must(kc().Cleanup)(kc())
        rawset(kc(), "Setting", state.setting)
        PW.ActiveMode = state.activeMode
        must(PW.Score).Award = state.award --[[@as fun(ply: Player, eventId: string, opts?: PW.ScoreOpts): boolean]]
        match().Finish = state.finish --[[@as fun(result?: any): boolean]]
    end,
    cases = {
        {
            name = "KC is registered: inherits TDM, two teams, score limit 65 confirms, a tag lifetime setting",
            func = function()
                local mode = kc()
                expect(mode.Base).to.equal("tdm")
                expect(mode.Teams).to.equal(2)
                local schema = PW.Settings._Schema(mode, "modes", function() end)
                expect(must(schema.scorelimit).id).to.equal("kc.scorelimit")
                expect(must(schema.scorelimit).default).to.equal(65)
                expect(must(schema.timelimit).default).to.equal(600)
                expect(must(schema.taglifetime).default).to.equal(0)
                expect(must(PW.Registries.score_events.Get("kc_confirm")).Points).to.equal(100)
                expect(must(PW.Registries.score_events.Get("kc_deny")).Points).to.equal(50)
            end
        },
        {
            name = "The tag spawns at the victim: a death in KC drops a tag at the victim's position",
            func = function()
                local before = #tags().GetAll()
                must(kc().PW_PlayerKilled)(kc(), host(), game.GetWorld(), DamageInfo())
                local list = tags().GetAll()
                expect(#list).to.equal(before + 1)
                local tag = must(list[#list])
                expect(tag:GetClass()).to.equal(tags().Class)
                expect(tag:GetVictim()).to.equal(host())
                local at, victimPos = tag:GetPos(), host():GetPos()
                expect(at.x).to.equal(victimPos.x)
                expect(at.y).to.equal(victimPos.y)
                -- Snapped to the ground under the victim: never above it, at most the trace length below.
                expect(at.z <= victimPos.z + 1).to.beTrue()
                expect(victimPos.z - at.z <= tags().GroundTrace).to.beTrue()
                expect(tag:UpdateTransmitState()).to.equal(TRANSMIT_ALWAYS)
            end
        },
        {
            name = "An enemy pickup confirms and scores: kc_confirm to the collector, one confirm for its team",
            func = function(state)
                PW.ActiveMode = kc()
                local tag = tagAtHost()
                local enemy = standIn(enemyTeam())
                tag:StartTouch(enemy)
                expect(#awards(state)).to.equal(1)
                expect(must(awards(state)[1]).ply).to.equal(enemy)
                expect(must(awards(state)[1]).id).to.equal("kc_confirm")
                expect(must(kc()._Confirms)[enemyTeam()]).to.equal(1)
                expect(kc().GetConfirms(enemyTeam())).to.equal(1)
            end
        },
        {
            name = "A teammate pickup denies: kc_deny to the collector, no confirm",
            func = function(state)
                PW.ActiveMode = kc()
                local tag = tagAtHost()
                local mate = standIn(host():Team())
                tag:StartTouch(mate)
                expect(#awards(state)).to.equal(1)
                expect(must(awards(state)[1]).ply).to.equal(mate)
                expect(must(awards(state)[1]).id).to.equal("kc_deny")
                expect(next(must(kc()._Confirms))).to.beNil()
            end
        },
        {
            name = "The tag is removed after pickup: out of the list at once, the entity next tick, no second pickup",
            async = true,
            timeout = 3,
            func = function(state)
                PW.ActiveMode = kc()
                local tag = tagAtHost()
                local before = #tags().GetAll()
                tag:StartTouch(standIn(enemyTeam()))
                tag:Touch(standIn(enemyTeam()))
                PW.ActiveMode = state.activeMode
                expect(#tags().GetAll()).to.equal(before - 1)
                expect(#awards(state)).to.equal(1)
                timer.Simple(0.2, function()
                    expect(IsValid(tag)).to.beFalse()
                    done()
                end)
            end
        },
        {
            name = "The engine detects touches: a physics prop dropped into a tag reaches the touch handler",
            async = true,
            timeout = 4,
            func = function(state)
                local lib = tags()
                local ground = must(lib._Ground)(host():GetPos())
                state.touch = lib._Touch
                local prop = ents.Create("prop_physics")
                state.prop = prop
                lib._Touch = function(_, other)
                    if other ~= prop then return nil end
                    lib._Touch = state.touch --[[@as fun(tag: PW.KCTag, other: any): PW.KCVerdict?]]
                    done()
                    return nil
                end
                must(lib.Spawn)(ground, standIn(enemyTeam()), 0)
                prop:SetModel("models/props_junk/PopCan01a.mdl")
                prop:SetPos(ground + Vector(0, 0, 40))
                prop:Spawn()
                local phys = prop:GetPhysicsObject()
                if IsValid(phys) then phys:Wake() end
            end,
            cleanup = function(state)
                tags()._Touch = state.touch --[[@as fun(tag: PW.KCTag, other: any): PW.KCVerdict?]]
                local prop = state.prop --[[@as Entity?]]
                if prop ~= nil and IsValid(prop) then prop:Remove() end
            end
        },
        {
            name = "Dead collectors, spectators and non-players pick nothing up; the tag stays",
            func = function(state)
                PW.ActiveMode = kc()
                local tag = tagAtHost()
                tag:StartTouch(standIn(enemyTeam(), false))
                tag:StartTouch(standIn(enemyTeam(), true, OBS_MODE_ROAMING))
                tag:StartTouch(game.GetWorld())
                expect(#awards(state)).to.equal(0)
                expect(IsValid(tag) and not tag:IsMarkedForDeletion()).to.beTrue()
            end
        },
        {
            name = "Verdict (pure): enemy confirms, teammate or the victim denies, dead or not a player is nothing",
            func = function()
                local verdict = tags()._Verdict
                expect(verdict({ player = true, alive = true, enemy = true })).to.equal("confirm")
                expect(verdict({ player = true, alive = true, enemy = false })).to.equal("deny")
                expect(verdict({ player = true, alive = false, enemy = true })).to.beNil()
                expect(verdict({ player = false, alive = true, enemy = true })).to.beNil()
            end
        },
        {
            name = "Confirm tally (pure): a confirm counts for the collector's team 1..N, a deny counts nothing",
            func = function()
                local mode = kc()
                ---@type table<integer, integer>
                local confirms = {}
                expect(mode._Apply(confirms, "confirm", 2)).to.equal("kc_confirm")
                expect(mode._Apply(confirms, "confirm", 2)).to.equal("kc_confirm")
                expect(mode._Apply(confirms, "deny", 1)).to.equal("kc_deny")
                expect(mode._Apply(confirms, "confirm", nil)).to.equal("kc_confirm")
                expect(confirms).to.deepEqual({ [2] = 2 })
                expect(mode._TeamIndex(1, 2)).to.equal(1)
                expect(mode._TeamIndex(1001, 2)).to.beNil()
                expect(mode._Standings({ [2] = 3 }, 2))
                    .to.deepEqual({ { id = 1, score = 0 }, { id = 2, score = 3 } })
            end
        },
        {
            name = "Score limit counts confirms: Think finishes at the limit; team kills do not count",
            func = function(state)
                local mode = kc()
                mode._StartedAt = CurTime() - 5
                local store = PW._MatchRules
                PW._MatchRules = must(PW.MatchRules)._NewStore()
                PW._MatchRules.teamKills = { [1] = 500, [2] = 500 }
                mode._Confirms = { [1] = 64, [2] = 10 }
                must(mode.Think)(mode)
                expect(#finished(state)).to.equal(0)
                mode._Confirms[1] = 65
                must(mode.Think)(mode)
                PW._MatchRules = store
                local result = must(finished(state)[1])
                expect(result.reason).to.equal("scorelimit")
                expect(result.winner).to.equal(1)
                expect(result.teams).to.beTrue()
                expect(result.standings).to.deepEqual({ { id = 1, score = 65 }, { id = 2, score = 10 } })
            end
        },
        {
            name = "Tags are removed at match end: Cleanup removes every tag and zeroes the confirms",
            func = function()
                local tag = tagAtHost()
                kc()._Confirms = { [1] = 3 }
                must(kc().Cleanup)(kc())
                expect(#tags().GetAll()).to.equal(0)
                expect(tag:IsMarkedForDeletion()).to.beTrue()
                expect(kc().GetConfirms(1)).to.equal(0)
            end
        },
        {
            name = "Lifetime and cap (pure): 0 never expires; the oldest tags make room over the cap",
            func = function()
                local lib = tags()
                expect(lib._ExpireAt(100, 0)).to.equal(0)
                expect(lib._ExpireAt(100, 30)).to.equal(130)
                expect(lib._Expired(0, 1e9)).to.beFalse()
                expect(lib._Expired(130, 129.9)).to.beFalse()
                expect(lib._Expired(130, 130)).to.beTrue()
                expect(lib._Evict(3, 64)).to.equal(0)
                expect(lib._Evict(64, 64)).to.equal(1)
                expect(lib._Evict(70, 64)).to.equal(7)
            end
        },
        {
            name = "A tag with a lifetime is removed by its own think once expired",
            func = function()
                local tag = must(tags().Spawn(host():GetPos(), host(), 30))
                -- A float network var: compare with the precision of a 32-bit float.
                expect(math.abs(tag:GetExpireAt() - (CurTime() + 30)) < 0.01).to.beTrue()
                tag:SetExpireAt(CurTime() - 1)
                tag:Think()
                expect(tag:IsMarkedForDeletion()).to.beTrue()
                expect(#tags().GetAll()).to.equal(0)
            end
        }
    }
}
