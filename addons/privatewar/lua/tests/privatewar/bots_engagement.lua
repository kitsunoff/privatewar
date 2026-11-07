-- Engagement latency of the bot pipeline (07-bots.md d.3, d.7, d.8, d.15; notes/14 reaction numbers): two hostile
-- managed bots on the "regular" tier, personality "run_and_gun", invulnerable, placed facing each other on
-- gm_construct. A timeline per bot (seen, recognised, fight, target, settled, fire decision, first bullet) is printed
-- for every duel, so a slow stage shows up with numbers.

local smokeHook = "PW.BotsEngagementTest"
local duels = 3
local duelTimeout = 12
-- Seconds from mutual sight to each bot's first bullet on the regular tier. The design pipeline is the reaction
-- (0.45 s mean, at most 0.61 s with the jitter) + the brain tick (0.1 s) + the attack delay (0.4 s, overlapping the
-- turn) + the aim settle; a bot that turned away while hunting re-acquires through a second reaction delay. After
-- the fixes 48 measured latencies were 0-3.0 s (median about 1.6 s); 3.5 s keeps that tail from making the suite
-- flaky. Before the fixes the duel took 2-12 s or never fired.
local engageBound = 3.5

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

local now = 1000

---A board over the real combat behaviours: a healthy bot at the origin with a full magazine and these contacts.
---@param contacts PW.BotContact[]
---@return PW.BotBoard
local function combatBoard(contacts)
    ---@type table<Entity, PW.BotContact>
    local memory = {}
    for _, c in ipairs(contacts) do memory[c.ent] = c end
    ---@type table<string, any>
    local facts = { at = now, pos = Vector(0, 0, 0), health = 100, maxHealth = 100, clip = 30, capacity = 30,
        reserve = 90, reloading = false, lethal = 0, profile = must(PW.BotTactics).ProfileFor(nil, nil, "regular") }
    return { bot = "bot" --[[@as Player]], tactics = facts --[[@as PW.BotCombatFacts]], contacts = contacts,
        memory = memory, intent = { buttons = 0 } }
end

