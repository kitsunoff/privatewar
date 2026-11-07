-- T-5.7 bot perception (07-bots.md d.7; docs/api/bots-blackboard.md "Stimuli"). Pure cases over plain data with a fake
-- clock (every function takes `now`); enemies and bots are plain tables, no real bots are needed.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotPerceptionLib
local function lib()
    return must(PW.BotPerception)
end

---@return PW.BotLib
local function botApi()
    return must(PW.Bot)
end

---@return PW.BotPerceptionParams
local function params()
    return lib().ParamsFor(nil, "regular") -- reaction 0.45 s
end

local forward = Vector(1, 0, 0)
local eye = Vector(0, 0, 64)
local tick = 0.1

---@param ent any
---@param pos Vector
---@return PW.BotSnapshotSet
local function seenAt(ent, pos)
    return { [ent] = { pos = pos, vel = Vector(0, 0, 0) } }
end

---Runs a perception step per tick from t = 0, with `seen` returning what is visible at tick time t.
---@param state PW.BotPerceptionState
---@param untilTime number
---@param seen fun(t: number): PW.BotSnapshotSet?
---@return table<integer, boolean> visibleAt contact visible per tick index
local function run(state, untilTime, seen)
    ---@type table<integer, boolean>
    local visibleAt = {}
    local steps = math.floor(untilTime / tick + 0.5)
    for i = 0, steps do
        local t = i * tick
        lib().Think(state, { params = params(), seen = seen(t) }, t)
        local first = state.contacts[1]
        visibleAt[i] = first ~= nil and first.visible
    end
    return visibleAt
end

---@param name string
---@return PW.BotPerceptionState
local function registered(name)
    local state = lib().NewState()
    lib().States[name] = state
    return state
end

