-- Persistence must not depend on PostPlayerDeath listener order. Disable cleanup is synchronous.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "approved lifecycle consumer is missing")
    return value
end

---@return Player
local function participant()
    ---@type table<string, boolean>
    local nw = {}
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        Alive = function() return false end,
        SetNW2Bool = function(_, key, value) nw[key] = value end,
        GetNW2Bool = function(_, key, default) if nw[key] == nil then return default end return nw[key] end
    } --[[@as Player]]
end

---@param ply Player
---@param id string
local function equip(ply, id)
    must(must(PW.Perks).Refresh)(ply, { perk3 = id })
end

return {
    groupName = "PW approved perk lifecycle",
    beforeEach = function(state)
        state.perks, state.streaks, state.mode = PW._Perks, PW._Streaks, PW.ActiveMode
        PW.ActiveMode = nil
        PW._Perks = must(must(PW.Perks)._NewStore)({ send = function() end })
        PW._Streaks = must(PW.Streaks)._NewStore({
            phase = function() return "LIVE" end, publish = function() end,
            resolve = function() return { streaks = { "uav" } } end,
            setting = function(key) if key == "earn" then return "kills" end return false end
        })
    end,
    afterEach = function(state)
        must(PW.Registries.perks)._Enable("quiet_steps")
        must(PW.Modules)._Enable("perks")
        for ply in pairs(must(PW._Perks).players) do must(must(PW.Perks)._Clear)(ply) end
        PW._Perks, PW._Streaks, PW.ActiveMode = state.perks, state.streaks, state.mode
    end,
    cases = {
        {
            name = "Continuity: both death listener orders preserve progress and unused inventory deterministically",
            func = function()
                local perks, streaks = must(PW.Perks), must(PW.Streaks)
                for _, perksFirst in ipairs({ false, true }) do
                    local ply = participant()
                    equip(ply, "continuity")
                    must(PW._Streaks).players[ply] = { progress = 3, inventory = { "uav" },
                        set = { { id = "uav", cost = 4 } } }
                    if perksFirst then
                        must(perks._OnDeath)(ply)
                        streaks._OnDeath(ply)
                    else
                        streaks._OnDeath(ply)
                        must(perks._OnDeath)(ply)
                    end
                    expect(streaks.Progress(ply)).to.equal(3)
                    expect(streaks.Inventory(ply)).to.deepEqual({ "uav" })
                    expect(perks.Get(ply)).to.deepEqual({})
                    streaks._OnDeath(ply)
                    expect(streaks.Progress(ply)).to.equal(3)
                end
            end
        },
        {
            name = "Continuity: no discounted looped or chained earnings and no stale persistence"
                .. " on next ordinary life",
            func = function()
                local perks, streaks = must(PW.Perks), must(PW.Streaks)
                local ply = participant()
                equip(ply, "continuity")
                must(PW._Streaks).players[ply] = { progress = 3, inventory = {}, set = { { id = "uav", cost = 4 } } }
                streaks._OnDeath(ply)
                must(perks._OnDeath)(ply)
                expect(streaks._OnScore(ply, "kill", 100)).to.deepEqual({ "uav" })
                expect(streaks._OnScore(ply, "kill", 100)).to.deepEqual({})
                expect(streaks.Inventory(ply)).to.deepEqual({ "uav" })
                ---@type string[]?
                local chained
                streaks.StreakDamage(function() chained = streaks._OnScore(ply, "kill", 100) end)
                expect(chained).to.deepEqual({})
                expect(streaks.Progress(ply)).to.equal(5)
                streaks._OnSpawn(ply)
                equip(ply, "adrenaline")
                must(perks._OnDeath)(ply)
                streaks._OnDeath(ply)
                expect(streaks.Progress(ply)).to.equal(0)
                expect(streaks.Inventory(ply)).to.deepEqual({ "uav" })
            end
        },
        {
            name = "Lifecycle: content disable clears owned hooks cache and replicated footsteps"
                .. " without waiting for death",
            func = function()
                local ply = participant()
                equip(ply, "quiet_steps")
                expect(ply:GetNW2Bool("pw_silent_steps", false)).to.beTrue()
                must(PW.Registries.perks)._Disable("quiet_steps", "test disable")
                expect(must(PW.Perks).Get(ply)).to.deepEqual({})
                expect(ply:GetNW2Bool("pw_silent_steps", false)).to.beFalse()
                expect(must(PW.Stat)(ply, "move_speed", 200)).to.equal(200)
                must(PW.Registries.perks)._Enable("quiet_steps")
                expect(must(PW.Perks).Get(ply)).to.deepEqual({})
                equip(ply, "quiet_steps")
                expect(ply:GetNW2Bool("pw_silent_steps", false)).to.beTrue()
            end
        },
        {
            name = "Lifecycle: module disable revokes all owners and reenable does not regrant previous life effects",
            func = function()
                local a, b = participant(), participant()
                equip(a, "quiet_steps")
                equip(b, "ghost")
                must(PW.Modules)._Disable("perks", "test disable")
                expect(must(PW.Perks).Get(a)).to.deepEqual({})
                expect(must(PW.Perks).Get(b)).to.deepEqual({})
                expect(a:GetNW2Bool("pw_silent_steps", false)).to.beFalse()
                must(PW.Modules)._Enable("perks")
                expect(must(PW.Perks).Get(a)).to.deepEqual({})
            end
        },
        {
            name = "Lifecycle: role revoke remains owner scoped and ordinary new loadout removes old effects",
            func = function()
                local a, b = participant(), participant()
                equip(a, "quiet_steps")
                equip(b, "quiet_steps")
                must(PW.Perks).Revoke(a)
                expect(a:GetNW2Bool("pw_silent_steps", false)).to.beFalse()
                expect(b:GetNW2Bool("pw_silent_steps", false)).to.beTrue()
                equip(b, "adrenaline")
                expect(b:GetNW2Bool("pw_silent_steps", false)).to.beFalse()
            end
        }
    }
}