---A brain env over the real fight, search, third_party and idle behaviours with a goal api that accepts everything.
---@param b PW.BotBoard
---@return PW.BotBrainEnv
local function combatEnv(b)
    local registry = must(PW.BotBehaviors)
    ---@type PW.BotBehavior[]
    local list = {}
    for _, id in ipairs({ "fight", "search", "third_party", "idle" }) do
        list[#list + 1] = must(registry.Get(id)) --[[@as PW.BotBehavior]]
    end
    ---@type PW.BotBrainApi
    local api = {
        setGoal = function() return true, "moving" end,
        clearGoal = function() end,
        searchPlan = function() return { Vector(800, 0, 0) } end
    }
    return { bot = "bot", board = b, behaviors = list, random = function() return 0 end, api = api }
end

---@param ent Entity
---@param visible boolean
---@param age number
---@return PW.BotContact
local function sighting(ent, visible, age)
    return { ent = ent, pos = Vector(800, 0, 0), vel = Vector(0, 0, 0), time = now - age, visible = visible,
        source = "sight" }
end

---@param state PW.BotBrainState
---@return string
local function topOf(state)
    local top = state.stack[#state.stack]
    return top ~= nil and top.id or "-"
end

---A partner of centers[i]: 500-1000 units away on one level with a clear line; spends the trace budget. Kept equal
---to the duel smoke case of bots_behaviors_combat.lua (a test file cannot require another one).
---@param centers Vector[]
---@param i integer
---@param budget { traces: integer }
---@return Vector?, Vector?
local function duelPartner(centers, i, budget)
    local a = centers[i]
    for j = i + 1, #centers do
        local b = centers[j]
        local d = a:Distance2D(b)
        if d >= 500 and d <= 1000 and math.abs(a.z - b.z) < 24 and budget.traces > 0 then
            budget.traces = budget.traces - 1
            local eye = Vector(0, 0, 64)
            local tr = util.TraceLine({ start = a + eye, endpos = b + eye, mask = MASK_SOLID })
            if not tr.Hit then return a, b end
        end
    end
    return nil, nil
end

---@return Vector?, Vector?
local function duelSpots()
    ---@type Vector[]
    local centers = {}
    for _, area in ipairs(navmesh.GetAllNavAreas() --[[@as CNavArea[] ]]) do
        if area:GetSizeX() >= 64 and area:GetSizeY() >= 64 then centers[#centers + 1] = area:GetCenter() end
    end
    local budget = { traces = 400 }
    for i = 1, #centers do
        local a, b = duelPartner(centers, i, budget)
        if a ~= nil or budget.traces <= 0 then return a, b end
    end
    return nil, nil
end

---A deterministic board: FFA, the "regular" tier and the "run_and_gun" personality.
---@param bot Player
---@return PW.BotBoard
local function duelBoard(bot)
    local profiles = must(PW.BotProfiles)
    ---@type table?
    local personality = nil
    for _, entity in ipairs(profiles.Entities("personality")) do
        if (entity --[[@as table<string, any>]]).ClassName == "run_and_gun" then
            personality = profiles.Snapshot(entity)
        end
    end
    ---@type table<string, any>
    local fresh = { bot = bot, difficulty = profiles.Snapshot(profiles.Tier("regular")), personality = personality }
    return fresh --[[@as PW.BotBoard]]
end

---Ends the bot's managed life: no board, no goal; the layers unregister on their next tick.
---@param bot Player
local function unmanage(bot)
    PW._BotsManager.boards[bot] = nil
    local goal = PW.BotGoal
    if goal ~= nil and goal._Drop ~= nil then goal._Drop(bot) end
end

---@param bot Player
---@param pos Vector
---@param toward Vector
local function place(bot, pos, toward)
    if not bot:Alive() then bot:Spawn() end
    bot:GodEnable()
    bot:StripWeapons()
    bot:Give("weapon_smg1")
    bot:GiveAmmo(225, "SMG1", true)
    bot:SelectWeapon("weapon_smg1")
    bot:SetPos(pos)
    local ang = (toward - pos):Angle()
    bot:SetEyeAngles(Angle(0, ang.y, 0))
end

---Whether the newest perception snapshot of bot holds enemy (what it sees now, before the reaction delay).
---@param bot Player
---@param enemy Player
---@return boolean
local function seesNow(bot, enemy)
    local state = PW.BotPerception.States[bot]
    local snaps = state ~= nil and state.queue.snaps or {}
    local last = snaps[#snaps]
    return last ~= nil and last.seen[enemy] ~= nil
end

---@param board PW.BotBoard
---@param enemy Player
---@return boolean
local function recognises(board, enemy)
    for _, c in ipairs(board.contacts or {}) do
        if c.ent == enemy and c.visible then return true end
    end
    return false
end

---The stage probes of one bot, in pipeline order.
---@param bot Player
---@param enemy Player
---@return table<string, boolean>
local function probe(bot, enemy)
    local board = PW._BotsManager.boards[bot]
    if board == nil then return {} end
    local aim = PW.BotAim.GetState(bot)
    local behavior = board.behavior
    return {
        perception = PW.BotPerception.States[bot] ~= nil,
        brain = PW._BotBrain.registered[bot] ~= nil,
        seen = seesNow(bot, enemy),
        recognised = recognises(board, enemy),
        fight = behavior ~= nil and behavior.id == "fight",
        target = board.target == enemy,
        settled = aim ~= nil and aim.settledSince ~= nil,
        decision = aim ~= nil and aim.fire == true
    }
end

local stages = { "perception", "brain", "seen", "recognised", "fight", "target", "settled", "decision", "shot" }

---@class PW.EngagementTrack
---@field first table<string, number> first time of each stage, seconds since the duel start
---@field lost integer how often the enemy left the newest snapshot after it was seen
---@field wasSeen boolean
---@field behaviors string[] the behaviour changes, "id@time"
---@field lastBehavior string?
---@field aim string[] aim samples before the first shot, "t err/tol focus"
---@field nextSample number

---@return PW.EngagementTrack
local function newTrack()
    return { first = {}, lost = 0, wasSeen = false, behaviors = {}, aim = {}, nextSample = 0 }
end

---Records one tick of a bot into its track.
---@param track PW.EngagementTrack
---@param bot Player
---@param enemy Player
---@param t number
local function sample(track, bot, enemy, t)
    local probed = probe(bot, enemy)
    for name, on in pairs(probed) do
        if on and track.first[name] == nil then track.first[name] = t end
    end
    if track.wasSeen and not probed.seen then track.lost = track.lost + 1 end
    track.wasSeen = probed.seen == true
    local board = PW._BotsManager.boards[bot]
    local id = board ~= nil and board.behavior ~= nil and board.behavior.id or "-"
    if id ~= track.lastBehavior then
        track.lastBehavior = id
        track.behaviors[#track.behaviors + 1] = string.format("%s@%.2f", id, t)
    end
    local aim = PW.BotAim.GetState(bot)
    if aim ~= nil and track.first.shot == nil and t >= track.nextSample and #track.aim < 24 then
        track.nextSample = t + 0.1
        -- v: the enemy is a visible contact (the aim may fire), b: the line of fire is blocked
        local flags = (probed.recognised and "v" or "") .. (aim.blockedSince ~= nil and "b" or "")
        track.aim[#track.aim + 1] = string.format("%.1f:%.2f/%.2f f%.1f%s", t, aim.err, aim.tolerance, aim.focus,
            flags)
    end
end

---@param track PW.EngagementTrack
---@return string
local function timeline(track)
    ---@type string[]
    local parts = {}
    for _, name in ipairs(stages) do
        local at = track.first[name]
        parts[#parts + 1] = string.format("%s=%s", name, at ~= nil and string.format("%.2f", at) or "-")
    end
    return table.concat(parts, " ")
end

---@param n integer
---@param bot Player
---@param track PW.EngagementTrack
local function report(n, bot, track)
    print(string.format("[PW] engagement duel %d %s: %s lost=%d", n, bot:Nick(), timeline(track), track.lost))
    print(string.format("[PW] engagement duel %d %s behaviours: %s", n, bot:Nick(),
        table.concat(track.behaviors, " ")))
    print(string.format("[PW] engagement duel %d %s aim: %s", n, bot:Nick(), table.concat(track.aim, " ")))
end

---Seconds from mutual visibility (both bots saw each other in a snapshot) to the bot's first bullet; nil if never.
---@param tracks PW.EngagementTrack[]
---@param i integer
---@return number?
local function sinceMutual(tracks, i)
    local a, b = tracks[1].first.seen, tracks[2].first.seen
    local shot = tracks[i].first.shot
    if a == nil or b == nil or shot == nil then return nil end
    return shot - math.max(a, b)
end

---Runs one duel; calls finish(tracks) once both bots fired, a bot is gone or the duel timed out.
---@param bots Player[]
---@param a Vector
---@param b Vector
---@param finish fun(tracks: PW.EngagementTrack[])
local function runDuel(bots, a, b, finish)
    place(bots[1], a, b)
    place(bots[2], b, a)
    local tracks = { newTrack(), newTrack() }
    local started = CurTime()
    hook.Add("EntityFireBullets", smokeHook, function(ent)
        for i, bot in ipairs(bots) do
            if ent == bot and tracks[i].first.shot == nil then tracks[i].first.shot = CurTime() - started end
        end
    end)
    for _, bot in ipairs(bots) do PW._BotsManager.boards[bot] = duelBoard(bot) end
    hook.Add("Tick", smokeHook, function()
        local t = CurTime() - started
        local gone = not (IsValid(bots[1]) and IsValid(bots[2]))
        if not gone then
            sample(tracks[1], bots[1], bots[2], t)
            sample(tracks[2], bots[2], bots[1], t)
        end
        local both = tracks[1].first.shot ~= nil and tracks[2].first.shot ~= nil
        if not both and not gone and t < duelTimeout then return end
        hook.Remove("Tick", smokeHook)
        hook.Remove("EntityFireBullets", smokeHook)
        for _, bot in ipairs(bots) do if IsValid(bot) then unmanage(bot) end end
        finish(tracks)
    end)
end

---Prints the duel's timelines and appends its two latencies since mutual sight (math.huge: none).
---@param bots Player[]
---@param n integer
---@param tracks PW.EngagementTrack[]
---@param results number[]
local function collect(bots, n, tracks, results)
    for i, bot in ipairs(bots) do
        if IsValid(bot) then report(n, bot, tracks[i]) end
        results[#results + 1] = sinceMutual(tracks, i) or math.huge
    end
end

---Runs duel n and the ones after it; each duel appends the two latencies since mutual sight (math.huge: none).
---@param bots Player[]
---@param a Vector
---@param b Vector
---@param n integer
---@param results number[]
---@param finish fun(results: number[])
local function runSeries(bots, a, b, n, results, finish)
    -- The layers unregister a bot without a board on their next tick (0.1 s); wait for them.
    timer.Create(smokeHook, 0.5, 1, function()
        runDuel(bots, a, b, function(tracks)
            collect(bots, n, tracks, results)
            if n >= duels then return finish(results) end
            runSeries(bots, a, b, n + 1, results, finish)
        end)
    end)
end

return {
    groupName = "PW bots engagement",
    beforeAll = function(state)
        ---@type Player[]
        local bots = {}
        for _, name in ipairs({ "PW engage A", "PW engage B" }) do
            local bot = player.CreateNextBot(name) --[[@as Player?]]
            if bot ~= nil and IsValid(bot) then
                bot:SetTeam(must(PW.MatchRules).FreeTeam)
                bot:Spawn()
                bots[#bots + 1] = bot
            end
        end
        state.bots = bots
        hook.Add("PW_IsEnemy", smokeHook, function(x, y)
            if x ~= y and table.HasValue(bots, x) and table.HasValue(bots, y) then return true end
        end)
    end,
    afterAll = function(state)
        hook.Remove("PW_IsEnemy", smokeHook)
        hook.Remove("Tick", smokeHook)
        hook.Remove("EntityFireBullets", smokeHook)
        timer.Remove(smokeHook)
        ---@type Player[]
        local bots = state.bots or {}
        for _, bot in ipairs(bots) do
            if IsValid(bot) then
                unmanage(bot)
                bot:GodDisable()
                bot:Kick("PW bots engagement test finished")
            end
        end
    end,
    beforeEach = function(state)
        -- A behaviour that errors is logged by PW.Call; keep the test output quiet (rawset: the field has one writer).
        state.log = PW._Call.log
        rawset(PW._Call, "log", function() end)
    end,
    afterEach = function(state)
        rawset(PW._Call, "log", state.log)
    end,
    cases = {
        {
            name = "fight keeps its target through a sight gap shorter than the grace, then gives up",
            func = function()
                local brain = must(PW.BotBrain)
                local foe = { name = "foe" } --[[@as Entity]]
                local b = combatBoard({ sighting(foe, true, 0) })
                local state, env = brain.NewState(), combatEnv(b)
                brain.Think(state, env, now)
                expect(topOf(state)).to.equal("fight")
                -- The enemy left the view (a turn, a strafe behind a post): fight holds on and keeps the target.
                local grace = must(PW.BotTactics).Config.fightGrace
                b.contacts = { sighting(foe, false, 0) }
                b.memory = { [foe] = b.contacts[1] }
                brain.Think(state, env, now + grace * 0.5)
                expect(topOf(state)).to.equal("fight")
                expect(b.target).to.equal(foe)
                brain.Think(state, env, now + grace + 0.3)
                expect(topOf(state) ~= "fight").to.beTrue()
                expect(b.target ~= foe or topOf(state) == "search").to.beTrue()
            end
        },
        {
            name = "Brain: an enemy that comes into sight re-evaluates every behaviour at once, not after its interval",
            func = function()
                local brain = must(PW.BotBrain)
                ---@param ctx PW.BotBrainCtx
                ---@return boolean
                local function anySeen(ctx)
                    for _, c in ipairs(ctx.contacts) do if c.visible then return true end end
                    return false
                end
                ---@type table<string, any>
                local shoot = { ClassName = "shoot", Interval = 1 }
                function shoot:Rank(_, ctx) return anySeen(ctx) and "combat" or false end
                function shoot:Weight() return 1 end
                function shoot:Update() return brain.Continue() end
                ---@type table<string, any>
                local roam = { ClassName = "roam", Interval = 1 }
                function roam:Rank() return "roam" end
                function roam:Weight() return 1 end
                function roam:Update() return brain.Continue() end
                local foe = { name = "foe" } --[[@as Entity]]
                local b = combatBoard({})
                ---@type PW.BotBrainEnv
                local env = { bot = "bot", board = b, behaviors = { shoot, roam } --[[@as PW.BotBehavior[] ]],
                    random = function() return 0 end }
                local state = brain.NewState()
                brain.Think(state, env, now)
                expect(topOf(state)).to.equal("roam")
                b.contacts = { sighting(foe, true, 0) }
                brain.Think(state, env, now + 0.1)
                expect(topOf(state)).to.equal("shoot")
                -- Losing sight is no new sighting: the cached evaluations stay until their interval passes.
                b.contacts = {}
                brain.Think(state, env, now + 0.2)
                expect(topOf(state)).to.equal("shoot")
            end
        },
        {
            name = "Aim fire gate: the CS half size (2 hull half widths, 1 for snipers), not the aimed part's size",
            func = function()
                local aim = must(PW.BotAim)
                expect(aim.FireHalfSize("smg")).to.equal(32)
                expect(aim.FireHalfSize(nil)).to.equal(32)
                expect(aim.FireHalfSize("sniper")).to.equal(16)
                -- At a typical duel range the gate is wider than the spring's lag behind the wandering focus error.
                expect(aim.Tolerance(aim.FireHalfSize("ar"), 800) > 2).to.beTrue()
                expect(aim.Tolerance(aim.FireHalfSize("sniper"), 800) < aim.Tolerance(aim.FireHalfSize("ar"), 800))
                    .to.beTrue()
            end
        },
        {
            name = "Aim fire gate: the tolerance grows with the current focus error, so long range does not stall",
            func = function()
                local aim = must(PW.BotAim)
                local share = aim.Config.focusTolerance
                expect(share > 0 and share < 0.5).to.beTrue()
                local far = aim.Tolerance(32, 2500)
                expect(math.abs(aim.Tolerance(32, 2500, 10) - (far + share * 10)) < 1e-6).to.beTrue()
                expect(aim.Tolerance(32, 2500, 0)).to.equal(far)
                expect(aim.Tolerance(32, 1, 1000)).to.equal(aim.Config.maxTolerance)
                -- Through a step: a bot with a large focus error gets the wider gate.
                local p = aim.ParamsFor(nil, "regular")
                local s = aim.NewState(0, 0, p, 0)
                aim.Acquire(s, p, 0, nil, function() return 0 end)
                aim.Step(s, { now = 0.01, dt = 0.01, eye = Vector(0, 0, 0), point = Vector(2500, 0, 0), radius = 32,
                    canFire = false }, p, function() return 0 end)
                expect(math.abs(s.tolerance - aim.Tolerance(32, 2500, s.focus)) < 1e-6).to.beTrue()
                expect(s.tolerance > far).to.beTrue()
            end
        },
        {
            name = "third_party: turns toward the heard fight, and gives the view back when it ends",
            func = function()
                local brain = must(PW.BotBrain)
                local foe = { name = "foe" } --[[@as Entity]]
                local heard = Vector(-1500, 0, 0)
                local b = combatBoard({ { ent = foe, pos = heard, vel = Vector(0, 0, 0), time = now - 1,
                    visible = false, source = "gunfire" } })
                local state, env = brain.NewState(), combatEnv(b)
                brain.Think(state, env, now)
                expect(topOf(state)).to.equal("third_party")
                expect(b.target).to.equal(heard)
                -- The enemy comes into sight: fight takes over and targets the entity, not the heard point.
                b.contacts = { sighting(foe, true, 0) }
                b.memory = { [foe] = b.contacts[1] }
                brain.Think(state, env, now + 0.1)
                expect(topOf(state)).to.equal("fight")
                expect(b.target).to.equal(foe)
            end
        },
        {
            name = "Goal follower: the walking view turns at most turn_max_speed, the short way round (07 d.15)",
            func = function()
                local goal = must(PW.BotGoal)
                -- 170 degrees behind at 360 degrees/s and 0.1 s: one tick turns 36 degrees, not 170.
                local view = goal.TurnToward(Angle(0, 0, 0), Angle(0, 170, 0), 360, 0.1)
                expect(math.abs(view.y - 36) < 1e-6).to.beTrue()
                -- Across the -180/180 seam the turn takes the short way: from 170 to -170 is +20, within the step.
                view = goal.TurnToward(Angle(0, 170, 0), Angle(0, -170, 0), 360, 0.1)
                expect(math.abs(math.AngleDifference(view.y, -170)) < 1e-6).to.beTrue()
                view = goal.TurnToward(Angle(0, 170, 0), Angle(0, 20, 0), 360, 0.1)
                expect(math.abs(view.y - 134) < 1e-6).to.beTrue()
                -- Pitch is clamped per axis too; a small turn arrives at once; no time, no turn.
                view = goal.TurnToward(Angle(0, 0, 0), Angle(60, 10, 0), 180, 0.1)
                expect(math.abs(view.p - 18) < 1e-6 and math.abs(view.y - 10) < 1e-6).to.beTrue()
                view = goal.TurnToward(Angle(5, 5, 0), Angle(80, 90, 0), 360, 0)
                expect(view.p == 5 and view.y == 5).to.beTrue()
            end
        },
        {
            name = "Perception: a one-tick glimpse is recognised after the reaction delay even when a tick is late",
            func = function()
                local lib = must(PW.BotPerception)
                local foe = { name = "foe" }
                local params = lib.ParamsFor(nil, "regular")
                local state = lib.NewState()
                ---@param t number
                ---@param seen PW.BotSnapshotSet
                ---@return boolean
                local function tickAt(t, seen)
                    lib.Think(state, { params = params, seen = seen }, t)
                    local c = state.memory[foe]
                    return c ~= nil and c.visible
                end
                -- Seen in the first snapshot only (the bot turned away), then the ticks run 0.1 s apart with one
                -- 0.14 s late tick: the latest-old-enough rule alone jumps over the glimpse and never recognises it.
                local glimpse = { [foe] = { pos = Vector(800, 0, 0), vel = Vector(0, 0, 0) } }
                ---@type boolean[]
                local visible = { tickAt(0, glimpse) }
                for _, t in ipairs({ 0.1, 0.2, 0.3, 0.42, 0.56, 0.66 }) do visible[#visible + 1] = tickAt(t, {}) end
                for i = 1, 4 do expect(visible[i]).to.beFalse() end
                expect(visible[5] or visible[6]).to.beTrue()
                expect(visible[7]).to.beFalse()
            end
        },
        {
            name = "fight is not entered on a contact that was lost before, whatever its age",
            func = function()
                local brain = must(PW.BotBrain)
                local foe = { name = "foe" } --[[@as Entity]]
                local b = combatBoard({ sighting(foe, false, 0.2) })
                local state = brain.NewState()
                brain.Think(state, combatEnv(b), now)
                expect(topOf(state) ~= "fight").to.beTrue()
            end
        },
        {
            name = "Engagement on gm_construct: in 3 duels both regular bots fire within 3.5 s of mutual sight",
            async = true,
            timeout = 60,
            func = function(state)
                local bots = state.bots --[[@as Player[] ]]
                expect(#bots).to.equal(2)
                local a, b = duelSpots()
                if game.GetMap() ~= "gm_construct" or a == nil or b == nil then
                    print("[PW] engagement skipped: map " .. game.GetMap() .. ", spots " .. tostring(a))
                    done()
                    return
                end
                runSeries(bots, must(a), must(b), 1, {}, function(results)
                    print("[PW] engagement since mutual sight: " .. table.concat(results, " "))
                    expect(#results).to.equal(duels * 2)
                    for _, latency in ipairs(results) do expect(latency <= engageBound).to.beTrue() end
                    done()
                end)
            end
        }
    }
}
