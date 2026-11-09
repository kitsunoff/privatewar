-- Infection's mode filter must keep damage retaliation from suspending a legal infected pursuit.
-- Real registered Actions and brain selector, plain perceived snapshots; no engine bots or hidden coordinates.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "installed Infection rush dependency is missing")
    return value
end

---@return boolean
local function absent() return not file.Exists("privatewar/types/pw_infection.lua", "LUA") end

---@class PW.InfectionRushFixture
---@field bot Player
---@field survivor Entity
---@field attacker Entity
---@field contact PW.BotContact
---@field facts PW.BotCombatFacts
---@field board PW.BotBoard
---@field env PW.BotBrainEnv
---@field state PW.BotBrainState
---@field goal? Vector

---@return PW.BotBehavior
---@param id string
local function behavior(id)
    return must(must(PW.BotBehaviors).Get(id)) --[[@as PW.BotBehavior]]
end

---@return PW.InfectionRushFixture
local function fixture()
    local function hiddenPosition() error("rush must never read live enemy coordinates") end
    local survivor = { IsValid = function() return true end, GetPos = hiddenPosition } --[[@as Entity]]
    local attacker = { IsValid = function() return true end, GetPos = hiddenPosition } --[[@as Entity]]
    local bot = { IsValid = function() return true end, IsPlayer = function() return true end,
        GetPos = function() return Vector() end, GetWalkSpeed = function() return 230 end } --[[@as Player]]
    local contact = { ent = survivor, pos = Vector(80, 0, 0), vel = Vector(), visible = true,
        time = 10, source = "sight" } --[[@as PW.BotContact]]
    local damage = { ent = attacker, pos = Vector(-300, 0, 0), vel = Vector(), visible = false,
        time = 10, source = "damage" } --[[@as PW.BotContact]]
    local facts = { at = 10, pos = Vector(), health = 400, maxHealth = 400, clip = -1, capacity = 0,
        reserve = 0, reloading = false, lethal = 0, active = "weapon_fists", melee = "weapon_fists",
        runSpeed = 460, profile = must(PW.BotTactics).DefaultProfile } --[[@as PW.BotCombatFacts]]
    ---@type PW.BotBoard
    local board = { bot = bot, tactics = facts, intent = { buttons = 0 }, contacts = { contact, damage },
        memory = { [survivor] = contact, [attacker] = damage } }
    ---@type PW.InfectionRushFixture
    local f
    f = { bot = bot, survivor = survivor, attacker = attacker, contact = contact, facts = facts, board = board,
        state = must(PW.BotBrain).NewState(), env = { bot = bot, board = board, mode = "pw_infection",
        behaviors = { behavior("pw_infection_pursuit"), behavior("retaliate"), behavior("idle") },
        random = function() return 0.5 end,
        api = { setGoal = function(_, point) f.goal = point return true, "moving" end,
            clearGoal = function() f.goal = nil end } } }
    return f
end

---@param f PW.InfectionRushFixture
---@param now number
local function think(f, now) must(PW.BotBrain).Think(f.state, f.env, now) end

---@param f PW.InfectionRushFixture
---@return string?
local function running(f)
    return f.board.behavior ~= nil and f.board.behavior.id or nil
end

---@return PW.InfectionMode
local function mode()
    return must(PW.Modes.Get("pw_infection")) --[[@as PW.InfectionMode]]
end

---@return PW.InfectionLib
local function activate()
    local lib = must(PW.Infection)
    PW.ActiveMode = mode()
    lib.State = { mode = mode(), playing = true, completed = {}, actors = {}, identities = {}, lives = {},
        history = {}, userIds = {}, metadata = {}, deathBaselines = {}, infections = {},
        round = 1, credited = false, zombie = true }
    return lib
end

