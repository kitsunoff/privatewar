-- Review regression: exercise actual owner-local status, not the obsolete PW._Throwables.blind layout.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "flash ownership test requires its public owner")
    return value
end

---@param bot boolean
---@return Player, { dsp: integer, calls: integer[] }
local function participant(bot)
    local d = { dsp = 17, calls = {} --[[@as integer[] ]] }
    return { IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return bot end, Alive = function() return true end,
        SetDSP = function(_, value) d.dsp = value d.calls[#d.calls + 1] = value end } --[[@as Player]], d
end

---@param body fun(packets: { ply: Player, value: integer, bits: integer }[])
local function packets(body)
    local start, write, send = net.Start, net.WriteUInt, net.Send
    ---@type { ply: Player, value: integer, bits: integer }[]
    local sent = {}
    local value, bits = 0, 0
    local flash = false
    -- Round notifications have multiple network owners; intercept only the flash protocol end to end.
    rawset(net, "Start", function(name, unreliable)
        flash = name == "pw_blind"
        if not flash then return start(name, unreliable) end
        value, bits = 0, 0
    end)
    rawset(net, "WriteUInt", function(n, width)
        if not flash then return write(n, width) end
        value, bits = n, width
    end)
    rawset(net, "Send", function(ply)
        if not flash then return send(ply) end
        sent[#sent + 1] = { ply = ply, value = value, bits = bits }
        flash = false
    end)
    local ok, err = pcall(body, sent)
    rawset(net, "Start", start)
    rawset(net, "WriteUInt", write)
    rawset(net, "Send", send)
    if not ok then error(err, 0) end
end

return {
    groupName = "PW perk flash ownership review",
    beforeEach = function(state) state.mode = PW.ActiveMode PW.ActiveMode = nil end,
    afterEach = function(state) PW.ActiveMode = state.mode end,
    cases = {
        {
            name = "Flash packet fixture: unrelated stop broadcasts and integer sends pass through without capture",
            func = function()
                ---@type table<string, any>[]
                local forwarded = {}
                stub(net, "Start").with(function(name, unreliable)
                    forwarded[#forwarded + 1] = { "start", name, unreliable }
                end)
                stub(net, "WriteBool").with(function(value)
                    forwarded[#forwarded + 1] = { "bool", value }
                end)
                stub(net, "Broadcast").with(function() forwarded[#forwarded + 1] = { "broadcast" } end)
                stub(net, "WriteUInt").with(function(value, bits)
                    forwarded[#forwarded + 1] = { "uint", value, bits }
                end)
                stub(net, "Send").with(function(ply) forwarded[#forwarded + 1] = { "send", ply } end)
                local human = participant(false)
                packets(function(sent)
                    net.Start("pw_blind")
                    net.WriteUInt(255, 8)
                    net.Send(human)
                    net.Start("pw_bot_voice_stop", true)
                    net.WriteBool(true)
                    net.Broadcast()
                    -- Mock-only packet exercises forwarding of the other two intercepted functions too.
                    net.Start("pw_test_other")
                    net.WriteUInt(7, 3)
                    net.Send(human)
                    net.Start("pw_blind")
                    net.WriteUInt(0, 8)
                    net.Send(human)
                    expect(sent).to.deepEqual({
                        { ply = human, value = 255, bits = 8 }, { ply = human, value = 0, bits = 8 }
                    })
                end)
                expect(forwarded).to.deepEqual({
                    { "start", "pw_bot_voice_stop", true }, { "bool", true }, { "broadcast" },
                    { "start", "pw_test_other" }, { "uint", 7, 3 }, { "send", human }
                })
            end
        },
        {
            name = "Client DSP ownership: expired weak overlay never resets DSP through the actual render callback",
            func = function()
                local ply, d = participant(false)
                ---@type function?
                local render
                local client = { Blinded = { strength = 0.2, at = 0 }, _BlindAlpha = function() return 0 end }
                local env = setmetatable({
                    PW = { Throwables = client, HookFor = function(_, name, callback)
                        if name == "RenderScreenspaceEffects" then render = callback end
                    end },
                    MODULE = {}, net = { Receive = function() end },
                    CurTime = function() return 10 end, LocalPlayer = function() return ply end
                }, { __index = _G })
                local code = must(file.Read("privatewar/modules/throwables/cl_init.lua", "LUA"))
                local chunk = CompileString(code, "perk_flash_client_owner_test", false)
                assert(isfunction(chunk), tostring(chunk))
                setfenv(chunk --[[@as function]], env)
                chunk()
                must(render)()
                expect(d.dsp).to.equal(17)
                expect(d.calls).to.deepEqual({})
            end
        },
        {
            name = "RoundEnd: actual human and bot flash packets DSP impairment timers and live projectile"
                .. " clear together",
            async = true,
            timeout = 5,
            func = function()
                packets(function(sent)
                    local lib = must(PW.Throwables)
                    local human, d = participant(false)
                    local bot = participant(true)
                    local projectile = lib.Throw(must(player.GetHumans()[1]), lib.EntityClass,
                        { drop = true, fuse = 10 })
                    assert(IsValid(projectile), "round cleanup test needs a real owned projectile")
                    lib.Blind(human, 1)
                    lib.Blind(bot, 1)
                    local ownedTimer = "PW.Blind." .. tostring(human)
                    local botTimer = "PW.Blind." .. tostring(bot)
                    expect(timer.Exists(ownedTimer)).to.beTrue()
                    PW.Notify("PW_RoundEnd", 1, false, {})
                    local remaining = { lib.Impairment(human), lib.Impairment(bot) }
                    local dsp, timerLeft = d.dsp, timer.Exists(ownedTimer) or timer.Exists(botTimer)
                    local zero = sent[#sent]
                    -- Entity:Remove queues native deletion; observe after a frame, before failure-safe cleanup.
                    timer.Simple(0.1, function()
                        local projectileLeft = IsValid(projectile)
                        local timerSettled = timer.Exists(ownedTimer) or timer.Exists(botTimer)
                        lib.ClearBlind(human)
                        lib.ClearBlind(bot)
                        lib._RemoveAll()
                        expect(remaining).to.deepEqual({ 0, 0 })
                        expect(dsp).to.equal(0)
                        expect(timerLeft).to.beFalse()
                        expect(timerSettled).to.beFalse()
                        expect(projectileLeft).to.beFalse()
                        expect({ zero.ply, zero.value, zero.bits }).to.deepEqual({ human, 0, 8 })
                        done()
                    end)
                end)
            end
        },
        {
            name = "DSP ownership: weak human or bot flash never resets an unrelated DSP it did not own",
            func = function()
                packets(function()
                    for _, bot in ipairs({ false, true }) do
                        local ply, d = participant(bot)
                        local lib = must(PW.Throwables)
                        lib.Blind(ply, 0.2)
                        local during = d.dsp
                        lib.ClearBlind(ply)
                        expect({ during, d.dsp }).to.deepEqual({ 17, 17 })
                        expect(d.calls).to.deepEqual({})
                    end
                end)
            end
        },
        {
            name = "DSP ownership: strong human flash retains its owned ringing across a weaker replacement"
                .. " until cleanup",
            func = function()
                packets(function()
                    local ply, d = participant(false)
                    local lib = must(PW.Throwables)
                    local clock = CurTime
                    local now = clock()
                    lib.Blind(ply, 1)
                    rawset(_G, "CurTime", function() return now + 3.8 end)
                    local ok, err = pcall(function() lib.Blind(ply, 0.2) end)
                    rawset(_G, "CurTime", clock)
                    local during = d.dsp
                    lib.ClearBlind(ply)
                    if not ok then error(err, 0) end
                    expect(during).to.equal(35)
                    expect(d.dsp).to.equal(0)
                    expect(d.calls).to.deepEqual({ 35, 0 })
                end)
            end
        }
    }
}
