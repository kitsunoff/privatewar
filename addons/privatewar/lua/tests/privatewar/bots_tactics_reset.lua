-- The tactics owner clears only its facts/hurt/queued work. No real bots, contacts or damage are created.
local events = { "PW_PlayerTeamChanging", "PW_PlayerTeamChanged", "PW_RoundPreparing", "PW_RoundPrepared" }

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected tactics owner API")
    return value
end

---@return PW.BotTacticsLib
local function lib() return must(PW.BotTactics) end

---@return PW.BotCombatFacts
local function facts()
    return { at = CurTime(), pos = Vector(), health = 100, maxHealth = 100, clip = 30, capacity = 30,
        reserve = 90, reloading = false, lethal = 1, profile = lib().DefaultProfile,
        hurtAt = CurTime(), attacker = NULL,
        cover = { pos = Vector(10, 0, 0), standPeek = false, threatPos = Vector(200, 0, 0),
            at = -math.huge, score = 1 } }
end

---@return Player
local function bot()
    return { IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return true end, Alive = function() return true end,
        GetPos = function() return Vector() end } --[[@as Player]]
end

---@param ply Player
---@return PW.BotBoard
local function boardOf(ply)
    local contact = { ent = NULL, pos = Vector(500, 0, 0), vel = Vector(), time = CurTime(), visible = true,
        source = "sight" }
    return { bot = ply, team = 1, tactics = facts(), contacts = { contact }, memory = { [NULL] = contact },
        intent = { buttons = IN_ATTACK, weapon = "weapon_smg1" },
        goal = { point = Vector(100, 0, 0), radius = 32, priority = "hunt", status = "moving", since = 0 } }
end

---@return PW.Module
local function owner() return must(PW.Modules.Get("bots_tactics")) --[[@as PW.Module]] end

---@type table<string, any>[]
local cases = {}
local suite = {
    groupName = "PW tactics relationship reset",
    beforeEach = function(state)
        local s = PW._BotTactics
        state.hurt, state.pending, state.registered = s.hurt, s.pending, s.registered
        s.hurt, s.pending, s.registered = {}, {}, {}
    end,
    afterEach = function(state)
        local s = PW._BotTactics
        s.hurt, s.pending, s.registered = state.hurt, state.pending, state.registered
    end,
    cases = cases
}

for _, event in ipairs(events) do
    suite.cases[#suite.cases + 1] = {
        name = "Tactics owner: " .. event .. " clears all managed caches without touching another layer",
        func = function()
            local a, b, unmanaged = bot(), bot(), bot()
            local ba, bb, other = boardOf(a), boardOf(b), boardOf(unmanaged)
            local contacts, memory, intent, goal = ba.contacts, ba.memory, ba.intent, ba.goal
            stub(must(PW.Bot), "Get").with(function(ply)
                if ply == a then return ba elseif ply == b then return bb end
            end)
            stub(player, "GetBots").with(function() return { a, b, unmanaged } end)
            PW._BotTactics.hurt[a] = { at = 1, attacker = NULL }
            PW._BotTactics.hurt[b] = { at = 1, attacker = NULL }
            PW._BotTactics.pending[a], PW._BotTactics.pending[b] = true, true
            PW._BotTactics.registered[a] = "tactics:test"
            PW.Call(owner(), event, NULL, 1, 2, "role_change")
            expect(ba.tactics).to.beNil()
            expect(bb.tactics).to.beNil()
            expect(other.tactics).to.exist()
            expect(PW._BotTactics.hurt).to.deepEqual({})
            expect(PW._BotTactics.pending).to.deepEqual({})
            expect(PW._BotTactics.registered[a]).to.equal("tactics:test")
            expect(ba.contacts).to.equal(contacts)
            expect(ba.memory).to.equal(memory)
            expect(ba.intent).to.equal(intent)
            expect(ba.goal).to.equal(goal)
            expect(ba.team).to.equal(1)
            expect(isfunction(must(hook.GetTable()[event])[owner()])).to.beTrue()
            PW.Call(owner(), event, NULL, 1, 2, "role_change")
            expect(ba.tactics).to.beNil()
        end
    }
