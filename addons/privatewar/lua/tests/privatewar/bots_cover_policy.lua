-- Optional cover-search policy, independent of behavior eligibility and of the optional addon.
local listener = "PW.TestCoverPolicy"

---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil, "missing cover policy dependency") return value end

---@return Player, PW.BotBoard
local function fixture()
    local bot = { IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return true end, Alive = function() return true end,
        GetPos = function() return Vector() end, GetVelocity = function() return Vector(12, 0, 0) end,
        Health = function() return 37 end, GetMaxHealth = function() return 400 end,
        GetRunSpeed = function() return 460 end, OnGround = function() return true end,
        Crouching = function() return false end, GetActiveWeapon = function() return NULL end,
        GetWeapons = function() return {} end } --[[@as Player]]
    return bot, { bot = bot, contacts = { { ent = NULL, pos = Vector(500, 0, 0), vel = Vector(),
        time = CurTime(), visible = true, source = "sight" } }, intent = { buttons = IN_ATTACK },
        goal = { point = Vector(100, 0, 0), radius = 32, priority = "hunt", status = "moving", since = 0 },
        path = { points = { Vector() }, index = 1, partial = false } }
end

---@param bot Player
---@param board PW.BotBoard
local function queue(bot, board)
    must(PW.BotTactics).Refresh(bot, board)
    must(must(PW.BotTactics)._QueueCover)(bot, board, must(board.tactics))
end

