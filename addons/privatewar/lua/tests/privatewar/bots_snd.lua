-- Frozen generic objective contracts: tests precede implementation.
-- No real bots or mode implementation; never reads another module's private state.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotCommanderLib
local function lib()
    return must(PW.BotCommander)
end

---@param action string
---@return PW.BotObjective
local function objective(action)
    return { id = "site_A", pos = Vector(0, 0, 0), radius = 64, action = action, weight = 1, want = 1,
        eligible = { [2] = true }, revision = 1 }
end

---@param obj PW.BotObjective
---@return PW.BotOrder
local function order(obj)
    return { id = obj.id, objective = obj, type = obj.action, priority = obj.weight, since = 0 }
end

return {
    groupName = "PW SND bot objective contracts",
    cases = {
        {
            name = "SND bots: carrier eligibility beats distance and survives every assignment pass",
            func = function()
                local obj = objective("plant")
                local bots = { { id = 1, pos = Vector(0, 0, 0) }, { id = 2, pos = Vector(500, 0, 0) } }
                local assigned = lib().Assign(bots, { obj }, {}, 1)
                expect(assigned[1]).to.beNil()
                expect(must(assigned[2]).type).to.equal("plant")
                local retained = lib().Assign(bots, { obj }, { [1] = order(obj) }, 2)
                expect(retained[1]).to.beNil()
                expect(must(retained[2]).type).to.equal("plant")
            end
        },
        {
            name = "SND bots: lost eligibility releases even an active sticky hold",
            func = function()
                local old = objective("hold")
                old.eligible = { [1] = true }
                local current = objective("hold")
                current.eligible = {}
                local assigned = lib().Assign({ { id = 1, pos = old.pos } }, { current }, { [1] = order(old) }, 1)
                expect(assigned[1]).to.beNil()
            end
        },
        {
            name = "SND bots: a changed visit revision releases a hold without changing legacy anti-dither",
            func = function()
                local old = objective("hold")
                old.eligible = nil
                local current = objective("hold")
                current.eligible, current.revision, current.want = nil, 2, 0
                local bots = { { id = 1, pos = old.pos } }
                expect(lib().Assign(bots, { current }, { [1] = order(old) }, 1)[1]).to.beNil()
                current.revision = 1
                expect(must(lib().Assign(bots, { current }, { [1] = order(old) }, 1)[1]).id).to.equal(old.id)
            end
        },
        {
            name = "SND bots: sanitizer preserves approved eligibility without leaking hidden enemies",
            func = function()
                local raw = objective("plant") --[[@as table<string, any>]]
                raw.enemy, raw.hiddenPos, raw.callback = "secret", Vector(999, 999, 999), function() end
                raw.eligible = { [2] = true, [3] = false, [-1] = true, nope = true }
                local sanitized = lib().Sanitize({ raw })
                expect(#sanitized).to.equal(1)
                local obj = must(sanitized[1])
                expect(obj).to.deepEqual(objective("plant"))
                expect(obj.eligible == raw.eligible).to.beFalse()
                local eligible = raw.eligible --[[@as table<integer, boolean>]]
                eligible[2] = nil
                expect(lib().Eligible(obj, 2)).to.beTrue()
                expect(lib().Eligible(obj, 1)).to.beFalse()
            end
        },
        {
            name = "SND bots: authoritative zone survives sanitization and malformed cylinders fail closed",
            func = function()
                local raw = objective("hold")
                raw.zone = { pos = Vector(0, 0, 0), radius = 80, above = 72, below = 16 }
                local clean = must(lib().Sanitize({ raw })[1])
                expect(clean.zone).to.deepEqual(raw.zone)
                expect(clean.zone == raw.zone).to.beFalse()
                must(raw.zone).radius = -1
                expect(lib().Sanitize({ raw })).to.deepEqual({})
            end
        },
        {
            name = "SND bots: local fallback filters an ineligible best choice without hiding the eligible second",
            func = function()
                local best, other = objective("plant"), objective("plant")
                best.weight, other.weight, other.id = 1, 0.5, "site_B"
                other.eligible = { [1] = true }
                local chosen = must(must(PW.BotObjectives).PickObjective({ best, other }, Vector(0, 0, 0), {}, nil, 1))
                expect(chosen.id).to.equal("site_B")
                expect(must(PW.BotObjectives).PickObjective({ best }, Vector(0, 0, 0), {})).to.beNil()
            end
        },
        {
            name = "SND bots: duplicate objective ids are rejected instead of aliasing assignment slots",
            func = function()
                expect(lib().Sanitize({ objective("plant"), objective("plant") })).to.deepEqual({})
            end
        },
        {
            name = "Objective arrival: projected disc and actual height stay inside the authoritative cylinder",
            func = function()
                local obj = objective("hold")
                obj.zone = { pos = Vector(0, 0, 0), radius = 100, above = 80, below = 8 }
                expect(lib().ArrivalFits(obj, Vector(0, 0, 0), 24)).to.beTrue()
                expect(lib().ArrivalFits(obj, Vector(90, 0, 0), 24)).to.beFalse()
                expect(lib().ArrivalFits(obj, Vector(0, 0, 81), 24)).to.beFalse()
                expect(lib().Inside(obj, Vector(0, 0, -9))).to.beFalse()
                expect(lib().Inside(obj, Vector(101, 0, 0))).to.beFalse()
                expect(lib().Inside(obj, Vector(100, 0, 0))).to.beTrue()
            end
        },
        {
            name = "Objective follower: real SetGoal rejects outside projected discs and records visit identity",
            func = function()
                local api, goals = must(PW.Bot), must(PW.BotGoal)
                local actor = must(player.GetHumans()[1])
                local origin = actor:GetPos()
                local obj = objective("hold")
                obj.pos, obj.radius = origin + Vector(300, 0, 0), 24
                obj.eligible = { [actor:UserID()] = true }
                obj.zone = { pos = obj.pos, radius = 100, above = 80, below = 8 }
                ---@type PW.BotBoard
                local board = { bot = actor, intent = { buttons = 0 }, team = 1 }
                stub(goals, "BoardOf").with(function(ply) return ply == actor and board or nil end)
                local projected = obj.pos + Vector(1000, 0, 0)
                stub(goals, "Project").with(function() return projected end)
                stub(must(PW.BotNav), "RequestPath").with(function()
                    return { status = "queued", partial = false, cached = false, iterations = 0,
                        slices = 0, done = false, from = 1, to = 2 }
                end)
                stub(must(PW.BotNav), "Cancel").with(function() end)
                ---@type PW.BotBrainCtx
                local ctx = { bot = actor, board = board, now = 10, state = {}, contacts = {}, memory = {}, _api = {},
                    order = order(obj), factsAt = 10, facts = { pos = origin, objectives = { obj }, mates = {},
                        deaths = {}, candidates = {}, stationary = false, teamwork = 1 },
                    Intent = function() return must(board.intent) end,
                    SetGoal = function(_, point, radius, priority)
                        return api.SetGoal(actor, point, radius, priority)
                    end,
                    ClearGoal = function() api.ClearGoal(actor) end,
                    GoalStatus = function() return board.goal ~= nil and board.goal.status or nil end,
                    SetTarget = function() end, Contact = function() end, SearchPlan = function() end }
                local behavior = must(PW.BotBehaviors.Get("objective")) --[[@as PW.BotBehavior]]
                local ok, err = pcall(function()
                    for _, offset in ipairs({ Vector(1000, 0, 0), Vector(0, 0, 500) }) do
                        projected = obj.pos + offset
                        api.ClearGoal(actor)
                        ctx.state = {}
                        behavior:Update(actor, ctx)
                        local goal = board.goal
                        if goal ~= nil then
                            local delta = must(goal.projected) - obj.pos
                            expect(delta.x * delta.x + delta.y * delta.y <= (100 - goal.radius) ^ 2).to.beTrue()
                            expect(delta.z >= -8 and delta.z <= 80).to.beTrue()
                        end
                        expect(must(ctx.state).id).to.equal(obj.id)
                        expect(must(ctx.state).revision).to.equal(obj.revision)
                    end
                end)
                api.ClearGoal(actor)
                assert(ok, tostring(err))
            end
        },
        {
            name = "SND bots: malformed present restrictions never become unrestricted",
            func = function()
                for _, invalid in ipairs({ false, "all", 1 }) do
                    local raw = objective("plant") --[[@as table<string, any>]]
                    raw.eligible = invalid
                    expect(lib().Sanitize({ raw })).to.deepEqual({})
                end
                local raw = objective("defuse") --[[@as table<string, any>]]
                raw.eligible = nil
                expect(lib().Sanitize({ raw })).to.deepEqual({})
                raw.eligible, raw.revision = {}, -1
                expect(lib().Sanitize({ raw })).to.deepEqual({})
                raw.revision, raw.radius = 1, 0
                expect(lib().Sanitize({ raw })).to.deepEqual({})
                raw.radius = nil
                expect(lib().Sanitize({ raw })).to.deepEqual({})
                local legacy = objective("capture")
                legacy.eligible, legacy.revision = nil, nil
                expect(lib().Eligible(legacy, 1)).to.beTrue()
                legacy.eligible = {}
                expect(lib().Eligible(legacy, 1)).to.beFalse()
            end
        }
    }
}