end

suite.cases[#suite.cases + 1] = {
    name = "Tactics queue: stale pre-reset jobs cannot trace, replace facts or clear a newer pending generation",
    func = function()
        for _, event in ipairs(events) do
            local ply = bot()
            local board = boardOf(ply)
            ---@type fun()[]
            local queued = {}
            local searches = 0
            stub(must(PW.Bot), "Get").with(function(who) if who == ply then return board end end)
            stub(player, "GetBots").with(function() return { ply } end)
            stub(must(PW.BotScheduler), "Enqueue").with(function(job) queued[#queued + 1] = job end)
            stub(navmesh, "Find").with(function() searches = searches + 1 return {} end)
            local found = facts().cover
            stub(lib(), "PickCover").with(function() return found end)
            must(lib()._QueueCover)(ply, board, must(board.tactics))
            expect(#queued).to.equal(1)
            PW.Call(owner(), event, NULL, 1, 2, "role_change")
            board.tactics = facts() -- ordinary fresh facts from a later life/tick
            must(lib()._QueueCover)(ply, board, board.tactics)
            expect(#queued).to.equal(2)
            local pending, fresh = PW._BotTactics.pending[ply], board.tactics
            queued[1]()
            expect(searches).to.equal(0)
            expect(PW._BotTactics.pending[ply]).to.equal(pending)
            expect(board.tactics).to.equal(fresh)
            expect(must(board.tactics).cover).to.equal(must(fresh).cover)
            queued[2]()
            expect(searches).to.equal(1)
            expect(must(board.tactics).cover).to.equal(found)
            expect(PW._BotTactics.pending[ply]).to.beNil()
        end
    end
}

suite.cases[#suite.cases + 1] = {
    name = "Tactics queue: a replaced board or facts cannot receive a stale cover even without another notification",
    func = function()
        for _, replaceBoard in ipairs({ false, true }) do
            local ply = bot()
            local board = boardOf(ply)
            local current = board
            ---@type fun()?
            local queued
            local searches = 0
            stub(must(PW.Bot), "Get").with(function() return current end)
            stub(must(PW.BotScheduler), "Enqueue").with(function(job) queued = job end)
            stub(navmesh, "Find").with(function() searches = searches + 1 return {} end)
            must(lib()._QueueCover)(ply, board, must(board.tactics))
            if replaceBoard then current = boardOf(ply) else board.tactics = facts() end
            local fresh = current.tactics
            must(queued)()
            expect(searches).to.equal(0)
            expect(current.tactics).to.equal(fresh)
            expect(PW._BotTactics.pending[ply]).to.beNil()
        end
    end
}

suite.cases[#suite.cases + 1] = {
    name = "Tactics queue: ordinary live work runs once, writes only cover and preserves pending suppression",
    func = function()
        local ply = bot()
        local board = boardOf(ply)
        local intent, goal, contacts = board.intent, board.goal, board.contacts
        ---@type fun()[]
        local queued = {}
        stub(must(PW.Bot), "Get").with(function() return board end)
        stub(must(PW.BotScheduler), "Enqueue").with(function(job) queued[#queued + 1] = job end)
        stub(navmesh, "Find").with(function() return {} end)
        local found = facts().cover
        stub(lib(), "PickCover").with(function() return found end)
        must(lib()._QueueCover)(ply, board, must(board.tactics))
        must(lib()._QueueCover)(ply, board, must(board.tactics))
        expect(#queued).to.equal(1)
        queued[1]()
        expect(must(board.tactics).cover).to.equal(found)
        expect(board.intent).to.equal(intent)
        expect(board.goal).to.equal(goal)
        expect(board.contacts).to.equal(contacts)
        expect(PW._BotTactics.pending[ply]).to.beNil()
    end
}

return suite