return {
    groupName = "PW cover search policy",
    beforeEach = function(state)
        state.mode, state.pending = PW.ActiveMode, PW._BotTactics.pending
        PW.ActiveMode, PW._BotTactics.pending = nil, {}
    end,
    afterEach = function(state)
        hook.Remove("PW_CanSearchBotCover", listener)
        PW.ActiveMode, PW._BotTactics.pending = state.mode, state.pending
    end,
    cases = {
        {
            name = "Cover opt-out: explicit false enqueues and traces nothing while refreshing every non-cover fact",
            func = function()
                local bot, board = fixture()
                local intent, goal, path, contacts = board.intent, board.goal, board.path, board.contacts
                local enqueues, finds, traces = 0, 0, 0
                hook.Add("PW_CanSearchBotCover", listener, function(who)
                    expect(who).to.equal(bot)
                    return false
                end)
                stub(must(PW.BotScheduler), "Enqueue").with(function() enqueues = enqueues + 1 end)
                stub(navmesh, "Find").with(function() finds = finds + 1 return {} end)
                stub(util, "TraceLine").with(function() traces = traces + 1 return { Fraction = 1 } end)
                for _ = 1, 3 do queue(bot, board) end
                expect({ enqueues, finds, traces }).to.deepEqual({ 0, 0, 0 })
                expect(PW._BotTactics.pending[bot]).to.beNil()
                local f = must(board.tactics)
                expect({ f.health, f.maxHealth, f.speed, f.runSpeed, f.clip, f.capacity, f.reserve,
                    f.reloading, f.onGround, f.crouching }).to.deepEqual({ 37, 400, 12, 460, -1, 0, 0,
                    false, true, false })
                expect(f.profile).to.exist()
                expect(f.at).to.equal(CurTime())
                expect(f.pos).to.equal(Vector())
                expect(board.intent).to.equal(intent)
                expect(board.goal).to.equal(goal)
                expect(board.path).to.equal(path)
                expect(board.contacts).to.equal(contacts)
            end
        },
        {
            name = "Cover legacy: absent nil and true providers retain pending suppression and one live search",
            func = function()
                for _, answer in ipairs({ "absent", "nil", "true" }) do
                    local bot, board = fixture()
                    ---@type fun()[]
                    local jobs = {}
                    local searches = 0
                    if answer ~= "absent" then
                        hook.Add("PW_CanSearchBotCover", listener, function()
                            if answer == "true" then return true end
                        end)
                    end
                    local get = stub(must(PW.Bot), "Get").with(function() return board end)
                    local enqueue = stub(must(PW.BotScheduler), "Enqueue").with(function(job) jobs[#jobs + 1] = job end)
                    local find = stub(navmesh, "Find").with(function() searches = searches + 1 return {} end)
                    queue(bot, board)
                    queue(bot, board)
                    expect(#jobs).to.equal(1)
                    jobs[1]()
                    expect(searches).to.equal(1)
                    expect(PW._BotTactics.pending[bot]).to.beNil()
                    hook.Remove("PW_CanSearchBotCover", listener)
                    find:Restore()
                    enqueue:Restore()
                    get:Restore()
                end
            end
        },
        {
            name = "Cover execution: a newly denied queued request does no search or cover write",
            func = function()
                local bot, board = fixture()
                local denied, searches = false, 0
                ---@type fun()[]
                local jobs = {}
                hook.Add("PW_CanSearchBotCover", listener, function() if denied then return false end end)
                stub(must(PW.Bot), "Get").with(function() return board end)
                stub(must(PW.BotScheduler), "Enqueue").with(function(job) jobs[#jobs + 1] = job end)
                stub(navmesh, "Find").with(function() searches = searches + 1 return {} end)
                queue(bot, board)
                local cover = { pos = Vector(), threatPos = Vector(), at = -math.huge, score = 1, standPeek = false }
                must(board.tactics).cover = cover
                denied = true
                jobs[1]()
                expect(searches).to.equal(0)
                expect(must(board.tactics).cover).to.equal(cover)
                expect(PW._BotTactics.pending[bot]).to.beNil()
            end
        },
        {
            name = "Cover lifecycle: denied conversion and reset cannot let stale work clear a newer pending token",
            func = function()
                local bot, board = fixture()
                local denied, searches = false, 0
                ---@type fun()[]
                local jobs = {}
                hook.Add("PW_CanSearchBotCover", listener, function() if denied then return false end end)
                stub(must(PW.Bot), "Get").with(function() return board end)
                stub(player, "GetBots").with(function() return { bot } end)
                stub(must(PW.BotScheduler), "Enqueue").with(function(job) jobs[#jobs + 1] = job end)
                stub(navmesh, "Find").with(function() searches = searches + 1 return {} end)
                queue(bot, board)
                denied = true
                PW.Call(must(PW.Modules.Get("bots_tactics")), "PW_PlayerTeamChanged", bot, 1, 2, "role_change")
                queue(bot, board)
                expect(#jobs).to.equal(1)
                denied = false
                queue(bot, board)
                local pending = PW._BotTactics.pending[bot]
                expect(#jobs).to.equal(2)
                jobs[1]()
                expect(searches).to.equal(0)
                expect(PW._BotTactics.pending[bot]).to.equal(pending)
                jobs[2]()
                expect(searches).to.equal(1)
                expect(PW._BotTactics.pending[bot]).to.beNil()
            end
        },
        {
            name = "Cover failure isolation: failing search releases its own pending token"
                .. " and FIFO A-star-style slices progress",
            func = function()
                local bot, board = fixture()
                local now, slices = 0, 0
                local sched = must(PW.BotScheduler).New({ clock = function() return now end,
                    budget = 2, onError = function() end })
                stub(must(PW.Bot), "Get").with(function() return board end)
                stub(must(PW.BotScheduler), "Enqueue").with(sched.Enqueue)
                stub(navmesh, "Find").with(function() error("isolated cover failure") end)
                queue(bot, board)
                sched.Enqueue(function()
                    slices = slices + 1
                    sched.Enqueue(function() slices = slices + 1 end)
                end)
                now = 1
                sched.Tick()
                expect(PW._BotTactics.pending[bot]).to.beNil()
                expect(sched.GetCounters().errors).to.equal(1)
                expect(slices).to.equal(0)
                sched.Tick()
                expect(slices).to.equal(1)
                sched.Tick()
                expect(slices).to.equal(2)
                expect(sched.GetCounters().jobsRun).to.equal(3)
            end
        }
    }
}
