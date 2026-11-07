-- T-2.9 spawns module (TASKS.md, "Mandatory test cases" T-2.9; 03-mapdata.md d.7; docs/api/map.md).
-- Pure cases score plain candidates against fake enemies and teammates (plain tables, no players, no traces): far
-- from enemies, enemy line of sight, the teammate bonus only in team modes, the recently used penalty and the hull
-- check through an injected probe. Glue cases call the module's listener and engine hooks with player stand-ins and
-- PW.Match.GetPhase stubbed. The in-game cases use the host only (no bots): Pick on the loaded map (gm_construct in
-- the test run) returns a free point, and the trace budget is measured with fake enemies on the real map.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.SpawnsLib
local function lib()
    return must(PW.Spawns)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@return PW.Module
local function module()
    return must(must(PW.Modules).Get("spawns")) --[[@as PW.Module]]
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

---@param x number
---@param y number
---@param opts? { visible?: boolean, key?: string }
---@return PW.SpawnCandidate
local function cand(x, y, opts)
    opts = opts or {}
    return { pos = Vector(x, y, 0), yaw = 0, key = opts.key or (x .. " " .. y), jitter = 0, visible = opts.visible }
end

---@param x number
---@param y number
---@param dir? Vector
---@return PW.SpawnActor
local function actor(x, y, dir)
    return { pos = Vector(x, y, 0), eye = Vector(x, y, 64), dir = dir }
end

---@param opts? table<string, any>
---@return PW.SpawnContext
local function ctx(opts)
    opts = opts or {}
    return {
        enemies = opts.enemies or {},
        mates = opts.mates or {},
        teamBonus = opts.teamBonus == true,
        now = opts.now or 100,
        used = opts.used or {}
    }
end

---A probe over fixed answers by candidate key; counts its calls.
---@param blocked table<string, boolean>
---@param seen table<string, boolean>
---@return PW.SpawnProbe
---@return { clear: integer, sees: integer }
local function probe(blocked, seen)
    local calls = { clear = 0, sees = 0 }
    return {
        clear = function(c)
            calls.clear = calls.clear + 1
            return not blocked[c.key]
        end,
        sees = function(c)
            calls.sees = calls.sees + 1
            return seen[c.key] == true
        end
    }, calls
end

---A player stand-in with the methods the protection glue reads.
---@return Player
local function fakePlayer()
    ---@type table<string, number>
    local nw = {}
    ---@type table<string, any>
    local fake = {}
    fake.IsValid = function() return true end
    fake.IsPlayer = function() return true end
    ---@param key string
    ---@param value number
    fake.SetNW2Float = function(_, key, value) nw[key] = value end
    ---@param key string
    ---@param fallback number
    ---@return number
    fake.GetNW2Float = function(_, key, fallback) return nw[key] or fallback end
    return fake --[[@as Player]]
end

