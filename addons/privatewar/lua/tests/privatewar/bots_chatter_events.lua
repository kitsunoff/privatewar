-- Thin server glue with explicit engine stand-ins, not a native playback smoke test.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "chatter dependency must load")
    return value
end

---@param bot boolean
---@param sent string[]
---@return Player
local function participant(bot, sent)
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return bot end, Alive = function() return true end,
        GetNW2Bool = function() return false end, GetObserverMode = function() return OBS_MODE_NONE end,
        Nick = function() return bot and "Bot" or "Human" end,
        Say = function(_, text, teamOnly)
            assert(teamOnly == false, "chatter uses ordinary global chat")
            sent[#sent + 1] = text
        end
    } --[[@as Player]]
end

-- GLuaTest injects stub into case environments, not into this file-level helper.
---@param stubber fun(tbl: table, key: string): any
---@param phase? string
---@param enabled? boolean
---@return table<string, any>
local function setup(stubber, phase, enabled)
    local lib = must(PW.BotChatter)
    local module = must(must(PW.Registries.modules).Get("bots_chatter"))
    stubber(module, "IsValid").with(function() return true end)
    stubber(must(PW.Match), "GetPhase").with(function() return phase or "LIVE" end)
    stubber(PW, "Setting").with(function(id)
        if id == "bots_chatter.enabled" then return enabled ~= false end
        if id == "bots_chatter.chat" then return true end
        return false
    end)
    stubber(must(PW.Bot), "Get").with(function() return {} end)
    stubber(lib, "_Line").with(function(_, _, event) return event end)
    ---@param states table<any, PW.ChatterState>
    ---@param ply any
    local function identity(states, ply)
        states[ply] = states[ply] or { next = 0, speaking = 0 }
        return states[ply]
    end
    stubber(lib, "_Identity").with(identity)
    -- Separate fixture clocks also keep the production service's global limit isolated between cases.
    stubber(_G, "CurTime").with(function() return 1000000 end)
    stubber(net, "Start").with(function() end)
    stubber(net, "WriteBool").with(function() end)
    stubber(net, "Broadcast").with(function() end)
    module:PW_PhaseChange("LOBBY")
    return module
end

return {
    groupName = "PW bot chatter server events",
    afterEach = function()
        local module = must(must(PW.Registries.modules).Get("bots_chatter"))
        PW.Call(module, "PW_PhaseChange", "LOBBY")
    end,
    cases = {
        {
            name = "Chatter events: enemy kill is global bot chat, duplicate event is rate limited",
            func = function()
                local module = setup(stub)
                local sent = {}
                local attacker, victim = participant(true, sent), participant(false, {})
                stub(PW, "IsEnemy").with(function() return true end)
                module:PW_PlayerKilled(victim, attacker)
                module:PW_PlayerKilled(victim, attacker)
                expect(#sent).to.equal(1)
                expect(sent[1]).to.equal("kill")
            end
        },
        {
            name = "Chatter events: friendly kill and suicide never produce killer taunts",
            func = function()
                local module = setup(stub)
                local sent = {}
                local attacker, victim = participant(true, sent), participant(false, {})
                stub(PW, "IsEnemy").with(function() return false end)
                module:PW_PlayerKilled(victim, attacker)
                expect(#sent).to.equal(0)
                module:PW_PlayerKilled(attacker, attacker)
                expect(#sent).to.equal(1)
                expect(sent[1]).to.equal("death")
            end
        },
        {
            name = "Chatter events: disabled service cannot deliver text",
            func = function()
                local module = setup(stub, "LIVE", false)
                local sent = {}
                local attacker, victim = participant(true, sent), participant(false, {})
                stub(PW, "IsEnemy").with(function() return true end)
                module:PW_PlayerKilled(victim, attacker)
                expect(#sent).to.equal(0)
            end
        },
        {
            name = "Chatter events: round end suppresses delivery until round start",
            func = function()
                local module = setup(stub)
                local sent = {}
                local attacker, victim = participant(true, sent), participant(false, {})
                stub(PW, "IsEnemy").with(function() return true end)
                module:PW_RoundEnd()
                module:PW_PlayerKilled(victim, attacker)
                expect(#sent).to.equal(0)
                module:PW_RoundStart()
                module:PW_PlayerKilled(victim, attacker)
                expect(#sent).to.equal(1)
            end
        },
        {
            name = "Chatter events: non-LIVE service cannot deliver text",
            func = function()
                local module = setup(stub, "POSTMATCH")
                local sent = {}
                local attacker, victim = participant(true, sent), participant(false, {})
                stub(PW, "IsEnemy").with(function() return true end)
                module:PW_PlayerKilled(victim, attacker)
                expect(#sent).to.equal(0)
            end
        }
    }
}
