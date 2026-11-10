-- A natural capture exposed separate objects in published contacts and newer sound/damage memory.
-- Drive the actual perception queue, registered retaliation and brain. No engine actors or hidden world reads.
---@class PW.RetaliateVisibilityFixture
---@field perception PW.BotPerceptionState
---@field params PW.BotPerceptionParams
---@field attacker Entity
---@field bot Player
---@field board PW.BotBoard
---@field brain PW.BotBrainState
---@field env PW.BotBrainEnv

---@return PW.BotBehavior
local function retaliate()
    return assert(assert(PW.BotBehaviors).Get("retaliate")) --[[@as PW.BotBehavior]]
end

---@return PW.RetaliateVisibilityFixture
local function fixture()
    local p, b = assert(PW.BotPerception), assert(PW.BotBrain)
    local attacker = { IsValid = function() return true end,
        GetPos = function() error("retaliation cannot query hidden attacker world coordinates") end } --[[@as Entity]]
    local bot = {} --[[@as Player]]
    local params = p.ParamsFor(nil, "regular")
    params.reaction_mean, params.reaction_floor, params.reaction_jitter = 0.45, 0.1, 0
    local perception = p.NewState()
    local board = { bot = bot, contacts = perception.contacts, memory = perception.memory,
        intent = { buttons = 0 }, tactics = { at = 10, pos = Vector(), health = 100, maxHealth = 100,
            clip = 30, capacity = 30, reserve = 90, reloading = false, lethal = 0,
            hurtAt = 10, attacker = attacker, profile = assert(PW.BotTactics).DefaultProfile } } --[[@as PW.BotBoard]]
    local fallback = { ClassName = "visibility_fixture_fallback", IsValid = function() return true end,
        Rank = function() return "combat" end, Weight = function() return 1 end,
        Update = function() return b.Continue() end } --[[@as PW.BotBehavior]]
    return { perception = perception, params = params, attacker = attacker, bot = bot, board = board,
        brain = b.NewState(), env = { bot = bot, board = board, behaviors = { retaliate(), fallback },
            random = function() return 0 end } }
end

---@param f PW.RetaliateVisibilityFixture
---@param now number
---@param seen boolean
local function sight(f, now, seen)
    assert(PW.BotPerception).Think(f.perception, { params = f.params,
        seen = seen and { [f.attacker] = { pos = Vector(200, 0, 36), vel = Vector() } } or {},
        random = function() return 0.5 end }, now)
    f.board.contacts, f.board.memory = f.perception.contacts, f.perception.memory
end

---@param f PW.RetaliateVisibilityFixture
---@param now number
---@param kind string
local function stimulus(f, now, kind)
    assert(assert(PW.BotPerception).AddStimulus(f.perception, kind,
        { ent = f.attacker, pos = Vector(190, 0, 36), time = now }))
end

---@param f PW.RetaliateVisibilityFixture
---@param now number
---@return string?
local function think(f, now)
    assert(PW.BotBrain).Think(f.brain, f.env, now)
    return f.board.behavior ~= nil and f.board.behavior.id or nil
end

return {
    groupName = "PW retaliation published visibility",
    cases = {
        {
            name = "Retaliation sight: newer hearing memory cannot hide the already recognized attacker",
            func = function()
                local f = fixture()
                sight(f, 10, true)
                sight(f, 10.5, true)
                stimulus(f, 10.51, "gunfire")
                expect(assert(f.board.contacts)[1].visible).to.beTrue()
                expect(assert(f.board.memory)[f.attacker].visible).to.beFalse() -- preserve memory semantics
                expect(think(f, 10.51)).to.equal("visibility_fixture_fallback")
            end
        },
        {
            name = "Retaliation sight: newer damage memory cannot hide the already recognized attacker",
            func = function()
                local f = fixture()
                sight(f, 10, true)
                sight(f, 10.5, true)
                stimulus(f, 10.51, "damage")
                expect(assert(f.board.contacts)[1].visible).to.beTrue()
                expect(assert(f.board.memory)[f.attacker].visible).to.beFalse()
                expect(think(f, 10.51)).to.equal("visibility_fixture_fallback")
            end
        },
        {
            name = "Retaliation fairness: raw sight before reaction never suppresses urgent unseen-attacker response",
            func = function()
                local f = fixture()
                sight(f, 10, true)
                stimulus(f, 10.1, "damage")
                expect(#assert(f.board.contacts)).to.equal(0)
                expect(think(f, 10.1)).to.equal("retaliate")
                expect(f.board.target).to.equal(f.attacker)
                expect(assert(f.board.intent).buttons).to.equal(0)
                expect(f.params.reaction_mean).to.equal(0.45)
            end
        },
        {
            name = "Retaliation Update: a running turn ends on published sight even while memory is a newer sound",
            func = function()
                local f = fixture()
                sight(f, 10, true)
                stimulus(f, 10.4, "damage")
                expect(think(f, 10.4)).to.equal("retaliate")
                sight(f, 10.5, true)
                stimulus(f, 10.51, "gunfire")
                -- The ctx references the same public board channels; it is not a synthetic aim/contact override.
                f.brain.ctx.contacts, f.brain.ctx.memory, f.brain.ctx.now =
                    assert(f.board.contacts), assert(f.board.memory), 10.51
                local transition = PW.Call(retaliate(), "Update", f.bot, f.brain.ctx) --[[@as PW.BotTransition]]
                expect(transition.kind).to.equal("done")
                expect(transition.reason).to.equal("attacker in sight")
                expect(think(f, 10.51)).to.equal("visibility_fixture_fallback")
            end
        },
        {
            name = "Retaliation safety: clearing sight and seeing another enemy do not hide the unseen attacker",
            func = function()
                local f = fixture()
                sight(f, 10, true)
                sight(f, 10.5, true)
                assert(PW.BotPerception).Clear(f.perception)
                f.board.contacts, f.board.memory = f.perception.contacts, f.perception.memory
                stimulus(f, 10.6, "damage")
                assert(f.board.contacts)[1] = { ent = {} --[[@as Entity]], pos = Vector(300, 0, 36),
                    vel = Vector(), visible = true, source = "sight", time = 10.6 }
                expect(think(f, 10.6)).to.equal("retaliate")
                expect(f.board.target).to.equal(f.attacker)
                expect(assert(f.board.intent).buttons).to.equal(0)
            end
        }
    }
}
