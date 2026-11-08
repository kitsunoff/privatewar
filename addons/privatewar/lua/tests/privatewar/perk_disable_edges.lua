-- Public entry points must not regrant disabled gameplay; failed constructor stats are not equipped.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "perk disable edge requires its public owner")
    return value
end

---@return Player
local function participant()
    return { IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return true end, Alive = function() return true end,
        SetNW2Bool = function() end, SetDSP = function() end } --[[@as Player]]
end

return {
    groupName = "PW perk disabled public entry points",
    beforeEach = function(state)
        state.perks, state.mode = PW._Perks, PW.ActiveMode
        PW.ActiveMode = nil
        PW._Perks = must(must(PW.Perks)._NewStore)({ send = function() end })
    end,
    afterEach = function(state)
        PW.Modules._Enable("perks")
        PW.Modules._Enable("throwables")
        must(PW.Perks).StatSource("pwt_disabled", nil)
        for ply in pairs(must(PW._Perks).players) do must(must(PW.Perks)._Clear)(ply) end
        PW._Perks, PW.ActiveMode = state.perks, state.mode
    end,
    cases = {
        {
            name = "Disabled perks: direct Refresh and source Recompute cannot regrant instances or cached stats",
            func = function()
                local perks, ply = must(PW.Perks), participant()
                perks.StatSource("pwt_disabled", function() return { { move_speed = 2 } } end)
                PW.Modules._Disable("perks", "test disabled public entry")
                must(perks.Refresh)(ply, { perk3 = "quiet_steps" })
                expect(perks.Get(ply)).to.deepEqual({})
                must(perks._Recompute)(ply)
                expect(must(PW.Stat)(ply, "move_speed", 200)).to.equal(200)
            end
        },
        {
            name = "Failed perk constructor: already-ended instance never contributes cached stats or equipped ids",
            func = function()
                local perks, ply = must(PW.Perks), participant()
                local def = { ClassName = "pwt_failed", Name = "Failed", Group = 1, Stats = { move_speed = 2 },
                    OnEquip = function() error("intentional failed constructor") end } --[[@as PW.Perk]]
                PW._Perks = must(perks._NewStore)({ send = function() end, lookup = function() return def end })
                must(perks.Refresh)(ply, { perk1 = "pwt_failed" })
                expect(perks.Get(ply)).to.deepEqual({})
                expect(must(PW.Stat)(ply, "move_speed", 200)).to.equal(200)
            end
        },
        {
            name = "Disabled ordinary flash: a delayed caller cannot recreate impairment after owner cleanup",
            func = function()
                local status, ply = must(PW.Throwables), participant()
                PW.Modules._Disable("throwables", "test disabled delayed flash")
                local applied = status.Blind(ply, 1)
                local impairment = status.Impairment(ply)
                status.ClearBlind(ply)
                expect(applied).to.beFalse()
                expect(impairment).to.equal(0)
            end
        }
    }
}
