-- Actual player consumers: baseline-relative movement/falls and pre-application flash impairment.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "approved player effect consumer is missing")
    return value
end

---@param lib table
---@param name string
---@return fun(...: any): any
local function api(lib, name)
    local fn = rawget(lib, name)
    assert(isfunction(fn), "player effect API missing: " .. name)
    return fn
end

---@param bot boolean
---@return Player, table<string, any>
local function participant(bot)
    ---@type table<string, boolean>
    local nw = {}
    ---@type table<string, any>
    local d = { hp = 80, max = 100, walk = 200, run = 400, jump = 200, alive = true, dsp = 0 }
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return bot end, Alive = function() return d.alive end,
        Health = function() return d.hp end, GetMaxHealth = function() return d.max end,
        SetHealth = function(_, n) d.hp = n end, SetMaxHealth = function(_, n) d.max = n end,
        GetWalkSpeed = function() return d.walk end, GetRunSpeed = function() return d.run end,
        SetWalkSpeed = function(_, n) d.walk = n end, SetRunSpeed = function(_, n) d.run = n end,
        GetJumpPower = function() return d.jump end,
        SetNW2Bool = function(_, key, value) nw[key] = value end,
        SetDSP = function(_, value) d.dsp = value end
    } --[[@as Player]], d
end

---@param ply Player
---@param id string?
local function equip(ply, id)
    must(must(PW.Perks).Refresh)(ply, id ~= nil and { perk1 = id } or {})
end

---@param value number
---@param expected number
---@return boolean
local function close(value, expected) return math.abs(value - expected) < 1e-6 end

