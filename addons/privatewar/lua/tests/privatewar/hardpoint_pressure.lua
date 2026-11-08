-- Opt-in pressure must not change the legacy behavior of other modes or invent enemy knowledge.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil, "Hardpoint pressure dependency absent") return value end

---@param urgency? number
---@return PW.BotObjective
local function objective(urgency)
    return { id = "current_zone", revision = 1, action = "hold", pos = Vector(1000, 0, 0), radius = 40,
        weight = 1, want = 4, urgency = urgency,
        zone = { pos = Vector(1000, 0, 0), radius = 160, above = 100, below = 20 } }
end

---@param target PW.BotObjective
---@param distance number
---@param visible? boolean
---@return PW.BotBrainState, PW.BotBrainEnv
local function environment(target, distance, visible)
    local foe = { name = "recognized_enemy" } --[[@as Entity]]
    local bot = { IsValid = function() return true end, UserID = function() return 1 end } --[[@as Player]]
    local contact = { ent = foe, pos = Vector(distance, 0, 0), vel = Vector(), time = 100,
        source = "sight", visible = visible ~= false }
    local tactics = must(PW.BotTactics)
    ---@type PW.BotBoard
    local board = { bot = bot, team = 1, contacts = { contact }, memory = { [foe] = contact },
        order = { id = target.id, objective = target, type = target.action, since = 100, priority = 1 },
        intent = { buttons = 0 }, tactics = { at = 100, pos = Vector(), health = 100, maxHealth = 100,
            clip = 30, capacity = 30, reserve = 90, reloading = false, lethal = 0,
            profile = tactics.ProfileFor(nil, nil, "regular") } }
    ---@type PW.BotFacts
    local facts = { pos = Vector(), team = 1, mode = "synthetic_mode", objectives = { target }, mates = {},
        deaths = {}, candidates = {}, stationary = false, teamwork = 1 }
    ---@type PW.BotBehavior[]
    local behaviors = {}
    for _, id in ipairs({ "objective", "fight", "take_cover", "search", "idle" }) do
        behaviors[#behaviors + 1] = must(must(PW.BotBehaviors).Get(id)) --[[@as PW.BotBehavior]]
    end
    local env = { bot = board.bot, board = board, behaviors = behaviors, mode = "synthetic_mode",
        random = function() return 0 end, api = { facts = function() return facts end,
            random = function() return 0 end, clearGoal = function() board.goal = nil end,
            bash = function() return false end, walkable = function() return true end,
            setGoal = function(_, point, radius, priority)
                board.goal = { point = point, projected = point, radius = radius, priority = priority,
                    status = "moving", since = 100 }
                return true, "moving"
            end } }
    return must(PW.BotBrain).NewState(), env
end

---@param state PW.BotBrainState
---@param env PW.BotBrainEnv
---@return string
local function think(state, env)
    must(PW.BotBrain).Think(state, env, 100)
    return must(state.stack[#state.stack]).id
end

return {
    groupName = "PW Hardpoint objective pressure",
    afterEach = function(state)
        if state.mode ~= nil then must(PW.Hardpoint).Cleanup(state.mode) end
    end,
    cases = {
        {
            name = "Hardpoint pressure: sanitizer clamps opt-in urgency without rejecting legacy objectives",
            func = function()
                local commander = must(PW.BotCommander)
                for _, value in ipairs({ -2, 0, 0.5, 1, 2, math.huge, -math.huge, 0 / 0 }) do
                    local clean = must(commander.Sanitize({ objective(value) })[1])
                    local expected = math.abs(value) < math.huge and value == value and math.Clamp(value, 0, 1) or 0
                    expect(clean.urgency or 0).to.equal(expected)
                end
                local legacy = objective()
                expect(commander.Sanitize({ legacy })[1]).to.deepEqual(legacy)
                local raw = objective() --[[@as table<string, any>]]
                raw.urgency, raw.enemy = "bad", "hidden"
                local clean = must(commander.Sanitize({ raw })[1])
                expect(clean.urgency or 0).to.equal(0)
                expect(rawget(clean, "enemy")).to.beNil()
            end
        },
        {
            name = "Hardpoint pressure: urgent travel beats distant combat and retains the recognized aim target",
            func = function()
                local state, env = environment(objective(1), 900)
                must(env.board.intent).drive = Vector(0, 200, 0)
                expect(think(state, env)).to.equal("objective")
                expect(must(env.board.goal).priority).to.equal("objective")
                expect(env.board.target).to.equal(must(env.board.contacts)[1].ent)
                expect(must(env.board.intent).sprint == true).to.beFalse()
                expect(must(env.board.intent).drive).to.beNil()
                expect(state.stack[#state.stack].rank < 40).to.beTrue()
            end
        },
        {
            name = "Hardpoint pressure: recognized threats at or within 400 units still trigger ordinary combat",
            func = function()
                for _, distance in ipairs({ 100, 399, 400 }) do
                    local state, env = environment(objective(1), distance)
                    expect(think(state, env)).to.equal("fight")
                end
                local state, env = environment(objective(1), 401)
                expect(think(state, env)).to.equal("objective")
                state, env = environment(objective(1), 100, false)
                expect(think(state, env)).to.equal("objective")
                expect(env.board.target).to.beNil()
            end
        },
        {
            name = "Hardpoint pressure: cached urgent travel yields to an approaching recognized near threat",
            func = function()
                local state, env = environment(objective(1), 900)
                expect(think(state, env)).to.equal("objective")
                must(env.board.contacts)[1].pos = Vector(300, 0, 0)
                must(PW.BotBrain).Think(state, env, 100.1) -- same contact, before the 0.5s Rank interval
                local top = state.stack[#state.stack]
                expect(top == nil or top.id ~= "objective").to.beTrue()
                must(PW.BotBrain).Think(state, env, 100.2)
                expect(must(state.stack[#state.stack]).id).to.equal("fight")
            end
        },
        {
            name = "Hardpoint pressure: an occupied zone stays the goal instead of chasing a distant enemy",
            func = function()
                local target = objective(0.5)
                local state, env = environment(target, 1900)
                expect(think(state, env)).to.equal("objective")
                must(env.board.tactics).pos = target.pos
                must(state.ctx.facts).pos = target.pos
                must(PW.BotBrain).Think(state, env, 100.6)
                expect(must(state.stack[#state.stack]).id).to.equal("objective")
                expect(must(env.board.goal).point:Distance(target.pos) <= 160).to.beTrue()
            end
        },
        {
            name = "Hardpoint pressure: immediate survival remains above urgent objective travel",
            func = function()
                local state, env = environment(objective(1), 900)
                local facts = must(env.board.tactics)
                facts.health, facts.hurtAt = 20, 99.9
                facts.cover = { pos = Vector(0, 200, 0), peek = Vector(20, 200, 0), standPeek = false,
                    threatPos = Vector(900, 0, 0), at = 100, score = 1 }
                expect(think(state, env)).to.equal("take_cover")
                expect(state.stack[#state.stack].rank).to.equal(40)
            end
        },
        {
            name = "Hardpoint pressure: absent urgency preserves legacy combat-first selection and order geometry",
            func = function()
                local state, env = environment(objective(), 900)
                expect(think(state, env)).to.equal("fight")
                local ordered = objective(1)
                local commander = must(PW.BotCommander)
                local order = must(commander.Assign({ { id = 1, pos = Vector() } }, { ordered }, {}, 100)[1])
                expect(order.objective.urgency).to.equal(1)
                expect(order.objective.zone).to.deepEqual(ordered.zone)
                expect(order.objective.revision).to.equal(1)
            end
        },
        {
            name = "Hardpoint pressure: HP emits current-zone urgency when empty enemy contested or behind",
            func = function(test)
                local hp = must(PW.Hardpoint)
                local mode = { ClassName = "hardpoint", Name = "Pressure fixture", Teams = 2,
                    _ScoreKey = "pw_hp_score_", HudScoreKey = "pw_hp_score_", Setting = function(_, key)
                    return ({ zonetime = 60, scorelimit = 250, timelimit = 600 })[key]
                end } --[[@as PW.HardpointMode]]
                test.mode = mode
                stub(hp, "Send").with(function() end)
                hp.Start(mode)
                local runtime = must(mode._Hardpoint) --[[@as PW.HardpointRuntime]]
                local state = runtime.state
                for _, control in ipairs({ 0, 2 }) do
                    state.control = control
                    expect(must(hp.Objectives(mode, 1)[1]).urgency).to.equal(1)
                end
                state.control, state.contested = 1, true
                expect(must(hp.Objectives(mode, 1)[1]).urgency).to.equal(1)
                state.contested, state.scores[2] = false, 100
                expect(must(hp.Objectives(mode, 1)[1]).urgency).to.equal(1)
                local orders = hp.Objectives(mode, 1)
                expect(#orders).to.equal(1)
                expect(orders[1].pos).to.equal(state.layout.zones[state.index].pos)
            end
        }
    }
}
