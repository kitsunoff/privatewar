-- Public reveal -> real bot stimulus owner -> exact-source retirement. No fake successful stimulus callback.
local key = "PW.SupportSourceLifetime"
---@type PW.RevealStore?
local previous
---@type table<any, PW.BotPerceptionState>
local oldStates
---@type PW.SupportDevice[]
local oldRecords
---@type Entity?
local entity
---@type PW.Instance?
local instance
local now, resets = 100, 0
---@type { pos: number, seconds: number }[]
local sent = {}
local position = Vector(100, 0, 0)

---@param id integer
---@return Player
local function person(id)
    return { IsValid = function() return true end, IsBot = function() return false end,
        Alive = function() return true end, Team = function() return id end, EntIndex = function() return id end,
        GetPos = function() return position end, WorldSpaceCenter = function() return position + Vector(0, 0, 32) end
    } --[[@as Player]]
end

---@return Player, Player, PW.BotPerceptionState
local function scene()
    local owner, target = person(1), person(2)
    local perception = assert(PW.BotPerception)
    local state = perception.NewState()
    perception.States[owner] = state
    PW._Reveal = assert(assert(PW.Streaks)._NewRevealStore)({ clock = function() return now end,
        members = function(viewer) return { viewer } end, players = function() return { owner, target } end,
        isEnemy = function(a, b) return a ~= b end,
        send = function(_, blips, seconds) sent[#sent + 1] = { pos = blips[1].pos.x, seconds = seconds } end,
        reset = function() resets = resets + 1 end, jamSend = function() end })
    return owner, target, state
end

---@param state PW.BotPerceptionState
local function step(state)
    local perception = assert(PW.BotPerception)
    local params = perception.ParamsFor(nil)
    params.reaction_mean, params.reaction_floor, params.reaction_jitter = 0, 0, 0
    perception.Think(state, { params = params, seen = {} }, now)
end

return {
    groupName = "PW support public reveal source lifetime",
    beforeEach = function()
        previous, oldStates, oldRecords = PW._Reveal, assert(PW.BotPerception).States, assert(PW.Devices)._Records
        assert(PW.BotPerception).States = {}
        now, resets, sent, position = 100, 0, {}, Vector(100, 0, 0)
        stub(_G, "CurTime").with(function() return now end)
    end,
    afterEach = function()
        if instance ~= nil then instance:Remove() instance = nil end
        if entity ~= nil and IsValid(entity) then entity:Remove() end
        PW._Reveal, assert(PW.BotPerception).States, assert(PW.Devices)._Records = previous, oldStates, oldRecords
        hook.Remove("PW_CanReveal", key)
        hook.Remove("PW_IsEnemy", key)
    end,
    cases = {
        {
            name = "Source lifetime: sensor removal preserves same-owner UAV CUAV and actual bot fallback",
            func = function()
                local owner, target, state = scene()
                local streaks = assert(PW.Streaks)
                assert(PW.Reveal)(owner, { target }, 3.5, owner)
                assert(streaks.Jam)(owner, 10)
                position = Vector(200, 0, 0)
                now = 101
                entity = ents.Create("base_anim")
                entity:SetPos(Vector())
                instance = PW.Instance({ OnEquip = function() end }, owner)
                local record = { owner = owner, kind = "ground_sensor", entity = entity, position = Vector(), team = 1,
                    ends = 130, instance = instance --[[@as PW.StreakInstance]],
                    pulse = now } --[[@as PW.SupportDevice]]
                assert(PW.Devices)._Records = { record }
                hook.Add("PW_IsEnemy", key, function(a, b) return a ~= b end)
                stub(player, "GetAll").returns({ owner, target })
                stub(util, "TraceLine").returns({ Fraction = 1 })
                PW.Call(assert(PW.Modules.Get("support_devices")), "Maintain", now, 0.25)
                expect(assert(state.memory[target]).pos.x).to.equal(200)
                assert(PW.Devices).Remove(record)
                expect(assert(state.memory[target]).pos.x).to.equal(100)
                expect(resets).to.equal(1)
                expect(sent[#sent]).to.deepEqual({ pos = 100, seconds = 2.5 })
                expect(assert(PW.Reveal)(target, { owner }, 3, target)).to.equal(0)
            end
        },
        {
            name = "Source lifetime: replay copies observed snapshots without refreshing hidden target positions",
            func = function()
                local owner, target = scene()
                local a, b = {}, {}
                assert(PW.Reveal)(owner, { target }, 5, owner)
                position.x = 200
                now = 101
                assert(PW.Reveal)(owner, { target }, 4, owner, a)
                position.x = 300
                assert(PW.Reveal)(owner, { target }, 6, owner, b)
                rawset(target --[[@as table]], "GetPos", function() error("retirement refreshed a hidden position") end)
                now = 102
                assert(assert(PW.Streaks).RetireRevealSource)(a)
                expect(resets).to.equal(1)
                expect(sent[#sent - 1]).to.deepEqual({ pos = 100, seconds = 3 })
                expect(sent[#sent]).to.deepEqual({ pos = 300, seconds = 5 })
            end
        },
        {
            name = "Source lifetime: nil unknown repeated and expired retirement never globally reset radar",
            func = function()
                local owner, target = scene()
                local retire = assert(assert(PW.Streaks).RetireRevealSource)
                local token, unknown = {}, {}
                retire(nil) retire(unknown)
                expect(resets).to.equal(0)
                expect(assert(PW.Reveal)(owner, { target }, 2, owner, unknown)).to.equal(1)
                assert(PW.Reveal)(owner, { target }, 2, owner, token)
                retire(token)
                expect(resets).to.equal(1)
                retire(token)
                expect(resets).to.equal(1)
                now = 103
                retire(unknown)
                expect(resets).to.equal(1)
            end
        },
        {
            name = "Source lifetime: independent radar contributors to one entity fall back through the public bot API",
            func = function()
                local owner, target, state = scene()
                local a, b = {}, {}
                local bots = assert(PW.Bot)
                expect(bots.AddStimulus(owner, "radar", { ent = target, pos = Vector(10, 0, 0),
                    sourceToken = a, expiresAt = 110 })).to.equal(1)
                now = 101
                bots.AddStimulus(owner, "radar", { ent = target, pos = Vector(20, 0, 0),
                    sourceToken = b, expiresAt = 110 })
                expect(assert(state.memory[target]).pos.x).to.equal(20)
                assert(bots.RetireStimulusSource)(b)
                expect(assert(state.memory[target]).pos.x).to.equal(10)
                assert(bots.RetireStimulusSource)(a)
                expect(state.memory[target]).to.beNil()
            end
        },
        {
            name = "Source lifetime: retirement preserves prior sight hearing damage and genuine shared evidence",
            func = function()
                local owner, target, state = scene()
                local bots = assert(PW.Bot)
                for _, kind in ipairs({ "sight", "gunfire", "damage", "shared" }) do
                    assert(PW.BotPerception).Clear(state)
                    now = 100
                    bots.AddStimulus(owner, kind, { ent = target, pos = Vector(10, 0, 0) })
                    local token = {}
                    now = 101
                    bots.AddStimulus(owner, "radar", { ent = target, pos = Vector(20, 0, 0),
                        sourceToken = token, expiresAt = 105 })
                    assert(bots.RetireStimulusSource)(token)
                    expect(assert(state.memory[target]).source).to.equal(kind)
                    expect(assert(state.memory[target]).pos.x).to.equal(10)
                end
            end
        },
        {
            name = "Source lifetime: later genuine sight supersedes radar and survives retirement",
            func = function()
                local owner, target, state = scene()
                local token = {}
                assert(PW.Reveal)(owner, { target }, 5, owner, token)
                now = 101
                local p = assert(PW.BotPerception)
                local params = p.ParamsFor(nil)
                params.reaction_mean, params.reaction_floor, params.reaction_jitter = 0, 0, 0
                local seen = { [target] = { pos = Vector(42, 0, 0), vel = Vector() } }
                p.Think(state, { params = params, seen = seen }, now)
                assert(assert(PW.Streaks).RetireRevealSource)(token)
                expect(assert(state.memory[target]).pos.x).to.equal(42)
                expect(assert(state.memory[target]).visible).to.beTrue()
                expect(assert(state.memory[target]).source).to.equal("sight")
            end
        },
        {
            name = "Source lifetime: expiry restores surviving evidence and drops radar-only contacts at equality",
            func = function()
                local owner, target, state = scene()
                local bots = assert(PW.Bot)
                bots.AddStimulus(owner, "gunfire", { ent = target, pos = Vector(10, 0, 0) })
                now = 101
                assert(PW.Reveal)(owner, { target }, 2, owner, {})
                now = 103
                step(state)
                expect(assert(state.memory[target]).source).to.equal("gunfire")
                assert(PW.BotPerception).Clear(state)
                assert(PW.Reveal)(owner, { target }, 2, owner, {})
                now = 105
                step(state)
                expect(state.memory[target]).to.beNil()
            end
        },
        {
            name = "Source lifetime: retired known tokens reject late sensor pulses and public bot re-delivery",
            func = function()
                local owner, target, state = scene()
                local token = {}
                assert(PW.Reveal)(owner, { target }, 5, owner, token)
                assert(assert(PW.Streaks).RetireRevealSource)(token)
                now = 101
                expect(assert(PW.Reveal)(owner, { target }, 5, owner, token)).to.equal(0)
                expect(assert(PW.Bot).AddStimulus(owner, "radar", { ent = target, pos = Vector(30, 0, 0),
                    sourceToken = token, expiresAt = 110 })).to.equal(0)
                expect(state.memory[target]).to.beNil()
            end
        },
        {
            name = "Source lifetime: pending and delivered radar sharing never launders retired sensor knowledge",
            func = function()
                local owner, target, state = scene()
                local p = assert(PW.BotPerception)
                local mate, second = p.NewState(), p.NewState()
                p.States[person(3)], p.States[person(4)] = mate, second
                local token = {}
                assert(PW.Reveal)(owner, { target }, 5, owner, token)
                local params = p.ParamsFor(nil)
                params.share_delay, params.share_radius = 1, 1000
                p.Share({ state = state, team = 1, pos = Vector() }, {
                    { state = mate, team = 1, pos = Vector(), params = params },
                    { state = second, team = 1, pos = Vector(), params = params }
                }, assert(state.memory[target]), now)
                now = 101
                step(mate)
                expect(assert(mate.memory[target]).pos.x).to.equal(100)
                assert(assert(PW.Streaks).RetireRevealSource)(token)
                step(second)
                expect(mate.memory[target]).to.beNil()
                expect(second.memory[target]).to.beNil()
            end
        },
        {
            name = "Source lifetime: opaque tokens use raw identity even with an equality metamethod",
            func = function()
                local owner, target, state = scene()
                local meta = { __eq = function() return true end }
                local a, b = setmetatable({}, meta), setmetatable({}, meta)
                assert(PW.Reveal)(owner, { target }, 5, owner, a)
                now, position = 101, Vector(200, 0, 0)
                assert(PW.Reveal)(owner, { target }, 5, owner, b)
                assert(assert(PW.Streaks).RetireRevealSource)(a)
                expect(assert(state.memory[target]).pos.x).to.equal(200)
                expect(sent[#sent].pos).to.equal(200)
                expect(sent[#sent].seconds).to.equal(5)
            end
        },
        {
            name = "Source lifetime: fallback copies independent observations before radar can overlay them",
            func = function()
                local owner, target, state = scene()
                local heard = Vector(10, 0, 0)
                assert(PW.Bot).AddStimulus(owner, "gunfire", { ent = target, pos = heard })
                now = 101
                local token = {}
                assert(PW.Reveal)(owner, { target }, 5, owner, token)
                heard.x = 999
                assert(assert(PW.Streaks).RetireRevealSource)(token)
                expect(assert(state.memory[target]).pos.x).to.equal(10)
            end
        },
        {
            name = "Source lifetime: ordinary flash visibility suppression survives retirement of an overlaid radar",
            func = function()
                local owner, target, state = scene()
                local token, p = {}, assert(PW.BotPerception)
                assert(PW.Reveal)(owner, { target }, 5, owner, token)
                now = 101
                local params = p.ParamsFor(nil)
                params.reaction_mean, params.reaction_floor, params.reaction_jitter = 0, 0, 0
                p.Think(state, { params = params, seen = {
                    [target] = { pos = Vector(42, 0, 0), vel = Vector() } } }, now)
                assert(p.HideSight)(state)
                assert(assert(PW.Streaks).RetireRevealSource)(token)
                expect(assert(state.memory[target]).source).to.equal("sight")
                expect(assert(state.memory[target]).visible).to.beFalse()
            end
        },
        {
            name = "Source lifetime: synchronous retirement updates public board contacts as well as memory",
            func = function()
                local owner, target, state = scene()
                local token, bots = {}, assert(PW.Bot)
                assert(PW.Reveal)(owner, { target }, 5, owner, token)
                step(state)
                local board = { contacts = state.contacts, memory = state.memory }
                local original = assert(bots.Get)
                stub(bots, "Get").with(function(who) if who == owner then return board end return original(who) end)
                expect(#board.contacts).to.equal(1)
                assert(assert(PW.Streaks).RetireRevealSource)(token)
                expect(#board.contacts).to.equal(0)
                expect(board.memory[target]).to.beNil()
            end
        },
        {
            name = "Source lifetime: legacy four-argument pulses retain independent observed bot snapshots",
            func = function()
                local owner, target, state = scene()
                assert(PW.Reveal)(owner, { target }, 10, owner)
                now, position = 101, Vector(200, 0, 0)
                assert(PW.Reveal)(owner, { target }, 1, owner)
                expect(assert(state.memory[target]).pos.x).to.equal(200)
                now = 102
                step(state)
                expect(assert(state.memory[target]).pos.x).to.equal(100)
                now = 110
                step(state)
                expect(state.memory[target]).to.beNil()
            end
        },
        {
            name = "Source lifetime: per-contact radar evidence stays capped while current contributors survive",
            func = function()
                local owner, target, state = scene()
                local first = {}
                assert(PW.Bot).AddStimulus(owner, "radar", { ent = target, pos = Vector(),
                    sourceToken = first, expiresAt = 110 })
                for i = 1, 129 do
                    now = 100 + i * 0.001
                    assert(PW.Bot).AddStimulus(owner, "radar", { ent = target, pos = Vector(i, 0, 0),
                        sourceToken = {}, expiresAt = 110 })
                end
                expect(#assert(assert(state.memory[target]).radar)).to.equal(128)
                assert(assert(PW.Bot).RetireStimulusSource)(first)
                expect(assert(state.memory[target]).pos.x).to.equal(129)
            end
        },
        {
            name = "Source lifetime: unrelated owner cleanup cannot retire an active sensor through its expired pulse",
            func = function()
                local owner, target, state = scene()
                local token = {}
                assert(PW.Reveal)(owner, { target }, 2.1, owner, token)
                now, position = 102, Vector(200, 0, 0)
                assert(PW.Reveal)(owner, { target }, 2.1, owner, token)
                now = 102.2
                assert(assert(PW.Streaks)._RemoveEffects)(person(3))
                expect(assert(state.memory[target]).pos.x).to.equal(200)
                now, position = 103, Vector(300, 0, 0)
                expect(assert(PW.Reveal)(owner, { target }, 2.1, owner, token)).to.equal(1)
                expect(assert(state.memory[target]).pos.x).to.equal(300)
            end
        },
        {
            name = "Source lifetime: malformed tagged duration refuses before disclosure and retains no immortal pulse",
            func = function()
                local owner, target, state = scene()
                local reads = 0
                rawset(target --[[@as table]], "GetPos", function() reads = reads + 1 return position end)
                for _, seconds in ipairs({ 0, -1, math.huge, 0 / 0 }) do
                    expect(assert(PW.Reveal)(owner, { target }, seconds, owner, {})).to.equal(0)
                end
                expect(reads).to.equal(0)
                expect(#sent).to.equal(0)
                expect(state.memory[target]).to.beNil()
            end
        },
        {
            name = "Source lifetime: malformed tagged bot timestamp returns refusal instead of throwing",
            func = function()
                local owner, target, state = scene()
                local ok, accepted = pcall(assert(PW.Bot).AddStimulus, owner, "radar", {
                    ent = target, pos = Vector(), sourceToken = {}, expiresAt = 105, time = "invalid"
                })
                expect(ok).to.beTrue()
                expect(accepted).to.equal(0)
                expect(state.memory[target]).to.beNil()
            end
        },
        {
            name = "Source lifetime: legacy and tokenized reveal use identical unchanged human wire",
            func = function()
                local owner, target = scene()
                PW._Reveal = assert(assert(PW.Streaks)._NewRevealStore)({ clock = function() return now end,
                    members = function() return { owner } end, isEnemy = function(a, b) return a ~= b end })
                ---@type string[]
                local wire = {}
                ---@param value number
                ---@param bits number
                local function write(value, bits) wire[#wire + 1] = tostring(value) .. ":" .. bits end
                stub(net, "Start").with(function(name) wire[#wire + 1] = name end)
                stub(net, "WriteUInt").with(write)
                stub(net, "WriteInt").with(write)
                stub(net, "Send").returns(nil)
                expect(assert(PW.Reveal)(owner, { target }, 2.1, owner)).to.equal(1)
                local legacy = table.Copy(wire)
                wire = {}
                expect(assert(PW.Reveal)(owner, { target }, 2.1, owner, {})).to.equal(1)
                expect(wire).to.deepEqual(legacy)
            end
        },
        {
            name = "Source lifetime: concealment receives real owner before positions and bot knowledge",
            func = function()
                local owner, target, state = scene()
                local token = {}
                hook.Add("PW_CanReveal", key, function(viewer, concealed, realOwner)
                    assert(viewer == owner and concealed == target and realOwner == owner)
                    return false
                end)
                rawset(target --[[@as table]], "GetPos", function() error("concealment read a hidden position") end)
                expect(assert(PW.Reveal)(owner, { target }, 5, owner, token)).to.equal(0)
                expect(state.memory[target]).to.beNil()
                expect(#sent).to.equal(0)
                expect(resets).to.equal(0)
            end
        }
    }
}