return {
    groupName = "PW bots perception",
    cases = {
        {
            name = "FOV: a target outside the cone is not seen and costs no trace",
            func = function()
                local traces = 0
                ---@type PW.BotSightCtx
                local ctx = {
                    eye = eye, forward = forward, fov = 110, range = 4500, budget = { left = 6 },
                    los = function() traces = traces + 1 return true end
                }
                local behind = Vector(-500, 0, 64)
                local side = Vector(0, 800, 64)
                local ahead = Vector(800, 100, 64)
                local function cand(pos)
                    return { ent = "e", center = pos, points = { pos, pos - Vector(0, 0, 20) }, vel = Vector(0, 0, 0) }
                end
                expect(lib().Visible(ctx, cand(behind))).to.beFalse()
                expect(lib().Visible(ctx, cand(side))).to.beFalse()
                expect(traces).to.equal(0)
                expect(lib().Visible(ctx, cand(ahead))).to.beTrue()
                expect(traces).to.equal(1)
            end
        },
        {
            name = "FOV: beyond the sight range is not seen, a blocked line of sight is not seen, traces are budgeted",
            func = function()
                local blocked = false
                ---@type PW.BotSightCtx
                local ctx = {
                    eye = eye, forward = forward, fov = 110, range = 1000, budget = { left = 2 },
                    los = function() return not blocked end
                }
                local pos = Vector(2000, 0, 64)
                local c = { ent = "e", center = pos, points = { pos, pos, pos }, vel = Vector(0, 0, 0) }
                expect(lib().Visible(ctx, c)).to.beFalse()
                local near = Vector(500, 0, 64)
                c = { ent = "e", center = near, points = { near, near, near }, vel = Vector(0, 0, 0) }
                blocked = true
                expect(lib().Visible(ctx, c)).to.beFalse()
                expect(ctx.budget.left).to.equal(0) -- two points traced, the third had no budget
                blocked = false
                expect(lib().Visible(ctx, c)).to.beFalse()
            end
        },
        {
            name = "Reaction: the queue delays recognition by the configured time",
            func = function()
                local state = lib().NewState()
                local ent = "enemy"
                local visibleAt = run(state, 1, function(t)
                    if t >= 0.2 then return seenAt(ent, Vector(500, 0, 0)) end
                    return nil
                end)
                -- first visible at t = 0.2, reaction 0.45 s: recognised at t = 0.65 (tick 7), not before
                expect(visibleAt[6]).to.beFalse()
                expect(visibleAt[7]).to.beTrue()
                expect(state.contacts[1].source).to.equal("sight")
            end
        },
        {
            name = "Reaction: the queue returns the snapshot of N seconds ago, to the tick",
            func = function()
                local queue = lib().NewQueue()
                lib().QueuePush(queue, 0, seenAt("e", Vector(1, 0, 0)))
                expect(lib().QueueRecognised(queue, 0.449, 0.45)["e"]).to.beNil()
                expect(lib().QueueRecognised(queue, 0.45, 0.45)["e"]).to.exist()
                expect(lib().QueueRecognised(queue, 0.2, 0)["e"]).to.exist()
            end
        },
        {
            name = "Reaction: a faster difficulty reacts sooner, the floor is a minimum, jitter stays above it",
            func = function()
                local recruit = lib().ParamsFor(nil, "recruit")
                local veteran = lib().ParamsFor(nil, "veteran")
                expect(recruit.reaction_mean).to.equal(0.6)
                expect(veteran.reaction_mean).to.equal(0.22)
                expect(lib().ReactionDelay(veteran)).to.equal(0.22)
                local fast = { reaction_mean = 0.1, reaction_floor = 0.15, reaction_jitter = 0.3, share_delay = 0,
                    share_radius = 0, fov = 110 }
                expect(lib().ReactionDelay(fast)).to.equal(0.15)
                expect(lib().ReactionDelay(recruit, function() return 0 end) < 0.6).to.beTrue()
                expect(lib().ReactionDelay(recruit, function() return 0.999 end) > 0.6).to.beTrue()
                local table_ = lib().ParamsFor({ reaction_mean = 0.3 }, "veteran")
                expect(table_.reaction_mean).to.equal(0.3)
                expect(table_.share_delay).to.equal(0.5)
            end
        },
        {
            name = "Memory: a contact decays after 12 s",
            func = function()
                local memory = {}
                lib().Remember(memory, "e", { pos = Vector(1, 2, 3), time = 100, source = "sound" })
                expect(lib().Decay(memory, 111.9)).to.equal(0)
                expect(memory["e"]).to.exist()
                expect(lib().Decay(memory, 112.1)).to.equal(1)
                expect(memory["e"]).to.beNil()
            end
        },
        {
            name = "Memory: a sighting is forgotten 12 s after the last sight, and is in the contacts until then",
            func = function()
                local state = lib().NewState()
                local ent = "enemy"
                run(state, 1, function() return seenAt(ent, Vector(500, 0, 0)) end)
                expect(state.memory[ent]).to.exist()
                lib().Think(state, { params = params() }, 11) -- out of sight since 1.0
                expect(state.memory[ent]).to.exist()
                expect(state.contacts[1].visible).to.beFalse()
                lib().Think(state, { params = params() }, 13.5)
                expect(state.memory[ent]).to.beNil()
                expect(#state.contacts).to.equal(0)
            end
        },
        {
            name = "Memory: an invalid entity is dropped and a newer contact is not overwritten by an older one",
            func = function()
                local memory = {}
                lib().Remember(memory, "e", { pos = Vector(1, 0, 0), time = 10, source = "sight" })
                lib().Remember(memory, "e", { pos = Vector(9, 9, 9), time = 5, source = "sound" })
                expect(memory["e"].pos).to.equal(Vector(1, 0, 0))
                expect(lib().Decay(memory, 11, 12, function() return false end)).to.equal(1)
            end
        },
        {
            name = "Search: the plan yields 5 points around the last known position",
            func = function()
                local contact = { ent = "e", pos = Vector(1000, 1000, 0), vel = Vector(200, 0, 0), time = 0,
                    visible = false, source = "sight" }
                local plan = lib().SearchPlan(contact)
                expect(#plan).to.equal(5)
                expect(plan[1]).to.equal(contact.pos)
                expect(plan[2].x > plan[1].x).to.beTrue() -- ahead along the velocity
                expect(plan[5].x > plan[2].x).to.beTrue() -- far ahead
                expect(plan[3].y ~= plan[4].y).to.beTrue() -- left and right differ
                expect(plan[3].x).to.equal(plan[1].x)
            end
        },
        {
            name = "Search: a standing target uses the facing, a projection moves the points, a failed one keeps them",
            func = function()
                local contact = { ent = "e", pos = Vector(0, 0, 0), vel = Vector(0, 0, 0), time = 0, visible = false,
                    source = "sound" }
                local plan = lib().SearchPlan(contact, { facing = Vector(0, 1, 0) })
                expect(#plan).to.equal(5)
                expect(plan[2].y > 0).to.beTrue()
                local projected = lib().SearchPlan(contact, { project = function(p) return p + Vector(0, 0, 7) end })
                expect(projected[1].z).to.equal(7)
                local kept = lib().SearchPlan(contact, { project = function() return nil end })
                expect(#kept).to.equal(5)
                expect(kept[1]).to.equal(contact.pos)
            end
        },
        {
            name = "Damage: damage reveals the attacker's direction",
            func = function()
                local stim = lib().DamageStimulus(Vector(0, 0, 64), "attacker", Vector(0, 300, 64))
                expect(stim.dir).to.equal(Vector(0, 1, 0))
                expect(stim.pos).to.equal(Vector(0, 300, 64))
                local far = lib().DamageStimulus(Vector(0, 0, 64), "attacker", Vector(3000, 0, 64))
                expect(far.dir).to.equal(Vector(1, 0, 0))
                expect(far.pos.x).to.equal(800) -- direction and a bounded distance, not the exact far position
                local state = lib().NewState()
                lib().AddStimulus(state, "damage", stim)
                local contact = must(state.memory["attacker"])
                expect(contact.source).to.equal("damage")
                expect(contact.dir).to.equal(Vector(0, 1, 0))
            end
        },
        {
            name = "Hearing: the range is respected, there is no map-wide hearing",
            func = function()
                local ear = Vector(0, 0, 0)
                expect(lib().CanHear("gunfire", ear, Vector(2000, 0, 0))).to.beTrue()
                expect(lib().CanHear("gunfire", ear, Vector(2600, 0, 0))).to.beFalse()
                expect(lib().CanHear("gunfire", ear, Vector(30000, 0, 0))).to.beFalse()
                expect(lib().CanHear("gunfire_suppressed", ear, Vector(600, 0, 0))).to.beFalse()
                expect(lib().CanHear("gunfire_suppressed", ear, Vector(300, 0, 0))).to.beTrue()
                expect(lib().CanHear("footstep", ear, Vector(500, 0, 0))).to.beFalse()
                expect(lib().CanHear("explosion", ear, Vector(3000, 0, 0))).to.beTrue()
                expect(lib().CanHear("unknown_kind", ear, Vector(1, 0, 0))).to.beFalse()
                expect(lib().HearingRange("unknown_kind")).to.equal(0)
            end
        },
        {
            name = "Hearing: only listeners within the range get the sound, never its own source, with an error",
            func = function()
                local near, far, own = lib().NewState(), lib().NewState(), lib().NewState()
                ---@type PW.BotListener[]
                local ears = {
                    { key = "near", state = near, ear = Vector(1000, 0, 0) },
                    { key = "far", state = far, ear = Vector(9000, 0, 0) },
                    { key = "shooter", state = own, ear = Vector(0, 0, 0) },
                }
                local heard = lib().HearSound(ears, "gunfire", Vector(0, 0, 0), "shooter")
                expect(heard).to.equal(1)
                expect(near.memory["shooter"]).to.exist()
                expect(far.memory["shooter"]).to.beNil()
                expect(own.memory["shooter"]).to.beNil()
                expect(near.memory["shooter"].source).to.equal("gunfire")
                local jittered = lib().HeardPosition(Vector(1000, 0, 0), Vector(0, 0, 0), function() return 1 end)
                expect(jittered ~= Vector(1000, 0, 0)).to.beTrue()
                expect(jittered:Distance(Vector(1000, 0, 0)) <= 100.01).to.beTrue() -- 10 percent of the distance
            end
        },
        {
            name = "Stimulus: PW.Bot.AddStimulus puts the stimulus into the memory of the bot",
            func = function()
                local bot = "stim_bot"
                local state = registered(bot)
                local fed = botApi().AddStimulus(bot, "radar", { ent = "enemy", pos = Vector(10, 20, 30), time = 50 })
                expect(fed).to.equal(1)
                local contact = must(state.memory["enemy"])
                expect(contact.pos).to.equal(Vector(10, 20, 30))
                expect(contact.source).to.equal("radar")
                expect(contact.visible).to.beFalse()
                expect(contact.time).to.equal(50)
                local all = botApi().AddStimulus(bot, { kind = "uav", ent = "other", pos = Vector(1, 1, 1), time = 51 })
                expect(all).to.equal(1)
                expect(state.memory["other"].source).to.equal("uav")
                lib().States[bot] = nil
            end
        },
        {
            name = "Stimulus: a team stimulus reaches every bot of the team, tolerates no bots and an invalid bot",
            func = function()
                local a, b, c = registered("team_a"), registered("team_b"), registered("team_c")
                a.team, b.team, c.team = 7, 7, 8
                local fed = botApi().AddStimulus(7, "radar", { ent = "enemy", pos = Vector(1, 2, 3), time = 5 })
                expect(fed).to.equal(2)
                expect(a.memory["enemy"]).to.exist()
                expect(b.memory["enemy"]).to.exist()
                expect(c.memory["enemy"]).to.beNil()
                expect(botApi().AddStimulus(99, "radar", { ent = "enemy", pos = Vector(1, 2, 3) })).to.equal(0)
                expect(botApi().AddStimulus("nobody", "radar", { ent = "enemy", pos = Vector(1, 2, 3) })).to.equal(0)
                expect(botApi().AddStimulus(nil, "radar", nil)).to.equal(0)
                expect(botApi().AddStimulus(7, "radar", { pos = Vector(1, 2, 3) })).to.equal(0) -- no enemy
                lib().States["team_a"], lib().States["team_b"], lib().States["team_c"] = nil, nil, nil
            end
        },
        {
            name = "Sharing: a teammate's sighting arrives after the share delay, within the radius, as a contact",
            func = function()
                local sender, near, far = lib().NewState(), lib().NewState(), lib().NewState()
                local p = params() -- share_delay 1.5, share_radius 1200
                ---@type PW.BotMate[]
                local mates = {
                    { state = sender, team = 1, pos = Vector(0, 0, 0), params = p },
                    { state = near, team = 1, pos = Vector(500, 0, 0), params = p },
                    { state = far, team = 1, pos = Vector(5000, 0, 0), params = p },
                }
                local sighting = { ent = "enemy", pos = Vector(100, 0, 0), vel = Vector(0, 0, 0), time = 10 }
                local sent = lib().Share({ state = sender, team = 1, pos = Vector(0, 0, 0) }, mates, sighting, 10)
                expect(sent).to.equal(1)
                lib().Think(near, { params = p }, 11)
                expect(near.memory["enemy"]).to.beNil()
                lib().Think(near, { params = p }, 11.6)
                local shared = must(near.memory["enemy"])
                expect(shared.source).to.equal("shared")
                expect(shared.visible).to.beFalse() -- the receiver still has to see it itself
                expect(far.pending[1]).to.beNil()
            end
        },
        {
            name = "Think: contacts list the seen first, then the newest, and an unseen contact is not visible",
            func = function()
                local state = lib().NewState()
                lib().AddStimulus(state, "sound", { ent = "old", pos = Vector(1, 0, 0), time = 1 })
                lib().AddStimulus(state, "sound", { ent = "newer", pos = Vector(2, 0, 0), time = 2 })
                lib().Think(state, { params = params(), seen = seenAt("viewed", Vector(3, 0, 0)) }, 2)
                lib().Think(state, { params = params(), seen = seenAt("viewed", Vector(3, 0, 0)) }, 2.5)
                expect(state.contacts[1].ent).to.equal("viewed")
                expect(state.contacts[1].visible).to.beTrue()
                expect(state.contacts[2].ent).to.equal("newer")
                expect(state.contacts[3].ent).to.equal("old")
            end
        },
    }
}
