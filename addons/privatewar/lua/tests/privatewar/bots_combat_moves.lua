-- T-11.6 bot combat movement (07-bots.md d.13 revision 2026-11-07): cover under fire with hide and peek, strafing
-- while shooting, running between covers, melee at close range, the optional Quick Slide support. Pure cases: the
-- rules of PW.BotTactics (sh_moves.lua), the input keys of PW.BotInput, the detection of PW.BotQuickSlide, and the
-- brain's Think over the real behaviour files with fixture facts and a fake ctx api. One in-game smoke case: a bot
-- under fire on gm_construct reaches a cover point.

local now = 1000

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

---@return PW.BotQuickSlideLib
local function quickSlide()
    return must(PW.BotQuickSlide)
end

local ids = { "fight", "take_cover", "reload_cover", "retaliate", "search", "third_party", "melee", "idle" }

---@return PW.BotBehavior[]
local function behaviors()
    local registry = must(PW.BotBehaviors)
    ---@type PW.BotBehavior[]
    local list = {}
    for _, id in ipairs(ids) do list[#list + 1] = must(registry.Get(id)) --[[@as PW.BotBehavior]] end
    return list
end

---Facts of a healthy, standing, running bot at the origin with a full magazine and a crowbar.
---@param over table<string, any>?
---@return PW.BotCombatFacts
local function facts(over)
    ---@type table<string, any>
    local f = { at = now, pos = Vector(0, 0, 0), health = 100, maxHealth = 100, clip = 30, capacity = 30,
        reserve = 90, reloading = false, lethal = 0, profile = tactics().ProfileFor(nil, nil, "regular"),
        speed = 400, runSpeed = 600, onGround = true, crouching = false, active = "weapon_smg1",
        melee = "weapon_crowbar" }
    for k, v in pairs(over or {}) do f[k] = v end
    return f --[[@as PW.BotCombatFacts]]
end

---@param name string
---@return Entity
local function enemy(name)
    return { name = name } --[[@as Entity]]
end

---@param ent Entity
---@param pos Vector
---@param visible boolean
---@param age number?
---@return PW.BotContact
local function contact(ent, pos, visible, age)
    return { ent = ent, pos = pos, vel = Vector(0, 0, 0), time = now - (age or 0), visible = visible, source = "sight" }
end

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

---A fake ctx api that records the calls; every point is walkable.
---@return PW.BotBrainApi, table<string, any[]>
local function fakeApi()
    ---@type table<string, any[]>
    local calls = { setGoal = {}, clearGoal = {}, bash = {} }
    ---@type PW.BotBrainApi
    local api = {
        setGoal = function(_, point, radius, priority)
            calls.setGoal[#calls.setGoal + 1] = { point = point, radius = radius, priority = priority }
            return true, "moving"
        end,
        clearGoal = function() calls.clearGoal[#calls.clearGoal + 1] = true end,
        searchPlan = function() return nil end,
        walkable = function() return true end,
        bash = function()
            calls.bash[#calls.bash + 1] = true
            return false
        end
    }
    return api, calls
end

---A brain over the real behaviours: think(at) runs one tick and returns the running id.
---@param b PW.BotBoard
---@return fun(at: number): string, table<string, any[]>, PW.BotBrainState
local function brainFor(b)
    local brain = must(PW.BotBrain)
    local state = brain.NewState()
    local api, calls = fakeApi()
    ---@type PW.BotBrainEnv
    local env = { bot = "bot", board = b, behaviors = behaviors(), random = function() return 0 end, api = api }
    return function(at)
        brain.Think(state, env, at)
        local top = state.stack[#state.stack]
        return top and top.id or "-", calls, state
    end
end

---A cover 250 units from the bot (farther than Config.coverSprintMin); the peek is standing up in place.
---@param over table<string, any>?
---@return PW.BotCover
local function cover(over)
    ---@type table<string, any>
    local c = { pos = Vector(-200, 150, 0), peek = Vector(-200, 150, 0), standPeek = true,
        threatPos = Vector(900, 0, 0), at = now - 0.5, score = 1 }
    for k, v in pairs(over or {}) do c[k] = v end
    return c --[[@as PW.BotCover]]
end

---Slide facts that pass every common condition.
---@param over table<string, any>?
---@return PW.BotSlideFacts
local function slideFacts(over)
    ---@type table<string, any>
    local s = { available = true, cooling = false, onGround = true, crouching = false, speed = 400, runSpeed = 600,
        roll = 0, chance = 0.6 }
    for k, v in pairs(over or {}) do s[k] = v end
    return s --[[@as PW.BotSlideFacts]]
end

---@param intent PW.BotIntent
---@param over table<string, any>?
---@return integer
local function keys(intent, over)
    ---@type table<string, any>
    local f = { now = now, eye = Angle(0, 0, 0), slide = true, slideTime = 0.75 }
    for k, v in pairs(over or {}) do f[k] = v end
    return must(PW.BotInput).Translate(intent, nil, must(PW.BotInput).NewState(), f --[[@as PW.BotInputFacts]]).buttons
end

---@param mask integer
---@param flag integer
---@return boolean
local function has(mask, flag)
    return bit.band(mask, flag) ~= 0
end

local smokeHook = "PW.BotsCombatMovesTest"

---A threat point 500-900 units from the spot on about one level, or nil.
---@param spot Vector
---@param areas CNavArea[]
---@return Vector?
local function threatFor(spot, areas)
    for _, b in ipairs(areas) do
        local threat = b:GetCenter()
        local d = spot:Distance2D(threat)
        if d >= 500 and d <= 900 and math.abs(spot.z - threat.z) < 24 then return threat end
    end
    return nil
end

---Up to 6 pairs of a bot spot (an area with navmesh hiding spots, so cover is near) and a threat point.
---@return { spot: Vector, threat: Vector }[]
local function smokePairs()
    ---@type CNavArea[]
    local areas = navmesh.GetAllNavAreas()
    ---@type { spot: Vector, threat: Vector }[]
    local found = {}
    for _, a in ipairs(areas) do
        if #found >= 6 then break end
        local roomy = a:GetSizeX() >= 48 and a:GetSizeY() >= 48
        local threat = roomy and #(a:GetHidingSpots() --[[@as Vector[] ]]) > 0 and threatFor(a:GetCenter(), areas)
        if threat then found[#found + 1] = { spot = a:GetCenter(), threat = threat } end
    end
    return found
end

return {
    groupName = "PW bots combat moves",
    beforeAll = function(state)
        local bot = player.CreateNextBot("PW moves") --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then
            bot:SetTeam(must(PW.MatchRules).FreeTeam)
            bot:Spawn()
        end
        state.bot = bot
    end,
    afterAll = function(state)
        local bot = state.bot --[[@as Player?]]
        timer.Remove(smokeHook)
        hook.Remove("PW_IsEnemy", smokeHook)
        if IsValid(state.prop) then (state.prop --[[@as Entity]]):Remove() end
        if bot ~= nil and IsValid(bot) then
            PW._BotsManager.boards[bot] = nil
            local goal = PW.BotGoal
            if goal ~= nil and goal._Drop ~= nil then goal._Drop(bot) end
            bot:Kick("PW bots combat moves test finished")
        end
    end,
    beforeEach = function(state)
        state.log = PW._Call.log
        rawset(PW._Call, "log", function() end)
    end,
    afterEach = function(state)
        rawset(PW._Call, "log", state.log)
    end,
    cases = {
        {
            name = "Mandatory (T-11.6) under fire a bot chooses take_cover and alternates hide and peek",
            func = function()
                stub(tactics(), "Random").returns(0)
                local a = enemy("a")
                local b = board(facts({ hurtAt = now - 0.5, cover = cover() }), { contact(a, Vector(900, 0, 0), true) })
                local think = brainFor(b)
                expect(think(now)).to.equal("take_cover")
                b.goal = { point = cover().pos, radius = 24, priority = "tactical", status = "arrived", since = now }
                expect(think(now + 0.3)).to.equal("take_cover")
                expect(must(b.intent).stance).to.equal("crouch")
                expect(think(now + 1.2)).to.equal("take_cover")
                expect(must(b.intent).stance).to.equal("stand")
                expect(think(now + 2.6)).to.equal("take_cover")
                expect(must(b.intent).stance).to.equal("crouch")
                expect(think(now + 3.5)).to.equal("take_cover")
                expect(must(b.intent).stance).to.equal("stand")
            end
        },
        {
            name = "take_cover: outnumbered is survival; a close enemy is fought, not run from; no cover, no cover",
            func = function()
                local lib = tactics()
                ---@type PW.BotCoverInput
                local base = { hasCover = true, health = 1, hurt = false, visibleCount = 2, engaged = true,
                    running = false, dist = 900, coverChance = 0.3 }
                expect(lib.CoverWanted(base)).to.equal("survival")
                expect(lib.CoverWanted(table.Merge(table.Copy(base), { dist = 150 }))).to.equal(false)
                expect(lib.CoverWanted(table.Merge(table.Copy(base), { hasCover = false }))).to.equal(false)
                local calm = table.Merge(table.Copy(base), { visibleCount = 1 })
                local rank, weight = lib.CoverWanted(calm)
                expect(rank).to.equal("combat")
                expect(weight < 1.15).to.beTrue()
                local _, held = lib.CoverWanted(table.Merge(table.Copy(calm), { running = true }))
                expect(held >= 1).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-11.6) while firing at a visible target the bot strafes (lateral movement intent)",
            func = function()
                stub(tactics(), "Random").returns(0)
                local a = enemy("a")
                local b = board(facts(), { contact(a, Vector(800, 0, 0), true) })
                local id, calls = brainFor(b)(now)
                expect(id).to.equal("fight")
                local drive = must(must(b.intent).drive)
                expect(drive.x).to.equal(0)
                expect(math.abs(drive.y) > 0).to.beTrue()
                expect(#calls.setGoal).to.equal(0)
                local recruit = facts({ profile = tactics().ProfileFor(nil, nil, "recruit") })
                local still = board(recruit, { contact(a, Vector(800, 0, 0), true) })
                expect(brainFor(still)(now)).to.equal("fight")
                expect(must(still.intent).drive).to.beNil()
            end
        },
        {
            name = "Strafe legs: a mobile personality jitters (shorter legs); mobility and slide come from the data",
            func = function()
                local lib = tactics()
                local profiles = must(PW.BotProfiles)
                ---@type table<string, table>
                local byId = {}
                for _, e in ipairs(profiles.Entities("personality")) do
                    byId[(e --[[@as table<string, any>]]).ClassName] = profiles.Snapshot(e)
                end
                local run = lib.ProfileFor(byId.run_and_gun, nil, "regular")
                local camp = lib.ProfileFor(byId.camper, nil, "regular")
                expect(run.mobility > camp.mobility).to.beTrue()
                expect(lib.LegLength(run, 0.5) < lib.LegLength(camp, 0.5)).to.beTrue()
                expect(lib.ProfileFor(nil, nil, "recruit").slide).to.equal(0)
                expect(lib.ProfileFor(nil, nil, "veteran").slide).to.equal(0.6)
            end
        },
        {
            name = "Mandatory (T-11.6) between covers the bot runs: a sprint intent, the aim let go, the input sprints",
            func = function()
                stub(tactics(), "Random").returns(0)
                local a = enemy("a")
                local b = board(facts({ hurtAt = now - 0.5, cover = cover() }), { contact(a, Vector(900, 0, 0), true) })
                local think = brainFor(b)
                expect(think(now)).to.equal("take_cover")
                expect(must(b.intent).sprint).to.beTrue()
                expect(b.target).to.beNil()
                local buttons = keys({ buttons = IN_ATTACK, move = Vector(600, 0, 0), sprint = true })
                expect(has(buttons, IN_SPEED)).to.beTrue()
                expect(has(buttons, IN_ATTACK)).to.beFalse()
                b.goal = { point = cover().pos, radius = 24, priority = "tactical", status = "arrived", since = now }
                think(now + 0.3)
                expect(must(b.intent).sprint).to.beNil()
                think(now + 0.6)
                expect(b.target).to.equal(a)
            end
        },
        {
            name = "Sprint rules: long legs by mobility; never backwards; the next behaviour drops the sprint",
            func = function()
                local lib = tactics()
                local p = lib.ProfileFor({ mobility = 0.9 }, nil, "regular")
                expect(lib.SprintWanted(1000, p, 0.5)).to.beTrue()
                expect(lib.SprintWanted(1000, p, 0.95)).to.beFalse()
                expect(lib.SprintWanted(100, p, 0)).to.beFalse()
                expect(has(keys({ buttons = 0, move = Vector(-600, 0, 0), sprint = true }), IN_SPEED)).to.beFalse()
                local b = board(facts(), {})
                must(b.intent).sprint = true
                must(b.intent).drive = Vector(0, 300, 0)
                brainFor(b)(now)
                expect(must(b.intent).sprint).to.beNil()
                expect(must(b.intent).drive).to.beNil()
            end
        },
        {
            name = "Mandatory (T-11.6) at close range the bot chooses melee and not a firearm",
            func = function()
                local a = enemy("a")
                local b = board(facts(), { contact(a, Vector(80, 0, 0), true) })
                expect(brainFor(b)(now)).to.equal("melee")
                expect(must(b.intent).weapon).to.equal("weapon_crowbar")
                expect(b.target).to.equal(a)
                expect(must(must(b.intent).drive).x > 0).to.beTrue()
                local far = board(facts(), { contact(a, Vector(800, 0, 0), true) })
                expect(brainFor(far)(now)).to.equal("fight")
                expect(must(far.intent).weapon).to.beNil()
            end
        },
        {
            name = "Melee: a dry gun rushes from farther; no melee weapon keeps the gun and tries the base's bash",
            func = function()
                local a = enemy("a")
                local dry = board(facts({ clip = 0, reserve = 0 }), { contact(a, Vector(300, 0, 0), true) })
                expect(brainFor(dry)(now)).to.equal("melee")
                local loaded = board(facts(), { contact(a, Vector(300, 0, 0), true) })
                expect(brainFor(loaded)(now)).to.equal("fight")
                local empty = board(facts({ clip = 2 }), { contact(a, Vector(80, 0, 0), true) })
                expect(brainFor(empty)(now)).to.equal("melee")
                local bare = board(facts(), { contact(a, Vector(80, 0, 0), true) })
                must(bare.tactics).melee = nil
                local id, calls = brainFor(bare)(now)
                expect(id).to.equal("fight")
                expect(#calls.bash).to.equal(1)
            end
        },
        {
            name = "Mandatory (T-11.6) Quick Slide: detected only with the addon's public surface (both branches)",
            func = function()
                local qs = quickSlide()
                expect(qs.Detect({ getSliding = true, convar = true, hook = false })).to.beTrue()
                expect(qs.Detect({ getSliding = true, convar = false, hook = true })).to.beTrue()
                expect(qs.Detect({ getSliding = false, convar = true, hook = true })).to.beFalse()
                expect(qs.Detect({ getSliding = true, convar = false, hook = false })).to.beFalse()
            end
        },
        {
            name = "Mandatory (T-11.6) Quick Slide is used only when detected and never when absent",
            func = function()
                stub(tactics(), "Random").returns(0)
                local a = enemy("a")
                local hit = facts({ hurtAt = now - 0.2, profile = tactics().ProfileFor(nil, nil, "veteran") })
                stub(quickSlide(), "Available").returns(false)
                local without = board(table.Copy(hit), { contact(a, Vector(400, 0, 0), true) })
                brainFor(without)(now)
                expect(must(without.intent).slideAt).to.beNil()
                local ignored = keys({ buttons = 0, move = Vector(400, 0, 0), slideAt = now }, { slide = false })
                expect(has(ignored, IN_DUCK) or has(ignored, IN_SPEED)).to.beFalse()
                stub(quickSlide(), "Available").returns(true)
                local with = board(table.Copy(hit), { contact(a, Vector(400, 0, 0), true) })
                brainFor(with)(now)
                expect(must(with.intent).slideAt).to.equal(now)
                local start = keys({ buttons = IN_ATTACK, move = Vector(400, 0, 0), slideAt = now })
                expect(has(start, IN_DUCK) and has(start, IN_SPEED)).to.beTrue()
                expect(has(start, IN_ATTACK)).to.beFalse()
                local held = keys({ buttons = 0, move = Vector(400, 0, 0), slideAt = now - 0.5 })
                expect(has(held, IN_DUCK) and not has(held, IN_SPEED)).to.beTrue()
                expect(has(keys({ buttons = 0, slideAt = now - 1 }), IN_DUCK)).to.beFalse()
            end
        },
        {
            name = "Mandatory (T-11.6) slide triggers: peek, dodge and close each only under their own conditions",
            func = function()
                local lib = tactics()
                expect(lib.SlideWanted("peek", slideFacts({ dist = 100 }))).to.beTrue()
                expect(lib.SlideWanted("peek", slideFacts({ dist = 20 }))).to.beFalse()
                expect(lib.SlideWanted("dodge", slideFacts({ hurtAge = 0.2 }))).to.beTrue()
                expect(lib.SlideWanted("dodge", slideFacts({ hurtAge = 2 }))).to.beFalse()
                expect(lib.SlideWanted("dodge", slideFacts({ dist = 100 }))).to.beFalse()
                expect(lib.SlideWanted("close", slideFacts({ dist = 300 }))).to.beTrue()
                expect(lib.SlideWanted("close", slideFacts({ dist = 80 }))).to.beFalse()
                expect(lib.SlideWanted("close", slideFacts({ dist = 900 }))).to.beFalse()
                expect(lib.SlideWanted("jump", slideFacts({ dist = 300, hurtAge = 0.1 }))).to.beFalse()
                local ok = { dist = 300 }
                expect(lib.SlideWanted("close", slideFacts(table.Merge({ available = false }, ok)))).to.beFalse()
                expect(lib.SlideWanted("close", slideFacts(table.Merge({ cooling = true }, ok)))).to.beFalse()
                expect(lib.SlideWanted("close", slideFacts(table.Merge({ crouching = true }, ok)))).to.beFalse()
                expect(lib.SlideWanted("close", slideFacts(table.Merge({ onGround = false }, ok)))).to.beFalse()
                expect(lib.SlideWanted("close", slideFacts(table.Merge({ speed = 200 }, ok)))).to.beFalse()
                expect(lib.SlideWanted("close", slideFacts(table.Merge({ roll = 0.7 }, ok)))).to.beFalse()
                expect(lib.SlideWanted("close", slideFacts(table.Merge({ chance = 0 }, ok)))).to.beFalse()
            end
        },
        {
            name = "Quick Slide peek: a step-out peek slides, a stand-up peek does not",
            func = function()
                stub(tactics(), "Random").returns(0)
                stub(quickSlide(), "Available").returns(true)
                local a = enemy("a")
                local vet = tactics().ProfileFor(nil, nil, "veteran")
                local step = cover({ standPeek = false, peek = Vector(-200, 300, 0) })
                for _, case in ipairs({ { step, true }, { cover(), false } }) do
                    local b = board(facts({ hurtAt = now - 0.5, cover = case[1], profile = vet }),
                        { contact(a, Vector(900, 0, 0), true) })
                    local think = brainFor(b)
                    think(now)
                    b.goal = { point = case[1].pos, radius = 24, priority = "tactical", status = "arrived",
                        since = now }
                    think(now + 0.3)
                    must(b.intent).slideAt = nil
                    think(now + 1.2)
                    expect(must(b.intent).slideAt ~= nil).to.equal(case[2])
                end
            end
        },
        {
            name = "Cover search: a hidden cover without a traced peek gets a side step out of it",
            func = function()
                local lib = tactics()
                local threat = Vector(1000, 0, 0)
                ---@type PW.BotCoverCandidate[]
                local cands = { { pos = Vector(-300, 0, 0), spot = true, hidden = true, standOpen = false } }
                cands[1].pre = lib.PreScore(cands[1], Vector(0, 0, 0), threat)
                local best = must(lib.PickCover(cands, threat, now))
                local peek = must(best.peek)
                expect(best.guessed).to.beTrue()
                expect(math.abs(peek:Distance(best.pos) - lib.Config.peekStep) < 1).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-11.6), smoke on gm_construct: a bot under fire reaches a cover point",
            async = true,
            timeout = 90,
            func = function(state)
                local bot = state.bot --[[@as Player?]]
                local spots = smokePairs()
                if game.GetMap() ~= "gm_construct" or bot == nil or not IsValid(bot) or #spots == 0 then
                    print("[PW] combat moves smoke skipped: map " .. game.GetMap() .. ", pairs " .. #spots)
                    done()
                    return
                end
                ---@cast bot Player
                if not bot:Alive() then bot:Spawn() end
                bot:GodEnable()
                local prop = ents.Create("prop_physics")
                prop:SetModel("models/props_junk/wood_crate001a.mdl")
                prop:Spawn()
                prop:SetMoveType(MOVETYPE_NONE)
                state.prop = prop
                hook.Add("PW_IsEnemy", smokeHook, function(a, b)
                    if (a == bot and b == prop) or (a == prop and b == bot) then return true end
                end)
                local started, attempt, attemptAt = CurTime(), 0, 0
                ---@type Vector?
                local threatPos = nil
                ---@type Vector[]
                local covers = {}
                ---Places the bot and the shooter for the next pair, with a fresh board.
                local function nextAttempt()
                    attempt, attemptAt, covers = attempt + 1, CurTime(), {}
                    local pair = spots[attempt]
                    threatPos = pair.threat
                    bot:SetPos(pair.spot)
                    prop:SetPos(pair.threat + Vector(0, 0, 24))
                    PW._BotsManager.boards[bot] = { bot = bot }
                end
                nextAttempt()
                timer.Create(smokeHook, 0.25, 0, function()
                    local b = PW._BotsManager.boards[bot]
                    if not IsValid(bot) or b == nil or threatPos == nil then return end
                    -- Under fire: a fresh hit (no attacker seen, so not retaliate) and the shooter's position known.
                    PW._BotTactics.hurt[bot] = { at = CurTime() } --[[@as { at: number, attacker: Entity }]]
                    must(PW.Bot).AddStimulus(bot, "damage", { ent = prop, pos = threatPos, time = CurTime() })
                    local behavior = b.behavior
                    local f = b.tactics
                    if behavior ~= nil and behavior.id == "take_cover" and f ~= nil and f.cover ~= nil then
                        covers[#covers + 1] = f.cover.pos
                    end
                    local reached = false
                    for _, c in ipairs(covers) do reached = reached or bot:GetPos():Distance2D(c) <= 64 end
                    local late = CurTime() - started > 80
                    if not reached and not late and #covers == 0 and CurTime() - attemptAt > 8
                        and attempt < #spots then
                        print(string.format("[PW] combat moves smoke: attempt %d found no cover (%s)", attempt,
                            behavior and behavior.id or "none"))
                        nextAttempt()
                        return
                    end
                    if not reached and not late then return end
                    timer.Remove(smokeHook)
                    print(string.format("[PW] combat moves smoke: reached %s after %.1f s, attempt %d, %d samples, %s",
                        tostring(reached), CurTime() - started, attempt, #covers, behavior and behavior.id or "none"))
                    bot:GodDisable()
                    PW._BotsManager.boards[bot] = nil
                    expect(reached).to.beTrue()
                    done()
                end)
            end
        }
    }
}
