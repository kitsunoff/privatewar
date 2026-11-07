-- Frozen public player overrides contract: thin engine fakes, no runtime implementation in this change.
local listener = "PW_Test_PlayerOverrides"

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "frozen public API is not implemented")
    return value
end

---@return PW.PlayerOverridesLib
local function lib() return must(PW.PlayerOverrides) end

---@param bot boolean
---@return Player, table<string, any>
local function participant(bot)
    local d = { hp = 80, max = 100, walk = 200, run = 400, jump = 200, alive = true, model = "ordinary" }
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return bot end, Alive = function() return d.alive end,
        Health = function() return d.hp end, GetMaxHealth = function() return d.max end,
        SetHealth = function(_, n) d.hp = n end, SetMaxHealth = function(_, n) d.max = n end,
        GetWalkSpeed = function() return d.walk end, GetRunSpeed = function() return d.run end,
        SetWalkSpeed = function(_, n) d.walk = n end, SetRunSpeed = function(_, n) d.run = n end,
        GetJumpPower = function() return d.jump end, SetJumpPower = function(_, n) d.jump = n end,
        GetModel = function() return d.model end
    } --[[@as Player]], d
end

---@return PW.PlayerOverrideProfile
local function infected()
    return { maxHealth = 400, spawnHealth = 400, walkSpeedMult = 1.15, runSpeedMult = 1.15 }
end

---@param state table<string, any>
---@param ply Player
local function remember(state, ply)
    local list = state.players --[[@as Player[] ]]
    list[#list + 1] = ply
end

return {
    groupName = "PW generic player overrides",
    beforeEach = function(state)
        state.mode = PW.ActiveMode
        state.profile = infected()
        state.players = {} --[[@as Player[] ]]
        PW.ActiveMode = { ClassName = "test_overrides", Teams = 2,
            PW_PlayerOverrides = function() return state.profile end }
    end,
    afterEach = function(state)
        hook.Remove("PW_PlayerOverrides", listener)
        if PW.PlayerOverrides ~= nil then
            for _, ply in ipairs(state.players --[[@as Player[] ]]) do PW.PlayerOverrides.Release(ply) end
        end
        PW.ActiveMode = state.mode
    end,
    cases = {
        {
            name = "Player overrides: postspawn applies 400 HP, 1.15 walk/run, unchanged jump to humans and bots",
            func = function(state)
                lib()
                for _, bot in ipairs({ false, true }) do
                    local ply, d = participant(bot)
                    remember(state, ply)
                    PW.Notify("PW_PlayerSpawned", ply)
                    expect({ d.hp, d.max, d.jump }).to.deepEqual({ 400, 400, 200 })
                    expect(math.abs(d.walk - 230) < 1e-6 and math.abs(d.run - 460) < 1e-6).to.beTrue()
                    d.hp = 275
                    expect(lib().Refresh(ply)).to.beTrue()
                    expect(lib().Refresh(ply)).to.beTrue()
                    expect(d.hp).to.equal(275)
                    expect(math.abs(d.walk - 230) < 1e-6).to.beTrue()
                end
            end
        },
        {
            name = "Player overrides: alive refresh never fills HP and release clamps down without healing",
            func = function(state)
                local ply, d = participant(false)
                remember(state, ply)
                expect(lib().Refresh(ply)).to.beTrue()
                expect(d.hp).to.equal(80)
                d.hp = 320
                expect(lib().Release(ply)).to.beTrue()
                expect({ d.hp, d.max, d.walk, d.run }).to.deepEqual({ 100, 100, 200, 400 })
                expect(lib().Refresh(ply)).to.beTrue()
                d.hp = 25
                lib().Release(ply)
                expect(d.hp).to.equal(25)
                expect(lib().Release(ply)).to.beFalse()
            end
        },
        {
            name = "Player overrides: dead release never revives and a new life captures fresh ordinary baseline",
            func = function(state)
                local ply, d = participant(true)
                remember(state, ply)
                lib()
                PW.Notify("PW_PlayerSpawned", ply)
                d.hp, d.alive = 0, false
                lib().Release(ply)
                expect(d.hp).to.equal(0)
                d.hp, d.max, d.walk, d.run, d.alive = 125, 125, 180, 360, true
                PW.Notify("PW_PlayerSpawned", ply)
                expect(d.hp).to.equal(400)
                expect(math.abs(d.walk - 207) < 1e-6).to.beTrue()
                lib().Release(ply)
                expect({ d.hp, d.max, d.walk, d.run }).to.deepEqual({ 125, 125, 180, 360 })
            end
        },
        {
            name = "Player overrides: new ordinary postspawn baseline replaces prior life without release",
            func = function(state)
                local ply, d = participant(true)
                remember(state, ply)
                lib()
                PW.Notify("PW_PlayerSpawned", ply)
                d.hp, d.max, d.walk, d.run = 100, 100, 160, 320
                PW.Notify("PW_PlayerSpawned", ply)
                expect(d.hp).to.equal(400)
                expect(math.abs(d.walk - 184) < 1e-6).to.beTrue()
                lib().Release(ply)
                expect({ d.max, d.walk, d.run }).to.deepEqual({ 100, 160, 320 })
            end
        },
        {
            name = "Player overrides: missing provider releases and malformed complete profile mutates nothing",
            func = function(state)
                local ply, d = participant(false)
                remember(state, ply)
                for _, bad in ipairs({ -1, 0, math.huge, "fast", 0 / 0 }) do
                    state.profile = { maxHealth = 400, spawnHealth = 400, walkSpeedMult = bad }
                    expect(lib().Refresh(ply)).to.beFalse()
                    expect({ d.hp, d.max, d.walk, d.run }).to.deepEqual({ 80, 100, 200, 400 })
                end
                state.profile = infected()
                lib().Refresh(ply)
                state.profile = nil
                lib().Refresh(ply)
                expect({ d.hp, d.max, d.walk, d.run }).to.deepEqual({ 80, 100, 200, 400 })
            end
        },
        {
            name = "Player overrides: abort and Infection to TDM or FFA leave no role stats",
            func = function(state)
                local provider = PW.ActiveMode
                for _, id in ipairs({ "tdm", "ffa" }) do
                    PW.ActiveMode = provider
                    local ply, d = participant(false)
                    remember(state, ply)
                    state.profile = infected()
                    lib().Refresh(ply)
                    PW.Call(must(PW.Modules.Get("player_overrides")), "PW_MatchEnd", {})
                    expect({ d.max, d.walk, d.run, d.hp }).to.deepEqual({ 100, 200, 400, 80 })
                    PW.ActiveMode = must(PW.Modes.Get(id))
                    PW.Notify("PW_PlayerSpawned", ply)
                    expect({ d.max, d.walk, d.run }).to.deepEqual({ 100, 200, 400 })
                end
            end
        }
    }
}
