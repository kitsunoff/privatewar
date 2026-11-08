-- Actual public operator override and optional addon snapshot assertions. No asset/runtime success is assumed.
local listener = "PW_Test_InfectionPresentation"

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "frozen public API is not implemented")
    return value
end

---@return boolean
local function absent()
    return not file.Exists("privatewar/types/pw_infection.lua", "LUA")
        and not file.Exists("privatewar/modes/pw_infection.lua", "LUA")
end

---@param bot boolean
---@return Player, table<string, any>
local function participant(bot)
    local d = { model = "", colour = Vector(), valid = true }
    return {
        IsValid = function() return d.valid end, IsPlayer = function() return true end,
        IsBot = function() return bot end, Alive = function() return true end,
        Team = function() return 1 end,
        GetInfo = function(_, key) return key == "cl_playermodel" and "kleiner" or "1 1 1" end,
        SetModel = function(_, path) d.model = path end,
        SetPlayerColor = function(_, colour) d.colour = colour end
    } --[[@as Player]], d
end

return {
    groupName = "PW Infection presentation and generic appearance",
    beforeEach = function(state)
        state.mode, state.operators = PW.ActiveMode, PW._Operators
        local operators = must(PW.Operators)
        PW._Operators = must(operators._NewStore)({ stock = function()
            return { kleiner = "models/player/kleiner.mdl", zombie = "models/player/zombie_classic.mdl" }
        end, economy = function() return {} end, teams = function() return 0 end,
            roll = function() return 0 end, log = function() state.logged = (state.logged or 0) + 1 end })
        PW.ActiveMode = { ClassName = "test_appearance", Teams = 2 }
    end,
    afterEach = function(state)
        hook.Remove("PW_PlayerModelOverride", listener)
        PW.ActiveMode, PW._Operators = state.mode, state.operators
    end,
    cases = {
        {
            name = "Appearance: zombie override preserves saved human and bot operator choices",
            func = function()
                local operators = must(PW.Operators)
                local refresh = must(operators.Refresh)
                for _, isBot in ipairs({ false, true }) do
                    local ply, d = participant(isBot)
                    refresh(ply)
                    local ordinary = d.model
                    local choice = PW._Operators.requested[ply]
                    hook.Add("PW_PlayerModelOverride", listener, function()
                        return "models/player/zombie_classic.mdl"
                    end)
                    expect(refresh(ply)).to.beTrue()
                    expect(d.model).to.equal("models/player/zombie_classic.mdl")
                    expect(PW._Operators.requested[ply]).to.equal(choice)
                    hook.Remove("PW_PlayerModelOverride", listener)
                    refresh(ply)
                    expect(d.model).to.equal(ordinary)
                end
            end
        },
        {
            name = "Appearance: invalid missing or NPC-only override falls back without changing the operator",
            func = function(state)
                local ply, d = participant(false)
                local refresh = must(must(PW.Operators).Refresh)
                refresh(ply)
                local ordinary = d.model
                local paths = { "models/zombie/classic.mdl", "models/player/does_not_exist.mdl", "../bad.mdl" }
                for _, path in ipairs(paths) do
                    hook.Add("PW_PlayerModelOverride", listener, function() return path end)
                    refresh(ply)
                    expect(d.model).to.equal(ordinary)
                    expect(PW._Operators.requested[ply]).to.beNil()
                end
                expect((state.logged or 0) > 0).to.beTrue()
            end
        },
        {
            name = "Infection snapshot: sanitize role counts deadline and personal wins, never hidden positions",
            skip = absent,
            func = function()
                local lib = must(PW.InfectionPresentation)
                local snapshot = must(lib.Accept(nil, { revision = 1, round = 1, survivors = 2, infected = 1,
                    deadline = 120, role = "survivor", personalWins = 0,
                    enemies = { Vector(1, 2, 3) }, positions = { secret = Vector(10, 20, 30) } }))
                expect(snapshot).to.deepEqual({ revision = 1, round = 1, survivors = 2, infected = 1,
                    deadline = 120, role = "survivor", personalWins = 0 })
                expect(lib.Model(snapshot, 119).remaining).to.equal(1)
                expect(lib.Model(snapshot, 121).remaining).to.equal(0)
                expect(lib.Accept(snapshot, { revision = 0, round = 0 })).to.beNil()
                expect(lib.Accept(snapshot, { revision = 1, round = 1 })).to.beNil()
                expect(lib.Accept(snapshot, { revision = 2, round = 2, survivors = -1, infected = 1,
                    deadline = 120, role = "infected", personalWins = 1 })).to.beNil()
            end
        }
    }
}