return {
    groupName = "PW spawns",
    beforeEach = function(state)
        state.store = PW._Spawns
        state.getPhase = match().GetPhase
        state.protection = lib()._ProtectionTime
        state.phase = "LIVE"
        PW._Spawns = lib()._NewStore()
        match().GetPhase = function() return state.phase end
    end,
    afterEach = function(state)
        match().GetPhase = state.getPhase --[[@as fun(): PW.PhaseName]]
        lib()._ProtectionTime = state.protection --[[@as fun(): number]]
        PW._Spawns = state.store
    end,
    cases = {
        {
            name = "Mandatory (T-2.9): scoring prefers far-from-enemy",
            func = function()
                local c = ctx({ enemies = { actor(0, 0) } })
                local near, far = cand(300, 0), cand(1500, 0)
                expect(lib()._Score(far, c) > lib()._Score(near, c)).to.beTrue()
                local p = probe({}, {})
                expect(must(lib()._Choose({ near, far }, c, p)).key).to.equal(far.key)
                local two = ctx({ enemies = { actor(0, 0), actor(2000, 0) } })
                expect(lib()._Score(cand(1000, 0), two) > lib()._Score(cand(1800, 0), two)).to.beTrue()
                expect(lib()._Score(cand(10, 0), ctx()) > lib()._Score(far, c)).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-2.9): penalises enemy line of sight",
            func = function()
                local c = ctx({ enemies = { actor(0, 0) } })
                local hidden, seen = cand(1000, 0), cand(0, 1000, { visible = true })
                expect(lib()._Score(hidden, c) > lib()._Score(seen, c)).to.beTrue()
                local nearHidden, farSeen = cand(400, 0, { key = "a" }), cand(2400, 0, { key = "b" })
                local p = probe({}, { b = true })
                expect(must(lib()._Choose({ farSeen, nearHidden }, c, p)).key).to.equal("a")
                local looking = ctx({ enemies = { actor(0, 0, Vector(1, 0, 0)) } })
                local away = ctx({ enemies = { actor(0, 0, Vector(-1, 0, 0)) } })
                local target = cand(1000, 0, { visible = true })
                expect(lib()._Score(target, looking) < lib()._Score(target, away)).to.beTrue()
                local unseen = cand(1000, 0)
                expect(lib()._Score(unseen, looking)).to.equal(lib()._Score(unseen, away))
            end
        },
        {
            name = "Mandatory (T-2.9): rewards nearby teammates only in team modes",
            func = function()
                local mates = { actor(1000, 300) }
                local enemies = { actor(0, 0) }
                local withMate, alone = cand(1000, 0), cand(0, 1000)
                local team = ctx({ enemies = enemies, mates = mates, teamBonus = true })
                local ffa = ctx({ enemies = enemies, mates = mates, teamBonus = false })
                expect(lib()._Score(withMate, team) > lib()._Score(alone, team)).to.beTrue()
                expect(lib()._Score(withMate, ffa)).to.equal(lib()._Score(alone, ffa))
                local farMate = ctx({ enemies = enemies, mates = { actor(5000, 5000) }, teamBonus = true })
                expect(lib()._Score(withMate, farMate)).to.equal(lib()._Score(alone, farMate))
                local p = probe({}, {})
                expect(must(lib()._Choose({ alone, withMate }, team, p)).key).to.equal(withMate.key)
            end
        },
        {
            name = "Mandatory (T-2.9): a recently used point is penalised",
            func = function()
                local w = lib().Weights
                local a, b = cand(1000, 0, { key = "a" }), cand(0, 1000, { key = "b" })
                local fresh = ctx({ enemies = { actor(0, 0) }, now = 100, used = { a = 99 } })
                expect(lib()._Score(a, fresh) < lib()._Score(b, fresh)).to.beTrue()
                local p = probe({}, {})
                expect(must(lib()._Choose({ a, b }, fresh, p)).key).to.equal("b")
                local old = ctx({ enemies = { actor(0, 0) }, now = 100, used = { a = 100 - w.recentWindow } })
                expect(lib()._Score(a, old)).to.equal(lib()._Score(b, old))
                local older = ctx({ enemies = { actor(0, 0) }, now = 100, used = { a = 95 } })
                expect(lib()._Score(a, older) > lib()._Score(a, fresh)).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-2.9): a hull-blocked point is never chosen",
            func = function()
                local c = ctx({ enemies = { actor(0, 0) } })
                local best, mid, worst = cand(2400, 0, { key = "best" }), cand(1200, 0, { key = "mid" }),
                    cand(200, 0, { key = "worst" })
                local p = probe({ best = true }, {})
                expect(must(lib()._Choose({ best, mid, worst }, c, p)).key).to.equal("mid")
                local seen = probe({ best = true, mid = true }, { worst = true })
                expect(must(lib()._Choose({ best, mid, worst }, c, seen)).key).to.equal("worst")
                local none = probe({ best = true, mid = true, worst = true }, {})
                expect(lib()._Choose({ best, mid, worst }, c, none)).to.beNil()
                expect(lib()._Choose({}, c, none)).to.beNil()
            end
        },
        {
            name = "Budget: probing stops once no remaining candidate can beat the best one",
            func = function()
                local c = ctx({ enemies = { actor(0, 0) } })
                local list = { cand(200, 0), cand(2400, 0), cand(800, 0), cand(1600, 0) }
                local p, calls = probe({}, {})
                expect(must(lib()._Choose(list, c, p)).pos.x).to.equal(2400)
                expect(calls.clear).to.equal(1)
                expect(calls.sees).to.equal(1)
                local seenAll, all = probe({}, { ["2400 0"] = true, ["1600 0"] = true, ["800 0"] = true,
                    ["200 0"] = true })
                expect(must(lib()._Choose(list, c, seenAll)).pos.x).to.equal(2400)
                expect(all.sees).to.equal(4)
            end
        },
        {
            name = "Candidates: first spawn uses the team's zone plus any-team points; respawns and FFA use all",
            func = function()
                local any = PW.Map and PW.Map.AnyTeam or 0
                ---@type PW.MapSpawns
                local spawns = {
                    [1] = { { pos = Vector(1, 0, 0), yaw = 0 } },
                    [2] = { { pos = Vector(2, 0, 0), yaw = 0 } },
                    [any] = { { pos = Vector(9, 0, 0), yaw = 90 } }
                }
                local first = lib()._Pool(spawns, 1, false)
                expect(#first).to.equal(2)
                for _, c in ipairs(first) do expect(c.pos.x ~= 2).to.beTrue() end
                expect(#lib()._Pool(spawns, 1, true)).to.equal(3)
                expect(#lib()._Pool(spawns, 3, false)).to.equal(3)
                expect(#lib()._Pool({}, 1, true)).to.equal(0)
                ---@type table<string, boolean>
                local keys = {}
                for _, c in ipairs(lib()._Pool(spawns, 1, true)) do keys[c.key] = true end
                expect(table.Count(keys)).to.equal(3)
            end
        },
        {
            name = "Sample: at most n distinct candidates; a short list is returned whole",
            func = function()
                ---@type PW.SpawnCandidate[]
                local list = {}
                for i = 1, 20 do list[i] = cand(i, 0) end
                local picked = lib()._Sample(list, 8, math.random)
                expect(#picked).to.equal(8)
                ---@type table<PW.SpawnCandidate, boolean>
                local seen = {}
                for _, c in ipairs(picked) do seen[c] = true end
                expect(table.Count(seen)).to.equal(8)
                expect(#lib()._Sample({ cand(1, 0), cand(2, 0) }, 8, math.random)).to.equal(2)
                expect(#list).to.equal(20)
            end
        },
        {
            name = "Protection (pure): 0 s gives none; protected strictly before the end time",
            func = function()
                expect(lib()._ProtectUntil(10, 0)).to.beNil()
                expect(lib()._ProtectUntil(10, 2)).to.equal(12)
                expect(lib()._Protected(nil, 10)).to.beFalse()
                expect(lib()._Protected(12, 11.9)).to.beTrue()
                expect(lib()._Protected(12, 12)).to.beFalse()
            end
        },
        {
            name = "Protection glue: a LIVE spawn blocks damage until the player fires; no protection outside LIVE",
            func = function(state)
                lib()._ProtectionTime = function() return 2 end
                local ply = fakePlayer()
                engineHook("PlayerSpawn", ply)
                expect(PW._Spawns.protect[ply]).to.exist()
                expect(engineHook("EntityTakeDamage", ply, nil)).to.beTrue()
                expect(lib().ProtectedUntil(ply) > CurTime()).to.beTrue()
                engineHook("KeyPress", ply, IN_JUMP)
                expect(engineHook("EntityTakeDamage", ply, nil)).to.beTrue()
                engineHook("KeyPress", ply, IN_ATTACK)
                expect(engineHook("EntityTakeDamage", ply, nil)).to.beNil()
                expect(lib().ProtectedUntil(ply)).to.equal(0)
                lib()._ProtectionTime = function() return 0 end
                local plain = fakePlayer()
                engineHook("PlayerSpawn", plain)
                expect(engineHook("EntityTakeDamage", plain, nil)).to.beNil()
                state.phase = "PREMATCH"
                lib()._ProtectionTime = function() return 2 end
                local early = fakePlayer()
                engineHook("PlayerSpawn", early)
                expect(engineHook("EntityTakeDamage", early, nil)).to.beNil()
                expect(PW._Spawns.spawned[early]).to.beNil()
            end
        },
        {
            name = "Setting: spawns.protection is a match setting, 0 to 5 s, default 0 (03-mapdata.md d.7)",
            func = function()
                local def = must(module().Settings).protection
                expect(def.type).to.equal("float")
                expect(def.min).to.equal(0)
                expect(def.max).to.equal(5)
                expect(def.default).to.equal(0)
                expect(PW.Setting("spawns.protection")).to.equal(0)
            end
        },
        {
            name = "Listener: PW_SelectSpawn ignores stand-ins and answers only during LIVE",
            func = function(state)
                local entity = module() --[[@as table<string, any>]]
                expect(entity:PW_SelectSpawn({})).to.beNil()
                state.phase = "LOBBY"
                expect(entity:PW_SelectSpawn(must(player.GetHumans()[1]))).to.beNil()
            end
        },
        {
            name = "In-game: Pick for the host returns a map point that is not inside a player (host only, no bots)",
            func = function()
                local host = must(player.GetHumans()[1])
                local point = lib().Pick(host, { first = false })
                local stats = must(PW._Spawns.stats)
                local pool = lib()._Pool(must(PW.Map).GetSpawns(), host:Team(), true)
                print(string.format("[PW] spawns smoke on %s: pool %d, %d candidates, %d probed, %d traces, %.2f ms",
                    game.GetMap(), #pool, stats.candidates, stats.probed, stats.traces, stats.ms))
                if #pool == 0 then
                    expect(point).to.beNil()
                    return
                end
                local p = must(point)
                expect(isvector(p.pos)).to.beTrue()
                expect(isnumber(p.yaw)).to.beTrue()
                expect(lib()._HullClear(p.pos, host)).to.beTrue()
                expect(PW._Spawns.used[lib()._Key(p.pos)]).to.equal(CurTime())
                for _, other in ipairs(player.GetAll()) do
                    if other ~= host and other:Alive() and other:GetMoveType() ~= MOVETYPE_OBSERVER then
                        local d = other:GetPos() - p.pos
                        local apart = math.max(math.abs(d.x), math.abs(d.y)) >= 32 or math.abs(d.z) >= 72
                        expect(apart).to.beTrue()
                    end
                end
            end
        },
        {
            name = "In-game: trace budget with 16 fake enemies stays within Budget.maxTraces",
            func = function()
                local host = must(player.GetHumans()[1])
                local pool = lib()._Pool(must(PW.Map).GetSpawns(), host:Team(), true)
                if #pool == 0 then return end
                ---@type PW.SpawnActor[]
                local enemies = {}
                for i = 1, 16 do
                    local at = must(pool[(i - 1) % #pool + 1]).pos + Vector(i * 8, 0, 0)
                    enemies[i] = { pos = at, eye = at + Vector(0, 0, 64), dir = Vector(1, 0, 0) }
                end
                local worst = 0
                for _ = 1, 20 do
                    PW._Spawns = lib()._NewStore()
                    lib().Pick(host, { first = false, enemies = enemies, mates = {} })
                    local stats = must(PW._Spawns.stats)
                    expect(stats.traces <= lib().Budget.maxTraces + lib().Budget.sample).to.beTrue()
                    if stats.ms > worst then worst = stats.ms end
                end
                print(string.format("[PW] spawns budget on %s: 16 enemies, worst of 20 picks %.2f ms",
                    game.GetMap(), worst))
                expect(worst).to.beLessThan(lib().Budget.maxMs)
            end
        }
    }
}