return {
    groupName = "PW Infection rush policy",
    beforeEach = function(state)
        state.mode = PW.ActiveMode
        state.infection = PW.Infection ~= nil and PW.Infection.State or nil
    end,
    afterEach = function(state)
        PW.ActiveMode = state.mode
        if PW.Infection ~= nil then PW.Infection.State = state.infection end
    end,
    cases = {
        {
            name = "Infected rush: mode prohibits retaliate cover reload fight and escape"
                .. " but permits pursuit search hunt",
            skip = absent,
            func = function()
                local lib, f = activate(), fixture()
                stub(lib, "Role").with(function() return "infected" end)
                for _, id in ipairs({ "retaliate", "take_cover", "reload_cover", "fight", "pw_infection_escape" }) do
                    expect(PW.Ask("PW_CanRunBotBehavior", f.bot, id)).to.beFalse()
                end
                for _, id in ipairs({ "pw_infection_pursuit", "search", "hunt", "idle" }) do
                    expect(PW.Ask("PW_CanRunBotBehavior", f.bot, id)).to.beTrue()
                end
            end
        },
        {
            name = "Infected rush: unseen attacker damage cannot suspend pursuit of a different visible survivor",
            skip = absent,
            func = function()
                local lib, f = activate(), fixture()
                stub(lib, "Role").with(function() return "infected" end)
                think(f, 10)
                expect(running(f)).to.equal("pw_infection_pursuit")
                f.facts.attacker, f.facts.hurtAt = f.attacker, 10.1
                for _, now in ipairs({ 10.2, 10.5, 11 }) do
                    think(f, now)
                    expect(running(f)).to.equal("pw_infection_pursuit")
                    expect(#f.state.stack).to.equal(1)
                    expect(f.board.target).to.equal(f.survivor)
                    expect(must(f.board.intent).drive).to.equal(Vector(230, 0, 0))
                    expect(must(f.board.intent).weapon).to.equal("weapon_fists")
                    expect(f.state.evals.retaliate).to.beNil()
                end
            end
        },
        {
            name = "Infected rush: low health recent unseen damage still pursues the perceived survivor at range",
            skip = absent,
            func = function()
                local lib, f = activate(), fixture()
                stub(lib, "Role").with(function() return "infected" end)
                f.facts.health, f.facts.attacker, f.facts.hurtAt = 1, f.attacker, 10
                f.contact.pos = Vector(600, 0, 0)
                think(f, 10)
                expect(running(f)).to.equal("pw_infection_pursuit")
                expect(f.goal).to.equal(f.contact.pos)
                expect(f.board.target).to.beNil()
                expect(must(f.board.intent).sprint).to.beTrue()
                expect(must(f.board.intent).weapon).to.equal("weapon_fists")
            end
        },
        {
            name = "Infected rush: unseen damage contact grants neither pursuit nor an omniscient target",
            skip = absent,
            func = function()
                local lib, f = activate(), fixture()
                stub(lib, "Role").with(function() return "infected" end)
                f.contact.visible = false
                f.facts.attacker, f.facts.hurtAt = f.attacker, 10
                think(f, 10)
                expect(running(f)).to.equal("idle")
                expect(f.board.target).to.beNil()
                expect(must(f.board.intent).target).to.beNil()
                expect(f.goal).to.beNil()
                expect(must(f.board.intent).drive).to.beNil()
                expect(must(f.board.intent).weapon).to.beNil()
            end
        },
        {
            name = "Infected rush: survivor escape and existing retaliation prohibition remain unchanged",
            skip = absent,
            func = function()
                local lib, f = activate(), fixture()
                stub(lib, "Role").with(function() return "survivor" end)
                for _, id in ipairs({ "retaliate", "take_cover", "reload_cover", "fight", "melee",
                    "pw_infection_pursuit" }) do
                    expect(PW.Ask("PW_CanRunBotBehavior", f.bot, id)).to.beFalse()
                end
                for _, id in ipairs({ "pw_infection_escape", "search", "hunt" }) do
                    expect(PW.Ask("PW_CanRunBotBehavior", f.bot, id)).to.beNil()
                end
                f.facts.attacker, f.facts.hurtAt = f.attacker, 10
                think(f, 10)
                expect(running(f)).to.equal("idle")
                expect(f.board.target).to.beNil()
            end
        },
        {
            name = "Infected rush: ordinary modes retain shared survival retaliation for unseen attacker damage",
            skip = absent,
            func = function()
                for _, id in ipairs({ "tdm", "ffa", "dom", "kc", "snd", "hardpoint" }) do
                    local f = fixture()
                    PW.ActiveMode = setmetatable({ IsValid = function() return true end,
                        _SND = { phase = "carried" }, _Rounds = { phase = "round" } },
                        { __index = must(PW.Modes.Get(id)) }) --[[@as PW.Mode]]
                    f.env.mode = id
                    f.facts.attacker, f.facts.hurtAt = f.attacker, 10
                    expect(PW.Ask("PW_CanRunBotBehavior", f.bot, "retaliate") == false).to.beFalse()
                    think(f, 10)
                    expect(running(f)).to.equal("retaliate")
                    expect(f.board.target).to.equal(f.attacker)
                    expect(must(f.state.evals.retaliate).rank).to.equal(must(PW.BotBrain).Buckets.survival)
                end
            end
        }
    }
}
