-- T-5.10 (first half) survival and combat behaviours (07-bots.md d.13): fight, take_cover, reload_cover, retaliate,
-- search, third_party, throw_equipment. Pure cases: the brain's Think over the real behaviour files with fixture
-- facts (board.tactics, contacts, memory), a fake ctx api and a fixed random source. One in-game smoke case: two
-- hostile managed bots facing each other on gm_construct start shooting.

local now = 1000

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotTacticsLib
local function tactics()
    return must(PW.BotTactics)
end

local ids = { "fight", "take_cover", "reload_cover", "retaliate", "search", "third_party", "throw_equipment", "idle" }

---@return PW.BotBehavior[]
local function behaviors()
    local registry = must(PW.BotBehaviors)
    ---@type PW.BotBehavior[]
    local list = {}
    for _, id in ipairs(ids) do list[#list + 1] = must(registry.Get(id)) --[[@as PW.BotBehavior]] end
    return list
end

---Facts of a healthy bot at the origin with a full magazine.
---@param over table<string, any>?
---@return PW.BotCombatFacts
local function facts(over)
    ---@type table<string, any>
    local f = { at = now, pos = Vector(0, 0, 0), health = 100, maxHealth = 100, clip = 30, capacity = 30,
        reserve = 90, reloading = false, lethal = 0, profile = tactics().ProfileFor(nil, nil, "regular") }
    for k, v in pairs(over or {}) do f[k] = v end
    return f --[[@as PW.BotCombatFacts]]
end

---A fake enemy entity (plain table: behaviours never touch the engine).
---@param name string
---@return Entity
local function enemy(name)
    return { name = name } --[[@as Entity]]
end

---@param ent Entity
---@param pos Vector
---@param visible boolean
---@param source string
---@param age number?
---@return PW.BotContact
local function contact(ent, pos, visible, source, age)
    return { ent = ent, pos = pos, vel = Vector(0, 0, 0), time = now - (age or 0), visible = visible, source = source }
end

---A board with facts and contacts (the seen first, as perception orders them).
---@param f PW.BotCombatFacts
---@param contacts PW.BotContact[]?
---@return PW.BotBoard
local function board(f, contacts)
    ---@type table<Entity, PW.BotContact>
    local memory = {}
    for _, c in ipairs(contacts or {}) do memory[c.ent] = c end
    return { bot = "bot" --[[@as Player]], tactics = f, contacts = contacts or {}, memory = memory,
        intent = { buttons = 0 } }
end

---A fake ctx api that records the calls.
---@return PW.BotBrainApi, table<string, any[]>
local function fakeApi()
    ---@type table<string, any[]>
    local calls = { setGoal = {}, clearGoal = {}, useEquipment = {} }
    ---@type PW.BotBrainApi
    local api = {
        setGoal = function(_, point, radius, priority)
            calls.setGoal[#calls.setGoal + 1] = { point = point, radius = radius, priority = priority }
            return true, "moving"
        end,
        clearGoal = function() calls.clearGoal[#calls.clearGoal + 1] = true end,
        searchPlan = function()
            return { Vector(500, 0, 0), Vector(800, 0, 0), Vector(500, 300, 0), Vector(500, -300, 0),
                Vector(1300, 0, 0) }
        end,
        useEquipment = function(_, slot)
            calls.useEquipment[#calls.useEquipment + 1] = slot
            return true
        end
    }
    return api, calls
end

---One brain tick over the real behaviours; returns the running id, the state, the env and the api calls.
---@param b PW.BotBoard
---@param at number?
---@return string, PW.BotBrainState, PW.BotBrainEnv, table<string, any[]>
local function think(b, at)
    local brain = must(PW.BotBrain)
    local state = brain.NewState()
    local api, calls = fakeApi()
    ---@type PW.BotBrainEnv
    local env = { bot = "bot", board = b, behaviors = behaviors(), random = function() return 0 end, api = api }
    brain.Think(state, env, at or now)
    local top = state.stack[#state.stack]
    return top and top.id or "-", state, env, calls
end

local cover = {
    pos = Vector(-200, 150, 0), peek = Vector(-200, 150, 0), standPeek = true, threatPos = Vector(900, 0, 0),
    at = now - 0.5, score = 1
}

local smokeHook = "PW.BotsBehaviorsCombatTest"

---A partner of centers[i] for a duel: 500-1000 units away on one level with a clear line; spends the trace budget.
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

---Two navmesh points on one level, 500-1000 units apart, with a clear line between eye heights; nil when none.
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

---A deterministic board for a duel bot: FFA (no team), the "regular" tier and the "run_and_gun" personality
---(the manager, paused during tests, would otherwise leave them unset and the values would follow the settings).
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

---One diagnostic line of a duel bot; tolerates a bot that is gone and a board without a behaviour.
---@param bot Player?
---@param firedAt table<Player, number>
---@return string
local function duelReport(bot, firedAt)
    if bot == nil or not IsValid(bot) then return "[PW] bots duel smoke: a bot is no longer valid" end
    local botBoard = PW._BotsManager.boards[bot]
    local behavior = botBoard ~= nil and botBoard.behavior or nil
    return string.format("[PW] bots duel smoke: %s fired at %s s, alive %s, health %s, behaviour %s (%s)",
        bot:Nick(), tostring(firedAt[bot]), tostring(bot:Alive()), tostring(bot:Health()),
        tostring(behavior ~= nil and behavior.id or "none"), tostring(behavior ~= nil and behavior.reason or "-"))
end

---@param bot Player
---@param pos Vector
---@param toward Vector
local function place(bot, pos, toward)
    bot:SetPos(pos)
    local ang = (toward - pos):Angle()
    bot:SetEyeAngles(Angle(0, ang.y, 0))
end

return {
    groupName = "PW bots behaviors combat",
    beforeAll = function(state)
        -- Two managed bots (the manager is paused during tests): FFA team, spawned, armed, hostile to each other.
        ---@type Player[]
        local bots = {}
        for _, name in ipairs({ "PW duel A", "PW duel B" }) do
            local bot = player.CreateNextBot(name) --[[@as Player?]]
            if bot ~= nil and IsValid(bot) then
                bot:SetTeam(must(PW.MatchRules).FreeTeam)
                bot:Spawn()
                bots[#bots + 1] = bot
            end
        end
        state.bots = bots
        hook.Add("PW_IsEnemy", smokeHook, function(a, b)
            if a ~= b and table.HasValue(bots, a) and table.HasValue(bots, b) then return true end
        end)
    end,
    afterAll = function(state)
        hook.Remove("PW_IsEnemy", smokeHook)
        hook.Remove("EntityFireBullets", smokeHook)
        ---@type Player[]
        local bots = state.bots or {}
        for _, bot in ipairs(bots) do
            if IsValid(bot) then
                PW._BotsManager.boards[bot] = nil
                local goal = PW.BotGoal
                if goal ~= nil and goal._Drop ~= nil then goal._Drop(bot) end
                bot:Kick("PW bots behaviors combat test finished")
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
            name = "Mandatory (T-5.10) fight: chosen when an enemy is visible, and it targets that enemy",
            func = function()
                local a = enemy("a")
                local b = board(facts(), { contact(a, Vector(800, 0, 0), true, "sight") })
                local id = think(b)
                expect(id).to.equal("fight")
                expect(b.target).to.equal(a)
                expect(must(b.intent).target).to.equal(a)
            end
        },
        {
            name = "Mandatory (T-5.10) fight: not chosen when no enemy is visible",
            func = function()
                local b = board(facts(), { contact(enemy("a"), Vector(800, 0, 0), false, "sight", 2) })
                expect(think(b) ~= "fight").to.beTrue()
                expect(think(board(facts()))).to.equal("idle")
            end
        },
        {
            name = "Mandatory (T-5.10) take_cover: chosen when hurt with a visible threat and a cover; moves there",
            func = function()
                local a = enemy("a")
                local f = facts({ health = 40, hurtAt = now - 0.5, attacker = a, cover = cover })
                local b = board(f, { contact(a, Vector(900, 0, 0), true, "sight") })
                local id, _, _, calls = think(b)
                expect(id).to.equal("take_cover")
                local goal = must(calls.setGoal[1])
                expect(goal.point).to.equal(cover.pos)
                expect(goal.priority).to.equal("tactical")
            end
        },
        {
            name = "Mandatory (T-5.10) take_cover: not chosen without a cover or without a threat",
            func = function()
                local a = enemy("a")
                local hurt = facts({ health = 40, hurtAt = now - 0.5, attacker = a })
                expect(think(board(hurt, { contact(a, Vector(900, 0, 0), true, "sight") }))).to.equal("fight")
                local calm = facts({ health = 40, cover = cover })
                expect(think(board(calm)) ~= "take_cover").to.beTrue()
                local stale = table.Copy(cover)
                stale.at = now - 30
                local old = facts({ health = 40, hurtAt = now - 0.5, attacker = a, cover = stale })
                expect(think(board(old, { contact(a, Vector(900, 0, 0), true, "sight") }))).to.equal("fight")
            end
        },
        {
            name = "Mandatory (T-5.10) reload_cover: chosen when the magazine is low with a threat; presses reload",
            func = function()
                local a = enemy("a")
                local b = board(facts({ clip = 3 }), { contact(a, Vector(900, 0, 0), true, "sight") })
                local id = think(b)
                expect(id).to.equal("reload_cover")
                expect(bit.band(must(b.intent).buttons, IN_RELOAD)).to.equal(IN_RELOAD)
            end
        },
        {
            name = "Mandatory (T-5.10) reload_cover: not chosen with a full enough magazine or nothing to reload",
            func = function()
                local a = enemy("a")
                local enough = board(facts({ clip = 25 }), { contact(a, Vector(900, 0, 0), true, "sight") })
                expect(think(enough)).to.equal("fight")
                local dry = board(facts({ clip = 0, reserve = 0 }), { contact(a, Vector(900, 0, 0), true, "sight") })
                expect(think(dry)).to.equal("fight")
                expect(think(board(facts({ clip = 30 })))).to.equal("idle")
            end
        },
        {
            name = "Mandatory (T-5.10) retaliate: chosen right after damage from an unseen attacker; turns to it",
            func = function()
                local a = enemy("a")
                local f = facts({ health = 80, hurtAt = now - 0.3, attacker = a })
                local b = board(f, { contact(a, Vector(-600, 0, 0), false, "damage") })
                local id = think(b)
                expect(id).to.equal("retaliate")
                expect(b.target).to.equal(a)
            end
        },
        {
            name = "Mandatory (T-5.10) retaliate: not chosen long after damage or while the attacker is in sight",
            func = function()
                local a = enemy("a")
                local old = facts({ health = 80, hurtAt = now - 6, attacker = a })
                local late = think(board(old, { contact(a, Vector(-600, 0, 0), false, "damage", 6) }))
                expect(late ~= "retaliate").to.beTrue()
                local seen = facts({ health = 80, hurtAt = now - 0.3, attacker = a })
                expect(think(board(seen, { contact(a, Vector(-600, 0, 0), true, "sight") }))).to.equal("fight")
            end
        },
        {
            name = "Mandatory (T-5.10) search: chosen when a seen enemy was lost; walks to the first search point",
            func = function()
                local a = enemy("a")
                local b = board(facts(), { contact(a, Vector(500, 0, 0), false, "sight", 3) })
                local id, _, _, calls = think(b)
                expect(id).to.equal("search")
                expect(must(calls.setGoal[1]).point).to.equal(Vector(500, 0, 0))
            end
        },
        {
            name = "Mandatory (T-5.10) search: not chosen while the enemy is visible or when only gunfire is heard",
            func = function()
                local a = enemy("a")
                expect(think(board(facts(), { contact(a, Vector(500, 0, 0), true, "sight") }))).to.equal("fight")
                local heard = board(facts(), { contact(a, Vector(1500, 0, 0), false, "gunfire", 1) })
                expect(think(heard) ~= "search").to.beTrue()
                local forgotten = board(facts(), { contact(a, Vector(500, 0, 0), false, "sight", 20) })
                expect(think(forgotten)).to.equal("idle")
            end
        },
        {
            name = "Mandatory (T-5.10) third_party: chosen when a fight is heard nearby; flanks after its delay",
            func = function()
                local a = enemy("a")
                local b = board(facts(), { contact(a, Vector(1500, 0, 0), false, "gunfire", 1) })
                local id, state, env, calls = think(b)
                expect(id).to.equal("third_party")
                expect(#calls.setGoal).to.equal(0)
                must(PW.BotBrain).Think(state, env, now + 2)
                local goal = must(calls.setGoal[1])
                expect(goal.point:Distance(Vector(1500, 0, 0)) > 200).to.beTrue()
                expect(math.abs(goal.point.y) > 200).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.10) third_party: not chosen for a far or old fight, or with an enemy in sight",
            func = function()
                local a, c = enemy("a"), enemy("c")
                expect(think(board(facts(), { contact(a, Vector(6000, 0, 0), false, "gunfire", 1) })))
                    .to.equal("idle")
                expect(think(board(facts(), { contact(a, Vector(1500, 0, 0), false, "gunfire", 10) })))
                    .to.equal("idle")
                local both = board(facts(), {
                    contact(c, Vector(700, 0, 0), true, "sight"), contact(a, Vector(1500, 0, 0), false, "gunfire", 1)
                })
                expect(think(both)).to.equal("fight")
            end
        },
        {
            name = "Mandatory (T-5.10) throw_equipment: chosen for a fresh enemy behind cover; throws the lethal",
            func = function()
                local a = enemy("a")
                local b = board(facts({ lethal = 1 }), { contact(a, Vector(900, 0, 0), false, "sight", 1) })
                local id, state, env, calls = think(b)
                expect(id).to.equal("throw_equipment")
                expect(b.target).to.equal(a)
                must(PW.BotBrain).Think(state, env, now + 1)
                expect(calls.useEquipment[1]).to.equal("lethal")
            end
        },
        {
            name = "Mandatory (T-5.10) throw_equipment: not chosen without a lethal, too close, or when in sight",
            func = function()
                local a = enemy("a")
                expect(think(board(facts(), { contact(a, Vector(900, 0, 0), false, "sight", 1) })))
                    .to.equal("search")
                expect(think(board(facts({ lethal = 1 }), { contact(a, Vector(150, 0, 0), false, "sight", 1) })))
                    .to.equal("search")
                expect(think(board(facts({ lethal = 1 }), { contact(a, Vector(900, 0, 0), true, "sight") })))
                    .to.equal("fight")
            end
        },
        {
            name = "Survival outranks combat: a hurt bot with a cover leaves fight for take_cover",
            func = function()
                local a = enemy("a")
                local b = board(facts(), { contact(a, Vector(900, 0, 0), true, "sight") })
                local id, state, env = think(b)
                expect(id).to.equal("fight")
                b.tactics = facts({ health = 30, hurtAt = now + 1, attacker = a, cover = cover })
                must(PW.BotBrain).Think(state, env, now + 1.5)
                expect(state.stack[#state.stack].id).to.equal("take_cover")
            end
        },
        {
            name = "Cover scoring: a hidden candidate near the bot wins; a stand-up peek pairs with the same point",
            func = function()
                local lib = tactics()
                local threat = Vector(1000, 0, 0)
                ---@type PW.BotCoverCandidate[]
                local cands = {
                    { pos = Vector(100, 300, 0), spot = true, hidden = true, standOpen = true },
                    { pos = Vector(-500, 0, 0), spot = false, hidden = true, standOpen = false },
                    { pos = Vector(50, 0, 0), spot = false, hidden = false, open = true }
                }
                for _, c in ipairs(cands) do c.pre = lib.PreScore(c, Vector(0, 0, 0), threat) end
                local best = must(lib.PickCover(cands, threat, now))
                expect(best.pos).to.equal(Vector(100, 300, 0))
                expect(best.standPeek).to.beTrue()
                expect(lib.PreScore({ pos = Vector(950, 0, 0), spot = true }, Vector(0, 0, 0), threat)).to.beNil()
                expect(lib.PreScore({ pos = Vector(-2000, 0, 0), spot = true }, Vector(0, 0, 0), threat)).to.beNil()
                expect(lib.PickCover({ { pos = Vector(1, 1, 0), spot = true, pre = 1, hidden = false } }, threat,
                    now)).to.beNil()
            end
        },
        {
            name = "Flank and strafe points: sideways of the line to the threat",
            func = function()
                local lib = tactics()
                local p = lib.FlankPoint(Vector(0, 0, 0), Vector(1000, 0, 0), 1, 400)
                expect(p.x > 300 and p.x < 900).to.beTrue()
                expect(math.abs(math.abs(p.y) - 400) < 1).to.beTrue()
                local q = lib.FlankPoint(Vector(0, 0, 0), Vector(1000, 0, 0), -1, 400)
                expect(p.y * q.y < 0).to.beTrue()
                local s = lib.StrafePoint(Vector(0, 0, 0), Vector(1000, 0, 0), 1, 150)
                expect(math.abs(s.x) < 1 and math.abs(math.abs(s.y) - 150) < 1).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.10), smoke on gm_construct: two hostile bots facing each other start shooting",
            async = true,
            timeout = 40,
            func = function(state)
                local bots = state.bots --[[@as Player[] ]]
                expect(#bots).to.equal(2)
                local a, b = duelSpots()
                if game.GetMap() ~= "gm_construct" or a == nil or b == nil then
                    print("[PW] bots duel smoke skipped: map " .. game.GetMap() .. ", spots " .. tostring(a))
                    done()
                    return
                end
                ---@type table<Player, number>
                local firedAt = {}
                for _, bot in ipairs(bots) do
                    -- The first bot to shoot used to kill the other before its reaction and attack delay passed (a
                    -- dead bot never fires in LOBBY): both are invulnerable for the duel, the shooting is unchanged.
                    if not bot:Alive() then bot:Spawn() end
                    bot:GodEnable()
                    bot:StripWeapons()
                    bot:Give("weapon_smg1")
                    bot:GiveAmmo(225, "SMG1", true)
                    bot:SelectWeapon("weapon_smg1")
                end
                place(bots[1], must(a), must(b))
                place(bots[2], must(b), must(a))
                local started = CurTime()
                ---@param ent Player
                hook.Add("EntityFireBullets", smokeHook, function(ent)
                    if firedAt[ent] == nil and table.HasValue(bots, ent) then firedAt[ent] = CurTime() - started end
                end)
                for _, bot in ipairs(bots) do PW._BotsManager.boards[bot] = duelBoard(bot) end
                timer.Create(smokeHook, 0.25, 0, function()
                    local both = firedAt[bots[1]] ~= nil and firedAt[bots[2]] ~= nil
                    local gone = not (IsValid(bots[1]) and IsValid(bots[2]))
                    local late = CurTime() - started > 30
                    if not both and not late and not gone then return end
                    timer.Remove(smokeHook)
                    hook.Remove("EntityFireBullets", smokeHook)
                    for _, bot in ipairs(bots) do
                        print(duelReport(bot, firedAt))
                        if IsValid(bot) then bot:GodDisable() end
                        PW._BotsManager.boards[bot] = nil
                    end
                    expect(both).to.beTrue()
                    done()
                end)
            end
        }
    }
}
