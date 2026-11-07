-- Generic invalidation is mandatory even when the optional Infection addon is absent.
-- Fakes populate owned stores only in tests, never in addon production code. No bots are created.
local listener = "PW_Test_RoleInvalidation"

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@param id integer
---@return Player
local function bot(id)
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return true end, UserID = function() return id end,
        Alive = function() return true end, Team = function() return 1 end,
        EyeAngles = function() return Angle() end, GetActiveWeapon = function() return NULL end
    } --[[@as Player]]
end

---@param state table<string, any>
---@param id integer
---@return Player, PW.BotBoard
local function seedBot(state, id)
    local ply = bot(id)
    local brain = must(PW.BotBrain)
    local board = { bot = ply, team = 1, contacts = {}, memory = {},
        target = state.human, intent = { buttons = IN_ATTACK, target = state.human, weapon = "weapon_smg1",
            sprint = true, drive = Vector(100, 0, 0), slideAt = 1 } } --[[@as PW.BotBoard]]
    PW._BotsManager.boards[ply] = board
    local bs = brain.NewState()
    PW._BotBrain.states[ply] = bs
    local behavior = { ClassName = "test_stale_action", IsValid = function() return true end,
        Rank = function() return 30 end, Weight = function() return 1 end,
        Update = function() return brain.Continue() end,
        OnEnd = function(_, _, ctx)
            state.ended = state.ended + 1
            local teams = state.endedTeams --[[@as integer[] ]]
            teams[#teams + 1] = state.human:Team()
            ctx:SetTarget(state.human)
            ctx:Intent().weapon = "weapon_smg1"
        end } --[[@as PW.BotBehavior]]
    brain.Think(bs, { bot = ply, board = board, behaviors = { behavior }, random = function() return 0 end }, 1)
    bs.cooldowns.stale = 100
    local perception = must(PW.BotPerception)
    local ps = perception.NewState()
    perception.States[ply] = ps
    board.contacts, board.memory = ps.contacts, ps.memory
    must(PW.Bot).AddStimulus(ply, "radar", { ent = state.human, pos = Vector(10, 0, 0), time = 1 })
    ps.contacts[1] = must(ps.memory[state.human])
    must(must(PW.BotInput).SetScripted)(ply, { buttons = IN_ATTACK, weapon = "weapon_smg1" })
    return ply, board
end

return {
    groupName = "PW generic role invalidation",
    beforeEach = function(state)
        state.boards, state.brains = PW._BotsManager.boards, PW._BotBrain.states
        state.perception = must(PW.BotPerception).States
        state.mode, state.ended, state.endedTeams = PW.ActiveMode, 0, {} --[[@as integer[] ]]
        PW._BotsManager.boards, PW._BotBrain.states, must(PW.BotPerception).States = {}, {}, {}
        state.team = 2
        state.human = { IsValid = function() return true end, IsPlayer = function() return true end,
            Team = function() return state.team end, IsBot = function() return false end } --[[@as Player]]
        PW.ActiveMode = { ClassName = "test_relationships", Teams = 2 }
        state.bots = {} --[[@as Player[] ]]
    end,
    afterEach = function(state)
        hook.Remove("PW_CanRunBotBehavior", listener)
        for _, ply in ipairs(state.bots --[[@as Player[] ]]) do must(must(PW.BotInput).SetScripted)(ply, nil) end
        PW._BotsManager.boards, PW._BotBrain.states = state.boards, state.brains
        must(PW.BotPerception).States, PW.ActiveMode = state.perception, state.mode
    end,
    cases = {
        {
            name = "Role transition: all brains stop before a HUMAN changes team; owners clear synchronously",
            func = function(state)
                local a, ba = seedBot(state, 9001)
                local b, bb = seedBot(state, 9002)
                state.bots = { a, b }
                expect(#must(ba.contacts) > 0).to.beTrue()
                PW.Notify("PW_PlayerTeamChanging", state.human, 2, 1, "role_change")
                expect(state.ended).to.equal(2)
                expect(state.endedTeams).to.deepEqual({ 2, 2 })
                state.team = 1
                PW.Notify("PW_PlayerTeamChanged", state.human, 2, 1, "role_change")
                for _, ply in ipairs(state.bots) do
                    local board = must(must(PW.Bot).Get(ply))
                    expect(board.target).to.beNil()
                    expect(board.behavior).to.beNil()
                    expect(board.contacts).to.deepEqual({})
                    expect(board.memory).to.deepEqual({})
                    expect(board.goal).to.beNil()
                    expect(board.path).to.beNil()
                    expect(#PW._BotBrain.states[ply].stack).to.equal(0)
                    expect(PW._BotBrain.states[ply].evals).to.deepEqual({})
                    expect(PW._BotBrain.states[ply].cooldowns).to.deepEqual({})
                    local intent = must(must(PW.BotInput).IntentFor)(ply)
                    local cleared = intent == nil
                        or (intent.buttons == 0 and intent.weapon == nil and intent.target == nil)
                    expect(cleared).to.beTrue()
                end
                expect(bb.team).to.equal(1)
                PW.Notify("PW_PlayerTeamChanged", state.human, 2, 1, "role_change")
                expect(state.ended).to.equal(2)
            end
        },
        {
            name = "Round preparation: unchanged teams stop before child and clear after child without new contacts",
            func = function(state)
                local ply, board = seedBot(state, 9003)
                state.bots = { ply }
                PW.Notify("PW_RoundPreparing", 2, false)
                expect(state.ended).to.equal(1)
                PW.Notify("PW_RoundPrepared", 2, false)
                expect(board.team).to.equal(1)
                expect(board.target).to.beNil()
                expect(board.memory).to.deepEqual({})
                expect(board.contacts).to.deepEqual({})
                expect(#PW._BotBrain.states[ply].stack).to.equal(0)
            end
        },
        {
            name = "Behavior admission: false rejects candidates and cached minimum-run frames",
            func = function()
                local brain = must(PW.BotBrain)
                local bs, board = brain.NewState(), { bot = bot(9004) }
                local denied, ended = false, 0
                local behavior = { ClassName = "test_fight", IsValid = function() return true end,
                    Interval = 100, MinRun = 100,
                    Rank = function() return 30 end, Weight = function() return 1 end,
                    Update = function() return brain.Continue() end, OnEnd = function() ended = ended + 1 end }
                local env = { bot = board.bot, board = board, behaviors = { behavior },
                    random = function() return 0 end }
                hook.Add("PW_CanRunBotBehavior", listener, function() if denied then return false end end)
                brain.Think(bs, env, 0)
                expect(brain.StackIds(bs)).to.deepEqual({ "test_fight" })
                denied = true
                brain.Think(bs, env, 0.1)
                expect(brain.StackIds(bs)).to.deepEqual({})
                expect(ended).to.equal(1)
                expect(bs.evals.test_fight).to.beNil()
                brain.Think(bs, env, 0.2)
                expect(brain.StackIds(bs)).to.deepEqual({})
            end
        },
        {
            name = "Behavior admission: ChangeTo and SuspendFor cannot enter a role-forbidden behavior",
            func = function()
                local brain = must(PW.BotBrain)
                for _, make in ipairs({ brain.ChangeTo, brain.SuspendFor }) do
                    local starts = 0
                    local a = { ClassName = "allowed", IsValid = function() return true end,
                        Rank = function() return 30 end, Weight = function() return 1 end,
                        Update = function() return make("forbidden") end }
                    local b = { ClassName = "forbidden", IsValid = function() return true end,
                        Rank = function() return 0 end, Weight = function() return 0 end,
                        OnStart = function() starts = starts + 1 end, Update = function() return brain.Continue() end }
                    hook.Add("PW_CanRunBotBehavior", listener, function(_, id)
                        if id == "forbidden" then return false end
                    end)
                    local bs, ply = brain.NewState(), bot(9005)
                    local env = { bot = ply, board = { bot = ply }, behaviors = { a, b },
                        random = function() return 0 end }
                    brain.Think(bs, env, 1)
                    expect(starts).to.equal(0)
                    expect(brain.StackIds(bs)).to.deepEqual({ "allowed" })
                end
            end
        }
    }
}
