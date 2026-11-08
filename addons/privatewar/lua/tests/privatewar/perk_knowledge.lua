-- Deliberate disclosure and ordinary hearing are separate; no perk may erase legitimate memory.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "approved knowledge consumer is missing")
    return value
end

---@param lib table
---@param name string
---@return fun(...: any): any
local function api(lib, name)
    local fn = rawget(lib, name)
    assert(isfunction(fn), "knowledge API missing: " .. name)
    return fn
end

---@param index integer
---@param bot boolean
---@return Player
local function participant(index, bot)
    ---@type table<string, boolean>
    local nw = {}
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return bot end, Alive = function() return true end,
        EntIndex = function() return index end, Team = function() return index end,
        IsSprinting = function() return true end, GetVelocity = function() return Vector(200, 0, 0) end,
        GetSliding = function() return false end,
        GetPos = function() return Vector(index, 0, 0) end,
        GetNW2Bool = function(_, key, default) if nw[key] == nil then return default end return nw[key] end,
        SetNW2Bool = function(_, key, value) nw[key] = value end
    } --[[@as Player]]
end

---@param ply Player
---@param id string
local function equip(ply, id)
    must(must(PW.Perks).Refresh)(ply, { perk3 = id })
end

return {
    groupName = "PW perk knowledge boundaries",
    beforeEach = function(state)
        state.perks, state.reveal, state.mode = PW._Perks, PW._Reveal, PW.ActiveMode
        state.players = {}
        PW.ActiveMode = nil
        PW._Perks = must(must(PW.Perks)._NewStore)({ send = function() end })
    end,
    afterEach = function(state)
        hook.Remove("PW_CanReveal", "PW_Test_CanReveal")
        if PW.Perks ~= nil then
            for ply in pairs(must(PW._Perks).players) do must(PW.Perks._Clear)(ply) end
        end
        PW._Perks, PW._Reveal, PW.ActiveMode = state.perks, state.reveal, state.mode
    end,
    cases = {
        {
            name = "Ghost: filter runs before positions human packets and bot stimuli for every reveal source",
            func = function()
                local viewer, hidden, visible = participant(1, false), participant(2, true), participant(3, false)
                equip(hidden, "ghost")
                rawset(hidden, "GetPos", function() error("concealed position must never be read") end)
                ---@type PW.RevealBlip[][]
                local sent = {}
                ---@type Player[]
                local stimuli = {}
                local streaks = must(PW.Streaks)
                PW._Reveal = streaks._NewRevealStore({
                    members = function() return { viewer } end,
                    isEnemy = function(a, b) return a ~= b end,
                    send = function(_, blips) sent[#sent + 1] = blips end,
                    stimulus = function(_, target) stimuli[#stimuli + 1] = target end
                })
                for _, source in ipairs({ "uav", "sensor", "scan", "retaliation" }) do
                    local sourceOwner = participant(10 + #source, true)
                    expect(must(PW.Reveal)(viewer, { hidden, visible }, 1.5, sourceOwner)).to.equal(1)
                end
                expect(#sent).to.equal(4)
                for _, blips in ipairs(sent) do
                    expect(#blips).to.equal(1)
                    expect(blips[1].index).to.equal(visible:EntIndex())
                end
                expect(stimuli).to.deepEqual({ visible, visible, visible, visible })
            end
        },
        {
            name = "Ghost: target veto applies to human and bot owners while CUAV remains an independent filter",
            func = function()
                local viewer, target = participant(1, false), participant(2, true)
                local sent, heard = 0, 0
                local streaks = must(PW.Streaks)
                PW._Reveal = streaks._NewRevealStore({
                    members = function() return { viewer } end,
                    isEnemy = function(a, b) return a ~= b end,
                    send = function() sent = sent + 1 end,
                    stimulus = function() heard = heard + 1 end,
                    clock = function() return 10 end
                })
                hook.Add("PW_CanReveal", "PW_Test_CanReveal", function(_, candidate)
                    if candidate == target then return false end
                end)
                expect(must(PW.Reveal)(viewer, { target }, 1.5)).to.equal(0)
                expect({ sent, heard }).to.deepEqual({ 0, 0 })
                hook.Remove("PW_CanReveal", "PW_Test_CanReveal")
                must(PW._Reveal).jams = { { owner = target, ends = 20 } }
                expect(must(PW.Reveal)(viewer, { target }, 1.5)).to.equal(0)
                expect({ sent, heard }).to.deepEqual({ 0, 0 })
            end
        },
        {
            name = "Quiet steps: stock footsteps and matching bot hearing mute equally without muting gunfire"
                .. " or memory",
            func = function()
                local perks, perception = must(PW.Perks), PW.BotPerception
                local audible = api(perks, "FootstepsAudible")
                for _, bot in ipairs({ false, true }) do
                    local source, listener = participant(2, bot), participant(1, true)
                    local memory = perception.NewState()
                    perception.AddStimulus(memory, "sight", { ent = source, pos = Vector(2, 0, 0), time = 1 })
                    local known = memory.memory[source]
                    equip(source, "quiet_steps")
                    expect(audible(source)).to.beFalse()
                    expect(source:GetNW2Bool("pw_silent_steps", false)).to.beTrue()
                    expect(hook.Run("PlayerFootstep", source, Vector(), 0, "test", 1, nil)).to.beTrue()
                    local ears = { { key = listener, state = memory, ear = Vector() } }
                    expect(perception.HearSound(ears, "footstep", Vector(2, 0, 0), source)).to.equal(0)
                    expect(memory.memory[source]).to.equal(known)
                    expect(perception.HearSound(ears, "gunfire", Vector(2, 0, 0), source)).to.equal(1)
                    must(perks._Clear)(source)
                    expect(audible(source)).to.beTrue()
                    expect(perception.HearSound(ears, "footstep", Vector(2, 0, 0), source)).to.equal(1)
                end
            end
        },
        {
            name = "Quiet steps: direct public footstep stimuli obey same contract independent of hook ordering",
            func = function()
                local source, listener = participant(2, false), participant(1, true)
                local perception = PW.BotPerception
                local old = perception.States[listener]
                local memory = perception.NewState()
                perception.States[listener] = memory
                local ok, err = pcall(function()
                    equip(source, "quiet_steps")
                    expect(perception.Dispatch(listener, "footstep", { ent = source, pos = Vector(2, 0, 0) }))
                        .to.equal(0)
                    expect(perception.Dispatch(listener, "damage", { ent = source, pos = Vector(2, 0, 0) })).to.equal(1)
                    expect(memory.memory[source].source).to.equal("damage")
                end)
                perception.States[listener] = old
                if not ok then error(err, 0) end
            end
        },
        {
            name = "Retaliation: enemy living direct weapon current LOS and exact five second cooldown are mandatory",
            func = function()
                local eligible = api(must(PW.Perks), "_RetaliationEligible")
                local facts = { now = 10, nextAt = 10, enemy = true, living = true, direct = true, los = true }
                expect(eligible(facts)).to.beTrue()
                for _, key in ipairs({ "enemy", "living", "direct", "los" }) do
                    local bad = table.Copy(facts) --[[@as table<string, any>]]
                    bad[key] = false
                    expect(eligible(bad)).to.beFalse()
                end
                facts.nextAt = 10.001
                expect(eligible(facts)).to.beFalse()
                facts.now = 15
                expect(eligible(facts)).to.beTrue()
            end
        }
    }
}
