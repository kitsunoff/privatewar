-- Separate recognized sight from newer nonvisual evidence; only current legal sight may be published visible.
---@return PW.BotPerceptionLib
local function lib() return assert(PW.BotPerception) end

---@return PW.BotPerceptionState, PW.BotThinkCtx
local function fixture()
    local state = lib().NewState()
    local ctx = { params = lib().ParamsFor(nil, "regular"), random = function() return 0.5 end,
        seen = { enemy = { pos = Vector(700, -1500, -107), vel = Vector(10, 0, 0) } } }
    lib().Think(state, ctx, 10)
    lib().Think(state, ctx, 11)
    return state, ctx
end

---@type table<string, any>[]
local cases = {}
for _, kind in ipairs({ "gunfire", "damage", "shared", "radar" }) do
    cases[#cases + 1] = {
        name = "Arbitration: one-tick-newer " .. kind .. " cannot replace matured legal sight or its velocity",
        func = function()
            local state, ctx = fixture()
            lib().AddStimulus(state, kind, { ent = "enemy", pos = Vector(820, -1400, -79),
                vel = Vector(0, 99, 0), dir = Vector(0, 1, 0), time = 11.115 })
            lib().Think(state, ctx, 11.1)
            local contact = state.contacts[1]
            expect(contact.visible).to.beTrue()
            expect(contact.source).to.equal("sight")
            expect(contact.pos).to.equal(Vector(700, -1500, -107))
            expect(contact.vel).to.equal(Vector(10, 0, 0))
            expect(contact.time).to.equal(11.1)
            expect(contact.dir).to.beNil()
            expect(contact.sourceToken).to.beNil()
            -- Losing LOS immediately removes fire permission, but keeps independently timestamped evidence.
            ctx.seen = {}
            lib().Think(state, ctx, 11.2)
            expect(state.contacts[1].visible).to.beFalse()
            lib().Think(state, ctx, 11.8)
            expect(state.contacts[1].visible).to.beFalse()
        end
    }
    cases[#cases + 1] = {
        name = "Fairness: raw sight and future " .. kind .. " cannot bypass reaction delay",
        func = function()
            local _, ctx = fixture()
            local state = lib().NewState()
            lib().AddStimulus(state, kind, { ent = "enemy", pos = Vector(820, -1400, -79), time = 10.015 })
            lib().Think(state, ctx, 10)
            lib().Think(state, ctx, 10.449)
            expect(state.contacts[1].visible).to.beFalse()
            expect(state.contacts[1].source).to.equal(kind)
            lib().Think(state, ctx, 10.45)
            expect(state.contacts[1].visible).to.beTrue()
        end
    }
end

cases[#cases + 1] = {
    name = "Control: ordinary past gunfire retains recognized sight",
    func = function()
        local state, ctx = fixture()
        lib().AddStimulus(state, "gunfire", { ent = "enemy", pos = Vector(820, -1400, -79), time = 11.085 })
        lib().Think(state, ctx, 11.1)
        expect(state.contacts[1].visible).to.beTrue()
        expect(state.contacts[1].pos).to.equal(Vector(700, -1500, -107))
    end
}

cases[#cases + 1] = {
    name = "Glimpse: late recognition stays in internal memory without publishing visibility through lost LOS",
    func = function()
        local _, ctx = fixture()
        local state = lib().NewState()
        lib().Think(state, ctx, 10)
        ctx.seen = {}
        lib().Think(state, ctx, 10.1)
        lib().Think(state, ctx, 10.56)
        expect(state.memory.enemy.source).to.equal("sight")
        expect(state.memory.enemy.pos).to.equal(Vector(700, -1500, -107))
        expect(state.contacts[1].visible).to.beFalse()
    end
}

cases[#cases + 1] = {
    name = "Copies: queued and published vectors and pending sharing never alias caller evidence",
    func = function()
        local _, ctx = fixture()
        local state, mate = lib().NewState(), lib().NewState()
        lib().Think(state, ctx, 10)
        assert(ctx.seen).enemy.pos.x = 999
        assert(ctx.seen).enemy.vel.x = 888
        local fresh = lib().Think(state, ctx, 10.5)
        expect(state.contacts[1].pos.x).to.equal(700)
        expect(state.contacts[1].vel.x).to.equal(10)
        lib().Share({ state = state, team = 1, pos = Vector() }, {
            { state = mate, team = 1, pos = Vector(), params = ctx.params }
        }, fresh[1], 10.5)
        fresh[1].pos.x = 777
        fresh[1].vel.x = 666
        state.contacts[1].pos.x = 555
        lib().Think(mate, { params = ctx.params }, 12.1)
        expect(mate.contacts[1].pos.x).to.equal(700)
        expect(mate.contacts[1].vel.x).to.equal(10)
        expect(mate.contacts[1].visible).to.beFalse()
        lib().RefreshContacts(state)
        expect(state.contacts[1].pos.x).to.equal(700)
    end
}

cases[#cases + 1] = {
    name = "Evidence: sight and sound retain independent clocks and immutable fallback through radar retirement",
    func = function()
        local state, ctx = fixture()
        local token, pos, vel = {}, Vector(800, 0, 0), Vector(0, 2, 0)
        -- Keep this pure fixture's tagged radar clock within the real validity window.
        stub(_G, "CurTime").with(function() return 11.1 end)
        lib().AddStimulus(state, "gunfire", { ent = "enemy", pos = pos, vel = vel, time = 11.115 })
        lib().AddStimulus(state, "radar", { ent = "enemy", pos = Vector(900, 0, 0),
            time = 11.12, sourceToken = token, expiresAt = 13 })
        pos.x, vel.y = 999, 999
        lib().States.arbitration = state
        lib().Think(state, ctx, 11.1)
        expect(state.contacts[1].source).to.equal("sight")
        expect(state.contacts[1].sourceToken).to.beNil()
        expect(lib().RetireSource(token, 11.1)).to.equal(1)
        expect(state.contacts[1].visible).to.beTrue()
        ctx.seen = {}
        -- No more old sight can be re-recognized after the queue retention window.
        lib().Think(state, ctx, 13.2)
        expect(state.contacts[1].source).to.equal("gunfire")
        expect(state.contacts[1].time).to.equal(11.115)
        expect(state.contacts[1].pos.x).to.equal(800)
        expect(state.contacts[1].vel.y).to.equal(2)
        lib().States.arbitration = nil
    end
}

cases[#cases + 1] = {
    name = "Lifecycle: invalid targets and clear forget sight sound radar and queued recognition together",
    func = function()
        local state, ctx = fixture()
        lib().AddStimulus(state, "gunfire", { ent = "enemy", pos = Vector(900, 0, 0), time = 11.115 })
        ctx.valid = function() return false end
        lib().Think(state, ctx, 11.1)
        expect(#state.contacts).to.equal(0)
        expect(state.memory.enemy).to.beNil()
        ctx.valid = nil
        lib().Clear(state)
        lib().Think(state, ctx, 11.2)
        expect(#state.contacts).to.equal(0)
        lib().Think(state, ctx, 11.65)
        expect(state.contacts[1].visible).to.beTrue()
        lib().HideSight(state)
        lib().RefreshContacts(state)
        expect(state.contacts[1].visible).to.beFalse()
    end
}

return { groupName = "PW perception sight evidence arbitration", cases = cases }
