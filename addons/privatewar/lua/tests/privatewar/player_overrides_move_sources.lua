---@return PW.PlayerOverridesLib
local function lib()
    return assert(PW.PlayerOverrides)
end

---@param ply Player
---@param id string
---@param value? number
local function move(ply, id, value)
    local source = assert(rawget(lib(), "MoveSource"), "MoveSource is not implemented")
    source(ply, id, value)
end

---@param sources? table<string, any>
---@return number
local function factor(sources)
    local calculate = assert(rawget(lib(), "_SpeedFactor"), "_SpeedFactor is not implemented")
    return calculate(sources)
end

---@param current number
---@param wanted number
---@return boolean
local function near(current, wanted)
    return math.abs(current - wanted) < 0.0001
end

return {
    groupName = "PW temporary movement sources",
    beforeEach = function(state)
        state.ask = PW.Ask
        state.stat = PW.Stat
        state.values = { walk = 200, run = 400, hp = 40, max = 100, healthWrites = 0 }
        local values = state.values --[[@as table<string, number>]]
        state.ply = {
            IsValid = function() return true end, IsPlayer = function() return true end,
            Alive = function() return true end, Health = function() return values.hp end,
            GetMaxHealth = function() return values.max end, GetWalkSpeed = function() return values.walk end,
            GetRunSpeed = function() return values.run end,
            SetHealth = function(_, n) values.hp, values.healthWrites = n, values.healthWrites + 1 end,
            SetMaxHealth = function(_, n) values.max = n end,
            SetWalkSpeed = function(_, n) values.walk = n end,
            SetRunSpeed = function(_, n) values.run = n end
        } --[[@as Player]]
        rawset(PW, "Ask", function(name, ply, ...)
            if name == "PW_PlayerOverrides" and ply == state.ply then return state.profile end
            return state.ask(name, ply, ...)
        end)
        rawset(PW, "Stat", function(ply, id, default)
            if ply == state.ply and id == "move_speed" then return state.speed or 1 end
            if state.stat then return state.stat(ply, id, default) end
            return default or 1
        end)
    end,
    afterEach = function(state)
        rawset(PW, "Ask", state.ask)
        rawset(PW, "Stat", state.stat)
        local module = assert(PW.Modules.Get("player_overrides"))
        local disconnected = assert(hook.GetTable().PlayerDisconnected[module])
        disconnected(module, state.ply)
    end,
    cases = {
        {
            name = "SpeedFactor: empty or nil sources give 1",
            func = function()
                expect(factor()).to.equal(1)
                expect(factor({})).to.equal(1)
            end
        },
        {
            name = "SpeedFactor: multiplies valid sources in sorted id order",
            func = function()
                -- Multiplying large factors first would overflow. Sorted order stays finite.
                expect(factor({ z = 1e200, a = 1e-200, b = 1e200 })).to.equal(1e200)
                expect(factor({ b = 3, a = 2, c = 0.5 })).to.equal(3)
            end
        },
        {
            name = "SpeedFactor: ignores non-number, nonfinite, zero and negative values",
            func = function()
                local sources = { s = "1", inf = math.huge, nan = 0 / 0, zero = 0, neg = -1, good = 1.25 }
                expect(factor(sources)).to.equal(1.25)
            end
        },
        {
            name = "MoveSource composes with role multiplier and move_speed stat relative to the ordinary baseline",
            func = function(state)
                state.profile, state.speed = { walkSpeedMult = 1.15, runSpeedMult = 1.2 }, 1.1
                move(state.ply, "stim", 1.2)
                expect(near(state.values.walk, 200 * 1.15 * 1.1 * 1.2)).to.beTrue()
                expect(near(state.values.run, 400 * 1.2 * 1.1 * 1.2)).to.beTrue()
                lib().Refresh(state.ply)
                expect(near(state.values.walk, 200 * 1.15 * 1.1 * 1.2)).to.beTrue()
            end
        },
        {
            name = "MoveSource removal restores the previous product without compounding",
            func = function(state)
                move(state.ply, "a", 1.2)
                move(state.ply, "b", 1.25)
                expect(near(state.values.walk, 300)).to.beTrue()
                expect(near(state.values.run, 600)).to.beTrue()
                move(state.ply, "b")
                expect(near(state.values.walk, 240)).to.beTrue()
                expect(near(state.values.run, 480)).to.beTrue()
            end
        },
        {
            name = "Removing the last source without profile or stat releases to the ordinary baseline",
            func = function(state)
                move(state.ply, "stim", 1.2)
                expect(near(state.values.walk, 240)).to.beTrue()
                move(state.ply, "stim")
                expect({ state.values.walk, state.values.run }).to.deepEqual({ 200, 400 })
                expect(lib().Release(state.ply)).to.beFalse()
            end
        },
        {
            name = "MoveSource refresh never heals or reapplies spawn health",
            func = function(state)
                state.profile = { maxHealth = 400, spawnHealth = 400 }
                move(state.ply, "stim", 1.2)
                move(state.ply, "stim")
                expect({ state.values.hp, state.values.max, state.values.healthWrites }).to.deepEqual({ 40, 400, 0 })
            end
        },
        {
            name = "PlayerSpawn drops move sources of the previous life",
            func = function(state)
                local module = assert(PW.Modules.Get("player_overrides"))
                local spawn = assert(hook.GetTable().PlayerSpawn[module])
                move(state.ply, "stim", 1.2)
                spawn(module, state.ply)
                expect({ state.values.walk, state.values.run }).to.deepEqual({ 200, 400 })
                state.values.walk, state.values.run = 180, 360
                PW.Call(module, "PW_PlayerSpawned", state.ply)
                expect({ state.values.walk, state.values.run }).to.deepEqual({ 180, 360 })
            end
        }
    }
}