---@param body fun(packets: { owner: Player, value: integer, bits: integer }[])
local function withBlindPackets(body)
    local start, write, send = net.Start, net.WriteUInt, net.Send
    ---@type { owner: Player, value: integer, bits: integer }[]
    local packets = {}
    local value, bits = 0, 0
    rawset(net, "Start", function(name) assert(name == "pw_blind", "unexpected flash message") end)
    rawset(net, "WriteUInt", function(n, width) value, bits = n, width end)
    rawset(net, "Send", function(owner)
        packets[#packets + 1] = { owner = owner, value = value, bits = bits }
    end)
    local ok, err = pcall(body, packets)
    rawset(net, "Start", start)
    rawset(net, "WriteUInt", write)
    rawset(net, "Send", send)
    if not ok then error(err, 0) end
end

return {
    groupName = "PW approved perk player effects",
    beforeEach = function(state)
        state.perks, state.mode = PW._Perks, PW.ActiveMode
        state.players = {} --[[@as Player[] ]]
        PW.ActiveMode = nil
        PW._Perks = must(must(PW.Perks)._NewStore)({ send = function() end })
    end,
    afterEach = function(state)
        must(PW.Modules)._Enable("throwables")
        hook.Remove("PW_FallDamageBaseline", "PW_Test_FallBaseline")
        hook.Remove("PW_Blinded", "PW_Test_Blind")
        for ply in pairs(must(PW._Perks).players) do must(must(PW.Perks)._Clear)(ply) end
        for _, ply in ipairs(state.players --[[@as Player[] ]]) do must(PW.PlayerOverrides).Release(ply) end
        PW._Perks, PW.ActiveMode = state.perks, state.mode
    end,
    cases = {
        {
            name = "Flash stacking: a weaker simultaneous flash never erases stronger remaining ordinary impairment",
            func = function()
                local lib = must(PW.Throwables)
                withBlindPackets(function()
                    for _, bot in ipairs({ false, true }) do
                        local ply = participant(bot)
                        lib.Blind(ply, 1)
                        lib.Blind(ply, 0.1)
                        expect(api(lib, "Impairment")(ply, CurTime() + 1) > 0.5).to.beTrue()
                        api(lib, "ClearBlind")(ply)
                    end
                end)
            end
        },
        {
            name = "Fleet Foot: ordinary walk run use 1.10 baseline once equally for humans and bots without healing",
            func = function(state)
                for _, bot in ipairs({ false, true }) do
                    local ply, d = participant(bot)
                    local players = state.players --[[@as Player[] ]]
                    players[#players + 1] = ply
                    PW.Call(must(PW.Modules.Get("player_overrides")), "PW_PlayerSpawned", ply)
                    equip(ply, "fleet_foot")
                    expect(close(d.walk, 220) and close(d.run, 440)).to.beTrue()
                    expect({ d.hp, d.max, d.jump }).to.deepEqual({ 80, 100, 200 })
                    for _ = 1, 3 do must(must(PW.Perks)._Recompute)(ply) end
                    expect(close(d.walk, 220) and close(d.run, 440)).to.beTrue()
                    equip(ply, nil)
                    expect({ d.hp, d.walk, d.run, d.jump }).to.deepEqual({ 80, 200, 400, 200 })
                end
            end
        },
        {
            name = "Fleet Foot: composition preserves Infection 400 HP and 1.15 role speed without health refill",
            func = function(state)
                PW.ActiveMode = { PW_PlayerOverrides = function()
                    return { maxHealth = 400, spawnHealth = 400, walkSpeedMult = 1.15, runSpeedMult = 1.15 }
                end }
                for _, bot in ipairs({ false, true }) do
                    local ply, d = participant(bot)
                    local players = state.players --[[@as Player[] ]]
                    players[#players + 1] = ply
                    PW.Call(must(PW.Modules.Get("player_overrides")), "PW_PlayerSpawned", ply)
                    expect(d.hp).to.equal(400)
                    d.hp = 173
                    equip(ply, "fleet_foot")
                    expect(close(d.walk, 253) and close(d.run, 506)).to.beTrue()
                    must(PW.PlayerOverrides).Refresh(ply)
                    must(must(PW.Perks)._Recompute)(ply)
                    expect({ d.hp, d.max, d.jump }).to.deepEqual({ 173, 400, 200 })
                    expect(close(d.walk, 253) and close(d.run, 506)).to.beTrue()
                    must(PW.Perks).Revoke(ply)
                    expect(close(d.walk, 230) and close(d.run, 460)).to.beTrue()
                    expect(d.hp).to.equal(173)
                    PW.ActiveMode = nil
                    must(PW.PlayerOverrides).Refresh(ply)
                    expect({ d.hp, d.max, d.walk, d.run }).to.deepEqual({ 100, 100, 200, 400 })
                    PW.ActiveMode = { PW_PlayerOverrides = function()
                        return { maxHealth = 400, spawnHealth = 400, walkSpeedMult = 1.15, runSpeedMult = 1.15 }
                    end }
                end
            end
        },
        {
            name = "Soft Landing: ordinary fall baseline is halved once with no physics or navigation mutation",
            func = function()
                local calls = 0
                hook.Add("PW_FallDamageBaseline", "PW_Test_FallBaseline", function()
                    calls = calls + 1
                    return 37
                end)
                for _, bot in ipairs({ false, true }) do
                    local ply = participant(bot)
                    equip(ply, "soft_landing")
                    expect(hook.Run("GetFallDamage", ply, 900)).to.equal(18.5)
                    must(must(PW.Perks)._Recompute)(ply)
                    expect(hook.Run("GetFallDamage", ply, 900)).to.equal(18.5)
                    expect(must(PW.Stat)(ply, "fall_damage", 0)).to.equal(0)
                end
                expect(calls).to.equal(4)
            end
        },
        {
            name = "Flash Guard: strength is halved before duration DSP notification and identical bot impairment",
            func = function(state)
                local throwables = must(PW.Throwables)
                ---@type { ply: Player, strength: number, seconds: number }[]
                local events = {}
                hook.Add("PW_Blinded", "PW_Test_Blind", function(ply, strength, seconds)
                    events[#events + 1] = { ply = ply, strength = strength, seconds = seconds }
                end)
                withBlindPackets(function(packets)
                    for _, bot in ipairs({ false, true }) do
                        local ordinary = participant(bot)
                        local resilient = participant(bot)
                        local players = state.players --[[@as Player[] ]]
                        players[#players + 1] = ordinary
                        players[#players + 1] = resilient
                        equip(resilient, "flash_guard")
                        expect(throwables.Blind(ordinary, 1)).to.beTrue()
                        expect(throwables.Blind(resilient, 1)).to.beTrue()
                        expect(api(throwables, "Impairment")(ordinary) > 0).to.beTrue()
                        expect(api(throwables, "Impairment")(resilient) > 0).to.beTrue()
                        expect(api(throwables, "Impairment")(resilient, CurTime() + 2.1)).to.equal(0)
                        expect(api(throwables, "Impairment")(ordinary, CurTime() + 2.1) > 0).to.beTrue()
                    end
                    expect(#events).to.equal(4)
                    expect(close(events[1].strength, 1)).to.beTrue()
                    expect(math.abs(events[2].strength - 0.5) <= 1 / 255).to.beTrue()
                    expect(events[1].strength).to.equal(events[3].strength)
                    expect(events[2].strength).to.equal(events[4].strength)
                    expect(events[1].seconds).to.equal(events[3].seconds)
                    expect(events[2].seconds).to.equal(events[4].seconds)
                    expect(close(events[1].seconds, throwables._BlindTime(events[1].strength))).to.beTrue()
                    expect(close(events[2].seconds, throwables._BlindTime(events[2].strength))).to.beTrue()
                    expect(math.abs(events[2].seconds / events[1].seconds - 0.5) <= 1 / 255).to.beTrue()
                    expect(#packets).to.equal(2)
                    for i, packet in ipairs(packets) do
                        expect(packet.bits).to.equal(8)
                        expect(packet.value).to.equal(throwables._EncodeStrength(events[i].strength))
                        expect(packet.owner).to.equal(events[i].ply)
                    end
                end)
            end
        },
        {
            name = "Ordinary flash: bot sight and fire consume status without deleting memory or changing difficulty",
            func = function()
                local throwables = must(PW.Throwables)
                local bot = participant(true)
                throwables.Blind(bot, 1)
                local perception = PW.BotPerception
                local sight = api(perception, "_FlashCanSee")
                local fire = api(must(PW.BotAim), "_FlashCanFire")
                expect(sight(bot, CurTime())).to.beFalse()
                expect(fire(bot, CurTime())).to.beFalse()
                expect(sight(bot, CurTime() + 4.1)).to.beTrue()
                expect(fire(bot, CurTime() + 4.1)).to.beTrue()
                local params = must(PW.BotAim).ParamsFor(nil, "regular")
                local before = table.Copy(params)
                fire(bot, CurTime())
                expect(params).to.deepEqual(before)
            end
        },
        {
            name = "Flash lifecycle: death clears ordinary impairment and DSP",
            func = function()
                local throwables = must(PW.Throwables)
                local ply, d = participant(true)
                throwables.Blind(ply, 1)
                expect(api(throwables, "Impairment")(ply) > 0).to.beTrue()
                d.alive = false
                hook.Run("PostPlayerDeath", ply)
                expect(api(throwables, "Impairment")(ply)).to.equal(0)
                expect(d.dsp).to.equal(0)
            end
        },
        {
            name = "Flash lifecycle: module disable clears ordinary status and reenable does not restore it",
            func = function()
                local throwables = must(PW.Throwables)
                local ply = participant(true)
                throwables.Blind(ply, 1)
                expect(api(throwables, "Impairment")(ply) > 0).to.beTrue()
                must(PW.Modules)._Disable("throwables", "test disable")
                expect(api(throwables, "Impairment")(ply)).to.equal(0)
                must(PW.Modules)._Enable("throwables")
                expect(api(throwables, "Impairment")(ply)).to.equal(0)
            end
        }
    }
}
